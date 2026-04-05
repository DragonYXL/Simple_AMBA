// =============================================================================
// Name:     top_apb_tb
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - Testbench for simple_apb top level
// - Async clocks: pclk 100MHz, slv_clk 70MHz (slower than pclk)
// - Test cases:
//     1. Write & readback on slave 0 RW registers
//     2. Write & readback on slave 1 RW registers
//     3. Read slave 0 RO registers driven by hw2reg
//     4. Error: write to RO register
//     5. Error: access out-of-range address
//     6. Error: access unaligned address
// =============================================================================

`timescale 1ns / 1ps

`include "simple_apb.vh"

module top_apb_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam ADDR_WIDTH = `APB_ADDR_WIDTH;
    localparam DATA_WIDTH = `APB_DATA_WIDTH;
    localparam NUM_RO     = `NUM_RO_REGS;
    localparam NUM_RW     = `NUM_RW_REGS;

    localparam PCLK_PERIOD    = 10;  // 100 MHz
    localparam SLVCLK_PERIOD  = 25;  // 40 MHz (slower than pclk)

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                          pclk;
    reg                          presetn;
    reg                          slv_clk;
    reg                          slv_rstn;

    reg                          start;
    reg                          write;
    reg  [ADDR_WIDTH-1:0]        addr;
    reg  [DATA_WIDTH-1:0]        wdata;
    wire [DATA_WIDTH-1:0]        rdata;
    wire                         done;
    wire                         slverr;

    reg  [NUM_RO*DATA_WIDTH-1:0] s0_hw2reg_ro_value;
    wire [NUM_RW*DATA_WIDTH-1:0] s0_reg2hw_rw_value;
    wire [NUM_RW-1:0]            s0_reg2hw_rw_write_pulse;

    reg  [NUM_RO*DATA_WIDTH-1:0] s1_hw2reg_ro_value;
    wire [NUM_RW*DATA_WIDTH-1:0] s1_reg2hw_rw_value;
    wire [NUM_RW-1:0]            s1_reg2hw_rw_write_pulse;

    // -------------------------------------------------------------------------
    // Clock generation (async: no phase relationship)
    // -------------------------------------------------------------------------
    initial
        pclk    = 1'b0;
    initial
        slv_clk = 1'b0;
    always #(PCLK_PERIOD / 2)    pclk    = ~pclk;
    always #(SLVCLK_PERIOD / 2)  slv_clk = ~slv_clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    simple_apb #(
                   .ADDR_WIDTH (ADDR_WIDTH),
                   .DATA_WIDTH (DATA_WIDTH)
               ) u_dut (
                   .pclk                      (pclk),
                   .presetn                   (presetn),
                   .slv_clk                   (slv_clk),
                   .slv_rstn                  (slv_rstn),
                   .start                     (start),
                   .write                     (write),
                   .addr                      (addr),
                   .wdata                     (wdata),
                   .rdata                     (rdata),
                   .done                      (done),
                   .slverr                    (slverr),
                   .s0_hw2reg_ro_value        (s0_hw2reg_ro_value),
                   .s0_reg2hw_rw_value        (s0_reg2hw_rw_value),
                   .s0_reg2hw_rw_write_pulse  (s0_reg2hw_rw_write_pulse),
                   .s1_hw2reg_ro_value        (s1_hw2reg_ro_value),
                   .s1_reg2hw_rw_value        (s1_reg2hw_rw_value),
                   .s1_reg2hw_rw_write_pulse  (s1_reg2hw_rw_write_pulse)
               );

    // -------------------------------------------------------------------------
    // Test infrastructure
    // -------------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer test_id;

    reg [DATA_WIDTH-1:0] rd_val;

    task apb_write;
        input [ADDR_WIDTH-1:0] wr_addr;
        input [DATA_WIDTH-1:0] wr_data;
        begin
            test_id = test_id + 1;
            @(posedge pclk);
            start <= 1'b1;
            write <= 1'b1;
            addr  <= wr_addr;
            wdata <= wr_data;
            @(posedge pclk);
            start <= 1'b0;
            // Poll done at each posedge (xsim-safe)
            while (!done)
                @(posedge pclk);
            @(posedge pclk);
        end
    endtask

    task apb_read;
        input  [ADDR_WIDTH-1:0] rd_addr;
        output [DATA_WIDTH-1:0] rd_data;
        begin
            test_id = test_id + 1;
            @(posedge pclk);
            start <= 1'b1;
            write <= 1'b0;
            addr  <= rd_addr;
            wdata <= {DATA_WIDTH{1'b0}};
            @(posedge pclk);
            start <= 1'b0;
            // Poll done at each posedge (xsim-safe)
            while (!done)
                @(posedge pclk);
            @(posedge pclk);
            rd_data = rdata;
            @(posedge pclk);
        end
    endtask

    task check_val;
        input [DATA_WIDTH-1:0] actual;
        input [DATA_WIDTH-1:0] expect_val;
        input [255:0]          msg;
        begin
            if (actual === expect_val) begin
                $display("[PASS] Test %0d: %0s  (got 0x%08h)", test_id, msg, actual);
                pass_cnt = pass_cnt + 1;
            end
            else begin
                $display("[FAIL] Test %0d: %0s  expect=0x%08h got=0x%08h", test_id, msg, expect_val, actual);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check_err;
        input            got_err;
        input            expect_err;
        input [255:0]    msg;
        begin
            if (got_err === expect_err) begin
                $display("[PASS] Test %0d: %0s  (slverr=%0b)", test_id, msg, got_err);
                pass_cnt = pass_cnt + 1;
            end
            else begin
                $display("[FAIL] Test %0d: %0s  expect_err=%0b got_err=%0b", test_id, msg, expect_err, got_err);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Capture slverr on done beat (combinational, only valid when done=1)
    // -------------------------------------------------------------------------
    reg last_slverr;
    always @(posedge pclk or negedge presetn) begin
        if(!presetn)
            last_slverr <= 1'b0;
        else if (done)
            last_slverr <= slverr;
    end

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------


    initial begin
        $display("==========================================================");
        $display("  Simple APB Testbench  -  Async clocks pclk/slv_clk");
        $display("==========================================================");

        pass_cnt = 0;
        fail_cnt = 0;
        test_id = 0;

        // Initialize
        presetn = 1'b0;
        slv_rstn = 1'b0;
        start   = 1'b0;
        write   = 1'b0;
        addr    = {ADDR_WIDTH{1'b0}};
        wdata   = {DATA_WIDTH{1'b0}};

        // Drive hw2reg RO values (static during test)
        s0_hw2reg_ro_value = {32'hDEAD_0004, 32'hDEAD_0003, 32'hDEAD_0002, 32'hDEAD_0001, 32'hDEAD_0000};
        s1_hw2reg_ro_value = {32'hBEEF_0004, 32'hBEEF_0003, 32'hBEEF_0002, 32'hBEEF_0001, 32'hBEEF_0000};

        // Reset release
        repeat (10) @(posedge pclk);
        presetn = 1'b1;
        repeat (3) @(posedge slv_clk);
        slv_rstn = 1'b1;
        repeat (5) @(posedge pclk);

        // =================================================================
        // Test group 1: Slave 0 RW write & readback
        // =================================================================
        $display("\n--- Group 1: Slave 0 RW write & readback ---");

        // Write 0xAAAA_5555 to slave0 REG5 (offset 0x14)
        apb_write(13'h0014, 32'hAAAA_5555);
        check_err(last_slverr, 1'b0, "S0 write REG5 no error");

        // Read back
        apb_read(13'h0014, rd_val);
        check_val(rd_val, 32'hAAAA_5555, "S0 readback REG5");

        // Write 0x1234_5678 to slave0 REG14 (offset 0x38, last RW)
        apb_write(13'h0038, 32'h1234_5678);
        check_err(last_slverr, 1'b0, "S0 write REG14 no error");

        apb_read(13'h0038, rd_val);
        check_val(rd_val, 32'h1234_5678, "S0 readback REG14");

        // =================================================================
        // Test group 2: Slave 1 RW write & readback
        // =================================================================
        $display("\n--- Group 2: Slave 1 RW write & readback ---");

        // Slave 1 base = 0x1000, REG5 offset = 0x14 -> addr = 0x1014
        apb_write(13'h1014, 32'hCAFE_BABE);
        check_err(last_slverr, 1'b0, "S1 write REG5 no error");

        apb_read(13'h1014, rd_val);
        check_val(rd_val, 32'hCAFE_BABE, "S1 readback REG5");

        // Slave 1 REG10 offset 0x28 -> addr = 0x1028
        apb_write(13'h1028, 32'h0000_FFFF);
        check_err(last_slverr, 1'b0, "S1 write REG10 no error");

        apb_read(13'h1028, rd_val);
        check_val(rd_val, 32'h0000_FFFF, "S1 readback REG10");

        // =================================================================
        // Test group 3: Slave 0 RO read (hw2reg values)
        // =================================================================
        $display("\n--- Group 3: Slave 0 RO read (hw2reg) ---");

        apb_read(13'h0000, rd_val);  // REG0
        check_val(rd_val, 32'hDEAD_0000, "S0 read REG0 (RO)");

        apb_read(13'h0004, rd_val);  // REG1
        check_val(rd_val, 32'hDEAD_0001, "S0 read REG1 (RO)");

        apb_read(13'h0010, rd_val);  // REG4 (last RO)
        check_val(rd_val, 32'hDEAD_0004, "S0 read REG4 (RO)");

        // =================================================================
        // Test group 4: Error - write to RO register
        // =================================================================
        $display("\n--- Group 4: Error - write to RO register ---");

        // Write to slave0 REG0 (RO) -> should get slverr
        apb_write(13'h0000, 32'hBAD0_BAD0);
        check_err(last_slverr, 1'b1, "S0 write REG0 (RO) -> slverr");

        // Verify REG0 unchanged
        apb_read(13'h0000, rd_val);
        check_val(rd_val, 32'hDEAD_0000, "S0 REG0 unchanged after RO write");

        // Write to slave1 REG3 (RO, addr = 0x100C) -> should get slverr
        apb_write(13'h100C, 32'hBAD1_BAD1);
        check_err(last_slverr, 1'b1, "S1 write REG3 (RO) -> slverr");

        // =================================================================
        // Test group 5: Error - out-of-range address
        // =================================================================
        $display("\n--- Group 5: Error - out-of-range address ---");

        // Slave 0 offset 0x3C -> index 15, out of range (only 0-14 valid)
        apb_write(13'h003C, 32'h0000_0001);
        check_err(last_slverr, 1'b1, "S0 write 0x3C (OOR) -> slverr");

        apb_read(13'h003C, rd_val);
        check_err(last_slverr, 1'b1, "S0 read 0x3C (OOR) -> slverr");

        // Slave 0 offset 0x40 -> beyond register space
        apb_read(13'h0040, rd_val);
        check_err(last_slverr, 1'b1, "S0 read 0x40 (OOR) -> slverr");

        // =================================================================
        // Test group 6: Error - unaligned address
        // =================================================================
        $display("\n--- Group 6: Error - unaligned address ---");

        // Slave 0 offset 0x01 -> unaligned
        apb_write(13'h0001, 32'h0000_0001);
        check_err(last_slverr, 1'b1, "S0 write 0x01 (unaligned) -> slverr");

        // Slave 0 offset 0x15 -> unaligned
        apb_read(13'h0015, rd_val);
        check_err(last_slverr, 1'b1, "S0 read 0x15 (unaligned) -> slverr");

        // Slave 1 offset 0x02 -> unaligned
        apb_write(13'h1002, 32'h0000_0001);
        check_err(last_slverr, 1'b1, "S1 write 0x02 (unaligned) -> slverr");

        // =================================================================
        // Test group 7: Verify earlier writes survived error tests
        // =================================================================
        $display("\n--- Group 7: Integrity check after error tests ---");

        apb_read(13'h0014, rd_val);
        check_val(rd_val, 32'hAAAA_5555, "S0 REG5 still intact");

        apb_read(13'h1014, rd_val);
        check_val(rd_val, 32'hCAFE_BABE, "S1 REG5 still intact");

        // =================================================================
        // Summary
        // =================================================================
        repeat (10) @(posedge pclk);

        $display("\n==========================================================");
        $display("  RESULTS:  %0d passed,  %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("==========================================================");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #200000;
        $display("[TIMEOUT] Simulation exceeded 200us, aborting.");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("top_apb_tb.vcd");
        $dumpvars(0, top_apb_tb);
    end

endmodule
