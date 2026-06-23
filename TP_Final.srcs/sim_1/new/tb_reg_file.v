`timescale 1ns/1ps

module tb_reg_file;

    reg         clk;
    reg         rst;
    reg         reg_write_en;

    reg  [4:0]  rs1_addr;
    reg  [4:0]  rs2_addr;
    reg  [4:0]  rd_addr;
    reg  [31:0] rd_data;

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    reg_file uut (
        .clk(clk),
        .rst(rst),
        .reg_write_en(reg_write_en),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .debug_addr(5'd0),
        .debug_data()
    );

    // Clock de 10 ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Task para escribir un registro
    // Se cargan señales antes del flanco de subida
    task write_reg;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            reg_write_en = 1'b1;
            rd_addr      = addr;
            rd_data      = data;

            @(posedge clk);
            #1;
            reg_write_en = 1'b0;
            rd_addr      = 5'd0;
            rd_data      = 32'h00000000;
        end
    endtask

    // Task para verificar lecturas síncronas en flanco de bajada
    task check_read;
        input [4:0]  addr1;
        input [31:0] exp1;
        input [4:0]  addr2;
        input [31:0] exp2;
        begin
            // Las direcciones deben estar estables antes del negedge
            @(posedge clk);
            rs1_addr = addr1;
            rs2_addr = addr2;

            @(negedge clk);
            #1;

            if (rs1_data !== exp1) begin
                $display("ERROR @ %0t ns -> rs1_data esperado = 0x%08h, actual = 0x%08h",
                         $time, exp1, rs1_data);
                $stop;
            end

            if (rs2_data !== exp2) begin
                $display("ERROR @ %0t ns -> rs2_data esperado = 0x%08h, actual = 0x%08h",
                         $time, exp2, rs2_data);
                $stop;
            end

            $display("OK @ %0t ns -> rs1(x%0d)=0x%08h | rs2(x%0d)=0x%08h",
                     $time, addr1, rs1_data, addr2, rs2_data);
        end
    endtask

    initial begin
        // Inicialización
        rst          = 1'b1;
        reg_write_en = 1'b0;
        rs1_addr     = 5'd0;
        rs2_addr     = 5'd0;
        rd_addr      = 5'd0;
        rd_data      = 32'h00000000;

        // Reset:
        // - en posedge se limpian los registros
        // - en negedge se limpian las salidas de lectura
        @(posedge clk);
        @(negedge clk);
        #1;

        // Después del reset, todo debe valer 0
        check_read(5'd0, 32'h00000000, 5'd1, 32'h00000000);

        // Salimos de reset
        @(posedge clk);
        rst = 1'b0;

        // Escribimos x1 = 5
        write_reg(5'd1, 32'h00000005);
        check_read(5'd1, 32'h00000005, 5'd0, 32'h00000000);

        // Escribimos x2 = 10
        write_reg(5'd2, 32'h0000000A);
        check_read(5'd1, 32'h00000005, 5'd2, 32'h0000000A);

        // Escribimos x3 = 0x12345678
        write_reg(5'd3, 32'h12345678);
        check_read(5'd3, 32'h12345678, 5'd2, 32'h0000000A);

        // Intento de escritura en x0: debe seguir en cero
        write_reg(5'd0, 32'hFFFFFFFF);
        check_read(5'd0, 32'h00000000, 5'd3, 32'h12345678);

        // Probamos cambio de direcciones de lectura síncrona
        check_read(5'd2, 32'h0000000A, 5'd1, 32'h00000005);

        // Reset otra vez: todo vuelve a cero
        @(negedge clk);
        rst = 1'b1;

        @(posedge clk);
        @(negedge clk);
        #1;

        check_read(5'd1, 32'h00000000, 5'd2, 32'h00000000);

        $display("TEST FINALIZADO CORRECTAMENTE");
        $finish;
    end

endmodule