`timescale 1ns/1ps
`include "verilog/sys_defs.svh"

// Unit testbench for verilog/dcache.sv
//
// Covers:
//   1.  Load miss -> fetch -> data returned, then a same-line hit
//   2.  Store hit (modify a clean line, mark dirty)
//   3.  Load hit reads back the modified line
//   4.  Sub-word stores (BYTE / HALF / WORD) update only the requested bytes
//   5.  Eviction of a dirty victim triggers a writeback to memory
//
// The testbench fakes a tiny version of mem.sv inline so we don't have to
// pull in the real one.  Conforms to the `.pass` grep convention:
//   prints "@@@ Passed" on success or "@@@ Incorrect" on any failure.

module dcache_test;

    logic         clock;
    logic         reset;

    // To dcache (mimics what pipeline.sv would route)
    logic [3:0]   Dmem2proc_response;
    logic [63:0]  Dmem2proc_data;
    logic [3:0]   Dmem2proc_tag;

    logic         proc_load;
    logic         proc_store;
    logic [`XLEN-1:0] proc_addr;
    logic [63:0]  proc_wr_data;
    logic [7:0]   proc_wr_be;

    logic [63:0]  proc_rd_data;
    logic         proc_done;
    logic         proc_busy;

    logic [1:0]       proc2Dmem_command;
    logic [`XLEN-1:0] proc2Dmem_addr;
    logic [63:0]      proc2Dmem_data;

    integer error_count;
    integer test_count;

    // ----------------------------------------------------------------
    // Tiny inline memory model.
    //
    // - 2048 64-bit lines (16 KB).
    // - Two-cycle latency for loads, modeled by a 1-bit pending counter.
    // - Stores are immediate (matches mem.sv CACHE_MODE behavior).
    // - Always grants tag = 1 if not pending, otherwise no response.
    // ----------------------------------------------------------------
    logic [63:0]  fake_mem [0:2047];
    integer       pending_cycles;
    logic [63:0]  pending_data;
    logic         pending_active;

    always @(posedge clock) begin
        if (reset) begin
            Dmem2proc_response <= 4'b0;
            Dmem2proc_data     <= 64'b0;
            Dmem2proc_tag      <= 4'b0;
            pending_cycles     <= 0;
            pending_data       <= 64'b0;
            pending_active     <= 1'b0;
        end else begin
            Dmem2proc_response <= 4'b0;
            Dmem2proc_tag      <= 4'b0;

            // serve a pending load
            if (pending_active) begin
                if (pending_cycles == 0) begin
                    Dmem2proc_tag  <= 4'd1;
                    Dmem2proc_data <= pending_data;
                    pending_active <= 1'b0;
                end else begin
                    pending_cycles <= pending_cycles - 1;
                end
            end

            // accept a new request
            if (proc2Dmem_command == BUS_LOAD && !pending_active) begin
                Dmem2proc_response <= 4'd1;
                pending_data       <= fake_mem[proc2Dmem_addr[15:3]];
                pending_cycles     <= 1; // 2-cycle latency
                pending_active     <= 1'b1;
            end else if (proc2Dmem_command == BUS_STORE) begin
                Dmem2proc_response <= 4'd1;
                fake_mem[proc2Dmem_addr[15:3]] <= proc2Dmem_data;
            end
        end
    end

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    dcache dut (
        .clock              (clock),
        .reset              (reset),

        .Dmem2proc_response (Dmem2proc_response),
        .Dmem2proc_data     (Dmem2proc_data),
        .Dmem2proc_tag      (Dmem2proc_tag),

        .proc_load          (proc_load),
        .proc_store         (proc_store),
        .proc_addr          (proc_addr),
        .proc_wr_data       (proc_wr_data),
        .proc_wr_be         (proc_wr_be),

        .proc_rd_data       (proc_rd_data),
        .proc_done          (proc_done),
        .proc_busy          (proc_busy),

        .proc2Dmem_command  (proc2Dmem_command),
        .proc2Dmem_addr     (proc2Dmem_addr),
        .proc2Dmem_data     (proc2Dmem_data)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task automatic clear_inputs;
        begin
            proc_load    = 1'b0;
            proc_store   = 1'b0;
            proc_addr    = '0;
            proc_wr_data = '0;
            proc_wr_be   = '0;
        end
    endtask

    task automatic do_reset;
        begin
            clear_inputs();
            reset = 1'b1;
            repeat (3) @(posedge clock);
            #1;
            reset = 1'b0;
            @(posedge clock);
            #1;
        end
    endtask

    task automatic check_eq64;
        input string         name;
        input logic [63:0]   got;
        input logic [63:0]   exp;
        begin
            if (got !== exp) begin
                $display("ERROR: %s mismatch: got=%h exp=%h @ t=%0t",
                         name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_eq;
        input string         name;
        input logic          got;
        input logic          exp;
        begin
            if (got !== exp) begin
                $display("ERROR: %s mismatch: got=%b exp=%b @ t=%0t",
                         name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    // Drive a load and wait for done; return the read data.
    task automatic do_load;
        input  logic [`XLEN-1:0] addr;
        output logic [63:0]      result;
        integer                  guard;
        begin
            proc_load  = 1'b1;
            proc_store = 1'b0;
            proc_addr  = addr;
            proc_wr_be = 8'h0;
            guard = 0;
            #1;
            while (!proc_done && guard < 200) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (!proc_done) begin
                $display("ERROR: load to %h timed out", addr);
                error_count = error_count + 1;
                result = 64'b0;
            end else begin
                result = proc_rd_data;
            end
            @(posedge clock);
            #1;
            proc_load = 1'b0;
        end
    endtask

    // Drive a store and wait for done.
    task automatic do_store;
        input logic [`XLEN-1:0] addr;
        input logic [63:0]      data;
        input logic [7:0]       be;
        integer                 guard;
        begin
            proc_load    = 1'b0;
            proc_store   = 1'b1;
            proc_addr    = addr;
            proc_wr_data = data;
            proc_wr_be   = be;
            guard = 0;
            #1;
            while (!proc_done && guard < 200) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (!proc_done) begin
                $display("ERROR: store to %h timed out", addr);
                error_count = error_count + 1;
            end
            @(posedge clock);
            #1;
            proc_store = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    task automatic test_load_miss_then_hit;
        logic [63:0] r;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: load miss -> fetch -> hit ===", test_count);
            do_reset();
            fake_mem[16'h0040 >> 3] = 64'h1122_3344_5566_7788;

            do_load(32'h0040, r);
            check_eq64("load miss data", r, 64'h1122_3344_5566_7788);

            do_load(32'h0040, r);
            check_eq64("load hit data", r, 64'h1122_3344_5566_7788);
        end
    endtask

    task automatic test_store_hit_load_back;
        logic [63:0] r;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: store hit then load back ===", test_count);
            do_reset();
            fake_mem[16'h0080 >> 3] = 64'h0000_0000_0000_0000;

            // bring the line in via a load (miss -> fill)
            do_load(32'h0080, r);
            check_eq64("init load data", r, 64'h0);

            // store full doubleword
            do_store(32'h0080, 64'hCAFE_BABE_DEAD_BEEF, 8'hff);

            // load back (hit, modified line in cache)
            do_load(32'h0080, r);
            check_eq64("load after store", r, 64'hCAFE_BABE_DEAD_BEEF);
        end
    endtask

    task automatic test_byte_store_only_modifies_one_byte;
        logic [63:0] r;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: BYTE store leaves other bytes intact ===", test_count);
            do_reset();
            fake_mem[16'h00C0 >> 3] = 64'hAAAA_AAAA_AAAA_AAAA;

            do_load(32'h00C0, r);
            check_eq64("init load", r, 64'hAAAA_AAAA_AAAA_AAAA);

            // Write 0x55 into byte 3 of the line.  The dcache uses byte
            // enables, so wr_data must already have 0x55 at the byte-3
            // position (the LSQ would do this replication for us in the
            // real pipeline).
            do_store(32'h00C3, 64'h0000_0000_5500_0000, 8'b0000_1000);

            do_load(32'h00C0, r);
            check_eq64("byte 3 modified, rest intact",
                       r, 64'hAAAA_AAAA_55AA_AAAA);
        end
    endtask

    task automatic test_half_store_only_modifies_two_bytes;
        logic [63:0] r;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: HALF store modifies exactly two bytes ===", test_count);
            do_reset();
            fake_mem[16'h0100 >> 3] = 64'hBBBB_BBBB_BBBB_BBBB;

            do_load(32'h0100, r);
            check_eq64("init load", r, 64'hBBBB_BBBB_BBBB_BBBB);

            // Write 0xCDEF into bytes 4-5 (addr offset 4). The half-word
            // value must already be positioned at bytes 4-5.
            do_store(32'h0104, 64'h0000_CDEF_0000_0000, 8'b0011_0000);

            do_load(32'h0100, r);
            check_eq64("half stored at offset 4",
                       r, 64'hBBBB_CDEF_BBBB_BBBB);
        end
    endtask

    task automatic test_word_store;
        logic [63:0] r;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: WORD store at upper half ===", test_count);
            do_reset();
            fake_mem[16'h0140 >> 3] = 64'hCCCC_CCCC_CCCC_CCCC;

            do_load(32'h0140, r);
            check_eq64("init load", r, 64'hCCCC_CCCC_CCCC_CCCC);

            // Write 0xDEAD_BEEF into the upper word (addr offset 4).
            // Position the word in the upper half of the doubleword.
            do_store(32'h0144, 64'hDEAD_BEEF_0000_0000, 8'b1111_0000);

            do_load(32'h0140, r);
            check_eq64("word stored at upper half",
                       r, 64'hDEAD_BEEF_CCCC_CCCC);
        end
    endtask

    task automatic test_dirty_eviction;
        logic [63:0] r;
        // The dcache index is addr[7:3] (5 bits).  Two addresses share an
        // index when their bits [7:3] match.  Pick 0x0000 and 0x0100 - both
        // have addr[7:3]=0 but different tags (addr[15:8]).
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: dirty eviction triggers writeback ===", test_count);
            do_reset();
            fake_mem[16'h0000 >> 3] = 64'h1111_2222_3333_4444;
            fake_mem[16'h2000 >> 3] = 64'h5555_6666_7777_8888;

            // Bring 0x0000 into the cache, modify it (becomes dirty).
            do_load(32'h0000, r);
            check_eq64("init load 0x0000", r, 64'h1111_2222_3333_4444);
            do_store(32'h0000, 64'hAAAA_BBBB_CCCC_DDDD, 8'hff);

            // Now access 0x2000 which maps to the same index. The dirty
            // line at index 0 must get written back first.
            do_load(32'h2000, r);
            check_eq64("load 0x2000 after eviction", r, 64'h5555_6666_7777_8888);

            // Confirm the eviction actually wrote the new value to memory.
            check_eq64("evicted line in fake_mem",
                       fake_mem[16'h0000 >> 3], 64'hAAAA_BBBB_CCCC_DDDD);
        end
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        error_count = 0;
        test_count  = 0;

        clear_inputs();
        reset = 1'b0;

        test_load_miss_then_hit();
        test_store_hit_load_back();
        test_byte_store_only_modifies_one_byte();
        test_half_store_only_modifies_two_bytes();
        test_word_store();
        test_dirty_eviction();

        if (error_count == 0)
            $display("\n@@@ Passed");
        else
            $display("\n@@@ Incorrect, error_count = %0d", error_count);

        $finish;
    end

endmodule
