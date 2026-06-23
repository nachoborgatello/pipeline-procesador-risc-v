module control_unit (
    input  wire [6:0] opcode,

    output reg        Branch,
    output reg        MemRead,
    output reg        MemtoReg,
    output reg [1:0]  ALUOp,
    output reg        MemWrite,
    output reg        ALUSrc,
    output reg        RegWrite,
    output reg        Jump,
    output reg        IsJALR,
    output reg        Halt
);

    localparam OPCODE_LOAD   = 7'b0000011; // lb, lh, lw, lbu, lhu
    localparam OPCODE_OP_IMM = 7'b0010011; // addi, andi, ori, xori, slli, srli, srai, slti, sltiu
    localparam OPCODE_STORE  = 7'b0100011; // sb, sh, sw
    localparam OPCODE_OP     = 7'b0110011; // add, sub, and, or, xor, sll, srl, sra, slt, sltu
    localparam OPCODE_BRANCH = 7'b1100011; // beq, bne
    localparam OPCODE_LUI    = 7'b0110111; // lui
    localparam OPCODE_JAL    = 7'b1101111; // jal
    localparam OPCODE_JALR   = 7'b1100111; // jalr
    localparam OPCODE_HALT   = 7'b1111111; // halt (custom, instr = 32'hFFFFFFFF)

    // ALUOp encoding:
    // 00 -> ADD (load/store address, LUI via opcode override, JAL/JALR)
    // 01 -> branch compare (SUB)
    // 10 -> funct3/funct7 determined

    always @(*) begin
        Branch   = 1'b0;
        MemRead  = 1'b0;
        MemtoReg = 1'b0;
        ALUOp    = 2'b00;
        MemWrite = 1'b0;
        ALUSrc   = 1'b0;
        RegWrite = 1'b0;
        Jump     = 1'b0;
        IsJALR   = 1'b0;
        Halt     = 1'b0;

        case (opcode)

            OPCODE_OP: begin
                ALUOp    = 2'b10;
                RegWrite = 1'b1;
            end

            OPCODE_OP_IMM: begin
                ALUOp    = 2'b10;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
            end

            OPCODE_LOAD: begin
                MemRead  = 1'b1;
                MemtoReg = 1'b1;
                ALUOp    = 2'b00;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
            end

            OPCODE_STORE: begin
                ALUOp    = 2'b00;
                MemWrite = 1'b1;
                ALUSrc   = 1'b1;
            end

            OPCODE_BRANCH: begin
                Branch   = 1'b1;
                ALUOp    = 2'b01;
            end

            // LUI: ALU_PASS(imm) -> rd
            // alu_control detecta opcode LUI con ALUOp=00 y devuelve ALU_PASS
            OPCODE_LUI: begin
                ALUOp    = 2'b00;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
            end

            // JAL: salto incondicional, escribe PC+4 en rd
            // target = PC + imm_J (calculado como branch_target en EX)
            OPCODE_JAL: begin
                ALUOp    = 2'b00;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                Jump     = 1'b1;
            end

            // JALR: salto a rs1+imm, escribe PC+4 en rd
            // target = (rs1 + imm_I) con bit[0]=0 (ALU_ADD via alu_result)
            OPCODE_JALR: begin
                ALUOp    = 2'b00;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                Jump     = 1'b1;
                IsJALR   = 1'b1;
            end

            OPCODE_HALT: begin
                Halt = 1'b1;
            end

            default: begin end

        endcase
    end

endmodule
