// =============================================================================
// Name:     apb_slave_interface
// Date:     2026.04.05
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - APB protocol adapter for one slave slot
// - Converts APB SETUP/ACCESS into a single in-flight register request
// - Waits for register response and drives APB wait-state via PREADY
// - Does not implement register map, permissions, or CDC policy
// =============================================================================

module apb_slave_interface #(
        parameter ADDR_WIDTH = 12,
        parameter DATA_WIDTH = 32
    ) (
        input  wire                    pclk,
        input  wire                    presetn,

        // APB slave interface
        input  wire                    psel,
        input  wire                    penable,
        input  wire                    pwrite,
        input  wire [ADDR_WIDTH-1:0]   paddr,
        input  wire [DATA_WIDTH-1:0]   pwdata,
        output wire [DATA_WIDTH-1:0]   prdata,
        output wire                    pready,
        output wire                    pslverr,

        // Register request toward slave reg block
        output wire                    reg_req_valid,
        output wire                    reg_req_write,
        output wire [ADDR_WIDTH-1:0]   reg_req_addr,
        output wire [DATA_WIDTH-1:0]   reg_req_wdata,

        // Register response from slave reg block
        input  wire                    reg_rsp_ready,
        input  wire [DATA_WIDTH-1:0]   reg_rsp_rdata,
        input  wire                    reg_rsp_err
    );

    wire setup_phase;
    wire access_phase;

    // -------------------------------------------------------------------------
    // APB phase decode
    // -------------------------------------------------------------------------
    assign setup_phase = psel & ~penable;
    assign access_phase = psel & penable;

    // -------------------------------------------------------------------------
    // slave register R/W request
    // - Launch request during SETUP
    // -------------------------------------------------------------------------
    assign reg_req_valid = setup_phase;
    assign reg_req_write = pwrite;
    assign reg_req_addr  = paddr;
    assign reg_req_wdata = pwdata;

    // -------------------------------------------------------------------------
    // slave to APB response
    // - PRDATA/PSLVERR are only meaningful on the completing ACCESS beat
    // -------------------------------------------------------------------------
    assign pready  = access_phase ? reg_rsp_ready : 1'b1;
    assign prdata  = (access_phase & pready & ~pwrite) ? reg_rsp_rdata : {DATA_WIDTH{1'b0}};
    assign pslverr = access_phase & pready & reg_rsp_err;

endmodule
