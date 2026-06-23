`timescale 1ns/1ps

module reg_file (
    input  wire        clk,
    input  wire        rst,
    input  wire        reg_write_en,

    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,

    input  wire [31:0] rd_data,

    output reg  [31:0] rs1_data,
    output reg  [31:0] rs2_data,

    input  wire [4:0]  debug_addr,
    output wire [31:0] debug_data
);

    reg [31:0] regs [0:31];
    integer i;

    // Escritura síncrona en flanco de subida
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'h00000000;
        end
        else begin
            // x0 siempre debe permanecer en cero
            regs[0] <= 32'h00000000;

            if (reg_write_en && (rd_addr != 5'd0))
                regs[rd_addr] <= rd_data;
        end
    end

    assign debug_data = regs[debug_addr];

    // Lectura síncrona en flanco de bajada con bypass WB.
    // El posedge actualiza MEM/WB antes del negedge, pero el reg_file recién
    // escribe en el SIGUIENTE posedge (por NBA). El bypass compensa esto:
    // si WB está escribiendo al mismo registro que se lee, se devuelve el
    // dato de WB directamente en lugar de esperar al posedge siguiente.
    always @(negedge clk) begin
        if (rst) begin
            rs1_data <= 32'h00000000;
            rs2_data <= 32'h00000000;
        end
        else begin
            if (reg_write_en && (rd_addr != 5'd0) && (rd_addr == rs1_addr))
                rs1_data <= rd_data;
            else
                rs1_data <= (rs1_addr == 5'd0) ? 32'h00000000 : regs[rs1_addr];

            if (reg_write_en && (rd_addr != 5'd0) && (rd_addr == rs2_addr))
                rs2_data <= rd_data;
            else
                rs2_data <= (rs2_addr == 5'd0) ? 32'h00000000 : regs[rs2_addr];
        end
    end

endmodule