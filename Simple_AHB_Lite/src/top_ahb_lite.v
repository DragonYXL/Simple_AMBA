// =============================================================================
// Name: top_ahb_lite
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - Top-level for AHB-Lite learning project
// - Bus1: CPU (master) -> DMA config + register slave
// - Bus2: DMA (master) -> SRAM0 + SRAM1
// =============================================================================

`include "ahb_lite_def.vh"

module top_ahb_lite #(
	parameter ADDR_WIDTH = `AHB_ADDR_W,
	parameter DATA_WIDTH = `AHB_DATA_W,
	parameter SRAM_DEPTH = 1024
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// CPU command interface
	input  wire                    cpu_start,
	input  wire                    cpu_write,
	input  wire [ADDR_WIDTH-1:0]   cpu_addr,
	input  wire [DATA_WIDTH-1:0]   cpu_wdata,
	output wire [DATA_WIDTH-1:0]   cpu_rdata,
	output wire                    cpu_done,
	output wire                    cpu_error,

	// Register slave hw2reg / reg2hw
	input  wire [`REG_NUM_RO*DATA_WIDTH-1:0]  hw2reg,
	output wire [`REG_NUM_RW*DATA_WIDTH-1:0]  reg2hw,
	output wire [`REG_NUM_RW-1:0]             rw_wr_pulse,

	// DMA done interrupt
	output wire                    dma_done
);

	// =========================================================================
	//  Bus1 wires — CPU (master) -> interconnect -> DMA slave + register slave
	// =========================================================================

	// master -> interconnect
	wire [ADDR_WIDTH-1:0]  b1_haddr;
	wire [1:0]             b1_htrans;
	wire                   b1_hwrite;
	wire [2:0]             b1_hsize;
	wire [2:0]             b1_hburst;
	wire [DATA_WIDTH-1:0]  b1_hwdata;
	wire [DATA_WIDTH-1:0]  b1_hrdata;
	wire                   b1_hready;
	wire                   b1_hresp;

	// interconnect -> slaves (shared)
	wire [11:0]            b1s_haddr;
	wire [1:0]             b1s_htrans;
	wire                   b1s_hwrite;
	wire [2:0]             b1s_hsize;
	wire [2:0]             b1s_hburst;
	wire [DATA_WIDTH-1:0]  b1s_hwdata;
	wire                   b1s_hready;

	// per-slave select & response
	wire                   b1_s0_hsel;
	wire [DATA_WIDTH-1:0]  b1_s0_hrdata;
	wire                   b1_s0_hrdyout;
	wire                   b1_s0_hresp;

	wire                   b1_s1_hsel;
	wire [DATA_WIDTH-1:0]  b1_s1_hrdata;
	wire                   b1_s1_hrdyout;
	wire                   b1_s1_hresp;

	// =========================================================================
	//  Bus2 wires — DMA (master) -> interconnect -> SRAM0 + SRAM1
	// =========================================================================

	wire [ADDR_WIDTH-1:0]  b2_haddr;
	wire [1:0]             b2_htrans;
	wire                   b2_hwrite;
	wire [2:0]             b2_hsize;
	wire [2:0]             b2_hburst;
	wire [DATA_WIDTH-1:0]  b2_hwdata;
	wire [DATA_WIDTH-1:0]  b2_hrdata;
	wire                   b2_hready;
	wire                   b2_hresp;

	wire [11:0]            b2s_haddr;
	wire [1:0]             b2s_htrans;
	wire                   b2s_hwrite;
	wire [2:0]             b2s_hsize;
	wire [2:0]             b2s_hburst;
	wire [DATA_WIDTH-1:0]  b2s_hwdata;
	wire                   b2s_hready;

	wire                   b2_s0_hsel;
	wire [DATA_WIDTH-1:0]  b2_s0_hrdata;
	wire                   b2_s0_hrdyout;
	wire                   b2_s0_hresp;

	wire                   b2_s1_hsel;
	wire [DATA_WIDTH-1:0]  b2_s1_hrdata;
	wire                   b2_s1_hrdyout;
	wire                   b2_s1_hresp;

	// =========================================================================
	//  Bus1 Master — CPU
	// =========================================================================
	ahb_master #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_cpu (
		.hclk    (hclk),
		.hresetn (hresetn),
		.start   (cpu_start),
		.write   (cpu_write),
		.addr    (cpu_addr),
		.wdata   (cpu_wdata),
		.rdata   (cpu_rdata),
		.done    (cpu_done),
		.error   (cpu_error),
		.haddr   (b1_haddr),
		.htrans  (b1_htrans),
		.hwrite  (b1_hwrite),
		.hsize   (b1_hsize),
		.hburst  (b1_hburst),
		.hwdata  (b1_hwdata),
		.hrdata  (b1_hrdata),
		.hready  (b1_hready),
		.hresp   (b1_hresp)
	);

	// =========================================================================
	//  Bus1 Interconnect
	// =========================================================================
	ahb_interconnect #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH),
		.SEL_BIT    (12)
	) u_bus1_ic (
		.hclk          (hclk),
		.hresetn       (hresetn),
		// master side
		.haddr         (b1_haddr),
		.htrans        (b1_htrans),
		.hwrite        (b1_hwrite),
		.hsize         (b1_hsize),
		.hburst        (b1_hburst),
		.hwdata        (b1_hwdata),
		.hrdata        (b1_hrdata),
		.hready        (b1_hready),
		.hresp         (b1_hresp),
		// slave 0 — DMA config
		.s0_hsel       (b1_s0_hsel),
		.s0_hrdata     (b1_s0_hrdata),
		.s0_hreadyout  (b1_s0_hrdyout),
		.s0_hresp      (b1_s0_hresp),
		// slave 1 — register file
		.s1_hsel       (b1_s1_hsel),
		.s1_hrdata     (b1_s1_hrdata),
		.s1_hreadyout  (b1_s1_hrdyout),
		.s1_hresp      (b1_s1_hresp),
		// shared to slaves
		.s_haddr       (b1s_haddr),
		.s_htrans      (b1s_htrans),
		.s_hwrite      (b1s_hwrite),
		.s_hsize       (b1s_hsize),
		.s_hburst      (b1s_hburst),
		.s_hwdata      (b1s_hwdata),
		.s_hready      (b1s_hready)
	);

	// =========================================================================
	//  Bus1 Slave 0 — DMA (config registers + burst engine)
	// =========================================================================
	dma_top #(
		.SLV_AW     (12),
		.MST_AW     (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_dma (
		.hclk        (hclk),
		.hresetn     (hresetn),
		// slave port on Bus1
		.s_hsel      (b1_s0_hsel),
		.s_haddr     (b1s_haddr),
		.s_htrans    (b1s_htrans),
		.s_hwrite    (b1s_hwrite),
		.s_hsize     (b1s_hsize),
		.s_hwdata    (b1s_hwdata),
		.s_hready    (b1s_hready),
		.s_hrdata    (b1_s0_hrdata),
		.s_hreadyout (b1_s0_hrdyout),
		.s_hresp     (b1_s0_hresp),
		// master port on Bus2
		.m_haddr     (b2_haddr),
		.m_htrans    (b2_htrans),
		.m_hwrite    (b2_hwrite),
		.m_hsize     (b2_hsize),
		.m_hburst    (b2_hburst),
		.m_hwdata    (b2_hwdata),
		.m_hrdata    (b2_hrdata),
		.m_hready    (b2_hready),
		.m_hresp     (b2_hresp),
		// status
		.dma_done_o  (dma_done)
	);

	// =========================================================================
	//  Bus1 Slave 1 — General register file
	// =========================================================================
	ahb_reg_slave #(
		.ADDR_WIDTH (12),
		.DATA_WIDTH (DATA_WIDTH),
		.NUM_RO     (`REG_NUM_RO),
		.NUM_RW     (`REG_NUM_RW)
	) u_reg_slv (
		.hclk        (hclk),
		.hresetn     (hresetn),
		.hsel        (b1_s1_hsel),
		.haddr       (b1s_haddr),
		.htrans      (b1s_htrans),
		.hwrite      (b1s_hwrite),
		.hsize       (b1s_hsize),
		.hwdata      (b1s_hwdata),
		.hready      (b1s_hready),
		.hrdata      (b1_s1_hrdata),
		.hreadyout   (b1_s1_hrdyout),
		.hresp       (b1_s1_hresp),
		.hw2reg      (hw2reg),
		.reg2hw      (reg2hw),
		.rw_wr_pulse (rw_wr_pulse)
	);

	// =========================================================================
	//  Bus2 Interconnect
	// =========================================================================
	ahb_interconnect #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH),
		.SEL_BIT    (12)
	) u_bus2_ic (
		.hclk          (hclk),
		.hresetn       (hresetn),
		.haddr         (b2_haddr),
		.htrans        (b2_htrans),
		.hwrite        (b2_hwrite),
		.hsize         (b2_hsize),
		.hburst        (b2_hburst),
		.hwdata        (b2_hwdata),
		.hrdata        (b2_hrdata),
		.hready        (b2_hready),
		.hresp         (b2_hresp),
		.s0_hsel       (b2_s0_hsel),
		.s0_hrdata     (b2_s0_hrdata),
		.s0_hreadyout  (b2_s0_hrdyout),
		.s0_hresp      (b2_s0_hresp),
		.s1_hsel       (b2_s1_hsel),
		.s1_hrdata     (b2_s1_hrdata),
		.s1_hreadyout  (b2_s1_hrdyout),
		.s1_hresp      (b2_s1_hresp),
		.s_haddr       (b2s_haddr),
		.s_htrans      (b2s_htrans),
		.s_hwrite      (b2s_hwrite),
		.s_hsize       (b2s_hsize),
		.s_hburst      (b2s_hburst),
		.s_hwdata      (b2s_hwdata),
		.s_hready      (b2s_hready)
	);

	// =========================================================================
	//  Bus2 Slave 0 — SRAM 0
	// =========================================================================
	ahb_sram #(
		.ADDR_WIDTH (12),
		.DATA_WIDTH (DATA_WIDTH),
		.DEPTH      (SRAM_DEPTH)
	) u_sram0 (
		.hclk      (hclk),
		.hresetn   (hresetn),
		.hsel      (b2_s0_hsel),
		.haddr     (b2s_haddr),
		.htrans    (b2s_htrans),
		.hwrite    (b2s_hwrite),
		.hsize     (b2s_hsize),
		.hburst    (b2s_hburst),
		.hwdata    (b2s_hwdata),
		.hready    (b2s_hready),
		.hrdata    (b2_s0_hrdata),
		.hreadyout (b2_s0_hrdyout),
		.hresp     (b2_s0_hresp)
	);

	// =========================================================================
	//  Bus2 Slave 1 — SRAM 1
	// =========================================================================
	ahb_sram #(
		.ADDR_WIDTH (12),
		.DATA_WIDTH (DATA_WIDTH),
		.DEPTH      (SRAM_DEPTH)
	) u_sram1 (
		.hclk      (hclk),
		.hresetn   (hresetn),
		.hsel      (b2_s1_hsel),
		.haddr     (b2s_haddr),
		.htrans    (b2s_htrans),
		.hwrite    (b2s_hwrite),
		.hsize     (b2s_hsize),
		.hburst    (b2s_hburst),
		.hwdata    (b2s_hwdata),
		.hready    (b2s_hready),
		.hrdata    (b2_s1_hrdata),
		.hreadyout (b2_s1_hrdyout),
		.hresp     (b2_s1_hresp)
	);

endmodule
