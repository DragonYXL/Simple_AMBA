// =============================================================================
// Name: dma_master
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - AHB-Lite burst master for DMA data movement on Bus2
// - Two-phase transfer: burst read (source) then burst write (destination)
// - Supports SINGLE / INCRx / WRAPx, word-only, up to 16 beats
// - Internal 16-word buffer between read and write phases
// =============================================================================

`include "ahb_lite_def.vh"

module dma_master #(
	parameter ADDR_WIDTH = `AHB_ADDR_W,
	parameter DATA_WIDTH = `AHB_DATA_W
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// AHB-Lite master interface (Bus2)
	output reg  [ADDR_WIDTH-1:0]   haddr,
	output reg  [1:0]              htrans,
	output reg                     hwrite,
	output reg  [2:0]              hsize,
	output reg  [2:0]              hburst,
	output reg  [DATA_WIDTH-1:0]   hwdata,
	input  wire [DATA_WIDTH-1:0]   hrdata,
	input  wire                    hready,
	input  wire                    hresp,

	// Control from dma_slave
	input  wire                    dma_start,
	input  wire [DATA_WIDTH-1:0]   dma_src,
	input  wire [DATA_WIDTH-1:0]   dma_dst,
	input  wire [4:0]              dma_len,      // 1-16
	input  wire [2:0]              dma_burst,

	// Status to dma_slave
	output wire                    dma_busy,
	output wire                    dma_done,
	output wire                    dma_err
);

	// -------------------------------------------------------------------------
	// FSM states
	// -------------------------------------------------------------------------
	localparam IDLE     = 3'd0;
	localparam RD_PHASE = 3'd1;  // burst read from source
	localparam WR_PHASE = 3'd2;  // burst write to destination
	localparam DONE     = 3'd3;

	reg [2:0] state, nxt_state;

	// -------------------------------------------------------------------------
	// Latched configuration (stable during transfer)
	// -------------------------------------------------------------------------
	reg [ADDR_WIDTH-1:0] src_cfg;
	reg [ADDR_WIDTH-1:0] dst_cfg;
	reg [2:0]            burst_cfg;
	reg [4:0]            num_beats;
	reg                  is_wrap;
	reg [ADDR_WIDTH-1:0] wrap_mask;

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			src_cfg   <= {ADDR_WIDTH{1'b0}};
			dst_cfg   <= {ADDR_WIDTH{1'b0}};
			burst_cfg <= `HBURST_SINGLE;
			num_beats <= 5'd1;
			is_wrap   <= 1'b0;
			wrap_mask <= {ADDR_WIDTH{1'b0}};
		end
		else if (state == IDLE && dma_start) begin
			src_cfg   <= dma_src[ADDR_WIDTH-1:0];
			dst_cfg   <= dma_dst[ADDR_WIDTH-1:0];
			burst_cfg <= dma_burst;

			// derive beat count from burst type
			case (dma_burst)
				`HBURST_SINGLE:  num_beats <= 5'd1;
				`HBURST_INCR:    num_beats <= dma_len;
				`HBURST_WRAP4,
				`HBURST_INCR4:   num_beats <= 5'd4;
				`HBURST_WRAP8,
				`HBURST_INCR8:   num_beats <= 5'd8;
				`HBURST_WRAP16,
				`HBURST_INCR16:  num_beats <= 5'd16;
				default:         num_beats <= 5'd1;
			endcase

			// wrap flag
			is_wrap <= (dma_burst == `HBURST_WRAP4)
			         | (dma_burst == `HBURST_WRAP8)
			         | (dma_burst == `HBURST_WRAP16);

			// wrap mask = num_beats * 4 - 1
			case (dma_burst)
				`HBURST_WRAP4:  wrap_mask <= {{(ADDR_WIDTH-4){1'b0}}, 4'hF};
				`HBURST_WRAP8:  wrap_mask <= {{(ADDR_WIDTH-5){1'b0}}, 5'h1F};
				`HBURST_WRAP16: wrap_mask <= {{(ADDR_WIDTH-6){1'b0}}, 6'h3F};
				default:        wrap_mask <= {ADDR_WIDTH{1'b0}};
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Beat counter
	//   cnt = 0         : first address phase (NONSEQ)
	//   cnt = 1..N-1    : addr phase(SEQ) + data phase of previous beat
	//   cnt = N          : last data phase only (HTRANS = IDLE)
	// -------------------------------------------------------------------------
	reg [4:0] cnt;

	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			cnt <= 5'd0;
		end
		else begin
			case (state)
				IDLE: begin
					cnt <= 5'd0;
				end
				RD_PHASE: begin
					if (hready) begin
						if (cnt == num_beats)
							cnt <= 5'd0;         // reset for write phase
						else
							cnt <= cnt + 5'd1;
					end
				end
				WR_PHASE: begin
					if (hready)
						cnt <= cnt + 5'd1;
				end
				DONE: begin
					cnt <= 5'd0;
				end
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Internal buffer (16 words)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] xfer_buf [0:15];

	// capture HRDATA during read phase (beat data_idx = cnt - 1)
	always @(posedge hclk) begin
		if (state == RD_PHASE && hready && cnt > 5'd0)
			xfer_buf[cnt - 5'd1] <= hrdata;
	end

	// -------------------------------------------------------------------------
	// Next-address calculation
	// -------------------------------------------------------------------------
	wire [ADDR_WIDTH-1:0] inc_addr  = haddr + {{(ADDR_WIDTH-3){1'b0}}, 3'd4};
	wire [ADDR_WIDTH-1:0] nxt_addr  = is_wrap ?
		((haddr & ~wrap_mask) | (inc_addr & wrap_mask)) : inc_addr;

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
				if (dma_start)
					nxt_state = RD_PHASE;
			end
			RD_PHASE: begin
				if (hready && cnt == num_beats)
					nxt_state = WR_PHASE;
			end
			WR_PHASE: begin
				if (hready && cnt == num_beats)
					nxt_state = DONE;
			end
			DONE: begin
				nxt_state = IDLE;
			end
			default:
				nxt_state = IDLE;
		endcase
	end

	// -------------------------------------------------------------------------
	// Registered AHB outputs
	//
	// Timing:
	//   Outputs registered in cycle K appear on bus in cycle K+1.
	//   IDLE + start  ->  register NONSEQ/src_addr  ->  bus shows in RD_PHASE
	//   RD cnt=N      ->  register NONSEQ/dst_addr  ->  bus shows in WR_PHASE
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			htrans <= `HTRANS_IDLE;
			haddr  <= {ADDR_WIDTH{1'b0}};
			hwrite <= 1'b0;
			hsize  <= `HSIZE_WORD;
			hburst <= `HBURST_SINGLE;
			hwdata <= {DATA_WIDTH{1'b0}};
		end
		else begin
			case (state)
				// ---------------------------------------------------------
				// IDLE: on start, set up first read address
				// ---------------------------------------------------------
				IDLE: begin
					if (dma_start) begin
						htrans <= `HTRANS_NONSEQ;
						haddr  <= dma_src[ADDR_WIDTH-1:0];
						hwrite <= 1'b0;
						hburst <= dma_burst;
						hsize  <= `HSIZE_WORD;
					end
				end

				// ---------------------------------------------------------
				// RD_PHASE: drive read addresses, capture read data
				// ---------------------------------------------------------
				RD_PHASE: begin
					if (hready) begin
						if (cnt == num_beats) begin
							// read done, set up first write address
							htrans <= `HTRANS_NONSEQ;
							haddr  <= dst_cfg;
							hwrite <= 1'b1;
							hburst <= burst_cfg;
						end
						else if (cnt == num_beats - 5'd1) begin
							// last read address was driven, next is data only
							htrans <= `HTRANS_IDLE;
						end
						else begin
							// more addresses to issue
							htrans <= `HTRANS_SEQ;
							haddr  <= nxt_addr;
						end
					end
				end

				// ---------------------------------------------------------
				// WR_PHASE: drive write addresses + write data
				//   hwdata[beat k] = xfer_buf[k], registered at cnt = k
				//   so it appears on bus at cnt = k+1 (data phase of beat k)
				// ---------------------------------------------------------
				WR_PHASE: begin
					if (hready) begin
						if (cnt == num_beats) begin
							// write done, clean up
							htrans <= `HTRANS_IDLE;
							hwrite <= 1'b0;
							hwdata <= {DATA_WIDTH{1'b0}};
						end
						else if (cnt == num_beats - 5'd1) begin
							// last write address, next is data only
							htrans <= `HTRANS_IDLE;
							hwdata <= xfer_buf[cnt];
						end
						else begin
							htrans <= `HTRANS_SEQ;
							haddr  <= nxt_addr;
							hwdata <= xfer_buf[cnt];
						end
					end
				end

				// ---------------------------------------------------------
				// DONE: one-cycle, reset all outputs
				// ---------------------------------------------------------
				DONE: begin
					htrans <= `HTRANS_IDLE;
					haddr  <= {ADDR_WIDTH{1'b0}};
					hwrite <= 1'b0;
					hburst <= `HBURST_SINGLE;
					hwdata <= {DATA_WIDTH{1'b0}};
				end
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Status outputs
	// -------------------------------------------------------------------------
	assign dma_busy = (state != IDLE);
	assign dma_done = (state == DONE);
	assign dma_err  = 1'b0;   // no error handling in this simple version

endmodule
