// =============================================================================
// APB4 Slave — pure protocol adapter
// Delay behavior comes from SRAM's RD_LATENCY, not from this module.
//   RD_LATENCY = 1  →  0 APB wait states (zero-wait)
//   RD_LATENCY = N  →  N-1 APB wait states
// =============================================================================

module apb_slave #(
    parameter ADDR_WIDTH  = 12,
    parameter DATA_WIDTH  = 32,
    parameter RAM_DEPTH   = 1024,
    parameter RD_LATENCY  = 1       // forwarded to SRAM
) (
    input  wire                    pclk,
    input  wire                    presetn,

    // APB4 slave interface
    input  wire                    psel,
    input  wire                    penable,
    input  wire                    pwrite,
    input  wire [ADDR_WIDTH-1:0]   paddr,
    input  wire [DATA_WIDTH-1:0]   pwdata,
    input  wire [DATA_WIDTH/8-1:0] pstrb,
    input  wire [2:0]              pprot,
    output wire [DATA_WIDTH-1:0]   prdata,
    output wire                    pready,
    output wire                    pslverr
);

    // -------------------------------------------------------------------------
    // Address decoding
    // -------------------------------------------------------------------------
    localparam RAM_ADDR_W   = $clog2(RAM_DEPTH);
    localparam RAM_ADDR_MSB = RAM_ADDR_W + 1;  // +2 for byte addr, -1 for bit index

    wire [RAM_ADDR_W-1:0] ram_addr;
    assign ram_addr = paddr[RAM_ADDR_MSB:2];    // word-aligned

    wire addr_valid;
    assign addr_valid = (paddr[ADDR_WIDTH-1:RAM_ADDR_MSB+1] == {(ADDR_WIDTH-RAM_ADDR_MSB-1){1'b0}});

    // -------------------------------------------------------------------------
    // SRAM interface
    // -------------------------------------------------------------------------
    // Read:  issue during setup phase  (PSEL & ~PENABLE & ~PWRITE)
    // Write: issue during access phase (PSEL &  PENABLE &  PWRITE)
    wire ram_rd_req = psel & ~penable & ~pwrite;
    wire ram_wr_req = psel &  penable &  pwrite;

    wire                  ram_en = ram_rd_req | ram_wr_req;
    wire                  ram_we = ram_wr_req;
    wire [DATA_WIDTH-1:0] ram_rdata;
    wire                  ram_rd_valid;

    sram #(
        .ADDR_WIDTH (RAM_ADDR_W),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (RAM_DEPTH),
        .RD_LATENCY (RD_LATENCY)
    ) u_ram (
        .clk     (pclk),
        .en      (ram_en),
        .we      (ram_we),
        .addr    (ram_addr),
        .wdata   (pwdata),
        .wstrb   (pstrb),
        .rdata   (ram_rdata),
        .rd_valid(ram_rd_valid)
    );

    // -------------------------------------------------------------------------
    // APB response
    // -------------------------------------------------------------------------
    assign prdata  = ram_rdata;
    assign pready  = pwrite ? 1'b1 : ram_rd_valid;
    assign pslverr = psel & penable & pready & ~addr_valid;

endmodule
