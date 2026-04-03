// =============================================================================
// Name:     apb_reg_file
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Dual-port register file with RO/RW attribute
// - Port A: general read/write (write restricted by RO mask)
// - Port B (local): unrestricted write for slave logic / testbench
// - No protocol awareness — pure register storage
// =============================================================================

module apb_reg_file #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter IDX_WIDTH    = 4
) (
	input  wire                  clk,
	input  wire                  rstn,

	// Port A: general read/write
	input  wire                  wr_en,
	input  wire [IDX_WIDTH-1:0]  wr_addr,
	input  wire [DATA_WIDTH-1:0] wr_data,
	input  wire [IDX_WIDTH-1:0]  rd_addr,
	output wire [DATA_WIDTH-1:0] rd_data,

	// Status outputs (address/attribute lookup)
	output wire                  addr_valid,
	output wire                  wr_ro_err,

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
	// Bitmask for RO/valid lookup (indexed by register address)
	// -------------------------------------------------------------------------
	// RO_MASK: bit[i]=1 means reg[i] is read-only on port A
	// VALID_MASK: bit[i]=1 means reg[i] exists
	localparam [2**IDX_WIDTH-1:0] RO_MASK    = (1 << NUM_RO_REGS) - 1;
	localparam [2**IDX_WIDTH-1:0] VALID_MASK = (1 << NUM_REGS)    - 1;

	wire is_ro;
	wire is_valid_wr;
	assign is_ro       = RO_MASK[wr_addr];
	assign addr_valid  = VALID_MASK[rd_addr];
	assign is_valid_wr = VALID_MASK[wr_addr];
	assign wr_ro_err   = wr_en & is_valid_wr & is_ro;

	// -------------------------------------------------------------------------
	// Read (combinational)
	// -------------------------------------------------------------------------
	assign rd_data = regs[rd_addr];

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

			// Port A: only RW registers (index >= NUM_RO_REGS)
			if (wr_en && is_valid_wr && !is_ro)
				regs[wr_addr] <= wr_data;
		end
	end

endmodule
