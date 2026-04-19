`include "sys_defs.svh"

module rs #(
    parameter RS_SIZE = `RS_SZ,
    parameter XLEN    = `XLEN,
    parameter TAG_W   = $clog2(`ROB_SZ),
    parameter OP_W    = 8
)(
    input  logic                  clock,
    input  logic                  reset,
    input  logic                  flush, // flush rs in next posedge

    // dispatch side (input of rs module)
    input  logic                  dispatch_valid, // if new entry is coming
    input  logic [OP_W-1:0]       dispatch_op, // op code
    input  logic [TAG_W-1:0]      dispatch_dest_tag, // destination tag

    input  logic                  dispatch_src1_ready, // if source 1 already has value
    input  logic [TAG_W-1:0]      dispatch_src1_tag,
    input  logic [XLEN-1:0]       dispatch_src1_value,

    input  logic                  dispatch_src2_ready, // if source 2 already has value
    input  logic [TAG_W-1:0]      dispatch_src2_tag,
    input  logic [XLEN-1:0]       dispatch_src2_value,

    // Per-entry branch metadata carried through the RS.  Non-branches
    // leave these at 0; the compare / CDB logic gates them on op[5|6].
    // Previously branch_target_buf and branch_funct3_buf lived as shared
    // latches in pipeline.sv; moving them in-RS lets multiple branches be
    // in flight simultaneously.
    //
    // branch_NPC is the return address for JAL/JALR (= dispatch PC + 4).
    // The CDB broadcasts this as cdb_value for uncond branches so any
    // downstream CDB-bypass consumer sees the correct link register value.
    input  logic [2:0]            dispatch_branch_funct3,
    input  logic [XLEN-1:0]       dispatch_branch_target,
    input  logic [XLEN-1:0]       dispatch_branch_NPC,

    output logic                  rs_full, // if rs is full

    // common data bus wakeup
    input  logic                  cdb_valid, // if cdb is valid
    input  logic [TAG_W-1:0]      cdb_tag,
    input  logic [XLEN-1:0]       cdb_value,

    // Early-tag sideband: wakeup-only.  One cycle before a multi-cycle
    // producer drives the CDB it pulses early_cdb_valid with the tag
    // that will retire next cycle.  We flip the registered src*_ready
    // bit on the matching entry; no value is latched from this signal.
    // MUST NOT be read by the issue selector (see rs-issue-loop-fix.md
    // — combinational loop through `_eff`).
    input  logic                  early_cdb_valid,
    input  logic [TAG_W-1:0]      early_cdb_tag,

    // issue side (output of rs module)
    input  logic                  issue_accept, // handshake to another mocule
    output logic                  issue_valid, // if an entry can be issued
    output logic [OP_W-1:0]       issue_op, // opcode
    output logic [TAG_W-1:0]      issue_dest_tag, // destination tag
    output logic [XLEN-1:0]       issue_src1_value, // source 1 value
    output logic [XLEN-1:0]       issue_src2_value, // source 2 value
    output logic [2:0]            issue_branch_funct3,
    output logic [XLEN-1:0]       issue_branch_target,
    output logic [XLEN-1:0]       issue_branch_NPC
);

    typedef struct packed {
        logic                 busy;
        logic [OP_W-1:0]      op;
        logic [TAG_W-1:0]     dest_tag;

        logic                 src1_ready;
        logic [TAG_W-1:0]     src1_tag;
        logic [XLEN-1:0]      src1_value;
        // Set when src1_value actually holds the operand.  Diverges from
        // src1_ready only during the one-cycle ETB window: an early-tag
        // wakeup flips src1_ready=1 but leaves src1_val_present=0 until
        // the real CDB broadcast arrives the next cycle.  The issue
        // value-mux uses this to know when to forward cdb_value instead.
        logic                 src1_val_present;

        logic                 src2_ready;
        logic [TAG_W-1:0]     src2_tag;
        logic [XLEN-1:0]      src2_value;
        logic                 src2_val_present;

        logic [2:0]           branch_funct3;
        logic [XLEN-1:0]      branch_target;
        logic [XLEN-1:0]      branch_NPC;
    } rs_entry_t;

    rs_entry_t entries [RS_SIZE-1:0];
    rs_entry_t next_entries [RS_SIZE-1:0];

    logic [$clog2(RS_SIZE)-1:0] free_idx;
    logic [$clog2(RS_SIZE)-1:0] issue_idx;
    logic                       free_found;
    logic                       issue_found;
    logic                       issue_fire;

    logic [RS_SIZE-1:0] src1_ready_eff;
    logic [RS_SIZE-1:0] src2_ready_eff;

    // 

    // find first free slot
    always_comb begin
        integer i;
        
        free_found = 1'b0;
        free_idx   = '0;
        for (i = 0; i < RS_SIZE; i++) begin
            if (!free_found && !entries[i].busy) begin
                free_found = 1'b1;
                free_idx   = i[$clog2(RS_SIZE)-1:0];
            end
        end
    end

    assign rs_full        = !free_found;

    // effective ready: current ready OR woken up by this cycle's CDB
    always_comb begin
        integer i;
        
        for (i = 0; i < RS_SIZE; i++) begin
            src1_ready_eff[i] = entries[i].src1_ready ||
                                (cdb_valid && entries[i].busy &&
                                 !entries[i].src1_ready &&
                                 (entries[i].src1_tag == cdb_tag));

            src2_ready_eff[i] = entries[i].src2_ready ||
                                (cdb_valid && entries[i].busy &&
                                 !entries[i].src2_ready &&
                                 (entries[i].src2_tag == cdb_tag));
        end
    end

    // pick first ready entry to issue
    //
    // IMPORTANT: this selector reads the REGISTERED `src*_ready` bits.
    // It MUST NOT reference `src*_ready_eff` (combinational CDB bypass)
    // or early_cdb_* — folding either here closes the selector ->
    // cdb_valid -> issue_accept loop documented in
    // doc/rs-issue-loop-fix.md that hung ~15 programs.  ETB flips
    // `src*_ready` through `next_entries` (one cycle later); the
    // selector sees the effect on the ETB+1 cycle, which is the same
    // cycle as the real CDB broadcast that carries the value.
    always_comb begin
        integer i;

        issue_found = 1'b0;
        issue_idx   = '0;
        for (i = 0; i < RS_SIZE; i++) begin
            if (!issue_found &&
                entries[i].busy &&
                entries[i].src1_ready &&
                entries[i].src2_ready) begin
                issue_found = 1'b1;
                issue_idx   = i[$clog2(RS_SIZE)-1:0];
            end
        end
    end

    assign issue_valid = issue_found;
    assign issue_fire  = issue_valid && issue_accept;

    always_comb begin
        issue_op            = '0;
        issue_dest_tag      = '0;
        issue_src1_value    = '0;
        issue_src2_value    = '0;
        issue_branch_funct3 = '0;
        issue_branch_target = '0;
        issue_branch_NPC    = '0;

        if (issue_found) begin
            issue_op            = entries[issue_idx].op;
            issue_dest_tag      = entries[issue_idx].dest_tag;
            issue_branch_funct3 = entries[issue_idx].branch_funct3;
            issue_branch_target = entries[issue_idx].branch_target;
            issue_branch_NPC    = entries[issue_idx].branch_NPC;

            // Value-mux: forward the CDB value on the issue cycle when
            // either (a) the entry is being woken by this cycle's CDB
            // (standard same-cycle bypass, guarded by `!src*_ready` so
            // a stale tag match on an already-resolved entry cannot
            // overwrite a latched value), or (b) the entry's stored
            // value is not yet present — this second arm catches the
            // ETB case, where `src*_ready` was flipped to 1 by the
            // early tag on the prior cycle but the value has not been
            // latched yet.  On an ETB+CDB cycle the producer gating
            // guarantees CDB is broadcasting our matching tag, so
            // `cdb_value` is the correct operand to forward.
            issue_src1_value = ((cdb_valid &&
                                 entries[issue_idx].busy &&
                                 !entries[issue_idx].src1_ready &&
                                 (entries[issue_idx].src1_tag == cdb_tag))
                                || !entries[issue_idx].src1_val_present)
                             ? cdb_value
                             : entries[issue_idx].src1_value;

            issue_src2_value = ((cdb_valid &&
                                 entries[issue_idx].busy &&
                                 !entries[issue_idx].src2_ready &&
                                 (entries[issue_idx].src2_tag == cdb_tag))
                                || !entries[issue_idx].src2_val_present)
                             ? cdb_value
                             : entries[issue_idx].src2_value;
        end
    end

    always_comb begin
        integer i;
        
        next_entries = entries;

        if (flush) begin
            for (i = 0; i < RS_SIZE; i++) begin
                next_entries[i] = '0;
            end
        end else begin
            // CDB wakeup: flips both src*_ready and src*_val_present, and
            // latches the value.  Gated on `!val_present` (not `!ready`)
            // so the CDB can still latch the value on an entry that was
            // already woken by the early tag the prior cycle (ready=1,
            // val_present=0).  ETB wakeup (below) is the weaker form —
            // it only flips src*_ready, leaving val_present=0.
            for (i = 0; i < RS_SIZE; i++) begin
                if (entries[i].busy) begin
                    if (cdb_valid && !entries[i].src1_val_present &&
                        (entries[i].src1_tag == cdb_tag)) begin
                        next_entries[i].src1_ready       = 1'b1;
                        next_entries[i].src1_val_present = 1'b1;
                        next_entries[i].src1_value       = cdb_value;
                    end

                    if (cdb_valid && !entries[i].src2_val_present &&
                        (entries[i].src2_tag == cdb_tag)) begin
                        next_entries[i].src2_ready       = 1'b1;
                        next_entries[i].src2_val_present = 1'b1;
                        next_entries[i].src2_value       = cdb_value;
                    end

                    // Early-tag wakeup: flips src*_ready only.  A later
                    // CDB broadcast on the next cycle will overwrite
                    // val_present=1 via the path above.  Safe to OR with
                    // the CDB path in the same always_comb: if both fire
                    // the same cycle (same tag on CDB and early), the
                    // CDB path runs first and sets val_present=1; this
                    // block's attempt to only set src*_ready is a no-op.
                    if (early_cdb_valid && !entries[i].src1_ready &&
                        (entries[i].src1_tag == early_cdb_tag)) begin
                        next_entries[i].src1_ready = 1'b1;
                    end

                    if (early_cdb_valid && !entries[i].src2_ready &&
                        (entries[i].src2_tag == early_cdb_tag)) begin
                        next_entries[i].src2_ready = 1'b1;
                    end
                end
            end

            // remove issued entry
            if (issue_fire) begin
                next_entries[issue_idx] = '0;
            end

            // insert new dispatched entry.  val_present follows ready at
            // dispatch time: ready=1 implies the value field is populated
            // (either dispatched with an immediate/regfile read, or
            // dispatch-time CDB bypass).
            if (dispatch_valid && free_found) begin
                next_entries[free_idx].busy             = 1'b1;
                next_entries[free_idx].op               = dispatch_op;
                next_entries[free_idx].dest_tag         = dispatch_dest_tag;

                next_entries[free_idx].src1_ready       = dispatch_src1_ready;
                next_entries[free_idx].src1_val_present = dispatch_src1_ready;
                next_entries[free_idx].src1_tag         = dispatch_src1_tag;
                next_entries[free_idx].src1_value       = dispatch_src1_value;

                next_entries[free_idx].src2_ready       = dispatch_src2_ready;
                next_entries[free_idx].src2_val_present = dispatch_src2_ready;
                next_entries[free_idx].src2_tag         = dispatch_src2_tag;
                next_entries[free_idx].src2_value       = dispatch_src2_value;

                next_entries[free_idx].branch_funct3    = dispatch_branch_funct3;
                next_entries[free_idx].branch_target    = dispatch_branch_target;
                next_entries[free_idx].branch_NPC       = dispatch_branch_NPC;
            end
        end
    end

    always_ff @(posedge clock) begin
        integer i;
        
        if (reset) begin
            for (i = 0; i < RS_SIZE; i++) begin
                entries[i] <= '0;
            end
        end else begin
            for (i = 0; i < RS_SIZE; i++) begin
                entries[i] <= next_entries[i];
            end
        end
    end

endmodule
