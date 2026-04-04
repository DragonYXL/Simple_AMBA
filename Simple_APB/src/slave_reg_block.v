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
// =============================================================================

module slave_reg_block #(
	parameter ADDR_WIDTH   = 12,
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter NUM_RW_REGS  = 10,
	parameter IDX_WIDTH    = 4
) (
	input  wire                               periph_clk,
	input  wire                               periph_rstn,

	// Register request / response
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

	localparam integer DATA_BYTES = DATA_WIDTH / 8;
	localparam integer ADDR_LSB   = $clog2(DATA_BYTES);
	localparam [IDX_WIDTH-1:0] RW_BASE = NUM_RO_REGS[IDX_WIDTH-1:0];
	localparam [ADDR_WIDTH-1:0] REG_SPACE_BYTES = NUM_REGS * DATA_BYTES;

	wire                         req_aligned;
	wire                         req_in_range;
	wire [IDX_WIDTH-1:0]         req_idx;
	wire                         req_is_ro;
	wire [IDX_WIDTH-1:0]         req_rw_idx;

	wire [DATA_WIDTH-1:0]        ro_values [0:NUM_RO_REGS-1];
	reg  [DATA_WIDTH-1:0]        rw_regs   [0:NUM_RW_REGS-1];

	integer i;
	genvar g;

	// -------------------------------------------------------------------------
	// Address decode
	// - Requests use slave-local byte offsets
	// - All range, alignment, and permission checks are centralized here
	// -------------------------------------------------------------------------
	assign req_aligned = (reg_req_addr[ADDR_LSB-1:0] == {ADDR_LSB{1'b0}});
	assign req_in_range = (reg_req_addr < REG_SPACE_BYTES);
	assign req_idx = reg_req_addr[IDX_WIDTH+ADDR_LSB-1:ADDR_LSB];
	assign req_is_ro = (req_idx < NUM_RO_REGS);
	assign req_rw_idx = req_idx - RW_BASE;

	// -------------------------------------------------------------------------
	// Hardware-facing views
	// - RO values come from hw2reg
	// - RW values are continuously visible through reg2hw
	// -------------------------------------------------------------------------
	generate
		for (g = 0; g < NUM_RO_REGS; g = g + 1) begin : gen_ro_value
			assign ro_values[g] = hw2reg_ro_value[g*DATA_WIDTH +: DATA_WIDTH];
		end

		for (g = 0; g < NUM_RW_REGS; g = g + 1) begin : gen_rw_value
			assign reg2hw_rw_value[g*DATA_WIDTH +: DATA_WIDTH] = rw_regs[g];
		end
	endgenerate

	// -------------------------------------------------------------------------
	// Register access engine
	// - Respond in one periph_clk cycle for each request pulse
	// - Write RO or out-of-range accesses return reg_rsp_err
	// - Successful RW writes emit a one-cycle reg2hw write pulse
	// -------------------------------------------------------------------------
	always @(posedge periph_clk or negedge periph_rstn) begin
		if (!periph_rstn) begin
			for (i = 0; i < NUM_RW_REGS; i = i + 1)
				rw_regs[i] <= {DATA_WIDTH{1'b0}};

			reg_rsp_ready <= 1'b0;
			reg_rsp_rdata <= {DATA_WIDTH{1'b0}};
			reg_rsp_err   <= 1'b0;
			reg2hw_rw_write_pulse <= {NUM_RW_REGS{1'b0}};
		end else begin
			reg_rsp_ready <= 1'b0;
			reg_rsp_rdata <= {DATA_WIDTH{1'b0}};
			reg_rsp_err   <= 1'b0;
			reg2hw_rw_write_pulse <= {NUM_RW_REGS{1'b0}};

			if (reg_req_valid) begin
				// The local register block is currently single-cycle from the
				// request pulse to the response pulse.
				reg_rsp_ready <= 1'b1;

				if (!req_aligned || !req_in_range) begin
					reg_rsp_err <= 1'b1;
				end else if (reg_req_write) begin
					if (req_is_ro) begin
						reg_rsp_err <= 1'b1;
					end else begin
						rw_regs[req_rw_idx] <= reg_req_wdata;
						reg2hw_rw_write_pulse[req_rw_idx] <= 1'b1;
					end
				end else begin
					if (req_is_ro)
						reg_rsp_rdata <= ro_values[req_idx];
					else
						reg_rsp_rdata <= rw_regs[req_rw_idx];
				end
			end
		end
	end

endmodule
