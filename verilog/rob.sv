`include "sys_defs.svh"

module rob #(
    parameter ROB_SIZE = `ROB_SZ,
    parameter XLEN     = `XLEN,
    parameter TAG_W    = $clog2(`ROB_SZ)
)(
    input  logic       clock,
    input  logic       reset,
    input  logic       flush,   // flush all entries (branch mispredict)

    // ---- Dispatch side ----
    input  logic             dispatch_valid,
    input  logic [4:0]       dispatch_dest_reg,  // architectural dest register (ZERO_REG if no writeback)
    input  logic [XLEN-1:0]  dispatch_NPC,
    input  logic [XLEN-1:0]  dispatch_PC,        // PC of the dispatched instruction (used for branch predictor update)
    input  logic             dispatch_halt,
    input  logic             dispatch_illegal,
    input  logic             dispatch_is_branch,
    input  logic             dispatch_is_uncond_branch,
    input  logic             dispatch_is_store,  // milestone 3: store ops sit in the LSQ until commit

    // Branch prediction carried through the pipeline.  Non-branches leave
    // these at 0 and the commit-time mispredict check ignores them.
    input  logic             dispatch_predicted_taken,
    input  logic [XLEN-1:0]  dispatch_predicted_target,

    output logic             rob_full,
    output logic [TAG_W-1:0] dispatch_tag,       // ROB index assigned to new entry (= current tail)

    // ---- Complete side (CDB broadcast from execution unit) ----
    input  logic             cdb_valid,
    input  logic [TAG_W-1:0] cdb_tag,
    input  logic [XLEN-1:0]  cdb_value,
    input  logic             cdb_take_branch,
    input  logic [XLEN-1:0]  cdb_branch_target,

    // ---- Store-ready sideband from the LSQ ----
    // The CDB only has bandwidth for one ALU/MULT/LOAD broadcast per cycle.
    // To avoid spending it on stores (which carry no register value), the
    // LSQ uses this dedicated port to mark a store entry as ready to commit.
    input  logic             store_done_valid,
    input  logic [TAG_W-1:0] store_done_tag,

    // ---- Commit side (in-order retirement at head) ----
    output logic             commit_valid,
    output logic [TAG_W-1:0] commit_tag,         // milestone 3: head index, for LSQ store release
    output logic             commit_is_store,    // milestone 3: tells LSQ "this commit is a store"
    output logic [4:0]       commit_dest_reg,
    output logic [XLEN-1:0]  commit_value,
    output logic [XLEN-1:0]  commit_NPC,
    output logic             commit_halt,
    output logic             commit_illegal,
    output logic             commit_is_branch,
    output logic             commit_take_branch,
    output logic [XLEN-1:0]  commit_branch_target,
    output logic             commit_is_uncond_branch, // needed by predictor update
    output logic [XLEN-1:0]  commit_branch_PC,        // PC of the committing branch

    // Mispredict sideband.  Pulses for exactly one cycle when a committing
    // branch disagrees with its prediction; drives pipeline flush + PC
    // redirect.  Also asserts on correctly-predicted taken branches whose
    // stored BTB target has decayed to the wrong value.
    output logic             mispredict_valid,
    output logic [XLEN-1:0]  mispredict_target,

    // ---- RAT queries: 2 source registers per dispatched instruction ----
    // If pending=1 and ready=1: value is available in ROB now
    // If pending=1 and ready=0: must wait for cdb_tag == returned tag
    // If pending=0: no ROB entry owns this register; read from regfile
    input  logic [4:0]       query1_arch_reg,
    output logic             query1_pending,
    output logic             query1_ready,
    output logic [TAG_W-1:0] query1_tag,
    output logic [XLEN-1:0]  query1_value,

    input  logic [4:0]       query2_arch_reg,
    output logic             query2_pending,
    output logic             query2_ready,
    output logic [TAG_W-1:0] query2_tag,
    output logic [XLEN-1:0]  query2_value
);

    // -------------------------------------------------------
    // Entry definition
    // -------------------------------------------------------
    typedef struct packed {
        logic            busy;
        logic            ready;         // execution complete, value valid
        logic            is_store;      // store entries take their data path through the LSQ
        logic [4:0]      dest_reg;
        logic [XLEN-1:0] value;
        logic [XLEN-1:0] NPC;
        logic            halt;
        logic            illegal;
        logic            is_branch;
        logic            take_branch;
        logic [XLEN-1:0] branch_target;
        // Prediction carried from the fetch-time BRANCH_PRED_PACKET so that
        // commit can compare predicted vs. actual and drive the mispredict
        // sideband.  Non-branch entries leave these at 0.
        logic            predicted_taken;
        logic [XLEN-1:0] predicted_target;
        logic            is_uncond_branch; // remembered so the predictor knows JAL vs. Bxx
        logic [XLEN-1:0] branch_PC;        // committing PC, needed for BTB/BHT update
    } rob_entry_t;

    rob_entry_t entries      [ROB_SIZE-1:0];
    rob_entry_t next_entries [ROB_SIZE-1:0];

    // -------------------------------------------------------
    // Register Alias Table (RAT)
    //   rat_busy[r] = 1  : ROB entry rat_tag[r] will write arch reg r
    //   rat_busy[r] = 0  : arch reg r is up-to-date in regfile
    // -------------------------------------------------------
    logic             rat_busy      [32];
    logic [TAG_W-1:0] rat_tag       [32];
    logic             next_rat_busy [32];
    logic [TAG_W-1:0] next_rat_tag  [32];

    // -------------------------------------------------------
    // Head / tail / count
    // -------------------------------------------------------
    logic [TAG_W-1:0] head,       tail;
    logic [TAG_W-1:0] next_head,  next_tail;
    logic [TAG_W:0]   count,      next_count;  // one extra bit for full/empty

    // -------------------------------------------------------
    // Combinational outputs
    // -------------------------------------------------------
    assign rob_full     = (count == ROB_SIZE[TAG_W:0]);
    assign dispatch_tag = tail;   // tag stamped on the instruction being dispatched

    assign commit_valid         = entries[head].busy && entries[head].ready;
    assign commit_tag           = head;
    assign commit_is_store      = entries[head].is_store;
    assign commit_dest_reg      = entries[head].dest_reg;
    // JAL / JALR write the return address (PC+4 = NPC) into rd.  The CDB
    // value for branches is always 0, so the ROB overrides the commit
    // value with the stored NPC when this entry is a branch with a
    // non-zero destination (which is exactly the JAL/JALR case -
    // conditional branches always have dest_reg=0).
    assign commit_value         = (entries[head].is_branch && entries[head].dest_reg != 5'd0)
                                  ? entries[head].NPC
                                  : entries[head].value;
    assign commit_NPC           = entries[head].NPC;
    assign commit_halt          = entries[head].halt;
    assign commit_illegal       = entries[head].illegal;
    assign commit_is_branch        = entries[head].is_branch;
    assign commit_take_branch      = entries[head].take_branch;
    assign commit_branch_target    = entries[head].branch_target;
    assign commit_is_uncond_branch = entries[head].is_uncond_branch;
    assign commit_branch_PC        = entries[head].branch_PC;

    // Commit-time mispredict detection.
    //   * direction miss: predicted != actual
    //   * target miss:    actual taken but BTB target != resolved target
    // For a not-taken actual outcome the correct next PC is NPC (= PC + 4).
    logic mispredict_int;
    assign mispredict_int = commit_valid && entries[head].is_branch &&
                            ((entries[head].predicted_taken ^ entries[head].take_branch) ||
                             (entries[head].take_branch &&
                              (entries[head].predicted_target != entries[head].branch_target)));
    assign mispredict_valid  = mispredict_int;
    assign mispredict_target = entries[head].take_branch
                               ? entries[head].branch_target
                               : entries[head].NPC;

    // -------------------------------------------------------
    // RAT query logic (with same-cycle CDB bypass)
    // -------------------------------------------------------
    logic [TAG_W-1:0] q1_tag_int, q2_tag_int;
    assign q1_tag_int = rat_tag[query1_arch_reg];
    assign q2_tag_int = rat_tag[query2_arch_reg];

    always_comb begin
        query1_pending = rat_busy[query1_arch_reg];
        query1_tag     = q1_tag_int;
        if (rat_busy[query1_arch_reg]) begin
            // CDB bypass: entry completing this very cycle
            if (cdb_valid && (q1_tag_int == cdb_tag) && !entries[q1_tag_int].ready) begin
                query1_ready = 1'b1;
                query1_value = cdb_value;
            end else begin
                query1_ready = entries[q1_tag_int].ready;
                query1_value = entries[q1_tag_int].value;
            end
        end else begin
            query1_ready = 1'b0;
            query1_value = '0;
        end
    end

    always_comb begin
        query2_pending = rat_busy[query2_arch_reg];
        query2_tag     = q2_tag_int;
        if (rat_busy[query2_arch_reg]) begin
            if (cdb_valid && (q2_tag_int == cdb_tag) && !entries[q2_tag_int].ready) begin
                query2_ready = 1'b1;
                query2_value = cdb_value;
            end else begin
                query2_ready = entries[q2_tag_int].ready;
                query2_value = entries[q2_tag_int].value;
            end
        end else begin
            query2_ready = 1'b0;
            query2_value = '0;
        end
    end

    // -------------------------------------------------------
    // Next-state combinational logic
    // Priority: flush > CDB complete / store-done > commit > dispatch
    // -------------------------------------------------------
    always_comb begin
        integer i;

        next_entries = entries;
        next_head    = head;
        next_tail    = tail;
        next_count   = count;
        for (i = 0; i < 32; i++) begin
            next_rat_busy[i] = rat_busy[i];
            next_rat_tag [i] = rat_tag [i];
        end

        if (flush) begin
            for (i = 0; i < ROB_SIZE; i++)
                next_entries[i] = '0;
            for (i = 0; i < 32; i++) begin
                next_rat_busy[i] = 1'b0;
                next_rat_tag [i] = '0;
            end
            next_head  = '0;
            next_tail  = '0;
            next_count = '0;

        end else begin

            // 1) CDB complete: mark entry done, store value and branch info
            if (cdb_valid) begin
                next_entries[cdb_tag].ready         = 1'b1;
                next_entries[cdb_tag].value         = cdb_value;
                next_entries[cdb_tag].take_branch   = cdb_take_branch;
                next_entries[cdb_tag].branch_target = cdb_branch_target;
            end

            // 1b) Store-done sideband: stores have no register value, so the LSQ
            //     marks them ready via this dedicated path instead of competing
            //     for the CDB.  Idempotent if asserted across multiple cycles.
            if (store_done_valid) begin
                next_entries[store_done_tag].ready = 1'b1;
                next_entries[store_done_tag].value = '0;
            end

            // 2) Commit: retire head entry if it is ready
            if (commit_valid) begin
                // Clear RAT only if this entry is still the "latest" writer
                if (entries[head].dest_reg != 5'd0 &&
                    rat_busy[entries[head].dest_reg] &&
                    rat_tag [entries[head].dest_reg] == head) begin
                    next_rat_busy[entries[head].dest_reg] = 1'b0;
                end
                next_entries[head] = '0;
                next_head  = (head == TAG_W'(ROB_SIZE - 1)) ? '0 : head + 1'b1;
                next_count = next_count - 1'b1;
            end

            // 3) Dispatch: allocate tail (guard against full this cycle)
            if (dispatch_valid && !rob_full) begin
                next_entries[tail].busy             = 1'b1;
                next_entries[tail].ready            = 1'b0;
                next_entries[tail].is_store         = dispatch_is_store;
                next_entries[tail].dest_reg         = dispatch_dest_reg;
                next_entries[tail].NPC              = dispatch_NPC;
                next_entries[tail].halt             = dispatch_halt;
                next_entries[tail].illegal          = dispatch_illegal;
                next_entries[tail].is_branch        = dispatch_is_branch;
                next_entries[tail].is_uncond_branch = dispatch_is_uncond_branch;
                next_entries[tail].branch_PC        = dispatch_PC;
                next_entries[tail].take_branch      = 1'b0;
                next_entries[tail].value            = '0;
                next_entries[tail].branch_target    = '0;
                next_entries[tail].predicted_taken  = dispatch_predicted_taken;
                next_entries[tail].predicted_target = dispatch_predicted_target;
                next_tail  = (tail == TAG_W'(ROB_SIZE - 1)) ? '0 : tail + 1'b1;
                next_count = next_count + 1'b1;
                // Update RAT (never track x0)
                if (dispatch_dest_reg != 5'd0) begin
                    next_rat_busy[dispatch_dest_reg] = 1'b1;
                    next_rat_tag [dispatch_dest_reg] = tail;
                end
            end

        end
    end

    // -------------------------------------------------------
    // Sequential update
    // -------------------------------------------------------
    always_ff @(posedge clock) begin
        integer i;
        if (reset) begin
            for (i = 0; i < ROB_SIZE; i++)
                entries[i] <= '0;
            for (i = 0; i < 32; i++) begin
                rat_busy[i] <= 1'b0;
                rat_tag [i] <= '0;
            end
            head  <= '0;
            tail  <= '0;
            count <= '0;
        end else begin
            entries <= next_entries;
            for (i = 0; i < 32; i++) begin
                rat_busy[i] <= next_rat_busy[i];
                rat_tag [i] <= next_rat_tag [i];
            end
            head  <= next_head;
            tail  <= next_tail;
            count <= next_count;
        end
    end

endmodule // rob
