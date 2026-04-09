// =============================================================================
// Name: ahb_lite_def
// Date: 2026.04.09
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - Global macro definitions for AHB-Lite project
// =============================================================================

`ifndef AHB_LITE_DEF_VH
`define AHB_LITE_DEF_VH

// -------------------------------------------------------------------------
// AHB-Lite transfer type (HTRANS)
// -------------------------------------------------------------------------
`define HTRANS_IDLE   2'b00
`define HTRANS_BUSY   2'b01
`define HTRANS_NONSEQ 2'b10
`define HTRANS_SEQ    2'b11

// -------------------------------------------------------------------------
// AHB-Lite burst type (HBURST)
// -------------------------------------------------------------------------
`define HBURST_SINGLE  3'b000
`define HBURST_INCR    3'b001
`define HBURST_WRAP4   3'b010
`define HBURST_INCR4   3'b011
`define HBURST_WRAP8   3'b100
`define HBURST_INCR8   3'b101
`define HBURST_WRAP16  3'b110
`define HBURST_INCR16  3'b111

// -------------------------------------------------------------------------
// AHB-Lite transfer size (HSIZE)
// -------------------------------------------------------------------------
`define HSIZE_BYTE 3'b000
`define HSIZE_HALF 3'b001
`define HSIZE_WORD 3'b010

// -------------------------------------------------------------------------
// AHB-Lite response (HRESP)
// -------------------------------------------------------------------------
`define HRESP_OKAY  1'b0
`define HRESP_ERROR 1'b1

// -------------------------------------------------------------------------
// Bus width
// -------------------------------------------------------------------------
`define AHB_ADDR_W 13
`define AHB_DATA_W 32

// -------------------------------------------------------------------------
// Bus1 address map — bit[12] selects slave
//   Slave 0 : DMA config registers  0x0000 - 0x0FFF
//   Slave 1 : General register file  0x1000 - 0x1FFF
// -------------------------------------------------------------------------
`define B1_DMA_BASE  13'h0000
`define B1_REG_BASE  13'h1000
`define B1_SLV_MASK  13'h0FFF

// -------------------------------------------------------------------------
// Bus2 address map — bit[12] selects slave
//   Slave 0 : SRAM 0   0x0000 - 0x0FFF
//   Slave 1 : SRAM 1   0x1000 - 0x1FFF
// -------------------------------------------------------------------------
`define B2_SRAM0_BASE 13'h0000
`define B2_SRAM1_BASE 13'h1000
`define B2_SLV_MASK   13'h0FFF

// -------------------------------------------------------------------------
// DMA register offset (12-bit local address inside DMA slave)
// -------------------------------------------------------------------------
`define DMA_REG_SRC  12'h000
`define DMA_REG_DST  12'h004
`define DMA_REG_LEN  12'h008
`define DMA_REG_CTRL 12'h00C
`define DMA_REG_STAT 12'h010

// -------------------------------------------------------------------------
// Register slave parameters
// -------------------------------------------------------------------------
`define REG_NUM_RO 4
`define REG_NUM_RW 8

`endif
