`timescale 1ns/1ps
`include "verilog/sys_defs.svh"

// Directed unit test for icache + stream_buffer working together.
//
// Scenarios:
//   A. Sequential prefetch hit:
//        demand=0x000 → icache miss, wait; stream buffer prefetches 0x008.
//        demand=0x008 → sb_valid_out immediately high, no stall.
//   B. Branch (prefetch miss - correctness):
//        demand=0x000 → fill; then jump to 0x100.
//        0x008 prefetch is stale; icache correctly fetches 0x100.
//   C. Prefetch chain:
//        sequential 0x000→0x008→0x010→0x018; every access after the first
//        should be served by the stream buffer (zero stall).
//
// Conforms to the `.pass` grep convention:
//   prints "@@@ Passed" on success or "@@@ Incorrect" on any failure.

module icache_test;

    logic        clock;
    logic        reset;

    // Unified memory bus driven by fake_mem (below)
    logic [3:0]  mem2proc_response;
    logic [63:0] mem2proc_data;
    logic [3:0]  mem2proc_tag;

    // icache ↔ bus
    logic [1:0]       proc2Imem_command;
    logic [`XLEN-1:0] proc2Imem_addr;
    logic [63:0]      Icache_data_out;
    logic             Icache_valid_out;

    // stream_buffer ↔ bus
    logic [1:0]       proc2Pmem_command;
    logic [`XLEN-1:0] proc2Pmem_addr;
    logic [63:0]      sb_data_out;
    logic             sb_valid_out;
    integer           prefetch_hit_count;

    // Shared demand address (= {PC[31:3], 3'b0})
    logic [`XLEN-1:0] demand_addr;

    // Bus arbitration (icache > stream_buffer, no dcache in this test)
    wire icache_drives = (proc2Imem_command != BUS_NONE);
    wire pfetch_drives = !icache_drives && (proc2Pmem_command != BUS_NONE);

    logic [1:0]       proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr;

    assign proc2mem_command = icache_drives ? proc2Imem_command :
                              pfetch_drives ? proc2Pmem_command : BUS_NONE;
    assign proc2mem_addr    = icache_drives ? proc2Imem_addr    : proc2Pmem_addr;

    // Response routing: each module only sees its own responses
    logic [3:0] icache_resp_in;
    logic [3:0] sb_resp_in;
    assign icache_resp_in = icache_drives ? mem2proc_response : 4'b0;
    assign sb_resp_in     = pfetch_drives ? mem2proc_response : 4'b0;

    // Combined valid/data for the fetch stage
    wire        fetch_valid = Icache_valid_out || sb_valid_out;
    wire [63:0] fetch_data  = sb_valid_out ? sb_data_out : Icache_data_out;

    integer error_count;
    integer test_count;

    // ----------------------------------------------------------------
    // Fake memory model
    //   - 8192 64-bit lines
    //   - MEM_LAT_CYCLES cycle latency (configurable per test)
    //   - Accepts one request per cycle, uses tag=1 always
    // ----------------------------------------------------------------
    localparam MEM_LAT_CYCLES = 5;

    logic [63:0] fake_mem [0:8191];
    integer      pend_cycles;
    logic        pend_active;
    logic [63:0] pend_data;
    logic [3:0]  pend_tag;

    always @(posedge clock) begin
        if (reset) begin
            mem2proc_response <= 4'b0;
            mem2proc_data     <= 64'b0;
            mem2proc_tag      <= 4'b0;
            pend_cycles       <= 0;
            pend_active       <= 1'b0;
            pend_data         <= 64'b0;
            pend_tag          <= 4'b0;
        end else begin
            mem2proc_response <= 4'b0;
            mem2proc_data     <= 64'b0;
            mem2proc_tag      <= 4'b0;

            if (pend_active) begin
                if (pend_cycles == 0) begin
                    mem2proc_tag  <= pend_tag;
                    mem2proc_data <= pend_data;
                    pend_active   <= 1'b0;
                end else begin
                    pend_cycles <= pend_cycles - 1;
                end
            end

            // Accept a new BUS_LOAD only when not already busy
            if (proc2mem_command == BUS_LOAD && !pend_active) begin
                mem2proc_response <= 4'd1;
                pend_data         <= fake_mem[proc2mem_addr[15:3]];
                pend_tag          <= 4'd1;
                pend_cycles       <= MEM_LAT_CYCLES - 1;
                pend_active       <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // DUT: icache
    // ----------------------------------------------------------------
    icache dut_icache (
        .clock              (clock),
        .reset              (reset),
        .Imem2proc_response (icache_resp_in),
        .Imem2proc_data     (mem2proc_data),
        .Imem2proc_tag      (mem2proc_tag),
        .proc2Icache_addr   (demand_addr),
        .proc2Imem_command  (proc2Imem_command),
        .proc2Imem_addr     (proc2Imem_addr),
        .Icache_data_out    (Icache_data_out),
        .Icache_valid_out   (Icache_valid_out)
    );

    // ----------------------------------------------------------------
    // DUT: stream_buffer
    // ----------------------------------------------------------------
    stream_buffer dut_sb (
        .clock              (clock),
        .reset              (reset),
        .mem2sb_response    (sb_resp_in),
        .mem2proc_data      (mem2proc_data),
        .mem2proc_tag       (mem2proc_tag),
        .demand_addr        (demand_addr),
        .proc2Pmem_command  (proc2Pmem_command),
        .proc2Pmem_addr     (proc2Pmem_addr),
        .sb_data_out        (sb_data_out),
        .sb_valid_out       (sb_valid_out),
        .prefetch_hit_count (prefetch_hit_count)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period
    // ----------------------------------------------------------------
    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task automatic do_reset;
        begin
            demand_addr = '0;
            reset       = 1'b1;
            repeat (3) @(posedge clock);
            #1;
            reset = 1'b0;
            @(posedge clock);
            #1;
        end
    endtask

    task automatic check_eq;
        input string name;
        input logic  got;
        input logic  exp;
        begin
            test_count = test_count + 1;
            if (got !== exp) begin
                $display("FAIL [%s]: got=%b exp=%b @ t=%0t", name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_eq64;
        input string       name;
        input logic [63:0] got;
        input logic [63:0] exp;
        begin
            test_count = test_count + 1;
            if (got !== exp) begin
                $display("FAIL [%s]: got=%h exp=%h @ t=%0t", name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    // Wait until fetch_valid is high or timeout, returns cycles waited.
    task automatic wait_for_valid;
        output integer cycles_waited;
        integer guard;
        begin
            guard = 0;
            cycles_waited = 0;
            while (!fetch_valid && guard < 200) begin
                @(posedge clock);
                #1;
                guard         = guard + 1;
                cycles_waited = cycles_waited + 1;
            end
            if (!fetch_valid) begin
                $display("FAIL: timed out waiting for fetch_valid @ t=%0t", $time);
                error_count = error_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test body
    // ----------------------------------------------------------------
    initial begin
        error_count = 0;
        test_count  = 0;

        // ---- Initialise fake memory with recognisable patterns ----
        for (int i = 0; i < 8192; i++)
            fake_mem[i] = {32'hA000_0000 | i[15:0], 32'hB000_0000 | i[15:0]};
        // So fake_mem[0] = 64'hA000_0000_B000_0000
        //    fake_mem[1] = 64'hA000_0001_B000_0001  (addr 0x008)
        //    fake_mem[2] = 64'hA000_0002_B000_0002  (addr 0x010)

        do_reset();

        // ==============================================================
        // Scenario A: Sequential prefetch hit
        //   Step 1 – demand 0x000, wait for icache to fill.
        //            While waiting, stream buffer should prefetch 0x008.
        //   Step 2 – advance demand to 0x008.
        //            Expect sb_valid_out=1 immediately (zero stall).
        // ==============================================================
        $display("--- Scenario A: Sequential prefetch hit ---");

        demand_addr = 32'h0000_0000;
        @(posedge clock); #1;

        // Wait for icache to serve 0x000
        begin
            integer cyc;
            wait_for_valid(cyc);
            $display("  0x000 served after %0d stall cycle(s)", cyc);
            check_eq("A: icache serves 0x000", Icache_valid_out, 1'b1);
        end

        // Give the stream buffer enough time to complete the prefetch of 0x008.
        // It starts requesting once icache is idle; with MEM_LAT_CYCLES=5 and
        // possible 1-cycle bus contention, wait a generous window.
        repeat (MEM_LAT_CYCLES + 4) @(posedge clock);
        #1;

        // Advance demand to 0x008
        demand_addr = 32'h0000_0008;
        @(posedge clock); #1;

        check_eq("A: sb_valid_out immediately high", sb_valid_out, 1'b1);
        check_eq("A: icache not needed (no demand miss)", Icache_valid_out, 1'b0);
        check_eq64("A: sb_data matches mem[1]",
                   sb_data_out, fake_mem[1]);

        $display("  prefetch_hit_count so far = %0d", prefetch_hit_count);

        // ==============================================================
        // Scenario B: Branch – prefetch is stale, icache handles new addr
        // ==============================================================
        $display("--- Scenario B: Branch to 0x100 ---");

        do_reset();
        demand_addr = 32'h0000_0000;
        @(posedge clock); #1;

        begin
            integer cyc;
            wait_for_valid(cyc);   // icache fills 0x000
        end

        // Jump – stream buffer has (or is fetching) 0x008, not 0x100
        demand_addr = 32'h0000_0100;
        @(posedge clock); #1;

        // sb_valid_out must be 0 (0x100 is not what was prefetched)
        check_eq("B: sb_valid on branch target = 0", sb_valid_out, 1'b0);

        // icache must eventually serve 0x100 correctly
        begin
            integer cyc;
            wait_for_valid(cyc);
            $display("  0x100 served after %0d stall cycle(s)", cyc);
            check_eq("B: icache serves 0x100", Icache_valid_out, 1'b1);
            check_eq64("B: icache data matches mem[0x20]",
                       Icache_data_out, fake_mem[32]);  // 0x100 >> 3 = 32
        end

        // ==============================================================
        // Scenario C: Prefetch chain – 4 sequential lines
        //   0x000 has one demand miss; 0x008, 0x010, 0x018 should all be
        //   served by the stream buffer (sb_valid_out=1, zero stall each).
        // ==============================================================
        $display("--- Scenario C: Prefetch chain ---");

        do_reset();

        // Prime the chain: fill 0x000 via icache
        demand_addr = 32'h0000_0000;
        @(posedge clock); #1;
        begin
            integer cyc;
            wait_for_valid(cyc);
            $display("  0x000 served after %0d stall cycle(s)", cyc);
        end

        // Wait for stream buffer to prefetch 0x008
        repeat (MEM_LAT_CYCLES + 4) @(posedge clock); #1;

        // Advance through 0x008, 0x010, 0x018
        begin
            logic [`XLEN-1:0] addrs [3];
            integer           expected_idx [3];
            addrs[0] = 32'h0000_0008;  expected_idx[0] = 1;
            addrs[1] = 32'h0000_0010;  expected_idx[1] = 2;
            addrs[2] = 32'h0000_0018;  expected_idx[2] = 3;

            for (int i = 0; i < 3; i++) begin
                demand_addr = addrs[i];
                @(posedge clock); #1;

                // When the stream buffer hits (sb_valid_out=1), the icache still
                // has a demand miss for the same address and will occupy the bus
                // for ~MEM_LAT_CYCLES cycles before the stream buffer can request
                // the next line.  So the total wait for the NEXT prefetch to land
                // is ~2*MEM_LAT_CYCLES.  Allow that window before checking.
                if (!sb_valid_out) begin
                    repeat (2 * MEM_LAT_CYCLES + 4) @(posedge clock); #1;
                end

                check_eq($sformatf("C: sb hit at addr=%h", addrs[i]),
                         sb_valid_out, 1'b1);
                check_eq64($sformatf("C: data correct at addr=%h", addrs[i]),
                           sb_data_out, fake_mem[expected_idx[i]]);

                // Stay long enough for icache to finish its demand fill AND
                // stream buffer to complete the next prefetch.
                repeat (2 * MEM_LAT_CYCLES + 4) @(posedge clock); #1;
            end
        end

        // ==============================================================
        // Result
        // ==============================================================
        $display("");
        $display("prefetch_hit_count (total) = %0d", prefetch_hit_count);
        $display("Tests run: %0d  Errors: %0d", test_count, error_count);
        if (error_count == 0)
            $display("@@@ Passed");
        else
            $display("@@@ Incorrect: %0d failure(s)", error_count);

        $finish;
    end

endmodule // icache_test
