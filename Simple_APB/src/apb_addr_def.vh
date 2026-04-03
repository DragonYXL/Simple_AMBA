// =============================================================================
// Name:     apb_addr_def
// Date:     2026.04.03
// Authors:  xlyan <yanxl24@m.fudan.edu.cn>
//
// Function:
// - APB system address map and register offset definitions
// =============================================================================

`ifndef APB_ADDR_DEF_VH
`define APB_ADDR_DEF_VH

// -------------------------------------------------------------------------
// System bus width
// -------------------------------------------------------------------------
`define APB_ADDR_WIDTH        13
`define APB_DATA_WIDTH        32

// -------------------------------------------------------------------------
// Slave base addresses
// -------------------------------------------------------------------------
`define SLV0_BASE_ADDR        13'h0000
`define SLV1_BASE_ADDR        13'h1000

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

`endif
