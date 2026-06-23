`timescale 1ns/1ps

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] i_data,
    input  wire       i_valid,

    output reg        o_tx,
    output reg        o_busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  tx_shift;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_count <= 0;
            bit_index <= 0;
            tx_shift  <= 0;
            o_tx      <= 1'b1;
            o_busy    <= 1'b0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    o_tx   <= 1'b1;
                    o_busy <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (i_valid) begin
                        tx_shift <= i_data;
                        o_busy   <= 1'b1;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    o_tx <= 1'b0;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state     <= S_DATA;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_DATA: begin
                    o_tx <= tx_shift[bit_index];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_index == 3'd7) begin
                            bit_index <= 0;
                            state     <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP: begin
                    o_tx <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state     <= S_IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
