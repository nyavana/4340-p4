`include "sys_defs.svh"

module rob #(
    parameter ROB_SIZE = `ROB_SZ,
    parameter XLEN     = `XLEN,
    parameter TAG_W    = $clog2(`ROB_SZ)
)(
    input  logic       clock,
    input  logic       reset,
    input  logic       flush,

    // ---- Dispatch side: up to 2 allocations per cycle ----
    input  logic [1:0]             dispatch_valid,
    input  logic [4:0]             dispatch_dest_reg [2],
    input  logic [XLEN-1:0]        dispatch_NPC      [2],
    input  logic [XLEN-1:0]        dispatch_PC       [2],
    input  logic [1:0]             dispatch_halt,
    input  logic [1:0]             dispatch_illegal,
    input  logic [1:0]             dispatch_is_branch,
    input  logic [1:0]             dispatch_is_uncond_branch,
    input  logic [1:0]             dispatch_is_store,
    input  logic [1:0]             dispatch_predicted_taken,
    input  logic [XLEN-1:0]        dispatch_predicted_target [2],

    output logic                   rob_full,
    output logic                   rob_almost_full,
    output logic [TAG_W-1:0]       dispatch_tag [2],

    // ---- Completion side: up to 2 broadcasts per cycle ----
    input  logic [1:0]             cdb_valid,
    input  logic [TAG_W-1:0]       cdb_tag   [2],
    input  logic [XLEN-1:0]        cdb_value [2],
    input  logic [1:0]             cdb_take_branch,
    input  logic [XLEN-1:0]        cdb_branch_target [2],

    // ---- Store ready sideband ----
    input  logic [1:0]             store_done_valid,
    input  logic [TAG_W-1:0]       store_done_tag [2],

    // ---- Commit side: up to 2 in-order commits per cycle ----
    output logic [1:0]             commit_valid,
    output logic [TAG_W-1:0]       commit_tag      [2],
    output logic [1:0]             commit_is_store,
    output logic [4:0]             commit_dest_reg [2],
    output logic [XLEN-1:0]        commit_value    [2],
    output logic [XLEN-1:0]        commit_NPC      [2],
    output logic [1:0]             commit_halt,
    output logic [1:0]             commit_illegal,
    output logic [1:0]             commit_is_branch,
    output logic [1:0]             commit_take_branch,
    output logic [XLEN-1:0]        commit_branch_target [2],
    output logic [1:0]             commit_is_uncond_branch,
    output logic [XLEN-1:0]        commit_branch_PC [2],

    output logic                   mispredict_valid,
    output logic [XLEN-1:0]        mispredict_target,

    input  logic [4:0]             query1_arch_reg,
    output logic                   query1_pending,
    output logic                   query1_ready,
    output logic [TAG_W-1:0]       query1_tag,
    output logic [XLEN-1:0]        query1_value,

    input  logic [4:0]             query2_arch_reg,
    output logic                   query2_pending,
    output logic                   query2_ready,
    output logic [TAG_W-1:0]       query2_tag,
    output logic [XLEN-1:0]        query2_value,

    input  logic [4:0]             query3_arch_reg,
    output logic                   query3_pending,
    output logic                   query3_ready,
    output logic [TAG_W-1:0]       query3_tag,
    output logic [XLEN-1:0]        query3_value,

    input  logic [4:0]             query4_arch_reg,
    output logic                   query4_pending,
    output logic                   query4_ready,
    output logic [TAG_W-1:0]       query4_tag,
    output logic [XLEN-1:0]        query4_value
);

    typedef struct packed {
        logic            busy;
        logic            ready;
        logic            is_store;
        logic [4:0]      dest_reg;
        logic [XLEN-1:0] value;
        logic [XLEN-1:0] NPC;
        logic            halt;
        logic            illegal;
        logic            is_branch;
        logic            take_branch;
        logic [XLEN-1:0] branch_target;
        logic            predicted_taken;
        logic [XLEN-1:0] predicted_target;
        logic            is_uncond_branch;
        logic [XLEN-1:0] branch_PC;
    } rob_entry_t;

    rob_entry_t entries      [ROB_SIZE-1:0];
    rob_entry_t next_entries [ROB_SIZE-1:0];

    logic             rat_busy      [32];
    logic [TAG_W-1:0] rat_tag       [32];
    logic             next_rat_busy [32];
    logic [TAG_W-1:0] next_rat_tag  [32];

    logic [TAG_W-1:0] head, next_head;
    logic [TAG_W-1:0] tail, next_tail;
    logic [TAG_W:0]   count, next_count;

    logic [TAG_W-1:0] head1;
    assign head1 = (head == ROB_SIZE-1) ? '0 : head + 1'b1;

    function automatic [TAG_W-1:0] bump_tag(input [TAG_W-1:0] tag, input integer amt);
        automatic integer tmp;
        begin
            tmp = tag + amt;
            if (tmp >= ROB_SIZE)
                tmp = tmp - ROB_SIZE;
            bump_tag = TAG_W'(tmp);
        end
    endfunction

    logic head0_valid, head1_valid;
    logic head0_mispredict, head1_mispredict;

    assign rob_full        = (count == ROB_SIZE[TAG_W:0]);
    assign rob_almost_full = (count >= ROB_SIZE-1);
    assign dispatch_tag[0] = tail;
    assign dispatch_tag[1] = bump_tag(tail, 1);

    assign head0_valid = entries[head].busy && entries[head].ready;
    assign head1_valid = head0_valid && entries[head1].busy && entries[head1].ready;

    assign head0_mispredict = head0_valid && entries[head].is_branch &&
                              ((entries[head].predicted_taken ^ entries[head].take_branch) ||
                               (entries[head].take_branch &&
                                (entries[head].predicted_target != entries[head].branch_target)));

    assign head1_mispredict = head1_valid && entries[head1].is_branch &&
                              ((entries[head1].predicted_taken ^ entries[head1].take_branch) ||
                               (entries[head1].take_branch &&
                                (entries[head1].predicted_target != entries[head1].branch_target)));

    assign commit_valid[0] = head0_valid;
    assign commit_valid[1] = head1_valid && !head0_mispredict && !head1_mispredict &&
                         !entries[head].halt && !entries[head].illegal;

    assign commit_tag[0]   = head;
    assign commit_tag[1]   = head1;

    genvar gi;
    generate
        for (gi = 0; gi < 2; gi++) begin : GEN_COMMIT_OUT
            wire [TAG_W-1:0] ctag = (gi == 0) ? head : head1;
            assign commit_is_store[gi]         = entries[ctag].is_store;
            assign commit_dest_reg[gi]         = entries[ctag].dest_reg;
            assign commit_value[gi]            = (entries[ctag].is_branch && entries[ctag].dest_reg != 5'd0)
                                                 ? entries[ctag].NPC : entries[ctag].value;
            assign commit_NPC[gi]              = entries[ctag].NPC;
            assign commit_halt[gi]             = entries[ctag].halt;
            assign commit_illegal[gi]          = entries[ctag].illegal;
            assign commit_is_branch[gi]        = entries[ctag].is_branch;
            assign commit_take_branch[gi]      = entries[ctag].take_branch;
            assign commit_branch_target[gi]    = entries[ctag].branch_target;
            assign commit_is_uncond_branch[gi] = entries[ctag].is_uncond_branch;
            assign commit_branch_PC[gi]        = entries[ctag].branch_PC;
        end
    endgenerate

    assign mispredict_valid  = head0_mispredict;
    assign mispredict_target = entries[head].take_branch ? entries[head].branch_target : entries[head].NPC;

    always_comb begin
        query1_pending = rat_busy[query1_arch_reg];
        query1_tag     = rat_tag[query1_arch_reg];
        query1_ready   = 1'b0;
        query1_value   = '0;

        if (rat_busy[query1_arch_reg]) begin
            query1_ready = entries[query1_tag].ready;
            query1_value = entries[query1_tag].value;
            if (cdb_valid[0] && (query1_tag == cdb_tag[0]) && !entries[query1_tag].ready) begin
                query1_ready = 1'b1;
                query1_value = cdb_value[0];
            end
            if (cdb_valid[1] && (query1_tag == cdb_tag[1]) && !entries[query1_tag].ready) begin
                query1_ready = 1'b1;
                query1_value = cdb_value[1];
            end
        end
    end

    always_comb begin
        query2_pending = rat_busy[query2_arch_reg];
        query2_tag     = rat_tag[query2_arch_reg];
        query2_ready   = 1'b0;
        query2_value   = '0;

        if (rat_busy[query2_arch_reg]) begin
            query2_ready = entries[query2_tag].ready;
            query2_value = entries[query2_tag].value;
            if (cdb_valid[0] && (query2_tag == cdb_tag[0]) && !entries[query2_tag].ready) begin
                query2_ready = 1'b1;
                query2_value = cdb_value[0];
            end
            if (cdb_valid[1] && (query2_tag == cdb_tag[1]) && !entries[query2_tag].ready) begin
                query2_ready = 1'b1;
                query2_value = cdb_value[1];
            end
        end
    end

    always_comb begin
        query3_pending = rat_busy[query3_arch_reg];
        query3_tag     = rat_tag[query3_arch_reg];
        query3_ready   = 1'b0;
        query3_value   = '0;

        if (rat_busy[query3_arch_reg]) begin
            query3_ready = entries[query3_tag].ready;
            query3_value = entries[query3_tag].value;
            if (cdb_valid[0] && (query3_tag == cdb_tag[0]) && !entries[query3_tag].ready) begin
                query3_ready = 1'b1;
                query3_value = cdb_value[0];
            end
            if (cdb_valid[1] && (query3_tag == cdb_tag[1]) && !entries[query3_tag].ready) begin
                query3_ready = 1'b1;
                query3_value = cdb_value[1];
            end
        end
    end

    always_comb begin
        query4_pending = rat_busy[query4_arch_reg];
        query4_tag     = rat_tag[query4_arch_reg];
        query4_ready   = 1'b0;
        query4_value   = '0;

        if (rat_busy[query4_arch_reg]) begin
            query4_ready = entries[query4_tag].ready;
            query4_value = entries[query4_tag].value;
            if (cdb_valid[0] && (query4_tag == cdb_tag[0]) && !entries[query4_tag].ready) begin
                query4_ready = 1'b1;
                query4_value = cdb_value[0];
            end
            if (cdb_valid[1] && (query4_tag == cdb_tag[1]) && !entries[query4_tag].ready) begin
                query4_ready = 1'b1;
                query4_value = cdb_value[1];
            end
        end
    end

    always_comb begin
        integer i;
        integer allocs;
        integer commits;

        next_entries = entries;
        for (i = 0; i < 32; i++) begin
            next_rat_busy[i] = rat_busy[i];
            next_rat_tag[i]  = rat_tag[i];
        end
        next_head  = head;
        next_tail  = tail;
        next_count = count;

        if (flush) begin
            for (i = 0; i < ROB_SIZE; i++)
                next_entries[i] = '0;
            for (i = 0; i < 32; i++) begin
                next_rat_busy[i] = 1'b0;
                next_rat_tag[i]  = '0;
            end
            next_head  = '0;
            next_tail  = '0;
            next_count = '0;
        end else begin
            for (i = 0; i < 2; i++) begin
                if (cdb_valid[i]) begin
                    next_entries[cdb_tag[i]].ready         = 1'b1;
                    next_entries[cdb_tag[i]].value         = cdb_value[i];
                    next_entries[cdb_tag[i]].take_branch   = cdb_take_branch[i];
                    next_entries[cdb_tag[i]].branch_target = cdb_branch_target[i];
                end
                if (store_done_valid[i]) begin
                    next_entries[store_done_tag[i]].ready = 1'b1;
                end
            end

            commits = 0;
            if (commit_valid[0]) begin
                if (entries[head].dest_reg != `ZERO_REG && rat_busy[entries[head].dest_reg] && rat_tag[entries[head].dest_reg] == head)
                    next_rat_busy[entries[head].dest_reg] = 1'b0;
                next_entries[head] = '0;
                commits = 1;
            end
            if (commit_valid[1]) begin
                if (entries[head1].dest_reg != `ZERO_REG && rat_busy[entries[head1].dest_reg] && rat_tag[entries[head1].dest_reg] == head1)
                    next_rat_busy[entries[head1].dest_reg] = 1'b0;
                next_entries[head1] = '0;
                commits = 2;
            end

            allocs = 0;
            if (dispatch_valid[0] && !rob_full) begin
                next_entries[tail].busy             = 1'b1;
                next_entries[tail].ready            = 1'b0;
                next_entries[tail].is_store         = dispatch_is_store[0];
                next_entries[tail].dest_reg         = dispatch_dest_reg[0];
                next_entries[tail].value            = '0;
                next_entries[tail].NPC              = dispatch_NPC[0];
                next_entries[tail].halt             = dispatch_halt[0];
                next_entries[tail].illegal          = dispatch_illegal[0];
                next_entries[tail].is_branch        = dispatch_is_branch[0];
                next_entries[tail].take_branch      = 1'b0;
                next_entries[tail].branch_target    = '0;
                next_entries[tail].predicted_taken  = dispatch_predicted_taken[0];
                next_entries[tail].predicted_target = dispatch_predicted_target[0];
                next_entries[tail].is_uncond_branch = dispatch_is_uncond_branch[0];
                next_entries[tail].branch_PC        = dispatch_PC[0];
                if (dispatch_dest_reg[0] != `ZERO_REG) begin
                    next_rat_busy[dispatch_dest_reg[0]] = 1'b1;
                    next_rat_tag[dispatch_dest_reg[0]]  = tail;
                end
                allocs = 1;
            end
            if (dispatch_valid[1] && !rob_almost_full) begin
                next_entries[bump_tag(tail, 1)].busy             = 1'b1;
                next_entries[bump_tag(tail, 1)].ready            = 1'b0;
                next_entries[bump_tag(tail, 1)].is_store         = dispatch_is_store[1];
                next_entries[bump_tag(tail, 1)].dest_reg         = dispatch_dest_reg[1];
                next_entries[bump_tag(tail, 1)].value            = '0;
                next_entries[bump_tag(tail, 1)].NPC              = dispatch_NPC[1];
                next_entries[bump_tag(tail, 1)].halt             = dispatch_halt[1];
                next_entries[bump_tag(tail, 1)].illegal          = dispatch_illegal[1];
                next_entries[bump_tag(tail, 1)].is_branch        = dispatch_is_branch[1];
                next_entries[bump_tag(tail, 1)].take_branch      = 1'b0;
                next_entries[bump_tag(tail, 1)].branch_target    = '0;
                next_entries[bump_tag(tail, 1)].predicted_taken  = dispatch_predicted_taken[1];
                next_entries[bump_tag(tail, 1)].predicted_target = dispatch_predicted_target[1];
                next_entries[bump_tag(tail, 1)].is_uncond_branch = dispatch_is_uncond_branch[1];
                next_entries[bump_tag(tail, 1)].branch_PC        = dispatch_PC[1];
                if (dispatch_dest_reg[1] != `ZERO_REG) begin
                    next_rat_busy[dispatch_dest_reg[1]] = 1'b1;
                    next_rat_tag[dispatch_dest_reg[1]]  = bump_tag(tail, 1);
                end
                allocs = 2;
            end

            next_head  = bump_tag(head, commits);
            next_tail  = bump_tag(tail, allocs);
            next_count = count + allocs - commits;
        end
    end

    always_ff @(posedge clock) begin
        integer i;
        if (reset) begin
            for (i = 0; i < ROB_SIZE; i++)
                entries[i] <= '0;
            for (i = 0; i < 32; i++) begin
                rat_busy[i] <= 1'b0;
                rat_tag[i]  <= '0;
            end
            head  <= '0;
            tail  <= '0;
            count <= '0;
        end else begin
            for (i = 0; i < ROB_SIZE; i++)
                entries[i] <= next_entries[i];
            for (i = 0; i < 32; i++) begin
                rat_busy[i] <= next_rat_busy[i];
                rat_tag[i]  <= next_rat_tag[i];
            end
            head  <= next_head;
            tail  <= next_tail;
            count <= next_count;
        end
    end

endmodule
