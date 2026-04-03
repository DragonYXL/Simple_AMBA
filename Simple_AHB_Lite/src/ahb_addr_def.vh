// =============================================================================
// Name:     ahb_addr_def
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - AHB-Lite system address map and register offset definitions
// =============================================================================

`ifndef AHB_ADDR_DEF_VH
`define AHB_ADDR_DEF_VH

// -------------------------------------------------------------------------
// System bus width
// -------------------------------------------------------------------------
`define AHB_ADDR_WIDTH        13
`define AHB_DATA_WIDTH        32

// -------------------------------------------------------------------------
// Slave base addresses
// -------------------------------------------------------------------------
`define SLV0_BASE_ADDR        13'h0000
`define SLV1_BASE_ADDR        13'h1000

// -------------------------------------------------------------------------
// Slave address space mask (4KB per slave)
// -------------------------------------------------------------------------
`define SLV_ADDR_MASK         13'h0FFF

// -------------------------------------------------------------------------
// Register configuration
// -------------------------------------------------------------------------
`define NUM_REGS              15
`define NUM_RO_REGS           5
`define NUM_RW_REGS           10
`define REG_IDX_WIDTH         4

// -------------------------------------------------------------------------
// Register byte offsets (shared layout for all slaves)
// -------------------------------------------------------------------------
`define REG0_OFFSET           12'h00
`define REG1_OFFSET           12'h04
`define REG2_OFFSET           12'h08
`define REG3_OFFSET           12'h0C
`define REG4_OFFSET           12'h10
`define REG5_OFFSET           12'h14
`define REG6_OFFSET           12'h18
`define REG7_OFFSET           12'h1C
`define REG8_OFFSET           12'h20
`define REG9_OFFSET           12'h24
`define REG10_OFFSET          12'h28
`define REG11_OFFSET          12'h2C
`define REG12_OFFSET          12'h30
`define REG13_OFFSET          12'h34
`define REG14_OFFSET          12'h38

// -------------------------------------------------------------------------
// AHB-Lite HTRANS encoding
// -------------------------------------------------------------------------
`define HTRANS_IDLE           2'b00
`define HTRANS_NONSEQ         2'b10

// -------------------------------------------------------------------------
// AHB-Lite HBURST encoding (single only for this design)
// -------------------------------------------------------------------------
`define HBURST_SINGLE         3'b000

// -------------------------------------------------------------------------
// AHB-Lite HSIZE encoding
// -------------------------------------------------------------------------
`define HSIZE_WORD            3'b010

// -------------------------------------------------------------------------
// AHB-Lite HRESP encoding
// -------------------------------------------------------------------------
`define HRESP_OKAY            1'b0
`define HRESP_ERROR           1'b1

`endif
