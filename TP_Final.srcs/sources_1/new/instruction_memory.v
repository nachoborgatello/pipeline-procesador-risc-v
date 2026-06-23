`timescale 1ns/1ps

module instruction_memory #
(
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = 8   // log2(DEPTH)
)
(
    input  wire        clk,

    // Puerto de lectura (Fetch)
    input  wire [31:0] addr,
    output reg  [31:0] instr,

    // Puerto de escritura (programación/debug/UART a futuro)
    input  wire        prog_we,
    input  wire [31:0] prog_addr,
    input  wire [31:0] prog_wdata
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP = addi x0, x0, 0
    end

    // Lectura combinacional
    always @(*) begin
        // Si la dirección no está alineada a palabra, devolvemos NOP
        if (addr[1:0] != 2'b00)
            instr = 32'h00000013;
        else if (addr[ADDR_WIDTH+1:2] < DEPTH)
            instr = mem[addr[ADDR_WIDTH+1:2]];
        else
            instr = 32'h00000013;
    end

    // Escritura síncrona para carga de programa
    always @(posedge clk) begin
        if (prog_we) begin
            if ((prog_addr[1:0] == 2'b00) &&
                (prog_addr[ADDR_WIDTH+1:2] < DEPTH))
                mem[prog_addr[ADDR_WIDTH+1:2]] <= prog_wdata;
        end
    end

endmodule