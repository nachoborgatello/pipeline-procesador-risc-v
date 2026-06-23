`timescale 1ns / 1ps

module wb_stage (
    input  wire [31:0] wb_read_data,
    input  wire [31:0] wb_alu_result,
    input  wire [4:0]  wb_rd,
    input  wire        wb_MemtoReg,
    input  wire        wb_RegWrite,
    input  wire [31:0] wb_pc_plus4,
    input  wire        wb_IsJump,

    output wire [31:0] rf_write_data,
    output wire [4:0]  rf_rd_addr,
    output wire        rf_reg_write
);

    // Selección del dato a escribir:
    // - IsJump=1 (JAL/JALR): PC+4 (dirección de retorno)
    // - MemtoReg=1 (LOAD): dato leído de memoria
    // - default: resultado de la ALU
    assign rf_write_data = wb_IsJump  ? wb_pc_plus4  :
                           wb_MemtoReg ? wb_read_data :
                                         wb_alu_result;

    assign rf_rd_addr  = wb_rd;
    assign rf_reg_write = wb_RegWrite;

endmodule
