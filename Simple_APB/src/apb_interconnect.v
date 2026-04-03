// =============================================================================
// Name:     apb_interconnect
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - APB interconnect (1 master, 2 slaves)
// - Address map:
//     slave 0: 0x0000 - 0x0FFF  (4KB address space)
//     slave 1: 0x1000 - 0x1FFF  (4KB address space)
// =============================================================================

`include "simple_apb.vh"

module apb_interconnect #(
	parameter ADDR_WIDTH = 13,
	parameter DATA_WIDTH = 32
) (
	// Master side
	input  wire                    psel_m,
	input  wire                    penable_m,
	input  wire                    pwrite_m,
	input  wire [ADDR_WIDTH-1:0]   paddr_m,
	input  wire [DATA_WIDTH-1:0]   pwdata_m,
	output wire [DATA_WIDTH-1:0]   prdata_m,
	output wire                    pready_m,
	output wire                    pslverr_m,

	// Slave 0
	output wire                    psel_s0,
	output wire                    penable_s0,
	output wire                    pwrite_s0,
	output wire [ADDR_WIDTH-2:0]   paddr_s0,
	output wire [DATA_WIDTH-1:0]   pwdata_s0,
	input  wire [DATA_WIDTH-1:0]   prdata_s0,
	input  wire                    pready_s0,
	input  wire                    pslverr_s0,

	// Slave 1
	output wire                    psel_s1,
	output wire                    penable_s1,
	output wire                    pwrite_s1,
	output wire [ADDR_WIDTH-2:0]   paddr_s1,
	output wire [DATA_WIDTH-1:0]   pwdata_s1,
	input  wire [DATA_WIDTH-1:0]   prdata_s1,
	input  wire                    pready_s1,
	input  wire                    pslverr_s1
);

	// -------------------------------------------------------------------------
	// Address decode
	// -------------------------------------------------------------------------
	wire sel_slave0;
	wire sel_slave1;

	assign sel_slave0 = psel_m & ((paddr_m & ~`SLV_ADDR_MASK) == `SLV0_BASE_ADDR);
	assign sel_slave1 = psel_m & ((paddr_m & ~`SLV_ADDR_MASK) == `SLV1_BASE_ADDR);

	// -------------------------------------------------------------------------
	// Forward to slaves (shared signals broadcast, PSEL gated)
	// -------------------------------------------------------------------------
	// Slave 0
	assign psel_s0    = sel_slave0;
	assign penable_s0 = penable_m;
	assign pwrite_s0  = pwrite_m;
	assign paddr_s0   = paddr_m[ADDR_WIDTH-2:0];
	assign pwdata_s0  = pwdata_m;

	// Slave 1
	assign psel_s1    = sel_slave1;
	assign penable_s1 = penable_m;
	assign pwrite_s1  = pwrite_m;
	assign paddr_s1   = paddr_m[ADDR_WIDTH-2:0];
	assign pwdata_s1  = pwdata_m;

	// -------------------------------------------------------------------------
	// Mux back to master
	// -------------------------------------------------------------------------
	assign prdata_m  = sel_slave1 ? prdata_s1  : prdata_s0;
	assign pready_m  = sel_slave1 ? pready_s1  : pready_s0;
	assign pslverr_m = sel_slave1 ? pslverr_s1 : pslverr_s0;

endmodule
