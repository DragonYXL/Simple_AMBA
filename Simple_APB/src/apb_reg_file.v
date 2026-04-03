// =============================================================================
// Name:     apb_reg_file
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Dual-port register file for APB slave
// - APB side: read all regs, write only RW regs (index >= NUM_RO_REGS)
// - Local side: write any register (for slave logic / testbench)
// =============================================================================

module apb_reg_file #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter IDX_WIDTH    = 4
) (
	input  wire                  pclk,
	input  wire                  presetn,

	// APB side (from slave adapter)
	input  wire                  apb_wr_en,
	input  wire [IDX_WIDTH-1:0]  apb_wr_addr,
	input  wire [DATA_WIDTH-1:0] apb_wr_data,
	input  wire [IDX_WIDTH-1:0]  apb_rd_addr,
	output wire [DATA_WIDTH-1:0] apb_rd_data,
	output wire                  apb_addr_valid,
	output wire                  apb_wr_ro_err,

	// Local side (for slave logic / testbench)
	input  wire                  local_wr_en,
	input  wire [IDX_WIDTH-1:0]  local_wr_addr,
	input  wire [DATA_WIDTH-1:0] local_wr_data
);

	// -------------------------------------------------------------------------
	// Register array
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

	// -------------------------------------------------------------------------
	// Address validity and RO protection
	// -------------------------------------------------------------------------
	wire is_ro;
	assign is_ro           = (apb_wr_addr < NUM_RO_REGS[IDX_WIDTH-1:0]);
	assign apb_addr_valid  = (apb_rd_addr < NUM_REGS[IDX_WIDTH-1:0]);
	assign apb_wr_ro_err   = apb_wr_en & (apb_wr_addr < NUM_REGS[IDX_WIDTH-1:0]) & is_ro;

	// -------------------------------------------------------------------------
	// APB read (combinational)
	// -------------------------------------------------------------------------
	assign apb_rd_data = regs[apb_rd_addr];

	// -------------------------------------------------------------------------
	// Register write logic
	// -------------------------------------------------------------------------
	integer i;
	always @(posedge pclk or negedge presetn) begin
		if (!presetn) begin
			for (i = 0; i < NUM_REGS; i = i + 1)
				regs[i] <= {DATA_WIDTH{1'b0}};
		end else begin
			// Local write: unrestricted, any register
			if (local_wr_en && (local_wr_addr < NUM_REGS[IDX_WIDTH-1:0]))
				regs[local_wr_addr] <= local_wr_data;

			// APB write: only RW registers (index >= NUM_RO_REGS)
			if (apb_wr_en && (apb_wr_addr < NUM_REGS[IDX_WIDTH-1:0]) && !is_ro)
				regs[apb_wr_addr] <= apb_wr_data;
		end
	end

endmodule
