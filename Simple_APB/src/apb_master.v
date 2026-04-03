// =============================================================================
// Name:     apb_master
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Single-word APB master protocol bridge
// - Converts command interface (start/addr/wdata/write) to APB protocol
// - Registered outputs driven one cycle ahead to align with FSM state
// - done/slverr are combinational for same-cycle notification
// =============================================================================

module apb_master #(
	parameter ADDR_WIDTH = 13,
	parameter DATA_WIDTH = 32
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// Command interface
	input  wire                    start,      // pulse to begin transfer
	input  wire                    write,      // 1=write, 0=read
	input  wire [ADDR_WIDTH-1:0]   addr,
	input  wire [DATA_WIDTH-1:0]   wdata,
	output reg  [DATA_WIDTH-1:0]   rdata,      // registered, valid cycle after done
	output wire                    done,       // combinational, same-cycle notification
	output wire                    slverr,     // combinational, same-cycle notification

	// APB master interface
	output reg                     psel,
	output reg                     penable,
	output reg                     pwrite,
	output reg  [ADDR_WIDTH-1:0]   paddr,
	output reg  [DATA_WIDTH-1:0]   pwdata,
	input  wire [DATA_WIDTH-1:0]   prdata,
	input  wire                    pready,
	input  wire                    pslverr
);

	// -------------------------------------------------------------------------
	// FSM states
	// -------------------------------------------------------------------------
	localparam IDLE   = 2'd0;
	localparam SETUP  = 2'd1;  // APB setup phase
	localparam ACCESS = 2'd2;  // APB access phase

	reg [1:0] state, nxt_state;

	// -------------------------------------------------------------------------
	// State register
	// -------------------------------------------------------------------------
	always @(posedge pclk or negedge presetn) begin
		if (!presetn)
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
					nxt_state = SETUP;
			end
			SETUP: begin
				nxt_state = ACCESS;
			end
			ACCESS: begin
				if (pready)
					nxt_state = IDLE;
			end
			default: nxt_state = IDLE;
		endcase
	end

	// -------------------------------------------------------------------------
	// Combinational done / slverr (same-cycle as ACCESS + pready)
	// -------------------------------------------------------------------------
	assign done   = (state == ACCESS) & pready;
	assign slverr = (state == ACCESS) & pready & pslverr;

	// -------------------------------------------------------------------------
	// Datapath (registered outputs driven one cycle ahead)
	// -------------------------------------------------------------------------
	always @(posedge pclk or negedge presetn) begin
		if (!presetn) begin
			psel    <= 1'b0;
			penable <= 1'b0;
			pwrite  <= 1'b0;
			paddr   <= {ADDR_WIDTH{1'b0}};
			pwdata  <= {DATA_WIDTH{1'b0}};
			rdata   <= {DATA_WIDTH{1'b0}};
		end else begin
			case (state)
				// ---------------------------------------------------------
				// IDLE: on start, drive SETUP outputs for next cycle
				// ---------------------------------------------------------
				IDLE: begin
					if (start) begin
						psel    <= 1'b1;
						penable <= 1'b0;
						pwrite  <= write;
						paddr   <= addr;
						pwdata  <= wdata;
					end
				end

				// ---------------------------------------------------------
				// SETUP: drive ACCESS outputs for next cycle
				// ---------------------------------------------------------
				SETUP: begin
					penable <= 1'b1;
				end

				// ---------------------------------------------------------
				// ACCESS: wait for pready, then capture and clean up
				// ---------------------------------------------------------
				ACCESS: begin
					if (pready) begin
						psel    <= 1'b0;
						penable <= 1'b0;
						pwrite  <= 1'b0;
						paddr   <= {ADDR_WIDTH{1'b0}};
						pwdata  <= {DATA_WIDTH{1'b0}};
						rdata   <= prdata;
					end
				end
			endcase
		end
	end

endmodule
