// =============================================================================
// Name:     reg_cdc_bridge
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Single-request register CDC bridge
// - Source domain launches one request and waits for one response
// - Destination domain presents request to local register block and returns
//   the response through an independent handshake
// =============================================================================

module reg_cdc_bridge #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = 32
) (
	// Source domain
	input  wire                    src_clk,
	input  wire                    src_rstn,
	input  wire                    src_req_valid,
	input  wire                    src_req_write,
	input  wire [ADDR_WIDTH-1:0]   src_req_addr,
	input  wire [DATA_WIDTH-1:0]   src_req_wdata,
	output reg                     src_rsp_ready,
	output reg  [DATA_WIDTH-1:0]   src_rsp_rdata,
	output reg                     src_rsp_err,

	// Destination domain
	input  wire                    dst_clk,
	input  wire                    dst_rstn,
	output wire                    dst_req_valid,
	output wire                    dst_req_write,
	output wire [ADDR_WIDTH-1:0]   dst_req_addr,
	output wire [DATA_WIDTH-1:0]   dst_req_wdata,
	input  wire                    dst_rsp_ready,
	input  wire [DATA_WIDTH-1:0]   dst_rsp_rdata,
	input  wire                    dst_rsp_err
);

	localparam SRC_IDLE     = 1'b0;
	localparam SRC_WAIT_RSP = 1'b1;

	localparam [1:0] DST_IDLE     = 2'd0;
	localparam [1:0] DST_ISSUE    = 2'd1;
	localparam [1:0] DST_WAIT_RSP = 2'd2;
	localparam [1:0] DST_WAIT_ACK = 2'd3;

	reg src_state_q;
	reg [1:0] dst_state_q;

	reg                  src_req_pulse_q;
	wire                 req_busy_src;
	wire                 req_pulse_dst;
	reg                  rsp_pulse_dst_q;
	wire                 rsp_busy_dst;
	wire                 rsp_pulse_src;

	reg                  src_req_write_hold_q;
	reg [ADDR_WIDTH-1:0] src_req_addr_hold_q;
	reg [DATA_WIDTH-1:0] src_req_wdata_hold_q;

	reg                  dst_req_write_q;
	reg [ADDR_WIDTH-1:0] dst_req_addr_q;
	reg [DATA_WIDTH-1:0] dst_req_wdata_q;

	reg [DATA_WIDTH-1:0] dst_rsp_rdata_hold_q;
	reg                  dst_rsp_err_hold_q;

	// -------------------------------------------------------------------------
	// Destination-domain request view
	// - Present one stable request to the local register block
	// - The local block responds through dst_rsp_*
	// -------------------------------------------------------------------------
	assign dst_req_valid = (dst_state_q == DST_ISSUE);
	assign dst_req_write = dst_req_write_q;
	assign dst_req_addr  = dst_req_addr_q;
	assign dst_req_wdata = dst_req_wdata_q;

	// -------------------------------------------------------------------------
	// Request CDC: source -> destination
	// Response CDC: destination -> source
	// - Each direction uses one pulse handshake plus held payload registers
	// -------------------------------------------------------------------------
	pulse_handshake u_req_cdc (
		.clk_src   (src_clk),
		.rstn_src  (src_rstn),
		.pulse_src (src_req_pulse_q),
		.busy_src  (req_busy_src),
		.clk_dst   (dst_clk),
		.rstn_dst  (dst_rstn),
		.pulse_dst (req_pulse_dst)
	);

	pulse_handshake u_rsp_cdc (
		.clk_src   (dst_clk),
		.rstn_src  (dst_rstn),
		.pulse_src (rsp_pulse_dst_q),
		.busy_src  (rsp_busy_dst),
		.clk_dst   (src_clk),
		.rstn_dst  (src_rstn),
		.pulse_dst (rsp_pulse_src)
	);

	// -------------------------------------------------------------------------
	// Source-domain FSM
	// - SRC_IDLE: accept one request and launch the request pulse
	// - SRC_WAIT_RSP: wait for one response pulse from destination
	// -------------------------------------------------------------------------
	always @(posedge src_clk or negedge src_rstn) begin
		if (!src_rstn) begin
			src_state_q          <= SRC_IDLE;
			src_req_pulse_q      <= 1'b0;
			src_req_write_hold_q <= 1'b0;
			src_req_addr_hold_q  <= {ADDR_WIDTH{1'b0}};
			src_req_wdata_hold_q <= {DATA_WIDTH{1'b0}};
			src_rsp_ready        <= 1'b0;
			src_rsp_rdata        <= {DATA_WIDTH{1'b0}};
			src_rsp_err          <= 1'b0;
		end else begin
			src_req_pulse_q <= 1'b0;
			src_rsp_ready   <= 1'b0;

			case (src_state_q)
				SRC_IDLE: begin
					// Capture the complete request payload before toggling the CDC.
					if (src_req_valid && !req_busy_src) begin
						src_req_write_hold_q <= src_req_write;
						src_req_addr_hold_q  <= src_req_addr;
						src_req_wdata_hold_q <= src_req_wdata;
						src_req_pulse_q      <= 1'b1;
						src_state_q          <= SRC_WAIT_RSP;
					end
				end

				SRC_WAIT_RSP: begin
					// Response payload is already stable in the destination-held
					// registers when the return pulse is observed here.
					if (rsp_pulse_src) begin
						src_rsp_ready <= 1'b1;
						src_rsp_rdata <= dst_rsp_rdata_hold_q;
						src_rsp_err   <= dst_rsp_err_hold_q;
						src_state_q   <= SRC_IDLE;
					end
				end
			endcase
		end
	end

	// -------------------------------------------------------------------------
	// Destination-domain FSM
	// - DST_IDLE: wait for request pulse from source
	// - DST_ISSUE: expose one request beat to the local register block
	// - DST_WAIT_RSP: wait for local response
	// - DST_WAIT_ACK: wait until response CDC is no longer busy
	// -------------------------------------------------------------------------
	always @(posedge dst_clk or negedge dst_rstn) begin
		if (!dst_rstn) begin
			dst_state_q         <= DST_IDLE;
			dst_req_write_q     <= 1'b0;
			dst_req_addr_q      <= {ADDR_WIDTH{1'b0}};
			dst_req_wdata_q     <= {DATA_WIDTH{1'b0}};
			dst_rsp_rdata_hold_q <= {DATA_WIDTH{1'b0}};
			dst_rsp_err_hold_q  <= 1'b0;
			rsp_pulse_dst_q     <= 1'b0;
		end else begin
			rsp_pulse_dst_q <= 1'b0;

			case (dst_state_q)
				DST_IDLE: begin
					// The source-domain payload remains stable until the full
					// request/response round trip is complete.
					if (req_pulse_dst) begin
						dst_req_write_q <= src_req_write_hold_q;
						dst_req_addr_q  <= src_req_addr_hold_q;
						dst_req_wdata_q <= src_req_wdata_hold_q;
						dst_state_q     <= DST_ISSUE;
					end
				end

				DST_ISSUE: begin
					// Keep dst_req_valid asserted for one destination cycle.
					dst_state_q <= DST_WAIT_RSP;
				end

				DST_WAIT_RSP: begin
					// Capture the local response before returning the response pulse.
					if (dst_rsp_ready && !rsp_busy_dst) begin
						dst_rsp_rdata_hold_q <= dst_rsp_rdata;
						dst_rsp_err_hold_q   <= dst_rsp_err;
						rsp_pulse_dst_q      <= 1'b1;
						dst_state_q          <= DST_WAIT_ACK;
					end
				end

				DST_WAIT_ACK: begin
					// Wait for the response handshake to fully drain before
					// accepting the next request pulse.
					if (!rsp_busy_dst)
						dst_state_q <= DST_IDLE;
				end
			endcase
		end
	end

endmodule
