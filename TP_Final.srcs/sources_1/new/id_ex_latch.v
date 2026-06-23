module id_ex_latch (
    input  wire        clk,
    input  wire        rst,
    input  wire        write_en,
    input  wire        flush,

    input  wire [31:0] id_pc,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire [31:0] id_imm,

    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [4:0]  id_rd,

    input  wire [2:0]  id_funct3,
    input  wire [6:0]  id_funct7,
    input  wire [6:0]  id_opcode,

    input  wire        id_Branch,
    input  wire        id_MemRead,
    input  wire        id_MemtoReg,
    input  wire [1:0]  id_ALUOp,
    input  wire        id_MemWrite,
    input  wire        id_ALUSrc,
    input  wire        id_RegWrite,
    input  wire        id_Jump,
    input  wire        id_IsJALR,
    input  wire        id_Halt,

    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg  [31:0] ex_imm,

    output reg  [4:0]  ex_rs1,
    output reg  [4:0]  ex_rs2,
    output reg  [4:0]  ex_rd,

    output reg  [2:0]  ex_funct3,
    output reg  [6:0]  ex_funct7,
    output reg  [6:0]  ex_opcode,

    output reg         ex_Branch,
    output reg         ex_MemRead,
    output reg         ex_MemtoReg,
    output reg  [1:0]  ex_ALUOp,
    output reg         ex_MemWrite,
    output reg         ex_ALUSrc,
    output reg         ex_RegWrite,
    output reg         ex_Jump,
    output reg         ex_IsJALR,
    output reg         ex_Halt
);

    always @(posedge clk) begin
        if (rst || flush) begin
            ex_pc        <= 32'b0;
            ex_rs1_data  <= 32'b0;
            ex_rs2_data  <= 32'b0;
            ex_imm       <= 32'b0;

            ex_rs1       <= 5'b0;
            ex_rs2       <= 5'b0;
            ex_rd        <= 5'b0;

            ex_funct3    <= 3'b0;
            ex_funct7    <= 7'b0;
            ex_opcode    <= 7'b0;

            ex_Branch    <= 1'b0;
            ex_MemRead   <= 1'b0;
            ex_MemtoReg  <= 1'b0;
            ex_ALUOp     <= 2'b0;
            ex_MemWrite  <= 1'b0;
            ex_ALUSrc    <= 1'b0;
            ex_RegWrite  <= 1'b0;
            ex_Jump      <= 1'b0;
            ex_IsJALR    <= 1'b0;
            ex_Halt      <= 1'b0;
        end
        else if (write_en) begin
            ex_pc        <= id_pc;
            ex_rs1_data  <= id_rs1_data;
            ex_rs2_data  <= id_rs2_data;
            ex_imm       <= id_imm;

            ex_rs1       <= id_rs1;
            ex_rs2       <= id_rs2;
            ex_rd        <= id_rd;

            ex_funct3    <= id_funct3;
            ex_funct7    <= id_funct7;
            ex_opcode    <= id_opcode;

            ex_Branch    <= id_Branch;
            ex_MemRead   <= id_MemRead;
            ex_MemtoReg  <= id_MemtoReg;
            ex_ALUOp     <= id_ALUOp;
            ex_MemWrite  <= id_MemWrite;
            ex_ALUSrc    <= id_ALUSrc;
            ex_RegWrite  <= id_RegWrite;
            ex_Jump      <= id_Jump;
            ex_IsJALR    <= id_IsJALR;
            ex_Halt      <= id_Halt;
        end
    end

endmodule
