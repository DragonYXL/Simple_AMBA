// =============================================================================
// Single-port SRAM with configurable read latency
//   RD_LATENCY = 1 : standard synchronous read (data valid 1 cycle after en)
//   RD_LATENCY = N : data valid N cycles after en (adds N-1 pipeline stages)
//   Writes always complete in 1 cycle.
// =============================================================================

module sram #(
    parameter ADDR_WIDTH  = 10,
    parameter DATA_WIDTH  = 32,
    parameter DEPTH       = 1024,
    parameter RD_LATENCY  = 1       // >= 1
) (
    input  wire                    clk,
    input  wire                    en,
    input  wire                    we,
    input  wire [ADDR_WIDTH-1:0]   addr,
    input  wire [DATA_WIDTH-1:0]   wdata,
    input  wire [DATA_WIDTH/8-1:0] wstrb,
    output wire [DATA_WIDTH-1:0]   rdata,
    output wire                    rd_valid
);

    // -------------------------------------------------------------------------
    // Memory array
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write with byte strobes
    integer i;
    always @(posedge clk) begin
        if (en & we) begin
            for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
                if (wstrb[i])
                    mem[addr][i*8 +: 8] <= wdata[i*8 +: 8];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read pipeline  (stage 0 = synchronous read from array)
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] rdata_s0;
    reg                  rvalid_s0;

    always @(posedge clk) begin
        rdata_s0  <= mem[addr];
        rvalid_s0 <= en & ~we;
    end

    // -------------------------------------------------------------------------
    // Additional pipeline stages (RD_LATENCY > 1)
    // -------------------------------------------------------------------------
    generate
        if (RD_LATENCY == 1) begin : gen_lat1
            assign rdata    = rdata_s0;
            assign rd_valid = rvalid_s0;

        end else begin : gen_latn
            reg [DATA_WIDTH-1:0] rdata_pipe  [0:RD_LATENCY-2];
            reg                  rvalid_pipe [0:RD_LATENCY-2];

            // First extra stage
            always @(posedge clk) begin
                rdata_pipe[0]  <= rdata_s0;
                rvalid_pipe[0] <= rvalid_s0;
            end

            // Remaining extra stages
            genvar g;
            for (g = 1; g <= RD_LATENCY-2; g = g + 1) begin : gen_pipe
                always @(posedge clk) begin
                    rdata_pipe[g]  <= rdata_pipe[g-1];
                    rvalid_pipe[g] <= rvalid_pipe[g-1];
                end
            end

            assign rdata    = rdata_pipe[RD_LATENCY-2];
            assign rd_valid = rvalid_pipe[RD_LATENCY-2];
        end
    endgenerate

endmodule
