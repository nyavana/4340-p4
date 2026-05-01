/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  branch_predictor.sv                                 //
//                                                                     //
//  Description :  BTB + bimodal direction predictor + RAS for the     //
//                 P6 core.                                            //
//                                                                     //
//                 BTB: direct-mapped, `BTB_ENTRIES` slots, each       //
//                 {valid, tag, target, is_uncond}, indexed by         //
//                 PC[log2(BTB_ENTRIES)+1:2] with the upper PC bits    //
//                 forming the tag.                                    //
//                                                                     //
//                 BHT: direct-mapped, `BHT_ENTRIES` 2-bit saturating  //
//                 counters indexed the same way (but with its own     //
//                 index width).  Reset state is 2'b01 (weakly         //
//                 not-taken).  Counters predict taken on states       //
//                 2'b10 / 2'b11.                                      //
//                                                                     //
//                 RAS: `RAS_ENTRIES`-deep circular stack.             //
//                 ras_push_en writes the link PC; ras_pop_en rewinds  //
//                 SP.  When predict_is_return and the stack is        //
//                 non-empty, pred_target comes from ras[top] and      //
//                 pred_valid/taken are forced high.                   //
//                                                                     //
//                 Predict port: combinational lookup on the current   //
//                 fetch PC, returns {valid, taken, target, is_uncond}.//
//                                                                     //
//                 Update port: single-cycle registered write on the   //
//                 cycle after a branch commits, driven by the ROB.    //
//                 BTB entry is written with {1, tag(PC), target,      //
//                 is_uncond}; BHT counter moves one saturating step   //
//                 toward the actual direction.                        //
//                                                                     //
//        Others : gshare implemented. 
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module branch_predictor #(
    parameter BTB_ENTRIES = `BTB_ENTRIES,
    parameter BHT_ENTRIES = `BHT_ENTRIES,
    parameter RAS_ENTRIES = `RAS_ENTRIES,
    parameter XLEN        = `XLEN
)(
    input  logic              clock,
    input  logic              reset,

    // ---- Prediction port (combinational, read at fetch) ----
    input  logic [XLEN-1:0]   predict_PC,
    output logic              pred_valid,
    output logic              pred_taken,
    output logic [XLEN-1:0]   pred_target,
    output logic              pred_is_uncond,

    // ---- RAS hints (push/pop gated with dispatch_fire externally) ----
    input  logic              predict_is_return,
    input  logic [XLEN-1:0]   predict_link_pc,
    input  logic              ras_push_en,
    input  logic              ras_pop_en,

    // ---- Update port (registered, one per committing branch) ----
    input  logic              update_valid,
    input  logic [XLEN-1:0]   update_PC,
    input  logic [XLEN-1:0]   update_target,
    input  logic              update_taken,
    input  logic              update_is_uncond
);

    // ------------------------------------------------------------------
    // Derived widths
    // ------------------------------------------------------------------
    localparam BTB_IDX_W = $clog2(BTB_ENTRIES);
    localparam BHT_IDX_W = $clog2(BHT_ENTRIES);
    localparam BTB_TAG_W = XLEN - 2 - BTB_IDX_W;
    localparam RAS_IDX_W = $clog2(RAS_ENTRIES);

    // ------------------------------------------------------------------
    // Index / tag helpers.  Both tables ignore PC[1:0] (instructions are
    // 4-byte aligned in RV32IM), so the LSB of the index is PC[2].
    // ------------------------------------------------------------------
    function automatic logic [BTB_IDX_W-1:0] btb_idx(input logic [XLEN-1:0] pc);
        btb_idx = pc[BTB_IDX_W+1 : 2];
    endfunction

    function automatic logic [BTB_TAG_W-1:0] btb_tag(input logic [XLEN-1:0] pc);
        btb_tag = pc[XLEN-1 : BTB_IDX_W+2];
    endfunction
    
    function automatic logic [BHT_IDX_W-1:0] bht_pc_bits(input logic [XLEN-1:0] pc);
        bht_pc_bits = pc[BHT_IDX_W+1 : 2];
    endfunction

    function automatic logic [BHT_IDX_W-1:0] bht_idx(
        input logic [XLEN-1:0] pc,
        input logic [BHT_IDX_W-1:0] hist
    );
        bht_idx = bht_pc_bits(pc) ^ hist;
    endfunction

    // ------------------------------------------------------------------
    // BTB storage
    // ------------------------------------------------------------------
    typedef struct packed {
        logic                 valid;
        logic                 is_uncond;
        logic [BTB_TAG_W-1:0] tag;
        logic [XLEN-1:0]      target;
    } btb_entry_t;

    btb_entry_t btb [BTB_ENTRIES-1:0];

    // ------------------------------------------------------------------
    // BHT storage: 2-bit saturating counters.  2'b00 / 2'b01 = not-taken,
    // 2'b10 / 2'b11 = taken.  Reset state is 2'b01 (weakly not-taken) to
    // bias cold forward branches toward fall-through.
    // ------------------------------------------------------------------
    logic [1:0] bht [BHT_ENTRIES-1:0];
    
    localparam GHR_W = BHT_IDX_W; // full-width gshare: GHR matches BHT index width

    logic [GHR_W-1:0]     ghr;
    logic [BHT_IDX_W-1:0] ghr_ext;

    assign ghr_ext = ghr;

    // ------------------------------------------------------------------
    // RAS storage.  ras_sp = next-push slot (top = ras_sp - 1).
    // ras_count tracks depth, saturating at RAS_ENTRIES.
    // ------------------------------------------------------------------
    logic [XLEN-1:0]     ras       [RAS_ENTRIES-1:0];
    logic [RAS_IDX_W-1:0] ras_sp;
    logic [RAS_IDX_W:0]   ras_count;

    wire [RAS_IDX_W-1:0] ras_top_i = ras_sp - {{(RAS_IDX_W-1){1'b0}}, 1'b1};
    wire                 ras_has_entry = (ras_count != '0);

    // ------------------------------------------------------------------
    // Combinational BTB/BHT lookup
    // ------------------------------------------------------------------
    logic [BTB_IDX_W-1:0] pred_btb_i;
    logic [BHT_IDX_W-1:0] pred_bht_i;
    logic [BTB_TAG_W-1:0] pred_tag;
    logic                 btb_hit;
    logic [1:0]           counter;

    assign pred_btb_i = btb_idx(predict_PC);
    assign pred_bht_i = bht_idx(predict_PC, ghr_ext);
    assign pred_tag   = btb_tag(predict_PC);

    assign btb_hit = btb[pred_btb_i].valid && (btb[pred_btb_i].tag == pred_tag);
    assign counter = bht[pred_bht_i];

    // BTB-sourced baseline prediction
    logic              btb_pred_valid;
    logic              btb_pred_taken;
    logic [XLEN-1:0]   btb_pred_target;
    logic              btb_pred_is_uncond;

    assign btb_pred_valid     = btb_hit;
    assign btb_pred_is_uncond = btb_hit && btb[pred_btb_i].is_uncond;
    assign btb_pred_taken     = btb_hit && (btb[pred_btb_i].is_uncond || counter[1]);
    assign btb_pred_target    = btb[pred_btb_i].target;

    // RAS override: on a return with non-empty stack, use ras[top].
    wire ras_override = predict_is_return && ras_has_entry;

    assign pred_valid     = ras_override ? 1'b1 : btb_pred_valid;
    assign pred_taken     = ras_override ? 1'b1 : btb_pred_taken;
    assign pred_is_uncond = ras_override ? 1'b1 : btb_pred_is_uncond;
    assign pred_target    = ras_override ? ras[ras_top_i] : btb_pred_target;

    // ------------------------------------------------------------------
    // Registered BTB/BHT update.  A single update per committing branch:
    //   BTB: write {valid=1, tag, target, is_uncond} on any update_valid.
    //        (Conservative: even a not-taken conditional rewrites the
    //        entry; target is what the branch resolved to -- PC+4 for a
    //        not-taken conditional -- so the BTB stays harmless.)
    //   BHT: saturating increment on taken, decrement on not-taken.
    //
    // Aliasing is accepted: two different PCs that hash to the same
    // BTB index fight for the slot, and two different PCs that hash to
    // the same BHT index share a counter.  Both are standard bimodal
    // baseline behavior; the cost is accuracy, not correctness.
    // ------------------------------------------------------------------
    logic [BTB_IDX_W-1:0] up_btb_i;
    logic [BHT_IDX_W-1:0] up_bht_i;
    logic [BTB_TAG_W-1:0] up_tag;
    logic [1:0]           up_counter_cur;
    logic [1:0]           up_counter_nxt;

    assign up_btb_i       = btb_idx(update_PC);
    assign up_bht_i       = bht_idx(update_PC, ghr_ext);
    assign up_tag         = btb_tag(update_PC);
    assign up_counter_cur = bht[up_bht_i];

    always_comb begin
        if (update_taken)
            up_counter_nxt = (up_counter_cur == 2'b11) ? 2'b11 : up_counter_cur + 2'b01;
        else
            up_counter_nxt = (up_counter_cur == 2'b00) ? 2'b00 : up_counter_cur - 2'b01;
    end

    // ------------------------------------------------------------------
    // RAS update.  Simultaneous push+pop pushes without popping.
    // No rollback on mispredict (speculative-only state).
    // ------------------------------------------------------------------
    integer i;
    always_ff @(posedge clock) begin
        if (reset) begin
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb[i].valid     <= 1'b0;
                btb[i].is_uncond <= 1'b0;
                btb[i].tag       <= '0;
                btb[i].target    <= '0;
            end
            for (i = 0; i < BHT_ENTRIES; i = i + 1)
                bht[i] <= 2'b01;
            ghr <= '0;
            for (i = 0; i < RAS_ENTRIES; i = i + 1)
                ras[i] <= '0;
            ras_sp    <= '0;
            ras_count <= '0;
        end else begin
            if (update_valid) begin
                btb[up_btb_i].valid     <= 1'b1;
                btb[up_btb_i].tag       <= up_tag;
                btb[up_btb_i].target    <= update_target;
                btb[up_btb_i].is_uncond <= update_is_uncond;
                if (!update_is_uncond) begin
                    bht[up_bht_i] <= up_counter_nxt;
                    ghr           <= {ghr[GHR_W-2:0], update_taken};
                end
            end

            if (ras_push_en) begin
                ras[ras_sp] <= predict_link_pc;
                ras_sp      <= ras_sp + {{(RAS_IDX_W-1){1'b0}}, 1'b1};
                if (!ras_pop_en && ras_count != RAS_ENTRIES)
                    ras_count <= ras_count + 1'b1;
            end else if (ras_pop_en) begin
                if (ras_has_entry) begin
                    ras_sp    <= ras_sp - {{(RAS_IDX_W-1){1'b0}}, 1'b1};
                    ras_count <= ras_count - 1'b1;
                end
            end
        end
    end

endmodule

