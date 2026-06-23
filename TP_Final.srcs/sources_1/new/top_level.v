`timescale 1ns/1ps

module top_level #(
    parameter CLK_FREQ            = 100_000_000,   // Frecuencia REAL del sistema (salida del Clock Wizard)
    parameter BAUD_RATE           = 115200,
    parameter IMEM_DEPTH          = 256,
    parameter IMEM_ADDR_WIDTH     = 8,
    parameter DATA_MEM_ADDR_WIDTH = 8
)(
    input  wire clk,          // 100 MHz de la placa (pin W5)
    input  wire rst,          // btnC (U18), active high
    input  wire uart_rx_i,
    output wire uart_tx_o
);

    // ============================================================
    // Clock Wizard: 100 MHz (placa) -> 90 MHz (sistema)
    // Se inserta el MMCM entre el pin de clock y el diseño para
    // correr por debajo del Fmax y cerrar timing sin gating manual.
    // ============================================================
    wire clk_sys;      // clock del sistema (90 MHz)
    wire clk_locked;   // '1' cuando el MMCM se estabiliza

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk),         // 100 MHz de la placa
        .reset    (rst),         // reset externo (active high)
        .clk_out1 (clk_sys),     // 90 MHz al diseño
        .locked   (clk_locked)
    );

    // ============================================================
    // Sincronizadores de entradas asincrónicas
    // ============================================================
    // rst (botón btnC) y uart_rx_i son señales externas asincrónicas al
    // dominio de clk_sys. Sin sincronizar pueden:
    //   1) Causar metastabilidad en los FFs que las consumen.
    //   2) Generar glitches que disparan resets espurios (warning LUTAR-1)
    //      o framing errors en el UART RX.
    // El atributo ASYNC_REG le indica a Vivado que coloque los 2 FFs
    // del sincronizador físicamente juntos (misma slice) y NO los
    // optimice, garantizando el comportamiento clásico de sincronización
    // contra metastabilidad.
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync_reg;
    (* ASYNC_REG = "TRUE" *) reg [1:0] uart_rx_sync_reg;

    always @(posedge clk_sys) begin
        rst_sync_reg     <= {rst_sync_reg[0],     rst};
        uart_rx_sync_reg <= {uart_rx_sync_reg[0], uart_rx_i};
    end

    wire rst_synced     = rst_sync_reg[1];
    wire uart_rx_synced = uart_rx_sync_reg[1];

    // Reset del sistema: activo con reset externo sincronizado O mientras
    // el MMCM todavía no engancha (locked=0). Como ambas señales son
    // sincronicas a clk_sys, sys_rst queda limpio (sin glitches) y los
    // optimizadores de Vivado pueden mapearlo a los pines R sincronicos
    // sin riesgo de resets espurios.
    wire sys_rst = rst_synced | ~clk_locked;

    // Debug Unit <-> Pipeline
    wire        pipe_start;
    wire        pipe_step;
    wire        pipe_mode;
    wire        pipe_rst;
    wire        pipe_halted;
    wire [31:0] pipe_pc;

    wire        prog_we;
    wire [31:0] prog_addr;
    wire [31:0] prog_wdata;

    wire [4:0]  debug_reg_addr;
    wire [31:0] debug_reg_data;
    wire [DATA_MEM_ADDR_WIDTH-1:0] debug_mem_addr;
    wire [31:0] debug_mem_data;

    // Latch debug wires
    wire [31:0] dbg_if_id_pc;
    wire [31:0] dbg_if_id_instr;

    wire [31:0] dbg_id_ex_pc;
    wire [31:0] dbg_id_ex_rs1_data;
    wire [31:0] dbg_id_ex_rs2_data;
    wire [31:0] dbg_id_ex_imm;
    wire [4:0]  dbg_id_ex_rd;
    wire [6:0]  dbg_id_ex_opcode;
    wire [31:0] dbg_id_ex_alu_op_ctrl;

    wire [31:0] dbg_ex_mem_alu_result;
    wire [31:0] dbg_ex_mem_rs2_data;
    wire [4:0]  dbg_ex_mem_rd;
    wire [31:0] dbg_ex_mem_pc_plus4;
    wire [31:0] dbg_ex_mem_branch_target;

    wire [31:0] dbg_mem_wb_read_data;
    wire [31:0] dbg_mem_wb_alu_result;
    wire [4:0]  dbg_mem_wb_rd;
    wire [31:0] dbg_mem_wb_pc_plus4;

    // Pipeline reset = system rst (ext + MMCM lock) OR debug-commanded rst
    wire pipeline_rst = sys_rst | pipe_rst;

    // ============================================================
    // RISC-V Pipeline
    // ============================================================
    riscv_pipeline_top #(
        .IMEM_DEPTH          (IMEM_DEPTH),
        .IMEM_ADDR_WIDTH     (IMEM_ADDR_WIDTH),
        .DATA_MEM_ADDR_WIDTH (DATA_MEM_ADDR_WIDTH)
    ) u_pipeline (
        .clk       (clk_sys),
        .rst       (pipeline_rst),
        .prog_we   (prog_we),
        .prog_addr (prog_addr),
        .prog_wdata(prog_wdata),

        .i_start   (pipe_start),
        .i_step    (pipe_step),
        .i_mode    (pipe_mode),
        .o_halted  (pipe_halted),
        .o_pc      (pipe_pc),

        .debug_reg_addr (debug_reg_addr),
        .debug_reg_data (debug_reg_data),
        .debug_mem_addr (debug_mem_addr),
        .debug_mem_data (debug_mem_data),

        .dbg_if_id_pc         (dbg_if_id_pc),
        .dbg_if_id_instr      (dbg_if_id_instr),
        .dbg_id_ex_pc         (dbg_id_ex_pc),
        .dbg_id_ex_rs1_data   (dbg_id_ex_rs1_data),
        .dbg_id_ex_rs2_data   (dbg_id_ex_rs2_data),
        .dbg_id_ex_imm        (dbg_id_ex_imm),
        .dbg_id_ex_rd         (dbg_id_ex_rd),
        .dbg_id_ex_opcode     (dbg_id_ex_opcode),
        .dbg_id_ex_alu_op_ctrl(dbg_id_ex_alu_op_ctrl),
        .dbg_ex_mem_alu_result    (dbg_ex_mem_alu_result),
        .dbg_ex_mem_rs2_data      (dbg_ex_mem_rs2_data),
        .dbg_ex_mem_rd            (dbg_ex_mem_rd),
        .dbg_ex_mem_pc_plus4      (dbg_ex_mem_pc_plus4),
        .dbg_ex_mem_branch_target (dbg_ex_mem_branch_target),
        .dbg_mem_wb_read_data  (dbg_mem_wb_read_data),
        .dbg_mem_wb_alu_result (dbg_mem_wb_alu_result),
        .dbg_mem_wb_rd         (dbg_mem_wb_rd),
        .dbg_mem_wb_pc_plus4   (dbg_mem_wb_pc_plus4)
    );

    // ============================================================
    // Debug Unit (UART + FSM)
    // ============================================================
    debug_unit #(
        .CLK_FREQ            (CLK_FREQ),
        .BAUD_RATE           (BAUD_RATE),
        .DATA_MEM_ADDR_WIDTH (DATA_MEM_ADDR_WIDTH)
    ) u_debug (
        .clk        (clk_sys),
        .rst        (sys_rst),
        .uart_rx_i  (uart_rx_synced),
        .uart_tx_o  (uart_tx_o),

        .pipe_start (pipe_start),
        .pipe_step  (pipe_step),
        .pipe_mode  (pipe_mode),
        .pipe_rst   (pipe_rst),
        .pipe_halted(pipe_halted),

        .prog_we    (prog_we),
        .prog_addr  (prog_addr),
        .prog_wdata (prog_wdata),

        .debug_reg_addr (debug_reg_addr),
        .debug_reg_data (debug_reg_data),
        .debug_mem_addr (debug_mem_addr),
        .debug_mem_data (debug_mem_data),

        .pipe_pc    (pipe_pc),

        .dbg_if_id_pc         (dbg_if_id_pc),
        .dbg_if_id_instr      (dbg_if_id_instr),
        .dbg_id_ex_pc         (dbg_id_ex_pc),
        .dbg_id_ex_rs1_data   (dbg_id_ex_rs1_data),
        .dbg_id_ex_rs2_data   (dbg_id_ex_rs2_data),
        .dbg_id_ex_imm        (dbg_id_ex_imm),
        .dbg_id_ex_rd         (dbg_id_ex_rd),
        .dbg_id_ex_opcode     (dbg_id_ex_opcode),
        .dbg_id_ex_alu_op_ctrl(dbg_id_ex_alu_op_ctrl),
        .dbg_ex_mem_alu_result    (dbg_ex_mem_alu_result),
        .dbg_ex_mem_rs2_data      (dbg_ex_mem_rs2_data),
        .dbg_ex_mem_rd            (dbg_ex_mem_rd),
        .dbg_ex_mem_pc_plus4      (dbg_ex_mem_pc_plus4),
        .dbg_ex_mem_branch_target (dbg_ex_mem_branch_target),
        .dbg_mem_wb_read_data  (dbg_mem_wb_read_data),
        .dbg_mem_wb_alu_result (dbg_mem_wb_alu_result),
        .dbg_mem_wb_rd         (dbg_mem_wb_rd),
        .dbg_mem_wb_pc_plus4   (dbg_mem_wb_pc_plus4)
    );

endmodule
