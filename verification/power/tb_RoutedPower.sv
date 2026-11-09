`timescale 1ns/1ps

module tb_RoutedPower #(
`ifdef SFE8
    parameter real SFE_HALF_NS = 62.5
`else
    parameter real SFE_HALF_NS = 500.0
`endif
);

localparam int CHANNELS      = 16;
localparam int CHANNEL_WIDTH = $clog2(CHANNELS);
localparam int MAX_INPUTS = 500000;
integer INPUT_COUNT;
integer EXPECTED_EVENTS;
logic [31:0] initial_threshold;
logic [31:0] feature_mem [0:111];
localparam int MAX_RESULTS   = 16384;
localparam logic [31:0] SRC_ADDR = 32'h0010_0000;
localparam logic [31:0] DST_ADDR = 32'h0080_0000;

logic AXI_CLK       = 1'b0;
logic SAMPLE_CLK    = 1'b0;
logic MAIN_CLK      = 1'b0;
logic SFE_CLK       = 1'b0;
logic AXI_RSTN      = 1'b0;
logic SAMPLE_RSTN   = 1'b0;
logic MAIN_RSTN     = 1'b0;
logic SFE_RSTN      = 1'b0;

always #5     AXI_CLK    = ~AXI_CLK;     // 100 MHz
always #1250  SAMPLE_CLK = ~SAMPLE_CLK;  // 0.4 MHz
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

logic [63:0] input_word;
integer input_fd;
integer input_word_index = 0;
logic [63:0] output_mem [0:MAX_RESULTS*8-1];
logic [511:0] expected_records [0:MAX_RESULTS-1];

logic        read_active;
integer      read_index;
integer      read_beats_left;
logic        write_active;
logic [1:0]  write_backpressure_count;
integer      write_index;
integer      write_beats_left;
integer      error_count;
integer      write_word_count;

BoardIPNetlist DUT (
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
    input logic [31:0] data
);
    begin
        @(negedge AXI_CLK);
        S_AXI_AWADDR  = address;
        S_AXI_AWVALID = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_AWREADY);
        @(negedge AXI_CLK);
        S_AXI_AWVALID = 1'b0;

        S_AXI_WDATA  = data;
        S_AXI_WSTRB  = 4'hf;
        S_AXI_WVALID = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_WREADY);
        @(negedge AXI_CLK);
        S_AXI_WVALID = 1'b0;

        S_AXI_BREADY = 1'b1;
        do @(posedge AXI_CLK); while (!S_AXI_BVALID);
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
        @(negedge AXI_CLK);
        S_AXI_RREADY = 1'b0;
    end
endtask

// Simple AXI read memory model. One outstanding burst is sufficient for RDMA.
always_comb begin
    M_AXI_ARREADY = !read_active;
    M_AXI_RVALID  = read_active;
    M_AXI_RDATA   = read_active ? input_word : 64'd0;
    M_AXI_RLAST   = read_active && (read_beats_left == 1);
    M_AXI_RRESP   = 2'b00;
    M_AXI_RID     = 6'd0;
end

always @(posedge AXI_CLK or negedge AXI_RSTN) begin
    if (!AXI_RSTN) begin
        read_active     <= 1'b0;
        read_index      <= 0;
        read_beats_left <= 0;
    end else begin
        if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            read_active     <= 1'b1;
            read_index      <= (M_AXI_ARADDR - SRC_ADDR) >> 3;
            read_beats_left <= M_AXI_ARLEN + 1;
        end else if (M_AXI_RVALID && M_AXI_RREADY) begin
            input_word_index = input_word_index + 1;
            if (input_word_index < INPUT_COUNT) begin : read_next_hex_word
                logic [63:0] next_word;
                integer fields;
                fields=$fscanf(input_fd,"%h\n",next_word);
                if(fields!=1) $fatal(1,"Missing input word %0d",input_word_index);
                input_word <= next_word;
            end
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
            write_active     <= 1'b1;
            write_index      <= (M_AXI_AWADDR - DST_ADDR) >> 3;
            write_beats_left <= M_AXI_AWLEN + 1;
        end

        if (M_AXI_WVALID && M_AXI_WREADY) begin
            output_mem[write_index] <= M_AXI_WDATA;
            write_word_count <= write_word_count + 1;


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


string data_dir, out_dir;
string input_path, config_path, golden_path;
integer observation_ns;
integer fd, rc, n, j, golden_count, result_fd;
logic [511:0] record;
logic [31:0] status, hw_count;

initial begin
    error_count = 0;
    S_AXI_AWADDR=0; S_AXI_AWPROT=0; S_AXI_AWVALID=0;
    S_AXI_WDATA=0; S_AXI_WSTRB=0; S_AXI_WVALID=0; S_AXI_BREADY=0;
    S_AXI_ARADDR=0; S_AXI_ARPROT=0; S_AXI_ARVALID=0; S_AXI_RREADY=0;
    if (!$value$plusargs("OUT_DIR=%s",out_dir)) out_dir=".";
    if (!$value$plusargs("DATA_DIR=%s",data_dir)) $fatal(1,"DATA_DIR required");
    if (!$value$plusargs("INPUT_COUNT=%d",INPUT_COUNT)) $fatal(1,"INPUT_COUNT required");
    if (!$value$plusargs("EXPECTED_EVENTS=%d",EXPECTED_EVENTS)) $fatal(1,"EXPECTED_EVENTS required");
    if (!$value$plusargs("THRESHOLD=%d",initial_threshold)) $fatal(1,"THRESHOLD required");
    if (!$value$plusargs("OBSERVATION_NS=%d",observation_ns)) $fatal(1,"OBSERVATION_NS required");
    if (INPUT_COUNT<1 || INPUT_COUNT>MAX_INPUTS || EXPECTED_EVENTS<1 ||
        EXPECTED_EVENTS>MAX_RESULTS || initial_threshold==0) $fatal(1,"Invalid case limits");
    input_path={data_dir,"/input.hex"};
    config_path={data_dir,"/feature.hex"};
    golden_path={data_dir,"/golden.hex"};
    for (n=0;n<MAX_RESULTS*8;n++) output_mem[n]=0;
    input_fd=$fopen(input_path,"r");
    if (!input_fd) $fatal(1,"Missing input");
    rc=$fscanf(input_fd,"%h\n",input_word);
    if (rc!=1) $fatal(1,"Invalid first input word");
    $readmemh(config_path,feature_mem,0,111);
    $readmemh(golden_path,expected_records,0,EXPECTED_EVENTS-1);
    golden_count=EXPECTED_EVENTS;

    #10000;
    @(negedge AXI_CLK);
    AXI_RSTN=1; SAMPLE_RSTN=1; MAIN_RSTN=1; SFE_RSTN=1;
    // Match board software: write the shared threshold before samples.
    axi_lite_write(32'h1c,initial_threshold);
    status=0;
    n=0;
    while (!status[0] && n<10000) begin
        axi_lite_read(32'h20,status);
        n++;
    end
    if (!status[0]) $fatal(1,"Threshold application timeout");
    for(n=0;n<112;n++) begin
        if ($isunknown(feature_mem[n])) $fatal(1,"Missing feature setting %0d",n);
        axi_lite_write(32'h18,feature_mem[n]);
    end
    #100000; // Same final configuration wait as the C program.
    axi_lite_write(32'h08,SRC_ADDR);
    axi_lite_write(32'h0c,INPUT_COUNT);
    axi_lite_write(32'h10,DST_ADDR);
    if($time >= 1000000) $fatal(1,"Config exceeded capture start");
    #(1000000-$time);
    axi_lite_write(32'h00,32'h1);
    $display("CAPTURE workload_start_ns=%0t input=%0d", $time,INPUT_COUNT);

    // Identical wall-clock observation interval for both architectures.
    // input.hex already includes the 32 final samples/channel; then fixed drain/idle.
    #(observation_ns);
    axi_lite_read(32'h04,status);
    axi_lite_read(32'h14,hw_count);
    if(status!==32'h2 || hw_count!==golden_count || write_word_count!=golden_count*8 || input_word_index!=INPUT_COUNT)
        $fatal(1,"FAIL status=%h events=%0d words=%0d",status,hw_count,write_word_count);
    result_fd=$fopen({out_dir,"/result_records.hex"},"w");
    if(!result_fd) $fatal(1,"Cannot save results");
    for(n=0;n<golden_count;n++) begin
        record=0;
        for(j=0;j<8;j++) record[j*64+:64]=output_mem[n*8+j];
        $fdisplay(result_fd,"%0128h",record);
        if(record !== expected_records[n]) begin
            if(error_count<10) $display("ERROR record=%0d got=%h expected=%h",n,record,expected_records[n]);
            error_count++;
        end
    end
    $fclose(result_fd);
    $fclose(input_fd);
    if(error_count) $fatal(1,"FAIL Golden mismatches=%0d",error_count);
    $display("PASS routed IP: input=%0d result=%0d Golden=%0d status=%h threshold=%0d",INPUT_COUNT,hw_count,golden_count,status,initial_threshold);
    $finish;
end

initial begin
    forever begin
        #20000000;
        $display("PROGRESS time_ms=%0.1f input_read=%0d output_events=%0d", $realtime/1000000.0,read_index,write_word_count/8);
    end
end

// Unused constants were optimized outside this exported IP boundary.
// Check all complete result records, not undriven unused response bits.
initial begin
    #1300000000;
    $fatal(1,"FAIL global timeout");
end
endmodule
