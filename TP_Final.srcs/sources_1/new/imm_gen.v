module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm_out
);

    wire [6:0] opcode;
    wire [2:0] funct3;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];

    // Opcodes RV32I
    localparam OPCODE_LOAD   = 7'b0000011; // lb, lh, lw, lbu, lhu
    localparam OPCODE_OP_IMM = 7'b0010011; // addi, andi, ori, xori, slti, sltiu, slli, srli, srai
    localparam OPCODE_JALR   = 7'b1100111; // jalr
    localparam OPCODE_STORE  = 7'b0100011; // sb, sh, sw
    localparam OPCODE_BRANCH = 7'b1100011; // beq, bne
    localparam OPCODE_LUI    = 7'b0110111; // lui
    localparam OPCODE_AUIPC  = 7'b0010111; // opcional, por compatibilidad
    localparam OPCODE_JAL    = 7'b1101111; // jal
    localparam OPCODE_OP     = 7'b0110011; // R-type

    always @(*) begin
        case (opcode)

            // I-type: loads, jalr e inmediatas aritméticas/lógicas
            OPCODE_LOAD,
            OPCODE_JALR: begin
                imm_out = {{20{instr[31]}}, instr[31:20]};
            end

            OPCODE_OP_IMM: begin
                // Para shifts inmediatos (slli, srli, srai) usamos shamt zero-extend
                if ((funct3 == 3'b001) || (funct3 == 3'b101))
                    imm_out = {27'b0, instr[24:20]};
                else
                    imm_out = {{20{instr[31]}}, instr[31:20]};
            end

            // S-type: stores
            OPCODE_STORE: begin
                imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-type: branches
            OPCODE_BRANCH: begin
                imm_out = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};
            end

            // U-type: lui / auipc
            OPCODE_LUI,
            OPCODE_AUIPC: begin
                imm_out = {instr[31:12], 12'b0};
            end

            // J-type: jal
            OPCODE_JAL: begin
                imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                           instr[20], instr[30:21], 1'b0};
            end

            // R-type o default
            OPCODE_OP: begin
                imm_out = 32'b0;
            end

            default: begin
                imm_out = 32'b0;
            end
        endcase
    end

endmodule