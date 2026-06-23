`timescale 1ns/1ps

module debug_unit #(
    parameter CLK_FREQ             = 50_000_000,
    parameter BAUD_RATE            = 9600,
    parameter DATA_MEM_ADDR_WIDTH  = 12
)(
    input  wire       clk,
    input  wire       rst,

    // UART pins
    input  wire       uart_rx_i,
    output wire       uart_tx_o,

    // Pipeline control
    output reg        pipe_start,
    output reg        pipe_step,
    output reg        pipe_mode,
    output reg        pipe_rst,
    input  wire       pipe_halted,

    // Program memory write
    output reg        prog_we,
    output reg [31:0] prog_addr,
    output reg [31:0] prog_wdata,

    // Debug read: register file
    output reg  [4:0]  debug_reg_addr,
    input  wire [31:0] debug_reg_data,

    // Debug read: data memory
    output reg  [DATA_MEM_ADDR_WIDTH-1:0] debug_mem_addr,
    input  wire [31:0]                    debug_mem_data,

    // Debug read: PC
    input  wire [31:0] pipe_pc,

    // Debug read: latch contents (IF/ID)
    input  wire [31:0] dbg_if_id_pc,
    input  wire [31:0] dbg_if_id_instr,

    // Debug read: latch contents (ID/EX)
    input  wire [31:0] dbg_id_ex_pc,
    input  wire [31:0] dbg_id_ex_rs1_data,
    input  wire [31:0] dbg_id_ex_rs2_data,
    input  wire [31:0] dbg_id_ex_imm,
    input  wire [4:0]  dbg_id_ex_rd,
    input  wire [6:0]  dbg_id_ex_opcode,
    input  wire [31:0] dbg_id_ex_alu_op_ctrl,

    // Debug read: latch contents (EX/MEM)
    input  wire [31:0] dbg_ex_mem_alu_result,
    input  wire [31:0] dbg_ex_mem_rs2_data,
    input  wire [4:0]  dbg_ex_mem_rd,
    input  wire [31:0] dbg_ex_mem_pc_plus4,
    input  wire [31:0] dbg_ex_mem_branch_target,

    // Debug read: latch contents (MEM/WB)
    input  wire [31:0] dbg_mem_wb_read_data,
    input  wire [31:0] dbg_mem_wb_alu_result,
    input  wire [4:0]  dbg_mem_wb_rd,
    input  wire [31:0] dbg_mem_wb_pc_plus4
);

    // ============================================================
    // UART instances
    // ============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_busy;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
        .clk    (clk),
        .rst    (rst),
        .rx     (uart_rx_i),
        .o_data (rx_data),
        .o_valid(rx_valid)
    );

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
        .clk    (clk),
        .rst    (rst),
        .i_data (tx_data),
        .i_valid(tx_valid),
        .o_tx   (uart_tx_o),
        .o_busy (tx_busy)
    );

    // ============================================================
    // Command codes
    // ============================================================
    localparam CMD_LOAD    = 8'h01;
    localparam CMD_RUN     = 8'h02;
    localparam CMD_STEP    = 8'h03;
    localparam CMD_REGS    = 8'h04;
    localparam CMD_LATCHES = 8'h05;
    localparam CMD_MEM     = 8'h06;
    localparam CMD_PC      = 8'h07;
    localparam CMD_RESET   = 8'h08;

    // ============================================================
    // FSM states
    // ============================================================
    localparam S_IDLE           = 5'd0;
    localparam S_CMD_DECODE     = 5'd1;
    localparam S_LOAD_LEN_HI   = 5'd2;
    localparam S_LOAD_LEN_LO   = 5'd3;
    localparam S_LOAD_BYTE3    = 5'd4;
    localparam S_LOAD_BYTE2    = 5'd5;
    localparam S_LOAD_BYTE1    = 5'd6;
    localparam S_LOAD_BYTE0    = 5'd7;
    localparam S_LOAD_WRITE    = 5'd8;
    localparam S_RUN           = 5'd9;
    localparam S_STEP          = 5'd10;
    localparam S_SEND_REGS     = 5'd11;
    localparam S_SEND_LATCHES  = 5'd12;
    localparam S_MEM_ADDR_HI   = 5'd13;
    localparam S_MEM_ADDR_LO   = 5'd14;
    localparam S_MEM_LEN_HI    = 5'd15;
    localparam S_MEM_LEN_LO    = 5'd16;
    localparam S_SEND_MEM      = 5'd17;
    localparam S_SEND_PC       = 5'd18;
    localparam S_RESET         = 5'd19;
    localparam S_TX_BYTE       = 5'd20;
    localparam S_TX_WAIT       = 5'd21;

    reg [4:0]  state;
    reg [4:0]  return_state;

    reg [7:0]  cmd;
    reg [15:0] load_len;
    reg [15:0] load_count;
    reg [31:0] instr_buf;

    reg [15:0] mem_addr_param;
    reg [15:0] mem_len_param;
    reg [15:0] mem_count;

    reg [5:0]  reg_index;
    reg [1:0]  byte_index;

    // Latch data array (18 words)
    localparam LATCH_WORDS = 17;
    reg [4:0]  latch_index;
    reg [31:0] latch_data;

    reg [31:0] tx_word;

    // ============================================================
    // Latch data MUX
    // ============================================================
    always @(*) begin
        case (latch_index)
            // IF/ID (2 words)
            5'd0:  latch_data = dbg_if_id_pc;
            5'd1:  latch_data = dbg_if_id_instr;
            // ID/EX (7 words)
            5'd2:  latch_data = dbg_id_ex_pc;
            5'd3:  latch_data = dbg_id_ex_rs1_data;
            5'd4:  latch_data = dbg_id_ex_rs2_data;
            5'd5:  latch_data = dbg_id_ex_imm;
            5'd6:  latch_data = {20'b0, dbg_id_ex_rd, dbg_id_ex_opcode};
            5'd7:  latch_data = dbg_id_ex_alu_op_ctrl;
            // EX/MEM (5 words)
            5'd8:  latch_data = dbg_ex_mem_alu_result;
            5'd9:  latch_data = dbg_ex_mem_rs2_data;
            5'd10: latch_data = {27'b0, dbg_ex_mem_rd};
            5'd11: latch_data = dbg_ex_mem_pc_plus4;
            5'd12: latch_data = dbg_ex_mem_branch_target;
            // MEM/WB (4 words)
            5'd13: latch_data = dbg_mem_wb_read_data;
            5'd14: latch_data = dbg_mem_wb_alu_result;
            5'd15: latch_data = {27'b0, dbg_mem_wb_rd};
            5'd16: latch_data = dbg_mem_wb_pc_plus4;
            default: latch_data = 32'h0;
        endcase
    end

    // ============================================================
    // Main FSM
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            return_state <= S_IDLE;
            pipe_start   <= 1'b0;
            pipe_step    <= 1'b0;
            pipe_mode    <= 1'b0;
            pipe_rst     <= 1'b0;
            prog_we      <= 1'b0;
            prog_addr    <= 32'b0;
            prog_wdata   <= 32'b0;
            tx_valid     <= 1'b0;
            tx_data      <= 8'b0;
            tx_word      <= 32'b0;
            cmd          <= 8'b0;
            load_len     <= 16'b0;
            load_count   <= 16'b0;
            instr_buf    <= 32'b0;
            mem_addr_param <= 16'b0;
            mem_len_param  <= 16'b0;
            mem_count    <= 16'b0;
            reg_index    <= 6'b0;
            byte_index   <= 2'b0;
            latch_index  <= 5'b0;
            debug_reg_addr <= 5'b0;
            debug_mem_addr <= {DATA_MEM_ADDR_WIDTH{1'b0}};
        end
        else begin
            pipe_start <= 1'b0;
            pipe_step  <= 1'b0;
            pipe_rst   <= 1'b0;
            prog_we    <= 1'b0;
            tx_valid   <= 1'b0;

            case (state)
                // ------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        cmd   <= rx_data;
                        state <= S_CMD_DECODE;
                    end
                end

                // ------------------------------------------------
                S_CMD_DECODE: begin
                    case (cmd)
                        CMD_LOAD:    state <= S_LOAD_LEN_HI;
                        CMD_RUN:     state <= S_RUN;
                        CMD_STEP:    state <= S_STEP;
                        CMD_REGS: begin
                            reg_index  <= 0;
                            byte_index <= 0;
                            debug_reg_addr <= 5'd0;
                            state <= S_SEND_REGS;
                        end
                        CMD_LATCHES: begin
                            latch_index <= 0;
                            byte_index  <= 0;
                            state <= S_SEND_LATCHES;
                        end
                        CMD_MEM:     state <= S_MEM_ADDR_HI;
                        CMD_PC: begin
                            tx_word    <= pipe_pc;
                            byte_index <= 0;
                            state <= S_SEND_PC;
                        end
                        CMD_RESET:   state <= S_RESET;
                        default:     state <= S_IDLE;
                    endcase
                end

                // ================================================
                // LOAD program
                // ================================================
                S_LOAD_LEN_HI: begin
                    if (rx_valid) begin
                        load_len[15:8] <= rx_data;
                        state <= S_LOAD_LEN_LO;
                    end
                end

                S_LOAD_LEN_LO: begin
                    if (rx_valid) begin
                        load_len[7:0] <= rx_data;
                        load_count <= 0;
                        state <= S_LOAD_BYTE3;
                    end
                end

                S_LOAD_BYTE3: begin
                    if (load_count >= load_len) begin
                        state <= S_IDLE;
                    end
                    else if (rx_valid) begin
                        instr_buf[31:24] <= rx_data;
                        state <= S_LOAD_BYTE2;
                    end
                end

                S_LOAD_BYTE2: begin
                    if (rx_valid) begin
                        instr_buf[23:16] <= rx_data;
                        state <= S_LOAD_BYTE1;
                    end
                end

                S_LOAD_BYTE1: begin
                    if (rx_valid) begin
                        instr_buf[15:8] <= rx_data;
                        state <= S_LOAD_BYTE0;
                    end
                end

                S_LOAD_BYTE0: begin
                    if (rx_valid) begin
                        instr_buf[7:0] <= rx_data;
                        state <= S_LOAD_WRITE;
                    end
                end

                S_LOAD_WRITE: begin
                    prog_we    <= 1'b1;
                    prog_addr  <= {16'b0, load_count} << 2;
                    prog_wdata <= instr_buf;
                    load_count <= load_count + 1;
                    state      <= S_LOAD_BYTE3;
                end

                // ================================================
                // RUN (continuous)
                // ================================================
                S_RUN: begin
                    pipe_mode  <= 1'b0;
                    pipe_start <= 1'b1;
                    state      <= S_IDLE;
                end

                // ================================================
                // STEP (one cycle)
                // ================================================
                S_STEP: begin
                    pipe_mode <= 1'b1;
                    pipe_step <= 1'b1;
                    state     <= S_IDLE;
                end

                // ================================================
                // SEND REGISTERS (32 x 4 bytes = 128 bytes)
                // ================================================
                S_SEND_REGS: begin
                    if (reg_index >= 6'd32) begin
                        state <= S_IDLE;
                    end
                    else begin
                        case (byte_index)
                            2'd0: begin
                                tx_word      <= debug_reg_data;
                                tx_data      <= debug_reg_data[31:24];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd1;
                                return_state <= S_SEND_REGS;
                                state        <= S_TX_BYTE;
                            end
                            2'd1: begin
                                tx_data      <= tx_word[23:16];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd2;
                                return_state <= S_SEND_REGS;
                                state        <= S_TX_BYTE;
                            end
                            2'd2: begin
                                tx_data      <= tx_word[15:8];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd3;
                                return_state <= S_SEND_REGS;
                                state        <= S_TX_BYTE;
                            end
                            2'd3: begin
                                tx_data      <= tx_word[7:0];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd0;
                                reg_index    <= reg_index + 1;
                                debug_reg_addr <= reg_index[4:0] + 1;
                                return_state <= S_SEND_REGS;
                                state        <= S_TX_BYTE;
                            end
                        endcase
                    end
                end

                // ================================================
                // SEND LATCHES (17 words x 4 bytes = 68 bytes)
                // ================================================
                S_SEND_LATCHES: begin
                    if (latch_index >= LATCH_WORDS) begin
                        state <= S_IDLE;
                    end
                    else begin
                        case (byte_index)
                            2'd0: begin
                                tx_word      <= latch_data;
                                tx_data      <= latch_data[31:24];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd1;
                                return_state <= S_SEND_LATCHES;
                                state        <= S_TX_BYTE;
                            end
                            2'd1: begin
                                tx_data      <= tx_word[23:16];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd2;
                                return_state <= S_SEND_LATCHES;
                                state        <= S_TX_BYTE;
                            end
                            2'd2: begin
                                tx_data      <= tx_word[15:8];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd3;
                                return_state <= S_SEND_LATCHES;
                                state        <= S_TX_BYTE;
                            end
                            2'd3: begin
                                tx_data      <= tx_word[7:0];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd0;
                                latch_index  <= latch_index + 1;
                                return_state <= S_SEND_LATCHES;
                                state        <= S_TX_BYTE;
                            end
                        endcase
                    end
                end

                // ================================================
                // SEND MEMORY (variable length)
                // ================================================
                S_MEM_ADDR_HI: begin
                    if (rx_valid) begin
                        mem_addr_param[15:8] <= rx_data;
                        state <= S_MEM_ADDR_LO;
                    end
                end

                S_MEM_ADDR_LO: begin
                    if (rx_valid) begin
                        mem_addr_param[7:0] <= rx_data;
                        state <= S_MEM_LEN_HI;
                    end
                end

                S_MEM_LEN_HI: begin
                    if (rx_valid) begin
                        mem_len_param[15:8] <= rx_data;
                        state <= S_MEM_LEN_LO;
                    end
                end

                S_MEM_LEN_LO: begin
                    if (rx_valid) begin
                        mem_len_param[7:0] <= rx_data;
                        mem_count  <= 0;
                        byte_index <= 0;
                        debug_mem_addr <= mem_addr_param[DATA_MEM_ADDR_WIDTH-1:0];
                        state <= S_SEND_MEM;
                    end
                end

                S_SEND_MEM: begin
                    if (mem_count >= mem_len_param) begin
                        state <= S_IDLE;
                    end
                    else begin
                        case (byte_index)
                            2'd0: begin
                                tx_word      <= debug_mem_data;
                                tx_data      <= debug_mem_data[31:24];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd1;
                                return_state <= S_SEND_MEM;
                                state        <= S_TX_BYTE;
                            end
                            2'd1: begin
                                tx_data      <= tx_word[23:16];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd2;
                                return_state <= S_SEND_MEM;
                                state        <= S_TX_BYTE;
                            end
                            2'd2: begin
                                tx_data      <= tx_word[15:8];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd3;
                                return_state <= S_SEND_MEM;
                                state        <= S_TX_BYTE;
                            end
                            2'd3: begin
                                tx_data      <= tx_word[7:0];
                                tx_valid     <= 1'b1;
                                byte_index   <= 2'd0;
                                mem_count    <= mem_count + 1;
                                debug_mem_addr <= mem_addr_param[DATA_MEM_ADDR_WIDTH-1:0] +
                                                  (mem_count[DATA_MEM_ADDR_WIDTH-1:0] + 1) * 4;
                                return_state <= S_SEND_MEM;
                                state        <= S_TX_BYTE;
                            end
                        endcase
                    end
                end

                // ================================================
                // SEND PC (4 bytes)
                // ================================================
                S_SEND_PC: begin
                    case (byte_index)
                        2'd0: begin
                            tx_data      <= tx_word[31:24];
                            tx_valid     <= 1'b1;
                            byte_index   <= 2'd1;
                            return_state <= S_SEND_PC;
                            state        <= S_TX_BYTE;
                        end
                        2'd1: begin
                            tx_data      <= tx_word[23:16];
                            tx_valid     <= 1'b1;
                            byte_index   <= 2'd2;
                            return_state <= S_SEND_PC;
                            state        <= S_TX_BYTE;
                        end
                        2'd2: begin
                            tx_data      <= tx_word[15:8];
                            tx_valid     <= 1'b1;
                            byte_index   <= 2'd3;
                            return_state <= S_SEND_PC;
                            state        <= S_TX_BYTE;
                        end
                        2'd3: begin
                            tx_data      <= tx_word[7:0];
                            tx_valid     <= 1'b1;
                            byte_index   <= 2'd0;
                            return_state <= S_IDLE;
                            state        <= S_TX_BYTE;
                        end
                    endcase
                end

                // ================================================
                // RESET pipeline
                // ================================================
                S_RESET: begin
                    pipe_rst <= 1'b1;
                    state    <= S_IDLE;
                end

                // ================================================
                // TX byte: delay de 1 ciclo para que UART TX active busy
                // ================================================
                S_TX_BYTE: begin
                    state <= S_TX_WAIT;
                end

                // ================================================
                // TX wait: espera que el UART TX deje de estar busy
                // ================================================
                S_TX_WAIT: begin
                    if (!tx_busy)
                        state <= return_state;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
