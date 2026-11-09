`timescale 1ns / 1ps

module SD_RB (
    input clk,
    input rst_n,

    input write_en,
    input [31:0] i_timestamp,
    input signed [15:0] i_sample,

    output reg signed [15:0] old_sample,
    output reg signed [15:0] mid_sample,
    output reg [31:0] mid_timestamp,
    output enough_samples
);

    reg [1:0] sample_count;

    assign enough_samples = (sample_count == 2'd2); // valid

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            old_sample    <= 16'd0;
            mid_sample    <= 16'd0;
            mid_timestamp <= 32'd0;
            sample_count  <= 2'd0;
        end else begin
            if (write_en) begin
                old_sample    <= mid_sample;
                mid_sample    <= i_sample;
                mid_timestamp <= i_timestamp;

                if (sample_count < 2'd2)
                    sample_count <= sample_count + 1'b1;
            end
        end
    end

endmodule
