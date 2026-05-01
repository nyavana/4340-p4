`timescale 1ns/1ps
`include "sys_defs.svh"

// Unit testbench for verilog/rob.sv
//
// Covers:
//   1.  Basic dispatch -> CDB complete -> commit
//   2.  In-order commit despite out-of-order completion
//   3.  RAT query returns pending + tag for a pending write
//   4.  Same-cycle CDB bypass in RAT query
//   5.  RAT clears on commit when still the latest writer
//   6.  RAT stale-clear protection (younger writer has already renamed)
//   7.  x0 guard (RAT never tracks x0; commit of x0 inst is harmless)
//   8.  Flush clears everything
//   9.  Full detection
//  10.  Wraparound
//
// Conforms to the `.pass` grep convention:
//   prints "@@@ Passed" on success or "@@@ Incorrect" on any failure.
module rob_test;

  localparam ROB_SIZE = `ROB_SZ;
  localparam XLEN     = `XLEN;
  localparam TAG_W    = $clog2(`ROB_SZ);

  logic                 clock;
  logic                 reset;
  logic                 flush;

  // dispatch
  logic [1:0]           dispatch_valid;
  logic [4:0]           dispatch_dest_reg        [2];
  logic [XLEN-1:0]      dispatch_NPC             [2];
  logic [XLEN-1:0]      dispatch_PC              [2];
  logic [1:0]           dispatch_halt;
  logic [1:0]           dispatch_illegal;
  logic [1:0]           dispatch_is_branch;
  logic [1:0]           dispatch_is_uncond_branch;
  logic [1:0]           dispatch_is_store;
  logic [1:0]           dispatch_predicted_taken;
  logic [XLEN-1:0]      dispatch_predicted_target [2];

  logic                 rob_full;
  logic                 rob_almost_full;
  logic [TAG_W-1:0]     dispatch_tag             [2];

  // cdb
  logic [1:0]           cdb_valid;
  logic [TAG_W-1:0]     cdb_tag           [2];
  logic [XLEN-1:0]      cdb_value         [2];
  logic [1:0]           cdb_take_branch;
  logic [XLEN-1:0]      cdb_branch_target [2];

  // store-done sideband
  logic [1:0]           store_done_valid;
  logic [TAG_W-1:0]     store_done_tag    [2];

  // commit
  logic [1:0]           commit_valid;
  logic [TAG_W-1:0]     commit_tag           [2];
  logic [1:0]           commit_is_store;
  logic [4:0]           commit_dest_reg      [2];
  logic [XLEN-1:0]      commit_value         [2];
  logic [XLEN-1:0]      commit_NPC           [2];
  logic [1:0]           commit_halt;
  logic [1:0]           commit_illegal;
  logic [1:0]           commit_is_branch;
  logic [1:0]           commit_take_branch;
  logic [XLEN-1:0]      commit_branch_target [2];
  logic [1:0]           commit_is_uncond_branch;
  logic [XLEN-1:0]      commit_branch_PC     [2];
  logic                 mispredict_valid;
  logic [XLEN-1:0]      mispredict_target;

  // rat queries
  logic [4:0]           query1_arch_reg;
  logic                 query1_pending;
  logic                 query1_ready;
  logic [TAG_W-1:0]     query1_tag;
  logic [XLEN-1:0]      query1_value;

  logic [4:0]           query2_arch_reg;
  logic                 query2_pending;
  logic                 query2_ready;
  logic [TAG_W-1:0]     query2_tag;
  logic [XLEN-1:0]      query2_value;

  integer error_count;
  integer test_count;

  // In synth flow, instantiate the rob_svsim wrapper which preserves the
  // unpacked-array port interface and repacks into the .vg netlist's
  // packed-bus ports via {>>{ }}.  The wrapper is `ifndef SYNTHESIS guarded.
`ifdef SYNTH
  rob_svsim dut (
`else
  rob dut (
`endif
    .clock(clock),
    .reset(reset),
    .flush(flush),

    .dispatch_valid(dispatch_valid),
    .dispatch_dest_reg(dispatch_dest_reg),
    .dispatch_NPC(dispatch_NPC),
    .dispatch_PC(dispatch_PC),
    .dispatch_halt(dispatch_halt),
    .dispatch_illegal(dispatch_illegal),
    .dispatch_is_branch(dispatch_is_branch),
    .dispatch_is_uncond_branch(dispatch_is_uncond_branch),
    .dispatch_is_store(dispatch_is_store),
    .dispatch_predicted_taken(dispatch_predicted_taken),
    .dispatch_predicted_target(dispatch_predicted_target),

    .rob_full(rob_full),
    .rob_almost_full(rob_almost_full),
    .dispatch_tag(dispatch_tag),

    .cdb_valid(cdb_valid),
    .cdb_tag(cdb_tag),
    .cdb_value(cdb_value),
    .cdb_take_branch(cdb_take_branch),
    .cdb_branch_target(cdb_branch_target),

    .store_done_valid(store_done_valid),
    .store_done_tag(store_done_tag),

    .commit_valid(commit_valid),
    .commit_tag(commit_tag),
    .commit_is_store(commit_is_store),
    .commit_dest_reg(commit_dest_reg),
    .commit_value(commit_value),
    .commit_NPC(commit_NPC),
    .commit_halt(commit_halt),
    .commit_illegal(commit_illegal),
    .commit_is_branch(commit_is_branch),
    .commit_take_branch(commit_take_branch),
    .commit_branch_target(commit_branch_target),
    .commit_is_uncond_branch(commit_is_uncond_branch),
    .commit_branch_PC(commit_branch_PC),
    .mispredict_valid(mispredict_valid),
    .mispredict_target(mispredict_target),

    .query1_arch_reg(query1_arch_reg),
    .query1_pending(query1_pending),
    .query1_ready(query1_ready),
    .query1_tag(query1_tag),
    .query1_value(query1_value),

    .query2_arch_reg(query2_arch_reg),
    .query2_pending(query2_pending),
    .query2_ready(query2_ready),
    .query2_tag(query2_tag),
    .query2_value(query2_value)
  );

  // ============================================================
  // clock
  // ============================================================
  initial begin
    clock = 1'b0;
    forever #5 clock = ~clock;
  end

  // ============================================================
  // helpers
  // ============================================================
  task automatic clear_inputs;
    begin
      flush                        = 1'b0;

      dispatch_valid               = 2'b0;
      dispatch_dest_reg[0]         = 5'd0;       dispatch_dest_reg[1]         = 5'd0;
      dispatch_NPC[0]              = '0;          dispatch_NPC[1]              = '0;
      dispatch_PC[0]               = '0;          dispatch_PC[1]               = '0;
      dispatch_halt                = 2'b0;
      dispatch_illegal             = 2'b0;
      dispatch_is_branch           = 2'b0;
      dispatch_is_uncond_branch    = 2'b0;
      dispatch_is_store            = 2'b0;
      dispatch_predicted_taken     = 2'b0;
      dispatch_predicted_target[0] = '0;          dispatch_predicted_target[1] = '0;

      cdb_valid                    = 2'b0;
      cdb_tag[0]                   = '0;          cdb_tag[1]          = '0;
      cdb_value[0]                 = '0;          cdb_value[1]        = '0;
      cdb_take_branch              = 2'b0;
      cdb_branch_target[0]         = '0;          cdb_branch_target[1] = '0;

      store_done_valid             = 2'b0;
      store_done_tag[0]            = '0;          store_done_tag[1]   = '0;

      query1_arch_reg              = 5'd0;
      query2_arch_reg              = 5'd0;
    end
  endtask

  task automatic do_reset;
    begin
      clear_inputs();
      reset = 1'b1;
      repeat (2) @(posedge clock);
      #1;
      reset = 1'b0;
      @(posedge clock);
      #1;
    end
  endtask

  task automatic check_equal;
    input string name;
    input logic [255:0] got;
    input logic [255:0] exp;
    begin
      if (got !== exp) begin
        $display("ERROR: %s mismatch, got=%0h exp=%0h @ t=%0t",
                 name, got, exp, $time);
        error_count = error_count + 1;
      end
    end
  endtask

  // Dispatch one instruction, holding the inputs into the next posedge.
  // Caller is responsible for advancing the clock and calling stop_dispatch.
  task automatic dispatch_drive;
    input logic [4:0]      dest;
    input logic [XLEN-1:0] npc;
    input logic            is_branch;
    input logic            halt;
    input logic            illegal;
    begin
      dispatch_valid[0]     = 1'b1; dispatch_valid[1]    = 1'b0;
      dispatch_dest_reg[0]  = dest; dispatch_dest_reg[1] = 5'd0;
      dispatch_NPC[0]       = npc;  dispatch_NPC[1]      = '0;
      dispatch_PC[0]        = npc - 4; dispatch_PC[1]    = '0;
      dispatch_is_branch[0] = is_branch; dispatch_is_branch[1] = 1'b0;
      dispatch_halt[0]      = halt;   dispatch_halt[1]    = 1'b0;
      dispatch_illegal[0]   = illegal; dispatch_illegal[1] = 1'b0;
    end
  endtask

  task automatic stop_dispatch;
    begin
      dispatch_valid               = 2'b0;
      dispatch_dest_reg[0]         = 5'd0;      dispatch_dest_reg[1]         = 5'd0;
      dispatch_NPC[0]              = '0;         dispatch_NPC[1]              = '0;
      dispatch_PC[0]               = '0;         dispatch_PC[1]               = '0;
      dispatch_is_branch           = 2'b0;
      dispatch_is_uncond_branch    = 2'b0;
      dispatch_halt                = 2'b0;
      dispatch_illegal             = 2'b0;
      dispatch_predicted_taken     = 2'b0;
      dispatch_predicted_target[0] = '0;         dispatch_predicted_target[1] = '0;
    end
  endtask

  task automatic drive_cdb;
    input logic [TAG_W-1:0] tag;
    input logic [XLEN-1:0]  val;
    input logic             tk;
    input logic [XLEN-1:0]  tgt;
    begin
      cdb_valid            = 2'b01;
      cdb_tag[0]           = tag;  cdb_tag[1]           = '0;
      cdb_value[0]         = val;  cdb_value[1]         = '0;
      cdb_take_branch[0]   = tk;   cdb_take_branch[1]   = 1'b0;
      cdb_branch_target[0] = tgt;  cdb_branch_target[1] = '0;
    end
  endtask

  task automatic stop_cdb;
    begin
      cdb_valid            = 2'b0;
      cdb_tag[0]           = '0;  cdb_tag[1]           = '0;
      cdb_value[0]         = '0;  cdb_value[1]         = '0;
      cdb_take_branch      = 2'b0;
      cdb_branch_target[0] = '0;  cdb_branch_target[1] = '0;
    end
  endtask

  // Dispatch exactly one instruction over one clock edge.
  // Returns the captured dispatch_tag via 'out_tag' (read before the edge).
  task automatic dispatch_one;
    input  logic [4:0]      dest;
    input  logic [XLEN-1:0] npc;
    input  logic            is_branch;
    output logic [TAG_W-1:0] out_tag;
    begin
      dispatch_drive(dest, npc, is_branch, 1'b0, 1'b0);
      #1;
      out_tag = dispatch_tag[0];
      @(posedge clock);
      #1;
      stop_dispatch();
    end
  endtask

  // Dispatch a branch instruction carrying a prediction over one posedge.
  task automatic dispatch_branch_pred;
    input  logic [4:0]      dest;
    input  logic [XLEN-1:0] pc;
    input  logic            is_uncond;
    input  logic            pred_taken;
    input  logic [XLEN-1:0] pred_target;
    output logic [TAG_W-1:0] out_tag;
    begin
      dispatch_valid[0]            = 1'b1;       dispatch_valid[1]            = 1'b0;
      dispatch_dest_reg[0]         = dest;        dispatch_dest_reg[1]         = 5'd0;
      dispatch_NPC[0]              = pc + 4;      dispatch_NPC[1]              = '0;
      dispatch_PC[0]               = pc;          dispatch_PC[1]               = '0;
      dispatch_is_branch[0]        = 1'b1;        dispatch_is_branch[1]        = 1'b0;
      dispatch_is_uncond_branch[0] = is_uncond;   dispatch_is_uncond_branch[1] = 1'b0;
      dispatch_halt                = 2'b0;
      dispatch_illegal             = 2'b0;
      dispatch_predicted_taken[0]  = pred_taken;  dispatch_predicted_taken[1]  = 1'b0;
      dispatch_predicted_target[0] = pred_target; dispatch_predicted_target[1] = '0;
      #1;
      out_tag = dispatch_tag[0];
      @(posedge clock);
      #1;
      stop_dispatch();
    end
  endtask

  // Drive CDB with a branch resolution for one cycle.
  task automatic complete_cdb_branch;
    input logic [TAG_W-1:0] tag;
    input logic             actual_taken;
    input logic [XLEN-1:0]  actual_target;
    begin
      drive_cdb(tag, 32'h0, actual_taken, actual_target);
      @(posedge clock);
      #1;
      stop_cdb();
    end
  endtask

  // Pulse CDB for one cycle.
  task automatic complete_cdb;
    input logic [TAG_W-1:0] tag;
    input logic [XLEN-1:0]  val;
    begin
      drive_cdb(tag, val, 1'b0, '0);
      @(posedge clock);
      #1;
      stop_cdb();
    end
  endtask

  // Advance one cycle with all inputs idle (e.g. to let head commit).
  task automatic idle_cycle;
    begin
      @(posedge clock);
      #1;
    end
  endtask

  // Query one architectural register (combinational read).
  task automatic query_reg;
    input  logic [4:0]      r;
    output logic            pend;
    output logic            rdy;
    output logic [TAG_W-1:0] tg;
    output logic [XLEN-1:0]  vl;
    begin
      query1_arch_reg = r;
      #1;
      pend = query1_pending;
      rdy  = query1_ready;
      tg   = query1_tag;
      vl   = query1_value;
    end
  endtask

  // ============================================================
  // tests
  // ============================================================

  task automatic test_basic_dispatch_complete_commit;
    logic [TAG_W-1:0] t0;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: basic dispatch -> CDB complete -> commit ===", test_count);

      do_reset();

      dispatch_one(5'd5, 32'h0000_1004, 1'b0, t0);

      // head should not commit yet (entry not ready)
      check_equal("commit_valid pre-complete", commit_valid[0], 1'b0);

      // Drive CDB in the next cycle; commit should become visible combinationally
      // *after* the CDB write latches (i.e. on the cycle after).
      complete_cdb(t0, 32'hDEAD_BEEF);

      // Now the entry is ready: check commit outputs before the head advances.
      check_equal("commit_valid",        commit_valid[0], 1'b1);
      check_equal("commit_dest_reg",     commit_dest_reg[0], 5'd5);
      check_equal("commit_value",        commit_value[0],    32'hDEAD_BEEF);
      check_equal("commit_NPC",          commit_NPC[0],      32'h0000_1004);

      // Let it retire.
      idle_cycle();
      check_equal("commit_valid after retire", commit_valid[0], 1'b0);
    end
  endtask

  task automatic test_in_order_commit;
    logic [TAG_W-1:0] t0, t1, t2;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: in-order commit despite OoO complete ===", test_count);

      do_reset();

      dispatch_one(5'd10, 32'h100, 1'b0, t0);
      dispatch_one(5'd11, 32'h104, 1'b0, t1);
      dispatch_one(5'd12, 32'h108, 1'b0, t2);

      // Complete tag 2 first.
      complete_cdb(t2, 32'h2222_2222);
      check_equal("no commit after t2 only", commit_valid[0], 1'b0);

      // Complete tag 1 next.
      complete_cdb(t1, 32'h1111_1111);
      check_equal("no commit after t1 too", commit_valid[0], 1'b0);

      // Complete tag 0 last - now head should retire.
      complete_cdb(t0, 32'h0000_0000);

      // 2-way ROB: t0 and t1 both ready, commit together in same cycle
      check_equal("commit t0 valid", commit_valid[0],    1'b1);
      check_equal("commit t0 dest",  commit_dest_reg[0], 5'd10);
      check_equal("commit t0 value", commit_value[0],    32'h0000_0000);
      check_equal("commit t1 valid", commit_valid[1],    1'b1);
      check_equal("commit t1 dest",  commit_dest_reg[1], 5'd11);
      check_equal("commit t1 value", commit_value[1],    32'h1111_1111);
      idle_cycle();

      // t2 commits next cycle
      check_equal("commit t2 valid", commit_valid[0],    1'b1);
      check_equal("commit t2 dest",  commit_dest_reg[0], 5'd12);
      check_equal("commit t2 value", commit_value[0],    32'h2222_2222);
      idle_cycle();

      check_equal("no commit after drain", commit_valid[0], 1'b0);
    end
  endtask

  task automatic test_rat_pending_tag;
    logic [TAG_W-1:0] t0;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: RAT returns pending + tag for in-flight write ===", test_count);

      do_reset();

      dispatch_one(5'd7, 32'h200, 1'b0, t0);

      // After dispatch, reg 7 must be pending, not-ready, and tag == t0.
      query_reg(5'd7, pend, rdy, tg, vl);
      check_equal("rat pending",  pend, 1'b1);
      check_equal("rat ready",    rdy,  1'b0);
      check_equal("rat tag",      tg,   {{(256-TAG_W){1'b0}}, t0});

      // Clean up: complete and commit so state is empty.
      complete_cdb(t0, 32'h0000_00AA);
      idle_cycle();
    end
  endtask

  task automatic test_rat_cdb_bypass;
    logic [TAG_W-1:0] t0;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: same-cycle CDB bypass in RAT query ===", test_count);

      do_reset();

      dispatch_one(5'd9, 32'h300, 1'b0, t0);

      // Drive the CDB and query the RAT in the SAME cycle (before posedge).
      drive_cdb(t0, 32'hFEED_F00D, 1'b0, '0);
      query1_arch_reg = 5'd9;
      #1;
      pend = query1_pending;
      rdy  = query1_ready;
      tg   = query1_tag;
      vl   = query1_value;

      check_equal("bypass pending", pend, 1'b1);
      check_equal("bypass ready",   rdy,  1'b1);
      check_equal("bypass value",   vl,   32'hFEED_F00D);

      @(posedge clock);
      #1;
      stop_cdb();
      // Allow commit to drain.
      idle_cycle();
    end
  endtask

  task automatic test_rat_clears_on_commit;
    logic [TAG_W-1:0] t0;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: RAT clears on commit (latest writer) ===", test_count);

      do_reset();

      dispatch_one(5'd5, 32'h400, 1'b0, t0);
      complete_cdb(t0, 32'h1234_5678);
      // head now ready, commit fires this cycle; advance to retire.
      idle_cycle();

      query_reg(5'd5, pend, rdy, tg, vl);
      check_equal("rat cleared after commit", pend, 1'b0);
    end
  endtask

  task automatic test_rat_stale_clear_protection;
    logic [TAG_W-1:0] t0, t1;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: RAT stale-clear protection ===", test_count);

      do_reset();

      // inst0 writes reg 5 (tag 0)
      dispatch_one(5'd5, 32'h500, 1'b0, t0);
      // inst1 also writes reg 5 (tag 1) - RAT now points at t1
      dispatch_one(5'd5, 32'h504, 1'b0, t1);

      // Confirm RAT points at t1 right now.
      query_reg(5'd5, pend, rdy, tg, vl);
      check_equal("rat pending after rename", pend, 1'b1);
      check_equal("rat tag == t1",            tg,   {{(256-TAG_W){1'b0}}, t1});

      // Complete inst0; inst0 commits next. Its commit must NOT clear the RAT
      // because t1 is now the latest writer of reg 5.
      complete_cdb(t0, 32'h0000_00A0);
      // inst0 is at head; commit fires this cycle. Advance to retire it.
      idle_cycle();

      query_reg(5'd5, pend, rdy, tg, vl);
      check_equal("rat still pending (stale clear blocked)", pend, 1'b1);
      check_equal("rat still points at t1",                  tg,   {{(256-TAG_W){1'b0}}, t1});

      // Clean up: complete inst1 and let it commit.
      complete_cdb(t1, 32'h0000_00B0);
      idle_cycle();

      query_reg(5'd5, pend, rdy, tg, vl);
      check_equal("rat cleared after latest commits", pend, 1'b0);
    end
  endtask

  task automatic test_x0_guard;
    logic [TAG_W-1:0] t0;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: x0 guard ===", test_count);

      do_reset();

      // Dispatch an instruction that writes x0.
      dispatch_one(5'd0, 32'h600, 1'b0, t0);

      // x0 must never be marked busy.
      query_reg(5'd0, pend, rdy, tg, vl);
      check_equal("x0 never pending", pend, 1'b0);

      // Complete and commit it; confirm still not pending.
      complete_cdb(t0, 32'hCAFE_BABE);
      idle_cycle();

      query_reg(5'd0, pend, rdy, tg, vl);
      check_equal("x0 still not pending after commit", pend, 1'b0);
    end
  endtask

  task automatic test_flush_clears_everything;
    logic [TAG_W-1:0] t0, t1, t2;
    logic             pend, rdy;
    logic [TAG_W-1:0] tg;
    logic [XLEN-1:0]  vl;
    integer           i;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: flush clears everything ===", test_count);

      do_reset();

      dispatch_one(5'd1, 32'h700, 1'b0, t0);
      dispatch_one(5'd2, 32'h704, 1'b0, t1);
      dispatch_one(5'd3, 32'h708, 1'b0, t2);

      // Flush for one cycle.
      flush = 1'b1;
      @(posedge clock);
      #1;
      flush = 1'b0;

      // All arch regs must be un-pending.
      for (i = 0; i < 32; i = i + 1) begin
        query_reg(i[4:0], pend, rdy, tg, vl);
        if (pend !== 1'b0) begin
          $display("ERROR: flush left reg %0d pending", i);
          error_count = error_count + 1;
        end
      end

      // rob_full must be 0; a subsequent dispatch must succeed.
      check_equal("rob_full after flush", rob_full, 1'b0);

      dispatch_one(5'd4, 32'h70C, 1'b0, t0);
      check_equal("dispatch_tag wraps to head", t0, {{(256-TAG_W){1'b0}}, {TAG_W{1'b0}}});

      complete_cdb(t0, 32'h0000_0044);
      idle_cycle();
    end
  endtask

  task automatic test_full_detection;
    logic [TAG_W-1:0] tx;
    integer           k;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: rob_full detection ===", test_count);

      do_reset();

      // Fill the ROB with ROB_SIZE dispatches without completing any of them.
      for (k = 0; k < ROB_SIZE; k = k + 1) begin
        check_equal("rob_full before this dispatch", rob_full, 1'b0);
        // Use destination reg (k + 1) to avoid x0 aliasing.
        dispatch_one(5'd1 + k[4:0], 32'h800 + 4 * k, 1'b0, tx);
      end

      check_equal("rob_full after fill", rob_full, 1'b1);

      // Another dispatch attempt while full should not disturb state.
      dispatch_drive(5'd31, 32'h900, 1'b0, 1'b0, 1'b0);
      @(posedge clock);
      #1;
      stop_dispatch();
      check_equal("rob_full still set", rob_full, 1'b1);

      // Drain everything so subsequent tests start clean.
      for (k = 0; k < ROB_SIZE; k = k + 1) begin
        complete_cdb(k[TAG_W-1:0], 32'h0);
        idle_cycle();
      end
      // After drain, flush any residual RAT state just in case.
      flush = 1'b1;
      @(posedge clock);
      #1;
      flush = 1'b0;
    end
  endtask

  task automatic test_wraparound;
    logic [TAG_W-1:0] tx;
    integer           k;
    integer           total;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: head/tail wraparound ===", test_count);

      do_reset();

      total = ROB_SIZE + 3;
      for (k = 0; k < total; k = k + 1) begin
        dispatch_one(5'd1 + (k[4:0] % 5'd30), 32'hA00 + 4 * k, 1'b0, tx);
        complete_cdb(tx, 32'hC0DE_0000 + k);
        // commit becomes visible on this cycle; advance to retire.
        check_equal("commit visible after complete", commit_valid[0], 1'b1);
        idle_cycle();
        check_equal("no stuck state", commit_valid[0], 1'b0);
      end

      // After all that, the ROB should be empty and not full.
      check_equal("rob_full at end of wraparound", rob_full, 1'b0);
    end
  endtask

  // ============================================================
  // Branch prediction / mispredict tests
  // ============================================================

  task automatic test_branch_correct_prediction;
    logic [TAG_W-1:0] tb;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: correct prediction -> no mispredict ===", test_count);
      do_reset();

      // Predicted taken, actual taken, target match.
      dispatch_branch_pred(5'd0, 32'h0000_1000, 1'b0, 1'b1, 32'h0000_2000, tb);
      complete_cdb_branch(tb, 1'b1, 32'h0000_2000);

      check_equal("no mispredict on correct pred", mispredict_valid, 1'b0);
      idle_cycle();
    end
  endtask

  task automatic test_branch_taken_predicted_not_taken;
    logic [TAG_W-1:0] tb;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: taken but predicted not-taken ===", test_count);
      do_reset();

      dispatch_branch_pred(5'd0, 32'h0000_1100, 1'b0, 1'b0, 32'h0, tb);
      complete_cdb_branch(tb, 1'b1, 32'h0000_1200);

      check_equal("mispredict pulse",            mispredict_valid,  1'b1);
      check_equal("mispredict_target",           mispredict_target, 32'h0000_1200);
      check_equal("commit_is_branch",            commit_is_branch[0],  1'b1);

      idle_cycle();
      check_equal("mispredict falls after retire", mispredict_valid, 1'b0);
    end
  endtask

  task automatic test_branch_not_taken_predicted_taken;
    logic [TAG_W-1:0] tb;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: not-taken but predicted taken ===", test_count);
      do_reset();

      // Predicted taken (toward 0x0000_2200), actual not-taken.  Recovery
      // target should be NPC = PC + 4 = 0x0000_1204.
      dispatch_branch_pred(5'd0, 32'h0000_1200, 1'b0, 1'b1, 32'h0000_2200, tb);
      complete_cdb_branch(tb, 1'b0, 32'h0);

      check_equal("mispredict pulse",  mispredict_valid,  1'b1);
      check_equal("mispredict target = NPC", mispredict_target, 32'h0000_1204);

      idle_cycle();
    end
  endtask

  task automatic test_branch_taken_wrong_target;
    logic [TAG_W-1:0] tb;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: correct direction but wrong target ===", test_count);
      do_reset();

      // Predicted taken to 0xAAAA; actually taken to 0xBBBB.
      dispatch_branch_pred(5'd0, 32'h0000_1300, 1'b0, 1'b1, 32'h0000_AAAA, tb);
      complete_cdb_branch(tb, 1'b1, 32'h0000_BBBB);

      check_equal("mispredict pulse",       mispredict_valid,  1'b1);
      check_equal("redirect to actual tgt", mispredict_target, 32'h0000_BBBB);
      idle_cycle();
    end
  endtask

  // ============================================================
  // main
  // ============================================================
  initial begin
    error_count = 0;
    test_count  = 0;

    clear_inputs();
    reset = 1'b0;

    test_basic_dispatch_complete_commit();
    test_in_order_commit();
    test_rat_pending_tag();
    test_rat_cdb_bypass();
    test_rat_clears_on_commit();
    test_rat_stale_clear_protection();
    test_x0_guard();
    test_flush_clears_everything();
    test_full_detection();
    test_wraparound();
    test_branch_correct_prediction();
    test_branch_taken_predicted_not_taken();
    test_branch_not_taken_predicted_taken();
    test_branch_taken_wrong_target();

    if (error_count == 0) begin
      $display("\n@@@ Passed");
    end else begin
      $display("\n@@@ Incorrect, error_count = %0d", error_count);
    end

    $finish;
  end

endmodule
