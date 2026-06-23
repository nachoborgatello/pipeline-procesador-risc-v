`timescale 1ns / 1ps
`default_nettype none

module tb_riscv_pipeline_top;

    localparam IMEM_DEPTH          = 256;
    localparam IMEM_ADDR_WIDTH     = 8;
    localparam DATA_MEM_ADDR_WIDTH = 12;

    localparam CLK_PERIOD = 10;
    localparam NOP        = 32'h0000_0013; // addi x0, x0, 0

    reg         clk;
    reg         rst;
    reg         prog_we;
    reg [31:0]  prog_addr;
    reg [31:0]  prog_wdata;
    reg         i_start;
    reg         i_step;
    reg         i_mode;
    wire        o_halted;

    integer tb_cycle_count;
    integer tb_error_count;
    integer tb_hazard_count;
    integer tb_stall_count;
    integer tb_branch_count;

    riscv_pipeline_top #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DATA_MEM_ADDR_WIDTH(DATA_MEM_ADDR_WIDTH)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .prog_we   (prog_we),
        .prog_addr (prog_addr),
        .prog_wdata(prog_wdata),
        .i_start   (i_start),
        .i_step    (i_step),
        .i_mode    (i_mode),
        .o_halted  (o_halted),
        .o_pc      (),
        .debug_reg_addr (5'd0),
        .debug_reg_data (),
        .debug_mem_addr ({12{1'b0}}),
        .debug_mem_data (),
        .dbg_if_id_pc         (),
        .dbg_if_id_instr      (),
        .dbg_id_ex_pc         (),
        .dbg_id_ex_rs1_data   (),
        .dbg_id_ex_rs2_data   (),
        .dbg_id_ex_imm        (),
        .dbg_id_ex_rd         (),
        .dbg_id_ex_opcode     (),
        .dbg_id_ex_alu_op_ctrl(),
        .dbg_ex_mem_alu_result    (),
        .dbg_ex_mem_rs2_data      (),
        .dbg_ex_mem_rd            (),
        .dbg_ex_mem_pc_plus4      (),
        .dbg_ex_mem_branch_target (),
        .dbg_mem_wb_read_data  (),
        .dbg_mem_wb_alu_result (),
        .dbg_mem_wb_rd         (),
        .dbg_mem_wb_pc_plus4   ()
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // Funciones de codificación RV32I
    // ============================================================
    function [31:0] rv32i_addi;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_addi = {imm12, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function [31:0] rv32i_add;
        input [4:0] rd; input [4:0] rs1; input [4:0] rs2;
        rv32i_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function [31:0] rv32i_lw;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_lw = {imm12, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function [31:0] rv32i_sw;
        input [4:0] rs2; input [4:0] rs1; input [11:0] imm12;
        rv32i_sw = {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
    endfunction

    function [31:0] rv32i_sb;
        input [4:0] rs2; input [4:0] rs1; input [11:0] imm12;
        rv32i_sb = {imm12[11:5], rs2, rs1, 3'b000, imm12[4:0], 7'b0100011};
    endfunction

    function [31:0] rv32i_sh;
        input [4:0] rs2; input [4:0] rs1; input [11:0] imm12;
        rv32i_sh = {imm12[11:5], rs2, rs1, 3'b001, imm12[4:0], 7'b0100011};
    endfunction

    function [31:0] rv32i_slli;
        input [4:0] rd; input [4:0] rs1; input [4:0] shamt;
        rv32i_slli = {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011};
    endfunction

    function [31:0] rv32i_or;
        input [4:0] rd; input [4:0] rs1; input [4:0] rs2;
        rv32i_or = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011};
    endfunction

    function [31:0] rv32i_lb;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_lb = {imm12, rs1, 3'b000, rd, 7'b0000011};
    endfunction

    function [31:0] rv32i_lh;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_lh = {imm12, rs1, 3'b001, rd, 7'b0000011};
    endfunction

    function [31:0] rv32i_lbu;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_lbu = {imm12, rs1, 3'b100, rd, 7'b0000011};
    endfunction

    function [31:0] rv32i_lhu;
        input [4:0] rd; input [4:0] rs1; input [11:0] imm12;
        rv32i_lhu = {imm12, rs1, 3'b101, rd, 7'b0000011};
    endfunction

    function [31:0] rv32i_beq;
        input [4:0] rs1; input [4:0] rs2; input [12:0] imm13;
        rv32i_beq = {imm13[12], imm13[10:5], rs2, rs1, 3'b000,
                     imm13[4:1], imm13[11], 7'b1100011};
    endfunction

    // LUI: imm20 son los bits [31:12] del resultado
    function [31:0] rv32i_lui;
        input [4:0]  rd;
        input [19:0] imm20;
        rv32i_lui = {imm20, rd, 7'b0110111};
    endfunction

    // JAL: imm21 es el offset con signo (bit 0 siempre 0)
    function [31:0] rv32i_jal;
        input [4:0]  rd;
        input [20:0] imm21;
        rv32i_jal = {imm21[20], imm21[10:1], imm21[11],
                     imm21[19:12], rd, 7'b1101111};
    endfunction

    // JALR: salta a rs1 + imm12
    function [31:0] rv32i_jalr;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] imm12;
        rv32i_jalr = {imm12, rs1, 3'b000, rd, 7'b1100111};
    endfunction

    // ============================================================
    // Lectura jerárquica del banco de registros
    // ============================================================
    function [31:0] tb_read_reg;
        input [4:0] tb_reg_idx;
        begin
            case (tb_reg_idx)
                5'd0  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[0];
                5'd1  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[1];
                5'd2  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[2];
                5'd3  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[3];
                5'd4  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[4];
                5'd5  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[5];
                5'd6  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[6];
                5'd7  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[7];
                5'd8  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[8];
                5'd9  : tb_read_reg = dut.u_id_stage.u_reg_file.regs[9];
                5'd10 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[10];
                5'd11 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[11];
                5'd12 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[12];
                5'd13 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[13];
                5'd14 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[14];
                5'd15 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[15];
                5'd16 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[16];
                5'd17 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[17];
                5'd18 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[18];
                5'd19 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[19];
                5'd20 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[20];
                5'd21 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[21];
                5'd22 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[22];
                5'd23 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[23];
                5'd24 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[24];
                5'd25 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[25];
                5'd26 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[26];
                5'd27 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[27];
                5'd28 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[28];
                5'd29 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[29];
                5'd30 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[30];
                5'd31 : tb_read_reg = dut.u_id_stage.u_reg_file.regs[31];
                default: tb_read_reg = 32'hXXXX_XXXX;
            endcase
        end
    endfunction

    // ============================================================
    // Tareas auxiliares
    // ============================================================
    task tb_prog_write;
        input [31:0] tb_addr;
        input [31:0] tb_data;
        begin
            @(negedge clk);
            prog_addr  = tb_addr;
            prog_wdata = tb_data;
            prog_we    = 1'b1;
            @(negedge clk);
            prog_we    = 1'b0;
            $display("[TB][PROG] addr=0x%08h data=0x%08h", tb_addr, tb_data);
        end
    endtask

    task tb_prog_write_word;
        input integer tb_word_index;
        input [31:0]  tb_instr;
        tb_prog_write(tb_word_index * 4, tb_instr);
    endtask

    task tb_run_cycles;
        input integer tb_num_cycles;
        integer i;
        begin
            for (i = 0; i < tb_num_cycles; i = i + 1)
                @(posedge clk);
        end
    endtask

    task tb_expect_reg;
        input [4:0]        tb_reg_idx;
        input [31:0]       tb_expected;
        input [8*64-1:0]   tb_msg;
        reg   [31:0]       tb_actual;
        begin
            tb_actual = tb_read_reg(tb_reg_idx);
            if (tb_actual !== tb_expected) begin
                tb_error_count = tb_error_count + 1;
                $display("[TB][ERROR] %0s -> x%0d esperado=0x%08h obtenido=0x%08h",
                         tb_msg, tb_reg_idx, tb_expected, tb_actual);
            end else begin
                $display("[TB][OK]    %0s -> x%0d = 0x%08h",
                         tb_msg, tb_reg_idx, tb_actual);
            end
        end
    endtask

    task tb_expect_true;
        input             tb_condition;
        input [8*64-1:0]  tb_msg;
        begin
            if (!tb_condition) begin
                tb_error_count = tb_error_count + 1;
                $display("[TB][ERROR] %0s", tb_msg);
            end else begin
                $display("[TB][OK]    %0s", tb_msg);
            end
        end
    endtask

    task tb_reset_and_run;
        input integer tb_num_cycles;
        begin
            rst = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            $display("[TB] Reset desactivado");
            // Pulso de start para que el pipeline arranque en modo continuo
            i_mode  = 1'b0;
            i_start = 1'b1;
            #(CLK_PERIOD);
            i_start = 1'b0;
            tb_run_cycles(tb_num_cycles);
        end
    endtask

    // ============================================================
    // FASE 1: forwarding, store/load lw, hazard, beq, lb/lh/lbu/lhu
    // ============================================================
    // Bloque 1 (words 0-19): R/I, forwarding, branch, sw/lw
    // Bloque 2 (words 20-40): lb / lh / lbu / lhu
    //
    // Mapa de registros (no se solapan entre bloques):
    //   x1-x12: bloque 1
    //   x13-x15, x20-x28: bloque 2
    // ============================================================
    task tb_load_phase1;
        begin
            // --- Bloque 1 ---
            tb_prog_write_word( 0, rv32i_addi(5'd7,  5'd0, 12'd7));
            tb_prog_write_word( 1, rv32i_addi(5'd8,  5'd0, 12'd8));
            tb_prog_write_word( 2, rv32i_addi(5'd9,  5'd0, 12'd9));
            tb_prog_write_word( 3, rv32i_addi(5'd12, 5'd0, 12'd25));
            tb_prog_write_word( 4, rv32i_addi(5'd1,  5'd0, 12'd5));
            tb_prog_write_word( 5, rv32i_addi(5'd2,  5'd0, 12'd10));
            tb_prog_write_word( 6, rv32i_add( 5'd3,  5'd1, 5'd2));
            tb_prog_write_word( 7, rv32i_add( 5'd4,  5'd3, 5'd1));
            tb_prog_write_word( 8, rv32i_sw(  5'd4,  5'd0, 12'd0));
            tb_prog_write_word( 9, rv32i_lw(  5'd5,  5'd0, 12'd0));
            tb_prog_write_word(10, rv32i_add( 5'd6,  5'd5, 5'd1));
            tb_prog_write_word(11, rv32i_beq( 5'd6,  5'd12, 13'd16));
            tb_prog_write_word(12, rv32i_addi(5'd7,  5'd0, 12'd111));  // wrong-path
            tb_prog_write_word(13, rv32i_addi(5'd8,  5'd0, 12'd122));  // wrong-path
            tb_prog_write_word(14, rv32i_addi(5'd9,  5'd0, 12'd133));  // wrong-path
            tb_prog_write_word(15, rv32i_addi(5'd10, 5'd0, 12'd55));   // branch target
            tb_prog_write_word(16, rv32i_sw(  5'd10, 5'd0, 12'd4));
            tb_prog_write_word(17, rv32i_lw(  5'd11, 5'd0, 12'd4));
            tb_prog_write_word(18, NOP);
            tb_prog_write_word(19, NOP);

            // --- Bloque 2: construir 0x0072FF81 sin LUI, luego lb/lh/lbu/lhu ---
            // mem[8..11] = 0x0072FF81 (little-endian)
            tb_prog_write_word(20, rv32i_addi(5'd13, 5'd0,  12'd8));
            tb_prog_write_word(21, rv32i_addi(5'd14, 5'd0,  12'h081));
            tb_prog_write_word(22, rv32i_addi(5'd15, 5'd0,  12'h0FF));
            tb_prog_write_word(23, rv32i_slli(5'd15, 5'd15, 5'd8));
            tb_prog_write_word(24, rv32i_or(  5'd14, 5'd14, 5'd15));
            tb_prog_write_word(25, rv32i_addi(5'd15, 5'd0,  12'h072));
            tb_prog_write_word(26, rv32i_slli(5'd15, 5'd15, 5'd16));
            tb_prog_write_word(27, rv32i_or(  5'd14, 5'd14, 5'd15));
            tb_prog_write_word(28, rv32i_sw(  5'd14, 5'd13, 12'd0));
            tb_prog_write_word(29, rv32i_lb(  5'd20, 5'd13, 12'd0));
            tb_prog_write_word(30, rv32i_lb(  5'd21, 5'd13, 12'd1));
            tb_prog_write_word(31, rv32i_lb(  5'd22, 5'd13, 12'd2));
            tb_prog_write_word(32, rv32i_lbu( 5'd23, 5'd13, 12'd0));
            tb_prog_write_word(33, rv32i_lbu( 5'd24, 5'd13, 12'd1));
            tb_prog_write_word(34, rv32i_lh(  5'd25, 5'd13, 12'd0));
            tb_prog_write_word(35, rv32i_lh(  5'd26, 5'd13, 12'd2));
            tb_prog_write_word(36, rv32i_lhu( 5'd27, 5'd13, 12'd0));
            tb_prog_write_word(37, rv32i_lhu( 5'd28, 5'd13, 12'd2));
            tb_prog_write_word(38, NOP);
            tb_prog_write_word(39, NOP);
            tb_prog_write_word(40, NOP);
        end
    endtask

    // ============================================================
    // FASE 2: LUI + sb + sh
    // ============================================================
    // Programa fresco en IMEM, data memory limpia (rst entre fases).
    //
    //  0: lui  x1, 0xDEADB   → x1 = 0xDEADB000
    //  1: lui  x2, 0x00001   → x2 = 0x00001000
    //  2: add  x3, x1, x2   → x3 = 0xDEADC000
    //  3: NOP
    //  4: NOP
    //
    //  5: addi x4, x0, 0x5A  → x4 = 0x5A = 90
    //  6: sb   x4, 0(x0)     → mem[0] = 0x5A
    //  7: addi x5, x0, 0x234 → x5 = 0x234 = 564
    //  8: sh   x5, 4(x0)     → mem[4..5] = 0x0234 (little-endian)
    //  9: lbu  x6, 0(x0)     → x6 = 0x0000005A  (verifica sb)
    // 10: lhu  x7, 4(x0)     → x7 = 0x00000234  (verifica sh)
    // 11: NOP
    // 12: NOP
    // 13: NOP
    // ============================================================
    task tb_load_phase2;
        begin
            tb_prog_write_word( 0, rv32i_lui( 5'd1, 20'hDEADB));
            tb_prog_write_word( 1, rv32i_lui( 5'd2, 20'h00001));
            tb_prog_write_word( 2, rv32i_add( 5'd3, 5'd1, 5'd2));
            tb_prog_write_word( 3, NOP);
            tb_prog_write_word( 4, NOP);

            tb_prog_write_word( 5, rv32i_addi(5'd4, 5'd0, 12'h05A));
            tb_prog_write_word( 6, rv32i_sb(  5'd4, 5'd0, 12'd0));
            tb_prog_write_word( 7, rv32i_addi(5'd5, 5'd0, 12'h234));
            tb_prog_write_word( 8, rv32i_sh(  5'd5, 5'd0, 12'd4));
            tb_prog_write_word( 9, rv32i_lbu( 5'd6, 5'd0, 12'd0));
            tb_prog_write_word(10, rv32i_lhu( 5'd7, 5'd0, 12'd4));
            tb_prog_write_word(11, NOP);
            tb_prog_write_word(12, NOP);
            tb_prog_write_word(13, NOP);

            // Rellenar words restantes con NOP para no ejecutar instrucciones
            // de la fase anterior que pudieron quedar en IMEM
            tb_prog_write_word(14, NOP);
            tb_prog_write_word(15, NOP);
        end
    endtask

    // ============================================================
    // FASE 3: JAL + JALR
    // ============================================================
    // Programa fresco, data memory limpia.
    //
    //  0 (PC=0):  jal  x1, +12     → salta a word 3 (PC=12), x1 = 4
    //  1 (PC=4):  addi x10, x0, 55 → wrong-path, NO debe ejecutarse
    //  2 (PC=8):  addi x10, x0, 66 → wrong-path, NO debe ejecutarse
    //  3 (PC=12): addi x2, x0, 99  → x2 = 99  (confirmacion de target JAL)
    //  4 (PC=16): NOP
    //  5 (PC=20): NOP
    //
    //  6 (PC=24): addi x3, x0, 40  → x3 = 40  (addr word10 = 10*4)
    //  7 (PC=28): jalr x4, x3, 0   → salta a 40 (word 10), x4 = 32
    //  8 (PC=32): addi x10, x0, 77 → wrong-path, NO debe ejecutarse
    //  9 (PC=36): addi x10, x0, 88 → wrong-path, NO debe ejecutarse
    // 10 (PC=40): addi x5, x0, 42  → x5 = 42  (confirmacion de target JALR)
    // 11 (PC=44): NOP
    // 12 (PC=48): NOP
    // 13 (PC=52): NOP
    //
    // x10 debe quedar en 0: confirma que AMBOS wrong-paths fueron flusheados.
    // ============================================================
    task tb_load_phase3;
        begin
            tb_prog_write_word( 0, rv32i_jal(  5'd1,  21'd12));
            tb_prog_write_word( 1, rv32i_addi( 5'd10, 5'd0, 12'd55));
            tb_prog_write_word( 2, rv32i_addi( 5'd10, 5'd0, 12'd66));
            tb_prog_write_word( 3, rv32i_addi( 5'd2,  5'd0, 12'd99));
            tb_prog_write_word( 4, NOP);
            tb_prog_write_word( 5, NOP);
            tb_prog_write_word( 6, rv32i_addi( 5'd3,  5'd0, 12'd40));
            tb_prog_write_word( 7, rv32i_jalr( 5'd4,  5'd3, 12'd0));
            tb_prog_write_word( 8, rv32i_addi( 5'd10, 5'd0, 12'd77));
            tb_prog_write_word( 9, rv32i_addi( 5'd10, 5'd0, 12'd88));
            tb_prog_write_word(10, rv32i_addi( 5'd5,  5'd0, 12'd42));
            tb_prog_write_word(11, NOP);
            tb_prog_write_word(12, NOP);
            tb_prog_write_word(13, NOP);
        end
    endtask

    // ============================================================
    // Monitor de eventos (activo durante toda la simulación)
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            tb_cycle_count  = 0;
            tb_hazard_count = 0;
            tb_stall_count  = 0;
            tb_branch_count = 0;
        end else begin
            tb_cycle_count = tb_cycle_count + 1;

            if (dut.hazard_id_ex_flush === 1'b1) begin
                tb_hazard_count = tb_hazard_count + 1;
                $display("[TB][C%0d] hazard_id_ex_flush=1", tb_cycle_count);
                if (dut.pc_write    !== 1'b0)
                    $display("[TB][WARN][C%0d] pc_write deberia ser 0 ante load-use", tb_cycle_count);
                if (dut.if_id_write !== 1'b0)
                    $display("[TB][WARN][C%0d] if_id_write deberia ser 0 ante load-use", tb_cycle_count);
            end

            if ((dut.mem_PCSrc   !== 1'b1) &&
                (dut.pc_write    === 1'b0) &&
                (dut.if_id_write === 1'b0)) begin
                tb_stall_count = tb_stall_count + 1;
            end

            if (dut.mem_PCSrc === 1'b1) begin
                tb_branch_count = tb_branch_count + 1;
                $display("[TB][C%0d] mem_PCSrc=1 -> salto/branch tomado", tb_cycle_count);
            end
        end
    end

    // ============================================================
    // Secuencia principal
    // ============================================================
    initial begin
        rst        = 1'b1;
        prog_we    = 1'b0;
        prog_addr  = 32'd0;
        prog_wdata = 32'd0;
        i_start    = 1'b0;
        i_step     = 1'b0;
        i_mode     = 1'b0;
        tb_error_count = 0;

        $dumpfile("tb_riscv_pipeline_top.vcd");
        $dumpvars(0, tb_riscv_pipeline_top);

        // ===========================================================
        // FASE 1: forwarding, hazard, branch, sw/lw, lb/lh/lbu/lhu
        // ===========================================================
        $display("============================================================");
        $display(" FASE 1: forwarding / hazard / branch / load-store");
        $display("============================================================");

        tb_load_phase1();
        tb_reset_and_run(70);

        $display("--- Verificaciones Fase 1 Bloque 1 ---");
        tb_expect_reg(5'd0,  32'd0,          "x0 siempre cero");
        tb_expect_reg(5'd7,  32'd7,          "x7 no sobreescrito (wrong-path flusheado)");
        tb_expect_reg(5'd8,  32'd8,          "x8 no sobreescrito (wrong-path flusheado)");
        tb_expect_reg(5'd9,  32'd9,          "x9 no sobreescrito (wrong-path flusheado)");
        tb_expect_reg(5'd12, 32'd25,         "x12 constante de branch");
        tb_expect_reg(5'd1,  32'd5,          "addi x1=5");
        tb_expect_reg(5'd2,  32'd10,         "addi x2=10");
        tb_expect_reg(5'd3,  32'd15,         "forwarding add x3=x1+x2=15");
        tb_expect_reg(5'd4,  32'd20,         "forwarding add x4=x3+x1=20");
        tb_expect_reg(5'd5,  32'd20,         "sw+lw: x5=mem[0]=20");
        tb_expect_reg(5'd6,  32'd25,         "load-use hazard: x6=x5+x1=25");
        tb_expect_reg(5'd10, 32'd55,         "branch target ejecutado: x10=55");
        tb_expect_reg(5'd11, 32'd55,         "sw+lw tras branch: x11=55");
        tb_expect_true((tb_hazard_count >= 1), "Se observo hazard load-use");
        tb_expect_true((tb_stall_count  >= 1), "Se observo stall por hazard");
        tb_expect_true((tb_branch_count >= 1), "Se observo branch/salto tomado");

        $display("--- Verificaciones Fase 1 Bloque 2: lb/lh/lbu/lhu ---");
        tb_expect_reg(5'd14, 32'h0072FF81,   "x14 patron 0x0072FF81 construido");
        tb_expect_reg(5'd20, 32'hFFFFFF81,   "lb  byte@0 0x81 -> sign-ext 0xFFFFFF81");
        tb_expect_reg(5'd21, 32'hFFFFFFFF,   "lb  byte@1 0xFF -> sign-ext 0xFFFFFFFF");
        tb_expect_reg(5'd22, 32'h00000072,   "lb  byte@2 0x72 -> sin cambio");
        tb_expect_reg(5'd23, 32'h00000081,   "lbu byte@0 0x81 -> zero-ext 0x81");
        tb_expect_reg(5'd24, 32'h000000FF,   "lbu byte@1 0xFF -> zero-ext 0xFF");
        tb_expect_reg(5'd25, 32'hFFFFFF81,   "lh  half@0 0xFF81 -> sign-ext");
        tb_expect_reg(5'd26, 32'h00000072,   "lh  half@2 0x0072 -> sin cambio");
        tb_expect_reg(5'd27, 32'h0000FF81,   "lhu half@0 0xFF81 -> zero-ext");
        tb_expect_reg(5'd28, 32'h00000072,   "lhu half@2 0x0072 -> zero-ext");

        // ===========================================================
        // FASE 2: LUI + sb + sh
        // Reset y reprogramar IMEM
        // ===========================================================
        $display("============================================================");
        $display(" FASE 2: LUI / sb / sh");
        $display("============================================================");

        rst = 1'b1;
        tb_load_phase2();
        tb_reset_and_run(30);

        $display("--- Verificaciones Fase 2: LUI ---");
        // lui x1, 0xDEADB -> x1 = 0xDEADB000
        tb_expect_reg(5'd1, 32'hDEADB000, "lui x1, 0xDEADB -> 0xDEADB000");
        // lui x2, 0x00001 -> x2 = 0x00001000
        tb_expect_reg(5'd2, 32'h00001000, "lui x2, 0x00001 -> 0x00001000");
        // add x3, x1, x2 -> 0xDEADB000 + 0x00001000 = 0xDEADC000
        tb_expect_reg(5'd3, 32'hDEADC000, "add x3=x1+x2 -> 0xDEADC000 (LUI sum)");

        $display("--- Verificaciones Fase 2: sb / sh ---");
        // sb x4(=0x5A), 0(x0) luego lbu -> x6 = 0x5A
        tb_expect_reg(5'd4, 32'h0000005A, "addi x4=0x5A");
        tb_expect_reg(5'd6, 32'h0000005A, "sb+lbu: x6=mem[0]=0x5A");
        // sh x5(=0x234), 4(x0) luego lhu -> x7 = 0x0234
        tb_expect_reg(5'd5, 32'h00000234, "addi x5=0x234");
        tb_expect_reg(5'd7, 32'h00000234, "sh+lhu: x7=mem[4..5]=0x0234");

        // ===========================================================
        // FASE 3: JAL + JALR
        // Reset y reprogramar IMEM
        // ===========================================================
        $display("============================================================");
        $display(" FASE 3: JAL / JALR");
        $display("============================================================");

        rst = 1'b1;
        tb_load_phase3();
        tb_reset_and_run(35);

        $display("--- Verificaciones Fase 3: JAL ---");
        // jal x1, +12 en PC=0: x1 = PC+4 = 4
        tb_expect_reg(5'd1, 32'd4,  "JAL link: x1 = PC+4 = 4");
        // addi x2, x0, 99 en target (PC=12)
        tb_expect_reg(5'd2, 32'd99, "JAL target ejecutado: x2=99");

        $display("--- Verificaciones Fase 3: JALR ---");
        // jalr x4, x3(=40), 0 en PC=28: x4 = PC+4 = 32
        tb_expect_reg(5'd4, 32'd32, "JALR link: x4 = PC+4 = 32");
        // addi x5, x0, 42 en target (PC=40)
        tb_expect_reg(5'd5, 32'd42, "JALR target ejecutado: x5=42");

        $display("--- Verificaciones Fase 3: wrong-path flusheado ---");
        // x10 no debe haber sido escrito (ambos wrong-paths flusheados)
        tb_expect_reg(5'd10, 32'd0, "x10=0: wrong-paths de JAL y JALR flusheados");

        // ===========================================================
        // Resumen final
        // ===========================================================
        $display("============================================================");
        if (tb_error_count == 0)
            $display(" TB PASS - %0d errores", tb_error_count);
        else
            $display(" TB FAIL - %0d errores detectados", tb_error_count);
        $display("============================================================");

        $finish;
    end

endmodule

`default_nettype wire
