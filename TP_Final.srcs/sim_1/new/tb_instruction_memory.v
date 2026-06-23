`timescale 1ns/1ps

module tb_instruction_memory;

    localparam DEPTH      = 16;
    localparam ADDR_WIDTH = 4;

    reg         clk;
    reg  [31:0] addr;
    wire [31:0] instr;

    reg         prog_we;
    reg  [31:0] prog_addr;
    reg  [31:0] prog_wdata;

    instruction_memory #
    (
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    )
    uut
    (
        .clk(clk),
        .addr(addr),
        .instr(instr),
        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata)
    );

    // Clock de 10 ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_instr;
        input [31:0] expected;
        begin
            #1;
            if (instr !== expected) begin
                $display("ERROR @ %0t ns -> esperado = 0x%08h, actual = 0x%08h",
                         $time, expected, instr);
                $stop;
            end
            else begin
                $display("OK    @ %0t ns -> instr = 0x%08h", $time, instr);
            end
        end
    endtask

    task program_word;
        input [31:0] p_addr;
        input [31:0] p_data;
        begin
            @(negedge clk);
            prog_we    = 1'b1;
            prog_addr  = p_addr;
            prog_wdata = p_data;

            @(posedge clk);
            #1;
            prog_we    = 1'b0;
            prog_addr  = 32'h00000000;
            prog_wdata = 32'h00000000;
        end
    endtask

    initial begin
        // Inicialización
        addr       = 32'h00000000;
        prog_we    = 1'b0;
        prog_addr  = 32'h00000000;
        prog_wdata = 32'h00000000;

        // 1) Al inicio toda la memoria está en NOP
        addr = 32'h00000000;
        check_instr(32'h00000013);

        addr = 32'h00000004;
        check_instr(32'h00000013);

        // 2) Programamos algunas instrucciones
        // addi x1, x0, 5   -> 0x00500093
        // addi x2, x0, 10  -> 0x00A00113
        // add  x3, x1, x2  -> 0x002081B3
        program_word(32'h00000000, 32'h00500093);
        program_word(32'h00000004, 32'h00A00113);
        program_word(32'h00000008, 32'h002081B3);

        // 3) Leemos por PC
        addr = 32'h00000000;
        check_instr(32'h00500093);

        addr = 32'h00000004;
        check_instr(32'h00A00113);

        addr = 32'h00000008;
        check_instr(32'h002081B3);

        // 4) Dirección desalineada -> NOP
        addr = 32'h00000002;
        check_instr(32'h00000013);

        // 5) Otra palabra no programada -> NOP
        addr = 32'h0000000C;
        check_instr(32'h00000013);

        $display("TEST FINALIZADO CORRECTAMENTE");
        $finish;
    end

endmodule