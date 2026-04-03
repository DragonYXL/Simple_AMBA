// =============================================================================
// Name:     apb_master
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Single-word APB master protocol bridge
// - Converts command interface (start/addr/wdata/write) to APB protocol
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
	input  wire [DATA_WIDTH/8-1:0] strb,
	output reg  [DATA_WIDTH-1:0]   rdata,
	output reg                     done,       // transfer complete pulse
	output reg                     slverr,     // latched pslverr

	// APB master interface
	output reg                     psel,
	output reg                     penable,
	output reg                     pwrite,
	output reg  [ADDR_WIDTH-1:0]   paddr,
	output reg  [DATA_WIDTH-1:0]   pwdata,
	output reg  [DATA_WIDTH/8-1:0] pstrb,
	input  wire [DATA_WIDTH-1:0]   prdata,
	input  wire                    pready,
	input  wire                    pslverr
);

	// -------------------------------------------------------------------------
	// FSM states
	// -------------------------------------------------------------------------
	localparam S_IDLE   = 2'd0;
	localparam S_SETUP  = 2'd1;  // APB setup phase
	localparam S_ACCESS = 2'd2;  // APB access phase

	reg [1:0] state, nxt_state;

	// -------------------------------------------------------------------------
	// State register
	// -------------------------------------------------------------------------
	always @(posedge pclk or negedge presetn) begin
		if (!presetn)
			state <= S_IDLE;
		else
			state <= nxt_state;
	end

	// -------------------------------------------------------------------------
	// Next state logic
	// -------------------------------------------------------------------------
	always @(*) begin
		nxt_state = state;
		case (state)
			S_IDLE: begin
				if (start)
					nxt_state = S_SETUP;
			end
			S_SETUP: begin
				nxt_state = S_ACCESS;
			end
			S_ACCESS: begin
				if (pready)
					nxt_state = S_IDLE;
			end
			default: nxt_state = S_IDLE;
		endcase
	end

	// -------------------------------------------------------------------------
	// Datapath
	// -------------------------------------------------------------------------
	always @(posedge pclk or negedge presetn) begin
		if (!presetn) begin
			psel    <= 1'b0;
			penable <= 1'b0;
			pwrite  <= 1'b0;
			paddr   <= {ADDR_WIDTH{1'b0}};
			pwdata  <= {DATA_WIDTH{1'b0}};
			pstrb   <= {DATA_WIDTH/8{1'b0}};
			rdata   <= {DATA_WIDTH{1'b0}};
			done    <= 1'b0;
			slverr  <= 1'b0;
		end else begin
			done   <= 1'b0;
			slverr <= 1'b0;

			case (state)
				// ---------------------------------------------------------
				S_IDLE: begin
					psel    <= 1'b0;
					penable <= 1'b0;
					if (start) begin
						pwrite <= write;
						paddr  <= addr;
						pwdata <= wdata;
						pstrb  <= strb;
					end
				end

				// ---------------------------------------------------------
				S_SETUP: begin
					psel    <= 1'b1;
					penable <= 1'b0;
				end

				// ---------------------------------------------------------
				S_ACCESS: begin
					penable <= 1'b1;
					if (pready) begin
						psel    <= 1'b0;
						penable <= 1'b0;
						rdata   <= prdata;
						slverr  <= pslverr;
						done    <= 1'b1;
					end
				end
			endcase
		end
	end

endmodule
