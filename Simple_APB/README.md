# Simple APB 设计文档

## 1. 总览

Simple APB 是一个基于 AMBA APB 协议的双时钟域寄存器访问子系统。系统包含一个 APB master（协议桥）、一个 1:2 地址译码互联、两组 slave + 寄存器文件。每个寄存器文件包含 15 个 32-bit 寄存器（5 个只读 + 10 个读写），支持 APB 总线侧（pclk）和 slave 逻辑侧（sclk）的双时钟域访问，通过 pulse handshake CDC 进行跨时钟域同步。

**设计特性：**
- 符合 AMBA APB 协议（无 PPROT，保留 PSTRB/PSLVERR）
- 双时钟域寄存器文件，RW/RO 影子寄存器 + CDC 握手
- 参数化设计：地址宽度、数据宽度、寄存器数量均可配置
- 地址映射通过 `simple_apb.vh` 头文件统一管理

## 2. 项目架构

```
simple_apb (顶层)
├── apb_master              APB 协议桥 (pclk)
├── apb_interconnect        1:2 地址译码 (组合逻辑)
│
├── apb_slave (×2)          APB 协议适配器 (pclk, 组合逻辑)
│   └─ 输出通用读写信号 ──→
│
└── apb_reg_file (×2)       双时钟域寄存器管理 (pclk + sclk)
    ├── apb_regs_pclk       RW 寄存器 + RO 影子寄存器 (pclk)
    ├── apb_regs_sclk       RO 寄存器 + RW 影子寄存器 (sclk)
    ├── pulse_handshake     RW 更新 CDC (pclk → sclk)
    └── pulse_handshake     RO 更新 CDC (sclk → pclk)
```

slave 与 reg_file 是**同级关系**，均在顶层实例化。slave 只负责 APB 协议转换，reg_file 只负责寄存器存储和跨时钟域同步。

## 3. 顶层 IO 说明

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `pclk` | input | 1 | APB 总线时钟 |
| `presetn` | input | 1 | APB 复位（低有效） |
| `sclk` | input | 1 | Slave 逻辑时钟 |
| `srstn` | input | 1 | Slave 复位（低有效） |

### 命令接口（pclk 域）

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `start` | input | 1 | 脉冲触发一次传输 |
| `write` | input | 1 | 1=写，0=读 |
| `addr` | input | 13 | 目标地址 |
| `wdata` | input | 32 | 写数据 |
| `strb` | input | 4 | 字节写使能 |
| `rdata` | output | 32 | 读数据（寄存器输出，done 后一拍有效） |
| `done` | output | 1 | 传输完成（组合逻辑，ACCESS 当拍有效） |
| `slverr` | output | 1 | 错误标志（组合逻辑，与 done 同步） |

### Slave 本地端口（sclk 域，每个 slave 一组）

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `sX_local_wr_en` | input | 1 | 本地写使能（仅写 RO 寄存器） |
| `sX_local_wr_addr` | input | 4 | 写地址（寄存器索引） |
| `sX_local_wr_data` | input | 32 | 写数据 |
| `sX_local_rd_addr` | input | 4 | 读地址（寄存器索引） |
| `sX_local_rd_data` | output | 32 | 读数据（组合输出） |

> `sX` 代表 `s0`（slave 0）或 `s1`（slave 1）。

## 4. 地址区间说明

| Slave | 基地址 | 地址范围 | 地址空间 |
|-------|--------|---------|---------|
| Slave 0 | `0x0000` | `0x0000 - 0x0FFF` | 4KB |
| Slave 1 | `0x1000` | `0x1000 - 0x1FFF` | 4KB |

地址译码方式：`(paddr & ~SLV_ADDR_MASK) == SLV_BASE_ADDR`，通过掩码比较实现。修改地址映射只需更改 `simple_apb.vh` 中的宏定义。

slave 内部地址译码：`reg_idx = paddr[5:2]`，取字对齐后的 4-bit 索引。

## 5. Slave 寄存器表

每个 slave 包含 15 个 32-bit 寄存器，地址布局相同：

| 寄存器 | 索引 | 字节偏移 | APB 权限 | 本地权限 | 说明 |
|--------|------|---------|---------|---------|------|
| REG0 | 0 | 0x00 | 只读 | 读写 | RO 寄存器，slave 逻辑写入 |
| REG1 | 1 | 0x04 | 只读 | 读写 | RO 寄存器 |
| REG2 | 2 | 0x08 | 只读 | 读写 | RO 寄存器 |
| REG3 | 3 | 0x0C | 只读 | 读写 | RO 寄存器 |
| REG4 | 4 | 0x10 | 只读 | 读写 | RO 寄存器 |
| REG5 | 5 | 0x14 | 读写 | 只读 | RW 寄存器，APB master 写入 |
| REG6 | 6 | 0x18 | 读写 | 只读 | RW 寄存器 |
| REG7 | 7 | 0x1C | 读写 | 只读 | RW 寄存器 |
| REG8 | 8 | 0x20 | 读写 | 只读 | RW 寄存器 |
| REG9 | 9 | 0x24 | 读写 | 只读 | RW 寄存器 |
| REG10 | 10 | 0x28 | 读写 | 只读 | RW 寄存器 |
| REG11 | 11 | 0x2C | 读写 | 只读 | RW 寄存器 |
| REG12 | 12 | 0x30 | 读写 | 只读 | RW 寄存器 |
| REG13 | 13 | 0x34 | 读写 | 只读 | RW 寄存器 |
| REG14 | 14 | 0x38 | 读写 | 只读 | RW 寄存器 |

**错误响应（PSLVERR）：**
- APB 写 RO 寄存器（REG0-4）→ PSLVERR=1，数据不写入
- 访问不存在的地址（索引 ≥ 15）→ PSLVERR=1

**RO/RW 判断方式：** 使用位掩码查表 `RO_MASK[addr]`，综合为单个 LUT，无比较器开销。

## 6. 模块设计说明

### 6.1 apb_master — APB 协议桥

将外部命令接口转换为标准 APB 协议时序。

**FSM（3 状态）：**
```
IDLE ──(start)──→ SETUP ──→ ACCESS ──(pready)──→ IDLE
```

- **IDLE**：等待 `start` 脉冲。收到后锁存 `addr/wdata/write/strb`，同时驱动 `psel=1` 为下一周期的 SETUP 准备。
- **SETUP**：`PSEL=1, PENABLE=0`。驱动 `penable=1` 为下一周期的 ACCESS 准备。
- **ACCESS**：`PSEL=1, PENABLE=1`。等待 `pready`，完成后锁存 `prdata` 到 `rdata`，清零总线信号回到 IDLE。

`done` 和 `slverr` 为组合输出（`state==ACCESS & pready`），在 ACCESS 当拍通知上层，节省一个周期。

### 6.2 apb_interconnect — 地址译码互联

纯组合逻辑。根据地址的高位与基地址掩码比较，选择目标 slave。共享信号（penable/pwrite/pwdata/pstrb）广播给所有 slave，仅 PSEL 按地址选通。返回方向的 prdata/pready/pslverr 通过 MUX 回传 master。

### 6.3 apb_slave — APB 协议适配器

纯组合逻辑模块（无寄存器），将 APB 协议信号转换为通用的寄存器读写信号。

- 地址译码：`paddr[5:2]` 提取寄存器索引
- 写使能：`access_phase & pwrite & pready`
- PREADY：`access_phase ? ~reg_busy : 1'b1`（CDC 忙时等待）
- PRDATA：仅在完成的读 ACCESS 时输出有效数据，其余时间为 0
- 时钟传递：将 `pclk/presetn` 传递给 reg_file 作为 pclk 域时钟

### 6.4 apb_reg_file — 双时钟域寄存器管理

协调 pclk 和 sclk 两个时钟域的寄存器访问，内部例化：
- `apb_regs_pclk`：pclk 域的 RW 寄存器和 RO 影子寄存器
- `apb_regs_sclk`：sclk 域的 RO 寄存器和 RW 影子寄存器
- 2 个 `pulse_handshake` CDC 模块

**数据流：**

```
RW 路径 (APB 写 → slave 读)：
  APB 写入 → RW regs (pclk) ──CDC pulse──→ RW shadow (sclk)

RO 路径 (slave 写 → APB 读)：
  local 写入 → RO regs (sclk) ──CDC pulse──→ RO shadow (pclk) → APB 读取
```

**busy 机制：** `busy = rw_cdc_busy`，来自 `pulse_handshake` 的 `busy_src` 输出，在 pclk 域内直接使用。APB 写入 RW 寄存器后，CDC 握手完成前 `pready=0` 阻止下一笔写入。RO 方向采用宽松模式，APB 读可能读到旧值，不产生 busy。

### 6.5 apb_regs_pclk — pclk 域寄存器

- **RW regs [10]**：APB master 直接写入和读取。写入后产生 `rw_update_pulse` 通知 sclk 域。
- **RO shadow [5]**：接收 sclk 域 CDC 同步过来的 RO 寄存器值。收到 `ro_update_pulse` 时批量更新。
- **读 MUX**：`addr ∈ [0,4]` 读 RO shadow，`addr ∈ [5,14]` 读 RW regs。

### 6.6 apb_regs_sclk — sclk 域寄存器

- **RO regs [5]**：slave 本地逻辑写入。写入后产生 `ro_update_pulse` 通知 pclk 域。
- **RW shadow [10]**：接收 pclk 域 CDC 同步过来的 RW 寄存器值。收到 `rw_update_pulse` 时批量更新。
- **读 MUX**：`addr ∈ [0,4]` 读 RO regs，`addr ∈ [5,14]` 读 RW shadow。与 pclk 端接口风格对称。

### 6.7 pulse_handshake — CDC 握手模块

基于 toggle 的脉冲跨时钟域同步器。

**工作流程：**
1. 源端收到 `pulse_src`（非 busy 时）→ 翻转 `req_toggle`，busy 拉高
2. `req_toggle` 经 3 级同步器到达目标端 → 检测边沿产生 `pulse_dst`
3. 目标端的同步值经 2 级反馈同步器回到源端
4. 反馈匹配 `req_toggle` → busy 清除

**亚稳态安全**：前向 3 级同步，反馈 2 级同步。

## 7. 文件结构

```
Simple_APB/
├── src/
│   ├── simple_apb.vh          地址映射和寄存器配置宏定义
│   ├── simple_apb.v           顶层模块
│   ├── apb_master.v           APB master 协议桥
│   ├── apb_interconnect.v     1:2 地址译码互联
│   ├── apb_slave.v            APB slave 协议适配器
│   ├── apb_reg_file.v         双时钟域寄存器管理（CDC wrapper）
│   ├── apb_regs_pclk.v        pclk 域寄存器
│   ├── apb_regs_sclk.v        sclk 域寄存器
│   └── handshake_cdc.v        脉冲握手 CDC 模块
├── dv/
│   └── top_apb_tb.v           Testbench
├── include/
│   ├── rtl_filelist.f         RTL 文件列表
│   └── dv_filelist.f          仿真文件列表
├── sim/
│   ├── Makefile               仿真构建脚本（Xcelium）
│   └── scripts/probe.tcl      波形探针脚本
├── doc/
│   └── apb_master_timing.json WaveDrom 时序图

```
