module ex_mem_latch (
    input  wire        clk,
    input  wire        rst,
    input  wire        write_en,
    input  wire        flush,

    // Entradas desde EX
    input  wire [31:0] ex_branch_target,
    input  wire [31:0] ex_pc_plus4,
    input  wire        ex_zero,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rs2_data_out,
    input  wire [4:0]  ex_rd_out,

    input  wire        ex_Branch,
    input  wire        ex_MemRead,
    input  wire        ex_MemWrite,
    input  wire        ex_MemtoReg,
    input  wire        ex_RegWrite,
    input  wire [2:0]  ex_funct3,
    input  wire        ex_Jump,
    input  wire        ex_IsJALR,
    input  wire        ex_Halt,

    // Salidas hacia MEM
    output reg  [31:0] mem_branch_target,
    output reg  [31:0] mem_pc_plus4,
    output reg         mem_zero,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_rs2_data,
    output reg  [4:0]  mem_rd,

    output reg         mem_Branch,
    output reg         mem_MemRead,
    output reg         mem_MemWrite,
    output reg         mem_MemtoReg,
    output reg         mem_RegWrite,
    output reg  [2:0]  mem_funct3,
    output reg         mem_Jump,
    output reg         mem_IsJALR,
    output reg         mem_Halt
);

    always @(posedge clk) begin
        if (rst || flush) begin
            mem_branch_target <= 32'b0;
            mem_pc_plus4      <= 32'b0;
            mem_zero          <= 1'b0;
            mem_alu_result    <= 32'b0;
            mem_rs2_data      <= 32'b0;
            mem_rd            <= 5'b0;

            mem_Branch        <= 1'b0;
            mem_MemRead       <= 1'b0;
            mem_MemWrite      <= 1'b0;
            mem_MemtoReg      <= 1'b0;
            mem_RegWrite      <= 1'b0;
            mem_funct3        <= 3'b0;
            mem_Jump          <= 1'b0;
            mem_IsJALR        <= 1'b0;
            mem_Halt          <= 1'b0;
        end
        else if (write_en) begin
            mem_branch_target <= ex_branch_target;
            mem_pc_plus4      <= ex_pc_plus4;
            mem_zero          <= ex_zero;
            mem_alu_result    <= ex_alu_result;
            mem_rs2_data      <= ex_rs2_data_out;
            mem_rd            <= ex_rd_out;

            mem_Branch        <= ex_Branch;
            mem_MemRead       <= ex_MemRead;
            mem_MemWrite      <= ex_MemWrite;
            mem_MemtoReg      <= ex_MemtoReg;
            mem_RegWrite      <= ex_RegWrite;
            mem_funct3        <= ex_funct3;
            mem_Jump          <= ex_Jump;
            mem_IsJALR        <= ex_IsJALR;
            mem_Halt          <= ex_Halt;
        end
    end

endmodule
