// =============================================================================
// Top level: APB4 master + interconnect + 2 slaves
// Delay is parameterized via SRAM RD_LATENCY per slave.
// =============================================================================

module top_apb #(
    parameter ADDR_WIDTH       = 13,
    parameter DATA_WIDTH       = 32,
    parameter SLAVE_ADDR_WIDTH = 12,
    parameter RAM_DEPTH        = 1024,
    parameter LOCAL_RAM_DEPTH  = 1024,
    parameter S0_RD_LATENCY    = 1,     // slave 0 SRAM read latency
    parameter S1_RD_LATENCY    = 1      // slave 1 SRAM read latency
) (
    input  wire        pclk,
    input  wire        presetn,

    // Control interface (directly exposed for testbench)
    input  wire        start,
    input  wire        rw,
    input  wire [ADDR_WIDTH-1:0]               apb_base,
    input  wire [$clog2(LOCAL_RAM_DEPTH)-1:0]  local_base,
    input  wire [7:0]                          length,
    output wire        done
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
    wire [2:0]              pprot_m;
    wire [DATA_WIDTH-1:0]   prdata_m;
    wire                    pready_m;
    wire                    pslverr_m;

    // APB signals: interconnect <-> slave 0
    wire                    psel_s0;
    wire                    penable_s0;
    wire                    pwrite_s0;
    wire [SLAVE_ADDR_WIDTH-1:0] paddr_s0;
    wire [DATA_WIDTH-1:0]   pwdata_s0;
    wire [DATA_WIDTH/8-1:0] pstrb_s0;
    wire [2:0]              pprot_s0;
    wire [DATA_WIDTH-1:0]   prdata_s0;
    wire                    pready_s0;
    wire                    pslverr_s0;

    // APB signals: interconnect <-> slave 1
    wire                    psel_s1;
    wire                    penable_s1;
    wire                    pwrite_s1;
    wire [SLAVE_ADDR_WIDTH-1:0] paddr_s1;
    wire [DATA_WIDTH-1:0]   pwdata_s1;
    wire [DATA_WIDTH/8-1:0] pstrb_s1;
    wire [2:0]              pprot_s1;
    wire [DATA_WIDTH-1:0]   prdata_s1;
    wire                    pready_s1;
    wire                    pslverr_s1;

    // -------------------------------------------------------------------------
    // Master
    // -------------------------------------------------------------------------
    apb_master #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .LOCAL_RAM_DEPTH(LOCAL_RAM_DEPTH)
    ) u_master (
        .pclk       (pclk),
        .presetn    (presetn),
        .start      (start),
        .rw         (rw),
        .apb_base   (apb_base),
        .local_base (local_base),
        .length     (length),
        .done       (done),
        .psel       (psel_m),
        .penable    (penable_m),
        .pwrite     (pwrite_m),
        .paddr      (paddr_m),
        .pwdata     (pwdata_m),
        .pstrb      (pstrb_m),
        .pprot      (pprot_m),
        .prdata     (prdata_m),
        .pready     (pready_m),
        .pslverr    (pslverr_m)
    );

    // -------------------------------------------------------------------------
    // Interconnect
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
        .pprot_m    (pprot_m),
        .prdata_m   (prdata_m),
        .pready_m   (pready_m),
        .pslverr_m  (pslverr_m),

        .psel_s0    (psel_s0),
        .penable_s0 (penable_s0),
        .pwrite_s0  (pwrite_s0),
        .paddr_s0   (paddr_s0),
        .pwdata_s0  (pwdata_s0),
        .pstrb_s0   (pstrb_s0),
        .pprot_s0   (pprot_s0),
        .prdata_s0  (prdata_s0),
        .pready_s0  (pready_s0),
        .pslverr_s0 (pslverr_s0),

        .psel_s1    (psel_s1),
        .penable_s1 (penable_s1),
        .pwrite_s1  (pwrite_s1),
        .paddr_s1   (paddr_s1),
        .pwdata_s1  (pwdata_s1),
        .pstrb_s1   (pstrb_s1),
        .pprot_s1   (pprot_s1),
        .prdata_s1  (prdata_s1),
        .pready_s1  (pready_s1),
        .pslverr_s1 (pslverr_s1)
    );

    // -------------------------------------------------------------------------
    // Slave 0
    // -------------------------------------------------------------------------
    apb_slave #(
        .ADDR_WIDTH (SLAVE_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .RAM_DEPTH  (RAM_DEPTH),
        .RD_LATENCY (S0_RD_LATENCY)
    ) u_slave0 (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel_s0),
        .penable (penable_s0),
        .pwrite  (pwrite_s0),
        .paddr   (paddr_s0),
        .pwdata  (pwdata_s0),
        .pstrb   (pstrb_s0),
        .pprot   (pprot_s0),
        .prdata  (prdata_s0),
        .pready  (pready_s0),
        .pslverr (pslverr_s0)
    );

    // -------------------------------------------------------------------------
    // Slave 1
    // -------------------------------------------------------------------------
    apb_slave #(
        .ADDR_WIDTH (SLAVE_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .RAM_DEPTH  (RAM_DEPTH),
        .RD_LATENCY (S1_RD_LATENCY)
    ) u_slave1 (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel_s1),
        .penable (penable_s1),
        .pwrite  (pwrite_s1),
        .paddr   (paddr_s1),
        .pwdata  (pwdata_s1),
        .pstrb   (pstrb_s1),
        .pprot   (pprot_s1),
        .prdata  (prdata_s1),
        .pready  (pready_s1),
        .pslverr (pslverr_s1)
    );

endmodule
