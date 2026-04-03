// =============================================================================
// Name:     apb_slave
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - APB slave protocol adapter
// - Decodes APB phases, generates register read/write controls
// - Handles PSLVERR for out-of-range and write-to-RO
// - Register file is protocol-agnostic (plain read/write interface)
// =============================================================================

`include "apb_addr_def.vh"

module apb_slave #(
	parameter ADDR_WIDTH   = 12,
	parameter DATA_WIDTH   = `APB_DATA_WIDTH
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// APB slave interface
	input  wire                    psel,
	input  wire                    penable,
	input  wire                    pwrite,
	input  wire [ADDR_WIDTH-1:0]   paddr,
	input  wire [DATA_WIDTH-1:0]   pwdata,
	input  wire [DATA_WIDTH/8-1:0] pstrb,
	output wire [DATA_WIDTH-1:0]   prdata,
	output wire                    pready,
	output wire                    pslverr,

	// Local write port (for slave logic / testbench)
	input  wire                           local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          local_wr_data,

	// Slave-side ready control
	input  wire                           local_ready
);

	// -------------------------------------------------------------------------
	// APB phase decode
	// -------------------------------------------------------------------------
	wire access_phase;
	assign access_phase = psel & penable;

	// -------------------------------------------------------------------------
	// Address decode (word-aligned register index)
	// -------------------------------------------------------------------------
	wire [`REG_IDX_WIDTH-1:0] reg_idx;
	assign reg_idx = paddr[`REG_IDX_WIDTH+1:2];

	// -------------------------------------------------------------------------
	// Register file control signals
	// -------------------------------------------------------------------------
	wire                  reg_wr_en;
	wire                  reg_addr_valid;
	wire                  reg_wr_ro_err;
	wire [DATA_WIDTH-1:0] reg_rd_data;

	// Write enable: only during access phase with pready
	assign reg_wr_en = access_phase & pwrite & pready;

	// Register file instance (protocol-agnostic)
	apb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file (
		.clk            (pclk),
		.rstn           (presetn),
		.wr_en          (reg_wr_en),
		.wr_addr        (reg_idx),
		.wr_data        (pwdata),
		.rd_addr        (reg_idx),
		.rd_data        (reg_rd_data),
		.addr_valid     (reg_addr_valid),
		.wr_ro_err      (reg_wr_ro_err),
		.local_wr_en    (local_wr_en),
		.local_wr_addr  (local_wr_addr),
		.local_wr_data  (local_wr_data)
	);

	// -------------------------------------------------------------------------
	// APB response
	// -------------------------------------------------------------------------
	assign prdata  = reg_rd_data;
	assign pready  = local_ready;
	assign pslverr = access_phase & pready & (~reg_addr_valid | reg_wr_ro_err);

endmodule
