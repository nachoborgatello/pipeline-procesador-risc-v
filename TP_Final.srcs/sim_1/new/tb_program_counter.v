`timescale 1ns/1ps

module tb_program_counter;

    reg         clk;
    reg         rst;
    reg         pc_en;
    reg  [31:0] pc_next;
    wire [31:0] pc;

    program_counter uut (
        .clk(clk),
        .rst(rst),
        .pc_en(pc_en),
        .pc_next(pc_next),
        .pc(pc)
    );

    // Clock de 10 ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_pc;
        input [31:0] expected;
        begin
            if (pc !== expected) begin
                $display("ERROR @ %0t ns -> esperado = 0x%08h, actual = 0x%08h",
                         $time, expected, pc);
                $stop;
            end
            else begin
                $display("OK    @ %0t ns -> PC = 0x%08h", $time, pc);
            end
        end
    endtask

    initial begin
        // Inicialización
        rst     = 1'b1;
        pc_en   = 1'b0;
        pc_next = 32'h00000000;

        // Reset
        @(posedge clk);
        #1;
        check_pc(32'h00000000);

        // Avanza a 4
        rst     = 1'b0;
        pc_en   = 1'b1;
        pc_next = 32'h00000004;

        @(posedge clk);
        #1;
        check_pc(32'h00000004);

        // Avanza a 8
        pc_next = 32'h00000008;

        @(posedge clk);
        #1;
        check_pc(32'h00000008);

        // Hold
        pc_en   = 1'b0;
        pc_next = 32'h0000000C;

        @(posedge clk);
        #1;
        check_pc(32'h00000008);

        // Salto arbitrario
        pc_en   = 1'b1;
        pc_next = 32'h00000100;

        @(posedge clk);
        #1;
        check_pc(32'h00000100);

        // Reset otra vez
        rst = 1'b1;

        @(posedge clk);
        #1;
        check_pc(32'h00000000);

        // Sale de reset y avanza
        rst     = 1'b0;
        pc_en   = 1'b1;
        pc_next = 32'h00000010;

        @(posedge clk);
        #1;
        check_pc(32'h00000010);

        $display("TEST FINALIZADO CORRECTAMENTE");
        $finish;
    end

endmodule