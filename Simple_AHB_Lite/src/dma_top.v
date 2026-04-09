// =============================================================================
// Name: dma_top
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - DMA wrapper: slave port on Bus1 + master port on Bus2
// - CPU configures DMA via Bus1 slave, DMA moves data via Bus2 master
// =============================================================================

`include "ahb_lite_def.vh"

module dma_top #(
	parameter SLV_AW  = 12,             // Bus1 local address width
	parameter MST_AW  = `AHB_ADDR_W,    // Bus2 full address width
	parameter DATA_WIDTH = `AHB_DATA_W
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// AHB-Lite slave interface (Bus1, config path)
	input  wire                    s_hsel,
	input  wire [SLV_AW-1:0]      s_haddr,
	input  wire [1:0]              s_htrans,
	input  wire                    s_hwrite,
	input  wire [2:0]              s_hsize,
	input  wire [DATA_WIDTH-1:0]   s_hwdata,
	input  wire                    s_hready,
	output wire [DATA_WIDTH-1:0]   s_hrdata,
	output wire                    s_hreadyout,
	output wire                    s_hresp,

	// AHB-Lite master interface (Bus2, data path)
	output wire [MST_AW-1:0]      m_haddr,
	output wire [1:0]              m_htrans,
	output wire                    m_hwrite,
	output wire [2:0]              m_hsize,
	output wire [2:0]              m_hburst,
	output wire [DATA_WIDTH-1:0]   m_hwdata,
	input  wire [DATA_WIDTH-1:0]   m_hrdata,
	input  wire                    m_hready,
	input  wire                    m_hresp,

	// Interrupt / status
	output wire                    dma_done_o
);

	// -------------------------------------------------------------------------
	// Internal wires between slave and master
	// -------------------------------------------------------------------------
	wire                    start_w;
	wire [DATA_WIDTH-1:0]   src_w;
	wire [DATA_WIDTH-1:0]   dst_w;
	wire [4:0]              len_w;
	wire [2:0]              burst_w;
	wire                    busy_w;
	wire                    done_w;
	wire                    err_w;

	// -------------------------------------------------------------------------
	// DMA slave — configuration registers on Bus1
	// -------------------------------------------------------------------------
	dma_slave #(
		.ADDR_WIDTH (SLV_AW),
		.DATA_WIDTH (DATA_WIDTH)
	) u_dma_slv (
		.hclk      (hclk),
		.hresetn   (hresetn),
		.hsel      (s_hsel),
		.haddr     (s_haddr),
		.htrans    (s_htrans),
		.hwrite    (s_hwrite),
		.hsize     (s_hsize),
		.hwdata    (s_hwdata),
		.hready    (s_hready),
		.hrdata    (s_hrdata),
		.hreadyout (s_hreadyout),
		.hresp     (s_hresp),
		.dma_start (start_w),
		.dma_src   (src_w),
		.dma_dst   (dst_w),
		.dma_len   (len_w),
		.dma_burst (burst_w),
		.dma_busy  (busy_w),
		.dma_done  (done_w),
		.dma_err   (err_w)
	);

	// -------------------------------------------------------------------------
	// DMA master — burst engine on Bus2
	// -------------------------------------------------------------------------
	dma_master #(
		.ADDR_WIDTH (MST_AW),
		.DATA_WIDTH (DATA_WIDTH)
	) u_dma_mst (
		.hclk      (hclk),
		.hresetn   (hresetn),
		.haddr     (m_haddr),
		.htrans    (m_htrans),
		.hwrite    (m_hwrite),
		.hsize     (m_hsize),
		.hburst    (m_hburst),
		.hwdata    (m_hwdata),
		.hrdata    (m_hrdata),
		.hready    (m_hready),
		.hresp     (m_hresp),
		.dma_start (start_w),
		.dma_src   (src_w),
		.dma_dst   (dst_w),
		.dma_len   (len_w),
		.dma_burst (burst_w),
		.dma_busy  (busy_w),
		.dma_done  (done_w),
		.dma_err   (err_w)
	);

	assign dma_done_o = done_w;

endmodule
