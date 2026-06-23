`timescale 1ns/1ps

module tb_debug_unit;

    // Usar baud rate alto para simulacion rapida
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 5_000_000;
    localparam CLK_PERIOD = 20; // 50MHz
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE * CLK_PERIOD;

    reg  clk;
    reg  rst;
    reg  uart_rx_in;
    wire uart_tx_out;

    top_level #(
        .CLK_FREQ            (CLK_FREQ),
        .BAUD_RATE           (BAUD_RATE),
        .IMEM_DEPTH          (256),
        .IMEM_ADDR_WIDTH     (8),
        .DATA_MEM_ADDR_WIDTH (12)
    ) uut (
        .clk       (clk),
        .rst       (rst),
        .uart_rx_i (uart_rx_in),
        .uart_tx_o (uart_tx_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ============================================================
    // Task: enviar un byte por UART (8N1)
    // ============================================================
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // Start bit
            uart_rx_in = 1'b0;
            #BIT_PERIOD;
            // 8 data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_in = data[i];
                #BIT_PERIOD;
            end
            // Stop bit
            uart_rx_in = 1'b1;
            #BIT_PERIOD;
        end
    endtask

    // ============================================================
    // Task: recibir un byte por UART TX
    // ============================================================
    task uart_recv_byte;
        output [7:0] data;
        integer i;
        begin
            // Esperar start bit (linea baja)
            @(negedge uart_tx_out);
            // Ir al centro del start bit
            #(BIT_PERIOD/2);
            // Verificar que sigue en 0
            if (uart_tx_out !== 1'b0)
                $display("[TB] WARN: start bit invalido");
            // Leer 8 bits de datos
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD;
                data[i] = uart_tx_out;
            end
            // Esperar stop bit
            #BIT_PERIOD;
        end
    endtask

    // ============================================================
    // Task: enviar instruccion de 32 bits como 4 bytes big-endian
    // ============================================================
    task uart_send_word;
        input [31:0] word;
        begin
            uart_send_byte(word[31:24]);
            uart_send_byte(word[23:16]);
            uart_send_byte(word[15:8]);
            uart_send_byte(word[7:0]);
        end
    endtask

    // ============================================================
    // Task: recibir word de 32 bits (4 bytes big-endian)
    // ============================================================
    task uart_recv_word;
        output [31:0] word;
        reg [7:0] b3, b2, b1, b0;
        begin
            uart_recv_byte(b3);
            uart_recv_byte(b2);
            uart_recv_byte(b1);
            uart_recv_byte(b0);
            word = {b3, b2, b1, b0};
        end
    endtask

    // Comandos
    localparam CMD_LOAD    = 8'h01;
    localparam CMD_RUN     = 8'h02;
    localparam CMD_STEP    = 8'h03;
    localparam CMD_REGS    = 8'h04;
    localparam CMD_LATCHES = 8'h05;
    localparam CMD_PC      = 8'h07;
    localparam CMD_RESET   = 8'h08;

    // Instrucciones de test
    localparam INSTR_ADDI_X1 = 32'h00500093; // addi x1, x0, 5
    localparam INSTR_ADDI_X2 = 32'h00A00113; // addi x2, x0, 10
    localparam INSTR_ADD_X3  = 32'h002081B3; // add  x3, x1, x2
    localparam INSTR_HALT    = 32'hFFFFFFFF;

    reg [31:0] recv_word;
    integer i;
    integer errors;

    initial begin
        clk        = 0;
        rst        = 1;
        uart_rx_in = 1'b1; // idle
        errors     = 0;

        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // ========================================================
        // TEST 1: LOAD + RUN + GET_REGS
        // ========================================================
        $display("============================================");
        $display("TEST 1: LOAD + RUN + GET_REGS via UART");
        $display("============================================");

        // Enviar CMD_LOAD con 4 instrucciones
        $display("[TB] Enviando CMD_LOAD (4 instrucciones)...");
        uart_send_byte(CMD_LOAD);
        uart_send_byte(8'h00); // len_hi = 0
        uart_send_byte(8'h04); // len_lo = 4

        uart_send_word(INSTR_ADDI_X1);
        uart_send_word(INSTR_ADDI_X2);
        uart_send_word(INSTR_ADD_X3);
        uart_send_word(INSTR_HALT);

        $display("[TB] Programa cargado.");
        #(CLK_PERIOD * 10);

        // Reset pipeline para limpiar estado
        $display("[TB] Enviando CMD_RESET...");
        uart_send_byte(CMD_RESET);
        #(CLK_PERIOD * 10);

        // Enviar CMD_RUN
        $display("[TB] Enviando CMD_RUN...");
        uart_send_byte(CMD_RUN);

        // Esperar a que el pipeline termine (o_halted = 1)
        $display("[TB] Esperando HALT...");
        wait(uut.u_pipeline.o_halted == 1'b1);
        #(CLK_PERIOD * 5);
        $display("[TB] Pipeline detenido (HALT alcanzado).");

        // Enviar CMD_REGS y recibir 32 registros
        $display("[TB] Enviando CMD_REGS...");
        uart_send_byte(CMD_REGS);

        for (i = 0; i < 32; i = i + 1) begin
            uart_recv_word(recv_word);
            if (i == 1 && recv_word !== 32'd5) begin
                $display("[TB] ERROR: x1 = %0d, esperado 5", recv_word);
                errors = errors + 1;
            end
            else if (i == 2 && recv_word !== 32'd10) begin
                $display("[TB] ERROR: x2 = %0d, esperado 10", recv_word);
                errors = errors + 1;
            end
            else if (i == 3 && recv_word !== 32'd15) begin
                $display("[TB] ERROR: x3 = %0d, esperado 15", recv_word);
                errors = errors + 1;
            end
            else if (i <= 3) begin
                $display("[TB] OK: x%0d = %0d", i, recv_word);
            end
        end

        $display("");

        // ========================================================
        // TEST 2: GET_PC
        // ========================================================
        $display("============================================");
        $display("TEST 2: GET_PC via UART");
        $display("============================================");

        uart_send_byte(CMD_PC);
        uart_recv_word(recv_word);
        $display("[TB] PC = 0x%08X", recv_word);

        $display("");

        // ========================================================
        // Resumen
        // ========================================================
        $display("============================================");
        if (errors == 0)
            $display("TODOS LOS TESTS PASARON");
        else
            $display("TESTS FALLIDOS: %0d errores", errors);
        $display("============================================");

        #(CLK_PERIOD * 100);
        $finish;
    end

endmodule
