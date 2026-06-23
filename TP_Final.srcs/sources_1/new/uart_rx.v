`timescale 1ns/1ps

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,

    output reg  [7:0] o_data,
    output reg        o_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT     = CLKS_PER_BIT / 2;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_shift;

    reg rx_sync_0, rx_sync_1;

    always @(posedge clk) begin
        if (rst) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx;
            rx_sync_1 <= rx_sync_0;
        end
    end

    wire rx_in = rx_sync_1;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_count <= 0;
            bit_index <= 0;
            rx_shift  <= 0;
            o_data    <= 0;
            o_valid   <= 1'b0;
        end
        else begin
            o_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_in == 1'b0)
                        state <= S_START;
                end

                S_START: begin
                    if (clk_count == HALF_BIT - 1) begin
                        if (rx_in == 1'b0) begin
                            clk_count <= 0;
                            state     <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        rx_shift[bit_index] <= rx_in;
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
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        o_data    <= rx_shift;
                        o_valid   <= 1'b1;
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
