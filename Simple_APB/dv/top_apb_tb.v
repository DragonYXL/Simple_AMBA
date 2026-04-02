// =============================================================================
// Testbench for Simple APB system
// Test cases:
//   1-2. Single word write/read to slave 0 (RD_LATENCY=1, zero wait)
//   3-4. Block write/read to slave 0  (4 words)
//   5-6. Single word write/read to slave 1 (RD_LATENCY=3, 2 wait states)
//   7-8. Block write/read to slave 1  (4 words, with wait states)
//   9.   Error: out-of-range address → PSLVERR
// =============================================================================

`timescale 1ns / 1ps

module top_apb_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter ADDR_WIDTH      = 13;
    parameter DATA_WIDTH      = 32;
    parameter RAM_DEPTH       = 16;     // small for TB
    parameter LOCAL_RAM_DEPTH = 16;
    parameter CLK_PERIOD      = 10;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    reg                    pclk;
    reg                    presetn;
    reg                    start;
    reg                    rw;
    reg  [ADDR_WIDTH-1:0]  apb_base;
    reg  [$clog2(LOCAL_RAM_DEPTH)-1:0] local_base;
    reg  [7:0]             length;
    wire                   done;

    // -------------------------------------------------------------------------
    // DUT: slave 0 = RD_LATENCY 1 (0 wait), slave 1 = RD_LATENCY 3 (2 wait)
    // -------------------------------------------------------------------------
    top_apb #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .RAM_DEPTH      (RAM_DEPTH),
        .LOCAL_RAM_DEPTH(LOCAL_RAM_DEPTH),
        .S0_RD_LATENCY  (1),
        .S1_RD_LATENCY  (3)
    ) u_dut (
        .pclk       (pclk),
        .presetn    (presetn),
        .start      (start),
        .rw         (rw),
        .apb_base   (apb_base),
        .local_base (local_base),
        .length     (length),
        .done       (done)
    );

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial pclk = 0;
    always #(CLK_PERIOD/2) pclk = ~pclk;

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------
    integer err_cnt;

    task automatic do_transfer(
        input        t_rw,
        input [ADDR_WIDTH-1:0]  t_apb_base,
        input [$clog2(LOCAL_RAM_DEPTH)-1:0] t_local_base,
        input [7:0]  t_length
    );
    begin
        @(posedge pclk);
        rw         <= t_rw;
        apb_base   <= t_apb_base;
        local_base <= t_local_base;
        length     <= t_length;
        start      <= 1'b1;
        @(posedge pclk);
        start      <= 1'b0;
        // Wait for done
        wait (done === 1'b1);
        @(posedge pclk);
    end
    endtask

    task automatic check_slave_ram(
        input integer slave_id,
        input integer offset,
        input [DATA_WIDTH-1:0] expected
    );
    reg [DATA_WIDTH-1:0] actual;
    begin
        if (slave_id == 0)
            actual = u_dut.u_slave0.u_ram.mem[offset];
        else
            actual = u_dut.u_slave1.u_ram.mem[offset];

        if (actual !== expected) begin
            $display("[FAIL] slave%0d.ram[%0d] = 0x%08h, expected 0x%08h",
                     slave_id, offset, actual, expected);
            err_cnt = err_cnt + 1;
        end else begin
            $display("[PASS] slave%0d.ram[%0d] = 0x%08h",
                     slave_id, offset, actual);
        end
    end
    endtask

    task automatic check_local_ram(
        input integer offset,
        input [DATA_WIDTH-1:0] expected
    );
    reg [DATA_WIDTH-1:0] actual;
    begin
        actual = u_dut.u_master.u_local_ram.mem[offset];
        if (actual !== expected) begin
            $display("[FAIL] local_ram[%0d] = 0x%08h, expected 0x%08h",
                     offset, actual, expected);
            err_cnt = err_cnt + 1;
        end else begin
            $display("[PASS] local_ram[%0d] = 0x%08h",
                     offset, actual);
        end
    end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    integer k;

    initial begin
        $dumpfile("top_apb_tb.vcd");
        $dumpvars(0, top_apb_tb);

        err_cnt    = 0;
        presetn    = 0;
        start      = 0;
        rw         = 0;
        apb_base   = 0;
        local_base = 0;
        length     = 0;

        // Reset
        repeat (5) @(posedge pclk);
        presetn = 1;
        repeat (2) @(posedge pclk);

        // =================================================================
        // Test 1: Single word write to slave 0 (zero wait state)
        // =================================================================
        $display("\n========== Test 1: Single write to slave 0 ==========");
        u_dut.u_master.u_local_ram.mem[0] = 32'hDEAD_BEEF;
        do_transfer(
            .t_rw        (1'b1),
            .t_apb_base  (13'h0000),
            .t_local_base(4'd0),
            .t_length    (8'd1)
        );
        check_slave_ram(0, 0, 32'hDEAD_BEEF);

        // =================================================================
        // Test 2: Single word read back from slave 0
        // =================================================================
        $display("\n========== Test 2: Single read from slave 0 ==========");
        u_dut.u_master.u_local_ram.mem[8] = 32'h0;
        do_transfer(
            .t_rw        (1'b0),
            .t_apb_base  (13'h0000),
            .t_local_base(4'd8),
            .t_length    (8'd1)
        );
        check_local_ram(8, 32'hDEAD_BEEF);

        // =================================================================
        // Test 3: Block write to slave 0 (4 words)
        // =================================================================
        $display("\n========== Test 3: Block write 4 words to slave 0 ==========");
        for (k = 0; k < 4; k = k + 1)
            u_dut.u_master.u_local_ram.mem[k] = 32'hA000_0000 + k;
        do_transfer(
            .t_rw        (1'b1),
            .t_apb_base  (13'h0010),   // slave 0, word offset 4
            .t_local_base(4'd0),
            .t_length    (8'd4)
        );
        for (k = 0; k < 4; k = k + 1)
            check_slave_ram(0, 4 + k, 32'hA000_0000 + k);

        // =================================================================
        // Test 4: Block read back from slave 0 (4 words)
        // =================================================================
        $display("\n========== Test 4: Block read 4 words from slave 0 ==========");
        for (k = 0; k < 4; k = k + 1)
            u_dut.u_master.u_local_ram.mem[4 + k] = 32'h0;
        do_transfer(
            .t_rw        (1'b0),
            .t_apb_base  (13'h0010),
            .t_local_base(4'd4),
            .t_length    (8'd4)
        );
        for (k = 0; k < 4; k = k + 1)
            check_local_ram(4 + k, 32'hA000_0000 + k);

        // =================================================================
        // Test 5: Single word write to slave 1 (2 wait states on read)
        // =================================================================
        $display("\n========== Test 5: Single write to slave 1 (multi-cycle) ==========");
        u_dut.u_master.u_local_ram.mem[0] = 32'hCAFE_BABE;
        do_transfer(
            .t_rw        (1'b1),
            .t_apb_base  (13'h1000),   // slave 1, offset 0
            .t_local_base(4'd0),
            .t_length    (8'd1)
        );
        check_slave_ram(1, 0, 32'hCAFE_BABE);

        // =================================================================
        // Test 6: Single word read from slave 1 (2 wait states)
        // =================================================================
        $display("\n========== Test 6: Single read from slave 1 (multi-cycle) ==========");
        u_dut.u_master.u_local_ram.mem[0] = 32'h0;
        do_transfer(
            .t_rw        (1'b0),
            .t_apb_base  (13'h1000),
            .t_local_base(4'd0),
            .t_length    (8'd1)
        );
        check_local_ram(0, 32'hCAFE_BABE);

        // =================================================================
        // Test 7: Block write to slave 1 (4 words, with wait states)
        // =================================================================
        $display("\n========== Test 7: Block write 4 words to slave 1 (multi-cycle) ==========");
        for (k = 0; k < 4; k = k + 1)
            u_dut.u_master.u_local_ram.mem[k] = 32'hB000_0000 + k;
        do_transfer(
            .t_rw        (1'b1),
            .t_apb_base  (13'h1004),   // slave 1, word offset 1
            .t_local_base(4'd0),
            .t_length    (8'd4)
        );
        for (k = 0; k < 4; k = k + 1)
            check_slave_ram(1, 1 + k, 32'hB000_0000 + k);

        // =================================================================
        // Test 8: Block read from slave 1 (4 words, with wait states)
        // =================================================================
        $display("\n========== Test 8: Block read 4 words from slave 1 (multi-cycle) ==========");
        for (k = 0; k < 4; k = k + 1)
            u_dut.u_master.u_local_ram.mem[8 + k] = 32'h0;
        do_transfer(
            .t_rw        (1'b0),
            .t_apb_base  (13'h1004),
            .t_local_base(4'd8),
            .t_length    (8'd4)
        );
        for (k = 0; k < 4; k = k + 1)
            check_local_ram(8 + k, 32'hB000_0000 + k);

        // =================================================================
        // Test 9: Error — access out-of-range address (PSLVERR)
        // =================================================================
        $display("\n========== Test 9: Out-of-range access (PSLVERR) ==========");
        // RAM_DEPTH=16 → valid byte range 0x00-0x3F, address 0x100 is out of range
        u_dut.u_master.u_local_ram.mem[0] = 32'hFFFF_FFFF;
        do_transfer(
            .t_rw        (1'b1),
            .t_apb_base  (13'h0100),   // slave 0, out-of-range
            .t_local_base(4'd0),
            .t_length    (8'd1)
        );
        $display("[INFO] Out-of-range write completed — PSLVERR expected on bus");

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
        #100000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
