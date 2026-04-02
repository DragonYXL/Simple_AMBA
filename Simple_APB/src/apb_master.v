// =============================================================================
// APB4 Master with local SRAM and control FSM
// Local SRAM uses RD_LATENCY=1 (standard synchronous read).
// FSM adds S_LOAD state to prefetch the first word before APB SETUP.
// =============================================================================

module apb_master #(
    parameter ADDR_WIDTH      = 13,
    parameter DATA_WIDTH      = 32,
    parameter LOCAL_RAM_DEPTH = 1024
) (
    input  wire                    pclk,
    input  wire                    presetn,

    // Control interface
    input  wire                    start,      // pulse to start transfer
    input  wire                    rw,         // 1=write to slave, 0=read from slave
    input  wire [ADDR_WIDTH-1:0]   apb_base,   // slave side base address
    input  wire [$clog2(LOCAL_RAM_DEPTH)-1:0] local_base, // local RAM base address
    input  wire [7:0]              length,     // number of words to transfer (1-based)
    output reg                     done,       // transfer complete pulse

    // APB4 master interface
    output reg                     psel,
    output reg                     penable,
    output reg                     pwrite,
    output reg  [ADDR_WIDTH-1:0]   paddr,
    output reg  [DATA_WIDTH-1:0]   pwdata,
    output reg  [DATA_WIDTH/8-1:0] pstrb,
    output wire [2:0]              pprot,
    input  wire [DATA_WIDTH-1:0]   prdata,
    input  wire                    pready,
    input  wire                    pslverr
);

    assign pprot = 3'b000;

    localparam RAM_ADDR_W = $clog2(LOCAL_RAM_DEPTH);

    // -------------------------------------------------------------------------
    // Local SRAM interface
    // -------------------------------------------------------------------------
    reg                    lram_en;
    reg                    lram_we;
    reg  [RAM_ADDR_W-1:0]  lram_addr;
    reg  [DATA_WIDTH-1:0]  lram_wdata;
    wire [DATA_WIDTH-1:0]  lram_rdata;
    wire                   lram_rd_valid;

    sram #(
        .ADDR_WIDTH (RAM_ADDR_W),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (LOCAL_RAM_DEPTH),
        .RD_LATENCY (1)
    ) u_local_ram (
        .clk     (pclk),
        .en      (lram_en),
        .we      (lram_we),
        .addr    (lram_addr),
        .wdata   (lram_wdata),
        .wstrb   ({DATA_WIDTH/8{1'b1}}),   // always full word
        .rdata   (lram_rdata),
        .rd_valid(lram_rd_valid)
    );

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam S_IDLE   = 3'd0;
    localparam S_LOAD   = 3'd1;  // prefetch first word from local SRAM
    localparam S_SETUP  = 3'd2;  // APB setup phase
    localparam S_ACCESS = 3'd3;  // APB access phase
    localparam S_STORE  = 3'd4;  // write read-data to local SRAM (read path)
    localparam S_DONE   = 3'd5;

    reg [2:0] state, nxt_state;

    // Transfer control registers
    reg                    rw_reg;
    reg [ADDR_WIDTH-1:0]   apb_addr_reg;
    reg [RAM_ADDR_W-1:0]   local_addr_reg;
    reg [7:0]              cnt;
    reg [7:0]              length_reg;

    // Read-from-slave: latched prdata
    reg [DATA_WIDTH-1:0]   prdata_lat;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state <= S_IDLE;
        else
            state <= nxt_state;
    end

    // -------------------------------------------------------------------------
    // Next state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        nxt_state = state;
        case (state)
            S_IDLE: begin
                if (start) begin
                    if (rw)
                        nxt_state = S_LOAD;   // write path: prefetch from local SRAM
                    else
                        nxt_state = S_SETUP;  // read path: go straight to APB setup
                end
            end
            S_LOAD: begin
                // One cycle for SRAM read latency, data available next cycle
                nxt_state = S_SETUP;
            end
            S_SETUP: begin
                nxt_state = S_ACCESS;
            end
            S_ACCESS: begin
                if (pready) begin
                    if (rw_reg) begin
                        // Write to slave: done?
                        if (cnt == length_reg)
                            nxt_state = S_DONE;
                        else
                            nxt_state = S_SETUP; // next word already prefetched
                    end else begin
                        // Read from slave: store to local SRAM
                        nxt_state = S_STORE;
                    end
                end
            end
            S_STORE: begin
                if (cnt == length_reg)
                    nxt_state = S_DONE;
                else
                    nxt_state = S_SETUP;
            end
            S_DONE: begin
                nxt_state = S_IDLE;
            end
            default: nxt_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Datapath
    // -------------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            rw_reg         <= 1'b0;
            apb_addr_reg   <= {ADDR_WIDTH{1'b0}};
            local_addr_reg <= {RAM_ADDR_W{1'b0}};
            cnt            <= 8'd0;
            length_reg     <= 8'd0;
            done           <= 1'b0;
            psel           <= 1'b0;
            penable        <= 1'b0;
            pwrite         <= 1'b0;
            paddr          <= {ADDR_WIDTH{1'b0}};
            pwdata         <= {DATA_WIDTH{1'b0}};
            pstrb          <= {DATA_WIDTH/8{1'b0}};
            prdata_lat     <= {DATA_WIDTH{1'b0}};
            lram_en        <= 1'b0;
            lram_we        <= 1'b0;
            lram_addr      <= {RAM_ADDR_W{1'b0}};
            lram_wdata     <= {DATA_WIDTH{1'b0}};
        end else begin
            done    <= 1'b0;
            lram_en <= 1'b0;
            lram_we <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;
                    if (start) begin
                        rw_reg         <= rw;
                        apb_addr_reg   <= apb_base;
                        local_addr_reg <= local_base;
                        length_reg     <= length;
                        cnt            <= 8'd0;
                        // Write path: start prefetch from local SRAM
                        if (rw) begin
                            lram_en   <= 1'b1;
                            lram_we   <= 1'b0;
                            lram_addr <= local_base;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_LOAD: begin
                    // SRAM data will be valid at next posedge (RD_LATENCY=1)
                    // Do nothing, just wait one cycle
                end

                // ---------------------------------------------------------
                S_SETUP: begin
                    // APB setup phase
                    psel    <= 1'b1;
                    penable <= 1'b0;
                    pwrite  <= rw_reg;
                    paddr   <= apb_addr_reg;
                    pstrb   <= {DATA_WIDTH/8{1'b1}};
                    if (rw_reg) begin
                        // Write path: lram_rdata is valid now (prefetched)
                        pwdata <= lram_rdata;
                        // Prefetch next word for back-to-back
                        lram_en   <= 1'b1;
                        lram_we   <= 1'b0;
                        lram_addr <= local_addr_reg + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                S_ACCESS: begin
                    penable <= 1'b1;
                    if (pready) begin
                        psel    <= 1'b0;
                        penable <= 1'b0;
                        cnt            <= cnt + 8'd1;
                        apb_addr_reg   <= apb_addr_reg + {{(ADDR_WIDTH-3){1'b0}}, 3'd4};
                        local_addr_reg <= local_addr_reg + 1'b1;
                        if (!rw_reg) begin
                            // Read path: latch data from slave
                            prdata_lat <= prdata;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_STORE: begin
                    // Write latched read-data to local SRAM
                    lram_en    <= 1'b1;
                    lram_we    <= 1'b1;
                    lram_addr  <= local_addr_reg - 1'b1;
                    lram_wdata <= prdata_lat;
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule
