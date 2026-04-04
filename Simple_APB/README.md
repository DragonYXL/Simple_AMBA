# Simple APB 设计文档

## 1. 总览

Simple APB 是一个双时钟域 APB 寄存器访问子系统，结构如下：

- `apb_master`：把 `start/write/addr/wdata` 命令接口转换成单次 APB 访问
- `apb_interconnect`：完成 1:2 slave 地址译码
- 每个 slave 子系统由三层组成：
  - `apb_slave_interface`
  - `reg_cdc_bridge`
  - `slave_reg_block`

新的架构中，寄存器真值只保存在外设时钟域 `sclk` 中。APB 访问通过请求/响应方式跨时钟域完成，不再使用 `pclk` 域 shadow 寄存器。

## 2. 架构分层

```text
simple_apb
├── apb_master
├── apb_interconnect
├── slave0
│   ├── apb_slave_interface
│   ├── reg_cdc_bridge
│   └── slave_reg_block
└── slave1
    ├── apb_slave_interface
    ├── reg_cdc_bridge
    └── slave_reg_block
```

各层职责：

- `apb_slave_interface`
  - 只负责 APB 协议适配
  - 把 APB SETUP/ACCESS 转换成单笔寄存器请求
  - 等待后端响应并驱动 `PREADY/PRDATA/PSLVERR`
- `reg_cdc_bridge`
  - 只负责 `pclk` 与 `sclk` 之间的请求/响应 CDC
  - 单次只允许一笔事务在途
- `slave_reg_block`
  - 是寄存器唯一真值所在
  - 负责地址合法性、RO/RW 权限和寄存器语义
  - 向外设逻辑暴露 `reg2hw/hw2reg` 风格接口

## 3. 顶层接口

### 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `pclk` | input | 1 | APB 时钟 |
| `presetn` | input | 1 | APB 复位，低有效 |
| `sclk` | input | 1 | 外设寄存器时钟域 |
| `srstn` | input | 1 | 外设寄存器复位，低有效 |

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
| `sX_reg2hw_rw_write_pulse` | output | `10` | 软件成功写 `REG5-14` 时产生的单拍脉冲 |

其中 `X` 为 `0` 或 `1`。

## 4. 地址映射

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

- `0x3C` 非法
- `0x40` 及以上偏移非法
- 非 32-bit 对齐访问非法
- APB 写 `REG0-4` 非法

以上非法访问都会在完成拍返回 `PSLVERR`。

## 5. 模块说明

### 5.1 `apb_slave_interface`

`apb_slave_interface` 在 `pclk` 域工作：

- 在 APB SETUP 周期发起一笔寄存器请求
- 在 ACCESS 周期等待后端响应
- 当响应返回时，拉高 `PREADY`

因此当前 slave 访问天然支持 wait-state，不再要求 APB 单周期完成。

### 5.2 `reg_cdc_bridge`

`reg_cdc_bridge` 负责 `pclk -> sclk -> pclk` 的请求/响应往返：

- `pclk` 域发起一笔 `reg_req`
- 请求跨域到 `sclk`
- `slave_reg_block` 执行访问并生成 `reg_rsp`
- 响应跨域返回 `pclk`

当前实现只支持单笔事务在途。

### 5.3 `slave_reg_block`

`slave_reg_block` 在 `sclk` 域工作，是寄存器的唯一真值源：

- `REG5-14` 使用内部 RW 存储
- `REG0-4` 直接来自 `hw2reg`
- 成功写 RW 寄存器时，产生对应 `reg2hw_rw_write_pulse`
- 所有地址和权限检查都在这里完成

## 6. 设计取向

这版架构的核心取向是：

- `master` 和 `interconnect` 尽量保持不变
- slave 侧 APB 接口与寄存器实现、CDC 机制解耦
- RO/RW 访问统一走请求/响应模型
- 不再维护 `pclk` 域 shadow 寄存器

这种写法更接近“协议 wrapper + CDC bridge + peripheral-domain reg block”的工业分层方式。

## 7. 文件列表

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
