`include "sys_defs.svh"

module rs #(
    parameter RS_SIZE = `RS_SZ,
    parameter OP_W    = 8,
    parameter XLEN    = `XLEN,
    parameter TAG_W   = $clog2(`ROB_SZ)
)(
    input  logic                  clock,
    input  logic                  reset,
    input  logic                  flush,

    // up to 2 dispatched non-memory ops
    input  logic [1:0]            dispatch_valid,
    input  logic [OP_W-1:0]       dispatch_op [2],
    input  logic [TAG_W-1:0]      dispatch_dest_tag [2],
    input  logic [1:0]            dispatch_src1_ready,
    input  logic [TAG_W-1:0]      dispatch_src1_tag [2],
    input  logic [XLEN-1:0]       dispatch_src1_value [2],
    input  logic [1:0]            dispatch_src2_ready,
    input  logic [TAG_W-1:0]      dispatch_src2_tag [2],
    input  logic [XLEN-1:0]       dispatch_src2_value [2],
    input  logic [2:0]            dispatch_branch_funct3 [2],
    input  logic [XLEN-1:0]       dispatch_branch_target [2],
    input  logic [XLEN-1:0]       dispatch_branch_NPC [2],

    output logic                  rs_full,
    output logic                  rs_almost_full,

    // dual CDB wakeup
    input  logic [1:0]            cdb_valid,
    input  logic [TAG_W-1:0]      cdb_tag [2],
    input  logic [XLEN-1:0]       cdb_value [2],

    // Early-tag sideband (wakeup-only, from mult FU)
    input  logic                  early_cdb_valid,
    input  logic [TAG_W-1:0]      early_cdb_tag,

    // dual issue
    input  logic [1:0]            issue_accept,
    output logic [1:0]            issue_valid,
    output logic [OP_W-1:0]       issue_op [2],
    output logic [TAG_W-1:0]      issue_dest_tag [2],
    output logic [XLEN-1:0]       issue_src1_value [2],
    output logic [XLEN-1:0]       issue_src2_value [2],
    output logic [2:0]            issue_branch_funct3 [2],
    output logic [XLEN-1:0]       issue_branch_target [2],
    output logic [XLEN-1:0]       issue_branch_NPC [2]
);

    typedef struct packed {
        logic                 busy;
        logic [OP_W-1:0]      op;
        logic [TAG_W-1:0]     dest_tag;
        logic                 src1_ready;
        logic                 src1_val_present;
        logic [TAG_W-1:0]     src1_tag;
        logic [XLEN-1:0]      src1_value;
        logic                 src2_ready;
        logic                 src2_val_present;
        logic [TAG_W-1:0]     src2_tag;
        logic [XLEN-1:0]      src2_value;
        logic [2:0]           branch_funct3;
        logic [XLEN-1:0]      branch_target;
        logic [XLEN-1:0]      branch_NPC;
    } rs_entry_t;

    rs_entry_t entries [RS_SIZE-1:0];
    rs_entry_t next_entries [RS_SIZE-1:0];

    logic [$clog2(RS_SIZE)-1:0] free_idx0, free_idx1;
    logic                       free_found0, free_found1;
    logic [$clog2(RS_SIZE)-1:0] issue_idx0, issue_idx1;
    logic                       issue_found0, issue_found1;

    function automatic logic entry_ready(input rs_entry_t e);
        begin
            entry_ready = e.busy && e.src1_ready && e.src2_ready;
        end
    endfunction


    always_comb begin
        integer i;
        free_found0 = 1'b0; free_idx0 = '0;
        free_found1 = 1'b0; free_idx1 = '0;
        for (i = 0; i < RS_SIZE; i++) begin
            if (!free_found0 && !entries[i].busy) begin
                free_found0 = 1'b1;
                free_idx0 = i[$clog2(RS_SIZE)-1:0];
            end else if (!free_found1 && !entries[i].busy) begin
                free_found1 = 1'b1;
                free_idx1 = i[$clog2(RS_SIZE)-1:0];
            end
        end
    end

    assign rs_full        = !free_found0;
    assign rs_almost_full = !free_found1;

    always_comb begin
        integer i;
        issue_found0 = 1'b0; issue_idx0 = '0;
        issue_found1 = 1'b0; issue_idx1 = '0;
        for (i = 0; i < RS_SIZE; i++) begin
            if (!issue_found0 && entry_ready(entries[i])) begin
                issue_found0 = 1'b1;
                issue_idx0   = i[$clog2(RS_SIZE)-1:0];
            end else if (!issue_found1 && entry_ready(entries[i])) begin
                issue_found1 = 1'b1;
                issue_idx1   = i[$clog2(RS_SIZE)-1:0];
            end
        end
    end

    assign issue_valid[0] = issue_found0;
    assign issue_valid[1] = issue_found1;

    genvar g;
    generate
        for (g = 0; g < 2; g++) begin : GEN_ISSUE_OUT
            wire [$clog2(RS_SIZE)-1:0] idx = (g == 0) ? issue_idx0 : issue_idx1;
            always_comb begin
                integer k;
                logic [`XLEN-1:0] fwd_val1, fwd_val2;
                issue_op[g]            = '0;
                issue_dest_tag[g]      = '0;
                issue_src1_value[g]    = '0;
                issue_src2_value[g]    = '0;
                issue_branch_funct3[g] = '0;
                issue_branch_target[g] = '0;
                issue_branch_NPC[g]    = '0;
                if (issue_valid[g]) begin
                    issue_op[g]            = entries[idx].op;
                    issue_dest_tag[g]      = entries[idx].dest_tag;
                    issue_branch_funct3[g] = entries[idx].branch_funct3;
                    issue_branch_target[g] = entries[idx].branch_target;
                    issue_branch_NPC[g]    = entries[idx].branch_NPC;
                    // ETB val-present forwarding: if value not yet latched,
                    // forward from whichever CDB slot carries the matching tag.
                    fwd_val1 = entries[idx].src1_value;
                    fwd_val2 = entries[idx].src2_value;
                    for (k = 0; k < 2; k++) begin
                        if (cdb_valid[k] && cdb_tag[k] == entries[idx].src1_tag)
                            fwd_val1 = cdb_value[k];
                        if (cdb_valid[k] && cdb_tag[k] == entries[idx].src2_tag)
                            fwd_val2 = cdb_value[k];
                    end
                    issue_src1_value[g] = entries[idx].src1_val_present ? entries[idx].src1_value : fwd_val1;
                    issue_src2_value[g] = entries[idx].src2_val_present ? entries[idx].src2_value : fwd_val2;
                end
            end
        end
    endgenerate

    always_comb begin
        integer i, k;
        logic [RS_SIZE-1:0] taken;

        next_entries = entries;
        taken = '0;

        if (flush) begin
            for (i = 0; i < RS_SIZE; i++)
                next_entries[i] = '0;
        end else begin
            for (i = 0; i < RS_SIZE; i++) begin
                if (entries[i].busy) begin
                    for (k = 0; k < 2; k++) begin
                        if (cdb_valid[k] && !next_entries[i].src1_val_present &&
                            (next_entries[i].src1_tag == cdb_tag[k])) begin
                            next_entries[i].src1_ready       = 1'b1;
                            next_entries[i].src1_val_present = 1'b1;
                            next_entries[i].src1_value       = cdb_value[k];
                        end
                        if (cdb_valid[k] && !next_entries[i].src2_val_present &&
                            (next_entries[i].src2_tag == cdb_tag[k])) begin
                            next_entries[i].src2_ready       = 1'b1;
                            next_entries[i].src2_val_present = 1'b1;
                            next_entries[i].src2_value       = cdb_value[k];
                        end
                    end
                    // Early-tag wakeup: flip src*_ready only (val_present stays 0)
                    if (early_cdb_valid && !next_entries[i].src1_ready &&
                        (next_entries[i].src1_tag == early_cdb_tag))
                        next_entries[i].src1_ready = 1'b1;
                    if (early_cdb_valid && !next_entries[i].src2_ready &&
                        (next_entries[i].src2_tag == early_cdb_tag))
                        next_entries[i].src2_ready = 1'b1;
                end
            end

            if (issue_valid[0] && issue_accept[0]) begin
                next_entries[issue_idx0] = '0;
                taken[issue_idx0] = 1'b1;
            end
            if (issue_valid[1] && issue_accept[1] && !taken[issue_idx1]) begin
                next_entries[issue_idx1] = '0;
                taken[issue_idx1] = 1'b1;
            end

            if (dispatch_valid[0] && free_found0) begin
                next_entries[free_idx0].busy              = 1'b1;
                next_entries[free_idx0].op                = dispatch_op[0];
                next_entries[free_idx0].dest_tag          = dispatch_dest_tag[0];
                next_entries[free_idx0].src1_ready        = dispatch_src1_ready[0];
                next_entries[free_idx0].src1_val_present  = dispatch_src1_ready[0];
                next_entries[free_idx0].src1_tag          = dispatch_src1_tag[0];
                next_entries[free_idx0].src1_value        = dispatch_src1_value[0];
                next_entries[free_idx0].src2_ready        = dispatch_src2_ready[0];
                next_entries[free_idx0].src2_val_present  = dispatch_src2_ready[0];
                next_entries[free_idx0].src2_tag          = dispatch_src2_tag[0];
                next_entries[free_idx0].src2_value        = dispatch_src2_value[0];
                next_entries[free_idx0].branch_funct3     = dispatch_branch_funct3[0];
                next_entries[free_idx0].branch_target     = dispatch_branch_target[0];
                next_entries[free_idx0].branch_NPC        = dispatch_branch_NPC[0];
                taken[free_idx0] = 1'b1;
            end
            if (dispatch_valid[1] && free_found1) begin
                next_entries[free_idx1].busy              = 1'b1;
                next_entries[free_idx1].op                = dispatch_op[1];
                next_entries[free_idx1].dest_tag          = dispatch_dest_tag[1];
                next_entries[free_idx1].src1_ready        = dispatch_src1_ready[1];
                next_entries[free_idx1].src1_val_present  = dispatch_src1_ready[1];
                next_entries[free_idx1].src1_tag          = dispatch_src1_tag[1];
                next_entries[free_idx1].src1_value        = dispatch_src1_value[1];
                next_entries[free_idx1].src2_ready        = dispatch_src2_ready[1];
                next_entries[free_idx1].src2_val_present  = dispatch_src2_ready[1];
                next_entries[free_idx1].src2_tag          = dispatch_src2_tag[1];
                next_entries[free_idx1].src2_value        = dispatch_src2_value[1];
                next_entries[free_idx1].branch_funct3     = dispatch_branch_funct3[1];
                next_entries[free_idx1].branch_target     = dispatch_branch_target[1];
                next_entries[free_idx1].branch_NPC        = dispatch_branch_NPC[1];
            end
        end
    end

    always_ff @(posedge clock) begin
        integer i;
        if (reset) begin
            for (i = 0; i < RS_SIZE; i++)
                entries[i] <= '0;
        end else begin
            for (i = 0; i < RS_SIZE; i++)
                entries[i] <= next_entries[i];
        end
    end

endmodule
