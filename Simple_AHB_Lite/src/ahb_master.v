// =============================================================================
// Name:     ahb_master
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Single-word AHB-Lite master protocol bridge
// - Converts command interface (start/addr/wdata/write) to AHB-Lite protocol
// - AHB-Lite pipelined: address phase (HTRANS/HADDR) then data phase (HWDATA/HRDATA)
// - Registered outputs driven one cycle ahead to align with FSM state
// - done/hresp_out are combinational for same-cycle notification
// =============================================================================

`include "ahb_addr_def.vh"

module ahb_master #(
	parameter ADDR_WIDTH = 13,
	parameter DATA_WIDTH = 32
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// Command interface
	input  wire                    start,      // pulse to begin transfer
	input  wire                    write,      // 1=write, 0=read
	input  wire [ADDR_WIDTH-1:0]   addr,
	input  wire [DATA_WIDTH-1:0]   wdata,
	output reg  [DATA_WIDTH-1:0]   rdata,      // registered, valid cycle after done
	output wire                    done,       // combinational, same-cycle notification
	output wire                    resp_err,   // combinational, same-cycle notification

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
	localparam ADDR = 2'd1;  // AHB address phase
	localparam DATA = 2'd2;  // AHB data phase (wait for hready)

	reg [1:0] state, nxt_state;

	// Latched write data (captured during ADDR phase for use in DATA phase)
	reg [DATA_WIDTH-1:0] wdata_lat;

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
				nxt_state = DATA;
			end
			DATA: begin
				if (hready)
					nxt_state = IDLE;
			end
			default: nxt_state = IDLE;
		endcase
	end

	// -------------------------------------------------------------------------
	// Combinational done / resp_err (same-cycle as DATA + hready)
	// -------------------------------------------------------------------------
	assign done     = (state == DATA) & hready;
	assign resp_err = (state == DATA) & hready & hresp;

	// -------------------------------------------------------------------------
	// Datapath (registered outputs driven one cycle ahead)
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			haddr     <= {ADDR_WIDTH{1'b0}};
			htrans    <= `HTRANS_IDLE;
			hwrite    <= 1'b0;
			hsize     <= 3'b000;
			hburst    <= `HBURST_SINGLE;
			hwdata    <= {DATA_WIDTH{1'b0}};
			wdata_lat <= {DATA_WIDTH{1'b0}};
			rdata     <= {DATA_WIDTH{1'b0}};
		end else begin
			case (state)
				// ---------------------------------------------------------
				// IDLE: on start, drive address phase outputs for next cycle
				// ---------------------------------------------------------
				IDLE: begin
					if (start) begin
						haddr  <= addr;
						htrans <= `HTRANS_NONSEQ;
						hwrite <= write;
						hsize  <= `HSIZE_WORD;
						hburst <= `HBURST_SINGLE;
						wdata_lat <= wdata;
					end else begin
						htrans <= `HTRANS_IDLE;
					end
				end

				// ---------------------------------------------------------
				// ADDR: address phase active, drive write data for data phase
				// ---------------------------------------------------------
				ADDR: begin
					htrans <= `HTRANS_IDLE;
					hwdata <= wdata_lat;
				end

				// ---------------------------------------------------------
				// DATA: wait for hready, then capture read data and clean up
				// ---------------------------------------------------------
				DATA: begin
					if (hready) begin
						haddr  <= {ADDR_WIDTH{1'b0}};
						hwrite <= 1'b0;
						hsize  <= 3'b000;
						hwdata <= {DATA_WIDTH{1'b0}};
						rdata  <= hrdata;
					end
				end
			endcase
		end
	end

endmodule
