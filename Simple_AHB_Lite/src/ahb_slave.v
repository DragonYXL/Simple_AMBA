// =============================================================================
// Name:     ahb_slave
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - AHB-Lite slave protocol adapter (no reg_file inside)
// - Latches address-phase signals (AHB pipelined: addr phase N, data phase N+1)
// - ADDR phase: latch haddr/hwrite/htrans when hsel & hreadyout
// - DATA phase: execute write, drive hrdata, confirm transfer
// - hreadyout gated by external busy (from reg_file)
// - hresp driven on address error or write-to-RO
// =============================================================================

`include "ahb_addr_def.vh"

module ahb_slave #(
	parameter ADDR_WIDTH   = 12,
	parameter DATA_WIDTH   = `AHB_DATA_WIDTH
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
	output wire [DATA_WIDTH-1:0]   hrdata,
	output wire                    hreadyout,
	output wire                    hresp,

	// Register file interface (directly wired to reg_file in top)
	output wire [`REG_IDX_WIDTH-1:0]      reg_addr,
	output wire                           reg_wr_en,
	output wire [DATA_WIDTH-1:0]          reg_wr_data,
	input  wire [DATA_WIDTH-1:0]          reg_rd_data,
	input  wire                           reg_addr_valid,
	input  wire                           reg_wr_ro_err,
	input  wire                           reg_busy
);

	// -------------------------------------------------------------------------
	// Latched address-phase signals (captured at end of address phase)
	// -------------------------------------------------------------------------
	reg                          addr_phase_valid;
	reg [ADDR_WIDTH-1:0]         haddr_lat;
	reg                          hwrite_lat;

	// -------------------------------------------------------------------------
	// Address phase detection
	// -------------------------------------------------------------------------
	wire addr_phase;
	assign addr_phase = hsel & htrans[1] & hreadyout;

	// -------------------------------------------------------------------------
	// Latch address-phase signals
	// -------------------------------------------------------------------------
	always @(posedge hclk or negedge hresetn) begin
		if (!hresetn) begin
			addr_phase_valid <= 1'b0;
			haddr_lat        <= {ADDR_WIDTH{1'b0}};
			hwrite_lat       <= 1'b0;
		end else if (hreadyout) begin
			addr_phase_valid <= addr_phase;
			haddr_lat        <= haddr;
			hwrite_lat       <= hwrite;
		end
	end

	// -------------------------------------------------------------------------
	// Register file address (from latched address, word-aligned)
	// -------------------------------------------------------------------------
	assign reg_addr = haddr_lat[`REG_IDX_WIDTH+1:2];

	// -------------------------------------------------------------------------
	// Register file write (data phase: valid & write & ready)
	// -------------------------------------------------------------------------
	assign reg_wr_en   = addr_phase_valid & hwrite_lat & hreadyout;
	assign reg_wr_data = hwdata;

	// -------------------------------------------------------------------------
	// AHB-Lite response
	// -------------------------------------------------------------------------
	// hreadyout: deassert during data phase when reg_file is busy
	assign hreadyout = addr_phase_valid ? ~reg_busy : 1'b1;

	// hrdata: only valid during data phase with hreadyout, otherwise 0
	assign hrdata = (addr_phase_valid & hreadyout & ~hwrite_lat) ? reg_rd_data : {DATA_WIDTH{1'b0}};

	// hresp: out-of-range or write-to-RO, only on completed data phase
	assign hresp = (addr_phase_valid & hreadyout) ? (~reg_addr_valid | reg_wr_ro_err) : `HRESP_OKAY;

endmodule
