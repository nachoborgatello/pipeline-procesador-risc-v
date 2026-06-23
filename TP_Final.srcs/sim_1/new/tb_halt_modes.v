`timescale 1ns/1ps

module tb_halt_modes;

    reg         clk;
    reg         rst;
    reg         prog_we;
    reg  [31:0] prog_addr;
    reg  [31:0] prog_wdata;
    reg         i_start;
    reg         i_step;
    reg         i_mode;
    wire        o_halted;

    riscv_pipeline_top #(
        .IMEM_DEPTH          (256),
        .IMEM_ADDR_WIDTH     (8),
        .DATA_MEM_ADDR_WIDTH (12)
    ) uut (
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

    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Instrucciones del programa de prueba:
    //   0: addi x1, x0, 5      -> x1 = 5
    //   4: addi x2, x0, 10     -> x2 = 10
    //   8: add  x3, x1, x2     -> x3 = 15
    //  12: HALT
    localparam INSTR_ADDI_X1  = 32'h00500093; // addi x1, x0, 5
    localparam INSTR_ADDI_X2  = 32'h00A00113; // addi x2, x0, 10
    localparam INSTR_ADD_X3   = 32'h002081B3; // add  x3, x1, x2
    localparam INSTR_HALT     = 32'hFFFFFFFF;

    task load_program;
    begin
        prog_we = 1'b1;

        prog_addr = 32'd0;  prog_wdata = INSTR_ADDI_X1; #CLK_PERIOD;
        prog_addr = 32'd4;  prog_wdata = INSTR_ADDI_X2; #CLK_PERIOD;
        prog_addr = 32'd8;  prog_wdata = INSTR_ADD_X3;  #CLK_PERIOD;
        prog_addr = 32'd12; prog_wdata = INSTR_HALT;    #CLK_PERIOD;

        prog_we = 1'b0;
    end
    endtask

    task reset_pipeline;
    begin
        rst = 1'b1;
        #(CLK_PERIOD * 2);
        rst = 1'b0;
        #CLK_PERIOD;
    end
    endtask

    task pulse_start;
    begin
        i_start = 1'b1;
        #CLK_PERIOD;
        i_start = 1'b0;
    end
    endtask

    task pulse_step;
    begin
        i_step = 1'b1;
        #CLK_PERIOD;
        i_step = 1'b0;
    end
    endtask

    integer cycle_count;
    integer i;

    initial begin
        clk       = 0;
        rst       = 0;
        prog_we   = 0;
        prog_addr = 0;
        prog_wdata= 0;
        i_start   = 0;
        i_step    = 0;
        i_mode    = 0;

        // ========================================================
        // TEST 1: Modo continuo
        // ========================================================
        $display("============================================");
        $display("TEST 1: Modo continuo");
        $display("============================================");

        reset_pipeline;
        load_program;
        reset_pipeline;

        i_mode = 1'b0; // continuo
        pulse_start;

        cycle_count = 0;
        while (!o_halted && cycle_count < 50) begin
            #CLK_PERIOD;
            cycle_count = cycle_count + 1;
        end

        $display("Pipeline se detuvo despues de %0d ciclos", cycle_count);
        $display("o_halted = %b", o_halted);

        // Verificar registros via acceso jerárquico
        $display("x1 = %0d (esperado: 5)",  uut.u_id_stage.u_reg_file.regs[1]);
        $display("x2 = %0d (esperado: 10)", uut.u_id_stage.u_reg_file.regs[2]);
        $display("x3 = %0d (esperado: 15)", uut.u_id_stage.u_reg_file.regs[3]);

        if (uut.u_id_stage.u_reg_file.regs[1] !== 32'd5)
            $display("ERROR: x1 != 5");
        if (uut.u_id_stage.u_reg_file.regs[2] !== 32'd10)
            $display("ERROR: x2 != 10");
        if (uut.u_id_stage.u_reg_file.regs[3] !== 32'd15)
            $display("ERROR: x3 != 15");
        if (!o_halted)
            $display("ERROR: pipeline no se detuvo");

        $display("");

        // ========================================================
        // TEST 2: Modo paso a paso
        // ========================================================
        $display("============================================");
        $display("TEST 2: Modo paso a paso");
        $display("============================================");

        reset_pipeline;
        load_program;
        reset_pipeline;

        i_mode = 1'b1; // paso a paso

        // Dar start para arrancar (primer ciclo)
        pulse_start;
        // En modo step, running se pone en 1 con start,
        // pero al siguiente ciclo se apaga si i_step=0.
        // Entonces start ejecuta 1 ciclo.

        cycle_count = 1;
        $display("Ciclo %0d: PC = 0x%08X", cycle_count, uut.if_pc);

        // Avanzar paso a paso hasta que se detenga
        while (!o_halted && cycle_count < 50) begin
            #(CLK_PERIOD * 2); // esperar a que running vuelva a 0
            pulse_step;
            cycle_count = cycle_count + 1;
            $display("Ciclo %0d: PC = 0x%08X, halted = %b", cycle_count, uut.if_pc, o_halted);
        end

        $display("Pipeline se detuvo despues de %0d pasos", cycle_count);
        $display("o_halted = %b", o_halted);

        $display("x1 = %0d (esperado: 5)",  uut.u_id_stage.u_reg_file.regs[1]);
        $display("x2 = %0d (esperado: 10)", uut.u_id_stage.u_reg_file.regs[2]);
        $display("x3 = %0d (esperado: 15)", uut.u_id_stage.u_reg_file.regs[3]);

        if (uut.u_id_stage.u_reg_file.regs[1] !== 32'd5)
            $display("ERROR: x1 != 5");
        if (uut.u_id_stage.u_reg_file.regs[2] !== 32'd10)
            $display("ERROR: x2 != 10");
        if (uut.u_id_stage.u_reg_file.regs[3] !== 32'd15)
            $display("ERROR: x3 != 15");
        if (!o_halted)
            $display("ERROR: pipeline no se detuvo");

        $display("");
        $display("============================================");
        $display("TESTS COMPLETADOS");
        $display("============================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
