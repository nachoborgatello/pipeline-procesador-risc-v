module alu_control (
    input  wire [1:0] ALUOp,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    input  wire [6:0] opcode,
    output reg  [3:0] alu_ctrl
);

    // Códigos internos de ALU (deben coincidir con alu.v)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;
    localparam ALU_PASS = 4'b1010;

    // Opcodes RV32I que nos interesan acá
    localparam OPCODE_OP      = 7'b0110011; // R-type
    localparam OPCODE_OP_IMM  = 7'b0010011; // I-type aritmética
    localparam OPCODE_LOAD    = 7'b0000011; // loads
    localparam OPCODE_STORE   = 7'b0100011; // stores
    localparam OPCODE_BRANCH  = 7'b1100011; // branches
    localparam OPCODE_LUI     = 7'b0110111; // lui
    localparam OPCODE_JALR    = 7'b1100111; // jalr

    always @(*) begin
        case (ALUOp)

            // Operaciones simples: suma para direcciones, addi, load/store, etc.
            2'b00: begin
                if (opcode == OPCODE_LUI)
                    alu_ctrl = ALU_PASS;  // resultado = inmediato
                else
                    alu_ctrl = ALU_ADD;
            end

            // Branch: usamos resta para obtener zero cuando rs1 == rs2
            2'b01: begin
                alu_ctrl = ALU_SUB;
            end

            // R-type / I-type aritmético-lógico
            2'b10: begin
                case (funct3)
                    3'b000: begin
                        // sub solo aplica en R-type con funct7 = 0100000
                        if ((opcode == OPCODE_OP) && (funct7 == 7'b0100000))
                            alu_ctrl = ALU_SUB;
                        else
                            alu_ctrl = ALU_ADD; // add / addi
                    end

                    3'b001: alu_ctrl = ALU_SLL;  // sll / slli
                    3'b010: alu_ctrl = ALU_SLT;  // slt / slti
                    3'b011: alu_ctrl = ALU_SLTU; // sltu / sltiu
                    3'b100: alu_ctrl = ALU_XOR;  // xor / xori

                    3'b101: begin
                        // sra / srai => funct7 = 0100000
                        if (funct7 == 7'b0100000)
                            alu_ctrl = ALU_SRA;
                        else
                            alu_ctrl = ALU_SRL;  // srl / srli
                    end

                    3'b110: alu_ctrl = ALU_OR;   // or / ori
                    3'b111: alu_ctrl = ALU_AND;  // and / andi

                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            default: begin
                alu_ctrl = ALU_ADD;
            end
        endcase
    end

endmodule