`timescale 1ns/1ps

module tb_if_stage;

    reg         clk;
    reg         rst;
    reg         pc_en;
    reg  [31:0] pc_next;

    reg         prog_we;
    reg  [31:0] prog_addr;
    reg  [31:0] prog_wdata;

    wire [31:0] pc;
    wire [31:0] pc_plus4;
    wire [31:0] instr;

    if_stage #
    (
        .IMEM_DEPTH(256),
        .IMEM_ADDR_WIDTH(8)
    )
    uut
    (
        .clk(clk),
        .rst(rst),
        .pc_en(pc_en),
        .pc_next(pc_next),

        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata),

        .pc(pc),
        .pc_plus4(pc_plus4),
        .instr(instr)
    );

    // Clock de 10 ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Task para programar una instrucción en IMEM
    task program_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            prog_we    = 1'b1;
            prog_addr  = addr;
            prog_wdata = data;

            @(posedge clk);
            #1;
            prog_we    = 1'b0;
            prog_addr  = 32'h00000000;
            prog_wdata = 32'h00000000;
        end
    endtask

    // Task para verificar PC, PC+4 e instrucción
    task check_if;
        input [31:0] exp_pc;
        input [31:0] exp_pc_plus4;
        input [31:0] exp_instr;
        begin
            #1;
            if (pc !== exp_pc) begin
                $display("ERROR @ %0t ns -> PC esperado = 0x%08h, actual = 0x%08h",
                         $time, exp_pc, pc);
                $stop;
            end

            if (pc_plus4 !== exp_pc_plus4) begin
                $display("ERROR @ %0t ns -> PC+4 esperado = 0x%08h, actual = 0x%08h",
                         $time, exp_pc_plus4, pc_plus4);
                $stop;
            end

            if (instr !== exp_instr) begin
                $display("ERROR @ %0t ns -> INSTR esperada = 0x%08h, actual = 0x%08h",
                         $time, exp_instr, instr);
                $stop;
            end

            $display("OK @ %0t ns -> PC = 0x%08h | PC+4 = 0x%08h | INSTR = 0x%08h",
                     $time, pc, pc_plus4, instr);
        end
    endtask

    initial begin
        // Inicialización
        rst       = 1'b1;
        pc_en     = 1'b0;
        pc_next   = 32'h00000000;
        prog_we   = 1'b0;
        prog_addr = 32'h00000000;
        prog_wdata= 32'h00000000;

        // Programamos algunas instrucciones en la IMEM
        // 0x00 -> addi x1, x0, 5   = 0x00500093
        // 0x04 -> addi x2, x0, 10  = 0x00A00113
        // 0x08 -> add  x3, x1, x2  = 0x002081B3
        // 0x20 -> addi x5, x0, 1   = 0x00100293
        program_word(32'h00000000, 32'h00500093);
        program_word(32'h00000004, 32'h00A00113);
        program_word(32'h00000008, 32'h002081B3);
        program_word(32'h00000020, 32'h00100293);

        // Reset activo: el PC debe quedar en 0
        @(posedge clk);
        check_if(32'h00000000, 32'h00000004, 32'h00500093);

        // Salimos de reset y habilitamos avance
        rst     = 1'b0;
        pc_en   = 1'b1;
        pc_next = 32'h00000004;

        // Fetch secuencial: PC = 0x04
        @(posedge clk);
        check_if(32'h00000004, 32'h00000008, 32'h00A00113);

        // Fetch secuencial: PC = 0x08
        pc_next = 32'h00000008;
        @(posedge clk);
        check_if(32'h00000008, 32'h0000000C, 32'h002081B3);

        // Hold: PC no debe cambiar aunque pc_next cambie
        pc_en   = 1'b0;
        pc_next = 32'h0000000C;
        @(posedge clk);
        check_if(32'h00000008, 32'h0000000C, 32'h002081B3);

        // Reanudar y hacer salto a 0x20
        pc_en   = 1'b1;
        pc_next = 32'h00000020;
        @(posedge clk);
        check_if(32'h00000020, 32'h00000024, 32'h00100293);

        // Reset nuevamente
        rst     = 1'b1;
        pc_en   = 1'b0;
        @(posedge clk);
        check_if(32'h00000000, 32'h00000004, 32'h00500093);

        $display("TEST FINALIZADO CORRECTAMENTE");
        $finish;
    end

endmodule