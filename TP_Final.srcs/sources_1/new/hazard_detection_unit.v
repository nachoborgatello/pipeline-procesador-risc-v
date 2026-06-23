`timescale 1ns/1ps

module hazard_detection_unit (
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire [4:0] ex_rd,
    input  wire       ex_MemRead,

    output reg        pc_write,
    output reg        if_id_write,
    output reg        id_ex_flush
);

    always @(*) begin
        // Valores por defecto: el pipeline avanza normalmente
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        id_ex_flush = 1'b0;

        // Load-use hazard:
        // si la instrucción en EX es un load y su destino coincide
        // con alguna fuente de la instrucción en ID, se debe hacer stall
        if (ex_MemRead && (ex_rd != 5'b00000) &&
            ((ex_rd == id_rs1) || (ex_rd == id_rs2))) begin
            pc_write    = 1'b0; // frena PC
            if_id_write = 1'b0; // frena IF/ID
            id_ex_flush = 1'b1; // inyecta NOP en ID/EX
        end
    end

endmodule