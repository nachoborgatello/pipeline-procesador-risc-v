`timescale 1ns/1ps

module if_stage #
(
    parameter IMEM_DEPTH = 256,
    parameter IMEM_ADDR_WIDTH = 8
)
(
    input  wire        clk,
    input  wire        rst,
    input  wire        pc_en,
    input  wire [31:0] pc_next,

    // Puerto de programación de la memoria de instrucciones
    input  wire        prog_we,
    input  wire [31:0] prog_addr,
    input  wire [31:0] prog_wdata,

    // Salidas de la etapa IF
    output wire [31:0] pc,
    output wire [31:0] pc_plus4,
    output wire [31:0] instr
);

    // PC + 4
    assign pc_plus4 = pc + 32'd4;

    // Program Counter
    program_counter pc_reg (
        .clk    (clk),
        .rst    (rst),
        .pc_en  (pc_en),
        .pc_next(pc_next),
        .pc     (pc)
    );

    // Instruction Memory
    instruction_memory #
    (
        .DEPTH(IMEM_DEPTH),
        .ADDR_WIDTH(IMEM_ADDR_WIDTH)
    )
    imem
    (
        .clk       (clk),
        .addr      (pc),
        .instr     (instr),
        .prog_we   (prog_we),
        .prog_addr (prog_addr),
        .prog_wdata(prog_wdata)
    );

endmodule