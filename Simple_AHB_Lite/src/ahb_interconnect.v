// =============================================================================
// Name:     ahb_interconnect
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - AHB-Lite interconnect (1 master, 2 slaves)
// - Address map:
//     slave 0: 0x0000 - 0x0FFF  (HADDR[12] == 0)
//     slave 1: 0x1000 - 0x1FFF  (HADDR[12] == 1)
// - Decodes HSEL per slave from master address
// - Muxes HRDATA/HREADYOUT/HRESP back to master
// =============================================================================

`include "ahb_addr_def.vh"

module ahb_interconnect #(
	parameter ADDR_WIDTH = 13,
	parameter DATA_WIDTH = 32
) (
	// Master side
	input  wire [ADDR_WIDTH-1:0]   haddr_m,
	input  wire [1:0]              htrans_m,
	input  wire                    hwrite_m,
	input  wire [2:0]              hsize_m,
	input  wire [2:0]              hburst_m,
	input  wire [DATA_WIDTH-1:0]   hwdata_m,
	output wire [DATA_WIDTH-1:0]   hrdata_m,
	output wire                    hready_m,
	output wire                    hresp_m,

	// Slave 0
	output wire                    hsel_s0,
	output wire [ADDR_WIDTH-2:0]   haddr_s0,
	output wire [1:0]              htrans_s0,
	output wire                    hwrite_s0,
	output wire [2:0]              hsize_s0,
	output wire [DATA_WIDTH-1:0]   hwdata_s0,
	input  wire [DATA_WIDTH-1:0]   hrdata_s0,
	input  wire                    hreadyout_s0,
	input  wire                    hresp_s0,

	// Slave 1
	output wire                    hsel_s1,
	output wire [ADDR_WIDTH-2:0]   haddr_s1,
	output wire [1:0]              htrans_s1,
	output wire                    hwrite_s1,
	output wire [2:0]              hsize_s1,
	output wire [DATA_WIDTH-1:0]   hwdata_s1,
	input  wire [DATA_WIDTH-1:0]   hrdata_s1,
	input  wire                    hreadyout_s1,
	input  wire                    hresp_s1
);

	// -------------------------------------------------------------------------
	// Address decode (active when HTRANS indicates a valid transfer)
	// -------------------------------------------------------------------------
	wire active_transfer;
	assign active_transfer = htrans_m[1];

	wire sel_slave0;
	wire sel_slave1;
	assign sel_slave0 = active_transfer & ((haddr_m & ~`SLV_ADDR_MASK) == `SLV0_BASE_ADDR);
	assign sel_slave1 = active_transfer & ((haddr_m & ~`SLV_ADDR_MASK) == `SLV1_BASE_ADDR);

	// -------------------------------------------------------------------------
	// Forward to slaves (shared signals broadcast, HSEL gated)
	// -------------------------------------------------------------------------
	// Slave 0
	assign hsel_s0   = sel_slave0;
	assign haddr_s0  = haddr_m[ADDR_WIDTH-2:0];
	assign htrans_s0 = htrans_m;
	assign hwrite_s0 = hwrite_m;
	assign hsize_s0  = hsize_m;
	assign hwdata_s0 = hwdata_m;

	// Slave 1
	assign hsel_s1   = sel_slave1;
	assign haddr_s1  = haddr_m[ADDR_WIDTH-2:0];
	assign htrans_s1 = htrans_m;
	assign hwrite_s1 = hwrite_m;
	assign hsize_s1  = hsize_m;
	assign hwdata_s1 = hwdata_m;

	// -------------------------------------------------------------------------
	// Mux back to master (based on which slave was selected)
	// -------------------------------------------------------------------------
	// Latched slave select for data phase mux (address and data phases are pipelined)
	// For this simple design with combinational slaves, use address-phase select directly
	assign hrdata_m = sel_slave1 ? hrdata_s1  : hrdata_s0;
	assign hready_m = sel_slave1 ? hreadyout_s1 : hreadyout_s0;
	assign hresp_m  = sel_slave1 ? hresp_s1  : hresp_s0;

endmodule
