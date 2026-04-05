# Simple APB 设计文档

## 1. 总览

Simple APB 是一个双时钟域 APB 寄存器访问子系统，结构如下：

- `apb_master`：把 `start/write/addr/wdata` 命令接口转换成单次 APB 访问
- `apb_interconnect`：完成 1:2 slave 地址译码
- 每个 slave 子系统由三层组成：
  - `apb_slave_interface`
  - `reg_cdc_bridge`
  - `slave_reg_block`

寄存器真值只保存在外设时钟域 `slv_clk` 中。APB 访问通过请求/响应方式跨时钟域完成，不再使用 `pclk` 域 shadow 寄存器。

## 2. 架构分层

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

各层职责：

- `apb_slave_interface`
  - 只负责 APB 协议适配（纯组合逻辑，无状态机）
  - 把 APB SETUP/ACCESS 转换成单笔寄存器请求
  - 等待后端响应并驱动 `PREADY/PRDATA/PSLVERR`
  - `PRDATA` 和 `PSLVERR` 使用 `access_phase` 门控，防止非访问阶段泄露残留值
- `reg_cdc_bridge`
  - 负责 `pclk (bus_clk)` 与 `slv_clk` 之间的请求/响应 CDC
  - 请求 payload 在 `bus_clk` 域锁存，响应 payload 在 `slv_clk` 域锁存
  - 每个方向使用独立的 `pulse_handshake` 实例跨域传递脉冲
  - 单次只允许一笔事务在途
- `pulse_handshake`
  - Toggle-based 单脉冲跨时钟域传输
  - 3 级同步 + 2 级反馈，提供 `busy_src` 防止重入
- `slave_reg_block`
  - 是寄存器唯一真值所在，运行在 `slv_clk` 域
  - 负责地址合法性、RO/RW 权限和寄存器语义
  - 单周期响应：请求脉冲到来后的下一个 `slv_clk` 沿输出结果
  - 向外设逻辑暴露 `reg2hw/hw2reg` 风格接口

## 3. 时钟域

| 时钟域 | 信号 | 用途 |
|--------|------|------|
| APB 域 | `pclk` / `presetn` | APB master、interconnect、slave interface |
| CDC bridge 源端 | `bus_clk` / `bus_rstn` | 映射到 `pclk`，锁存请求 payload |
| 外设域 | `slv_clk` / `slv_rstn` | CDC bridge 目的端、slave_reg_block，锁存响应 payload |

## 4. 顶层接口

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `pclk` | input | 1 | APB 时钟 |
| `presetn` | input | 1 | APB 复位，低有效 |
| `slv_clk` | input | 1 | 外设寄存器时钟域 |
| `slv_rstn` | input | 1 | 外设寄存器复位，低有效 |

### 命令接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `start` | input | 1 | 触发一次 APB 访问 |
| `write` | input | 1 | `1` 为写，`0` 为读 |
| `addr` | input | 13 | APB 地址 |
| `wdata` | input | 32 | 写数据 |
| `rdata` | output | 32 | 读数据寄存结果 |
| `done` | output | 1 | 访问完成，`ACCESS` 当拍有效（组合输出） |
| `slverr` | output | 1 | 错误响应，和 `done` 同拍（组合输出） |

### `hw2reg / reg2hw` 接口

每个 slave 都有一组面向外设逻辑的接口。

#### `hw2reg`

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `sX_hw2reg_ro_value` | input | `5*32` | `REG0-4` 的 RO 状态值，来自外设逻辑 |

#### `reg2hw`

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `sX_reg2hw_rw_value` | output | `10*32` | `REG5-14` 的当前 RW 配置值 |
| `sX_reg2hw_rw_write_pulse` | output | `10` | 软件成功写 `REG5-14` 时产生的单拍脉冲（`slv_clk` 域） |

其中 `X` 为 `0` 或 `1`。

## 5. 地址映射

顶层 APB 地址宽度固定为 13 bit。

| Slave | 基地址 | 地址范围 | 地址空间 |
|-------|--------|---------|---------|
| Slave 0 | `0x0000` | `0x0000 - 0x0FFF` | 4KB |
| Slave 1 | `0x1000` | `0x1000 - 0x1FFF` | 4KB |

每个 slave 的 4KB 窗口中，当前只实现 15 个 32-bit 寄存器：

| 寄存器 | 索引 | 偏移 | APB 权限 | 外设逻辑语义 |
|--------|------|------|---------|-------------|
| REG0 | 0 | `0x00` | RO | `hw2reg` 状态输入 |
| REG1 | 1 | `0x04` | RO | `hw2reg` 状态输入 |
| REG2 | 2 | `0x08` | RO | `hw2reg` 状态输入 |
| REG3 | 3 | `0x0C` | RO | `hw2reg` 状态输入 |
| REG4 | 4 | `0x10` | RO | `hw2reg` 状态输入 |
| REG5 | 5 | `0x14` | RW | `reg2hw` 配置输出 |
| REG6 | 6 | `0x18` | RW | `reg2hw` 配置输出 |
| REG7 | 7 | `0x1C` | RW | `reg2hw` 配置输出 |
| REG8 | 8 | `0x20` | RW | `reg2hw` 配置输出 |
| REG9 | 9 | `0x24` | RW | `reg2hw` 配置输出 |
| REG10 | 10 | `0x28` | RW | `reg2hw` 配置输出 |
| REG11 | 11 | `0x2C` | RW | `reg2hw` 配置输出 |
| REG12 | 12 | `0x30` | RW | `reg2hw` 配置输出 |
| REG13 | 13 | `0x34` | RW | `reg2hw` 配置输出 |
| REG14 | 14 | `0x38` | RW | `reg2hw` 配置输出 |

非法访问规则：

- `0x3C` 非法（超出 15 个寄存器范围）
- `0x40` 及以上偏移非法
- 非 32-bit 对齐访问非法
- APB 写 `REG0-4` 非法

以上非法访问都会在完成拍返回 `PSLVERR`。

## 6. 模块说明

### 6.1 `apb_master`

三段式状态机 `IDLE → SETUP → ACCESS`：

- `IDLE`：等待 `start` 脉冲，锁存命令到 APB 输出寄存器
- `SETUP`：驱动 `penable`
- `ACCESS`：等待 `pready`，完成后组合输出 `done/slverr`，寄存 `rdata`

### 6.2 `apb_interconnect`

纯组合逻辑地址译码：

- 用 `paddr[12]` 选择 slave（`addr & ~MASK` 比较基地址）
- 向下广播 `penable/pwrite/paddr[11:0]/pwdata`
- 向上 mux `prdata/pready/pslverr`

### 6.3 `apb_slave_interface`

纯组合逻辑 APB 协议适配：

- 在 APB SETUP 周期（`psel & ~penable`）发起一笔寄存器请求
- 在 ACCESS 周期等待后端响应，通过 `pready` 驱动 wait-state
- `prdata` 和 `pslverr` 仅在 `access_phase & pready` 时有效输出

### 6.4 `reg_cdc_bridge`

双向 CDC 桥接，每个方向使用独立的 `pulse_handshake`：

- 请求方向（`bus_clk → slv_clk`）：payload 在 `bus_clk` 域锁存
- 响应方向（`slv_clk → bus_clk`）：payload 在 `slv_clk` 域锁存
- 单事务在途保证锁存值在跨域期间不会被覆盖

### 6.5 `pulse_handshake`

Toggle-based 脉冲跨时钟域传输：

- 源域：toggle 翻转 + busy 检测（防止重入）
- 目的域：3 级同步器 + XOR 边沿检测生成目的域脉冲
- 反馈路径：2 级同步器回传 ack 清除 busy

### 6.6 `slave_reg_block`

外设域寄存器块，单周期响应：

- `REG5-14` 使用内部 RW 存储
- `REG0-4` 直接来自 `hw2reg`
- 成功写 RW 寄存器时，产生对应 `reg2hw_rw_write_pulse`
- 所有地址对齐、范围和权限检查集中在此模块

## 7. CDC 设计说明

CDC 采用"源域锁存 + 脉冲握手"模式：

1. 源域在脉冲触发时快照 payload 到寄存器（latch）
2. `pulse_handshake` 将脉冲跨域传递到目的域
3. 目的域收到同步后的脉冲时，源域 latch 值已稳定，直接读取
4. 单事务在途保证 latch 在跨域期间不会被下一笔事务覆盖

## 8. 设计取向

这版架构的核心取向是：

- `master` 和 `interconnect` 保持冻结，除非有接口/逻辑不合理性
- slave 侧 APB 接口与寄存器实现、CDC 机制解耦
- RO/RW 访问统一走请求/响应模型
- 不再维护 `pclk` 域 shadow 寄存器

这种写法更接近"协议 wrapper + CDC bridge + peripheral-domain reg block"的工业分层方式。

## 9. 头文件定义 (`simple_apb.vh`)

| 宏 | 值 | 说明 |
|----|----|------|
| `APB_ADDR_WIDTH` | 13 | 顶层 APB 地址宽度 |
| `APB_DATA_WIDTH` | 32 | 数据宽度 |
| `SLV0_BASE_ADDR` | `13'h0000` | Slave 0 基地址 |
| `SLV1_BASE_ADDR` | `13'h1000` | Slave 1 基地址 |
| `SLV_ADDR_MASK` | `13'h0FFF` | 4KB 地址空间掩码 |
| `NUM_RO_REGS` | 5 | RO 寄存器数量 |
| `NUM_RW_REGS` | 10 | RW 寄存器数量 |

`NUM_REGS` (15) 和 `IDX_WIDTH` (4) 由 `slave_reg_block` 内部推导，不在头文件中定义。

## 10. 文件列表

```text
Simple_APB/
├── src/
│   ├── simple_apb.vh
│   ├── simple_apb.v
│   ├── apb_master.v
│   ├── apb_interconnect.v
│   ├── apb_slave_interface.v
│   ├── reg_cdc_bridge.v
│   ├── slave_reg_block.v
│   └── pulse_handshake.v
├── dv/
│   └── top_apb_tb.v
├── include/
│   ├── rtl_filelist.f
│   └── dv_filelist.f
├── sim/
│   ├── Makefile
│   └── scripts/probe.tcl
├── pic/
│   └── apb_master_timing.PNG
└── APB_doc/
    └── IHI0024C_amba_apb_protocol_v2_0_spec.pdf
```
