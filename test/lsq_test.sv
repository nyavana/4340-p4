`timescale 1ns/1ps
`include "verilog/sys_defs.svh"

// Unit testbench for verilog/lsq.sv
//
// Covers:
//   1. Dispatch a load with the operand already ready -> request goes to
//      a stub dcache and the load broadcasts on the load_complete port.
//   2. Dispatch a load with the operand pending -> CDB wakeup -> issue.
//   3. Dispatch a store with operands ready -> store_ready_valid is
//      asserted to the ROB.  Faked rob_commit then releases the store.
//   4. Dispatch interleaved load+store -> verifies FIFO ordering (the
//      store at LSQ tail does not race ahead of the load at the head).
//
// The dcache side is a simple stub that always says hit and returns a
// value derived from the address.  No real caching - we just need to
// validate the LSQ wiring.
//
// Conforms to the `.pass` grep convention:
//   prints "@@@ Passed" on success or "@@@ Incorrect" on any failure.

module lsq_test;

    localparam XLEN  = `XLEN;
    localparam TAG_W = $clog2(`ROB_SZ);

    logic              clock;
    logic              reset;
    logic              flush;

    // dispatch
    logic              dispatch_valid;
    logic              dispatch_is_store;
    logic [TAG_W-1:0]  dispatch_rob_tag;
    logic [1:0]        dispatch_mem_size;
    logic              dispatch_is_signed;
    logic              dispatch_base_ready;
    logic [TAG_W-1:0]  dispatch_base_tag;
    logic [XLEN-1:0]   dispatch_base_value;
    logic              dispatch_data_ready;
    logic [TAG_W-1:0]  dispatch_data_tag;
    logic [XLEN-1:0]   dispatch_data_value;
    logic [XLEN-1:0]   dispatch_imm;

    logic              lsq_full;

    // CDB
    logic              cdb_valid;
    logic [TAG_W-1:0]  cdb_tag;
    logic [XLEN-1:0]   cdb_value;

    // store_ready sideband
    logic              store_ready_valid;
    logic [TAG_W-1:0]  store_ready_tag;

    // rob commit snoop
    logic              rob_commit_valid;
    logic [TAG_W-1:0]  rob_commit_tag;

    // dcache stub interface
    logic              dcache_load;
    logic              dcache_store;
    logic [XLEN-1:0]   dcache_addr;
    logic [63:0]       dcache_wr_data;
    logic [7:0]        dcache_wr_be;
    logic              dcache_done;
    logic [63:0]       dcache_rd_data;

    // load complete
    logic              load_complete_valid;
    logic [TAG_W-1:0]  load_complete_tag;
    logic [XLEN-1:0]   load_complete_value;
    logic              load_complete_accept;

    integer error_count;
    integer test_count;

    // Track the most recent store seen by the dcache stub.
    logic [XLEN-1:0] last_store_addr;
    logic [63:0]     last_store_data;
    logic [7:0]      last_store_be;
    logic            saw_store;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    lsq dut (
        .clock               (clock),
        .reset               (reset),
        .flush               (flush),

        .dispatch_valid      (dispatch_valid),
        .dispatch_is_store   (dispatch_is_store),
        .dispatch_rob_tag    (dispatch_rob_tag),
        .dispatch_mem_size   (dispatch_mem_size),
        .dispatch_is_signed  (dispatch_is_signed),

        .dispatch_base_ready (dispatch_base_ready),
        .dispatch_base_tag   (dispatch_base_tag),
        .dispatch_base_value (dispatch_base_value),

        .dispatch_data_ready (dispatch_data_ready),
        .dispatch_data_tag   (dispatch_data_tag),
        .dispatch_data_value (dispatch_data_value),

        .dispatch_imm        (dispatch_imm),

        .lsq_full            (lsq_full),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),

        .store_ready_valid   (store_ready_valid),
        .store_ready_tag     (store_ready_tag),

        .rob_commit_valid    (rob_commit_valid),
        .rob_commit_tag      (rob_commit_tag),

        .dcache_load         (dcache_load),
        .dcache_store        (dcache_store),
        .dcache_addr         (dcache_addr),
        .dcache_wr_data      (dcache_wr_data),
        .dcache_wr_be        (dcache_wr_be),
        .dcache_done         (dcache_done),
        .dcache_rd_data      (dcache_rd_data),

        .load_complete_valid (load_complete_valid),
        .load_complete_tag   (load_complete_tag),
        .load_complete_value (load_complete_value),
        .load_complete_accept(load_complete_accept)
    );

    // Always accept loads in this stub testbench.
    assign load_complete_accept = load_complete_valid;

    // ----------------------------------------------------------------
    // DCache stub: 1-cycle hits.  Read returns the address replicated
    // into the doubleword.  Stores are silently latched into a single
    // capture register so the test can inspect them.
    // ----------------------------------------------------------------
    assign dcache_done    = dcache_load || dcache_store;
    assign dcache_rd_data = {32'hAA55_AA55, dcache_addr[31:0]};

    always @(posedge clock) begin
        if (reset) begin
            last_store_addr <= '0;
            last_store_data <= '0;
            last_store_be   <= '0;
            saw_store       <= 1'b0;
        end else if (dcache_store) begin
            last_store_addr <= dcache_addr;
            last_store_data <= dcache_wr_data;
            last_store_be   <= dcache_wr_be;
            saw_store       <= 1'b1;
        end
    end

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
            flush               = 1'b0;
            dispatch_valid      = 1'b0;
            dispatch_is_store   = 1'b0;
            dispatch_rob_tag    = '0;
            dispatch_mem_size   = 2'b10; // WORD by default
            dispatch_is_signed  = 1'b0;
            dispatch_base_ready = 1'b0;
            dispatch_base_tag   = '0;
            dispatch_base_value = '0;
            dispatch_data_ready = 1'b0;
            dispatch_data_tag   = '0;
            dispatch_data_value = '0;
            dispatch_imm        = '0;
            cdb_valid           = 1'b0;
            cdb_tag             = '0;
            cdb_value           = '0;
            rob_commit_valid    = 1'b0;
            rob_commit_tag      = '0;
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

    task automatic check_eq;
        input string name;
        input logic  got;
        input logic  exp;
        begin
            if (got !== exp) begin
                $display("ERROR: %s mismatch: got=%b exp=%b @ t=%0t",
                         name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_eq32;
        input string         name;
        input logic [XLEN-1:0] got;
        input logic [XLEN-1:0] exp;
        begin
            if (got !== exp) begin
                $display("ERROR: %s mismatch: got=%h exp=%h @ t=%0t",
                         name, got, exp, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic dispatch_load_ready;
        input logic [TAG_W-1:0] tag;
        input logic [XLEN-1:0]  base;
        input logic [XLEN-1:0]  imm;
        begin
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b0;
            dispatch_rob_tag    = tag;
            dispatch_mem_size   = 2'b10; // WORD
            dispatch_is_signed  = 1'b0;
            dispatch_base_ready = 1'b1;
            dispatch_base_value = base;
            dispatch_data_ready = 1'b1;
            dispatch_data_value = '0;
            dispatch_imm        = imm;
            @(posedge clock);
            #1;
            dispatch_valid = 1'b0;
        end
    endtask

    task automatic dispatch_load_pending;
        input logic [TAG_W-1:0] tag;
        input logic [TAG_W-1:0] base_producer_tag;
        input logic [XLEN-1:0]  imm;
        begin
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b0;
            dispatch_rob_tag    = tag;
            dispatch_mem_size   = 2'b10;
            dispatch_is_signed  = 1'b0;
            dispatch_base_ready = 1'b0;
            dispatch_base_tag   = base_producer_tag;
            dispatch_base_value = '0;
            dispatch_data_ready = 1'b1;
            dispatch_imm        = imm;
            @(posedge clock);
            #1;
            dispatch_valid = 1'b0;
        end
    endtask

    task automatic dispatch_store_ready;
        input logic [TAG_W-1:0] tag;
        input logic [XLEN-1:0]  base;
        input logic [XLEN-1:0]  imm;
        input logic [XLEN-1:0]  data;
        begin
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b1;
            dispatch_rob_tag    = tag;
            dispatch_mem_size   = 2'b10;
            dispatch_is_signed  = 1'b0;
            dispatch_base_ready = 1'b1;
            dispatch_base_value = base;
            dispatch_data_ready = 1'b1;
            dispatch_data_value = data;
            dispatch_imm        = imm;
            @(posedge clock);
            #1;
            dispatch_valid = 1'b0;
        end
    endtask

    task automatic do_cdb;
        input logic [TAG_W-1:0] tag;
        input logic [XLEN-1:0]  val;
        begin
            cdb_valid = 1'b1;
            cdb_tag   = tag;
            cdb_value = val;
            @(posedge clock);
            #1;
            cdb_valid = 1'b0;
        end
    endtask

    task automatic do_commit;
        input logic [TAG_W-1:0] tag;
        begin
            rob_commit_valid = 1'b1;
            rob_commit_tag   = tag;
            @(posedge clock);
            #1;
            rob_commit_valid = 1'b0;
        end
    endtask

    task automatic idle;
        begin
            @(posedge clock);
            #1;
        end
    endtask

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    task automatic test_load_with_ready_operand;
        integer guard;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: load with ready operand -> dcache req -> complete ===", test_count);
            do_reset();

            // dispatch a load: addr = 0x100 + 0x10 = 0x110
            dispatch_load_ready(3'd0, 32'h100, 32'h10);

            // Cycle just after dispatch: LSQ asserts dcache_load with the right addr.
            // The stub asserts dcache_done same cycle, so the LSQ buffers the
            // value internally; load_complete_valid won't fire until next cycle.
            check_eq("dcache_load asserted", dcache_load, 1'b1);
            check_eq32("dcache_addr", dcache_addr, 32'h0000_0110);

            idle();
            // Now the buffered result should appear on the load-complete bus.
            check_eq("load_complete_valid after buffer", load_complete_valid, 1'b1);

            idle();
            check_eq("dcache_load dropped after pop", dcache_load, 1'b0);
        end
    endtask

    task automatic test_load_pending_then_cdb;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: load pending operand woken by CDB ===", test_count);
            do_reset();

            // dispatch a load whose base will be produced by tag 5
            dispatch_load_pending(3'd0, 3'd5, 32'h20);

            // No request yet (operand pending).
            check_eq("dcache_load held off", dcache_load, 1'b0);

            // CDB wakes the operand up with value 0x200.
            do_cdb(3'd5, 32'h200);

            // Now the LSQ has the operand and should issue.
            check_eq("dcache_load fires after CDB", dcache_load, 1'b1);
            check_eq32("dcache_addr after CDB", dcache_addr, 32'h0000_0220);

            idle();
        end
    endtask

    task automatic test_store_waits_for_commit;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: store asserts ready, waits for commit, then drains ===", test_count);
            do_reset();

            dispatch_store_ready(3'd0, 32'h300, 32'h08, 32'hCAFE_BABE);

            // The store should now be at the head with operands ready.
            // store_ready_valid should be asserted to mark the ROB entry ready.
            check_eq("store_ready_valid", store_ready_valid, 1'b1);

            // Without a commit, the store must NOT touch the dcache yet.
            check_eq("dcache_store held until commit", dcache_store, 1'b0);

            // Fake the ROB committing tag 0.
            do_commit(3'd0);

            // After commit the store may go to the dcache.
            check_eq("dcache_store fires after commit", dcache_store, 1'b1);
            check_eq32("dcache_addr (8-byte aligned)", dcache_addr, 32'h0000_0308);

            idle();
        end
    endtask

    task automatic test_flush_clears_queue;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: flush preserves committed store, drops younger entries ===", test_count);
            // Scenario: head is a committed store waiting on its base
            // operand (stalled mid-drain); behind it are two uncommitted
            // entries (a load and a store) that are younger than a
            // mispredicting branch.  After flush, the committed store
            // MUST be preserved (its architectural write cannot be lost),
            // and the younger speculative entries MUST be cleared.  After
            // the store's base wakes, it drains as if nothing happened.
            do_reset();

            // Head: a store that we will mark committed but whose base is
            // pending so it does not fire dcache_store yet.
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b1;
            dispatch_rob_tag    = 3'd0;
            dispatch_mem_size   = 2'b10;
            dispatch_is_signed  = 1'b0;
            dispatch_base_ready = 1'b0;
            dispatch_base_tag   = 3'd7;
            dispatch_base_value = '0;
            dispatch_data_ready = 1'b1;
            dispatch_data_value = 32'hAAAA_0000;
            dispatch_imm        = 32'h0;
            @(posedge clock); #1;
            dispatch_valid = 1'b0;

            // Fake commit of the head store.
            rob_commit_valid = 1'b1;
            rob_commit_tag   = 3'd0;
            @(posedge clock); #1;
            rob_commit_valid = 1'b0;

            // Younger entry 1: a load behind the store, base pending.
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b0;
            dispatch_rob_tag    = 3'd1;
            dispatch_base_ready = 1'b0;
            dispatch_base_tag   = 3'd7;
            dispatch_data_ready = 1'b1;
            dispatch_imm        = 32'h10;
            @(posedge clock); #1;
            dispatch_valid = 1'b0;

            // Younger entry 2: another store, operands pending.
            dispatch_valid      = 1'b1;
            dispatch_is_store   = 1'b1;
            dispatch_rob_tag    = 3'd2;
            dispatch_base_ready = 1'b0;
            dispatch_base_tag   = 3'd7;
            dispatch_data_ready = 1'b0;
            dispatch_data_tag   = 3'd8;
            dispatch_imm        = 32'h20;
            @(posedge clock); #1;
            dispatch_valid = 1'b0;

            // Pulse flush.
            flush = 1'b1;
            @(posedge clock); #1;
            flush = 1'b0;

            // After flush: committed store at head is preserved; younger
            // entries are gone; no spurious dcache traffic.
            check_eq("no dcache_load after flush",  dcache_load,  1'b0);
            check_eq("no dcache_store after flush", dcache_store, 1'b0);
            check_eq("store_ready off (committed)", store_ready_valid, 1'b0);
            check_eq("lsq_full clear after flush",  lsq_full, 1'b0);

            // Wake the preserved store's base via CDB; it should then
            // drain through the stub dcache.
            do_cdb(3'd7, 32'h300);
            check_eq("preserved store fires",   dcache_store, 1'b1);
            check_eq32("preserved store addr",  dcache_addr,  32'h0000_0300);

            idle();
            // After dcache_done, the store pops and the LSQ is empty.  A
            // fresh load should fire immediately.
            dispatch_load_ready(3'd0, 32'h900, 32'h0);
            check_eq("fresh load fires after drain", dcache_load, 1'b1);
            idle();
        end
    endtask

    task automatic test_fifo_order_load_then_store;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: FIFO order - load at head must drain before store ===", test_count);
            do_reset();

            // Load first
            dispatch_load_ready(3'd0, 32'h400, 32'h00);
            // dcache_load should be asserted on the first cycle after dispatch.
            check_eq("dcache_load fires", dcache_load, 1'b1);

            idle();
            // Now the load result is buffered and broadcast.
            check_eq("load complete after buffer", load_complete_valid, 1'b1);

            // Dispatch a store.  The store sits behind the load until the
            // load pops.  Until then dcache_store stays low.
            dispatch_store_ready(3'd1, 32'h500, 32'h00, 32'hDEAD_BEEF);

            // After the load is accepted and pops, the store becomes head.
            // No commit yet -> store_ready asserted but dcache_store not.
            check_eq("store_ready after load pop", store_ready_valid, 1'b1);
            check_eq("store still held until commit", dcache_store, 1'b0);

            // Commit the store.
            do_commit(3'd1);
            check_eq("store fires after commit", dcache_store, 1'b1);
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

        test_load_with_ready_operand();
        test_load_pending_then_cdb();
        test_store_waits_for_commit();
        test_fifo_order_load_then_store();
        test_flush_clears_queue();

        if (error_count == 0)
            $display("\n@@@ Passed");
        else
            $display("\n@@@ Incorrect, error_count = %0d", error_count);

        $finish;
    end

endmodule
