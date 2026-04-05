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
// - Payload latches live in the SOURCE domain of each direction:
//     request  payload latched in bus_clk  (stable before crossing)
//     response payload latched in slv_clk  (stable before crossing)
// =============================================================================

module reg_cdc_bridge #(
	parameter ADDR_WIDTH = 12,
	parameter DATA_WIDTH = 32
) (
	// Bus (APB) clock domain -- source of requests
	input  wire                    bus_clk,
	input  wire                    bus_rstn,
	input  wire                    bus_req_valid,	// one cycle pulse in bus_clk
	input  wire                    bus_req_write,
	input  wire [ADDR_WIDTH-1:0]   bus_req_addr,
	input  wire [DATA_WIDTH-1:0]   bus_req_wdata,
	output wire                    bus_rsp_ready,	// one cycle pulse in bus_clk
	output wire [DATA_WIDTH-1:0]   bus_rsp_rdata,
	output wire                    bus_rsp_err,

	// Slave (peripheral) clock domain -- source of responses
	input  wire                    slv_clk,
	input  wire                    slv_rstn,
	output wire                    slv_req_valid,	// one cycle pulse in slv_clk
	output wire                    slv_req_write,
	output wire [ADDR_WIDTH-1:0]   slv_req_addr,
	output wire [DATA_WIDTH-1:0]   slv_req_wdata,
	input  wire                    slv_rsp_ready,	// one cycle pulse in slv_clk
	input  wire [DATA_WIDTH-1:0]   slv_rsp_rdata,
	input  wire                    slv_rsp_err
);

	// -------------------------------------------------------------------------
	// Request payload latch (bus_clk domain -- source side)
	// - Snapshot request fields on the pulse, hold stable across CDC
	// -------------------------------------------------------------------------
	reg                      bus_req_write_lat;
	reg [ADDR_WIDTH-1:0]     bus_req_addr_lat;
	reg [DATA_WIDTH-1:0]     bus_req_wdata_lat;

	always @(posedge bus_clk or negedge bus_rstn) begin
		if (!bus_rstn) begin
			bus_req_write_lat <= 1'b0;
			bus_req_addr_lat  <= {ADDR_WIDTH{1'b0}};
			bus_req_wdata_lat <= {DATA_WIDTH{1'b0}};
		end else if (bus_req_valid) begin
			bus_req_write_lat <= bus_req_write;
			bus_req_addr_lat  <= bus_req_addr;
			bus_req_wdata_lat <= bus_req_wdata;
		end
	end

	assign slv_req_write = bus_req_write_lat;
	assign slv_req_addr  = bus_req_addr_lat;
	assign slv_req_wdata = bus_req_wdata_lat;

	// -------------------------------------------------------------------------
	// Response payload latch (slv_clk domain -- source side)
	// - Snapshot response fields on the pulse, hold stable across CDC
	// -------------------------------------------------------------------------
	reg                      slv_rsp_err_lat;
	reg [DATA_WIDTH-1:0]     slv_rsp_rdata_lat;

	always @(posedge slv_clk or negedge slv_rstn) begin
		if (!slv_rstn) begin
			slv_rsp_err_lat   <= 1'b0;
			slv_rsp_rdata_lat <= {DATA_WIDTH{1'b0}};
		end else if (slv_rsp_ready) begin
			slv_rsp_err_lat   <= slv_rsp_err;
			slv_rsp_rdata_lat <= slv_rsp_rdata;
		end
	end

	assign bus_rsp_rdata = slv_rsp_rdata_lat;
	assign bus_rsp_err   = slv_rsp_err_lat;

	// -------------------------------------------------------------------------
	// Request CDC: bus_clk -> slv_clk
	// -------------------------------------------------------------------------
	pulse_handshake u_req_cdc (
		.clk_src   (bus_clk),
		.rstn_src  (bus_rstn),
		.pulse_src (bus_req_valid),
		.busy_src  (),
		.clk_dst   (slv_clk),
		.rstn_dst  (slv_rstn),
		.pulse_dst (slv_req_valid)
	);

	// -------------------------------------------------------------------------
	// Response CDC: slv_clk -> bus_clk
	// -------------------------------------------------------------------------
	pulse_handshake u_rsp_cdc (
		.clk_src   (slv_clk),
		.rstn_src  (slv_rstn),
		.pulse_src (slv_rsp_ready),
		.busy_src  (),
		.clk_dst   (bus_clk),
		.rstn_dst  (bus_rstn),
		.pulse_dst (bus_rsp_ready)
	);

endmodule
