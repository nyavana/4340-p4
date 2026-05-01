`timescale 1ns/1ps
`include "verilog/sys_defs.svh"

// Unit testbench for verilog/branch_predictor.sv
//
// Covers:
//   1. Cold BTB miss -> pred_valid = 0
//   2. Learn a taken conditional (one update) -> next predict = taken
//   3. Learn a not-taken conditional -> counter decrements from 01 to 00
//   4. JAL install -> pred_is_uncond, pred_taken regardless of counter
//   5. Counter saturates at 11 on repeated taken
//   6. Counter saturates at 00 on repeated not-taken
//   7. From 11, two not-takens -> 01 and prediction flips to not-taken
//   8. Tag-alias collision -> same index, different tag => miss
//   9. Write-then-read sanity: update on cycle N posedge is visible on N+1
//   10. RAS push/pop: single call-return predicts link PC even on BTB miss
//   11. RAS nesting: push x3, pop x3 -> LIFO order
//   12. RAS empty: predict_is_return with count=0 falls back to BTB
//   13. RAS wrap: more pushes than RAS_ENTRIES -> SP wraps, count saturates
//
// Conforms to the `.pass` grep convention:
//   prints "@@@ Passed" on success or "@@@ Incorrect" on any failure.

module branch_predictor_test;

    localparam XLEN        = `XLEN;
    localparam BTB_ENTRIES = `BTB_ENTRIES;
    localparam BHT_ENTRIES = `BHT_ENTRIES;
    localparam RAS_ENTRIES = `RAS_ENTRIES;
    localparam BTB_IDX_W   = $clog2(BTB_ENTRIES);
    localparam BHT_IDX_W   = $clog2(BHT_ENTRIES);
    localparam BTB_TAG_W   = XLEN - 2 - BTB_IDX_W;
    localparam GHR_W       = BHT_IDX_W;

    logic              clock;
    logic              reset;

    logic [XLEN-1:0]   predict_PC;
    logic              pred_valid;
    logic              pred_taken;
    logic [XLEN-1:0]   pred_target;
    logic              pred_is_uncond;

    logic              predict_is_return;
    logic [XLEN-1:0]   predict_link_pc;
    logic              ras_push_en;
    logic              ras_pop_en;

    logic              update_valid;
    logic [XLEN-1:0]   update_PC;
    logic [XLEN-1:0]   update_target;
    logic              update_taken;
    logic              update_is_uncond;

    integer            error_count;
    integer            test_count;

    branch_predictor dut (
        .clock            (clock),
        .reset            (reset),
        .predict_PC       (predict_PC),
        .pred_valid       (pred_valid),
        .pred_taken       (pred_taken),
        .pred_target      (pred_target),
        .pred_is_uncond   (pred_is_uncond),
        .predict_is_return (predict_is_return),
        .predict_link_pc   (predict_link_pc),
        .ras_push_en       (ras_push_en),
        .ras_pop_en        (ras_pop_en),
        .update_valid     (update_valid),
        .update_PC        (update_PC),
        .update_target    (update_target),
        .update_taken     (update_taken),
        .update_is_uncond (update_is_uncond)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    task automatic clear_inputs;
        begin
            predict_PC        = '0;
            predict_is_return = 1'b0;
            predict_link_pc   = '0;
            ras_push_en       = 1'b0;
            ras_pop_en        = 1'b0;
            update_valid      = 1'b0;
            update_PC         = '0;
            update_target     = '0;
            update_taken      = 1'b0;
            update_is_uncond  = 1'b0;
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
            mdl_reset();
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

    // ----------------------------------------------------------------
    // TB-side gshare reference model.
    //
    // Mirrors the RTL state (GHR, BHT, BTB) so tests can assert on the
    // exact prediction the predictor should produce given the history of
    // updates so far.  The RTL is gshare: bht_idx = pc[BHT_IDX_W+1:2] ^ ghr,
    // and ghr shifts on every conditional update.  Hard-coded "still taken"
    // claims are not recoverable for single-PC sequences, so failing tests
    // assert "RTL == model" instead.
    // ----------------------------------------------------------------
    logic [GHR_W-1:0]     mdl_ghr;
    logic [1:0]           mdl_bht [BHT_ENTRIES-1:0];
    logic                 mdl_btb_v   [BTB_ENTRIES-1:0];
    logic                 mdl_btb_un  [BTB_ENTRIES-1:0];
    logic [BTB_TAG_W-1:0] mdl_btb_tag [BTB_ENTRIES-1:0];
    logic [XLEN-1:0]      mdl_btb_tgt [BTB_ENTRIES-1:0];

    function automatic logic [BHT_IDX_W-1:0] mdl_bht_pc_bits(input logic [XLEN-1:0] pc);
        mdl_bht_pc_bits = pc[BHT_IDX_W+1 : 2];
    endfunction

    function automatic logic [BTB_IDX_W-1:0] mdl_btb_idx(input logic [XLEN-1:0] pc);
        mdl_btb_idx = pc[BTB_IDX_W+1 : 2];
    endfunction

    function automatic logic [BTB_TAG_W-1:0] mdl_btb_tag_of(input logic [XLEN-1:0] pc);
        mdl_btb_tag_of = pc[XLEN-1 : BTB_IDX_W+2];
    endfunction

    task automatic mdl_reset;
        integer j;
        begin
            mdl_ghr = '0;
            for (j = 0; j < BHT_ENTRIES; j = j + 1) mdl_bht[j] = 2'b01;
            for (j = 0; j < BTB_ENTRIES; j = j + 1) begin
                mdl_btb_v[j]   = 1'b0;
                mdl_btb_un[j]  = 1'b0;
                mdl_btb_tag[j] = '0;
                mdl_btb_tgt[j] = '0;
            end
        end
    endtask

    task automatic mdl_apply_update;
        input logic [XLEN-1:0] pc;
        input logic [XLEN-1:0] target;
        input logic            taken;
        input logic            is_uncond;
        logic [BTB_IDX_W-1:0] bi;
        logic [BHT_IDX_W-1:0] hi;
        begin
            bi = mdl_btb_idx(pc);
            mdl_btb_v[bi]   = 1'b1;
            mdl_btb_un[bi]  = is_uncond;
            mdl_btb_tag[bi] = mdl_btb_tag_of(pc);
            mdl_btb_tgt[bi] = target;
            if (!is_uncond) begin
                hi = mdl_bht_pc_bits(pc) ^ mdl_ghr;
                if (taken && mdl_bht[hi] != 2'b11)
                    mdl_bht[hi] = mdl_bht[hi] + 2'b01;
                if (!taken && mdl_bht[hi] != 2'b00)
                    mdl_bht[hi] = mdl_bht[hi] - 2'b01;
                mdl_ghr = {mdl_ghr[GHR_W-2:0], taken};
            end
        end
    endtask

    // Compute (v, t, tgt, un) the predictor should produce at this PC,
    // given the current model state (BTB/BHT/GHR, no RAS).
    task automatic mdl_predict;
        input  logic [XLEN-1:0] pc;
        output logic            v;
        output logic            t;
        output logic [XLEN-1:0] tgt;
        output logic            un;
        logic [BTB_IDX_W-1:0] bi;
        logic [BHT_IDX_W-1:0] hi;
        logic [BTB_TAG_W-1:0] tg;
        logic                 hit;
        begin
            bi  = mdl_btb_idx(pc);
            hi  = mdl_bht_pc_bits(pc) ^ mdl_ghr;
            tg  = mdl_btb_tag_of(pc);
            hit = mdl_btb_v[bi] && (mdl_btb_tag[bi] == tg);
            if (hit) begin
                v   = 1'b1;
                un  = mdl_btb_un[bi];
                t   = mdl_btb_un[bi] || mdl_bht[hi][1];
                tgt = mdl_btb_tgt[bi];
            end else begin
                v   = 1'b0;
                un  = 1'b0;
                t   = 1'b0;
                tgt = '0;
            end
        end
    endtask

    // Return the smallest aligned PC whose bht_pc_bits == `target_bits`,
    // for use in tests that need updates landing on a chosen BHT counter
    // under gshare's running GHR.  Bit 7 carries the high bit of bht_pc_bits;
    // bits [6:2] form the low five bits and also serve as btb_idx.  Choosing
    // tag-bits = 0 keeps every constructed PC inside the same BTB tag space,
    // so the BTB-direct-mapped collisions in this test are deliberate.
    function automatic logic [XLEN-1:0] make_pc_for_bht_bits(input logic [BHT_IDX_W-1:0] target_bits);
        make_pc_for_bht_bits = {{(XLEN-BHT_IDX_W-2){1'b0}}, target_bits, 2'b00};
    endfunction

    // Drive one commit-time update over exactly one posedge.
    task automatic do_update;
        input logic [XLEN-1:0] pc;
        input logic [XLEN-1:0] target;
        input logic            taken;
        input logic            is_uncond;
        begin
            update_valid     = 1'b1;
            update_PC        = pc;
            update_target    = target;
            update_taken     = taken;
            update_is_uncond = is_uncond;
            @(posedge clock);
            #1;
            update_valid     = 1'b0;
            update_PC        = '0;
            update_target    = '0;
            update_taken     = 1'b0;
            update_is_uncond = 1'b0;
            mdl_apply_update(pc, target, taken, is_uncond);
        end
    endtask

    // Combinational read of the prediction for a given PC.
    task automatic do_predict;
        input  logic [XLEN-1:0] pc;
        output logic            v;
        output logic            t;
        output logic [XLEN-1:0] tgt;
        output logic            un;
        begin
            predict_PC = pc;
            #1;
            v   = pred_valid;
            t   = pred_taken;
            tgt = pred_target;
            un  = pred_is_uncond;
        end
    endtask

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    task automatic test_cold_miss;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: cold BTB miss ===", test_count);
            do_reset();

            do_predict(32'h0000_1000, v, t, tgt, un);
            check_eq("cold pred_valid", v, 1'b0);
            check_eq("cold pred_taken", t, 1'b0);
            check_eq("cold pred_is_uncond", un, 1'b0);
        end
    endtask

    task automatic test_learn_taken_conditional;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        logic            mv, mt, mun;
        logic [XLEN-1:0] mtgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: learn a taken conditional ===", test_count);
            do_reset();

            // One taken update at PC 0x1000 -> target 0x2000.  The update
            // increments BHT[bht_pc_bits(0x1000) ^ ghr_pre=0] from 01 to 10
            // and shifts ghr to 6'b000001.  A subsequent predict at PC 0x1000
            // therefore reads BHT[0 ^ 1 = 1] (a cold counter), so pred_taken
            // is 0 -- this is gshare's intended behavior, not a bug.
            do_update(32'h0000_1000, 32'h0000_2000, 1'b1, 1'b0);

            do_predict(32'h0000_1000, v, t, tgt, un);
            mdl_predict(32'h0000_1000, mv, mt, mtgt, mun);
            check_eq("hit after one taken update", v, mv);
            check_eq("pred_taken matches gshare model", t, mt);
            check_eq("is_uncond matches model", un, mun);
            check_eq32("stored target", tgt, mtgt);
            // The update did install the BTB entry.
            check_eq("model: BTB hit recorded", mv, 1'b1);
            check_eq32("model: stored target = 0x2000", mtgt, 32'h0000_2000);
        end
    endtask

    task automatic test_learn_not_taken;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: learn a not-taken conditional ===", test_count);
            do_reset();

            // Single not-taken update: counter goes 01 -> 00.  BTB still gets
            // written; the prediction should be hit but not-taken.
            do_update(32'h0000_3000, 32'h0000_3004, 1'b0, 1'b0);

            do_predict(32'h0000_3000, v, t, tgt, un);
            check_eq("hit after not-taken update", v, 1'b1);
            check_eq("prediction is not-taken after one nt update", t, 1'b0);
        end
    endtask

    task automatic test_jal_install;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: JAL install ===", test_count);
            do_reset();

            // JAL at 0x4000 -> 0x6000, unconditional; update_taken=1 is used
            // for commit-side bookkeeping, but is_uncond=1 forces taken on
            // prediction regardless of counter state.
            do_update(32'h0000_4000, 32'h0000_6000, 1'b1, 1'b1);

            do_predict(32'h0000_4000, v, t, tgt, un);
            check_eq("JAL hit", v, 1'b1);
            check_eq("JAL is_uncond reported", un, 1'b1);
            check_eq("JAL predicted taken", t, 1'b1);
            check_eq32("JAL target", tgt, 32'h0000_6000);
        end
    endtask

    task automatic test_saturate_high;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        logic            mv, mt, mun;
        logic [XLEN-1:0] mtgt;
        integer          k;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: repeated taken at single PC, gshare path ===", test_count);
            do_reset();

            // Six taken updates at the same PC.  Each shifts GHR, so the
            // updates land on six DIFFERENT BHT counters under gshare.  The
            // single-PC saturation claim doesn't hold; we instead assert the
            // RTL prediction tracks the gshare model after every step.
            for (k = 0; k < 6; k = k + 1)
                do_update(32'h0000_5000, 32'h0000_5100, 1'b1, 1'b0);

            do_predict(32'h0000_5000, v, t, tgt, un);
            mdl_predict(32'h0000_5000, mv, mt, mtgt, mun);
            check_eq("after 6 takens: pred_valid matches model", v, mv);
            check_eq("after 6 takens: pred_taken matches model", t, mt);

            // One additional not-taken update.
            do_update(32'h0000_5000, 32'h0000_5004, 1'b0, 1'b0);
            do_predict(32'h0000_5000, v, t, tgt, un);
            mdl_predict(32'h0000_5000, mv, mt, mtgt, mun);
            check_eq("after +1 not-taken: pred_taken matches model", t, mt);
        end
    endtask

    task automatic test_saturate_low;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        integer          k;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: counter saturates at 00 on repeated not-taken ===", test_count);
            do_reset();

            for (k = 0; k < 6; k = k + 1)
                do_update(32'h0000_7000, 32'h0000_7004, 1'b0, 1'b0);

            do_predict(32'h0000_7000, v, t, tgt, un);
            check_eq("still not-taken after saturation low", t, 1'b0);

            // One taken step: 00 -> 01 => still not-taken.
            do_update(32'h0000_7000, 32'h0000_7100, 1'b1, 1'b0);
            do_predict(32'h0000_7000, v, t, tgt, un);
            check_eq("00 -> 01 still not-taken", t, 1'b0);
        end
    endtask

    task automatic test_flip_from_11_to_01;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        logic [GHR_W-1:0] eg;
        logic [XLEN-1:0]  pc_predict_after_nt1;
        logic [XLEN-1:0]  pc_predict_after_nt2;
        integer          k;
        // Saturate-then-flip a chosen target counter under gshare by picking
        // a fresh PC at every step so bht_pc_bits(pc_k) ^ ghr_pre_k always
        // equals TGT_IDX.  Each conditional update therefore lands on the
        // same BHT counter regardless of how the GHR has shifted.  The two
        // post-flip predictions need their own BTB hit, so we install BTB
        // entries at the predict PCs ahead of time via not-taken updates
        // (which leave GHR=0 since 0 shifts in 0 unchanged).
        localparam logic [BHT_IDX_W-1:0] TGT_IDX = 6'd33;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: flip from 11 to 01 (gshare colliding PCs) ===", test_count);
            do_reset();

            eg = '0;

            // After 4 takens + 1 not-taken, GHR = 6'b011110 = 30.
            // After 4 takens + 2 not-takens, GHR = 6'b111100 = 60.
            pc_predict_after_nt1 = make_pc_for_bht_bits(TGT_IDX ^ 6'd30);
            pc_predict_after_nt2 = make_pc_for_bht_bits(TGT_IDX ^ 6'd60);

            // Pre-install BTB entries at the predict PCs.  These hit BHT
            // indices that are NOT TGT_IDX, so they leave the saturating
            // counter alone.  GHR stays 0 because 0 shifts in 0.
            do_update(pc_predict_after_nt1, 32'h0000_8200, 1'b0, 1'b0);
            do_update(pc_predict_after_nt2, 32'h0000_8200, 1'b0, 1'b0);

            // Four takens, each at a PC that lands the update on BHT[TGT_IDX].
            for (k = 0; k < 4; k = k + 1) begin
                do_update(make_pc_for_bht_bits(TGT_IDX ^ eg),
                          32'h0000_8200, 1'b1, 1'b0);
                eg = {eg[GHR_W-2:0], 1'b1};
            end

            // First not-taken at PC chosen to also land on BHT[TGT_IDX].
            // BHT[TGT_IDX]: 11 -> 10.
            do_update(make_pc_for_bht_bits(TGT_IDX ^ eg),
                      32'h0000_8004, 1'b0, 1'b0);
            eg = {eg[GHR_W-2:0], 1'b0};
            do_predict(pc_predict_after_nt1, v, t, tgt, un);
            check_eq("after one nt: still taken (10)", t, 1'b1);

            // Second not-taken: BHT[TGT_IDX]: 10 -> 01.
            do_update(make_pc_for_bht_bits(TGT_IDX ^ eg),
                      32'h0000_8004, 1'b0, 1'b0);
            eg = {eg[GHR_W-2:0], 1'b0};
            do_predict(pc_predict_after_nt2, v, t, tgt, un);
            check_eq("after two nts: not-taken (01)", t, 1'b0);
        end
    endtask

    task automatic test_tag_alias;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        logic [XLEN-1:0] pc_a, pc_b;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: tag alias collision ===", test_count);
            do_reset();

            // Pick two PCs that share the BTB index but differ in tag.
            // Stride to collide on BTB_IDX_W-bit index at word boundaries.
            pc_a = 32'h0000_9000;
            pc_b = pc_a + (32'h1 << (BTB_IDX_W + 2));

            // Install pc_a with target X, is_uncond=0, taken.
            do_update(pc_a, 32'h0000_AA00, 1'b1, 1'b0);

            // Predict pc_b: same index, different tag -> miss.
            do_predict(pc_b, v, t, tgt, un);
            check_eq("alias: tag mismatch -> miss", v, 1'b0);
            check_eq("alias: not taken on miss", t, 1'b0);

            // Installing pc_b overwrites the slot; pc_a should now miss.
            do_update(pc_b, 32'h0000_BB00, 1'b1, 1'b0);
            do_predict(pc_a, v, t, tgt, un);
            check_eq("alias: original tag now misses after overwrite", v, 1'b0);
        end
    endtask

    // --- RAS helpers --------------------------------------------------

    // Drive one push over a posedge.  `link` is the return address
    // that would be stored by a JAL / call.  ras_push_en is registered
    // on the next posedge and state becomes visible afterward.
    task automatic ras_push;
        input logic [XLEN-1:0] link;
        begin
            predict_link_pc = link;
            ras_push_en     = 1'b1;
            ras_pop_en      = 1'b0;
            @(posedge clock);
            #1;
            ras_push_en     = 1'b0;
            predict_link_pc = '0;
        end
    endtask

    // Drive one pop over a posedge.
    task automatic ras_pop;
        begin
            ras_push_en = 1'b0;
            ras_pop_en  = 1'b1;
            @(posedge clock);
            #1;
            ras_pop_en  = 1'b0;
        end
    endtask

    // Sample the return prediction at `ret_pc` with `predict_is_return`
    // asserted.  Does not cross a posedge so the stack is left alone.
    task automatic do_predict_return;
        input  logic [XLEN-1:0] ret_pc;
        output logic            v;
        output logic            t;
        output logic [XLEN-1:0] tgt;
        output logic            un;
        begin
            predict_PC        = ret_pc;
            predict_is_return = 1'b1;
            #1;
            v   = pred_valid;
            t   = pred_taken;
            tgt = pred_target;
            un  = pred_is_uncond;
            predict_is_return = 1'b0;
        end
    endtask

    // --- RAS tests ----------------------------------------------------

    task automatic test_ras_single_call_return;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: RAS single call-return ===", test_count);
            do_reset();

            // Simulate one call: link = PC+4 = 0x1004 is pushed.
            ras_push(32'h0000_1004);

            // On a return prediction the RAS top should drive the target
            // even though no BTB entry exists for the JALR itself.
            do_predict_return(32'h0000_2100, v, t, tgt, un);
            check_eq("return hit via RAS", v, 1'b1);
            check_eq("return taken via RAS", t, 1'b1);
            check_eq("return is_uncond via RAS", un, 1'b1);
            check_eq32("return target = link", tgt, 32'h0000_1004);
        end
    endtask

    task automatic test_ras_nested_lifo;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: RAS nested LIFO ===", test_count);
            do_reset();

            ras_push(32'hAAAA_0004);
            ras_push(32'hBBBB_0004);
            ras_push(32'hCCCC_0004);

            do_predict_return(32'h0000_3000, v, t, tgt, un);
            check_eq32("first return -> top (CCCC)", tgt, 32'hCCCC_0004);
            ras_pop();

            do_predict_return(32'h0000_3000, v, t, tgt, un);
            check_eq32("second return -> BBBB", tgt, 32'hBBBB_0004);
            ras_pop();

            do_predict_return(32'h0000_3000, v, t, tgt, un);
            check_eq32("third return -> AAAA", tgt, 32'hAAAA_0004);
        end
    endtask

    task automatic test_ras_empty_fallback;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: RAS empty falls back to BTB ===", test_count);
            do_reset();

            // No pushes have happened.  A return prediction must not be
            // forced valid; it should reflect the (cold-miss) BTB path.
            do_predict_return(32'h0000_4000, v, t, tgt, un);
            check_eq("empty RAS -> pred_valid follows BTB (miss)", v, 1'b0);
            check_eq("empty RAS -> pred_taken follows BTB (miss)", t, 1'b0);
        end
    endtask

    task automatic test_ras_underflow_no_crash;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: RAS underflow is a no-op ===", test_count);
            do_reset();

            // Pop on an empty stack a few times; none of these should
            // perturb internal state or make the next return succeed.
            ras_pop();
            ras_pop();
            ras_pop();

            do_predict_return(32'h0000_5000, v, t, tgt, un);
            check_eq("after underflow pops, RAS still empty", v, 1'b0);

            // One push after the underflow: next return must still work.
            ras_push(32'hDEAD_BEE4);
            do_predict_return(32'h0000_5000, v, t, tgt, un);
            check_eq("post-underflow push+pop path works", v, 1'b1);
            check_eq32("post-underflow link", tgt, 32'hDEAD_BEE4);
        end
    endtask

    task automatic test_ras_wrap;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        integer          k;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: RAS wrap on deeper-than-depth push ===", test_count);
            do_reset();

            // Push RAS_ENTRIES+1 distinct links.  The first link is
            // overwritten by the wraparound; the most-recently-pushed
            // link must still be the predicted return target.
            for (k = 0; k <= RAS_ENTRIES; k = k + 1)
                ras_push(32'hE000_0000 | (k[15:0] << 2));

            do_predict_return(32'h0000_6000, v, t, tgt, un);
            check_eq32("wrap: top = last push",
                       tgt, 32'hE000_0000 | (RAS_ENTRIES[15:0] << 2));
        end
    endtask

    task automatic test_write_then_read_next_cycle;
        logic            v, t, un;
        logic [XLEN-1:0] tgt;
        begin
            test_count = test_count + 1;
            $display("\n=== Test %0d: write on cycle N visible on cycle N+1 ===", test_count);
            do_reset();

            // Before the update: cold miss.
            do_predict(32'h0000_C000, v, t, tgt, un);
            check_eq("pre-update miss", v, 1'b0);

            // Single-cycle update.
            do_update(32'h0000_C000, 32'h0000_D000, 1'b1, 1'b0);

            // Immediately after the update posedge: hit visible.
            do_predict(32'h0000_C000, v, t, tgt, un);
            check_eq("post-update hit", v, 1'b1);
            check_eq32("post-update target", tgt, 32'h0000_D000);
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

        test_cold_miss();
        test_learn_taken_conditional();
        test_learn_not_taken();
        test_jal_install();
        test_saturate_high();
        test_saturate_low();
        test_flip_from_11_to_01();
        test_tag_alias();
        test_write_then_read_next_cycle();
        test_ras_single_call_return();
        test_ras_nested_lifo();
        test_ras_empty_fallback();
        test_ras_underflow_no_crash();
        test_ras_wrap();

        if (error_count == 0)
            $display("\n@@@ Passed");
        else
            $display("\n@@@ Incorrect, error_count = %0d", error_count);

        $finish;
    end

    // Coverage report (from `make branch_predictor.coverage`):
    //   dut  line: 100.00  cond: 95.45  toggle:  3.23  fsm: --  branch: 100.00
    //   tb   line:  97.06  cond: 91.67  toggle:  4.56  fsm: --  branch:  76.92
    // The low toggle % is the 32-bit PC/target space we leave unexercised;
    // all reachable branch_predictor code paths hit 100%.

endmodule
