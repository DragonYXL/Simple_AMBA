// 模板prompt{
// 代码在默认情况下遵守工业界最常用的实现方案 不要因为个别局部问题简单而使用激进优化方案
// 代码注释不要有中文 输出回答问题用中文 模板文件中所有中文都认为是模板要求而不是注释本身内容
// 缩进必须以单次tab为基本单位 不要出现空格 假如发现导入的.v .sv 等硬件描述语言文件中出现了缩进问题，一律立刻改成tap缩进
// 信号名称全小写 用_分割，信号名称不要太长不宜超过14个字母，不易出现大于4以上的下划线，可以适当缩写，复杂的信号一定要注释提供作用说明
// 状态机最好使用三段式，不宜将无关的输出放在同一个状态机的always块中}

// =============================================================================
// Name: apb_master     //模块名称不易太长 不宜过度缩写
// Date: 2026.04.03     //使用东八区时间
// Authors: xlyan -- dragonyxl.eminence@gmail.com
//
// Function:
// - add module function here!!!
// =============================================================================

module apb_master #(// parameter 命名要遵守工业界风格 信号名称全大写 用_分割
        parameter ADDR_WIDTH = 13,
        parameter DATA_WIDTH = 32
    ) (
        // 说明信号组的内容 IO信号命名要遵守工业界和协议的风格
        input  wire                    pclk,
        input  wire                    presetn,

        // Control interface //说明信号组的内容 比如master和slave这种能打包的要打包放一起
        input  wire                    start,      // pulse to begin transfer
        input  wire                    write,      // 1=write, 0=read
        input  wire [ADDR_WIDTH-1:0]   addr,
        input  wire [DATA_WIDTH-1:0]   wdata,
        output reg  [DATA_WIDTH-1:0]   rdata,      // registered, valid cycle after done
        output wire                    done,       // combinational, same-cycle notification
        output wire                    slverr,     // combinational, same-cycle notification

        // APB4 master interface //说明信号组的内容 对于经典信号可以不加声明 比如AMAB这种众所周知的 但是自定义IO要加声明 声明可以比较短
        output reg                     psel,
        output reg                     penable,
        output reg                     pwrite,
        output reg  [ADDR_WIDTH-1:0]   paddr,
        output reg  [DATA_WIDTH-1:0]   pwdata,
        input  wire [DATA_WIDTH-1:0]   prdata,
        input  wire                    pready,
        input  wire                    pslverr
    );


    //每次例化最好添加说明 不用很长 但是一定要有一句
    //    ins #(
    //        .ADDR_WIDTH (PARAM_A),
    //        .DATA_WIDTH (PARAM_B),
    //   ) u_ins (
    //        .clk     (B),
    //        .en      (A),
    //   );


    // -------------------------------------------------------------------------
    // FSM states //有必要说明的状态必须添加额外说明 IDLE DONE这种就不用多解释了
    // -------------------------------------------------------------------------
    localparam IDLE   = 2'd0;
    localparam SETUP  = 2'd1;  // APB setup phase
    localparam ACCESS = 2'd2;  // APB access phase

    reg [1:0] state, nxt_state;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state <= IDLE;
        else
            state <= nxt_state;
    end

    // -------------------------------------------------------------------------
    // Next state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        nxt_state = state;
        case (state)
            IDLE: begin
                if (start)
                    nxt_state = SETUP;
            end
            SETUP: begin
                nxt_state = ACCESS;
            end
            ACCESS: begin
                if (pready)
                    nxt_state = IDLE;
            end
            default:
                nxt_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Combinational done / slverr (same-cycle as ACCESS + pready)
    // -------------------------------------------------------------------------
    assign done   = (state == ACCESS) & pready;
    assign slverr = (state == ACCESS) & pready & pslverr;

    // -------------------------------------------------------------------------
    // Datapath (registered outputs driven one cycle ahead)
    // -------------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
            paddr   <= {ADDR_WIDTH{1'b0}};
            pwdata  <= {DATA_WIDTH{1'b0}};
            rdata   <= {DATA_WIDTH{1'b0}};
        end
        else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE: on start, drive SETUP outputs for next cycle
                // ---------------------------------------------------------
                IDLE: begin
                    if (start) begin
                        psel    <= 1'b1;
                        penable <= 1'b0;
                        pwrite  <= write;
                        paddr   <= addr;
                        pwdata  <= wdata;
                    end
                end

                // ---------------------------------------------------------
                // SETUP: drive ACCESS outputs for next cycle
                // ---------------------------------------------------------
                SETUP: begin
                    penable <= 1'b1;
                end

                // ---------------------------------------------------------
                // ACCESS: wait for pready, then capture and clean up
                // ---------------------------------------------------------
                ACCESS: begin
                    if (pready) begin
                        psel    <= 1'b0;
                        penable <= 1'b0;
                        pwrite  <= 1'b0;
                        paddr   <= {ADDR_WIDTH{1'b0}};
                        pwdata  <= {DATA_WIDTH{1'b0}};
                        rdata   <= prdata;
                    end
                end
            endcase
        end
    end

endmodule
