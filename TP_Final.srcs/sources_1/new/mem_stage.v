module mem_stage #(
    parameter DATA_MEM_ADDR_WIDTH = 12
)(
    input  wire        clk,
    input  wire        rst,

    // Entradas desde EX/MEM latch
    input  wire [31:0] mem_branch_target,
    input  wire [31:0] mem_pc_plus4,
    input  wire        mem_zero,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_rs2_data,
    input  wire [4:0]  mem_rd,
    input  wire        mem_Branch,
    input  wire        mem_MemRead,
    input  wire        mem_MemWrite,
    input  wire        mem_MemtoReg,
    input  wire        mem_RegWrite,
    input  wire [2:0]  mem_funct3,
    input  wire        mem_Jump,
    input  wire        mem_IsJALR,
    input  wire        mem_Halt,

    // Control del PC
    output wire        mem_PCSrc,
    output wire [31:0] mem_branch_target_out,

    // Salidas hacia MEM/WB latch
    output wire [31:0] wb_read_data,
    output wire [31:0] wb_alu_result,
    output wire [4:0]  wb_rd,
    output wire        wb_MemtoReg,
    output wire        wb_RegWrite,
    output wire [31:0] wb_pc_plus4,
    output wire        wb_IsJump,
    output wire        wb_Halt,

    input  wire [DATA_MEM_ADDR_WIDTH-1:0] debug_mem_addr,
    output wire [31:0]                    debug_mem_data
);

    wire [31:0] mem_data_read;
    wire [31:0] mem_data_extended;

    wire [1:0] byte_offset = mem_alu_result[1:0];

    wire [7:0] load_byte =
        (byte_offset == 2'b00) ? mem_data_read[7:0]   :
        (byte_offset == 2'b01) ? mem_data_read[15:8]  :
        (byte_offset == 2'b10) ? mem_data_read[23:16] :
                                 mem_data_read[31:24];

    wire [15:0] load_half =
        (byte_offset[1] == 1'b0) ? mem_data_read[15:0] :
                                   mem_data_read[31:16];

    // PCSrc: branch condicional O salto incondicional (JAL/JALR)
    assign mem_PCSrc = (mem_Branch & mem_zero) | mem_Jump;

    // Destino del PC:
    // - JALR: (rs1+imm) con bit[0]=0 (mem_alu_result viene de la ALU)
    // - JAL o branch: PC + imm (mem_branch_target)
    wire [31:0] jump_target;
    assign jump_target = mem_IsJALR ? {mem_alu_result[31:1], 1'b0} : mem_branch_target;
    assign mem_branch_target_out = jump_target;

    data_memory #(
        .ADDR_WIDTH(DATA_MEM_ADDR_WIDTH)
    ) u_data_memory (
        .clk        (clk),
        .rst        (rst),
        .MemRead    (mem_MemRead),
        .MemWrite   (mem_MemWrite),
        .funct3     (mem_funct3),
        .addr       (mem_alu_result),
        .write_data (mem_rs2_data),
        .read_data  (mem_data_read),
        .debug_addr (debug_mem_addr),
        .debug_data (debug_mem_data)
    );

    // Extensión de signo/cero para loads según funct3
    assign mem_data_extended =
        (mem_funct3 == 3'b000) ? {{24{load_byte[7]}},  load_byte}  : // lb
        (mem_funct3 == 3'b001) ? {{16{load_half[15]}}, load_half}  : // lh
        (mem_funct3 == 3'b010) ?  mem_data_read                    : // lw
        (mem_funct3 == 3'b100) ? { 24'b0,              load_byte}  : // lbu
        (mem_funct3 == 3'b101) ? { 16'b0,              load_half}  : // lhu
                                   mem_data_read;

    assign wb_read_data  = mem_data_extended;
    assign wb_alu_result = mem_alu_result;
    assign wb_rd         = mem_rd;
    assign wb_MemtoReg   = mem_MemtoReg;
    assign wb_RegWrite   = mem_RegWrite;
    assign wb_pc_plus4   = mem_pc_plus4;
    assign wb_IsJump     = mem_Jump;
    assign wb_Halt       = mem_Halt;

endmodule
