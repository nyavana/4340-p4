`timescale 1ns/1ps
`include "sys_defs.svh"

module rs_test;

  localparam RS_SIZE = `RS_SZ;
  localparam XLEN    = `XLEN;
  localparam TAG_W   = $clog2(`ROB_SZ);
  localparam OP_W    = 8;

  logic                 clock;
  logic                 reset;
  logic                 flush;

  // dispatch side
  logic                 dispatch_valid;
  logic [OP_W-1:0]      dispatch_op;
  logic [TAG_W-1:0]     dispatch_dest_tag;

  logic                 dispatch_src1_ready;
  logic [TAG_W-1:0]     dispatch_src1_tag;
  logic [XLEN-1:0]      dispatch_src1_value;

  logic                 dispatch_src2_ready;
  logic [TAG_W-1:0]     dispatch_src2_tag;
  logic [XLEN-1:0]      dispatch_src2_value;

  logic [2:0]           dispatch_branch_funct3;
  logic [XLEN-1:0]      dispatch_branch_target;
  logic [XLEN-1:0]      dispatch_branch_NPC;

  logic                 rs_full;

  // cdb
  logic                 cdb_valid;
  logic [TAG_W-1:0]     cdb_tag;
  logic [XLEN-1:0]      cdb_value;

  // issue side
  logic                 issue_accept;
  logic                 issue_valid;
  logic [OP_W-1:0]      issue_op;
  logic [TAG_W-1:0]     issue_dest_tag;
  logic [XLEN-1:0]      issue_src1_value;
  logic [XLEN-1:0]      issue_src2_value;
  logic [2:0]           issue_branch_funct3;
  logic [XLEN-1:0]      issue_branch_target;
  logic [XLEN-1:0]      issue_branch_NPC;

  integer error_count;
  integer test_count;

  rs dut (
    .clock(clock),
    .reset(reset),
    .flush(flush),

    .dispatch_valid(dispatch_valid),
    .dispatch_op(dispatch_op),
    .dispatch_dest_tag(dispatch_dest_tag),

    .dispatch_src1_ready(dispatch_src1_ready),
    .dispatch_src1_tag(dispatch_src1_tag),
    .dispatch_src1_value(dispatch_src1_value),

    .dispatch_src2_ready(dispatch_src2_ready),
    .dispatch_src2_tag(dispatch_src2_tag),
    .dispatch_src2_value(dispatch_src2_value),

    .dispatch_branch_funct3(dispatch_branch_funct3),
    .dispatch_branch_target(dispatch_branch_target),
    .dispatch_branch_NPC   (dispatch_branch_NPC),

    .rs_full(rs_full),

    .cdb_valid(cdb_valid),
    .cdb_tag(cdb_tag),
    .cdb_value(cdb_value),

    .issue_accept(issue_accept),
    .issue_valid(issue_valid),
    .issue_op(issue_op),
    .issue_dest_tag(issue_dest_tag),
    .issue_src1_value(issue_src1_value),
    .issue_src2_value(issue_src2_value),
    .issue_branch_funct3(issue_branch_funct3),
    .issue_branch_target(issue_branch_target),
    .issue_branch_NPC   (issue_branch_NPC)
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
      flush               = 1'b0;

      dispatch_valid      = 1'b0;
      dispatch_op         = '0;
      dispatch_dest_tag   = '0;
      dispatch_src1_ready = 1'b0;
      dispatch_src1_tag   = '0;
      dispatch_src1_value = '0;
      dispatch_src2_ready = 1'b0;
      dispatch_src2_tag   = '0;
      dispatch_src2_value = '0;

      dispatch_branch_funct3 = 3'b0;
      dispatch_branch_target = '0;
      dispatch_branch_NPC    = '0;

      cdb_valid           = 1'b0;
      cdb_tag             = '0;
      cdb_value           = '0;

      issue_accept        = 1'b0;
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
        $display("ERROR: %s mismatch, got=%0h exp=%0h @ t=%0t", name, got, exp, $time);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic expect_no_issue;
    begin
      if (issue_valid !== 1'b0) begin
        $display("ERROR: expected no issue, but issue_valid=1 @ t=%0t", $time);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic expect_issue;
    input logic [OP_W-1:0]  exp_op;
    input logic [TAG_W-1:0] exp_dest;
    input logic [XLEN-1:0]  exp_v1;
    input logic [XLEN-1:0]  exp_v2;
    begin
      if (issue_valid !== 1'b1) begin
        $display("ERROR: expected issue_valid=1 @ t=%0t", $time);
        error_count = error_count + 1;
      end else begin
        check_equal("issue_op",         issue_op,         exp_op);
        check_equal("issue_dest_tag",   issue_dest_tag,   exp_dest);
        check_equal("issue_src1_value", issue_src1_value, exp_v1);
        check_equal("issue_src2_value", issue_src2_value, exp_v2);
      end
    end
  endtask

  task automatic dispatch_inst;
    input logic [OP_W-1:0]  op;
    input logic [TAG_W-1:0] dest_tag;
    input logic             s1_ready;
    input logic [TAG_W-1:0] s1_tag;
    input logic [XLEN-1:0]  s1_val;
    input logic             s2_ready;
    input logic [TAG_W-1:0] s2_tag;
    input logic [XLEN-1:0]  s2_val;
    begin
      dispatch_valid      = 1'b1;
      dispatch_op         = op;
      dispatch_dest_tag   = dest_tag;

      dispatch_src1_ready = s1_ready;
      dispatch_src1_tag   = s1_tag;
      dispatch_src1_value = s1_val;

      dispatch_src2_ready = s2_ready;
      dispatch_src2_tag   = s2_tag;
      dispatch_src2_value = s2_val;
    end
  endtask

  task automatic stop_dispatch;
    begin
      dispatch_valid      = 1'b0;
      dispatch_op         = '0;
      dispatch_dest_tag   = '0;
      dispatch_src1_ready = 1'b0;
      dispatch_src1_tag   = '0;
      dispatch_src1_value = '0;
      dispatch_src2_ready = 1'b0;
      dispatch_src2_tag   = '0;
      dispatch_src2_value = '0;
    end
  endtask

  task automatic drive_cdb;
    input logic [TAG_W-1:0] tag;
    input logic [XLEN-1:0]  val;
    begin
      cdb_valid = 1'b1;
      cdb_tag   = tag;
      cdb_value = val;
    end
  endtask

  task automatic stop_cdb;
    begin
      cdb_valid = 1'b0;
      cdb_tag   = '0;
      cdb_value = '0;
    end
  endtask

  task automatic accept_issue_one_cycle;
    begin
      issue_accept = 1'b1;
      @(posedge clock);
      #1;
      issue_accept = 1'b0;
    end
  endtask

  // ============================================================
  // tests
  // ============================================================

  task automatic test_reset_empty;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: reset empty ===", test_count);

      do_reset();

      check_equal("rs_full after reset", rs_full, 1'b0);
      expect_no_issue();
    end
  endtask

  task automatic test_basic_ready_dispatch_issue;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: basic ready dispatch -> issue ===", test_count);

      do_reset();

      dispatch_inst(
        8'h11,   // op
        3'd1,    // dest_tag
        1'b1,    // src1 ready
        '0,
        32'h10,
        1'b1,    // src2 ready
        '0,
        32'h20
      );

      if (rs_full !== 1'b0) begin
        $display("ERROR: RS should not be full before first dispatch");
        error_count = error_count + 1;
      end

      @(posedge clock);
      #1;
      stop_dispatch();

      expect_issue(8'h11, 3'd1, 32'h10, 32'h20);

      accept_issue_one_cycle();
      expect_no_issue();
    end
  endtask

  task automatic test_dependency_wakeup_then_issue;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: dependency wakeup then issue ===", test_count);

      do_reset();

      dispatch_inst(
        8'h22,
        3'd2,
        1'b0,         // src1 not ready
        3'd5,         // wait for tag 5
        32'h0,
        1'b1,
        '0,
        32'h33
      );

      @(posedge clock);
      #1;
      stop_dispatch();

      expect_no_issue();

      drive_cdb(3'd5, 32'hAAAA_5555);
      #1;
      expect_issue(8'h22, 3'd2, 32'hAAAA_5555, 32'h33);

      accept_issue_one_cycle();
      stop_cdb();
      expect_no_issue();
    end
  endtask

  task automatic test_same_cycle_cdb_bypass_issue;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: same-cycle CDB bypass into issue ===", test_count);

      do_reset();

      dispatch_inst(
        8'h33,
        3'd3,
        1'b0,
        3'd6,
        32'h0,
        1'b1,
        '0,
        32'h44
      );

      @(posedge clock);
      #1;
      stop_dispatch();

      expect_no_issue();

      // This cycle the CDB wakes it up.
      // issue_valid should become 1 combinationally,
      // and the issued src1 value should bypass directly from cdb_value.
      drive_cdb(3'd6, 32'hDEAD_BEEF);
      #1;
      expect_issue(8'h33, 3'd3, 32'hDEAD_BEEF, 32'h44);

      accept_issue_one_cycle();
      stop_cdb();
      expect_no_issue();
    end
  endtask

  task automatic test_backpressure_hold_issue;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: backpressure holds issue ===", test_count);

      do_reset();

      dispatch_inst(
        8'h44,
        3'd4,
        1'b1, '0, 32'h1111,
        1'b1, '0, 32'h2222
      );

      @(posedge clock);
      #1;
      stop_dispatch();

      expect_issue(8'h44, 3'd4, 32'h1111, 32'h2222);

      // do not accept yet
      issue_accept = 1'b0;
      @(posedge clock);
      #1;

      // still there
      expect_issue(8'h44, 3'd4, 32'h1111, 32'h2222);

      accept_issue_one_cycle();
      expect_no_issue();
    end
  endtask

  task automatic test_full_behavior;
    integer k;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: fill RS and check rs_full ===", test_count);

      do_reset();

      for (k = 0; k < RS_SIZE; k = k + 1) begin
        dispatch_inst(
          8'h50 + k[7:0],
          k[TAG_W-1:0],
          1'b0, 3'd7, 32'h0,   // keep them not ready so they won't issue away
          1'b0, 3'd6, 32'h0
        );
        @(posedge clock);
        #1;
        stop_dispatch();
      end

      check_equal("rs_full after filling", rs_full, 1'b1);

      // extra dispatch should not create issue magically or break state
      dispatch_inst(
        8'h7F,
        3'd1,
        1'b1, '0, 32'h1,
        1'b1, '0, 32'h2
      );
      @(posedge clock);
      #1;
      stop_dispatch();

      // still full; no ready instruction
      check_equal("rs_full remains high", rs_full, 1'b1);
      expect_no_issue();
    end
  endtask

  task automatic test_flush_clears_all;
    begin
      test_count = test_count + 1;
      $display("\n=== Test %0d: flush clears all ===", test_count);

      do_reset();

      dispatch_inst(
        8'h66,
        3'd5,
        1'b1, '0, 32'h11,
        1'b1, '0, 32'h22
      );
      @(posedge clock);
      #1;
      stop_dispatch();

      expect_issue(8'h66, 3'd5, 32'h11, 32'h22);

      flush = 1'b1;
      @(posedge clock);
      #1;
      flush = 1'b0;

      expect_no_issue();
      check_equal("rs_full after flush", rs_full, 1'b0);
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

    test_reset_empty();
    test_basic_ready_dispatch_issue();
    test_dependency_wakeup_then_issue();
    test_same_cycle_cdb_bypass_issue();
    test_backpressure_hold_issue();
    test_full_behavior();
    test_flush_clears_all();

    if (error_count == 0) begin
      $display("\n@@@ Passed");
    end else begin
      $display("\n@@@ Incorrect, error_count = %0d", error_count);
    end

    $finish;
  end

endmodule
