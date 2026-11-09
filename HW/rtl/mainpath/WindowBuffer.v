`timescale 1ns / 1ps

module WindowBuffer #(
    parameter CHANNELS = 16,
    parameter DEPTH    = 64,
    parameter PRE_SAMPLES = 32
)(
    input clk,
    input rst_n,

    // IFIFO
    input                              i_valid,
    input [$clog2(CHANNELS)-1:0]       i_channel_id,
    input signed [15:0]                i_sample,

    // SD
    output reg [CHANNELS-1:0]          o_detect_ready,
    input [$clog2(CHANNELS)-1:0]       i_event_channel_id,

    // PendingEventQueue
    output [$clog2(DEPTH)-1:0]         o_event_next_addr,

    // WindowController
    input                              i_read,
    output                             o_read_ready,
    input [$clog2(CHANNELS)-1:0]       i_read_channel_id,
    input [$clog2(DEPTH)-1:0]          i_read_base,
    input [$clog2(DEPTH)-1:0]          i_read_index,

    // WindowFIFO
    output reg                         o_valid,
    input                              i_ready,
    output reg                         o_last,
    output reg signed [15:0]           o_sample
);

    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam MEM_ADDR_WIDTH = $clog2(CHANNELS * DEPTH);
    localparam COUNT_WIDTH = $clog2(PRE_SAMPLES + 2);

    reg signed [15:0] window_mem [0:CHANNELS*DEPTH-1];

    reg [ADDR_WIDTH-1:0] write_ptr [0:CHANNELS-1];
    reg [COUNT_WIDTH-1:0] sample_count [0:CHANNELS-1];

    reg [ADDR_WIDTH:0] read_sum; // to calculate read_addr
    reg [ADDR_WIDTH-1:0] read_addr;

    wire [MEM_ADDR_WIDTH-1:0] write_mem_addr;
    wire [MEM_ADDR_WIDTH-1:0] read_mem_addr;

    integer ch;

    assign write_mem_addr = i_channel_id * DEPTH + write_ptr[i_channel_id];
    assign read_mem_addr = i_read_channel_id * DEPTH + read_addr;

    // read adress
    always @(*) begin
        read_sum = {1'b0, i_read_base} + {1'b0, i_read_index};

        if (read_sum >= DEPTH)
            read_addr = read_sum - DEPTH;
        else
            read_addr = read_sum[ADDR_WIDTH-1:0];
    end

    assign o_event_next_addr = write_ptr[i_event_channel_id];

    // sample memory write
    always @(posedge clk) begin
        if (i_valid)
            window_mem[write_mem_addr] <= i_sample;
    end

    // write pointer and SD start condition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_detect_ready <= 0;

            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                write_ptr[ch] <= 0;
                sample_count[ch] <= 0;
            end
        end else if (i_valid) begin
            if (write_ptr[i_channel_id] == DEPTH-1) begin
                write_ptr[i_channel_id] <= 0;
            end else begin
                write_ptr[i_channel_id] <= write_ptr[i_channel_id] + 1'b1;
            end

            // SD detect start 
            if (!o_detect_ready[i_channel_id]) begin
                sample_count[i_channel_id] <= sample_count[i_channel_id] + 1'b1;
                if (sample_count[i_channel_id] == PRE_SAMPLES)
                    o_detect_ready[i_channel_id] <= 1'b1;
            end
        end
    end

    // read sample 
    assign o_read_ready = ~o_valid | i_ready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid     <= 1'b0;
            o_last      <= 1'b0;
            o_sample    <= 16'd0;
        end else begin
            if (i_read && o_read_ready) begin
                o_valid     <= 1'b1;
                o_last      <= (i_read_index == DEPTH-1);
                o_sample    <= window_mem[read_mem_addr];
            end else if (o_valid && i_ready) begin
                o_valid <= 1'b0;
                o_last  <= 1'b0;
            end
        end
    end

endmodule
