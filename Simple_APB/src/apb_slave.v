// =============================================================================
// Name:     apb_slave
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - APB slave protocol adapter with internal register file
// - 15 registers: reg0-4 read-only (APB), reg5-14 read-write (APB)
// - Local write port exposed for slave logic / testbench access
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
	input  wire [DATA_WIDTH-1:0]          local_wr_data
);

	// -------------------------------------------------------------------------
	// Address decode
	// -------------------------------------------------------------------------
	wire [`REG_IDX_WIDTH-1:0] reg_idx;
	assign reg_idx = paddr[`REG_IDX_WIDTH+1:2];    // word-aligned index

	// -------------------------------------------------------------------------
	// Register file signals
	// -------------------------------------------------------------------------
	wire                  apb_addr_valid;
	wire                  apb_wr_ro_err;
	wire [DATA_WIDTH-1:0] rd_data;

	// Register file instance
	apb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file (
		.pclk           (pclk),
		.presetn        (presetn),
		.apb_wr_en      (psel & penable & pwrite),
		.apb_wr_addr    (reg_idx),
		.apb_wr_data    (pwdata),
		.apb_rd_addr    (reg_idx),
		.apb_rd_data    (rd_data),
		.apb_addr_valid (apb_addr_valid),
		.apb_wr_ro_err  (apb_wr_ro_err),
		.local_wr_en    (local_wr_en),
		.local_wr_addr  (local_wr_addr),
		.local_wr_data  (local_wr_data)
	);

	// -------------------------------------------------------------------------
	// APB response
	// -------------------------------------------------------------------------
	assign prdata  = rd_data;
	assign pready  = 1'b1;
	assign pslverr = psel & penable & (~apb_addr_valid | apb_wr_ro_err);

endmodule
