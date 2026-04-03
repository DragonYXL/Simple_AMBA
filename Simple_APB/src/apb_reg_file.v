// =============================================================================
// Name:     apb_reg_file
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Dual-clock register file with CDC handshake
// - Instantiates pclk-domain regs, slv_clk-domain regs, and 2x CDC
// - RW: APB writes in pclk, CDC pulse syncs to slv_clk shadow
// - RO: local writes in slv_clk, CDC pulse syncs to pclk shadow
// - busy: RW CDC in flight (pclk domain, blocks next APB write)
// =============================================================================

module apb_reg_file #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter NUM_RW_REGS  = 10,
	parameter IDX_WIDTH    = 4
) (
	// pclk domain (APB side)
	input  wire                  pclk,
	input  wire                  prstn,

	// slv_clk domain (slave logic side)
	input  wire                  sclk,
	input  wire                  srstn,

	// Port A: APB read/write (pclk domain)
	input  wire                  wr_en,
	input  wire [IDX_WIDTH-1:0]  addr,
	input  wire [DATA_WIDTH-1:0] wr_data,
	output wire [DATA_WIDTH-1:0] rd_data,
	output wire                  err,
	output wire                  busy,

	// Port B: local (slv_clk domain)
	input  wire                  local_wr_en,
	input  wire [IDX_WIDTH-1:0]  local_wr_addr,
	input  wire [DATA_WIDTH-1:0] local_wr_data,
	input  wire [IDX_WIDTH-1:0]  local_rd_addr,
	output wire [DATA_WIDTH-1:0] local_rd_data
);

	// -------------------------------------------------------------------------
	// Internal CDC signals
	// -------------------------------------------------------------------------
	wire                  rw_update_pulse;     // pclk: RW reg written
	wire                  rw_update_sclk;      // slv_clk: CDC output
	wire                  rw_cdc_busy;         // pclk: CDC in flight

	wire                  ro_update_pulse;     // slv_clk: RO reg written
	wire                  ro_update_pclk;      // pclk: CDC output

	// Cross-domain register data buses
	wire [DATA_WIDTH-1:0] rw_reg_bus  [0:NUM_RW_REGS-1];  // pclk → slv_clk
	wire [DATA_WIDTH-1:0] ro_reg_bus  [0:NUM_RO_REGS-1];  // slv_clk → pclk

	// -------------------------------------------------------------------------
	// Busy: RW CDC handshake in flight (pclk domain)
	// -------------------------------------------------------------------------
	assign busy = rw_cdc_busy;

	// -------------------------------------------------------------------------
	// pclk domain registers (RW regs + RO shadow)
	// -------------------------------------------------------------------------
	apb_regs_pclk #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (NUM_REGS),
		.NUM_RO_REGS (NUM_RO_REGS),
		.NUM_RW_REGS (NUM_RW_REGS),
		.IDX_WIDTH   (IDX_WIDTH)
	) u_pclk_regs (
		.pclk            (pclk),
		.prstn           (prstn),
		.wr_en           (wr_en),
		.addr            (addr),
		.wr_data         (wr_data),
		.rd_data         (rd_data),
		.err             (err),
		.rw_update_pulse (rw_update_pulse),
		.rw_reg_out      (rw_reg_bus),
		.ro_update_pulse (ro_update_pclk),
		.ro_reg_in       (ro_reg_bus)
	);

	// -------------------------------------------------------------------------
	// slv_clk domain registers (RO regs + RW shadow)
	// -------------------------------------------------------------------------
	apb_regs_sclk #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_RO_REGS (NUM_RO_REGS),
		.NUM_RW_REGS (NUM_RW_REGS),
		.IDX_WIDTH   (IDX_WIDTH)
	) u_sclk_regs (
		.sclk            (sclk),
		.srstn           (srstn),
		.local_wr_en     (local_wr_en),
		.local_wr_addr   (local_wr_addr),
		.local_wr_data   (local_wr_data),
		.local_rd_addr   (local_rd_addr),
		.local_rd_data   (local_rd_data),
		.ro_update_pulse (ro_update_pulse),
		.ro_reg_out      (ro_reg_bus),
		.rw_update_pulse (rw_update_sclk),
		.rw_reg_in       (rw_reg_bus)
	);

	// -------------------------------------------------------------------------
	// CDC: RW update (pclk → slv_clk)
	// -------------------------------------------------------------------------
	pulse_handshake u_rw_cdc (
		.clk_src   (pclk),
		.rstn_src  (prstn),
		.pulse_src (rw_update_pulse),
		.busy_src  (rw_cdc_busy),
		.clk_dst   (sclk),
		.rstn_dst  (srstn),
		.pulse_dst (rw_update_sclk)
	);

	// -------------------------------------------------------------------------
	// CDC: RO update (slv_clk → pclk)
	// -------------------------------------------------------------------------
	pulse_handshake u_ro_cdc (
		.clk_src   (sclk),
		.rstn_src  (srstn),
		.pulse_src (ro_update_pulse),
		.busy_src  (),
		.clk_dst   (pclk),
		.rstn_dst  (prstn),
		.pulse_dst (ro_update_pclk)
	);

endmodule
