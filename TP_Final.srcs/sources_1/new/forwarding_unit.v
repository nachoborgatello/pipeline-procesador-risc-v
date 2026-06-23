module forwarding_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,

    input  wire [4:0] mem_rd,
    input  wire       mem_RegWrite,

    input  wire [4:0] wb_rd,
    input  wire       wb_RegWrite,

    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);

    // Codificación de selección para los MUX de forwarding:
    // 00 -> usar dato original desde ID/EX
    // 10 -> forward desde EX/MEM
    // 01 -> forward desde MEM/WB
    // 11 -> no usado
    localparam [1:0] FWD_NONE = 2'b00,
                     FWD_WB   = 2'b01,
                     FWD_MEM  = 2'b10;

    always @(*) begin
        // Valor por defecto: sin forwarding
        forward_a = FWD_NONE;
        forward_b = FWD_NONE;

        // -----------------------------
        // Forwarding para operando A
        // -----------------------------
        if (mem_RegWrite && (mem_rd != 5'b00000) && (mem_rd == ex_rs1)) begin
            forward_a = FWD_MEM;
        end
        else if (wb_RegWrite && (wb_rd != 5'b00000) && (wb_rd == ex_rs1)) begin
            forward_a = FWD_WB;
        end

        // -----------------------------
        // Forwarding para operando B
        // -----------------------------
        if (mem_RegWrite && (mem_rd != 5'b00000) && (mem_rd == ex_rs2)) begin
            forward_b = FWD_MEM;
        end
        else if (wb_RegWrite && (wb_rd != 5'b00000) && (wb_rd == ex_rs2)) begin
            forward_b = FWD_WB;
        end
    end

endmodule