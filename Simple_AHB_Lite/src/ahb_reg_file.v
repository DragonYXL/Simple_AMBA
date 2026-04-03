// =============================================================================
// Name:     ahb_reg_file
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Dual-port register file with RO/RW attribute
// - Port A: general read/write (write restricted by RO mask)
// - Port B (local): unrestricted write for slave logic / testbench
// - Outputs busy when local port is writing (Port A must wait)
// - No protocol awareness -- pure register storage
// =============================================================================

module ahb_reg_file #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter IDX_WIDTH    = 4
) (
	input  wire                  clk,
	input  wire                  rstn,

	// Port A: general read/write (shared address)
	input  wire                  wr_en,
	input  wire [IDX_WIDTH-1:0]  addr,
	input  wire [DATA_WIDTH-1:0] wr_data,
	output wire [DATA_WIDTH-1:0] rd_data,

	// Status outputs
	output wire                  addr_valid,
	output wire                  wr_ro_err,
	output wire                  busy,

	// Port B (local): unrestricted write
	input  wire                  local_wr_en,
	input  wire [IDX_WIDTH-1:0]  local_wr_addr,
	input  wire [DATA_WIDTH-1:0] local_wr_data
);

	// -------------------------------------------------------------------------
	// Register array
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

	// -------------------------------------------------------------------------
	// Bitmask for RO/valid lookup
	// -------------------------------------------------------------------------
	localparam [2**IDX_WIDTH-1:0] RO_MASK    = (1 << NUM_RO_REGS) - 1;
	localparam [2**IDX_WIDTH-1:0] VALID_MASK = (1 << NUM_REGS)    - 1;

	wire is_ro;
	assign is_ro       = RO_MASK[addr];
	assign addr_valid  = VALID_MASK[addr];
	assign wr_ro_err   = wr_en & addr_valid & is_ro;

	// -------------------------------------------------------------------------
	// Busy: local port is writing, Port A must wait
	// -------------------------------------------------------------------------
	assign busy = local_wr_en;

	// -------------------------------------------------------------------------
	// Read (combinational, shared address)
	// -------------------------------------------------------------------------
	assign rd_data = regs[addr];

	// -------------------------------------------------------------------------
	// Write logic
	// -------------------------------------------------------------------------
	integer i;
	always @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			for (i = 0; i < NUM_REGS; i = i + 1)
				regs[i] <= {DATA_WIDTH{1'b0}};
		end else begin
			// Port B (local): unrestricted, any register
			if (local_wr_en && VALID_MASK[local_wr_addr])
				regs[local_wr_addr] <= local_wr_data;

			// Port A: only RW registers, and not when busy
			if (wr_en && addr_valid && !is_ro && !busy)
				regs[addr] <= wr_data;
		end
	end

endmodule
