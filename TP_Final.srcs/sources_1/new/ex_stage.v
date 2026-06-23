module ex_stage (
    // Entradas desde ID/EX
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_rs1_data,
    input  wire [31:0] ex_rs2_data,
    input  wire [31:0] ex_imm,

    input  wire [4:0]  ex_rs1,
    input  wire [4:0]  ex_rs2,
    input  wire [4:0]  ex_rd,

    input  wire [2:0]  ex_funct3,
    input  wire [6:0]  ex_funct7,
    input  wire [6:0]  ex_opcode,

    input  wire        ex_Branch,
    input  wire        ex_MemRead,
    input  wire        ex_MemtoReg,
    input  wire [1:0]  ex_ALUOp,
    input  wire        ex_MemWrite,
    input  wire        ex_ALUSrc,
    input  wire        ex_RegWrite,
    input  wire        ex_Jump,
    input  wire        ex_IsJALR,
    input  wire        ex_Halt,

    // Salidas hacia EX/MEM
    output wire [31:0] ex_branch_target,
    output wire [31:0] ex_pc_plus4,
    output reg         ex_zero,
    output wire [31:0] ex_alu_result,
    output wire [31:0] ex_rs2_data_out,
    output wire [4:0]  ex_rd_out,

    output wire        ex_Branch_out,
    output wire        ex_MemRead_out,
    output wire        ex_MemWrite_out,
    output wire        ex_MemtoReg_out,
    output wire        ex_RegWrite_out,
    output wire        ex_Jump_out,
    output wire        ex_IsJALR_out,
    output wire        ex_Halt_out
);

    wire [31:0] alu_operand_b;
    wire [3:0]  alu_ctrl;
    wire        alu_zero_raw;

    reg         branch_condition;

    assign alu_operand_b  = (ex_ALUSrc) ? ex_imm : ex_rs2_data;

    // branch_target = PC + imm (B-type offset ya tiene LSB=0 desde imm_gen)
    // Para JAL: misma formula con imm_J
    assign ex_branch_target = ex_pc + ex_imm;

    // PC+4 para escribir en rd en JAL/JALR
    assign ex_pc_plus4 = ex_pc + 32'd4;

    alu_control u_alu_control (
        .ALUOp    (ex_ALUOp),
        .funct3   (ex_funct3),
        .funct7   (ex_funct7),
        .opcode   (ex_opcode),
        .alu_ctrl (alu_ctrl)
    );

    alu u_alu (
        .a        (ex_rs1_data),
        .b        (alu_operand_b),
        .alu_ctrl (alu_ctrl),
        .result   (ex_alu_result),
        .zero     (alu_zero_raw)
    );

    // Lógica de condición de branch
    always @(*) begin
        branch_condition = 1'b0;

        if (ex_Branch) begin
            case (ex_funct3)
                3'b000: branch_condition =  alu_zero_raw; // beq
                3'b001: branch_condition = ~alu_zero_raw; // bne
                default: branch_condition = 1'b0;
            endcase
        end

        if (ex_Branch)
            ex_zero = branch_condition;
        else
            ex_zero = alu_zero_raw;
    end

    assign ex_rs2_data_out  = ex_rs2_data;
    assign ex_rd_out        = ex_rd;

    assign ex_Branch_out    = ex_Branch;
    assign ex_MemRead_out   = ex_MemRead;
    assign ex_MemWrite_out  = ex_MemWrite;
    assign ex_MemtoReg_out  = ex_MemtoReg;
    assign ex_RegWrite_out  = ex_RegWrite;
    assign ex_Jump_out      = ex_Jump;
    assign ex_IsJALR_out    = ex_IsJALR;
    assign ex_Halt_out      = ex_Halt;

endmodule
