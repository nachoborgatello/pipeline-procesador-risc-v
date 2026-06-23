module id_stage (
    input  wire        clk,
    input  wire        reset,

    // Desde IF/ID latch
    input  wire [31:0] pc_in,
    input  wire [31:0] instr_in,

    // Write-back desde etapa posterior
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd,
    input  wire [31:0] wb_write_data,

    // Salidas de datos hacia ID/EX
    output wire [31:0] pc_out,
    output wire [31:0] rs1_data_out,
    output wire [31:0] rs2_data_out,
    output wire [31:0] imm_out,

    // Campos de la instrucción
    output wire [4:0]  rs1_out,
    output wire [4:0]  rs2_out,
    output wire [4:0]  rd_out,
    output wire [2:0]  funct3_out,
    output wire [6:0]  funct7_out,
    output wire [6:0]  opcode_out,

    // Señales de control
    output wire        Branch,
    output wire        MemRead,
    output wire        MemtoReg,
    output wire [1:0]  ALUOp,
    output wire        MemWrite,
    output wire        ALUSrc,
    output wire        RegWrite,
    output wire        Jump,
    output wire        IsJALR,
    output wire        Halt,

    input  wire [4:0]  debug_reg_addr,
    output wire [31:0] debug_reg_data
);

    assign opcode_out = instr_in[6:0];
    assign rd_out     = instr_in[11:7];
    assign funct3_out = instr_in[14:12];
    assign rs1_out    = instr_in[19:15];
    assign rs2_out    = instr_in[24:20];
    assign funct7_out = instr_in[31:25];

    assign pc_out = pc_in;

    reg_file u_reg_file (
        .clk         (clk),
        .rst         (reset),
        .reg_write_en(wb_reg_write),
        .rs1_addr    (rs1_out),
        .rs2_addr    (rs2_out),
        .rd_addr     (wb_rd),
        .rd_data     (wb_write_data),
        .rs1_data    (rs1_data_out),
        .rs2_data    (rs2_data_out),
        .debug_addr  (debug_reg_addr),
        .debug_data  (debug_reg_data)
    );

    imm_gen u_imm_gen (
        .instr   (instr_in),
        .imm_out (imm_out)
    );

    control_unit u_control_unit (
        .opcode   (opcode_out),
        .Branch   (Branch),
        .MemRead  (MemRead),
        .MemtoReg (MemtoReg),
        .ALUOp    (ALUOp),
        .MemWrite (MemWrite),
        .ALUSrc   (ALUSrc),
        .RegWrite (RegWrite),
        .Jump     (Jump),
        .IsJALR   (IsJALR),
        .Halt     (Halt)
    );

endmodule
