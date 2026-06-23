`timescale 1ns/1ps

module tb_id_ex_latch;

    // =========================
    // Señales del DUT
    // =========================
    reg         clk;
    reg         rst;
    reg         write_en;
    reg         flush;

    reg  [31:0] id_pc;
    reg  [31:0] id_rs1_data;
    reg  [31:0] id_rs2_data;
    reg  [31:0] id_imm;

    reg  [4:0]  id_rs1;
    reg  [4:0]  id_rs2;
    reg  [4:0]  id_rd;

    reg  [2:0]  id_funct3;
    reg  [6:0]  id_funct7;
    reg  [6:0]  id_opcode;

    reg         id_Branch;
    reg         id_MemRead;
    reg         id_MemtoReg;
    reg  [1:0]  id_ALUOp;
    reg         id_MemWrite;
    reg         id_ALUSrc;
    reg         id_RegWrite;

    wire [31:0] ex_pc;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;

    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [4:0]  ex_rd;

    wire [2:0]  ex_funct3;
    wire [6:0]  ex_funct7;
    wire [6:0]  ex_opcode;

    wire        ex_Branch;
    wire        ex_MemRead;
    wire        ex_MemtoReg;
    wire [1:0]  ex_ALUOp;
    wire        ex_MemWrite;
    wire        ex_ALUSrc;
    wire        ex_RegWrite;

    // =========================
    // Instancia del DUT
    // =========================
    id_ex_latch dut (
        .clk(clk),
        .rst(rst),
        .write_en(write_en),
        .flush(flush),

        .id_pc(id_pc),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm(id_imm),

        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),

        .id_funct3(id_funct3),
        .id_funct7(id_funct7),
        .id_opcode(id_opcode),

        .id_Branch(id_Branch),
        .id_MemRead(id_MemRead),
        .id_MemtoReg(id_MemtoReg),
        .id_ALUOp(id_ALUOp),
        .id_MemWrite(id_MemWrite),
        .id_ALUSrc(id_ALUSrc),
        .id_RegWrite(id_RegWrite),

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
        .ex_RegWrite(ex_RegWrite)
    );

    // =========================
    // Clock: período 10 ns
    // =========================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================
    // Tarea para inicializar entradas
    // =========================
    task clear_inputs;
    begin
        write_en     = 1'b0;
        flush        = 1'b0;

        id_pc        = 32'b0;
        id_rs1_data  = 32'b0;
        id_rs2_data  = 32'b0;
        id_imm       = 32'b0;

        id_rs1       = 5'b0;
        id_rs2       = 5'b0;
        id_rd        = 5'b0;

        id_funct3    = 3'b0;
        id_funct7    = 7'b0;
        id_opcode    = 7'b0;

        id_Branch    = 1'b0;
        id_MemRead   = 1'b0;
        id_MemtoReg  = 1'b0;
        id_ALUOp     = 2'b0;
        id_MemWrite  = 1'b0;
        id_ALUSrc    = 1'b0;
        id_RegWrite  = 1'b0;
    end
    endtask

    // =========================
    // Tarea para cargar un patrón de prueba
    // =========================
    task load_pattern_1;
    begin
        id_pc        = 32'h00000020;
        id_rs1_data  = 32'h11111111;
        id_rs2_data  = 32'h22222222;
        id_imm       = 32'h00000010;

        id_rs1       = 5'd1;
        id_rs2       = 5'd2;
        id_rd        = 5'd3;

        id_funct3    = 3'b000;
        id_funct7    = 7'b0000000;
        id_opcode    = 7'b0110011;

        id_Branch    = 1'b0;
        id_MemRead   = 1'b0;
        id_MemtoReg  = 1'b0;
        id_ALUOp     = 2'b10;
        id_MemWrite  = 1'b0;
        id_ALUSrc    = 1'b0;
        id_RegWrite  = 1'b1;
    end
    endtask

    task load_pattern_2;
    begin
        id_pc        = 32'h00000040;
        id_rs1_data  = 32'hAAAAAAAA;
        id_rs2_data  = 32'hBBBBBBBB;
        id_imm       = 32'hFFFFFFFC;

        id_rs1       = 5'd4;
        id_rs2       = 5'd5;
        id_rd        = 5'd6;

        id_funct3    = 3'b010;
        id_funct7    = 7'b0100000;
        id_opcode    = 7'b0010011;

        id_Branch    = 1'b1;
        id_MemRead   = 1'b1;
        id_MemtoReg  = 1'b1;
        id_ALUOp     = 2'b01;
        id_MemWrite  = 1'b0;
        id_ALUSrc    = 1'b1;
        id_RegWrite  = 1'b1;
    end
    endtask

    // =========================
    // Tareas de chequeo
    // =========================
    task check_all_zero;
    begin
        if (ex_pc       !== 32'b0) $display("ERROR: ex_pc no es 0");
        if (ex_rs1_data !== 32'b0) $display("ERROR: ex_rs1_data no es 0");
        if (ex_rs2_data !== 32'b0) $display("ERROR: ex_rs2_data no es 0");
        if (ex_imm      !== 32'b0) $display("ERROR: ex_imm no es 0");

        if (ex_rs1      !== 5'b0)  $display("ERROR: ex_rs1 no es 0");
        if (ex_rs2      !== 5'b0)  $display("ERROR: ex_rs2 no es 0");
        if (ex_rd       !== 5'b0)  $display("ERROR: ex_rd no es 0");

        if (ex_funct3   !== 3'b0)  $display("ERROR: ex_funct3 no es 0");
        if (ex_funct7   !== 7'b0)  $display("ERROR: ex_funct7 no es 0");
        if (ex_opcode   !== 7'b0)  $display("ERROR: ex_opcode no es 0");

        if (ex_Branch   !== 1'b0)  $display("ERROR: ex_Branch no es 0");
        if (ex_MemRead  !== 1'b0)  $display("ERROR: ex_MemRead no es 0");
        if (ex_MemtoReg !== 1'b0)  $display("ERROR: ex_MemtoReg no es 0");
        if (ex_ALUOp    !== 2'b0)  $display("ERROR: ex_ALUOp no es 0");
        if (ex_MemWrite !== 1'b0)  $display("ERROR: ex_MemWrite no es 0");
        if (ex_ALUSrc   !== 1'b0)  $display("ERROR: ex_ALUSrc no es 0");
        if (ex_RegWrite !== 1'b0)  $display("ERROR: ex_RegWrite no es 0");
    end
    endtask

    task check_pattern_1;
    begin
        if (ex_pc       !== 32'h00000020) $display("ERROR: ex_pc pattern1");
        if (ex_rs1_data !== 32'h11111111) $display("ERROR: ex_rs1_data pattern1");
        if (ex_rs2_data !== 32'h22222222) $display("ERROR: ex_rs2_data pattern1");
        if (ex_imm      !== 32'h00000010) $display("ERROR: ex_imm pattern1");

        if (ex_rs1      !== 5'd1)         $display("ERROR: ex_rs1 pattern1");
        if (ex_rs2      !== 5'd2)         $display("ERROR: ex_rs2 pattern1");
        if (ex_rd       !== 5'd3)         $display("ERROR: ex_rd pattern1");

        if (ex_funct3   !== 3'b000)       $display("ERROR: ex_funct3 pattern1");
        if (ex_funct7   !== 7'b0000000)   $display("ERROR: ex_funct7 pattern1");
        if (ex_opcode   !== 7'b0110011)   $display("ERROR: ex_opcode pattern1");

        if (ex_Branch   !== 1'b0)         $display("ERROR: ex_Branch pattern1");
        if (ex_MemRead  !== 1'b0)         $display("ERROR: ex_MemRead pattern1");
        if (ex_MemtoReg !== 1'b0)         $display("ERROR: ex_MemtoReg pattern1");
        if (ex_ALUOp    !== 2'b10)        $display("ERROR: ex_ALUOp pattern1");
        if (ex_MemWrite !== 1'b0)         $display("ERROR: ex_MemWrite pattern1");
        if (ex_ALUSrc   !== 1'b0)         $display("ERROR: ex_ALUSrc pattern1");
        if (ex_RegWrite !== 1'b1)         $display("ERROR: ex_RegWrite pattern1");
    end
    endtask

    task check_pattern_2;
    begin
        if (ex_pc       !== 32'h00000040) $display("ERROR: ex_pc pattern2");
        if (ex_rs1_data !== 32'hAAAAAAAA) $display("ERROR: ex_rs1_data pattern2");
        if (ex_rs2_data !== 32'hBBBBBBBB) $display("ERROR: ex_rs2_data pattern2");
        if (ex_imm      !== 32'hFFFFFFFC) $display("ERROR: ex_imm pattern2");

        if (ex_rs1      !== 5'd4)         $display("ERROR: ex_rs1 pattern2");
        if (ex_rs2      !== 5'd5)         $display("ERROR: ex_rs2 pattern2");
        if (ex_rd       !== 5'd6)         $display("ERROR: ex_rd pattern2");

        if (ex_funct3   !== 3'b010)       $display("ERROR: ex_funct3 pattern2");
        if (ex_funct7   !== 7'b0100000)   $display("ERROR: ex_funct7 pattern2");
        if (ex_opcode   !== 7'b0010011)   $display("ERROR: ex_opcode pattern2");

        if (ex_Branch   !== 1'b1)         $display("ERROR: ex_Branch pattern2");
        if (ex_MemRead  !== 1'b1)         $display("ERROR: ex_MemRead pattern2");
        if (ex_MemtoReg !== 1'b1)         $display("ERROR: ex_MemtoReg pattern2");
        if (ex_ALUOp    !== 2'b01)        $display("ERROR: ex_ALUOp pattern2");
        if (ex_MemWrite !== 1'b0)         $display("ERROR: ex_MemWrite pattern2");
        if (ex_ALUSrc   !== 1'b1)         $display("ERROR: ex_ALUSrc pattern2");
        if (ex_RegWrite !== 1'b1)         $display("ERROR: ex_RegWrite pattern2");
    end
    endtask

    // =========================
    // Secuencia de prueba
    // =========================
    initial begin
        $display("========================================");
        $display("Inicio de simulacion tb_id_ex_latch");
        $display("========================================");

        clear_inputs();
        rst = 1'b1;

        // -------------------------
        // Test 1: reset
        // -------------------------
        #12;
        rst = 1'b0;
        #1;
        $display("Test 1: reset");
        check_all_zero();

        // -------------------------
        // Test 2: escritura normal
        // -------------------------
        @(negedge clk);
        write_en = 1'b1;
        flush    = 1'b0;
        load_pattern_1();

        @(posedge clk);
        #1;
        $display("Test 2: carga normal pattern_1");
        check_pattern_1();

        // -------------------------
        // Test 3: stall / hold
        // write_en = 0, debe conservar pattern_1
        // -------------------------
        @(negedge clk);
        write_en = 1'b0;
        flush    = 1'b0;
        load_pattern_2();   // cambio entradas, pero no debería capturarlas

        @(posedge clk);
        #1;
        $display("Test 3: hold con write_en=0");
        check_pattern_1();

        // -------------------------
        // Test 4: flush
        // -------------------------
        @(negedge clk);
        write_en = 1'b1;
        flush    = 1'b1;

        @(posedge clk);
        #1;
        $display("Test 4: flush");
        check_all_zero();

        // -------------------------
        // Test 5: nueva carga luego del flush
        // -------------------------
        @(negedge clk);
        write_en = 1'b1;
        flush    = 1'b0;
        load_pattern_2();

        @(posedge clk);
        #1;
        $display("Test 5: carga normal pattern_2");
        check_pattern_2();

        $display("========================================");
        $display("Fin de simulacion tb_id_ex_latch");
        $display("========================================");
        $finish;
    end

endmodule