// =============================================================================
// Name:     slave_reg_block
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Peripheral-domain register block with single source of truth
// - REG0-4  are read-only and provided by hw2reg
// - REG5-14 are read/write and exposed through reg2hw
// - Performs all register-map decode, range checks, and permission checks
//
// Address map (byte offset):
//   REG0 -REG4  : 0x00-0x10  RO  (hw2reg input)
//   REG5 -REG14 : 0x14-0x38  RW  (reg2hw output)
//   0x3C+       : illegal
//
// Error conditions (reg_rsp_err = 1):
//   - Unaligned access (addr[1:0] != 0)
//   - Out-of-range access (addr >= NUM_REGS * 4)
//   - Write to RO register (REG0-4)
// =============================================================================

module slave_reg_block #(
        parameter ADDR_WIDTH   = 12,
        parameter DATA_WIDTH   = 32,
        parameter NUM_RO_REGS  = 5,
        parameter NUM_RW_REGS  = 10
    ) (
        input  wire                               slv_clk,
        input  wire                               slv_rstn,

        // Register request / response (single-cycle handshake)
        input  wire                               reg_req_valid,
        input  wire                               reg_req_write,
        input  wire [ADDR_WIDTH-1:0]              reg_req_addr,
        input  wire [DATA_WIDTH-1:0]              reg_req_wdata,
        output reg                                reg_rsp_ready,
        output reg  [DATA_WIDTH-1:0]              reg_rsp_rdata,
        output reg                                reg_rsp_err,

        // Software-visible RW registers toward hardware
        output wire [NUM_RW_REGS*DATA_WIDTH-1:0]  reg2hw_rw_value,
        output reg  [NUM_RW_REGS-1:0]             reg2hw_rw_write_pulse,

        // Hardware-visible RO values toward software
        input  wire [NUM_RO_REGS*DATA_WIDTH-1:0]  hw2reg_ro_value
    );

    // -------------------------------------------------------------------------
    // Derived constants (default values shown for current config)
    // -------------------------------------------------------------------------
    localparam integer NUM_REGS    = NUM_RO_REGS + NUM_RW_REGS; // 15
    localparam integer IDX_WIDTH   = $clog2(NUM_REGS + 1);      // 4
    localparam integer DATA_BYTES  = DATA_WIDTH / 8;             // 4
    localparam integer ADDR_LSB    = $clog2(DATA_BYTES);         // 2

    // The complexity here mainly becasue the need for bit width conversion to prevent compilation warnings
    localparam [IDX_WIDTH-1:0]  RW_BASE       = NUM_RO_REGS[IDX_WIDTH-1:0]; // 4'd5
    localparam [ADDR_WIDTH-1:0] REG_SPACE_END = NUM_REGS * DATA_BYTES;      // 12'h03C

    // -------------------------------------------------------------------------
    // Address decode signals
    // -------------------------------------------------------------------------
    wire                   req_aligned;  // addr[1:0] == 0
    wire                   req_in_range; // addr < REG_SPACE_END
    wire [IDX_WIDTH-1:0]   req_idx;      // register index from byte addr
    wire                   req_is_ro;    // index falls in RO region
    wire [IDX_WIDTH-1:0]   req_rw_idx;   // index into RW array (idx - RW_BASE)

    // Prevent access that does not follow word-addressable rules
    assign req_aligned  = (reg_req_addr[ADDR_LSB-1:0] == {ADDR_LSB{1'b0}});

    // in the requset in reg file range
    assign req_in_range = (reg_req_addr < REG_SPACE_END);

    assign req_idx      = reg_req_addr[IDX_WIDTH+ADDR_LSB-1:ADDR_LSB];
    assign req_is_ro    = (req_idx < NUM_RO_REGS);
    assign req_rw_idx   = req_idx - RW_BASE;

    // -------------------------------------------------------------------------
    // Register storage
    // -------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0]  ro_values [0:NUM_RO_REGS-1];
    reg  [DATA_WIDTH-1:0]  rw_regs   [0:NUM_RW_REGS-1];

    // -------------------------------------------------------------------------
    // From the perspective of the slave
    // -------------------------------------------------------------------------
    genvar  g;

    generate
        // Unpack flat hw2reg bus into per-register wires
        for (g = 0; g < NUM_RO_REGS; g = g + 1) begin : gen_ro
            assign ro_values[g] = hw2reg_ro_value[g*DATA_WIDTH +: DATA_WIDTH];
        end

        // Pack per-register regs into flat reg2hw bus
        for (g = 0; g < NUM_RW_REGS; g = g + 1) begin : gen_rw
            assign reg2hw_rw_value[g*DATA_WIDTH +: DATA_WIDTH] = rw_regs[g];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Register access engine (single-cycle response)
    // -------------------------------------------------------------------------
    integer i;

    always @(posedge slv_clk or negedge slv_rstn) begin
        if (!slv_rstn) begin
            for (i = 0; i < NUM_RW_REGS; i = i + 1)
                rw_regs[i] <= {DATA_WIDTH{1'b0}};
            reg_rsp_ready         <= 1'b0;
            reg_rsp_rdata         <= {DATA_WIDTH{1'b0}};
            reg_rsp_err           <= 1'b0;
            reg2hw_rw_write_pulse <= {NUM_RW_REGS{1'b0}};
        end
        else if (reg_req_valid) begin
            reg_rsp_ready <= 1'b1;
            if (!req_aligned || !req_in_range) begin	// Alignment or range violation
                reg_rsp_err <= 1'b1;
            end
            else if (reg_req_write) begin
                if (req_is_ro) begin		// Write to read-only register
                    reg_rsp_err <= 1'b1;
                end
                else begin
                    rw_regs[req_rw_idx]                <= reg_req_wdata;
                    reg2hw_rw_write_pulse[req_rw_idx]  <= 1'b1;
                end
            end
            else begin		// Read path
                if (req_is_ro)
                    reg_rsp_rdata <= ro_values[req_idx];
                else
                    reg_rsp_rdata <= rw_regs[req_rw_idx];
            end
        end
        else begin		// Default: clear single-cycle outputs every cycle
            reg_rsp_ready         <= 1'b0;
            reg_rsp_rdata         <= {DATA_WIDTH{1'b0}};
            reg_rsp_err           <= 1'b0;
            reg2hw_rw_write_pulse <= {NUM_RW_REGS{1'b0}};
        end
    end

endmodule
