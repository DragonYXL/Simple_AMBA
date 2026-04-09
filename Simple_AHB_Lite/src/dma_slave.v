// =============================================================================
// Name: dma_slave
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite slave for DMA configuration registers on Bus1
// - Registers: SRC_ADDR, DST_ADDR, XFER_LEN, CTRL, STATUS
// - Generates one-cycle start pulse to DMA master engine
// =============================================================================

`include "ahb_lite_def.vh"

module dma_slave #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = `AHB_DATA_W
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// AHB-Lite slave interface
	input  wire                    hsel,
	input  wire [ADDR_WIDTH-1:0]   haddr,
	input  wire [1:0]              htrans,
	input  wire                    hwrite,
	input  wire [2:0]              hsize,
	input  wire [DATA_WIDTH-1:0]   hwdata,
	input  wire                    hready,
	output reg  [DATA_WIDTH-1:0]   hrdata,
	output wire                    hreadyout,
	output wire                    hresp,

	// DMA engine interface
	output reg                     dma_start,
	output wire [DATA_WIDTH-1:0]   dma_src,
	output wire [DATA_WIDTH-1:0]   dma_dst,
	output wire [4:0]              dma_len,      // 1-16 beats
	output wire [2:0]              dma_burst,    // HBURST encoding
	input  wire                    dma_busy,
	input  wire                    dma_done,
	input  wire                    dma_err
);

	// -------------------------------------------------------------------------
	// Address phase sampling
	// -------------------------------------------------------------------------
	wire valid_xfer = hsel & htrans[1] & hready;

	reg [ADDR_WIDTH-1:0] addr_r;
	reg                   wr_r;
	reg                   xfer_r;

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			addr_r <= {ADDR_WIDTH{1'b0}};
			wr_r   <= 1'b0;
			xfer_r <= 1'b0;
		end
		else if (hready) begin
			addr_r <= haddr;
			wr_r   <= hwrite;
			xfer_r <= valid_xfer;
		end
	end

	// -------------------------------------------------------------------------
	// Configuration registers (RW)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] src_reg;    // 0x000 source address
	reg [DATA_WIDTH-1:0] dst_reg;    // 0x004 destination address
	reg [DATA_WIDTH-1:0] len_reg;    // 0x008 transfer length
	reg [DATA_WIDTH-1:0] ctrl_reg;   // 0x00C control: [3:1]=burst, [0]=start

	// Status flags
	reg done_flag;
	reg err_flag;

	// Write logic
	wire wr_hit = xfer_r & wr_r & hready;

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			src_reg  <= {DATA_WIDTH{1'b0}};
			dst_reg  <= {DATA_WIDTH{1'b0}};
			len_reg  <= {DATA_WIDTH{1'b0}};
			ctrl_reg <= {DATA_WIDTH{1'b0}};
		end
		else if (wr_hit) begin
			case (addr_r)
				`DMA_REG_SRC:  src_reg  <= hwdata;
				`DMA_REG_DST:  dst_reg  <= hwdata;
				`DMA_REG_LEN:  len_reg  <= hwdata;
				`DMA_REG_CTRL: ctrl_reg <= hwdata;
				default: ;
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Start pulse (one-cycle, gated by !busy)
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn)
			dma_start <= 1'b0;
		else
			dma_start <= wr_hit
			          & (addr_r == `DMA_REG_CTRL)
			          & hwdata[0]
			          & ~dma_busy;
	end

	// -------------------------------------------------------------------------
	// Status register (RO)
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			done_flag <= 1'b0;
			err_flag  <= 1'b0;
		end
		else if (dma_start) begin
			done_flag <= 1'b0;
			err_flag  <= 1'b0;
		end
		else begin
			if (dma_done) done_flag <= 1'b1;
			if (dma_err)  err_flag  <= 1'b1;
		end
	end

	wire [DATA_WIDTH-1:0] stat_val = {{(DATA_WIDTH-3){1'b0}},
	                                   err_flag, done_flag, dma_busy};

	// -------------------------------------------------------------------------
	// Output to DMA engine
	// -------------------------------------------------------------------------
	assign dma_src   = src_reg;
	assign dma_dst   = dst_reg;
	assign dma_len   = len_reg[4:0];
	assign dma_burst = ctrl_reg[3:1];

	// -------------------------------------------------------------------------
	// Read mux
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			hrdata <= {DATA_WIDTH{1'b0}};
		end
		else if (valid_xfer & ~hwrite) begin
			case (haddr)
				`DMA_REG_SRC:  hrdata <= src_reg;
				`DMA_REG_DST:  hrdata <= dst_reg;
				`DMA_REG_LEN:  hrdata <= len_reg;
				`DMA_REG_CTRL: hrdata <= ctrl_reg;
				`DMA_REG_STAT: hrdata <= stat_val;
				default:       hrdata <= {DATA_WIDTH{1'b0}};
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Always ready, always OKAY
	// -------------------------------------------------------------------------
	assign hreadyout = 1'b1;
	assign hresp     = `HRESP_OKAY;

endmodule
