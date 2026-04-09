// =============================================================================
// Name: ahb_master
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite single-transfer master with simple command interface
// - Converts start/write/addr/wdata pulses into AHB-Lite SINGLE transfers
// - Used as CPU stub on Bus1 for register configuration
// =============================================================================

`include "ahb_lite_def.vh"

module ahb_master #(
	parameter ADDR_WIDTH = `AHB_ADDR_W,
	parameter DATA_WIDTH = `AHB_DATA_W
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// Command interface
	input  wire                    start,      // pulse to begin transfer
	input  wire                    write,      // 1=write, 0=read
	input  wire [ADDR_WIDTH-1:0]   addr,
	input  wire [DATA_WIDTH-1:0]   wdata,
	output reg  [DATA_WIDTH-1:0]   rdata,      // valid one cycle after done
	output wire                    done,       // combinational, same-cycle
	output wire                    error,      // combinational, same-cycle

	// AHB-Lite master interface
	output reg  [ADDR_WIDTH-1:0]   haddr,
	output reg  [1:0]              htrans,
	output reg                     hwrite,
	output reg  [2:0]              hsize,
	output reg  [2:0]              hburst,
	output reg  [DATA_WIDTH-1:0]   hwdata,
	input  wire [DATA_WIDTH-1:0]   hrdata,
	input  wire                    hready,
	input  wire                    hresp
);

	// -------------------------------------------------------------------------
	// FSM states
	// -------------------------------------------------------------------------
	localparam IDLE = 2'd0;
	localparam ADDR = 2'd1;  // address phase on bus
	localparam DATA = 2'd2;  // data phase on bus

	reg [1:0] state, nxt_state;

	// -------------------------------------------------------------------------
	// State register
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn)
			state <= IDLE;
		else
			state <= nxt_state;
	end

	// -------------------------------------------------------------------------
	// Next state logic
	// -------------------------------------------------------------------------
	always @(*) begin
		nxt_state = state;
		case (state)
			IDLE: begin
				if (start)
					nxt_state = ADDR;
			end
			ADDR: begin
				if (hready)
					nxt_state = DATA;
			end
			DATA: begin
				if (hready)
					nxt_state = IDLE;
			end
			default:
				nxt_state = IDLE;
		endcase
	end

	// -------------------------------------------------------------------------
	// Combinational done / error
	// -------------------------------------------------------------------------
	assign done  = (state == DATA) & hready;
	assign error = (state == DATA) & hready & hresp;

	// -------------------------------------------------------------------------
	// Registered AHB outputs
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			htrans <= `HTRANS_IDLE;
			haddr  <= {ADDR_WIDTH{1'b0}};
			hwrite <= 1'b0;
			hsize  <= `HSIZE_WORD;
			hburst <= `HBURST_SINGLE;
			hwdata <= {DATA_WIDTH{1'b0}};
			rdata  <= {DATA_WIDTH{1'b0}};
		end
		else begin
			case (state)
				// ---------------------------------------------------------
				// IDLE: latch command, drive address phase for next cycle
				// ---------------------------------------------------------
				IDLE: begin
					if (start) begin
						htrans <= `HTRANS_NONSEQ;
						haddr  <= addr;
						hwrite <= write;
						hsize  <= `HSIZE_WORD;
						hburst <= `HBURST_SINGLE;
						hwdata <= wdata;
					end
				end

				// ---------------------------------------------------------
				// ADDR: address captured, prepare data phase
				// ---------------------------------------------------------
				ADDR: begin
					if (hready) begin
						htrans <= `HTRANS_IDLE;
					end
				end

				// ---------------------------------------------------------
				// DATA: transfer complete, capture read data, clean up
				// ---------------------------------------------------------
				DATA: begin
					if (hready) begin
						htrans <= `HTRANS_IDLE;
						haddr  <= {ADDR_WIDTH{1'b0}};
						hwrite <= 1'b0;
						hwdata <= {DATA_WIDTH{1'b0}};
						if (!hwrite)
							rdata <= hrdata;
					end
				end
			endcase
		end
	end

endmodule
