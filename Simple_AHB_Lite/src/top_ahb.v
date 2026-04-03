// =============================================================================
// Name:     top_ahb
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Top level: master + interconnect + 2x (slave + reg_file) side-by-side
// - Each reg_file has 15 registers (reg0-4 RO, reg5-14 RW from AHB side)
// - Local write ports exposed for slave logic / testbench
// =============================================================================

`include "ahb_addr_def.vh"

module top_ahb #(
	parameter ADDR_WIDTH       = `AHB_ADDR_WIDTH,
	parameter DATA_WIDTH       = `AHB_DATA_WIDTH,
	parameter SLAVE_ADDR_WIDTH = ADDR_WIDTH - 1
) (
	input  wire                    hclk,
	input  wire                    hresetn,

	// Command interface
	input  wire                           start,
	input  wire                           write,
	input  wire [ADDR_WIDTH-1:0]          addr,
	input  wire [DATA_WIDTH-1:0]          wdata,
	output wire [DATA_WIDTH-1:0]          rdata,
	output wire                           done,
	output wire                           resp_err,

	// Slave 0 local write port (directly to reg_file0)
	input  wire                           s0_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s0_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s0_local_wr_data,

	// Slave 1 local write port (directly to reg_file1)
	input  wire                           s1_local_wr_en,
	input  wire [`REG_IDX_WIDTH-1:0]      s1_local_wr_addr,
	input  wire [DATA_WIDTH-1:0]          s1_local_wr_data
);

	// -------------------------------------------------------------------------
	// Internal AHB-Lite signals: master <-> interconnect
	// -------------------------------------------------------------------------
	wire [ADDR_WIDTH-1:0]   haddr_m;
	wire [1:0]              htrans_m;
	wire                    hwrite_m;
	wire [2:0]              hsize_m;
	wire [2:0]              hburst_m;
	wire [DATA_WIDTH-1:0]   hwdata_m;
	wire [DATA_WIDTH-1:0]   hrdata_m;
	wire                    hready_m;
	wire                    hresp_m;

	// AHB-Lite signals: interconnect <-> slave 0
	wire                        hsel_s0;
	wire [SLAVE_ADDR_WIDTH-1:0] haddr_s0;
	wire [1:0]                  htrans_s0;
	wire                        hwrite_s0;
	wire [2:0]                  hsize_s0;
	wire [DATA_WIDTH-1:0]       hwdata_s0;
	wire [DATA_WIDTH-1:0]       hrdata_s0;
	wire                        hreadyout_s0;
	wire                        hresp_s0;

	// AHB-Lite signals: interconnect <-> slave 1
	wire                        hsel_s1;
	wire [SLAVE_ADDR_WIDTH-1:0] haddr_s1;
	wire [1:0]                  htrans_s1;
	wire                        hwrite_s1;
	wire [2:0]                  hsize_s1;
	wire [DATA_WIDTH-1:0]       hwdata_s1;
	wire [DATA_WIDTH-1:0]       hrdata_s1;
	wire                        hreadyout_s1;
	wire                        hresp_s1;

	// Slave 0 <-> reg_file 0 interface
	wire [`REG_IDX_WIDTH-1:0]  s0_reg_addr;
	wire                       s0_reg_wr_en;
	wire [DATA_WIDTH-1:0]      s0_reg_wr_data;
	wire [DATA_WIDTH-1:0]      s0_reg_rd_data;
	wire                       s0_reg_addr_valid;
	wire                       s0_reg_wr_ro_err;
	wire                       s0_reg_busy;

	// Slave 1 <-> reg_file 1 interface
	wire [`REG_IDX_WIDTH-1:0]  s1_reg_addr;
	wire                       s1_reg_wr_en;
	wire [DATA_WIDTH-1:0]      s1_reg_wr_data;
	wire [DATA_WIDTH-1:0]      s1_reg_rd_data;
	wire                       s1_reg_addr_valid;
	wire                       s1_reg_wr_ro_err;
	wire                       s1_reg_busy;

	// -------------------------------------------------------------------------
	// Master (single-word AHB-Lite bridge)
	// -------------------------------------------------------------------------
	ahb_master #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_master (
		.hclk     (hclk),
		.hresetn  (hresetn),
		.start    (start),
		.write    (write),
		.addr     (addr),
		.wdata    (wdata),
		.rdata    (rdata),
		.done     (done),
		.resp_err (resp_err),
		.haddr    (haddr_m),
		.htrans   (htrans_m),
		.hwrite   (hwrite_m),
		.hsize    (hsize_m),
		.hburst   (hburst_m),
		.hwdata   (hwdata_m),
		.hrdata   (hrdata_m),
		.hready   (hready_m),
		.hresp    (hresp_m)
	);

	// -------------------------------------------------------------------------
	// Interconnect (1 master, 2 slaves)
	// -------------------------------------------------------------------------
	ahb_interconnect #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_interconnect (
		.haddr_m      (haddr_m),
		.htrans_m     (htrans_m),
		.hwrite_m     (hwrite_m),
		.hsize_m      (hsize_m),
		.hburst_m     (hburst_m),
		.hwdata_m     (hwdata_m),
		.hrdata_m     (hrdata_m),
		.hready_m     (hready_m),
		.hresp_m      (hresp_m),
		.hsel_s0      (hsel_s0),
		.haddr_s0     (haddr_s0),
		.htrans_s0    (htrans_s0),
		.hwrite_s0    (hwrite_s0),
		.hsize_s0     (hsize_s0),
		.hwdata_s0    (hwdata_s0),
		.hrdata_s0    (hrdata_s0),
		.hreadyout_s0 (hreadyout_s0),
		.hresp_s0     (hresp_s0),
		.hsel_s1      (hsel_s1),
		.haddr_s1     (haddr_s1),
		.htrans_s1    (htrans_s1),
		.hwrite_s1    (hwrite_s1),
		.hsize_s1     (hsize_s1),
		.hwdata_s1    (hwdata_s1),
		.hrdata_s1    (hrdata_s1),
		.hreadyout_s1 (hreadyout_s1),
		.hresp_s1     (hresp_s1)
	);

	// -------------------------------------------------------------------------
	// Slave 0 (AHB-Lite protocol adapter)
	// -------------------------------------------------------------------------
	ahb_slave #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave0 (
		.hclk           (hclk),
		.hresetn        (hresetn),
		.hsel           (hsel_s0),
		.haddr          (haddr_s0),
		.htrans         (htrans_s0),
		.hwrite         (hwrite_s0),
		.hsize          (hsize_s0),
		.hwdata         (hwdata_s0),
		.hrdata         (hrdata_s0),
		.hreadyout      (hreadyout_s0),
		.hresp          (hresp_s0),
		.reg_addr       (s0_reg_addr),
		.reg_wr_en      (s0_reg_wr_en),
		.reg_wr_data    (s0_reg_wr_data),
		.reg_rd_data    (s0_reg_rd_data),
		.reg_addr_valid (s0_reg_addr_valid),
		.reg_wr_ro_err  (s0_reg_wr_ro_err),
		.reg_busy       (s0_reg_busy)
	);

	// Register file 0 (slave0 side-by-side)
	ahb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file0 (
		.clk            (hclk),
		.rstn           (hresetn),
		.wr_en          (s0_reg_wr_en),
		.addr           (s0_reg_addr),
		.wr_data        (s0_reg_wr_data),
		.rd_data        (s0_reg_rd_data),
		.addr_valid     (s0_reg_addr_valid),
		.wr_ro_err      (s0_reg_wr_ro_err),
		.busy           (s0_reg_busy),
		.local_wr_en    (s0_local_wr_en),
		.local_wr_addr  (s0_local_wr_addr),
		.local_wr_data  (s0_local_wr_data)
	);

	// -------------------------------------------------------------------------
	// Slave 1 (AHB-Lite protocol adapter)
	// -------------------------------------------------------------------------
	ahb_slave #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave1 (
		.hclk           (hclk),
		.hresetn        (hresetn),
		.hsel           (hsel_s1),
		.haddr          (haddr_s1),
		.htrans         (htrans_s1),
		.hwrite         (hwrite_s1),
		.hsize          (hsize_s1),
		.hwdata         (hwdata_s1),
		.hrdata         (hrdata_s1),
		.hreadyout      (hreadyout_s1),
		.hresp          (hresp_s1),
		.reg_addr       (s1_reg_addr),
		.reg_wr_en      (s1_reg_wr_en),
		.reg_wr_data    (s1_reg_wr_data),
		.reg_rd_data    (s1_reg_rd_data),
		.reg_addr_valid (s1_reg_addr_valid),
		.reg_wr_ro_err  (s1_reg_wr_ro_err),
		.reg_busy       (s1_reg_busy)
	);

	// Register file 1 (slave1 side-by-side)
	ahb_reg_file #(
		.DATA_WIDTH  (DATA_WIDTH),
		.NUM_REGS    (`NUM_REGS),
		.NUM_RO_REGS (`NUM_RO_REGS),
		.IDX_WIDTH   (`REG_IDX_WIDTH)
	) u_reg_file1 (
		.clk            (hclk),
		.rstn           (hresetn),
		.wr_en          (s1_reg_wr_en),
		.addr           (s1_reg_addr),
		.wr_data        (s1_reg_wr_data),
		.rd_data        (s1_reg_rd_data),
		.addr_valid     (s1_reg_addr_valid),
		.wr_ro_err      (s1_reg_wr_ro_err),
		.busy           (s1_reg_busy),
		.local_wr_en    (s1_local_wr_en),
		.local_wr_addr  (s1_local_wr_addr),
		.local_wr_data  (s1_local_wr_data)
	);

endmodule
