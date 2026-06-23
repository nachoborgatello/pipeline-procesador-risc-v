`timescale 1ns/1ps

module tb_mem_stage;

    // ------------------------------------------------------------
    // Parámetro de la memoria
    // ------------------------------------------------------------
    localparam DATA_MEM_ADDR_WIDTH = 12;

    // ------------------------------------------------------------
    // Señales del DUT
    // ------------------------------------------------------------
    reg         clk;
    reg         rst;

    reg  [31:0] mem_branch_target;
    reg         mem_zero;
    reg  [31:0] mem_alu_result;
    reg  [31:0] mem_rs2_data;
    reg  [4:0]  mem_rd;
    reg         mem_Branch;
    reg         mem_MemRead;
    reg         mem_MemWrite;
    reg         mem_MemtoReg;
    reg         mem_RegWrite;

    wire        mem_PCSrc;
    wire [31:0] mem_branch_target_out;

    wire [31:0] wb_read_data;
    wire [31:0] wb_alu_result;
    wire [4:0]  wb_rd;
    wire        wb_MemtoReg;
    wire        wb_RegWrite;

    // ------------------------------------------------------------
    // Instancia del módulo bajo prueba
    // ------------------------------------------------------------
    mem_stage #(
        .DATA_MEM_ADDR_WIDTH(DATA_MEM_ADDR_WIDTH)
    ) dut (
        .clk                   (clk),
        .rst                   (rst),
        .mem_branch_target     (mem_branch_target),
        .mem_zero              (mem_zero),
        .mem_alu_result        (mem_alu_result),
        .mem_rs2_data          (mem_rs2_data),
        .mem_rd                (mem_rd),
        .mem_Branch            (mem_Branch),
        .mem_MemRead           (mem_MemRead),
        .mem_MemWrite          (mem_MemWrite),
        .mem_MemtoReg          (mem_MemtoReg),
        .mem_RegWrite          (mem_RegWrite),
        .mem_PCSrc             (mem_PCSrc),
        .mem_branch_target_out (mem_branch_target_out),
        .wb_read_data          (wb_read_data),
        .wb_alu_result         (wb_alu_result),
        .wb_rd                 (wb_rd),
        .wb_MemtoReg           (wb_MemtoReg),
        .wb_RegWrite           (wb_RegWrite)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // período = 10 ns
    end

    // ------------------------------------------------------------
    // Tasks de chequeo
    // ------------------------------------------------------------
    task check_value;
        input [255:0] test_name;
        input [31:0]  expected;
        input [31:0]  got;
        begin
            if (got === expected)
                $display("[OK]   %0s | esperado = 0x%08h, obtenido = 0x%08h", test_name, expected, got);
            else
                $display("[FAIL] %0s | esperado = 0x%08h, obtenido = 0x%08h", test_name, expected, got);
        end
    endtask

    task check_bit;
        input [255:0] test_name;
        input         expected;
        input         got;
        begin
            if (got === expected)
                $display("[OK]   %0s | esperado = %b, obtenido = %b", test_name, expected, got);
            else
                $display("[FAIL] %0s | esperado = %b, obtenido = %b", test_name, expected, got);
        end
    endtask

    // ------------------------------------------------------------
    // Estímulos
    // ------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("       INICIO TESTBENCH mem_stage");
        $display("========================================");

        // Inicialización
        rst               = 1'b1;
        mem_branch_target = 32'b0;
        mem_zero          = 1'b0;
        mem_alu_result    = 32'b0;
        mem_rs2_data      = 32'b0;
        mem_rd            = 5'b0;
        mem_Branch        = 1'b0;
        mem_MemRead       = 1'b0;
        mem_MemWrite      = 1'b0;
        mem_MemtoReg      = 1'b0;
        mem_RegWrite      = 1'b0;

        // --------------------------------------------------------
        // TEST 1: Reset
        // --------------------------------------------------------
        @(posedge clk);
        @(posedge clk);
        rst = 1'b0;

        $display("\n--- TEST 1: Verificación básica post-reset ---");
        check_bit("PCSrc después de reset", 1'b0, mem_PCSrc);
        check_value("branch_target_out después de reset", 32'h00000000, mem_branch_target_out);
        check_value("wb_read_data después de reset", 32'h00000000, wb_read_data);

        // --------------------------------------------------------
        // TEST 2: sw
        // Escritura en dirección alineada
        // --------------------------------------------------------
        $display("\n--- TEST 2: Store word (sw) ---");

        mem_alu_result    = 32'h00000004;
        mem_rs2_data      = 32'hAABBCCDD;
        mem_rd            = 5'd10;
        mem_Branch        = 1'b0;
        mem_zero          = 1'b0;
        mem_MemRead       = 1'b0;
        mem_MemWrite      = 1'b1;
        mem_MemtoReg      = 1'b0;
        mem_RegWrite      = 1'b0;
        mem_branch_target = 32'h00000020;

        @(posedge clk);   // escritura efectiva
        #10
        mem_MemWrite = 1'b0;

        check_value("wb_alu_result luego de sw", 32'h00000004, wb_alu_result);
        check_value("wb_rd luego de sw", 32'd10, {27'b0, wb_rd});
        check_bit("wb_MemtoReg luego de sw", 1'b0, wb_MemtoReg);
        check_bit("wb_RegWrite luego de sw", 1'b0, wb_RegWrite);

        // --------------------------------------------------------
        // TEST 3: lw
        // Lectura sincrónica de la dirección escrita
        // --------------------------------------------------------
        $display("\n--- TEST 3: Load word (lw) ---");

        mem_alu_result    = 32'h00000004;
        mem_rs2_data      = 32'h00000000;
        mem_rd            = 5'd11;
        mem_Branch        = 1'b0;
        mem_zero          = 1'b0;
        mem_MemRead       = 1'b1;
        mem_MemWrite      = 1'b0;
        mem_MemtoReg      = 1'b1;
        mem_RegWrite      = 1'b1;
        mem_branch_target = 32'h00000024;

        @(posedge clk);   // lectura efectiva si la memoria es sincrónica
        #1;

        check_value("wb_read_data luego de lw", 32'hAABBCCDD, wb_read_data);
        check_value("wb_alu_result luego de lw", 32'h00000004, wb_alu_result);
        check_value("wb_rd luego de lw", 32'd11, {27'b0, wb_rd});
        check_bit("wb_MemtoReg luego de lw", 1'b1, wb_MemtoReg);
        check_bit("wb_RegWrite luego de lw", 1'b1, wb_RegWrite);

        mem_MemRead = 1'b0;

        // --------------------------------------------------------
        // TEST 4: Branch tomado
        // --------------------------------------------------------
        $display("\n--- TEST 4: Branch tomado ---");

        mem_branch_target = 32'h00000100;
        mem_Branch        = 1'b1;
        mem_zero          = 1'b1;

        #1;

        check_bit("mem_PCSrc con branch tomado", 1'b1, mem_PCSrc);
        check_value("mem_branch_target_out con branch tomado", 32'h00000100, mem_branch_target_out);

        // --------------------------------------------------------
        // TEST 5: Branch no tomado por zero = 0
        // --------------------------------------------------------
        $display("\n--- TEST 5: Branch no tomado por zero=0 ---");

        mem_branch_target = 32'h00000200;
        mem_Branch        = 1'b1;
        mem_zero          = 1'b0;

        #1;

        check_bit("mem_PCSrc con Branch=1 y zero=0", 1'b0, mem_PCSrc);
        check_value("mem_branch_target_out se mantiene", 32'h00000200, mem_branch_target_out);

        // --------------------------------------------------------
        // TEST 6: Branch no tomado por Branch = 0
        // --------------------------------------------------------
        $display("\n--- TEST 6: Branch no tomado por Branch=0 ---");

        mem_branch_target = 32'h00000300;
        mem_Branch        = 1'b0;
        mem_zero          = 1'b1;

        #1;

        check_bit("mem_PCSrc con Branch=0 y zero=1", 1'b0, mem_PCSrc);
        check_value("mem_branch_target_out se mantiene", 32'h00000300, mem_branch_target_out);

        // --------------------------------------------------------
        // TEST 7: Acceso desalineado
        // Una escritura desalineada debe ignorarse
        // Una lectura desalineada debe devolver 0
        // --------------------------------------------------------
        $display("\n--- TEST 7: Acceso desalineado ---");

        // Escritura desalineada
        mem_alu_result = 32'h00000006;
        mem_rs2_data   = 32'h11223344;
        mem_MemRead    = 1'b0;
        mem_MemWrite   = 1'b1;

        @(posedge clk);

        mem_MemWrite = 1'b0;

        // Lectura desalineada
        mem_alu_result = 32'h00000006;
        mem_MemRead    = 1'b1;

        @(posedge clk);
        #1;

        check_value("lw desalineado devuelve 0", 32'h00000000, wb_read_data);

        mem_MemRead = 1'b0;

        // --------------------------------------------------------
        // TEST 8: Verificación final de memoria
        // La dirección 0x04 debe seguir conteniendo AABBCCDD
        // --------------------------------------------------------
        $display("\n--- TEST 8: Verificación final de memoria ---");

        mem_alu_result = 32'h00000004;
        mem_MemRead    = 1'b1;
        mem_MemWrite   = 1'b0;

        @(posedge clk);
        #1;

        check_value("contenido de memoria en 0x04 sigue intacto", 32'hAABBCCDD, wb_read_data);

        mem_MemRead = 1'b0;

        $display("\n========================================");
        $display("      FIN TESTBENCH mem_stage");
        $display("========================================");
        $finish;
    end

endmodule