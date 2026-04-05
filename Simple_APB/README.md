# Simple APB 设计文档

## 1. 项目简介

Simple APB 是一个支持双时钟域的 APB 寄存器访问模块。当然，这是一个偏理想化的"学校"项目，核心功能就是把 SoC 片内总线发起的寄存器读写请求转发到外设端。

项目的模块组成：

- `apb_master`：把 `start/write/addr/wdata` 命令接口转换成单次 APB 访问
- `apb_interconnect`：1-to-2 slave 地址译码和信号路由
- 每个 slave 子系统由三层组成：
  - `apb_slave_interface`：APB 协议适配
  - `reg_cdc_bridge`：请求/响应双向 CDC
  - `slave_reg_block`：外设域寄存器真值

Simple APB 采用了一种简化方案：我把所有寄存器都放到外设时钟域来维护。好处是 `PREADY` 不再恒为 1，ACCESS 阶段天然支持 wait-state，slave 端可以适配不同的时钟频率。代价是每次访问都要等两次 CDC 同步（这个延迟会比较长），会浪费 APB 的读写带宽。不过对于分析 APB 时序、学习跨时钟域寄存器桥来说还是很有用的。如果你没有 CDC 的基础，可以跳过只看接口部分和仿真波形，这不会影响 APB 协议本身的学习。

## 2. 背景知识

这一节补充一些寄存器访问相关的工程背景，已经了解的可以直接跳到第 3 节。

### 2.1 片内外设 vs 片外外设

实际工程中，片外外设一般通过 UART、I2C、SPI 等协议通讯——也就是嵌入式课设做的那些东西。这类外设芯片通常由专门的数模混合芯片公司提供，芯片软件工程师负责通讯协议对齐。而片内外设则可以采用通用接口 IP 快速集成，一般用 APB 做寄存器配置，因为 AMBA 本身就是片内总线协议族（包括 AHB 用于高速传输、APB 用于低速配置等）。

简单来说：片外外设走串行协议（UART/I2C/SPI），片内外设走并行总线（APB/AHB），两者的寄存器访问机制不同，但"软件通过地址读写寄存器来控制硬件"这个核心思路是一样的。

### 2.2 RO/RW 寄存器的角色

RO（Read-Only）寄存器在外设端一般表征工作状态和上报信息；RW（Read-Write）寄存器则用来配置具体的工作参数。

举个具体例子：一个 LED 驱动外设，RW 寄存器用来配置色温、亮度、频闪周期等参数，软件写入后外设按配置工作；而当发生短路、断路、过温等异常时，外设通过 RO 寄存器上报状态到 SoC 系统，软件轮询或中断读取后做相应处理。

这种 RO/RW 的分工在几乎所有外设中都能看到——网卡有状态寄存器和配置寄存器，DMA 有通道状态和传输配置，ADC 有采样结果和采样参数……理解了这一点，看任何外设的寄存器手册都不会陌生。

### 2.3 寄存器的时钟域归属

一般而言，RO 寄存器一定是离散维护的——比如表征短路、断路、过温的状态信号可能分布在芯片的不同模块中，不可能用一个 `regs.v` 把所有寄存器全拉进来，这样做既不合理也不现实。所以 RO 寄存器天然处于外设自身的时钟域，通常会把所有 RO 值通过 wire 连线拉到接口处再做转发。

而 RW 寄存器本来就是来自上层的命令，一般在接口时钟域下工作，可以用一个 `regs.v` 统一管理，然后再做 CDC 传到外设时钟域去用（当然如果本身就在同一个时钟域就省了这些事）。

### 2.4 时钟域与 CDC

片外外设的协议时钟和片内工作时钟往往是异步的，CDC 处理一般在外设片内完成。至于片内要不要给外设搞多时钟域，完全看设计需求，没有通用结论。最简单的做法是核心、总线、外设采用同源时钟，外设和外设总线同频。但现实中由于功耗、性能等原因，多时钟域几乎不可避免。

CDC（Clock Domain Crossing）本身是数字设计中的一个大话题，核心问题就是：一个时钟域产生的信号，在另一个时钟域采样时可能正好处于亚稳态。解决方案从最简单的两级同步器（打两拍），到握手协议、异步 FIFO，都是为了安全地把信息从一个时钟域传到另一个时钟域。本项目用的是 toggle-based 脉冲握手，属于中等复杂度的方案，适合单笔事务传递。

### 2.5 本项目的设计取舍

Simple APB 把所有寄存器（包括 RO 和 RW）都放到外设时钟域维护，访问统一走请求/响应模型，不在 `pclk` 域维护影子寄存器。这样做架构最简洁，但代价是每次访问都有 CDC 往返延迟。

如果要改得更工业一些，我有一个可行的思路（当然这只是众多方法中的一个）：把 RW 寄存器放到 `pclk` 端更新，ACCESS 一个周期就能完成，模块检测到寄存器修改后自行维护 `slv_clk` 域的影子寄存器；而 RO 寄存器的读取则需要两次 CDC，`pclk` 侧不维护影子寄存器。这种混合方案兼顾了写入性能和架构清晰度，但实现复杂度也更高。

## 3. 架构分层

```text
simple_apb
├── apb_master
├── apb_interconnect
├── slave0
│   ├── apb_slave_interface
│   ├── reg_cdc_bridge
│   │   ├── pulse_handshake (req)
│   │   └── pulse_handshake (rsp)
│   └── slave_reg_block
└── slave1
    ├── apb_slave_interface
    ├── reg_cdc_bridge
    │   ├── pulse_handshake (req)
    │   └── pulse_handshake (rsp)
    └── slave_reg_block
```

这个分层思路是比较经典的"协议 wrapper + CDC bridge + peripheral-domain reg block"三层结构，各层职责非常明确，互不越界：

- `apb_slave_interface`：纯组合逻辑，只做 APB 协议适配。把 SETUP/ACCESS 转成一笔寄存器请求，等后端响应后驱动 `PREADY/PRDATA/PSLVERR`。输出用 `access_phase` 门控，非访问阶段不会泄露残留值。
- `reg_cdc_bridge`：只管 `pclk` 和 `slv_clk` 之间的 CDC。具体来说，APB slave 端发起请求时，将单周期的 req 脉冲跨域传到 `slv_clk`；slave 端完成寄存器操作后，再把单周期的 rsp 脉冲传回 `pclk`。双方在收到对方同步后的脉冲时采样数据——因为 payload 已经在源域锁存且稳定，所以能保证 CDC 的数据有效性。
- `pulse_handshake`：Toggle-based 单脉冲跨时钟域传输，3 级同步 + 2 级反馈 ack，提供 `busy_src` 防止重入。这个模块新手不太容易一眼看明白，建议结合 6.5 节的波形图理解。
- `slave_reg_block`：真实寄存器所在的模块，跑在 `slv_clk` 域。地址对齐、范围检查、RO/RW 权限判断全在这里做，单周期响应。对外暴露 `reg2hw/hw2reg` 风格接口——也就是 slave 内部接口，外设逻辑直接读写这些信号就行。

## 4. 时钟域

项目涉及两个时钟域，通过 `reg_cdc_bridge` 桥接：

| 时钟域 | 信号 | 涉及模块 |
|--------|------|---------|
| APB 总线域 | `pclk` / `presetn` | master、interconnect、slave_interface、CDC bridge 源端 |
| 外设域 | `slv_clk` / `slv_rstn` | CDC bridge 目的端、slave_reg_block |

`reg_cdc_bridge` 的端口命名中，`bus_clk/bus_rstn` 映射到 `pclk`，`slv_clk/slv_rstn` 映射到外设时钟。这样命名是为了让模块本身不依赖具体的顶层信号名，方便后续其他项目使用。

## 5. 顶层接口

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `pclk` | input | 1 | APB 时钟 |
| `presetn` | input | 1 | APB 复位，低有效 |
| `slv_clk` | input | 1 | 外设寄存器时钟 |
| `slv_rstn` | input | 1 | 外设寄存器复位，低有效 |

### 命令接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `start` | input | 1 | 单拍脉冲，触发一次 APB 访问 |
| `write` | input | 1 | `1` 写，`0` 读 |
| `addr` | input | 13 | APB 字节地址 |
| `wdata` | input | 32 | 写数据 |
| `rdata` | output | 32 | 读数据，`done` 当拍由 master 寄存（NBA 更新） |
| `done` | output | 1 | 访问完成，组合输出，`ACCESS + pready` 当拍有效 |
| `slverr` | output | 1 | 错误响应，和 `done` 同拍，组合输出 |

注意 `rdata` 是寄存器输出，在 `done` 拉高的同一个 posedge 通过 NBA 更新，仿真中需要等 NBA 落定后才能采到正确值（典型做法是 `#1` 延迟或多等一拍）。

### `hw2reg / reg2hw` 接口

每个 slave 都有一组面向外设逻辑的接口，其中 `X` 为 `0` 或 `1`：

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `sX_hw2reg_ro_value` | input | `5*32` | REG0-4 的 RO 状态值，来自外设逻辑 |
| `sX_reg2hw_rw_value` | output | `10*32` | REG5-14 的当前 RW 配置值 |
| `sX_reg2hw_rw_write_pulse` | output | `10` | 软件写 REG5-14 成功时的单拍脉冲（`slv_clk` 域） |

## 6. 地址映射

顶层 APB 地址宽度 13 bit，最高位用来选 slave：

| Slave | 基地址 | 地址范围 | 空间 |
|-------|--------|---------|------|
| Slave 0 | `0x0000` | `0x0000 - 0x0FFF` | 4KB |
| Slave 1 | `0x1000` | `0x1000 - 0x1FFF` | 4KB |

每个 slave 的 4KB 窗口中，当前只用了 15 个 32-bit 寄存器（60 字节）：

| 寄存器 | 索引 | 偏移 | 权限 | 说明 |
|--------|------|------|------|------|
| REG0-4 | 0-4 | `0x00`-`0x10` | RO | `hw2reg` 外设状态输入 |
| REG5-14 | 5-14 | `0x14`-`0x38` | RW | `reg2hw` 软件配置输出 |

非法访问会返回 `PSLVERR` 的所有情况：

- 超区域访问（超出 15 个寄存器）
- 地址未 32-bit 对齐（`addr[1:0] != 0`）
- 写 RO 寄存器（REG0-4）

## 7. 模块说明

### 7.1 `apb_master`

经典三段式状态机，没什么花活：

- `IDLE`：等 `start` 脉冲，锁存命令到 APB 输出寄存器
- `SETUP`：拉起 `penable`，无条件跳 ACCESS
- `ACCESS`：等 `pready`，完成后组合输出 `done/slverr`，同拍寄存 `rdata <= prdata`

`done` 和 `slverr` 是组合输出，在 `state == ACCESS & pready` 时有效，只持续一个 pclk 周期。

下图展示了一次写后跟一次读的完整流程，ACCESS 阶段有多个等待周期（`PREADY=0`），这就是 CDC 延迟的直观体现：

<img src="pic/APB Master—Write then Read.png" width="800">

> 波形源文件：`pic/apb_master_waitstate.json`，用 [WaveDrom](https://wavedrom.com/editor.html) 打开可编辑。

关键时序要点：

- **IDLE → SETUP**：`start` 脉冲拉高一拍，master 在这拍锁存 `addr/wdata/write` 到 APB 输出寄存器。下一个 posedge，`PSEL` 拉高、`PENABLE` 为 0，进入 SETUP。
- **SETUP → ACCESS**：无条件跳转，`PENABLE` 拉高。此时 `apb_slave_interface` 检测到 `setup_phase`（`PSEL & ~PENABLE`）并发出寄存器请求。
- **ACCESS 等待**：请求经过 CDC 到达 `slv_clk` 域，`slave_reg_block` 处理后响应再 CDC 回来，这段时间 `PREADY=0`，master 一直等。对比零等待的标准 APB 时序，CDC 方案的代价就在这里。
- **ACCESS 完成**：`PREADY=1` 的那一拍，`done` 和 `slverr` 作为组合输出同时有效。master 同拍通过 NBA 寄存 `rdata <= prdata`。
- **读数据采样**：`rdata` 是寄存器输出，在 `done` 当拍的 NBA 更新。仿真 TB 中如果用 `while(!done) @(posedge pclk)` 轮询，退出时 NBA 还没生效，需要 `#1` 或多等一拍才能采到正确值。

### 7.2 `apb_interconnect`

纯组合逻辑，用 `paddr[12]`（即 `addr & ~MASK` 比较基地址）选 slave。向下广播 `penable/pwrite/paddr[11:0]/pwdata`，向上 mux 回 `prdata/pready/pslverr`。因为 13-bit 地址空间被两个 slave 完整覆盖，不存在"没选中任何 slave"的情况。

### 7.3 `apb_slave_interface`

纯组合逻辑，没有状态机。在 SETUP 阶段（`psel & ~penable`）发一笔寄存器请求，ACCESS 阶段等后端响应，用 `pready` 自然形成 wait-state。`prdata` 和 `pslverr` 都用 `access_phase` 门控，非访问阶段输出全零，不会泄露残留值。

### 7.4 `reg_cdc_bridge`

请求和响应各走一个独立的 `pulse_handshake`，payload 在源域锁存：

- 请求方向（`bus_clk → slv_clk`）：`bus_req_valid` 触发时锁存 `write/addr/wdata`，CDC 跨域后 `slv_clk` 侧直接读锁存值
- 响应方向（`slv_clk → bus_clk`）：`slv_rsp_ready` 触发时锁存 `rdata/err`，CDC 跨域后 `bus_clk` 侧直接读锁存值

因为单事务在途，锁存值在跨域期间不会被下一笔事务覆盖，所以不需要额外的握手保护 payload。这就是"源域锁存 + 脉冲握手"的经典 CDC 模式——源域快照 payload，`pulse_handshake` 跨域传脉冲，目的域收到脉冲时直接读已稳定的锁存值。

### 7.5 `pulse_handshake`

标准的 toggle-based 脉冲跨时钟域方案。这个模块新手不太容易一眼看明白，下面结合波形图逐步拆解。

<img src="pic/pulse_handshake — Toggle-based Single Pulse CDC.png" width="700">

> 波形源文件：`pic/pulse_handshake_cdc.json`，`clk_src` 频率快于 `clk_dst`（图中周期比约 2:3）。用 [WaveDrom](https://wavedrom.com/editor.html) 打开可编辑。

工作原理：

1. **源域发射**：`pulse_src` 拉高一拍，`req_toggle` 翻转（0→1），`busy_src` 同时拉高，阻止新的脉冲进入。
2. **3 级同步**：`req_toggle` 进入 `clk_dst` 域的移位寄存器 `sync[2:0]`。经过 3 个 `clk_dst` 周期，toggle 信号逐级传播到 `sync[2]`。
3. **边沿检测**：`pulse_dst = sync[2] ^ sync[1]`。当 `sync[1]` 已经翻转但 `sync[2]` 还没翻转时，XOR 输出为 1，恰好持续一个 `clk_dst` 周期——这就是目的域还原出来的单周期脉冲。
4. **反馈解锁**：`sync[1]`（已稳定的 toggle 值）反馈回 `clk_src` 域，经过 2 级同步器后到达 `fb_sync[1]`。当 `fb_sync[1] == req_toggle` 时，`busy_src` 清零，源域可以发射下一个脉冲。

整个往返延迟大约 3 个 `clk_dst` 周期（正向同步）+ 2 个 `clk_src` 周期（反馈同步），在本项目的配置下（`pclk` 100MHz，`slv_clk` 40MHz）大概是 100-150ns。

### 7.6 `slave_reg_block`

外设域的寄存器块，单周期响应。REG0-4（RO）直接取自 `hw2reg` 输入，REG5-14（RW）用内部寄存器存储。地址对齐、范围、RO/RW 权限检查全部集中在这一个模块里做。写 RW 寄存器成功时，对应 bit 的 `reg2hw_rw_write_pulse` 会出一个 `slv_clk` 域的单拍脉冲。

`NUM_REGS`（15）和 `IDX_WIDTH`（4）由模块内部从 `NUM_RO_REGS + NUM_RW_REGS` 推导，不作为外部参数传入。

## 8. 头文件定义 (`simple_apb.vh`)

| 宏 | 值 | 说明 |
|----|----|------|
| `APB_ADDR_WIDTH` | 13 | 顶层地址宽度 |
| `APB_DATA_WIDTH` | 32 | 数据宽度 |
| `SLV0_BASE_ADDR` | `13'h0000` | Slave 0 基地址 |
| `SLV1_BASE_ADDR` | `13'h1000` | Slave 1 基地址 |
| `SLV_ADDR_MASK` | `13'h0FFF` | 4KB 地址空间掩码 |
| `NUM_RO_REGS` | 5 | RO 寄存器数量 |
| `NUM_RW_REGS` | 10 | RW 寄存器数量 |

`NUM_REGS`（15）和 `IDX_WIDTH`（4）不在头文件定义，由 `slave_reg_block` 内部推导。这样做是为了避免冗余定义——改了 RO/RW 数量却忘了改总数，这种 bug 很难查。

## 9. 文件列表

```text
Simple_APB/
├── src/
│   ├── simple_apb.vh          # 全局宏定义
│   ├── simple_apb.v           # 顶层
│   ├── apb_master.v           # APB master 状态机
│   ├── apb_interconnect.v     # 1:2 地址译码
│   ├── apb_slave_interface.v  # APB slave 协议适配
│   ├── reg_cdc_bridge.v       # 请求/响应双向 CDC
│   ├── slave_reg_block.v      # 外设域寄存器块
│   └── pulse_handshake.v      # 单脉冲跨时钟域
├── dv/
│   └── top_apb_tb.v           # 顶层 testbench
├── include/
│   ├── rtl_filelist.f
│   └── dv_filelist.f
├── sim/
│   ├── Makefile
│   └── scripts/probe.tcl
├── pic/
│   ├── apb_master_timing.PNG
│   ├── apb_master_waitstate.json  # WaveDrom 波形源文件
│   └── pulse_handshake_cdc.json   # WaveDrom 波形源文件
└── APB_doc/
    └── IHI0024C_amba_apb_protocol_v2_0_spec.pdf
```
