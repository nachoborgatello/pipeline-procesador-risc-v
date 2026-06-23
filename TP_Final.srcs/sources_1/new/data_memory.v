module data_memory #(
    parameter ADDR_WIDTH = 12  // 2^12 bytes = 4096 bytes = 4 KB
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        MemRead,
    input  wire        MemWrite,
    input  wire [2:0]  funct3,

    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,

    input  wire [ADDR_WIDTH-1:0] debug_addr,
    output wire [31:0]           debug_data
);

    localparam BYTE_DEPTH = (1 << ADDR_WIDTH);

    reg [7:0] memory [0:BYTE_DEPTH-1];
    integer i;

    wire [ADDR_WIDTH-1:0] byte_addr;
    wire [ADDR_WIDTH-1:0] word_base_addr;
    wire                  word_aligned;
    wire                  addr_in_range;
    wire                  read_in_range;

    assign byte_addr      = addr[ADDR_WIDTH-1:0];
    assign word_base_addr = {byte_addr[ADDR_WIDTH-1:2], 2'b00};
    assign word_aligned   = (addr[1:0] == 2'b00);

    assign addr_in_range  = (addr[31:ADDR_WIDTH] == 0) &&
                            (byte_addr <= BYTE_DEPTH - 4);
    assign read_in_range  = (addr[31:ADDR_WIDTH] == 0) &&
                            (word_base_addr <= BYTE_DEPTH - 4);

    // Escritura sincrónica con soporte sb/sh/sw via funct3
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < BYTE_DEPTH; i = i + 1)
                memory[i] <= 8'b0;
        end
        else if (MemWrite) begin
            case (funct3)
                3'b000: begin // sb: escribe 1 byte
                    if (addr[31:ADDR_WIDTH] == 0)
                        memory[byte_addr] <= write_data[7:0];
                end
                3'b001: begin // sh: escribe 2 bytes (little-endian)
                    if (addr[31:ADDR_WIDTH] == 0 && byte_addr < BYTE_DEPTH - 1) begin
                        memory[byte_addr]     <= write_data[7:0];
                        memory[byte_addr + 1] <= write_data[15:8];
                    end
                end
                default: begin // sw: escribe 4 bytes (little-endian), requiere alineación
                    if (word_aligned && addr_in_range) begin
                        memory[byte_addr]     <= write_data[7:0];
                        memory[byte_addr + 1] <= write_data[15:8];
                        memory[byte_addr + 2] <= write_data[23:16];
                        memory[byte_addr + 3] <= write_data[31:24];
                    end
                end
            endcase
        end
    end

    wire [ADDR_WIDTH-1:0] debug_word_base = {debug_addr[ADDR_WIDTH-1:2], 2'b00};
    assign debug_data = {
        memory[debug_word_base + 3],
        memory[debug_word_base + 2],
        memory[debug_word_base + 1],
        memory[debug_word_base]
    };

    // Lectura combinacional: devuelve la palabra de 32 bits que contiene addr
    // La extracción de byte/halfword y la extensión de signo/cero se hacen en mem_stage
    always @(*) begin
        if (MemRead && read_in_range) begin
            read_data = {
                memory[word_base_addr + 3],
                memory[word_base_addr + 2],
                memory[word_base_addr + 1],
                memory[word_base_addr]
            };
        end
        else begin
            read_data = 32'b0;
        end
    end

endmodule
