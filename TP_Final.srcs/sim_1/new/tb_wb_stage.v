`timescale 1ns / 1ps

module tb_wb_stage;

    // Entradas al DUT
    reg  [31:0] wb_read_data;
    reg  [31:0] wb_alu_result;
    reg  [4:0]  wb_rd;
    reg         wb_MemtoReg;
    reg         wb_RegWrite;

    // Salidas del DUT
    wire [31:0] rf_write_data;
    wire [4:0]  rf_rd_addr;
    wire        rf_reg_write;

    // Instancia del DUT
    wb_stage dut (
        .wb_read_data (wb_read_data),
        .wb_alu_result(wb_alu_result),
        .wb_rd        (wb_rd),
        .wb_MemtoReg  (wb_MemtoReg),
        .wb_RegWrite  (wb_RegWrite),
        .rf_write_data(rf_write_data),
        .rf_rd_addr   (rf_rd_addr),
        .rf_reg_write (rf_reg_write)
    );

    // Tarea de verificación
    task check_outputs;
        input [31:0] exp_write_data;
        input [4:0]  exp_rd_addr;
        input        exp_reg_write;
        input [255:0] test_name;
        begin
            if (rf_write_data !== exp_write_data)
                $display("[ERROR] %s | rf_write_data esperado = 0x%08h, obtenido = 0x%08h",
                         test_name, exp_write_data, rf_write_data);
            else
                $display("[OK]    %s | rf_write_data = 0x%08h",
                         test_name, rf_write_data);

            if (rf_rd_addr !== exp_rd_addr)
                $display("[ERROR] %s | rf_rd_addr esperado = %0d, obtenido = %0d",
                         test_name, exp_rd_addr, rf_rd_addr);
            else
                $display("[OK]    %s | rf_rd_addr = %0d",
                         test_name, rf_rd_addr);

            if (rf_reg_write !== exp_reg_write)
                $display("[ERROR] %s | rf_reg_write esperado = %b, obtenido = %b",
                         test_name, exp_reg_write, rf_reg_write);
            else
                $display("[OK]    %s | rf_reg_write = %b",
                         test_name, rf_reg_write);
        end
    endtask

    initial begin
        $display("=======================================");
        $display("      INICIO TESTBENCH wb_stage");
        $display("=======================================");

        // =========================
        // TEST 1: Selección desde ALU
        // wb_MemtoReg = 0
        // =========================
        wb_read_data  = 32'h11112222;
        wb_alu_result = 32'hAAAABBBB;
        wb_rd         = 5'd10;
        wb_MemtoReg   = 1'b0;
        wb_RegWrite   = 1'b1;
        #1;

        check_outputs(32'hAAAABBBB, 5'd10, 1'b1, "TEST 1 - Writeback desde ALU");

        // =========================
        // TEST 2: Selección desde memoria
        // wb_MemtoReg = 1
        // =========================
        wb_read_data  = 32'hDEADBEEF;
        wb_alu_result = 32'h12345678;
        wb_rd         = 5'd5;
        wb_MemtoReg   = 1'b1;
        wb_RegWrite   = 1'b1;
        #1;

        check_outputs(32'hDEADBEEF, 5'd5, 1'b1, "TEST 2 - Writeback desde memoria");

        // =========================
        // TEST 3: RegWrite desactivado
        // =========================
        wb_read_data  = 32'hCAFEBABE;
        wb_alu_result = 32'h0F0F0F0F;
        wb_rd         = 5'd3;
        wb_MemtoReg   = 1'b0;
        wb_RegWrite   = 1'b0;
        #1;

        check_outputs(32'h0F0F0F0F, 5'd3, 1'b0, "TEST 3 - RegWrite en 0");

        // =========================
        // TEST 4: Registro destino x0
        // =========================
        wb_read_data  = 32'h87654321;
        wb_alu_result = 32'hABCDEF12;
        wb_rd         = 5'd0;
        wb_MemtoReg   = 1'b1;
        wb_RegWrite   = 1'b1;
        #1;

        check_outputs(32'h87654321, 5'd0, 1'b1, "TEST 4 - Destino x0");

        // =========================
        // TEST 5: Cambio rápido de fuente
        // =========================
        wb_read_data  = 32'h0000AAAA;
        wb_alu_result = 32'h55550000;
        wb_rd         = 5'd31;
        wb_MemtoReg   = 1'b0;
        wb_RegWrite   = 1'b1;
        #1;

        check_outputs(32'h55550000, 5'd31, 1'b1, "TEST 5A - Fuente ALU");

        wb_MemtoReg   = 1'b1;
        #1;

        check_outputs(32'h0000AAAA, 5'd31, 1'b1, "TEST 5B - Fuente MEM");

        $display("=======================================");
        $display("       FIN TESTBENCH wb_stage");
        $display("=======================================");
        $finish;
    end

endmodule