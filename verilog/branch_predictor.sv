/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  branch_predictor.sv                                 //
//                                                                     //
//  Description :  BTB + bimodal direction predictor for the P6 core.  //
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
//                 Predict port: combinational lookup on the current   //
//                 fetch PC, returns {valid, taken, target, is_uncond}.//
//                                                                     //
//                 Update port: single-cycle registered write on the   //
//                 cycle after a branch commits, driven by the ROB.    //
//                 BTB entry is written with {1, tag(PC), target,      //
//                 is_uncond}; BHT counter moves one saturating step   //
//                 toward the actual direction.                        //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module branch_predictor #(
    parameter BTB_ENTRIES = `BTB_ENTRIES,
    parameter BHT_ENTRIES = `BHT_ENTRIES,
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

    // ------------------------------------------------------------------
    // Index / tag helpers.  Both tables ignore PC[1:0] (instructions are
    // 4-byte aligned in RV32IM), so the LSB of the index is PC[2].
    // ------------------------------------------------------------------
    function automatic logic [BTB_IDX_W-1:0] btb_idx(input logic [XLEN-1:0] pc);
        btb_idx = pc[BTB_IDX_W+1 : 2];
    endfunction

    function automatic logic [BHT_IDX_W-1:0] bht_idx(input logic [XLEN-1:0] pc);
        bht_idx = pc[BHT_IDX_W+1 : 2];
    endfunction

    function automatic logic [BTB_TAG_W-1:0] btb_tag(input logic [XLEN-1:0] pc);
        btb_tag = pc[XLEN-1 : BTB_IDX_W+2];
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

    // ------------------------------------------------------------------
    // Combinational prediction lookup
    // ------------------------------------------------------------------
    logic [BTB_IDX_W-1:0] pred_btb_i;
    logic [BHT_IDX_W-1:0] pred_bht_i;
    logic [BTB_TAG_W-1:0] pred_tag;
    logic                 btb_hit;
    logic [1:0]           counter;

    assign pred_btb_i = btb_idx(predict_PC);
    assign pred_bht_i = bht_idx(predict_PC);
    assign pred_tag   = btb_tag(predict_PC);

    assign btb_hit = btb[pred_btb_i].valid && (btb[pred_btb_i].tag == pred_tag);
    assign counter = bht[pred_bht_i];

    assign pred_valid     = btb_hit;
    assign pred_is_uncond = btb_hit && btb[pred_btb_i].is_uncond;
    assign pred_taken     = btb_hit && (btb[pred_btb_i].is_uncond || counter[1]);
    assign pred_target    = btb[pred_btb_i].target;

    // ------------------------------------------------------------------
    // Registered update.  A single update per committing branch:
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
    assign up_bht_i       = bht_idx(update_PC);
    assign up_tag         = btb_tag(update_PC);
    assign up_counter_cur = bht[up_bht_i];

    always_comb begin
        if (update_taken)
            up_counter_nxt = (up_counter_cur == 2'b11) ? 2'b11 : up_counter_cur + 2'b01;
        else
            up_counter_nxt = (up_counter_cur == 2'b00) ? 2'b00 : up_counter_cur - 2'b01;
    end

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
        end else if (update_valid) begin
            btb[up_btb_i].valid     <= 1'b1;
            btb[up_btb_i].tag       <= up_tag;
            btb[up_btb_i].target    <= update_target;
            btb[up_btb_i].is_uncond <= update_is_uncond;
            bht[up_bht_i]           <= up_counter_nxt;
        end
    end

endmodule
