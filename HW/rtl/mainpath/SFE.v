`timescale 1ns / 1ps

module SFE #(
    parameter CHANNELS = 16
)(
    input clk,
    input rst_n,

    // Feature configuration: written before event processing.
    input                    i_cfg_valid,
    output                   o_cfg_ready,
    input [$clog2(CHANNELS)-1:0] i_cfg_channel_id,
    input [2:0]              i_cfg_feature_id,
    input signed [6:0]       i_cfg_offset,
    input                    i_cfg_enable,

    // OFIFO
    input               i_event_valid,
    output              i_event_ready,
    input [31:0]        i_event_id,
    input [31:0]        i_event_timestamp,
    input [$clog2(CHANNELS)-1:0] i_event_channel_id,
    input signed [15:0] i_event_sample,

    // WindowFIFO
    input               i_sample_valid,
    output              i_sample_ready,
    input signed [15:0] i_sample,
    // output
    output reg               o_valid,
    output [31:0]            o_id,
    output [31:0]            o_timestamp,
    output [$clog2(CHANNELS)-1:0] o_channel_id,
    output signed [15:0]     o_event_sample,
    output reg [6:0]         o_feature_flag,
    output signed [35:0]     o_feature0,
    output signed [35:0]     o_feature1,
    output signed [35:0]     o_feature2,
    output signed [35:0]     o_feature3,
    output signed [35:0]     o_feature4,
    output signed [35:0]     o_feature5,
    output signed [35:0]     o_feature6,
    output reg [5:0]         o_max_slope_index,
    output                   o_busy
);

localparam FEATURES   = 7;
// |8| + |2| + |6| + |4| = 20, so a signed 21-bit result covers
// every possible sum from four signed 16-bit samples.
localparam FIR_WIDTH  = 21;

localparam IDLE             = 3'd0;
localparam FILTER           = 3'd1;
localparam DRAIN            = 3'd2;
localparam READ_FEATURE_0_1 = 3'd3;
localparam READ_FEATURE_2_3 = 3'd4;
localparam READ_FEATURE_4_5 = 3'd5;
localparam READ_FEATURE_6   = 3'd6;

reg [2:0] state;
reg [5:0] sample_index;

reg [31:0] event_id;
reg [31:0] event_timestamp;
reg [$clog2(CHANNELS)-1:0] event_channel_id;
reg signed [15:0] event_sample;


reg signed [6:0] feature_offset_mem [0:CHANNELS*FEATURES-1];
reg [6:0] feature_flag_mem [0:CHANNELS-1];


reg signed [6:0] active_feature_offset [0:6];
reg [6:0] active_feature_flag;

// FIR result and feature
reg signed [FIR_WIDTH-1:0] filtered_mem [0:63];
reg signed [FIR_WIDTH-1:0] feature_value [0:6];

// Only three previous samples are needed because taps 4~8 are zero.
reg signed [15:0] sample_history [0:2];

reg signed [16:0]   max_slope;
reg [5:0]           max_slope_index;
reg signed [16:0]   next_max_slope;
reg [5:0]           next_max_slope_index;

// Three-stage FIR pipeline.
reg signed [FIR_WIDTH-1:0] fir_product [0:3];
reg signed [FIR_WIDTH-1:0] fir_sum0;
reg signed [FIR_WIDTH-1:0] fir_sum1;

reg       fir_valid1;
reg       fir_valid2;
reg [5:0] fir_index1;
reg [5:0] fir_index2;
reg       fir_last1;
reg       fir_last2;

wire event_hs;
wire sample_hs;
wire cfg_hs;
wire window_done;
wire fir_last_out;
wire signed [16:0] current_slope;
wire signed [FIR_WIDTH-1:0] fir_result;
wire signed [FIR_WIDTH-1:0] fir_input;
wire signed [FIR_WIDTH-1:0] fir_history0;
wire signed [FIR_WIDTH-1:0] fir_history1;
wire signed [FIR_WIDTH-1:0] fir_history2;
reg signed [6:0] selected_feature_offset0;
reg signed [6:0] selected_feature_offset1;
wire signed [7:0] feature_address0;
wire signed [7:0] feature_address1;

integer history_i;
integer filtered_i;
integer result_i;
integer config_i;
integer config_channel;
integer active_i;

assign o_cfg_ready     = (state == IDLE);
assign i_event_ready   = (state == IDLE) && !i_cfg_valid;
assign i_sample_ready  = (state == FILTER);
assign o_busy          = (state != IDLE);

assign cfg_hs     = i_cfg_valid && o_cfg_ready;
assign event_hs   = i_event_valid && i_event_ready;
assign sample_hs  = i_sample_valid && i_sample_ready;
assign window_done = sample_hs && (sample_index == 63);

assign o_id           = event_id;
assign o_timestamp    = event_timestamp;
assign o_channel_id   = event_channel_id;
assign o_event_sample = event_sample;

// Keep only the real 21-bit FIR value and extend it at the output interface.
assign o_feature0 = {{(36-FIR_WIDTH){feature_value[0][FIR_WIDTH-1]}}, feature_value[0]};
assign o_feature1 = {{(36-FIR_WIDTH){feature_value[1][FIR_WIDTH-1]}}, feature_value[1]};
assign o_feature2 = {{(36-FIR_WIDTH){feature_value[2][FIR_WIDTH-1]}}, feature_value[2]};
assign o_feature3 = {{(36-FIR_WIDTH){feature_value[3][FIR_WIDTH-1]}}, feature_value[3]};
assign o_feature4 = {{(36-FIR_WIDTH){feature_value[4][FIR_WIDTH-1]}}, feature_value[4]};
assign o_feature5 = {{(36-FIR_WIDTH){feature_value[5][FIR_WIDTH-1]}}, feature_value[5]};
assign o_feature6 = {{(36-FIR_WIDTH){feature_value[6][FIR_WIDTH-1]}}, feature_value[6]};

// Sign-extend before shifting so no upper bits are lost.
assign fir_input    = {{(FIR_WIDTH-16){i_sample[15]}}, i_sample};
assign fir_history0 = {{(FIR_WIDTH-16){sample_history[0][15]}}, sample_history[0]};
assign fir_history1 = {{(FIR_WIDTH-16){sample_history[1][15]}}, sample_history[1]};
assign fir_history2 = {{(FIR_WIDTH-16){sample_history[2][15]}}, sample_history[2]};

// Two shared address calculations serve all four feature-read cycles.
always @(*) begin
    selected_feature_offset0 = active_feature_offset[0];
    selected_feature_offset1 = active_feature_offset[1];

    case (state)
        READ_FEATURE_2_3: begin
            selected_feature_offset0 = active_feature_offset[2];
            selected_feature_offset1 = active_feature_offset[3];
        end

        READ_FEATURE_4_5: begin
            selected_feature_offset0 = active_feature_offset[4];
            selected_feature_offset1 = active_feature_offset[5];
        end

        READ_FEATURE_6: begin
            selected_feature_offset0 = active_feature_offset[6];
            selected_feature_offset1 = 0;
        end

        default: begin
            selected_feature_offset0 = active_feature_offset[0];
            selected_feature_offset1 = active_feature_offset[1];
        end
    endcase
end

assign feature_address0 = $signed({2'b00, max_slope_index}) + $signed({selected_feature_offset0[6], selected_feature_offset0});
assign feature_address1 = $signed({2'b00, max_slope_index}) + $signed({selected_feature_offset1[6], selected_feature_offset1});

// Store one feature offset and its enable bit on each configuration handshake.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (config_channel = 0; config_channel < CHANNELS; config_channel = config_channel + 1)
            feature_flag_mem[config_channel] <= 0;

        for (config_i = 0; config_i < CHANNELS*FEATURES; config_i = config_i + 1)
            feature_offset_mem[config_i] <= 0;
    end else if (cfg_hs && (i_cfg_feature_id < FEATURES)) begin
        feature_offset_mem[i_cfg_channel_id*FEATURES + i_cfg_feature_id] <= i_cfg_offset;
        feature_flag_mem[i_cfg_channel_id][i_cfg_feature_id]             <= i_cfg_enable;
    end
end

// Keep the selected channel setting stable until the current event is done.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active_feature_flag <= 0;
        for (active_i = 0; active_i < FEATURES; active_i = active_i + 1)
            active_feature_offset[active_i] <= 0;
    end else if (event_hs) begin
        active_feature_flag <= feature_flag_mem[i_event_channel_id];
        for (active_i = 0; active_i < FEATURES; active_i = active_i + 1)
            active_feature_offset[active_i]
                <= feature_offset_mem[i_event_channel_id*FEATURES + active_i];
    end
end

// Stage 1: calculate the four non-zero fixed-coefficient terms.
always @(posedge clk) begin
    if (sample_hs) begin
        fir_product[0] <=  (fir_input     <<< 3);
        fir_product[1] <= -(fir_history0 <<< 1);
        fir_product[2] <= -((fir_history1 <<< 2) + (fir_history1 <<< 1));
        fir_product[3] <= -(fir_history2 <<< 2);
    end
end

// Stage 2: calculate two partial sums.
always @(posedge clk) begin
    if (fir_valid1) begin
        fir_sum0 <= fir_product[0] + fir_product[1];
        fir_sum1 <= fir_product[2] + fir_product[3];
    end
end

// Stage 3: make the final FIR result.
assign fir_result = fir_sum0 + fir_sum1;

// Keep valid, index and last aligned with the pipeline result.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fir_valid1 <= 1'b0;
        fir_valid2 <= 1'b0;
        fir_index1 <= 0;
        fir_index2 <= 0;
        fir_last1  <= 1'b0;
        fir_last2  <= 1'b0;
    end else if (event_hs) begin
        fir_valid1 <= 1'b0;
        fir_valid2 <= 1'b0;
        fir_index1 <= 0;
        fir_index2 <= 0;
        fir_last1  <= 1'b0;
        fir_last2  <= 1'b0;
    end else begin
        fir_valid1 <= sample_hs;
        fir_valid2 <= fir_valid1;

        if (sample_hs) begin
            fir_index1 <= sample_index;
            fir_last1  <= (sample_index == 63);
        end

        if (fir_valid1) begin
            fir_index2 <= fir_index1;
            fir_last2  <= fir_last1;
        end
    end
end

assign fir_last_out = fir_valid2 && fir_last2;

// slope
assign current_slope = {i_sample[15], i_sample} - {sample_history[0][15], sample_history[0]};

// find maximum slope
always @(*) begin
    next_max_slope       = max_slope;
    next_max_slope_index = max_slope_index;

    // start from sample 1
    if ((sample_index == 1) || ((sample_index > 1) && (current_slope > max_slope))) begin
        next_max_slope       = current_slope;
        next_max_slope_index = sample_index;
    end
end

// save maximum slope
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_slope       <= 0;
        max_slope_index <= 0;
    end else if (event_hs) begin
        max_slope       <= 0;
        max_slope_index <= 0;
    end else if (sample_hs) begin
        max_slope       <= next_max_slope;
        max_slope_index <= next_max_slope_index;
    end
end

// FSM
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= IDLE;
        sample_index     <= 0;
        event_id         <= 0;
        event_timestamp  <= 0;
        event_channel_id <= 0;
        event_sample     <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (event_hs) begin
                    state            <= FILTER;
                    sample_index     <= 0;
                    event_id         <= i_event_id;
                    event_timestamp  <= i_event_timestamp;
                    event_channel_id <= i_event_channel_id;
                    event_sample     <= i_event_sample;
                end
            end

            FILTER: begin
                if (sample_hs) begin
                    if (window_done) begin
                        state        <= DRAIN;
                        sample_index <= 0;
                    end else begin
                        sample_index <= sample_index + 1'b1;
                    end
                end
            end

            DRAIN: begin
                if (fir_last_out)
                    state <= READ_FEATURE_0_1;
            end

            READ_FEATURE_0_1: begin
                state <= READ_FEATURE_2_3;
            end

            READ_FEATURE_2_3: begin
                state <= READ_FEATURE_4_5;
            end

            READ_FEATURE_4_5: begin
                state <= READ_FEATURE_6;
            end

            READ_FEATURE_6: begin
                state <= IDLE;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

// save previous samples
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (history_i = 0; history_i < 3; history_i = history_i + 1)
            sample_history[history_i] <= 0;
    end else if (event_hs) begin
        for (history_i = 0; history_i < 3; history_i = history_i + 1)
            sample_history[history_i] <= 0;
    end else if (sample_hs) begin
        for (history_i = 2; history_i > 0; history_i = history_i - 1)
            sample_history[history_i] <= sample_history[history_i-1];

        sample_history[0] <= i_sample;
    end
end

// Save results 
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (filtered_i = 0; filtered_i < 64; filtered_i = filtered_i + 1)
            filtered_mem[filtered_i] <= 0;
    end else if (fir_valid2) begin
        filtered_mem[fir_index2] <= fir_result;
    end
end

// select feature
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        o_valid           <= 1'b0;
        o_feature_flag    <= 0;
        o_max_slope_index <= 0;

        for (result_i = 0; result_i < FEATURES; result_i = result_i + 1)
            feature_value[result_i] <= 0;
    end else begin
        o_valid <= 1'b0;

        if (state == READ_FEATURE_0_1) begin
            if (active_feature_flag[0] && (feature_address0 >= 0) && (feature_address0 < 64))
                feature_value[0] <= filtered_mem[feature_address0];
            else
                feature_value[0] <= 0;

            if (active_feature_flag[1] && (feature_address1 >= 0) && (feature_address1 < 64))
                feature_value[1] <= filtered_mem[feature_address1];
            else
                feature_value[1] <= 0;
        end

        if (state == READ_FEATURE_2_3) begin
            if (active_feature_flag[2] && (feature_address0 >= 0) && (feature_address0 < 64))
                feature_value[2] <= filtered_mem[feature_address0];
            else
                feature_value[2] <= 0;

            if (active_feature_flag[3] && (feature_address1 >= 0) && (feature_address1 < 64))
                feature_value[3] <= filtered_mem[feature_address1];
            else
                feature_value[3] <= 0;
        end

        if (state == READ_FEATURE_4_5) begin
            if (active_feature_flag[4] && (feature_address0 >= 0) && (feature_address0 < 64))
                feature_value[4] <= filtered_mem[feature_address0];
            else
                feature_value[4] <= 0;

            if (active_feature_flag[5] && (feature_address1 >= 0) && (feature_address1 < 64))
                feature_value[5] <= filtered_mem[feature_address1];
            else
                feature_value[5] <= 0;
        end

        // Last read: feature 6, then make the complete result valid.
        if (state == READ_FEATURE_6) begin
            o_valid           <= 1'b1;
            o_feature_flag    <= active_feature_flag;
            o_max_slope_index <= max_slope_index;

            if (active_feature_flag[6] && (feature_address0 >= 0) && (feature_address0 < 64))
                feature_value[6] <= filtered_mem[feature_address0];
            else
                feature_value[6] <= 0;
        end
    end
end

endmodule
