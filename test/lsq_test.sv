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
    logic [1:0]        cdb_valid;
    logic [TAG_W-1:0]  cdb_tag   [2];
    logic [XLEN-1:0]   cdb_value [2];

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
    logic              dcache_busy;
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
        .dcache_busy         (dcache_busy),
        .dcache_rd_data      (dcache_rd_data),

        .load_complete_valid (load_complete_valid),
        .load_complete_tag   (load_complete_tag),
        .load_complete_value (load_complete_value),
        .load_complete_accept(load_complete_accept)
    );

    // Always accept loads in this stub testbench.
    assign load_complete_accept = load_complete_valid;

    // ----------------------------------------------------------------
    // DCache stub.  Two modes:
    //   stub_mode=0 (default): 1-cycle hits -- dcache_done tracks
    //     dcache_load||dcache_store on the same cycle.
    //   stub_mode=1: manual -- the test drives `manual_dcache_done`
    //     directly so we can test flush/done race scenarios.  In this
    //     mode the stub also honours `manual_stale_done_pulse` which
    //     fires a done pulse even when the LSQ is not asking, to model
    //     a real D-cache completing a request whose owner has been
    //     flushed.
    // ----------------------------------------------------------------
    logic stub_mode;
    logic manual_dcache_done;
    logic manual_stale_done_pulse;
    assign dcache_done    = stub_mode ? (manual_dcache_done || manual_stale_done_pulse)
                                      : (dcache_load || dcache_store);
    assign dcache_rd_data = {32'hAA55_AA55, dcache_addr[31:0]};
    // Stub cache is modelled as "always ready to accept" -- even in
    // manual mode the LSQ's in_flight handshaking still relies on
    // dcache_busy tracking whether a real cache is mid-fetch.  The
    // existing tests pre-date the dcache_busy port and don't care
    // about it, so holding it at 0 preserves the old 1-cycle-hit
    // behaviour.
    assign dcache_busy    = 1'b0;

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
            cdb_valid           = 2'b0;
            cdb_tag[0]          = '0; cdb_tag[1]   = '0;
            cdb_value[0]        = '0; cdb_value[1] = '0;
            rob_commit_valid    = 1'b0;
            rob_commit_tag      = '0;
            stub_mode              = 1'b0;
            manual_dcache_done     = 1'b0;
            manual_stale_done_pulse = 1'b0;
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
            cdb_valid    = 2'b01;
            cdb_tag[0]   = tag; cdb_tag[1]   = '0;
            cdb_value[0] = val; cdb_value[1] = '0;
            @(posedge clock);
            #1;
            cdb_valid = 2'b0;
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
    // 11.3 regression: committed store at head, flush on the same
    // cycle the D-cache finally asserts dcache_done.
    //
    // Two sub-scenarios:
    //   (a) store was `in_flight=1` (miss path): the flush preserves
    //       the committed store.  The dcache_done pulse for the miss
    //       lands on the flush cycle.  The store MUST pop correctly on
    //       that cycle (or the very next cycle) -- the LSQ must not
    //       re-issue the store, because the external cache has already
    //       applied the write.
    //   (b) store was about to release on a hit (in_flight=0): a
    //       flush lands on the same cycle dcache_store+dcache_done
    //       would have popped the entry.  Same requirement: the store
    //       MUST pop and the LSQ must not send a second store to the
    //       cache.
    //
    // Documented invariant: once `committed=1` and the store has been
    // physically handed to the D-cache (either in_flight=1 OR a
    // handshake is in progress), a matching dcache_done MUST pop the
    // entry regardless of flush.  The current head-only policy says a
    // committed store on the flush cycle either drained already or is
    // safely droppable -- this test exists so we notice if the
    // second option silently regresses.
    // ----------------------------------------------------------------
    task automatic test_flush_during_store_miss_done;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: flush + dcache_done on committed in_flight store ===", test_count);
            do_reset();
            stub_mode = 1'b1;

            // Dispatch a committed-store ready to drain.  Operands
            // ready so addr_valid is set at dispatch.
            dispatch_store_ready(3'd0, 32'h300, 32'h08, 32'hCAFE_BABE);

            // Commit it at the ROB so committed=1 gets latched.
            do_commit(3'd0);

            // LSQ should now be asserting dcache_store; stub_mode=1 so
            // done stays low.  This drives the store into in_flight=1
            // on the next cycle.
            check_eq("dcache_store asserted", dcache_store, 1'b1);
            check_eq("dcache_done still low",  dcache_done,  1'b0);
            @(posedge clock); #1;
            // Now in_flight=1.  The store sits waiting for done.
            check_eq("still asking dcache",   dcache_store, 1'b1);

            // Fire flush + manual done on the same cycle.  The LSQ
            // preserves the committed store across flush, but the
            // dcache_done pulse is for THIS store and MUST pop it.
            flush              = 1'b1;
            manual_dcache_done = 1'b1;
            @(posedge clock); #1;
            flush              = 1'b0;
            manual_dcache_done = 1'b0;

            // After the race: LSQ must be empty.  No second dcache_store
            // can fire, or we would double-write architectural memory.
            check_eq("no dcache_store after race", dcache_store, 1'b0);
            check_eq("no dcache_load after race",  dcache_load,  1'b0);
            check_eq("lsq_full clear",             lsq_full,     1'b0);
            if (dut.count !== '0) begin
                $display("ERROR: lsq.count nonzero after flush+done race: %0d", dut.count);
                error_count = error_count + 1;
            end

            stub_mode = 1'b0;
            idle();
        end
    endtask

    task automatic test_flush_during_store_hit;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: flush + same-cycle hit on committed store (in_flight=0) ===", test_count);
            do_reset();
            stub_mode = 1'b1;

            dispatch_store_ready(3'd0, 32'h400, 32'h08, 32'hFEED_FACE);
            do_commit(3'd0);

            // The LSQ is asserting dcache_store and expecting done.  In
            // this scenario the store has NOT yet been seen as in_flight
            // -- fire flush + done on the very first release cycle.
            check_eq("dcache_store asserted pre-race", dcache_store, 1'b1);

            flush              = 1'b1;
            manual_dcache_done = 1'b1;
            @(posedge clock); #1;
            flush              = 1'b0;
            manual_dcache_done = 1'b0;

            check_eq("no dcache_store after race", dcache_store, 1'b0);
            check_eq("no dcache_load after race",  dcache_load,  1'b0);
            if (dut.count !== '0) begin
                $display("ERROR: lsq.count nonzero after flush+hit race: %0d", dut.count);
                error_count = error_count + 1;
            end

            stub_mode = 1'b0;
            idle();
        end
    endtask

    // 11.4 regression: the D-cache keeps servicing an already-flushed
    // request and asserts dcache_done for nobody.  Today
    // `stale_response_pending` is a single bit, so a second flush
    // inside the original miss window can leak a stale response into
    // the new head entry.  Requirement: either the pending count
    // saturates and subsequent stale dones are still swallowed, or
    // the flag is widened to cover every in-flight request at flush
    // time.  This test exercises the back-to-back case.
    task automatic test_two_back_to_back_stale_responses;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: two flushes inside miss window, both stale dones swallowed ===", test_count);
            do_reset();
            stub_mode = 1'b1;

            // Dispatch a load; let it go in_flight.
            dispatch_load_ready(3'd0, 32'h500, 32'h00);
            check_eq("load req fires",       dcache_load,  1'b1);
            @(posedge clock); #1;
            // in_flight should now be set.  XMR probe into the DUT
            // internals does not survive synthesis flattening, so it
            // is guarded for sim-only builds.  The externally-visible
            // checks above/below still run on syn_simv.
`ifndef SYNTH
            if (!dut.entries[dut.head].in_flight) begin
                $display("ERROR: load not in_flight before flush");
                error_count = error_count + 1;
            end
`endif

            // First flush: drops the load but a stale response is
            // pending from the cache.
            flush = 1'b1;
            @(posedge clock); #1;
            flush = 1'b0;

            // Dispatch another load that will also miss (new head).
            dispatch_load_ready(3'd1, 32'h600, 32'h00);
            check_eq("second load fires",    dcache_load,  1'b1);
            @(posedge clock); #1;

            // Second flush: drops this load too.  Now TWO stale
            // responses are outstanding in a real cache.
            flush = 1'b1;
            @(posedge clock); #1;
            flush = 1'b0;

            // Fire the first stale done from the cache.
            manual_stale_done_pulse = 1'b1;
            @(posedge clock); #1;
            manual_stale_done_pulse = 1'b0;

            // Now install a new head load that MUST NOT latch the
            // second stale done.
            dispatch_load_ready(3'd2, 32'h700, 32'h00);
            check_eq("fresh load after stales", dcache_load, 1'b1);

            // Fire the second stale done.  If the one-bit flag is the
            // bug, the fresh load will latch this data.
            manual_stale_done_pulse = 1'b1;
            @(posedge clock); #1;
            manual_stale_done_pulse = 1'b0;

            // The fresh load must still be waiting -- it should not
            // have been popped or had its buffer latched by the stale
            // response.  XMR probe is sim-only.
`ifndef SYNTH
            if (dut.entries[dut.head].load_buf_valid) begin
                $display("ERROR: fresh head load latched a stale dcache_done");
                error_count = error_count + 1;
            end
`endif

            stub_mode = 1'b0;
            idle();
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
        test_flush_during_store_miss_done();
        test_flush_during_store_hit();
        test_two_back_to_back_stale_responses();

        if (error_count == 0)
            $display("\n@@@ Passed");
        else
            $display("\n@@@ Incorrect, error_count = %0d", error_count);

        $finish;
    end

endmodule
