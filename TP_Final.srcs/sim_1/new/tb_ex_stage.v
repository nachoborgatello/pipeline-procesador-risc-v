`timescale 1ns / 1ps

module tb_ex_stage;

    // =====================================
    // Entradas al DUT
    // =====================================
    reg  [31:0] ex_pc;
    reg  [31:0] ex_rs1_data;
    reg  [31:0] ex_rs2_data;
    reg  [31:0] ex_imm;

    reg  [4:0]  ex_rs1;
    reg  [4:0]  ex_rs2;
    reg  [4:0]  ex_rd;

    reg  [2:0]  ex_funct3;
    reg  [6:0]  ex_funct7;
    reg  [6:0]  ex_opcode;

    reg         ex_Branch;
    reg         ex_MemRead;
    reg         ex_MemtoReg;
    reg  [1:0]  ex_ALUOp;
    reg         ex_MemWrite;
    reg         ex_ALUSrc;
    reg         ex_RegWrite;

    // =====================================
    // Salidas del DUT
    // =====================================
    wire [31:0] ex_branch_target;
    wire        ex_zero;
    wire [31:0] ex_alu_result;
    wire [31:0] ex_rs2_data_out;
    wire [4:0]  ex_rd_out;

    wire        ex_Branch_out;
    wire        ex_MemRead_out;
    wire        ex_MemWrite_out;
    wire        ex_MemtoReg_out;
    wire        ex_RegWrite_out;

    // =====================================
    // Instancia del DUT
    // =====================================
    ex_stage dut (
        .ex_pc(ex_pc),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),

        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),

        .ex_funct3(ex_funct3),
        .ex_funct7(ex_funct7),
        .ex_opcode(ex_opcode),

        .ex_Branch(ex_Branch),
        .ex_MemRead(ex_MemRead),
        .ex_MemtoReg(ex_MemtoReg),
        .ex_ALUOp(ex_ALUOp),
        .ex_MemWrite(ex_MemWrite),
        .ex_ALUSrc(ex_ALUSrc),
        .ex_RegWrite(ex_RegWrite),

        .ex_branch_target(ex_branch_target),
        .ex_zero(ex_zero),
        .ex_alu_result(ex_alu_result),
        .ex_rs2_data_out(ex_rs2_data_out),
        .ex_rd_out(ex_rd_out),

        .ex_Branch_out(ex_Branch_out),
        .ex_MemRead_out(ex_MemRead_out),
        .ex_MemWrite_out(ex_MemWrite_out),
        .ex_MemtoReg_out(ex_MemtoReg_out),
        .ex_RegWrite_out(ex_RegWrite_out)
    );

    // =====================================
    // Constantes útiles
    // =====================================
    localparam OPCODE_OP      = 7'b0110011;
    localparam OPCODE_OP_IMM  = 7'b0010011;
    localparam OPCODE_LOAD    = 7'b0000011;
    localparam OPCODE_STORE   = 7'b0100011;
    localparam OPCODE_BRANCH  = 7'b1100011;
    localparam OPCODE_LUI     = 7'b0110111;

    integer errors;

    // =====================================
    // Tareas auxiliares
    // =====================================
    task clear_inputs;
    begin
        ex_pc        = 32'b0;
        ex_rs1_data  = 32'b0;
        ex_rs2_data  = 32'b0;
        ex_imm       = 32'b0;

        ex_rs1       = 5'b0;
        ex_rs2       = 5'b0;
        ex_rd        = 5'b0;

        ex_funct3    = 3'b0;
        ex_funct7    = 7'b0;
        ex_opcode    = 7'b0;

        ex_Branch    = 1'b0;
        ex_MemRead   = 1'b0;
        ex_MemtoReg  = 1'b0;
        ex_ALUOp     = 2'b0;
        ex_MemWrite  = 1'b0;
        ex_ALUSrc    = 1'b0;
        ex_RegWrite  = 1'b0;
    end
    endtask

    task check32;
        input [8*50:1] test_name;
        input [31:0] actual;
        input [31:0] expected;
    begin
        if (actual !== expected) begin
            $display("[ERROR] %0s -> actual = 0x%08h, expected = 0x%08h",
                     test_name, actual, expected);
            errors = errors + 1;
        end
        else begin
            $display("[ OK ] %0s -> 0x%08h", test_name, actual);
        end
    end
    endtask

    task check1;
        input [8*50:1] test_name;
        input actual;
        input expected;
    begin
        if (actual !== expected) begin
            $display("[ERROR] %0s -> actual = %b, expected = %b",
                     test_name, actual, expected);
            errors = errors + 1;
        end
        else begin
            $display("[ OK ] %0s -> %b", test_name, actual);
        end
    end
    endtask

    task check5;
        input [8*50:1] test_name;
        input [4:0] actual;
        input [4:0] expected;
    begin
        if (actual !== expected) begin
            $display("[ERROR] %0s -> actual = %0d, expected = %0d",
                     test_name, actual, expected);
            errors = errors + 1;
        end
        else begin
            $display("[ OK ] %0s -> %0d", test_name, actual);
        end
    end
    endtask

    // =====================================
    // Estímulos
    // =====================================
    initial begin
        errors = 0;

        $display("========================================");
        $display(" Iniciando testbench actualizado de ex_stage");
        $display("========================================");

        // -------------------------------------------------
        // TEST 1: ADD (R-type)
        // 10 + 20 = 30
        // No branch -> ex_zero debe reflejar zero real ALU
        // branch_target = pc + (imm << 1)
        // -------------------------------------------------
        clear_inputs;
        ex_pc        = 32'h00000010;
        ex_rs1_data  = 32'd10;
        ex_rs2_data  = 32'd20;
        ex_imm       = 32'd4;       // branch target no importa funcionalmente acá, pero se chequea
        ex_rs1       = 5'd1;
        ex_rs2       = 5'd2;
        ex_rd        = 5'd3;
        ex_funct3    = 3'b000;
        ex_funct7    = 7'b0000000;
        ex_opcode    = OPCODE_OP;
        ex_ALUOp     = 2'b10;
        ex_ALUSrc    = 1'b0;
        ex_RegWrite  = 1'b1;
        #1;

        check32("ADD - alu_result",      ex_alu_result,    32'd30);
        check1 ("ADD - ex_zero",         ex_zero,          1'b0);
        check32("ADD - branch_target",   ex_branch_target, 32'h00000018); // 0x10 + (4<<1)=0x18
        check32("ADD - rs2_data_out",    ex_rs2_data_out,  32'd20);
        check5 ("ADD - rd_out",          ex_rd_out,        5'd3);
        check1 ("ADD - Branch_out",      ex_Branch_out,    1'b0);
        check1 ("ADD - RegWrite_out",    ex_RegWrite_out,  1'b1);

        // -------------------------------------------------
        // TEST 2: SUB (R-type)
        // 40 - 15 = 25
        // -------------------------------------------------
        clear_inputs;
        ex_rs1_data  = 32'd40;
        ex_rs2_data  = 32'd15;
        ex_rd        = 5'd4;
        ex_funct3    = 3'b000;
        ex_funct7    = 7'b0100000;
        ex_opcode    = OPCODE_OP;
        ex_ALUOp     = 2'b10;
        ex_ALUSrc    = 1'b0;
        ex_RegWrite  = 1'b1;
        #1;

        check32("SUB - alu_result",      ex_alu_result,   32'd25);
        check1 ("SUB - ex_zero",         ex_zero,         1'b0);

        // -------------------------------------------------
        // TEST 3: SUB con resultado 0
        // No branch -> ex_zero debe ser el zero real de la ALU
        // 55 - 55 = 0
        // -------------------------------------------------
        clear_inputs;
        ex_rs1_data  = 32'd55;
        ex_rs2_data  = 32'd55;
        ex_funct3    = 3'b000;
        ex_funct7    = 7'b0100000;
        ex_opcode    = OPCODE_OP;
        ex_ALUOp     = 2'b10;
        ex_ALUSrc    = 1'b0;
        #1;

        check32("SUB zero - alu_result", ex_alu_result,   32'd0);
        check1 ("SUB zero - ex_zero",    ex_zero,         1'b1);

        // -------------------------------------------------
        // TEST 4: ADDI
        // 7 + 5 = 12
        // ex_ALUSrc = 1 usa inmediato
        // -------------------------------------------------
        clear_inputs;
        ex_rs1_data  = 32'd7;
        ex_rs2_data  = 32'd99; // no debería usarse en ALU
        ex_imm       = 32'd5;
        ex_rd        = 5'd5;
        ex_funct3    = 3'b000;
        ex_opcode    = OPCODE_OP_IMM;
        ex_ALUOp     = 2'b00;
        ex_ALUSrc    = 1'b1;
        ex_RegWrite  = 1'b1;
        #1;

        check32("ADDI - alu_result",     ex_alu_result,   32'd12);
        check1 ("ADDI - ex_zero",        ex_zero,         1'b0);
        check32("ADDI - rs2_data_out",   ex_rs2_data_out, 32'd99);

        // -------------------------------------------------
        // TEST 5: LUI
        // resultado = imm
        // -------------------------------------------------
        clear_inputs;
        ex_imm       = 32'h12345000;
        ex_rd        = 5'd6;
        ex_opcode    = OPCODE_LUI;
        ex_ALUOp     = 2'b00;
        ex_ALUSrc    = 1'b1;
        ex_RegWrite  = 1'b1;
        #1;

        check32("LUI - alu_result",      ex_alu_result,   32'h12345000);
        check1 ("LUI - ex_zero",         ex_zero,         1'b0);
        check5 ("LUI - rd_out",          ex_rd_out,       5'd6);

        // -------------------------------------------------
        // TEST 6: BEQ tomado
        // rs1 == rs2
        // En branch, ex_zero representa "condición cumplida"
        // -------------------------------------------------
        clear_inputs;
        ex_pc        = 32'h00000100;
        ex_rs1_data  = 32'd25;
        ex_rs2_data  = 32'd25;
        ex_imm       = 32'd8;
        ex_funct3    = 3'b000; // beq
        ex_opcode    = OPCODE_BRANCH;
        ex_Branch    = 1'b1;
        ex_ALUOp     = 2'b01;
        ex_ALUSrc    = 1'b0;
        #1;

        check32("BEQ taken - alu_result",    ex_alu_result,    32'd0);
        check1 ("BEQ taken - ex_zero",       ex_zero,          1'b1);
        check32("BEQ taken - branch_target", ex_branch_target, 32'h00000110); // 0x100 + (8<<1)=0x110
        check1 ("BEQ taken - Branch_out",    ex_Branch_out,    1'b1);

        // -------------------------------------------------
        // TEST 7: BEQ no tomado
        // rs1 != rs2
        // -------------------------------------------------
        clear_inputs;
        ex_pc        = 32'h00000200;
        ex_rs1_data  = 32'd25;
        ex_rs2_data  = 32'd30;
        ex_imm       = 32'd4;
        ex_funct3    = 3'b000; // beq
        ex_opcode    = OPCODE_BRANCH;
        ex_Branch    = 1'b1;
        ex_ALUOp     = 2'b01;
        ex_ALUSrc    = 1'b0;
        #1;

        check1 ("BEQ not taken - ex_zero",       ex_zero,          1'b0);
        check32("BEQ not taken - branch_target", ex_branch_target, 32'h00000208);

        // -------------------------------------------------
        // TEST 8: BNE tomado
        // rs1 != rs2
        // En branch, ex_zero representa "condición cumplida"
        // -------------------------------------------------
        clear_inputs;
        ex_pc        = 32'h00000300;
        ex_rs1_data  = 32'd11;
        ex_rs2_data  = 32'd99;
        ex_imm       = 32'd6;
        ex_funct3    = 3'b001; // bne
        ex_opcode    = OPCODE_BRANCH;
        ex_Branch    = 1'b1;
        ex_ALUOp     = 2'b01;
        ex_ALUSrc    = 1'b0;
        #1;

        check1 ("BNE taken - ex_zero",       ex_zero,          1'b1);
        check32("BNE taken - branch_target", ex_branch_target, 32'h0000030C); // 0x300 + (6<<1)=0x30C

        // -------------------------------------------------
        // TEST 9: BNE no tomado
        // rs1 == rs2
        // -------------------------------------------------
        clear_inputs;
        ex_pc        = 32'h00000400;
        ex_rs1_data  = 32'd77;
        ex_rs2_data  = 32'd77;
        ex_imm       = 32'd2;
        ex_funct3    = 3'b001; // bne
        ex_opcode    = OPCODE_BRANCH;
        ex_Branch    = 1'b1;
        ex_ALUOp     = 2'b01;
        ex_ALUSrc    = 1'b0;
        #1;

        check1 ("BNE not taken - ex_zero",       ex_zero,          1'b0);
        check32("BNE not taken - branch_target", ex_branch_target, 32'h00000404);

        // -------------------------------------------------
        // TEST 10: Propagación de señales de memoria
        // -------------------------------------------------
        clear_inputs;
        ex_rs2_data  = 32'hDEADBEEF;
        ex_rd        = 5'd10;
        ex_Branch    = 1'b0;
        ex_MemRead   = 1'b1;
        ex_MemWrite  = 1'b0;
        ex_MemtoReg  = 1'b1;
        ex_RegWrite  = 1'b1;
        #1;

        check32("CTRL PROP - rs2_data_out", ex_rs2_data_out, 32'hDEADBEEF);
        check5 ("CTRL PROP - rd_out",       ex_rd_out,       5'd10);
        check1 ("CTRL PROP - Branch_out",   ex_Branch_out,   1'b0);
        check1 ("CTRL PROP - MemRead_out",  ex_MemRead_out,  1'b1);
        check1 ("CTRL PROP - MemWrite_out", ex_MemWrite_out, 1'b0);
        check1 ("CTRL PROP - MemtoReg_out", ex_MemtoReg_out, 1'b1);
        check1 ("CTRL PROP - RegWrite_out", ex_RegWrite_out, 1'b1);

        // -------------------------------------------------
        // TEST 11: Caso tipo store
        // chequea propagación de MemWrite
        // -------------------------------------------------
        clear_inputs;
        ex_rs2_data  = 32'hCAFEBABE;
        ex_MemWrite  = 1'b1;
        ex_MemRead   = 1'b0;
        ex_MemtoReg  = 1'b0;
        ex_RegWrite  = 1'b0;
        #1;

        check32("STORE CTRL - rs2_data_out", ex_rs2_data_out, 32'hCAFEBABE);
        check1 ("STORE CTRL - MemWrite_out", ex_MemWrite_out, 1'b1);
        check1 ("STORE CTRL - MemRead_out",  ex_MemRead_out,  1'b0);
        check1 ("STORE CTRL - RegWrite_out", ex_RegWrite_out, 1'b0);

        // -------------------------------------------------
        // Resultado final
        // -------------------------------------------------
        $display("========================================");
        if (errors == 0)
            $display(" Todos los tests de ex_stage pasaron OK");
        else
            $display(" Se encontraron %0d errores", errors);
        $display("========================================");

        $finish;
    end

endmodule