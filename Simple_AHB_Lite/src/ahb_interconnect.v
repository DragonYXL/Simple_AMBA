// =============================================================================
// Name: ahb_interconnect
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite 1-master-to-2-slave interconnect
// - Address decoder uses a single bit (SEL_BIT) for slave selection
// - Strips upper bits and passes local address to slaves
// - Muxes HRDATA / HREADYOUT / HRESP from data-phase-selected slave
// - Reused for both Bus1 and Bus2
// =============================================================================

`include "ahb_lite_def.vh"

module ahb_interconnect #(
	parameter ADDR_WIDTH = `AHB_ADDR_W,
	parameter DATA_WIDTH = `AHB_DATA_W,
	parameter SEL_BIT    = 12           // address bit for slave select
) (
	input  wire                      hclk,
	input  wire                      hresetn,

	// Master side
	input  wire [ADDR_WIDTH-1:0]     haddr,
	input  wire [1:0]                htrans,
	input  wire                      hwrite,
	input  wire [2:0]                hsize,
	input  wire [2:0]                hburst,
	input  wire [DATA_WIDTH-1:0]     hwdata,
	output wire [DATA_WIDTH-1:0]     hrdata,
	output wire                      hready,
	output wire                      hresp,

	// Slave 0
	output wire                      s0_hsel,
	input  wire [DATA_WIDTH-1:0]     s0_hrdata,
	input  wire                      s0_hreadyout,
	input  wire                      s0_hresp,

	// Slave 1
	output wire                      s1_hsel,
	input  wire [DATA_WIDTH-1:0]     s1_hrdata,
	input  wire                      s1_hreadyout,
	input  wire                      s1_hresp,

	// Shared slave-facing signals
	output wire [SEL_BIT-1:0]        s_haddr,
	output wire [1:0]                s_htrans,
	output wire                      s_hwrite,
	output wire [2:0]                s_hsize,
	output wire [2:0]                s_hburst,
	output wire [DATA_WIDTH-1:0]     s_hwdata,
	output wire                      s_hready
);

	// -------------------------------------------------------------------------
	// Address decode (combinational, address phase)
	// -------------------------------------------------------------------------
	assign s0_hsel = ~haddr[SEL_BIT];
	assign s1_hsel =  haddr[SEL_BIT];

	// -------------------------------------------------------------------------
	// Broadcast master signals to slaves (strip upper bits for address)
	// -------------------------------------------------------------------------
	assign s_haddr  = haddr[SEL_BIT-1:0];
	assign s_htrans = htrans;
	assign s_hwrite = hwrite;
	assign s_hsize  = hsize;
	assign s_hburst = hburst;
	assign s_hwdata = hwdata;
	assign s_hready = hready;          // muxed HREADY fed back to slaves

	// -------------------------------------------------------------------------
	// Data phase slave select (registered, updated when hready = 1)
	// -------------------------------------------------------------------------
	reg dph_sel;   // 0 = slave 0,  1 = slave 1

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn)
			dph_sel <= 1'b0;
		else if (hready)
			dph_sel <= haddr[SEL_BIT];
	end

	// -------------------------------------------------------------------------
	// Response mux (data phase)
	// -------------------------------------------------------------------------
	assign hrdata = dph_sel ? s1_hrdata    : s0_hrdata;
	assign hready = dph_sel ? s1_hreadyout : s0_hreadyout;
	assign hresp  = dph_sel ? s1_hresp     : s0_hresp;

endmodule
