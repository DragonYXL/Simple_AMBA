// =============================================================================
// Name:     simple_apb
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Top level: master + interconnect + 2x (slave + reg_file) side-by-side
// - Each reg_file has 15 registers (reg0-4 RO, reg5-14 RW from APB side)
// - Local write ports exposed for slave logic / testbench
// =============================================================================

`include "simple_apb.vh"

module simple_apb #(
	parameter ADDR_WIDTH       = `APB_ADDR_WIDTH,
	parameter DATA_WIDTH       = `APB_DATA_WIDTH,
	parameter SLAVE_ADDR_WIDTH = ADDR_WIDTH - 1
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// Slave clock domain
	input  wire                    sclk,
	input  wire                    srstn,

	// Command interface
	input  wire                           start,
	input  wire                           write,
	input  wire [ADDR_WIDTH-1:0]          addr,
	input  wire [DATA_WIDTH-1:0]          wdata,
	output wire [DATA_WIDTH-1:0]          rdata,
	output wire                           done,
	output wire                           slverr,

	// Slave 0 local port (sclk domain, directly to reg_file0)
	input  wire                           s0_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s0_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s0_local_wr_data,
	input  wire [`REG_IDX_WIDTH-1:0]      s0_local_rd_addr,
	output wire [DATA_WIDTH-1:0]          s0_local_rd_data,

	// Slave 1 local port (sclk domain, directly to reg_file1)
	input  wire                           s1_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s1_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s1_local_wr_data,
	input  wire [`REG_IDX_WIDTH-1:0]      s1_local_rd_addr,
	output wire [DATA_WIDTH-1:0]          s1_local_rd_data
);

	// -------------------------------------------------------------------------
	// Internal APB signals: master <-> interconnect
	// -------------------------------------------------------------------------
	wire                    psel_m;
	wire                    penable_m;
	wire                    pwrite_m;
	wire [ADDR_WIDTH-1:0]   paddr_m;
	wire [DATA_WIDTH-1:0]   pwdata_m;
	wire [DATA_WIDTH-1:0]   prdata_m;
	wire                    pready_m;
	wire                    pslverr_m;

	// APB signals: interconnect <-> slave 0
	wire                        psel_s0;
	wire                        penable_s0;
	wire                        pwrite_s0;
	wire [SLAVE_ADDR_WIDTH-1:0] paddr_s0;
	wire [DATA_WIDTH-1:0]       pwdata_s0;
	wire [DATA_WIDTH-1:0]       prdata_s0;
	wire                        pready_s0;
	wire                        pslverr_s0;

	// APB signals: interconnect <-> slave 1
	wire                        psel_s1;
	wire                        penable_s1;
	wire                        pwrite_s1;
	wire [SLAVE_ADDR_WIDTH-1:0] paddr_s1;
	wire [DATA_WIDTH-1:0]       pwdata_s1;
	wire [DATA_WIDTH-1:0]       prdata_s1;
	wire                        pready_s1;
	wire                        pslverr_s1;

	// Slave 0 <-> reg_file 0 interface
	wire                       s0_reg_clk;
	wire                       s0_reg_rstn;
	wire [`REG_IDX_WIDTH-1:0]  s0_reg_addr;
	wire                       s0_reg_wr_en;
	wire [DATA_WIDTH-1:0]      s0_reg_wr_data;
	wire [DATA_WIDTH-1:0]      s0_reg_rd_data;
	wire                       s0_reg_err;
	wire                       s0_reg_busy;

	// Slave 1 <-> reg_file 1 interface
	wire                       s1_reg_clk;
	wire                       s1_reg_rstn;
	wire [`REG_IDX_WIDTH-1:0]  s1_reg_addr;
	wire                       s1_reg_wr_en;
	wire [DATA_WIDTH-1:0]      s1_reg_wr_data;
	wire [DATA_WIDTH-1:0]      s1_reg_rd_data;
	wire                       s1_reg_err;
	wire                       s1_reg_busy;

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
		.rdata   (rdata),
		.done    (done),
		.slverr  (slverr),
		.psel    (psel_m),
		.penable (penable_m),
		.pwrite  (pwrite_m),
		.paddr   (paddr_m),
		.pwdata  (pwdata_m),
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
		.prdata_m   (prdata_m),
		.pready_m   (pready_m),
		.pslverr_m  (pslverr_m),
		.psel_s0    (psel_s0),
		.penable_s0 (penable_s0),
		.pwrite_s0  (pwrite_s0),
		.paddr_s0   (paddr_s0),
		.pwdata_s0  (pwdata_s0),
		.prdata_s0  (prdata_s0),
		.pready_s0  (pready_s0),
		.pslverr_s0 (pslverr_s0),
		.psel_s1    (psel_s1),
		.penable_s1 (penable_s1),
		.pwrite_s1  (pwrite_s1),
		.paddr_s1   (paddr_s1),
		.pwdata_s1  (pwdata_s1),
		.prdata_s1  (prdata_s1),
		.pready_s1  (pready_s1),
		.pslverr_s1 (pslverr_s1)
	);

	// -------------------------------------------------------------------------
	// Slave 0 (APB protocol adapter)
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
		.prdata         (prdata_s0),
		.pready         (pready_s0),
		.pslverr        (pslverr_s0),
		.reg_clk        (s0_reg_clk),
		.reg_rstn       (s0_reg_rstn),
		.reg_addr       (s0_reg_addr),
		.reg_wr_en      (s0_reg_wr_en),
		.reg_wr_data    (s0_reg_wr_data),
		.reg_rd_data    (s0_reg_rd_data),
		.reg_err        (s0_reg_err),
		.reg_busy       (s0_reg_busy)
	);

	// Register file 0 (slave0 side-by-side, dual clock domain)
	apb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.NUM_RW_REGS (`NUM_RW_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file0 (
		.pclk           (s0_reg_clk),
		.prstn          (s0_reg_rstn),
		.sclk           (sclk),
		.srstn          (srstn),
		.wr_en          (s0_reg_wr_en),
		.addr           (s0_reg_addr),
		.wr_data        (s0_reg_wr_data),
		.rd_data        (s0_reg_rd_data),
		.err            (s0_reg_err),
		.busy           (s0_reg_busy),
		.local_wr_en    (s0_local_wr_en),
		.local_wr_addr  (s0_local_wr_addr),
		.local_wr_data  (s0_local_wr_data),
		.local_rd_addr  (s0_local_rd_addr),
		.local_rd_data  (s0_local_rd_data)
	);

	// -------------------------------------------------------------------------
	// Slave 1 (APB protocol adapter)
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
		.prdata         (prdata_s1),
		.pready         (pready_s1),
		.pslverr        (pslverr_s1),
		.reg_clk        (s1_reg_clk),
		.reg_rstn       (s1_reg_rstn),
		.reg_addr       (s1_reg_addr),
		.reg_wr_en      (s1_reg_wr_en),
		.reg_wr_data    (s1_reg_wr_data),
		.reg_rd_data    (s1_reg_rd_data),
		.reg_err        (s1_reg_err),
		.reg_busy       (s1_reg_busy)
	);

	// Register file 1 (slave1 side-by-side, dual clock domain)
	apb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.NUM_RW_REGS (`NUM_RW_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file1 (
		.pclk           (s1_reg_clk),
		.prstn          (s1_reg_rstn),
		.sclk           (sclk),
		.srstn          (srstn),
		.wr_en          (s1_reg_wr_en),
		.addr           (s1_reg_addr),
		.wr_data        (s1_reg_wr_data),
		.rd_data        (s1_reg_rd_data),
		.err            (s1_reg_err),
		.busy           (s1_reg_busy),
		.local_wr_en    (s1_local_wr_en),
		.local_wr_addr  (s1_local_wr_addr),
		.local_wr_data  (s1_local_wr_data),
		.local_rd_addr  (s1_local_rd_addr),
		.local_rd_data  (s1_local_rd_data)
	);

endmodule
