// =============================================================================
// Name: ahb_sram
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite SRAM slave, word-only, zero wait-state
// - Supports all burst types (master drives correct HADDR per beat)
// - Instantiated twice on Bus2 as SRAM0 and SRAM1
// =============================================================================

`include "ahb_lite_def.vh"

module ahb_sram #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = `AHB_DATA_W,
	parameter DEPTH      = 1024     // word count (4 KB)
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// AHB-Lite slave interface
	input  wire                    hsel,
	input  wire [ADDR_WIDTH-1:0]   haddr,
	input  wire [1:0]              htrans,
	input  wire                    hwrite,
	input  wire [2:0]              hsize,
	input  wire [2:0]              hburst,
	input  wire [DATA_WIDTH-1:0]   hwdata,
	input  wire                    hready,
	output reg  [DATA_WIDTH-1:0]   hrdata,
	output wire                    hreadyout,
	output wire                    hresp
);

	localparam AW = $clog2(DEPTH);  // word address width

	// -------------------------------------------------------------------------
	// Memory array
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

	// -------------------------------------------------------------------------
	// Address phase sampling
	// -------------------------------------------------------------------------
	wire valid_xfer = hsel & htrans[1] & hready;

	reg [AW-1:0] addr_r;
	reg           wr_r;
	reg           xfer_r;

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			addr_r <= {AW{1'b0}};
			wr_r   <= 1'b0;
			xfer_r <= 1'b0;
		end
		else if (hready) begin
			addr_r <= haddr[AW+1:2];   // byte addr -> word addr
			wr_r   <= hwrite;
			xfer_r <= valid_xfer;
		end
	end

	// -------------------------------------------------------------------------
	// Data phase — write
	// -------------------------------------------------------------------------
	always @(posedge hclk) begin
		if (xfer_r & wr_r & hready)
			mem[addr_r] <= hwdata;
	end

	// -------------------------------------------------------------------------
	// Data phase — read (synchronous read, result in data phase)
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn)
			hrdata <= {DATA_WIDTH{1'b0}};
		else if (valid_xfer & ~hwrite)
			hrdata <= mem[haddr[AW+1:2]];
	end

	// -------------------------------------------------------------------------
	// Always ready, always OKAY
	// -------------------------------------------------------------------------
	assign hreadyout = 1'b1;
	assign hresp     = `HRESP_OKAY;

endmodule
