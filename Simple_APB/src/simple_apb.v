// =============================================================================
// Name:     simple_apb
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Top level: master + interconnect + 2x slave subsystem
// - Slave subsystem = APB interface + CDC bridge + peripheral-domain reg block
// - Register truth lives only in the peripheral clock domain
// =============================================================================

`include "simple_apb.vh"

module simple_apb #(
	parameter ADDR_WIDTH       = `APB_ADDR_WIDTH,
	parameter DATA_WIDTH       = `APB_DATA_WIDTH,
	parameter SLAVE_ADDR_WIDTH = ADDR_WIDTH - 1
) (
	input  wire                    pclk,
	input  wire                    presetn,

	// Peripheral clock domain
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

	// Slave 0 hardware-to-register (RO status into register block)
	input  wire [`NUM_RO_REGS*DATA_WIDTH-1:0]  s0_hw2reg_ro_value,
	// Slave 0 register-to-hardware (RW config out of register block)
	output wire [`NUM_RW_REGS*DATA_WIDTH-1:0]  s0_reg2hw_rw_value,
	output wire [`NUM_RW_REGS-1:0]             s0_reg2hw_rw_write_pulse,

	// Slave 1 hardware-to-register (RO status into register block)
	input  wire [`NUM_RO_REGS*DATA_WIDTH-1:0]  s1_hw2reg_ro_value,
	// Slave 1 register-to-hardware (RW config out of register block)
	output wire [`NUM_RW_REGS*DATA_WIDTH-1:0]  s1_reg2hw_rw_value,
	output wire [`NUM_RW_REGS-1:0]             s1_reg2hw_rw_write_pulse
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

	// Slave 0 interface <-> CDC bridge
	wire                      s0_req_valid_if;
	wire                      s0_req_write_if;
	wire [SLAVE_ADDR_WIDTH-1:0] s0_req_addr_if;
	wire [DATA_WIDTH-1:0]     s0_req_wdata_if;
	wire                      s0_rsp_ready_if;
	wire [DATA_WIDTH-1:0]     s0_rsp_rdata_if;
	wire                      s0_rsp_err_if;

	// Slave 0 CDC bridge <-> peripheral register block
	wire                      s0_req_valid_blk;
	wire                      s0_req_write_blk;
	wire [SLAVE_ADDR_WIDTH-1:0] s0_req_addr_blk;
	wire [DATA_WIDTH-1:0]     s0_req_wdata_blk;
	wire                      s0_rsp_ready_blk;
	wire [DATA_WIDTH-1:0]     s0_rsp_rdata_blk;
	wire                      s0_rsp_err_blk;

	// Slave 1 interface <-> CDC bridge
	wire                      s1_req_valid_if;
	wire                      s1_req_write_if;
	wire [SLAVE_ADDR_WIDTH-1:0] s1_req_addr_if;
	wire [DATA_WIDTH-1:0]     s1_req_wdata_if;
	wire                      s1_rsp_ready_if;
	wire [DATA_WIDTH-1:0]     s1_rsp_rdata_if;
	wire                      s1_rsp_err_if;

	// Slave 1 CDC bridge <-> peripheral register block
	wire                      s1_req_valid_blk;
	wire                      s1_req_write_blk;
	wire [SLAVE_ADDR_WIDTH-1:0] s1_req_addr_blk;
	wire [DATA_WIDTH-1:0]     s1_req_wdata_blk;
	wire                      s1_rsp_ready_blk;
	wire [DATA_WIDTH-1:0]     s1_rsp_rdata_blk;
	wire                      s1_rsp_err_blk;

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
	// Slave 0 APB interface
	// -------------------------------------------------------------------------
	apb_slave_interface #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave0_if (
		.pclk          (pclk),
		.presetn       (presetn),
		.psel          (psel_s0),
		.penable       (penable_s0),
		.pwrite        (pwrite_s0),
		.paddr         (paddr_s0),
		.pwdata        (pwdata_s0),
		.prdata        (prdata_s0),
		.pready        (pready_s0),
		.pslverr       (pslverr_s0),
		.reg_req_valid (s0_req_valid_if),
		.reg_req_write (s0_req_write_if),
		.reg_req_addr  (s0_req_addr_if),
		.reg_req_wdata (s0_req_wdata_if),
		.reg_rsp_ready (s0_rsp_ready_if),
		.reg_rsp_rdata (s0_rsp_rdata_if),
		.reg_rsp_err   (s0_rsp_err_if)
	);

	reg_cdc_bridge #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave0_cdc (
		.src_clk       (pclk),
		.src_rstn      (presetn),
		.src_req_valid (s0_req_valid_if),
		.src_req_write (s0_req_write_if),
		.src_req_addr  (s0_req_addr_if),
		.src_req_wdata (s0_req_wdata_if),
		.src_rsp_ready (s0_rsp_ready_if),
		.src_rsp_rdata (s0_rsp_rdata_if),
		.src_rsp_err   (s0_rsp_err_if),
		.dst_clk       (sclk),
		.dst_rstn      (srstn),
		.dst_req_valid (s0_req_valid_blk),
		.dst_req_write (s0_req_write_blk),
		.dst_req_addr  (s0_req_addr_blk),
		.dst_req_wdata (s0_req_wdata_blk),
		.dst_rsp_ready (s0_rsp_ready_blk),
		.dst_rsp_rdata (s0_rsp_rdata_blk),
		.dst_rsp_err   (s0_rsp_err_blk)
	);

	slave_reg_block #(
		.ADDR_WIDTH   (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH   (DATA_WIDTH),
		.NUM_REGS     (`NUM_REGS),
		.NUM_RO_REGS  (`NUM_RO_REGS),
		.NUM_RW_REGS  (`NUM_RW_REGS),
		.IDX_WIDTH    (`REG_IDX_WIDTH)
	) u_slave0_regs (
		.periph_clk            (sclk),
		.periph_rstn           (srstn),
		.reg_req_valid         (s0_req_valid_blk),
		.reg_req_write         (s0_req_write_blk),
		.reg_req_addr          (s0_req_addr_blk),
		.reg_req_wdata         (s0_req_wdata_blk),
		.reg_rsp_ready         (s0_rsp_ready_blk),
		.reg_rsp_rdata         (s0_rsp_rdata_blk),
		.reg_rsp_err           (s0_rsp_err_blk),
		.reg2hw_rw_value       (s0_reg2hw_rw_value),
		.reg2hw_rw_write_pulse (s0_reg2hw_rw_write_pulse),
		.hw2reg_ro_value       (s0_hw2reg_ro_value)
	);

	// -------------------------------------------------------------------------
	// Slave 1 APB interface
	// -------------------------------------------------------------------------
	apb_slave_interface #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave1_if (
		.pclk          (pclk),
		.presetn       (presetn),
		.psel          (psel_s1),
		.penable       (penable_s1),
		.pwrite        (pwrite_s1),
		.paddr         (paddr_s1),
		.pwdata        (pwdata_s1),
		.prdata        (prdata_s1),
		.pready        (pready_s1),
		.pslverr       (pslverr_s1),
		.reg_req_valid (s1_req_valid_if),
		.reg_req_write (s1_req_write_if),
		.reg_req_addr  (s1_req_addr_if),
		.reg_req_wdata (s1_req_wdata_if),
		.reg_rsp_ready (s1_rsp_ready_if),
		.reg_rsp_rdata (s1_rsp_rdata_if),
		.reg_rsp_err   (s1_rsp_err_if)
	);

	reg_cdc_bridge #(
		.ADDR_WIDTH (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_slave1_cdc (
		.src_clk       (pclk),
		.src_rstn      (presetn),
		.src_req_valid (s1_req_valid_if),
		.src_req_write (s1_req_write_if),
		.src_req_addr  (s1_req_addr_if),
		.src_req_wdata (s1_req_wdata_if),
		.src_rsp_ready (s1_rsp_ready_if),
		.src_rsp_rdata (s1_rsp_rdata_if),
		.src_rsp_err   (s1_rsp_err_if),
		.dst_clk       (sclk),
		.dst_rstn      (srstn),
		.dst_req_valid (s1_req_valid_blk),
		.dst_req_write (s1_req_write_blk),
		.dst_req_addr  (s1_req_addr_blk),
		.dst_req_wdata (s1_req_wdata_blk),
		.dst_rsp_ready (s1_rsp_ready_blk),
		.dst_rsp_rdata (s1_rsp_rdata_blk),
		.dst_rsp_err   (s1_rsp_err_blk)
	);

	slave_reg_block #(
		.ADDR_WIDTH   (SLAVE_ADDR_WIDTH),
		.DATA_WIDTH   (DATA_WIDTH),
		.NUM_REGS     (`NUM_REGS),
		.NUM_RO_REGS  (`NUM_RO_REGS),
		.NUM_RW_REGS  (`NUM_RW_REGS),
		.IDX_WIDTH    (`REG_IDX_WIDTH)
	) u_slave1_regs (
		.periph_clk            (sclk),
		.periph_rstn           (srstn),
		.reg_req_valid         (s1_req_valid_blk),
		.reg_req_write         (s1_req_write_blk),
		.reg_req_addr          (s1_req_addr_blk),
		.reg_req_wdata         (s1_req_wdata_blk),
		.reg_rsp_ready         (s1_rsp_ready_blk),
		.reg_rsp_rdata         (s1_rsp_rdata_blk),
		.reg_rsp_err           (s1_rsp_err_blk),
		.reg2hw_rw_value       (s1_reg2hw_rw_value),
		.reg2hw_rw_write_pulse (s1_reg2hw_rw_write_pulse),
		.hw2reg_ro_value       (s1_hw2reg_ro_value)
	);

endmodule
