// =============================================================================
// Name: ahb_reg_slave
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite register file slave, zero wait-state
// - NUM_RO read-only registers sourced from hw2reg input
// - NUM_RW read-write registers exposed via reg2hw output
// - Provides per-register write pulse (rw_wr_pulse)
// =============================================================================

`include "ahb_lite_def.vh"

module ahb_reg_slave #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = `AHB_DATA_W,
	parameter NUM_RO     = `REG_NUM_RO,
	parameter NUM_RW     = `REG_NUM_RW
) (
	input  wire                           hclk,
	input  wire                           hresetn,

	// AHB-Lite slave interface
	input  wire                           hsel,
	input  wire [ADDR_WIDTH-1:0]          haddr,
	input  wire [1:0]                     htrans,
	input  wire                           hwrite,
	input  wire [2:0]                     hsize,
	input  wire [DATA_WIDTH-1:0]          hwdata,
	input  wire                           hready,
	output reg  [DATA_WIDTH-1:0]          hrdata,
	output wire                           hreadyout,
	output wire                           hresp,

	// Register interface
	input  wire [NUM_RO*DATA_WIDTH-1:0]   hw2reg,       // RO values from HW
	output wire [NUM_RW*DATA_WIDTH-1:0]   reg2hw,       // RW values to HW
	output reg  [NUM_RW-1:0]              rw_wr_pulse   // per-reg write pulse
);

	localparam NUM_REGS  = NUM_RO + NUM_RW;
	localparam IDX_WIDTH = $clog2(NUM_REGS);

	// -------------------------------------------------------------------------
	// Address phase sampling
	// -------------------------------------------------------------------------
	wire valid_xfer = hsel & htrans[1] & hready;

	reg [IDX_WIDTH-1:0] idx_r;
	reg                  wr_r;
	reg                  xfer_r;

	wire [IDX_WIDTH-1:0] reg_idx = haddr[IDX_WIDTH+1:2]; // byte -> reg index

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			idx_r  <= {IDX_WIDTH{1'b0}};
			wr_r   <= 1'b0;
			xfer_r <= 1'b0;
		end
		else if (hready) begin
			idx_r  <= reg_idx;
			wr_r   <= hwrite;
			xfer_r <= valid_xfer;
		end
	end

	// -------------------------------------------------------------------------
	// RW register array
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] rw_regs [0:NUM_RW-1];

	// Pack rw_regs into reg2hw bus
	genvar g;
	generate
		for (g = 0; g < NUM_RW; g = g + 1) begin : gen_reg2hw
			assign reg2hw[g*DATA_WIDTH +: DATA_WIDTH] = rw_regs[g];
		end
	endgenerate

	// -------------------------------------------------------------------------
	// Data phase — write RW registers
	// -------------------------------------------------------------------------
	integer i;
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			for (i = 0; i < NUM_RW; i = i + 1)
				rw_regs[i] <= {DATA_WIDTH{1'b0}};
			rw_wr_pulse <= {NUM_RW{1'b0}};
		end
		else begin
			rw_wr_pulse <= {NUM_RW{1'b0}};   // default: clear pulse
			if (xfer_r & wr_r & hready) begin
				// only write if index targets RW range
				if (idx_r >= NUM_RO && idx_r < NUM_REGS) begin
					rw_regs[idx_r - NUM_RO] <= hwdata;
					rw_wr_pulse[idx_r - NUM_RO] <= 1'b1;
				end
			end
		end
	end

	// -------------------------------------------------------------------------
	// Data phase — read (combinational mux, registered in addr phase)
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			hrdata <= {DATA_WIDTH{1'b0}};
		end
		else if (valid_xfer & ~hwrite) begin
			if (reg_idx < NUM_RO)
				hrdata <= hw2reg[reg_idx*DATA_WIDTH +: DATA_WIDTH];
			else if (reg_idx < NUM_REGS)
				hrdata <= rw_regs[reg_idx - NUM_RO];
			else
				hrdata <= {DATA_WIDTH{1'b0}};
		end
	end

	// -------------------------------------------------------------------------
	// Always ready, always OKAY
	// -------------------------------------------------------------------------
	assign hreadyout = 1'b1;
	assign hresp     = `HRESP_OKAY;

endmodule
