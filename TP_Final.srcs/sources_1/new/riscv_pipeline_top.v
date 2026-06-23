`timescale 1ns/1ps

module riscv_pipeline_top #
(
    parameter IMEM_DEPTH           = 256,
    parameter IMEM_ADDR_WIDTH      = 8,
    parameter DATA_MEM_ADDR_WIDTH  = 12
)
(
    input  wire        clk,
    input  wire        rst,

    // Puerto de programación de la memoria de instrucciones
    input  wire        prog_we,
    input  wire [31:0] prog_addr,
    input  wire [31:0] prog_wdata,

    // Control de ejecución (Debug Unit -> pipeline)
    input  wire        i_start,
    input  wire        i_step,
    input  wire        i_mode,   // 0=continuo, 1=paso a paso

    // Estado del pipeline (pipeline -> Debug Unit)
    output wire        o_halted,
    output wire [31:0] o_pc,

    // Debug read ports
    input  wire [4:0]                     debug_reg_addr,
    output wire [31:0]                    debug_reg_data,
    input  wire [DATA_MEM_ADDR_WIDTH-1:0] debug_mem_addr,
    output wire [31:0]                    debug_mem_data,

    // Latch outputs para debug
    output wire [31:0] dbg_if_id_pc,
    output wire [31:0] dbg_if_id_instr,

    output wire [31:0] dbg_id_ex_pc,
    output wire [31:0] dbg_id_ex_rs1_data,
    output wire [31:0] dbg_id_ex_rs2_data,
    output wire [31:0] dbg_id_ex_imm,
    output wire [4:0]  dbg_id_ex_rd,
    output wire [6:0]  dbg_id_ex_opcode,
    output wire [31:0] dbg_id_ex_alu_op_ctrl,

    output wire [31:0] dbg_ex_mem_alu_result,
    output wire [31:0] dbg_ex_mem_rs2_data,
    output wire [4:0]  dbg_ex_mem_rd,
    output wire [31:0] dbg_ex_mem_pc_plus4,
    output wire [31:0] dbg_ex_mem_branch_target,

    output wire [31:0] dbg_mem_wb_read_data,
    output wire [31:0] dbg_mem_wb_alu_result,
    output wire [4:0]  dbg_mem_wb_rd,
    output wire [31:0] dbg_mem_wb_pc_plus4
);

    // ============================================================
    // IF stage
    // ============================================================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_instr;

    wire        if_pc_en;
    wire [31:0] if_pc_next;

    // ============================================================
    // IF/ID latch
    // ============================================================
    wire        if_id_write_en;
    wire        if_id_flush;

    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instr;

    // ============================================================
    // ID stage
    // ============================================================
    wire [31:0] id_pc_out;
    wire [31:0] id_rs1_data_out;
    wire [31:0] id_rs2_data_out;
    wire [31:0] id_imm_out;

    wire [4:0]  id_rs1_out;
    wire [4:0]  id_rs2_out;
    wire [4:0]  id_rd_out;
    wire [2:0]  id_funct3_out;
    wire [6:0]  id_funct7_out;
    wire [6:0]  id_opcode_out;

    wire        id_Branch;
    wire        id_MemRead;
    wire        id_MemtoReg;
    wire [1:0]  id_ALUOp;
    wire        id_MemWrite;
    wire        id_ALUSrc;
    wire        id_RegWrite;
    wire        id_Jump;
    wire        id_IsJALR;
    wire        id_Halt;

    // ============================================================
    // Hazard detection
    // ============================================================
    wire        pc_write;
    wire        if_id_write;
    wire        hazard_id_ex_flush;

    // ============================================================
    // ID/EX latch
    // ============================================================
    wire        id_ex_flush;

    wire [31:0] ex_pc;
    wire [31:0] ex_rs1_data_raw;
    wire [31:0] ex_rs2_data_raw;
    wire [31:0] ex_imm;

    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [4:0]  ex_rd;

    wire [2:0]  ex_funct3;
    wire [6:0]  ex_funct7;
    wire [6:0]  ex_opcode;

    wire        ex_Branch;
    wire        ex_MemRead;
    wire        ex_MemtoReg;
    wire [1:0]  ex_ALUOp;
    wire        ex_MemWrite;
    wire        ex_ALUSrc;
    wire        ex_RegWrite;
    wire        ex_Jump;
    wire        ex_IsJALR;
    wire        ex_Halt;

    // ============================================================
    // Forwarding
    // ============================================================
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;

    reg  [31:0] ex_rs1_data_fwd;
    reg  [31:0] ex_rs2_data_fwd;

    // ============================================================
    // EX stage
    // ============================================================
    wire [31:0] ex_branch_target;
    wire [31:0] ex_pc_plus4;
    wire        ex_zero;
    wire [31:0] ex_alu_result;
    wire [31:0] ex_rs2_data_out;
    wire [4:0]  ex_rd_out;

    wire        ex_Branch_out;
    wire        ex_MemRead_out;
    wire        ex_MemWrite_out;
    wire        ex_MemtoReg_out;
    wire        ex_RegWrite_out;
    wire        ex_Jump_out;
    wire        ex_IsJALR_out;
    wire        ex_Halt_out;

    // ============================================================
    // EX/MEM latch
    // ============================================================
    wire        ex_mem_flush;

    wire [31:0] mem_branch_target;
    wire [31:0] mem_pc_plus4;
    wire        mem_zero;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rs2_data;
    wire [4:0]  mem_rd;

    wire        mem_Branch;
    wire        mem_MemRead;
    wire        mem_MemWrite;
    wire        mem_MemtoReg;
    wire        mem_RegWrite;
    wire [2:0]  mem_funct3;
    wire        mem_Jump;
    wire        mem_IsJALR;
    wire        mem_Halt;

    // ============================================================
    // MEM stage
    // ============================================================
    wire        mem_PCSrc;
    wire [31:0] mem_branch_target_out;

    wire [31:0] mem_wb_read_data;
    wire [31:0] mem_wb_alu_result;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_MemtoReg;
    wire        mem_wb_RegWrite;
    wire [31:0] mem_wb_pc_plus4;
    wire        mem_wb_IsJump;
    wire        mem_wb_Halt;

    // ============================================================
    // MEM/WB latch
    // ============================================================
    wire [31:0] wb_read_data;
    wire [31:0] wb_alu_result;
    wire [4:0]  wb_rd;
    wire        wb_MemtoReg;
    wire        wb_RegWrite;
    wire [31:0] wb_pc_plus4;
    wire        wb_IsJump;
    wire        wb_Halt;

    // ============================================================
    // WB stage
    // ============================================================
    wire [31:0] rf_write_data;
    wire [4:0]  rf_rd_addr;
    wire        rf_reg_write;

    // ============================================================
    // Control de ejecución: running / halted
    // ============================================================
    reg         running;
    reg         halted;
    reg  [31:0] halt_pc_latch;   // PC capturado de la instrucción HALT
    wire        pipeline_en;
    wire        halt_detected;

    assign halt_detected = wb_Halt;
    assign o_halted      = halted;
    assign pipeline_en   = running;

    always @(posedge clk) begin
        if (rst) begin
            running       <= 1'b0;
            halted        <= 1'b0;
            halt_pc_latch <= 32'b0;
        end
        else begin
            // Captura del PC de HALT cuando entra a ID stage.
            // En este momento id_pc es el PC de la instrucción HALT.
            // Guard !halted evita re-escrituras tras quedar detenido.
            if (id_Halt && !halted)
                halt_pc_latch <= id_pc;

            if (halt_detected) begin
                running <= 1'b0;
                halted  <= 1'b1;
            end
            else if (i_start) begin
                running <= 1'b1;
                halted  <= 1'b0;
            end
            else if (i_mode && i_step && !running && !halted) begin
                running <= 1'b1;
            end
            else if (i_mode && running) begin
                running <= 1'b0;
            end
        end
    end

    // ============================================================
    // Control de PC y flushes
    // ============================================================
    // Cuando HALT está en ID/EX/MEM, inhibir fetch para que no
    // entren instrucciones posteriores al HALT al pipeline.
    // Así el pipeline se vacía (NOPs detrás del HALT).
    wire halt_in_pipeline = id_Halt | ex_Halt | mem_Halt;

    assign if_pc_next     = (mem_PCSrc) ? mem_branch_target_out : if_pc_plus4;
    assign if_pc_en       = pipeline_en & ~halt_in_pipeline & ((mem_PCSrc) ? 1'b1 : pc_write);
    assign if_id_write_en = pipeline_en & ~halt_in_pipeline & ((mem_PCSrc) ? 1'b1 : if_id_write);

    assign if_id_flush   = mem_PCSrc | (pipeline_en & halt_in_pipeline);
    assign id_ex_flush   = hazard_id_ex_flush | mem_PCSrc;
    assign ex_mem_flush  = mem_PCSrc;

    // ============================================================
    // Debug output assigns
    // ============================================================
    // Cuando el pipeline está halted, reportar el PC de la instrucción HALT
    // (capturado en halt_pc_latch). En cualquier otro momento, reportar if_pc.
    // Esto hace que modo run y modo step terminen reportando el mismo PC.
    assign o_pc = halted ? halt_pc_latch : if_pc;

    assign dbg_if_id_pc    = id_pc;
    assign dbg_if_id_instr = id_instr;

    assign dbg_id_ex_pc       = ex_pc;
    assign dbg_id_ex_rs1_data = ex_rs1_data_raw;
    assign dbg_id_ex_rs2_data = ex_rs2_data_raw;
    assign dbg_id_ex_imm      = ex_imm;
    assign dbg_id_ex_rd       = ex_rd;
    assign dbg_id_ex_opcode   = ex_opcode;
    assign dbg_id_ex_alu_op_ctrl = {20'b0, ex_Halt, ex_IsJALR, ex_Jump, ex_RegWrite,
                                     ex_ALUSrc, ex_MemWrite, ex_ALUOp, ex_MemtoReg,
                                     ex_MemRead, ex_Branch};

    assign dbg_ex_mem_alu_result    = mem_alu_result;
    assign dbg_ex_mem_rs2_data      = mem_rs2_data;
    assign dbg_ex_mem_rd            = mem_rd;
    assign dbg_ex_mem_pc_plus4      = mem_pc_plus4;
    assign dbg_ex_mem_branch_target = mem_branch_target;

    assign dbg_mem_wb_read_data  = wb_read_data;
    assign dbg_mem_wb_alu_result = wb_alu_result;
    assign dbg_mem_wb_rd         = wb_rd;
    assign dbg_mem_wb_pc_plus4   = wb_pc_plus4;

    // ============================================================
    // MUXes de forwarding
    // 00 -> dato original desde ID/EX
    // 10 -> forward desde EX/MEM
    // 01 -> forward desde MEM/WB
    // ============================================================
    always @(*) begin
        case (forward_a)
            2'b10: ex_rs1_data_fwd = mem_alu_result;
            2'b01: ex_rs1_data_fwd = rf_write_data;
            default: ex_rs1_data_fwd = ex_rs1_data_raw;
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10: ex_rs2_data_fwd = mem_alu_result;
            2'b01: ex_rs2_data_fwd = rf_write_data;
            default: ex_rs2_data_fwd = ex_rs2_data_raw;
        endcase
    end

    // ============================================================
    // IF stage
    // ============================================================
    if_stage #(
        .IMEM_DEPTH      (IMEM_DEPTH),
        .IMEM_ADDR_WIDTH (IMEM_ADDR_WIDTH)
    ) u_if_stage (
        .clk        (clk),
        .rst        (rst),
        .pc_en      (if_pc_en),
        .pc_next    (if_pc_next),
        .prog_we    (prog_we),
        .prog_addr  (prog_addr),
        .prog_wdata (prog_wdata),
        .pc         (if_pc),
        .pc_plus4   (if_pc_plus4),
        .instr      (if_instr)
    );

    // ============================================================
    // IF/ID latch
    // ============================================================
    if_id_latch u_if_id_latch (
        .clk         (clk),
        .rst         (rst),
        .write_en    (if_id_write_en),
        .flush       (if_id_flush),
        .if_pc       (if_pc),
        .if_pc_plus4 (if_pc_plus4),
        .if_instr    (if_instr),
        .id_pc       (id_pc),
        .id_pc_plus4 (id_pc_plus4),
        .id_instr    (id_instr)
    );

    // ============================================================
    // ID stage
    // ============================================================
    id_stage u_id_stage (
        .clk           (clk),
        .reset         (rst),
        .pc_in         (id_pc),
        .instr_in      (id_instr),
        .wb_reg_write  (rf_reg_write),
        .wb_rd         (rf_rd_addr),
        .wb_write_data (rf_write_data),
        .pc_out        (id_pc_out),
        .rs1_data_out  (id_rs1_data_out),
        .rs2_data_out  (id_rs2_data_out),
        .imm_out       (id_imm_out),
        .rs1_out       (id_rs1_out),
        .rs2_out       (id_rs2_out),
        .rd_out        (id_rd_out),
        .funct3_out    (id_funct3_out),
        .funct7_out    (id_funct7_out),
        .opcode_out    (id_opcode_out),
        .Branch        (id_Branch),
        .MemRead       (id_MemRead),
        .MemtoReg      (id_MemtoReg),
        .ALUOp         (id_ALUOp),
        .MemWrite      (id_MemWrite),
        .ALUSrc        (id_ALUSrc),
        .RegWrite      (id_RegWrite),
        .Jump          (id_Jump),
        .IsJALR        (id_IsJALR),
        .Halt          (id_Halt),
        .debug_reg_addr(debug_reg_addr),
        .debug_reg_data(debug_reg_data)
    );

    // ============================================================
    // Hazard detection unit
    // ============================================================
    hazard_detection_unit u_hazard_detection_unit (
        .id_rs1      (id_rs1_out),
        .id_rs2      (id_rs2_out),
        .ex_rd       (ex_rd),
        .ex_MemRead  (ex_MemRead),
        .pc_write    (pc_write),
        .if_id_write (if_id_write),
        .id_ex_flush (hazard_id_ex_flush)
    );

    // ============================================================
    // ID/EX latch
    // ============================================================
    id_ex_latch u_id_ex_latch (
        .clk         (clk),
        .rst         (rst),
        .write_en    (pipeline_en),
        .flush       (id_ex_flush),

        .id_pc       (id_pc_out),
        .id_rs1_data (id_rs1_data_out),
        .id_rs2_data (id_rs2_data_out),
        .id_imm      (id_imm_out),

        .id_rs1      (id_rs1_out),
        .id_rs2      (id_rs2_out),
        .id_rd       (id_rd_out),

        .id_funct3   (id_funct3_out),
        .id_funct7   (id_funct7_out),
        .id_opcode   (id_opcode_out),

        .id_Branch   (id_Branch),
        .id_MemRead  (id_MemRead),
        .id_MemtoReg (id_MemtoReg),
        .id_ALUOp    (id_ALUOp),
        .id_MemWrite (id_MemWrite),
        .id_ALUSrc   (id_ALUSrc),
        .id_RegWrite (id_RegWrite),
        .id_Jump     (id_Jump),
        .id_IsJALR   (id_IsJALR),
        .id_Halt     (id_Halt),

        .ex_pc       (ex_pc),
        .ex_rs1_data (ex_rs1_data_raw),
        .ex_rs2_data (ex_rs2_data_raw),
        .ex_imm      (ex_imm),

        .ex_rs1      (ex_rs1),
        .ex_rs2      (ex_rs2),
        .ex_rd       (ex_rd),

        .ex_funct3   (ex_funct3),
        .ex_funct7   (ex_funct7),
        .ex_opcode   (ex_opcode),

        .ex_Branch   (ex_Branch),
        .ex_MemRead  (ex_MemRead),
        .ex_MemtoReg (ex_MemtoReg),
        .ex_ALUOp    (ex_ALUOp),
        .ex_MemWrite (ex_MemWrite),
        .ex_ALUSrc   (ex_ALUSrc),
        .ex_RegWrite (ex_RegWrite),
        .ex_Jump     (ex_Jump),
        .ex_IsJALR   (ex_IsJALR),
        .ex_Halt     (ex_Halt)
    );

    // ============================================================
    // Forwarding unit
    // ============================================================
    forwarding_unit u_forwarding_unit (
        .ex_rs1       (ex_rs1),
        .ex_rs2       (ex_rs2),
        .mem_rd       (mem_rd),
        .mem_RegWrite (mem_RegWrite),
        .wb_rd        (wb_rd),
        .wb_RegWrite  (wb_RegWrite),
        .forward_a    (forward_a),
        .forward_b    (forward_b)
    );

    // ============================================================
    // EX stage
    // ============================================================
    ex_stage u_ex_stage (
        .ex_pc          (ex_pc),
        .ex_rs1_data    (ex_rs1_data_fwd),
        .ex_rs2_data    (ex_rs2_data_fwd),
        .ex_imm         (ex_imm),

        .ex_rs1         (ex_rs1),
        .ex_rs2         (ex_rs2),
        .ex_rd          (ex_rd),

        .ex_funct3      (ex_funct3),
        .ex_funct7      (ex_funct7),
        .ex_opcode      (ex_opcode),

        .ex_Branch      (ex_Branch),
        .ex_MemRead     (ex_MemRead),
        .ex_MemtoReg    (ex_MemtoReg),
        .ex_ALUOp       (ex_ALUOp),
        .ex_MemWrite    (ex_MemWrite),
        .ex_ALUSrc      (ex_ALUSrc),
        .ex_RegWrite    (ex_RegWrite),
        .ex_Jump        (ex_Jump),
        .ex_IsJALR      (ex_IsJALR),
        .ex_Halt        (ex_Halt),

        .ex_branch_target (ex_branch_target),
        .ex_pc_plus4      (ex_pc_plus4),
        .ex_zero          (ex_zero),
        .ex_alu_result    (ex_alu_result),
        .ex_rs2_data_out  (ex_rs2_data_out),
        .ex_rd_out        (ex_rd_out),

        .ex_Branch_out    (ex_Branch_out),
        .ex_MemRead_out   (ex_MemRead_out),
        .ex_MemWrite_out  (ex_MemWrite_out),
        .ex_MemtoReg_out  (ex_MemtoReg_out),
        .ex_RegWrite_out  (ex_RegWrite_out),
        .ex_Jump_out      (ex_Jump_out),
        .ex_IsJALR_out    (ex_IsJALR_out),
        .ex_Halt_out      (ex_Halt_out)
    );

    // ============================================================
    // EX/MEM latch
    // ============================================================
    ex_mem_latch u_ex_mem_latch (
        .clk            (clk),
        .rst            (rst),
        .write_en       (pipeline_en),
        .flush          (ex_mem_flush),

        .ex_branch_target (ex_branch_target),
        .ex_pc_plus4      (ex_pc_plus4),
        .ex_zero          (ex_zero),
        .ex_alu_result    (ex_alu_result),
        .ex_rs2_data_out  (ex_rs2_data_out),
        .ex_rd_out        (ex_rd_out),

        .ex_Branch      (ex_Branch_out),
        .ex_MemRead     (ex_MemRead_out),
        .ex_MemWrite    (ex_MemWrite_out),
        .ex_MemtoReg    (ex_MemtoReg_out),
        .ex_RegWrite    (ex_RegWrite_out),
        .ex_funct3      (ex_funct3),
        .ex_Jump        (ex_Jump_out),
        .ex_IsJALR      (ex_IsJALR_out),
        .ex_Halt        (ex_Halt_out),

        .mem_branch_target (mem_branch_target),
        .mem_pc_plus4      (mem_pc_plus4),
        .mem_zero          (mem_zero),
        .mem_alu_result    (mem_alu_result),
        .mem_rs2_data      (mem_rs2_data),
        .mem_rd            (mem_rd),

        .mem_Branch      (mem_Branch),
        .mem_MemRead     (mem_MemRead),
        .mem_MemWrite    (mem_MemWrite),
        .mem_MemtoReg    (mem_MemtoReg),
        .mem_RegWrite    (mem_RegWrite),
        .mem_funct3      (mem_funct3),
        .mem_Jump        (mem_Jump),
        .mem_IsJALR      (mem_IsJALR),
        .mem_Halt        (mem_Halt)
    );

    // ============================================================
    // MEM stage
    // ============================================================
    mem_stage #(
        .DATA_MEM_ADDR_WIDTH (DATA_MEM_ADDR_WIDTH)
    ) u_mem_stage (
        .clk                  (clk),
        .rst                  (rst),

        .mem_branch_target    (mem_branch_target),
        .mem_pc_plus4         (mem_pc_plus4),
        .mem_zero             (mem_zero),
        .mem_alu_result       (mem_alu_result),
        .mem_rs2_data         (mem_rs2_data),
        .mem_rd               (mem_rd),
        .mem_Branch           (mem_Branch),
        .mem_MemRead          (mem_MemRead),
        .mem_MemWrite         (mem_MemWrite),
        .mem_MemtoReg         (mem_MemtoReg),
        .mem_RegWrite         (mem_RegWrite),
        .mem_funct3           (mem_funct3),
        .mem_Jump             (mem_Jump),
        .mem_IsJALR           (mem_IsJALR),
        .mem_Halt             (mem_Halt),

        .mem_PCSrc            (mem_PCSrc),
        .mem_branch_target_out(mem_branch_target_out),

        .wb_read_data         (mem_wb_read_data),
        .wb_alu_result        (mem_wb_alu_result),
        .wb_rd                (mem_wb_rd),
        .wb_MemtoReg          (mem_wb_MemtoReg),
        .wb_RegWrite          (mem_wb_RegWrite),
        .wb_pc_plus4          (mem_wb_pc_plus4),
        .wb_IsJump            (mem_wb_IsJump),
        .wb_Halt              (mem_wb_Halt),
        .debug_mem_addr       (debug_mem_addr),
        .debug_mem_data       (debug_mem_data)
    );

    // ============================================================
    // MEM/WB latch
    // ============================================================
    mem_wb_latch u_mem_wb_latch (
        .clk           (clk),
        .rst           (rst),
        .write_en      (pipeline_en),
        .flush         (1'b0),

        .mem_read_data (mem_wb_read_data),
        .mem_alu_result(mem_wb_alu_result),
        .mem_rd        (mem_wb_rd),
        .mem_MemtoReg  (mem_wb_MemtoReg),
        .mem_RegWrite  (mem_wb_RegWrite),
        .mem_pc_plus4  (mem_wb_pc_plus4),
        .mem_IsJump    (mem_wb_IsJump),
        .mem_Halt      (mem_wb_Halt),

        .wb_read_data  (wb_read_data),
        .wb_alu_result (wb_alu_result),
        .wb_rd         (wb_rd),
        .wb_MemtoReg   (wb_MemtoReg),
        .wb_RegWrite   (wb_RegWrite),
        .wb_pc_plus4   (wb_pc_plus4),
        .wb_IsJump     (wb_IsJump),
        .wb_Halt       (wb_Halt)
    );

    // ============================================================
    // WB stage
    // ============================================================
    wb_stage u_wb_stage (
        .wb_read_data  (wb_read_data),
        .wb_alu_result (wb_alu_result),
        .wb_rd         (wb_rd),
        .wb_MemtoReg   (wb_MemtoReg),
        .wb_RegWrite   (wb_RegWrite),
        .wb_pc_plus4   (wb_pc_plus4),
        .wb_IsJump     (wb_IsJump),

        .rf_write_data (rf_write_data),
        .rf_rd_addr    (rf_rd_addr),
        .rf_reg_write  (rf_reg_write)
    );

endmodule
