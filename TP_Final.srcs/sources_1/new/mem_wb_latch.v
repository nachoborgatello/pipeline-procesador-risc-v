`timescale 1ns / 1ps

module mem_wb_latch (
    input  wire        clk,
    input  wire        rst,
    input  wire        write_en,
    input  wire        flush,

    // Entradas desde MEM stage
    input  wire [31:0] mem_read_data,
    input  wire [31:0] mem_alu_result,
    input  wire [4:0]  mem_rd,
    input  wire        mem_MemtoReg,
    input  wire        mem_RegWrite,
    input  wire [31:0] mem_pc_plus4,
    input  wire        mem_IsJump,
    input  wire        mem_Halt,

    // Salidas registradas hacia WB stage
    output reg  [31:0] wb_read_data,
    output reg  [31:0] wb_alu_result,
    output reg  [4:0]  wb_rd,
    output reg         wb_MemtoReg,
    output reg         wb_RegWrite,
    output reg  [31:0] wb_pc_plus4,
    output reg         wb_IsJump,
    output reg         wb_Halt
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_read_data  <= 32'b0;
            wb_alu_result <= 32'b0;
            wb_rd         <= 5'b0;
            wb_MemtoReg   <= 1'b0;
            wb_RegWrite   <= 1'b0;
            wb_pc_plus4   <= 32'b0;
            wb_IsJump     <= 1'b0;
            wb_Halt       <= 1'b0;
        end
        else if (flush) begin
            wb_read_data  <= 32'b0;
            wb_alu_result <= 32'b0;
            wb_rd         <= 5'b0;
            wb_MemtoReg   <= 1'b0;
            wb_RegWrite   <= 1'b0;
            wb_pc_plus4   <= 32'b0;
            wb_IsJump     <= 1'b0;
            wb_Halt       <= 1'b0;
        end
        else if (write_en) begin
            wb_read_data  <= mem_read_data;
            wb_alu_result <= mem_alu_result;
            wb_rd         <= mem_rd;
            wb_MemtoReg   <= mem_MemtoReg;
            wb_RegWrite   <= mem_RegWrite;
            wb_pc_plus4   <= mem_pc_plus4;
            wb_IsJump     <= mem_IsJump;
            wb_Halt       <= mem_Halt;
        end
    end

endmodule
