// =============================================================================
// Name:     top_apb_tb
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - Testbench for APB system with register-file-based slaves
// - Tests: single RW read/write, RO protection, out-of-range, local write
// =============================================================================

`timescale 1ns / 1ps
`include "apb_addr_def.vh"

module top_apb_tb;

	// -------------------------------------------------------------------------
	// Parameters
	// -------------------------------------------------------------------------
	parameter ADDR_WIDTH = `APB_ADDR_WIDTH;
	parameter DATA_WIDTH = `APB_DATA_WIDTH;
	parameter CLK_PERIOD = 10;

	// -------------------------------------------------------------------------
	// DUT signals
	// -------------------------------------------------------------------------
	reg                           pclk;
	reg                           presetn;

	// Command interface
	reg                           start;
	reg                           write;
	reg  [ADDR_WIDTH-1:0]         addr;
	reg  [DATA_WIDTH-1:0]         wdata;
	reg  [DATA_WIDTH/8-1:0]       strb;
	wire [DATA_WIDTH-1:0]         rdata;
	wire                          done;
	wire                          slverr;

	// Slave 0 local port
	reg                           s0_local_wr_en;
	reg  [`REG_IDX_WIDTH-1:0]     s0_local_wr_addr;
	reg  [DATA_WIDTH-1:0]         s0_local_wr_data;
	reg                           s0_local_ready;

	// Slave 1 local port
	reg                           s1_local_wr_en;
	reg  [`REG_IDX_WIDTH-1:0]     s1_local_wr_addr;
	reg  [DATA_WIDTH-1:0]         s1_local_wr_data;
	reg                           s1_local_ready;

	// -------------------------------------------------------------------------
	// DUT
	// -------------------------------------------------------------------------
	top_apb #(
		.ADDR_WIDTH (ADDR_WIDTH),
		.DATA_WIDTH (DATA_WIDTH)
	) u_dut (
		.pclk             (pclk),
		.presetn          (presetn),
		.start            (start),
		.write            (write),
		.addr             (addr),
		.wdata            (wdata),
		.strb             (strb),
		.rdata            (rdata),
		.done             (done),
		.slverr           (slverr),
		.s0_local_wr_en   (s0_local_wr_en),
		.s0_local_wr_addr (s0_local_wr_addr),
		.s0_local_wr_data (s0_local_wr_data),
		.s0_local_ready   (s0_local_ready),
		.s1_local_wr_en   (s1_local_wr_en),
		.s1_local_wr_addr (s1_local_wr_addr),
		.s1_local_wr_data (s1_local_wr_data),
		.s1_local_ready   (s1_local_ready)
	);

	// -------------------------------------------------------------------------
	// Clock generation
	// -------------------------------------------------------------------------
	initial pclk = 0;
	always #(CLK_PERIOD/2) pclk = ~pclk;

	// -------------------------------------------------------------------------
	// Error counter
	// -------------------------------------------------------------------------
	integer err_cnt;

	// -------------------------------------------------------------------------
	// Helper task: APB write
	// -------------------------------------------------------------------------
	task automatic apb_write(
		input [ADDR_WIDTH-1:0] t_addr,
		input [DATA_WIDTH-1:0] t_data
	);
	begin
		@(posedge pclk);
		write <= 1'b1;
		addr  <= t_addr;
		wdata <= t_data;
		strb  <= {DATA_WIDTH/8{1'b1}};
		start <= 1'b1;
		@(posedge pclk);
		start <= 1'b0;
		wait (done === 1'b1);
		@(posedge pclk);
	end
	endtask

	// -------------------------------------------------------------------------
	// Helper task: APB read
	// -------------------------------------------------------------------------
	task automatic apb_read(
		input [ADDR_WIDTH-1:0] t_addr
	);
	begin
		@(posedge pclk);
		write <= 1'b0;
		addr  <= t_addr;
		wdata <= {DATA_WIDTH{1'b0}};
		strb  <= {DATA_WIDTH/8{1'b0}};
		start <= 1'b1;
		@(posedge pclk);
		start <= 1'b0;
		wait (done === 1'b1);
		@(posedge pclk);
	end
	endtask

	// -------------------------------------------------------------------------
	// Helper task: check rdata after read
	// -------------------------------------------------------------------------
	task automatic check_rdata(
		input [DATA_WIDTH-1:0] expected,
		input [8*40-1:0]       msg
	);
	begin
		if (rdata !== expected) begin
			$display("[FAIL] %0s: got 0x%08h, expected 0x%08h", msg, rdata, expected);
			err_cnt = err_cnt + 1;
		end else begin
			$display("[PASS] %0s: 0x%08h", msg, rdata);
		end
	end
	endtask

	// -------------------------------------------------------------------------
	// Helper task: check slverr after transfer
	// -------------------------------------------------------------------------
	task automatic check_slverr(
		input        expected,
		input [8*40-1:0] msg
	);
	begin
		if (slverr !== expected) begin
			$display("[FAIL] %0s: slverr=%0b, expected=%0b", msg, slverr, expected);
			err_cnt = err_cnt + 1;
		end else begin
			$display("[PASS] %0s: slverr=%0b", msg, slverr);
		end
	end
	endtask

	// -------------------------------------------------------------------------
	// Helper task: local write to slave register
	// -------------------------------------------------------------------------
	task automatic local_write_s0(
		input [`REG_IDX_WIDTH-1:0] reg_idx,
		input [DATA_WIDTH-1:0]     data
	);
	begin
		@(posedge pclk);
		s0_local_wr_en   <= 1'b1;
		s0_local_wr_addr <= reg_idx;
		s0_local_wr_data <= data;
		@(posedge pclk);
		s0_local_wr_en   <= 1'b0;
	end
	endtask

	task automatic local_write_s1(
		input [`REG_IDX_WIDTH-1:0] reg_idx,
		input [DATA_WIDTH-1:0]     data
	);
	begin
		@(posedge pclk);
		s1_local_wr_en   <= 1'b1;
		s1_local_wr_addr <= reg_idx;
		s1_local_wr_data <= data;
		@(posedge pclk);
		s1_local_wr_en   <= 1'b0;
	end
	endtask

	// -------------------------------------------------------------------------
	// Main test sequence
	// -------------------------------------------------------------------------
	integer k;

	initial begin
		$dumpfile("top_apb_tb.vcd");
		$dumpvars(0, top_apb_tb);

		err_cnt          = 0;
		presetn          = 0;
		start            = 0;
		write            = 0;
		addr             = 0;
		wdata            = 0;
		strb             = 0;
		s0_local_wr_en   = 0;
		s0_local_wr_addr = 0;
		s0_local_wr_data = 0;
		s0_local_ready   = 1;
		s1_local_wr_en   = 0;
		s1_local_wr_addr = 0;
		s1_local_wr_data = 0;
		s1_local_ready   = 1;

		// Reset
		repeat (5) @(posedge pclk);
		presetn = 1;
		repeat (2) @(posedge pclk);

		// =================================================================
		// Test 1: Local write to slave 0 RO regs, APB read back
		// =================================================================
		$display("\n========== Test 1: Local write slave 0 RO regs, APB read ==========");
		for (k = 0; k < `NUM_RO_REGS; k = k + 1) begin
			local_write_s0(k[`REG_IDX_WIDTH-1:0], 32'hAA00_0000 + k);
		end
		for (k = 0; k < `NUM_RO_REGS; k = k + 1) begin
			apb_read(`SLV0_BASE_ADDR + {k[9:0], 2'b00});
			check_rdata(32'hAA00_0000 + k, "s0 RO reg read");
		end

		// =================================================================
		// Test 2: Local write to slave 1 RO regs, APB read back
		// =================================================================
		$display("\n========== Test 2: Local write slave 1 RO regs, APB read ==========");
		for (k = 0; k < `NUM_RO_REGS; k = k + 1) begin
			local_write_s1(k[`REG_IDX_WIDTH-1:0], 32'hBB00_0000 + k);
		end
		for (k = 0; k < `NUM_RO_REGS; k = k + 1) begin
			apb_read(`SLV1_BASE_ADDR + {k[9:0], 2'b00});
			check_rdata(32'hBB00_0000 + k, "s1 RO reg read");
		end

		// =================================================================
		// Test 3: APB write to RO register -> PSLVERR
		// =================================================================
		$display("\n========== Test 3: APB write to RO reg -> PSLVERR ==========");
		apb_write(`SLV0_BASE_ADDR + `REG0_OFFSET, 32'hFFFF_FFFF);
		check_slverr(1'b1, "s0 RO write err");
		// Verify data unchanged
		apb_read(`SLV0_BASE_ADDR + `REG0_OFFSET);
		check_rdata(32'hAA00_0000, "s0 RO unchanged");

		// =================================================================
		// Test 4: APB write/read slave 0 RW register (reg5)
		// =================================================================
		$display("\n========== Test 4: APB write/read slave 0 reg5 ==========");
		apb_write(`SLV0_BASE_ADDR + `REG5_OFFSET, 32'hDEAD_BEEF);
		check_slverr(1'b0, "s0 RW write ok");
		apb_read(`SLV0_BASE_ADDR + `REG5_OFFSET);
		check_rdata(32'hDEAD_BEEF, "s0 reg5 read");

		// =================================================================
		// Test 5: APB write/read slave 0 RW register (reg14, last valid)
		// =================================================================
		$display("\n========== Test 5: APB write/read slave 0 reg14 ==========");
		apb_write(`SLV0_BASE_ADDR + `REG14_OFFSET, 32'hCAFE_BABE);
		check_slverr(1'b0, "s0 reg14 write ok");
		apb_read(`SLV0_BASE_ADDR + `REG14_OFFSET);
		check_rdata(32'hCAFE_BABE, "s0 reg14 read");

		// =================================================================
		// Test 6: APB write/read slave 1 RW register (reg5)
		// =================================================================
		$display("\n========== Test 6: APB write/read slave 1 reg5 ==========");
		apb_write(`SLV1_BASE_ADDR + `REG5_OFFSET, 32'h1234_5678);
		check_slverr(1'b0, "s1 RW write ok");
		apb_read(`SLV1_BASE_ADDR + `REG5_OFFSET);
		check_rdata(32'h1234_5678, "s1 reg5 read");

		// =================================================================
		// Test 7: Write all 10 RW regs of slave 0, read all back
		// =================================================================
		$display("\n========== Test 7: Write/read all slave 0 RW regs ==========");
		for (k = 0; k < `NUM_RW_REGS; k = k + 1) begin
			apb_write(`SLV0_BASE_ADDR + {(k[9:0] + 10'd5), 2'b00}, 32'hC000_0000 + k);
		end
		for (k = 0; k < `NUM_RW_REGS; k = k + 1) begin
			apb_read(`SLV0_BASE_ADDR + {(k[9:0] + 10'd5), 2'b00});
			check_rdata(32'hC000_0000 + k, "s0 RW bulk read");
		end

		// =================================================================
		// Test 8: Write all 10 RW regs of slave 1, read all back
		// =================================================================
		$display("\n========== Test 8: Write/read all slave 1 RW regs ==========");
		for (k = 0; k < `NUM_RW_REGS; k = k + 1) begin
			apb_write(`SLV1_BASE_ADDR + {(k[9:0] + 10'd5), 2'b00}, 32'hD000_0000 + k);
		end
		for (k = 0; k < `NUM_RW_REGS; k = k + 1) begin
			apb_read(`SLV1_BASE_ADDR + {(k[9:0] + 10'd5), 2'b00});
			check_rdata(32'hD000_0000 + k, "s1 RW bulk read");
		end

		// =================================================================
		// Test 9: Out-of-range access (reg15, byte addr 0x3C) -> PSLVERR
		// =================================================================
		$display("\n========== Test 9: Out-of-range access -> PSLVERR ==========");
		apb_write(`SLV0_BASE_ADDR + 12'h3C, 32'hFFFF_FFFF);
		check_slverr(1'b1, "s0 OOR write err");
		apb_read(`SLV1_BASE_ADDR + 12'h3C);
		check_slverr(1'b0, "s1 OOR read no err");

		// =================================================================
		// Test 10: Register overwrite verification
		// =================================================================
		$display("\n========== Test 10: RW register overwrite ==========");
		apb_write(`SLV0_BASE_ADDR + `REG5_OFFSET, 32'h1111_1111);
		apb_read(`SLV0_BASE_ADDR + `REG5_OFFSET);
		check_rdata(32'h1111_1111, "s0 reg5 overwrite1");
		apb_write(`SLV0_BASE_ADDR + `REG5_OFFSET, 32'h2222_2222);
		apb_read(`SLV0_BASE_ADDR + `REG5_OFFSET);
		check_rdata(32'h2222_2222, "s0 reg5 overwrite2");

		// =================================================================
		// Test 11: Local write + APB read (verify local port works on RW)
		// =================================================================
		$display("\n========== Test 11: Local write + APB read ==========");
		local_write_s0(4'd7, 32'hFACE_FACE);
		apb_read(`SLV0_BASE_ADDR + `REG7_OFFSET);
		check_rdata(32'hFACE_FACE, "s0 local wr->APB rd");

		// =================================================================
		// Test 12: Wait states via local_ready control
		// =================================================================
		$display("\n========== Test 12: Wait states (local_ready) ==========");
		// Write a known value first
		apb_write(`SLV0_BASE_ADDR + `REG6_OFFSET, 32'hAAAA_BBBB);
		// De-assert ready on slave 0, start a read
		s0_local_ready = 0;
		@(posedge pclk);
		write <= 1'b0;
		addr  <= `SLV0_BASE_ADDR + `REG6_OFFSET;
		start <= 1'b1;
		@(posedge pclk);
		start <= 1'b0;
		// Wait a few cycles while slave holds off
		repeat (3) @(posedge pclk);
		// Verify done has NOT fired yet
		if (done === 1'b1) begin
			$display("[FAIL] done asserted while local_ready=0");
			err_cnt = err_cnt + 1;
		end else begin
			$display("[PASS] transfer stalled while local_ready=0");
		end
		// Re-assert ready, transfer should complete
		s0_local_ready = 1;
		wait (done === 1'b1);
		@(posedge pclk);
		check_rdata(32'hAAAA_BBBB, "s0 wait-state read");

		// =================================================================
		// Summary
		// =================================================================
		repeat (5) @(posedge pclk);
		$display("\n==========================================");
		if (err_cnt == 0)
			$display("  ALL TESTS PASSED");
		else
			$display("  FAILED: %0d errors", err_cnt);
		$display("==========================================\n");
		$finish;
	end

	// -------------------------------------------------------------------------
	// Timeout watchdog
	// -------------------------------------------------------------------------
	initial begin
		#200000;
		$display("[ERROR] Simulation timeout!");
		$finish;
	end

endmodule
