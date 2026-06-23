`timescale 1ns/1ps

module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        pc_en,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc
);

    always @(posedge clk) begin
        if (rst)
            pc <= 32'h00000000;
        else if (pc_en)
            pc <= pc_next;
        else
            pc <= pc;
    end

endmodule