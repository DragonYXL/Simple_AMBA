// =============================================================================
// Name:     top_apb
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Top level: APB master (bridge) + interconnect + 2 slaves with reg files
// - Each slave has 15 registers (reg0-4 RO, reg5-14 RW from APB side)
// - Local write ports exposed for testbench / slave-side logic
// =============================================================================

`include "apb_addr_def.vh"

module top_apb #(
	parameter ADDR_WIDTH       = `APB_ADDR_WIDTH,
	parameter DATA_WIDTH       = `APB_DATA_WIDTH,
	parameter SLAVE_ADDR_WIDTH = ADDR_WIDTH - 1
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// Command interface
	input  wire                           start,
	input  wire                           write,
	input  wire [ADDR_WIDTH-1:0]          addr,
	input  wire [DATA_WIDTH-1:0]          wdata,
	input  wire [DATA_WIDTH/8-1:0]        strb,
	output wire [DATA_WIDTH-1:0]          rdata,
	output wire                           done,
	output wire                           slverr,

	// Slave 0 local write port
	input  wire                           s0_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s0_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s0_local_wr_data,

	// Slave 1 local write port
	input  wire                           s1_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s1_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s1_local_wr_data
);

	// -------------------------------------------------------------------------
	// Internal APB signals: master <-> interconnect
	// -------------------------------------------------------------------------
	wire                    psel_m;
	wire                    penable_m;
	wire                    pwrite_m;
	wire [ADDR_WIDTH-1:0]   paddr_m;
	wire [DATA_WIDTH-1:0]   pwdata_m;
	wire [DATA_WIDTH/8-1:0] pstrb_m;
	wire [DATA_WIDTH-1:0]   prdata_m;
	wire                    pready_m;
	wire                    pslverr_m;

	// APB signals: interconnect <-> slave 0
	wire                        psel_s0;
	wire                        penable_s0;
	wire                        pwrite_s0;
	wire [SLAVE_ADDR_WIDTH-1:0] paddr_s0;
	wire [DATA_WIDTH-1:0]       pwdata_s0;
	wire [DATA_WIDTH/8-1:0]     pstrb_s0;
	wire [DATA_WIDTH-1:0]       prdata_s0;
	wire                        pready_s0;
	wire                        pslverr_s0;

	// APB signals: interconnect <-> slave 1
	wire                        psel_s1;
	wire                        penable_s1;
	wire                        pwrite_s1;
	wire [SLAVE_ADDR_WIDTH-1:0] paddr_s1;
	wire [DATA_WIDTH-1:0]       pwdata_s1;
	wire [DATA_WIDTH/8-1:0]     pstrb_s1;
	wire [DATA_WIDTH-1:0]       prdata_s1;
	wire                        pready_s1;
	wire                        pslverr_s1;

	// -------------------------------------------------------------------------
	// Master (single-word APB bridge)
	// -------------------------------------------------------------------------
	apb_master #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_master (
		.pclk    (pclk),
		.presetn (presetn),
		.start   (start),
		.write   (write),
		.addr    (addr),
		.wdata   (wdata),
		.strb    (strb),
		.rdata   (rdata),
		.done    (done),
		.slverr  (slverr),
		.psel    (psel_m),
		.penable (penable_m),
		.pwrite  (pwrite_m),
		.paddr   (paddr_m),
		.pwdata  (pwdata_m),
		.pstrb   (pstrb_m),
		.prdata  (prdata_m),
		.pready  (pready_m),
		.pslverr (pslverr_m)
	);

	// -------------------------------------------------------------------------
	// Interconnect (1 master, 2 slaves)
	// -------------------------------------------------------------------------
	apb_interconnect #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_interconnect (
		.psel_m     (psel_m),
		.penable_m  (penable_m),
		.pwrite_m   (pwrite_m),
		.paddr_m    (paddr_m),
		.pwdata_m   (pwdata_m),
		.pstrb_m    (pstrb_m),
		.prdata_m   (prdata_m),
		.pready_m   (pready_m),
		.pslverr_m  (pslverr_m),
		.psel_s0    (psel_s0),
		.penable_s0 (penable_s0),
		.pwrite_s0  (pwrite_s0),
		.paddr_s0   (paddr_s0),
		.pwdata_s0  (pwdata_s0),
		.pstrb_s0   (pstrb_s0),
		.prdata_s0  (prdata_s0),
		.pready_s0  (pready_s0),
		.pslverr_s0 (pslverr_s0),
		.psel_s1    (psel_s1),
		.penable_s1 (penable_s1),
		.pwrite_s1  (pwrite_s1),
		.paddr_s1   (paddr_s1),
		.pwdata_s1  (pwdata_s1),
		.pstrb_s1   (pstrb_s1),
		.prdata_s1  (prdata_s1),
		.pready_s1  (pready_s1),
		.pslverr_s1 (pslverr_s1)
	);

	// -------------------------------------------------------------------------
	// Slave 0
	// -------------------------------------------------------------------------
	apb_slave #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave0 (
		.pclk           (pclk),
		.presetn        (presetn),
		.psel           (psel_s0),
		.penable        (penable_s0),
		.pwrite         (pwrite_s0),
		.paddr          (paddr_s0),
		.pwdata         (pwdata_s0),
		.pstrb          (pstrb_s0),
		.prdata         (prdata_s0),
		.pready         (pready_s0),
		.pslverr        (pslverr_s0),
		.local_wr_en    (s0_local_wr_en),
		.local_wr_addr  (s0_local_wr_addr),
		.local_wr_data  (s0_local_wr_data)
	);

	// -------------------------------------------------------------------------
	// Slave 1
	// -------------------------------------------------------------------------
	apb_slave #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave1 (
		.pclk           (pclk),
		.presetn        (presetn),
		.psel           (psel_s1),
		.penable        (penable_s1),
		.pwrite         (pwrite_s1),
		.paddr          (paddr_s1),
		.pwdata         (pwdata_s1),
		.pstrb          (pstrb_s1),
		.prdata         (prdata_s1),
		.pready         (pready_s1),
		.pslverr        (pslverr_s1),
		.local_wr_en    (s1_local_wr_en),
		.local_wr_addr  (s1_local_wr_addr),
		.local_wr_data  (s1_local_wr_data)
	);

endmodule
