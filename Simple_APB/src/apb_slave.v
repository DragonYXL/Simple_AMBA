// =============================================================================
// Name:     apb_slave
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - APB slave protocol adapter (no reg_file inside)
// - Decodes APB phases, outputs generic register read/write signals
// - SETUP phase: address decode and read data preparation
// - ACCESS phase: execute write, confirm transfer
// - pready gated by busy (RW CDC in flight, pclk domain)
// - accesses outside implemented register window return PSLVERR
// - prdata held at 0 outside valid ACCESS window
// =============================================================================

`include "simple_apb.vh"

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
	output wire [DATA_WIDTH-1:0]   prdata,
	output wire                    pready,
	output wire                    pslverr,

	// Register file interface (wired to reg_file in top)
	output wire                           reg_clk,
	output wire                           reg_rstn,
	output wire [`REG_IDX_WIDTH-1:0]      reg_addr,
	output wire                           reg_wr_en,
	output wire [DATA_WIDTH-1:0]          reg_wr_data,
	input  wire [DATA_WIDTH-1:0]          reg_rd_data,
	input  wire                           reg_err,
	input  wire                           reg_busy
);

	// -------------------------------------------------------------------------
	// Clock/reset pass-through to register file
	// -------------------------------------------------------------------------
	assign reg_clk  = pclk;
	assign reg_rstn = presetn;

	// -------------------------------------------------------------------------
	// APB phase decode
	// -------------------------------------------------------------------------
	wire access_phase;
	assign access_phase = psel &  penable;

	// -------------------------------------------------------------------------
	// Register file address (driven from SETUP, held into ACCESS)
	// -------------------------------------------------------------------------
	wire reg_space_hit;
	assign reg_addr = paddr[`REG_IDX_WIDTH+1:2];
	assign reg_space_hit = ~|paddr[ADDR_WIDTH-1:`REG_IDX_WIDTH+2];

	// -------------------------------------------------------------------------
	// Register file write (ACCESS + pready + write)
	// -------------------------------------------------------------------------
	assign reg_wr_en   = access_phase & pwrite & pready & reg_space_hit;
	assign reg_wr_data = pwdata;

	// -------------------------------------------------------------------------
	// APB response
	// -------------------------------------------------------------------------
	// pready: deassert only during ACCESS when reg_file is busy
	assign pready  = access_phase ? ~reg_busy : 1'b1;

	// prdata: only valid during ACCESS with pready, otherwise 0
	assign prdata  = (access_phase & pready & ~pwrite & reg_space_hit)
	               ? reg_rd_data
	               : {DATA_WIDTH{1'b0}};

	// pslverr: invalid local offset or reg_file error, only on completed ACCESS
	assign pslverr = access_phase & pready & (~reg_space_hit | reg_err);

endmodule
