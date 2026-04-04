# Simple APB 设计文档

## 1. 总览

Simple APB 是一个双时钟域 APB 寄存器访问子系统，包含：

- 一个 `apb_master`，把 `start/write/addr/wdata` 命令接口转换成单次 APB 访问
- 一个 `apb_interconnect`，完成 1:2 slave 地址译码
- 两组 `apb_slave + apb_reg_file`

每个 `apb_reg_file` 内有 15 个 32-bit 寄存器：

- `REG0` 到 `REG4` 为 RO，APB 侧只读，`sclk` 本地侧可写
- `REG5` 到 `REG14` 为 RW，APB 侧可读写，`sclk` 本地侧只读

`pclk` 域和 `sclk` 域之间通过 `pulse_handshake` 做跨时钟同步。

## 2. 项目结构

```text
simple_apb
├── apb_master
├── apb_interconnect
├── apb_slave x2
└── apb_reg_file x2
    ├── apb_regs_pclk
    ├── apb_regs_sclk
    ├── pulse_handshake  (RW: pclk -> sclk)
    └── pulse_handshake  (RO: sclk -> pclk)
```

`apb_slave` 和 `apb_reg_file` 是并列关系：

- `apb_slave` 负责 APB 协议适配
- `apb_reg_file` 负责寄存器存储和 CDC

## 3. 顶层接口

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `pclk` | input | 1 | APB 时钟 |
| `presetn` | input | 1 | APB 复位，低有效 |
| `sclk` | input | 1 | slave 本地时钟 |
| `srstn` | input | 1 | slave 本地复位，低有效 |

### 命令接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `start` | input | 1 | 触发一次 APB 访问 |
| `write` | input | 1 | `1` 为写，`0` 为读 |
| `addr` | input | 13 | APB 地址 |
| `wdata` | input | 32 | 写数据 |
| `rdata` | output | 32 | 读数据寄存结果 |
| `done` | output | 1 | 访问完成，`ACCESS` 当拍有效 |
| `slverr` | output | 1 | 错误响应，和 `done` 同拍 |

### slave 本地接口

每个 slave 都有一组本地接口，位于 `sclk` 域：

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `sX_local_wr_en` | input | 1 | 本地写使能，只允许写 RO 寄存器 |
| `sX_local_wr_addr` | input | 4 | 本地写地址 |
| `sX_local_wr_data` | input | 32 | 本地写数据 |
| `sX_local_rd_addr` | input | 4 | 本地读地址 |
| `sX_local_rd_data` | output | 32 | 本地读数据，组合输出 |

其中 `X` 为 `0` 或 `1`。

## 4. 地址映射

顶层 APB 地址宽度固定为 13 bit。

| Slave | 基地址 | 地址范围 | 地址空间 |
|-------|--------|---------|---------|
| Slave 0 | `0x0000` | `0x0000 - 0x0FFF` | 4KB |
| Slave 1 | `0x1000` | `0x1000 - 0x1FFF` | 4KB |

地址译码由 [`simple_apb.vh`](src/simple_apb.vh) 中的宏定义控制。

### slave 内部寄存器窗口

虽然每个 slave 保留了 4KB 地址空间，但当前只实现了 15 个寄存器，合法偏移如下：

| 寄存器 | 索引 | 偏移 | APB 权限 | 本地权限 |
|--------|------|------|---------|---------|
| REG0 | 0 | `0x00` | RO | RW |
| REG1 | 1 | `0x04` | RO | RW |
| REG2 | 2 | `0x08` | RO | RW |
| REG3 | 3 | `0x0C` | RO | RW |
| REG4 | 4 | `0x10` | RO | RW |
| REG5 | 5 | `0x14` | RW | RO |
| REG6 | 6 | `0x18` | RW | RO |
| REG7 | 7 | `0x1C` | RW | RO |
| REG8 | 8 | `0x20` | RW | RO |
| REG9 | 9 | `0x24` | RW | RO |
| REG10 | 10 | `0x28` | RW | RO |
| REG11 | 11 | `0x2C` | RW | RO |
| REG12 | 12 | `0x30` | RW | RO |
| REG13 | 13 | `0x34` | RW | RO |
| REG14 | 14 | `0x38` | RW | RO |

非法访问规则：

- 访问 `0x3C`，即索引 `15`，返回 `PSLVERR`
- 访问 `0x40` 及以上偏移，不再镜像到低地址寄存器，统一返回 `PSLVERR`
- APB 写 `REG0` 到 `REG4`，返回 `PSLVERR`

## 5. 模块说明

### 5.1 `apb_master`

`apb_master` 使用三态 FSM：

```text
IDLE -> SETUP -> ACCESS -> IDLE
```

行为如下：

- `IDLE`：等待 `start`
- `SETUP`：输出 `PSEL=1, PENABLE=0`
- `ACCESS`：输出 `PSEL=1, PENABLE=1`，等待 `PREADY`

`done` 和 `slverr` 是组合输出，在 `ACCESS && PREADY` 当拍有效。

### 5.2 `apb_interconnect`

`apb_interconnect` 是纯组合逻辑：

- 根据地址高位选择 slave 0 或 slave 1
- `penable/pwrite/pwdata` 广播给全部 slave
- `psel` 按地址选通
- `prdata/pready/pslverr` 从目标 slave 复用回 master

### 5.3 `apb_slave`

`apb_slave` 负责把 APB 事务转换成寄存器文件接口：

- `reg_addr = paddr[5:2]`
- `reg_wr_en = access_phase & pwrite & pready`
- `prdata` 只在合法读访问完成时输出
- 非法偏移或寄存器权限错误时输出 `PSLVERR`

### 5.4 `apb_reg_file`

`apb_reg_file` 协调两个时钟域：

- `apb_regs_pclk` 保存 RW 寄存器和 RO shadow
- `apb_regs_sclk` 保存 RO 寄存器和 RW shadow
- 两个 `pulse_handshake` 分别处理 RW 和 RO 更新脉冲

数据流如下：

```text
RW 路径:
  APB write -> pclk RW regs -> CDC pulse -> sclk RW shadow

RO 路径:
  local write -> sclk RO regs -> CDC pulse -> pclk RO shadow
```

### 5.5 busy 行为

当前实现中：

- `busy` 来自 RW 方向 CDC 的 `busy_src`
- 当 RW 同步尚未完成时，`apb_slave` 会把 `PREADY` 拉低
- 这会阻塞该 slave 上的全部 APB 访问，不区分读写

也就是说，`busy` 现在表达的是“该 slave 正在等待一次 pclk->sclk 的 RW 同步完成”，而不是“仅阻塞下一笔写”。

### 5.6 RO 同步策略说明

当前 RO 路径是“宽松同步”：

- `sclk` 侧本地写先更新本地 RO 寄存器
- 再通过 pulse CDC 把更新通知到 `pclk` 侧 shadow
- APB 读取的是 `pclk` 侧 shadow，因此短时间内可能读到旧值

如果 `sclk` 侧在前一次 RO 同步完成前连续更新多次，后续脉冲可能被合并或丢弃。这个行为适合“状态类寄存器”，不适合要求逐次事件不丢失的计数器或 FIFO 状态上报。

## 6. 文件列表

```text
Simple_APB/
├── src/
│   ├── simple_apb.vh
│   ├── simple_apb.v
│   ├── apb_master.v
│   ├── apb_interconnect.v
│   ├── apb_slave.v
│   ├── apb_reg_file.v
│   ├── apb_regs_pclk.v
│   ├── apb_regs_sclk.v
│   └── handshake_cdc.v
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

当前仓库未提供 testbench。
