// =============================================================================
// Name:     apb_slave_interface
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - APB protocol adapter for one slave slot
// - Converts APB SETUP/ACCESS into a single in-flight register request
// - Waits for register response and drives APB wait-state via PREADY
// - Does not implement register map, permissions, or CDC policy
// =============================================================================

module apb_slave_interface #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = 32
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// APB slave interface
	input  wire                    psel,
	input  wire                    penable,
	input  wire                    pwrite,
	input  wire [ADDR_WIDTH-1:0]   paddr,
	input  wire [DATA_WIDTH-1:0]   pwdata,
	output wire [DATA_WIDTH-1:0]   prdata,
	output wire                    pready,
	output wire                    pslverr,

	// Register request toward backend
	output wire                    reg_req_valid,
	output wire                    reg_req_write,
	output wire [ADDR_WIDTH-1:0]   reg_req_addr,
	output wire [DATA_WIDTH-1:0]   reg_req_wdata,

	// Register response from backend
	input  wire                    reg_rsp_ready,
	input  wire [DATA_WIDTH-1:0]   reg_rsp_rdata,
	input  wire                    reg_rsp_err
);

	localparam IDLE     = 1'b0;
	localparam WAIT_RSP = 1'b1;

	reg state_q;
	reg req_write_q;

	reg                  rsp_pending_q;
	reg [DATA_WIDTH-1:0] rsp_rdata_q;
	reg                  rsp_err_q;

	wire setup_phase;
	wire access_phase;

	wire rsp_available;
	wire [DATA_WIDTH-1:0] rsp_rdata_mux;
	wire                  rsp_err_mux;

	// -------------------------------------------------------------------------
	// APB phase decode
	// -------------------------------------------------------------------------
	assign setup_phase = psel & ~penable;
	assign access_phase = psel & penable;

	// -------------------------------------------------------------------------
	// Backend register request
	// - Launch once during SETUP
	// - Backend must retain or consume the request from this pulse
	// -------------------------------------------------------------------------
	assign reg_req_valid = (state_q == IDLE) & setup_phase;
	assign reg_req_write = pwrite;
	assign reg_req_addr  = paddr;
	assign reg_req_wdata = pwdata;

	// -------------------------------------------------------------------------
	// Response mux
	// - If response comes back before ACCESS, buffer it locally
	// - If response arrives during ACCESS, use it directly
	// -------------------------------------------------------------------------
	assign rsp_available = rsp_pending_q | reg_rsp_ready;
	assign rsp_rdata_mux = reg_rsp_ready ? reg_rsp_rdata : rsp_rdata_q;
	assign rsp_err_mux   = reg_rsp_ready ? reg_rsp_err   : rsp_err_q;

	// -------------------------------------------------------------------------
	// APB response
	// - Hold PREADY low until one backend response is available
	// - PRDATA/PSLVERR are only meaningful on the completing ACCESS beat
	// -------------------------------------------------------------------------
	assign pready  = access_phase & rsp_available;
	assign prdata  = (access_phase & rsp_available & ~req_write_q) ? rsp_rdata_mux : {DATA_WIDTH{1'b0}};
	assign pslverr = access_phase & rsp_available & rsp_err_mux;

	// -------------------------------------------------------------------------
	// State machine
	// - IDLE: wait for one APB SETUP and issue one backend request
	// - WAIT_RSP: hold the request context until backend response returns
	// -------------------------------------------------------------------------
	always @(posedge pclk or negedge presetn) begin
		if (!presetn) begin
			state_q       <= IDLE;
			req_write_q   <= 1'b0;
			rsp_pending_q <= 1'b0;
			rsp_rdata_q   <= {DATA_WIDTH{1'b0}};
			rsp_err_q     <= 1'b0;
		end else begin
			case (state_q)
				IDLE: begin
					rsp_pending_q <= 1'b0;
					if (setup_phase) begin
						req_write_q <= pwrite;
						state_q     <= WAIT_RSP;
					end
				end

				WAIT_RSP: begin
					// Buffer an early response until the APB master reaches ACCESS.
					if (reg_rsp_ready && !access_phase) begin
						rsp_pending_q <= 1'b1;
						rsp_rdata_q   <= reg_rsp_rdata;
						rsp_err_q     <= reg_rsp_err;
					end

					// Complete the APB transfer on the first ACCESS cycle that
					// observes a valid backend response.
					if (access_phase && rsp_available) begin
						rsp_pending_q <= 1'b0;
						state_q       <= IDLE;
					end
				end
			endcase
		end
	end

endmodule
