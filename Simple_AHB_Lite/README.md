# Simple AHB-Lite 设计文档

## 1. 项目简介

Simple AHB-Lite 是一个用于学习 AHB-Lite 总线协议的项目，覆盖了 master 端和 slave 端的实现。项目围绕两条独立的 AHB-Lite 总线展开，各有侧重：

- **Bus1（寄存器配置）**：CPU 作为 master，通过单次传输读写 DMA 配置寄存器和一组通用寄存器。重点学习 AHB-Lite 的基本读写时序、地址译码、slave 响应机制。
- **Bus2（Burst 传输）**：DMA 作为 master，从 SRAM0 burst 读数据，再 burst 写到 SRAM1。重点学习流水线 burst 传输、地址自增/回绕、HTRANS 状态切换。

DMA 是两条总线的桥梁——在 Bus1 上它是 slave（被 CPU 配置），在 Bus2 上它是 master（执行数据搬运）。这种 slave+master 的双重角色在实际 SoC 中非常常见。

项目和实际工程最大的区别是 CPU 看不到 SRAM 这个总线上的 slave ，但这只是学习目的上的简化：Bus1 专注寄存器访问，Bus2 专注 burst 传输，两条路径互不干扰。SRAM 的初始数据可以在仿真 TB 中通过层次路径或 `$readmemh` 直接加载。

项目的模块组成：

- `ahb_master`：CPU 的 AHB-Lite 单次传输 master
- `ahb_interconnect`：1-to-2 地址译码和 slave 响应复用（两条总线各用一个）
- `ahb_reg_slave`：通用寄存器 slave，支持 RO/RW
- `dma_top`：DMA 顶层包装
  - `dma_slave`：配置寄存器 slave（Bus1 侧）
  - `dma_master`：burst 传输引擎（Bus2 侧）
- `ahb_sram`：SRAM slave，支持 burst（例化两个）

## 2. 背景知识

这一节补充 AHB-Lite 相关的工程背景，已经了解的可以直接跳到第 3 节。

### 2.1 AHB-Lite vs AHB

AHB-Lite 是 AHB 的简化版，区别只有一个：**单 master**。去掉了多 master 仲裁（arbiter）和 split/retry 响应，协议复杂度低了不少，但核心的流水线传输、burst 机制都保留了。绝大多数 SoC 子系统（DMA 通道、外设总线桥）用的都是 AHB-Lite，因为一条总线通常只有一个 master 在驱动。

### 2.2 流水线传输

AHB-Lite 的核心特性是**地址阶段和数据阶段重叠**：

- 第 N 拍：master 驱动 beat N 的地址（HADDR、HTRANS 等）
- 第 N+1 拍：slave 响应 beat N 的数据（HRDATA/HWDATA），同时 master 可以驱动 beat N+1 的地址

这意味着一笔单次传输需要 2 个周期（地址 + 数据），而连续 burst 中每个额外的 beat 只需 1 个周期——地址和数据交叠流水。`HREADY` 控制流水线推进：slave 拉低 `HREADY` 时，master 必须保持当前输出不变，流水线暂停。

### 2.3 Burst 传输

AHB-Lite 支持以下 burst 类型，由 `HBURST` 信号指示：

| HBURST | 类型 | 说明 |
|--------|------|------|
| `000` | SINGLE | 单次传输 |
| `001` | INCR | 不定长递增 |
| `010` | WRAP4 | 4 beat 回绕 |
| `011` | INCR4 | 4 beat 递增 |
| `100` | WRAP8 | 8 beat 回绕 |
| `101` | INCR8 | 8 beat 递增 |
| `110` | WRAP16 | 16 beat 回绕 |
| `111` | INCR16 | 16 beat 递增 |

INCR 类型地址每拍递增一个传输大小（word = +4）。WRAP 类型地址在对齐边界处回绕——比如 WRAP4 word 在 16 字节边界回绕：起始地址 `0x0C` 的 4 beat 序列是 `0x0C → 0x00 → 0x04 → 0x08`。

在 burst 中，`HTRANS` 的使用规则：
- 第一拍：`NONSEQ`（新传输的起始）
- 后续拍：`SEQ`（burst 内的连续传输）
- burst 结束后：`IDLE`

Master 负责驱动正确的 HADDR 序列，slave 只需按当前 HADDR 读写即可。

## 3. 架构分层

```text
top_ahb_lite
├── ahb_master (u_cpu)              — Bus1 master, CPU stub
├── ahb_interconnect (u_bus1_ic)    — Bus1 1:2 interconnect
│   ├── → dma_top (u_dma)           — Bus1 slave 0
│   │      ├── dma_slave            — config registers
│   │      └── dma_master           — burst engine (Bus2 master)
│   └── → ahb_reg_slave (u_reg_slv) — Bus1 slave 1
├── ahb_interconnect (u_bus2_ic)    — Bus2 1:2 interconnect
│   ├── → ahb_sram (u_sram0)        — Bus2 slave 0
│   └── → ahb_sram (u_sram1)        — Bus2 slave 1
```

各层职责：

- `ahb_master`：把 `start/write/addr/wdata` 命令接口转换成 AHB-Lite 单次传输。只做 SINGLE burst，不涉及连续传输。
- `ahb_interconnect`：纯组合逻辑的地址译码 + 注册数据阶段的 slave 选择 + 响应 mux。两条总线各例化一个，参数完全相同。
- `dma_slave`：AHB slave 接口 + 5 个配置/状态寄存器。CPU 写 CTRL.start 后产生一拍启动脉冲给 `dma_master`。
- `dma_master`：burst 传输引擎。收到启动后，先 burst 读源地址（数据存入 16-word 内部 buffer），再 burst 写目的地址。支持所有 HBURST 类型。
- `ahb_reg_slave`：参数化的寄存器文件 slave，NUM_RO 个只读寄存器 + NUM_RW 个读写寄存器。
- `ahb_sram`：同步 SRAM slave，零等待周期。burst 中 master 驱动正确地址，SRAM 只需按地址读写。

## 4. 时钟域

整个项目只有一个时钟域，没有 CDC 问题：

| 信号 | 说明 |
|------|------|
| `hclk` | AHB 时钟 |
| `hresetn` | 异步复位，低有效 |

所有模块都跑在 `hclk` 下。DMA 的 slave 端（Bus1）和 master 端（Bus2）共享同一个时钟，配置寄存器和 burst 引擎之间不需要跨时钟域处理，直接用组合/寄存器信号连接即可。

## 5. 顶层接口

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `hclk` | input | 1 | AHB 时钟 |
| `hresetn` | input | 1 | 异步复位，低有效 |

### CPU 命令接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `cpu_start` | input | 1 | 单拍脉冲，触发一次 AHB 访问 |
| `cpu_write` | input | 1 | `1` 写，`0` 读 |
| `cpu_addr` | input | 13 | AHB 字节地址 |
| `cpu_wdata` | input | 32 | 写数据 |
| `cpu_rdata` | output | 32 | 读数据，`cpu_done` 当拍 NBA 更新 |
| `cpu_done` | output | 1 | 访问完成，组合输出 |
| `cpu_error` | output | 1 | 错误响应，组合输出 |

### 寄存器 slave 外设接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `hw2reg` | input | 4×32 | REG0-3 的 RO 状态值 |
| `reg2hw` | output | 8×32 | REG4-11 的 RW 配置值 |
| `rw_wr_pulse` | output | 8 | 软件写 RW 寄存器的单拍脉冲 |

### DMA 状态

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `dma_done` | output | 1 | DMA 传输完成脉冲 |

## 6. 地址映射

### Bus1（13-bit 地址，bit[12] 选 slave）

| Slave | 范围 | 空间 | 说明 |
|-------|------|------|------|
| DMA config | `0x0000 - 0x0FFF` | 4 KB | DMA 配置寄存器 |
| Register file | `0x1000 - 0x1FFF` | 4 KB | 通用寄存器 |

#### DMA 配置寄存器

| 偏移 | 名称 | 权限 | 说明 |
|------|------|------|------|
| `0x000` | SRC_ADDR | RW | 源地址（Bus2 地址空间） |
| `0x004` | DST_ADDR | RW | 目的地址（Bus2 地址空间） |
| `0x008` | XFER_LEN | RW | INCR burst 长度（1-16），固定长度 burst 忽略此值 |
| `0x00C` | CTRL | RW | `[0]` start（写 1 触发，自动清零）；`[3:1]` burst 类型（HBURST 编码） |
| `0x010` | STATUS | RO | `[0]` busy；`[1]` done；`[2]` error |

#### 通用寄存器 slave

| 寄存器 | 偏移 | 权限 | 说明 |
|--------|------|------|------|
| REG0-3 | `0x00`-`0x0C` | RO | `hw2reg` 外设状态输入 |
| REG4-11 | `0x10`-`0x2C` | RW | `reg2hw` 软件配置输出 |

### Bus2（13-bit 地址，bit[12] 选 slave）

| Slave | 范围 | 空间 | 说明 |
|-------|------|------|------|
| SRAM 0 | `0x0000 - 0x0FFF` | 4 KB (1024 words) | DMA 源 |
| SRAM 1 | `0x1000 - 0x1FFF` | 4 KB (1024 words) | DMA 目的 |

## 7. 模块说明

### 7.1 `ahb_master`

经典三段式状态机，和 APB master 的思路一样，只是换成了 AHB-Lite 的两阶段流水线：

- `IDLE`：等 `start` 脉冲，锁存命令到 AHB 输出寄存器（HTRANS=NONSEQ、HADDR、HWRITE、HWDATA 全部一拍锁存）
- `ADDR`：地址阶段。总线上 HTRANS=NONSEQ，等 HREADY（正常情况下此时 HREADY=1，因为没有上一笔传输）。地址被 slave 采样后，注册 HTRANS=IDLE 进入数据阶段。
- `DATA`：数据阶段。写传输中 HWDATA 仍保持有效（从 IDLE 阶段锁存至今）；读传输中 slave 驱动 HRDATA。等 HREADY=1 后传输结束，组合输出 `done`，同拍 NBA 寄存 `rdata`。

一笔单次传输的最小延迟是 2 个 `hclk` 周期（地址 + 数据）。

### 7.2 `ahb_interconnect`

1-master-to-2-slave 互联，两条总线各例化一份，参数相同（`SEL_BIT=12`）。

- **地址译码**：组合逻辑，直接用 `haddr[12]` 选 slave。`0` 选 slave 0，`1` 选 slave 1。
- **信号广播**：HADDR（去掉高位，只传低 12-bit 本地地址）、HTRANS、HWRITE、HSIZE、HBURST、HWDATA 广播给两个 slave。
- **数据阶段 mux**：用寄存器 `dph_sel` 记录地址阶段选中的 slave（在 HREADY=1 时更新），数据阶段根据 `dph_sel` mux 回 HRDATA、HREADYOUT、HRESP。这是标准的 AHB decoder 模式——地址阶段选 slave，数据阶段 mux 响应。

因为 13-bit 地址空间被两个 slave 完整覆盖（bit[12]=0 或 1），不存在无效地址的情况，不需要 default slave。

### 7.3 `ahb_reg_slave`

参数化的寄存器文件，和 APB 项目的 `slave_reg_block` 类似但接口换成了 AHB-Lite。

- 地址阶段（`hsel & htrans[1] & hready`）采样 HADDR 和 HWRITE，注册到 `idx_r` 和 `wr_r`。
- 数据阶段：写命中 RW 范围时，写入对应寄存器并出一拍 `rw_wr_pulse`；读命中时，mux 出 RO 值（来自 `hw2reg`）或 RW 值。
- 零等待周期（HREADYOUT 恒为 1），不返回错误。

### 7.4 `dma_top` / `dma_slave` / `dma_master`

DMA 分三个文件：`dma_slave` 管 Bus1 侧的配置寄存器，`dma_master` 管 Bus2 侧的 burst 引擎，`dma_top` 把它俩包在一起。

#### `dma_slave`

5 个寄存器（SRC_ADDR、DST_ADDR、XFER_LEN、CTRL、STATUS），AHB slave 接口和 `ahb_reg_slave` 类似。CPU 写 CTRL[0]=1 时，在下一拍产生一个 `dma_start` 脉冲（前提是 DMA 不忙）。STATUS 是只读的，反映 DMA 引擎的 busy/done/error 状态。

#### `dma_master`

这是项目里最复杂的模块，也是 burst 学习的核心。

**状态机：**

```
IDLE → RD_PHASE → WR_PHASE → DONE → IDLE
```

- `IDLE`：等 `dma_start`，锁存配置（源地址、目的地址、burst 类型、beat 数）
- `RD_PHASE`：burst 读源地址，数据存入 16-word 内部 buffer
- `WR_PHASE`：burst 写目的地址，数据从 buffer 取出
- `DONE`：一拍完成信号，然后回 IDLE

**Beat 计数器 `cnt`：**

```
cnt = 0           : 驱动第一个地址（NONSEQ），无数据
cnt = 1..N-1      : 驱动后续地址（SEQ）+ 处理上一拍数据
cnt = N            : 不驱动地址（IDLE）+ 处理最后一拍数据
```

对于 INCR4（N=4），读阶段需要 5 个周期（1 个纯地址 + 3 个地址/数据重叠 + 1 个纯数据），写阶段也是 5 个周期，总共约 11 个周期完成一次 4-beat 搬运（含过渡）。

**地址计算：**

- INCR 类型：`nxt_addr = haddr + 4`
- WRAP 类型：`nxt_addr = (haddr & ~wrap_mask) | ((haddr + 4) & wrap_mask)`

其中 `wrap_mask` 在启动时根据 burst 类型预计算：WRAP4=0xF，WRAP8=0x1F，WRAP16=0x3F。

**注册输出时序：**

所有 AHB 信号都是注册输出。在 cycle K 注册的值在 cycle K+1 出现在总线上。读到写的过渡（`cnt == num_beats` in `RD_PHASE`）是无缝的——在捕获最后一笔读数据的同一拍，注册写阶段的 NONSEQ 地址，下一拍 Bus2 上就是写操作的第一个地址。

**HWDATA 时序：**

写阶段中，`hwdata <= xfer_buf[cnt]` 在 `cnt = k` 时注册，出现在 `cnt = k+1`——恰好是 beat k 的数据阶段。所以 buffer 索引和 beat 索引自然对齐，不需要额外偏移。

### 7.5 `ahb_sram`

同步 SRAM slave，参数化深度（默认 1024 words = 4 KB）。

- 地址阶段采样（同 `ahb_reg_slave`），注册地址和写标志
- 读：在地址阶段发起同步读（`mem[haddr[AW+1:2]]`），结果在数据阶段有效
- 写：在数据阶段写入（使用注册的地址和 HWDATA）
- 零等待周期，不返回错误

Burst 传输中，master 每拍驱动正确的 HADDR，SRAM 只是按地址逐拍读写，不需要自己计算地址——这是 AHB-Lite slave 的设计简洁之处。

仿真时 SRAM 内容默认未初始化。可以在 TB 中用层次路径直接写入：
```verilog
u_top.u_sram0.mem[0] = 32'hDEAD_BEEF;
```
或用 `$readmemh("data.hex", u_top.u_sram0.mem)` 加载文件。

## 8. 头文件定义 (`ahb_lite_def.vh`)

| 宏 | 值 | 说明 |
|----|-----|------|
| `AHB_ADDR_W` | 13 | 顶层地址宽度 |
| `AHB_DATA_W` | 32 | 数据宽度 |
| `B1_DMA_BASE` | `13'h0000` | Bus1 DMA slave 基地址 |
| `B1_REG_BASE` | `13'h1000` | Bus1 寄存器 slave 基地址 |
| `B2_SRAM0_BASE` | `13'h0000` | Bus2 SRAM0 基地址 |
| `B2_SRAM1_BASE` | `13'h1000` | Bus2 SRAM1 基地址 |
| `DMA_REG_SRC` | `12'h000` | DMA SRC_ADDR 偏移 |
| `DMA_REG_DST` | `12'h004` | DMA DST_ADDR 偏移 |
| `DMA_REG_LEN` | `12'h008` | DMA XFER_LEN 偏移 |
| `DMA_REG_CTRL` | `12'h00C` | DMA CTRL 偏移 |
| `DMA_REG_STAT` | `12'h010` | DMA STATUS 偏移 |
| `REG_NUM_RO` | 4 | 通用寄存器 slave RO 数量 |
| `REG_NUM_RW` | 8 | 通用寄存器 slave RW 数量 |

## 9. 文件列表

```text
Simple_AHB_Lite/
├── src/
│   ├── ahb_lite_def.vh      # 全局宏定义
│   ├── ahb_master.v         # CPU AHB-Lite 单次传输 master
│   ├── ahb_interconnect.v   # 1:2 地址译码 + 响应 mux
│   ├── ahb_reg_slave.v      # 通用寄存器 slave (RO/RW)
│   ├── dma_slave.v          # DMA 配置寄存器 slave
│   ├── dma_master.v         # DMA burst 传输引擎
│   ├── dma_top.v            # DMA 包装 (slave + master)
│   ├── ahb_sram.v           # SRAM slave
│   └── top_ahb_lite.v       # 顶层
├── AHB-lite_doc/
│   └── IHI0033a.pdf         # ARM AHB-Lite 协议规范
└── AHB_Lite_design.md       # 本文档
```
