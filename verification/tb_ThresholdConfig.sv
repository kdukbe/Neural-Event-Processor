`timescale 1ns/1ps

module tb_ThresholdConfig #(
    parameter bit EVENT_DRIVEN = 1'b1,
    parameter realtime SFE_HALF_NS = 62.5,
    parameter integer OFIFO_DEPTH = 8,
    parameter integer WFIFO_DEPTH = 512
);

localparam int CHANNELS      = 16;
localparam int CHANNEL_WIDTH = $clog2(CHANNELS);
integer INPUT_COUNT;
integer EXPECTED_EVENTS;
integer initial_threshold;
integer force_threshold;
localparam int MAX_INPUTS = 500000;
localparam int MAX_RESULTS = 16384;
string data_dir;
string input_path, golden_path, feature_path;
logic [31:0] feature_mem [0:111];
logic [511:0] golden_mem [0:MAX_RESULTS-1];
integer golden_index = 0;
integer threshold_writes = 0;
integer max_pending = 0, max_ofifo = 0, max_wfifo = 0;
integer detected_count = 0, drop_count = 0;
realtime sample_half_ns = 1250.0;
localparam logic [31:0] SRC_ADDR = 32'h0001_0000;
localparam logic [31:0] DST_ADDR = 32'h0002_0000;

logic AXI_CLK       = 1'b0;
logic SAMPLE_CLK    = 1'b0;
logic MAIN_CLK      = 1'b0;
logic SFE_CLK       = 1'b0;
logic AXI_RSTN      = 1'b0;
logic SAMPLE_RSTN   = 1'b0;
logic MAIN_RSTN     = 1'b0;
logic SFE_RSTN      = 1'b0;

always #5     AXI_CLK    = ~AXI_CLK;     // 100 MHz
always #(sample_half_ns) SAMPLE_CLK = ~SAMPLE_CLK;
always #37.5  MAIN_CLK   = ~MAIN_CLK;    // 13.333 MHz
always #(SFE_HALF_NS) SFE_CLK    = ~SFE_CLK;     // 8 MHz

// AXI4-Lite master
logic [31:0] S_AXI_AWADDR;
logic [2:0]  S_AXI_AWPROT;
logic        S_AXI_AWVALID;
wire         S_AXI_AWREADY;
logic [31:0] S_AXI_WDATA;
logic [3:0]  S_AXI_WSTRB;
logic        S_AXI_WVALID;
wire         S_AXI_WREADY;
wire [1:0]   S_AXI_BRESP;
wire         S_AXI_BVALID;
logic        S_AXI_BREADY;
logic [31:0] S_AXI_ARADDR;
logic [2:0]  S_AXI_ARPROT;
logic        S_AXI_ARVALID;
wire         S_AXI_ARREADY;
wire [31:0]  S_AXI_RDATA;
wire [1:0]   S_AXI_RRESP;
wire         S_AXI_RVALID;
logic        S_AXI_RREADY;

// AXI4-Full memory slave
wire [5:0]   M_AXI_AWID;
wire [31:0]  M_AXI_AWADDR;
wire [7:0]   M_AXI_AWLEN;
wire [2:0]   M_AXI_AWSIZE;
wire [1:0]   M_AXI_AWBURST;
wire         M_AXI_AWLOCK;
wire [3:0]   M_AXI_AWCACHE;
wire [2:0]   M_AXI_AWPROT;
wire [3:0]   M_AXI_AWQOS;
wire         M_AXI_AWVALID;
logic        M_AXI_AWREADY;
logic [5:0]  M_AXI_BID;
logic [1:0]  M_AXI_BRESP;
logic        M_AXI_BVALID;
wire         M_AXI_BREADY;
wire [63:0]  M_AXI_WDATA;
wire [7:0]   M_AXI_WSTRB;
wire         M_AXI_WLAST;
wire         M_AXI_WVALID;
logic        M_AXI_WREADY;
wire [5:0]   M_AXI_ARID;
wire [31:0]  M_AXI_ARADDR;
wire [7:0]   M_AXI_ARLEN;
wire [2:0]   M_AXI_ARSIZE;
wire [1:0]   M_AXI_ARBURST;
wire         M_AXI_ARLOCK;
wire [3:0]   M_AXI_ARCACHE;
wire [2:0]   M_AXI_ARPROT;
wire [3:0]   M_AXI_ARQOS;
wire         M_AXI_ARVALID;
logic        M_AXI_ARREADY;
logic [5:0]  M_AXI_RID;
logic [63:0] M_AXI_RDATA;
logic [1:0]  M_AXI_RRESP;
logic        M_AXI_RLAST;
logic        M_AXI_RVALID;
wire         M_AXI_RREADY;
wire         IRQ;

logic [63:0] input_mem  [0:MAX_INPUTS-1];
logic [63:0] output_mem [0:MAX_RESULTS*8-1];
logic [511:0] expected_records[$];

logic        read_active;
integer      read_index;
integer      read_beats_left;
logic        write_active;
logic [1:0]  write_backpressure_count;
integer      write_index;
integer      write_beats_left;
integer      error_count;
integer      write_word_count;

`ifdef USE_1MHZ_TOP
top_1MHz #(
`else
top #(
`endif
    .CHANNELS(CHANNELS),
    .IFIFO_DEPTH(4),
    .WINDOW_DEPTH(64),
    .OFIFO_DEPTH(OFIFO_DEPTH),
    .WFIFO_DEPTH(WFIFO_DEPTH),
    .PENDING_DEPTH(16),
    .IBUFFER_DEPTH(32),
    .OBUFFER_DEPTH(8),
    .THRESHOLD(15000),
    .REFRACTORY(63),
    .POST_SAMPLES(30),
    .EVENT_DRIVEN(EVENT_DRIVEN)
) DUT (
    .AXI_CLK,
    .AXI_RSTN,
    .SAMPLE_CLK,
    .SAMPLE_RSTN,
    .MAIN_CLK,
    .MAIN_RSTN,
    .SFE_CLK,
    .SFE_RSTN,
    .S_AXI_AWADDR,
    .S_AXI_AWPROT,
    .S_AXI_AWVALID,
    .S_AXI_AWREADY,
    .S_AXI_WDATA,
    .S_AXI_WSTRB,
    .S_AXI_WVALID,
    .S_AXI_WREADY,
    .S_AXI_BRESP,
    .S_AXI_BVALID,
    .S_AXI_BREADY,
    .S_AXI_ARADDR,
    .S_AXI_ARPROT,
    .S_AXI_ARVALID,
    .S_AXI_ARREADY,
    .S_AXI_RDATA,
    .S_AXI_RRESP,
    .S_AXI_RVALID,
    .S_AXI_RREADY,
    .M_AXI_AWID,
    .M_AXI_AWADDR,
    .M_AXI_AWLEN,
    .M_AXI_AWSIZE,
    .M_AXI_AWBURST,
    .M_AXI_AWLOCK,
    .M_AXI_AWCACHE,
    .M_AXI_AWPROT,
    .M_AXI_AWQOS,
    .M_AXI_AWVALID,
    .M_AXI_AWREADY,
    .M_AXI_BID,
    .M_AXI_BRESP,
    .M_AXI_BVALID,
    .M_AXI_BREADY,
    .M_AXI_WDATA,
    .M_AXI_WSTRB,
    .M_AXI_WLAST,
    .M_AXI_WVALID,
    .M_AXI_WREADY,
    .M_AXI_ARID,
    .M_AXI_ARADDR,
    .M_AXI_ARLEN,
    .M_AXI_ARSIZE,
    .M_AXI_ARBURST,
    .M_AXI_ARLOCK,
    .M_AXI_ARCACHE,
    .M_AXI_ARPROT,
    .M_AXI_ARQOS,
    .M_AXI_ARVALID,
    .M_AXI_ARREADY,
    .M_AXI_RID,
    .M_AXI_RDATA,
    .M_AXI_RRESP,
    .M_AXI_RLAST,
    .M_AXI_RVALID,
    .M_AXI_RREADY,
    .IRQ
);

// Write one controller register through AXI-Lite.
task automatic axi_lite_write(
    input logic [31:0] address,
    input logic [31:0] data,
    input logic [3:0] strobes = 4'hf,
    input logic [1:0] expected_response = 2'b00
);
    begin
        @(negedge AXI_CLK);
        S_AXI_AWADDR  = address;
        S_AXI_AWVALID = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_AWREADY);
        @(negedge AXI_CLK);
        S_AXI_AWVALID = 1'b0;

        S_AXI_WDATA  = data;
        S_AXI_WSTRB  = strobes;
        S_AXI_WVALID = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_WREADY);
        @(negedge AXI_CLK);
        S_AXI_WVALID = 1'b0;

        S_AXI_BREADY = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_BVALID);
        assert (S_AXI_BRESP == expected_response)
        else begin
            $error("AXI-Lite write response error at address %h", address);
            error_count++;
        end
        @(negedge AXI_CLK);
        S_AXI_BREADY = 1'b0;
    end
endtask

task automatic axi_lite_read(
    input  logic [31:0] address,
    output logic [31:0] data
);
    begin
        @(negedge AXI_CLK);
        S_AXI_ARADDR  = address;
        S_AXI_ARVALID = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_ARREADY);
        @(negedge AXI_CLK);
        S_AXI_ARVALID = 1'b0;

        S_AXI_RREADY = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_RVALID);
        data = S_AXI_RDATA;
        assert (S_AXI_RRESP == 2'b00)
        else begin
            $error("AXI-Lite read response error at address %h", address);
            error_count++;
        end
        @(negedge AXI_CLK);
        S_AXI_RREADY = 1'b0;
    end
endtask

task automatic write_feature(
    input int channel_id,
    input int feature_id,
    input int signed offset,
    input bit enable
);
    logic [31:0] config_word;
    begin
        config_word = 32'd0;
        config_word[0 +: CHANNEL_WIDTH] = channel_id[CHANNEL_WIDTH-1:0];
        config_word[CHANNEL_WIDTH +: 3] = feature_id[2:0];
        config_word[CHANNEL_WIDTH+3 +: 7] = offset[6:0];
        config_word[CHANNEL_WIDTH+10] = enable;
        axi_lite_write(32'h18, config_word);
    end
endtask

// Simple AXI read memory model. One outstanding burst is sufficient for RDMA.
always_comb begin
    M_AXI_ARREADY = !read_active;
    M_AXI_RVALID  = read_active;
    M_AXI_RDATA   = read_active ? input_mem[read_index] : 64'd0;
    M_AXI_RLAST   = read_active && (read_beats_left == 1);
    M_AXI_RRESP   = 2'b00;
    M_AXI_RID     = 6'd0;
end

always_ff @(posedge AXI_CLK or negedge AXI_RSTN) begin
    if (!AXI_RSTN) begin
        read_active     <= 1'b0;
        read_index      <= 0;
        read_beats_left <= 0;
    end else begin
        if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            assert (M_AXI_ARSIZE == 3'b011 && M_AXI_ARBURST == 2'b01)
            else begin
                $error("RDMA issued unsupported AXI read format");
                error_count++;
            end
            read_active     <= 1'b1;
            read_index      <= (M_AXI_ARADDR - SRC_ADDR) >> 3;
            read_beats_left <= M_AXI_ARLEN + 1;
        end else if (M_AXI_RVALID && M_AXI_RREADY) begin
            if (read_beats_left == 1) begin
                read_active     <= 1'b0;
                read_beats_left <= 0;
            end else begin
                read_index      <= read_index + 1;
                read_beats_left <= read_beats_left - 1;
            end
        end
    end
end

// Simple AXI write memory model with periodic backpressure.
always_comb begin
    M_AXI_AWREADY = !write_active && !M_AXI_BVALID;
    M_AXI_WREADY  = write_active && (write_backpressure_count != 2'd0);
    M_AXI_BID     = 6'd0;
    M_AXI_BRESP   = 2'b00;
end

always_ff @(posedge AXI_CLK or negedge AXI_RSTN) begin
    if (!AXI_RSTN) begin
        write_active     <= 1'b0;
        write_backpressure_count <= 2'd0;
        write_index      <= 0;
        write_beats_left <= 0;
        M_AXI_BVALID     <= 1'b0;
        write_word_count <= 0;
    end else begin
        write_backpressure_count <= write_backpressure_count + 1'b1;

        if (M_AXI_AWVALID && M_AXI_AWREADY) begin
            assert (M_AXI_AWSIZE == 3'b011 && M_AXI_AWBURST == 2'b01)
            else begin
                $error("WDMA issued unsupported AXI write format");
                error_count++;
            end
            write_active     <= 1'b1;
            write_index      <= (M_AXI_AWADDR - DST_ADDR) >> 3;
            write_beats_left <= M_AXI_AWLEN + 1;
        end

        if (M_AXI_WVALID && M_AXI_WREADY) begin
            output_mem[write_index] <= M_AXI_WDATA;
            write_word_count <= write_word_count + 1;

            assert (M_AXI_WLAST == (write_beats_left == 1))
            else begin
                $error("WDMA WLAST mismatch at word %0d", write_index);
                error_count++;
            end

            if (write_beats_left == 1) begin
                write_active     <= 1'b0;
                write_beats_left <= 0;
                M_AXI_BVALID     <= 1'b1;
            end else begin
                write_index      <= write_index + 1;
                write_beats_left <= write_beats_left - 1;
            end
        end

        if (M_AXI_BVALID && M_AXI_BREADY)
            M_AXI_BVALID <= 1'b0;
    end
end

// Store the exact SFE record before it enters OBuffer.
always @(negedge SFE_CLK) begin
    if (SFE_RSTN && DUT.core_result_valid) begin
        expected_records.push_back(DUT.core_result_data);
        if (golden_index >= EXPECTED_EVENTS || DUT.core_result_data !== golden_mem[golden_index]) begin
            if (error_count < 8)
                $display("ERROR Golden record=%0d expected=%h actual=%h",golden_index,golden_mem[golden_index],DUT.core_result_data);
            error_count++;
        end
        golden_index++;
    end
end

// Handshake payloads must remain stable while the receiver applies backpressure.
property p_axi_write_stable;
    @(posedge AXI_CLK) disable iff (!AXI_RSTN)
        M_AXI_WVALID && !M_AXI_WREADY |=>
        M_AXI_WVALID && $stable(M_AXI_WDATA) && $stable(M_AXI_WLAST);
endproperty
assert property (p_axi_write_stable)
else begin
    $error("WDMA changed data while stalled");
    error_count++;
end

property p_no_core_loss;
    @(posedge MAIN_CLK) disable iff (!MAIN_RSTN)
        !DUT.core_event_drop;
endproperty
assert property (p_no_core_loss)
else begin
    $error("NeuralCore dropped an event");
    error_count++;
end

generate
    if (EVENT_DRIVEN) begin : g_event_driven_checks
        property p_cfg_wakes_sfe;
            @(posedge SFE_CLK) disable iff (!SFE_RSTN)
                DUT.cfg_valid |-> ##[0:8] DUT.core_sfe_active;
        endproperty
        assert property (p_cfg_wakes_sfe)
        else begin
            $error("Feature configuration did not wake SFE");
            error_count++;
        end

        property p_result_only_while_active;
            @(posedge SFE_CLK) disable iff (!SFE_RSTN)
                DUT.core_result_valid |-> DUT.core_sfe_active;
        endproperty
        assert property (p_result_only_while_active)
        else begin
            $error("SFE result appeared while SFE was disabled");
            error_count++;
        end
    end
endgenerate

always @(posedge MAIN_CLK) begin
    if (MAIN_RSTN && DUT.threshold_valid && DUT.threshold_ready)
        threshold_writes <= threshold_writes+1;
end
always @(negedge MAIN_CLK) begin : fifo_monitor
    integer ofifo_level, wfifo_level;
    if (MAIN_RSTN) begin
        ofifo_level = (DUT.u_NeuralCore.u_MainPath.u_OFIFO.u_OFIFO.wptr -
                       DUT.u_NeuralCore.u_MainPath.u_OFIFO.u_OFIFO.rptr) & (2*OFIFO_DEPTH-1);
        wfifo_level = (DUT.u_NeuralCore.u_MainPath.u_WindowFIFO.u_WindowFIFO.wptr -
                       DUT.u_NeuralCore.u_MainPath.u_WindowFIFO.u_WindowFIFO.rptr) & (2*WFIFO_DEPTH-1);
        if (ofifo_level > max_ofifo) max_ofifo = ofifo_level;
        if (wfifo_level > max_wfifo) max_wfifo = wfifo_level;
        if (DUT.u_NeuralCore.pending_level > max_pending)
            max_pending = DUT.u_NeuralCore.pending_level;
        if (DUT.u_NeuralCore.u_MainPath.sd_valid) detected_count++;
        if (DUT.core_event_drop) drop_count++;
    end
end
property p_threshold_frozen;
    @(posedge MAIN_CLK) disable iff (!MAIN_RSTN)
        DUT.u_NeuralCore.u_MainPath.sample_hs |=> $stable(DUT.u_NeuralCore.u_MainPath.u_SD.threshold_reg);
endproperty
assert property (p_threshold_frozen)
else begin
    $error("Threshold changed during sample processing");
    error_count++;
end

initial begin : run_test
    logic [31:0] status;
    logic [31:0] hw_result_count;
    logic [511:0] written_record;
    integer sample_index;
    integer channel;
    integer feature;
    integer word_index;
    integer timeout;

    if (!$value$plusargs("DATA_DIR=%s",data_dir) ||
        !$value$plusargs("ROWS=%d",INPUT_COUNT) ||
        !$value$plusargs("EVENTS=%d",EXPECTED_EVENTS) ||
        !$value$plusargs("THRESHOLD=%d",initial_threshold))
        $fatal(1,"DATA_DIR, ROWS, EVENTS, THRESHOLD plusargs required");
    if (INPUT_COUNT > MAX_INPUTS || EXPECTED_EVENTS > MAX_RESULTS || EXPECTED_EVENTS <= 0)
        $fatal(1,"Test vectors exceed testbench capacity");
    if ($value$plusargs("SAMPLE_HALF_NS=%f",sample_half_ns)) begin end
    error_count       = 0;
    S_AXI_AWADDR      = 0;
    S_AXI_AWPROT      = 0;
    S_AXI_AWVALID     = 0;
    S_AXI_WDATA       = 0;
    S_AXI_WSTRB       = 0;
    S_AXI_WVALID      = 0;
    S_AXI_BREADY      = 0;
    S_AXI_ARADDR      = 0;
    S_AXI_ARPROT      = 0;
    S_AXI_ARVALID     = 0;
    S_AXI_RREADY      = 0;

    for (int i = 0; i < INPUT_COUNT; i++)
        input_mem[i] = 64'd0;
    for (int i = 0; i < MAX_RESULTS*8; i++)
        output_mem[i] = 64'd0;

    input_path = $sformatf("%s/input.hex",data_dir);
    golden_path = $sformatf("%s/golden.hex",data_dir);
    feature_path = $sformatf("%s/feature.hex",data_dir);
    $readmemh(input_path,input_mem,0,INPUT_COUNT-1);
    $readmemh(golden_path,golden_mem,0,EXPECTED_EVENTS-1);
    $readmemh(feature_path,feature_mem,0,111);
    if ($isunknown(golden_mem[0]) || $isunknown(feature_mem[0]) || input_mem[INPUT_COUNT-1] == 0)
        $fatal(1,"Input/config/Golden file load failed: %s",data_dir);

    repeat (8) @(negedge AXI_CLK);
    AXI_RSTN    = 1'b1;
    SAMPLE_RSTN = 1'b1;
    MAIN_RSTN   = 1'b1;
    SFE_RSTN    = 1'b1;

    // Reject invalid settings without modifying the reset default.
    axi_lite_write(32'h1c, 0, 4'hf, 2'b10);
    axi_lite_write(32'h1c, 123, 4'h3, 2'b10);
    if (DUT.u_NeuralCore.u_MainPath.u_SD.threshold_reg !== 15000)
        $fatal(1,"Invalid configuration changed threshold");

    // A write response means queued, not applied: poll the return path.
    axi_lite_write(32'h1c, initial_threshold);
    status=0;
    timeout=0;
    while (!status[0] && timeout<1000) begin
        axi_lite_read(32'h20,status);
        timeout++;
    end
    if (!status[0] || DUT.u_NeuralCore.u_MainPath.u_SD.threshold_reg !== initial_threshold)
        $fatal(1,"Threshold CDC / application failed");
    for (channel = 0; channel < CHANNELS; channel++) begin
        for (feature = 0; feature < 7; feature++)
            axi_lite_write(32'h18,feature_mem[channel*7+feature]);
    end
    // Wait until the existing feature FIFO has delivered the last setting.
    wait (!DUT.u_controller.u_cfg_fifo.s_nonempty);
    repeat (4) @(posedge AXI_CLK);
    $display("CONFIG_APPLIED threshold=%0d feature_writes=112",initial_threshold);

    axi_lite_write(32'h08, SRC_ADDR);
    axi_lite_write(32'h0c, INPUT_COUNT);
    axi_lite_write(32'h10, DST_ADDR);
    axi_lite_write(32'h00, 32'h1);
    // Settings cannot change after DMA start, including before the first sample.
    axi_lite_write(32'h1c, initial_threshold+1, 4'hf, 2'b10);

    timeout = 0;
    status = 0;
    while (!status[1] && timeout < 100000) begin
        repeat (2000) @(posedge AXI_CLK);
        axi_lite_read(32'h04, status);
        timeout++;
    end

    assert (status[1])
    else begin
        $error("Controller did not finish");
        error_count++;
    end
    assert (!status[2])
    else begin
        $error("Controller reported an error");
        error_count++;
    end

    axi_lite_read(32'h14, hw_result_count);
    assert (hw_result_count == EXPECTED_EVENTS && expected_records.size() == EXPECTED_EVENTS)
    else begin
        $error("Wrong event count: count=%0d queue=%0d",
               hw_result_count, expected_records.size());
        error_count++;
    end

    for (int e=0;e<EXPECTED_EVENTS;e++) begin
        written_record = 512'd0;
        for (word_index=0;word_index<8;word_index++)
            written_record[word_index*64 +: 64]=output_mem[e*8+word_index];
        if (written_record !== golden_mem[e]) begin
            if (error_count<8) $display("ERROR DDR record=%0d",e);
            error_count++;
        end
    end
    if (write_word_count != EXPECTED_EVENTS*8 || golden_index != EXPECTED_EVENTS || threshold_writes != 1)
        error_count++;
    $display("SUMMARY rows=%0d events=%0d golden=%0d errors=%0d threshold=%0d ED=%0d",
        INPUT_COUNT,hw_result_count,EXPECTED_EVENTS,error_count,initial_threshold,EVENT_DRIVEN);
    $display("COUNTERS detected=%0d drop=%0d max_pending=%0d max_ofifo=%0d max_wfifo=%0d threshold_writes=%0d",
        detected_count,drop_count,max_pending,max_ofifo,max_wfifo,threshold_writes);
    if (error_count == 0)
        $display(
            "PASS tb_ThresholdConfig: event_driven=%0d AXI config -> RDMA -> Core -> WDMA, all records match Python",
            EVENT_DRIVEN
        );
    else
        $fatal(1, "FAIL tb_ThresholdConfig errors=%0d", error_count);

    $finish;
end

initial begin
    #2000ms;
    $fatal(1, "FAIL tb_ThresholdConfig global timeout");
end

endmodule
