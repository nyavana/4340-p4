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

    output logic                  rs_full, // if rs is full

    // common data bus wakeup
    input  logic                  cdb_valid, // if cdb is valid
    input  logic [TAG_W-1:0]      cdb_tag,
    input  logic [XLEN-1:0]       cdb_value,

    // issue side (output of rs module)
    input  logic                  issue_accept, // handshake to another mocule
    output logic                  issue_valid, // if an entry can be issued
    output logic [OP_W-1:0]       issue_op, // opcode
    output logic [TAG_W-1:0]      issue_dest_tag, // destination tag
    output logic [XLEN-1:0]       issue_src1_value, // source 1 value
    output logic [XLEN-1:0]       issue_src2_value // source 2 value
);

    typedef struct packed {
        logic                 busy;
        logic [OP_W-1:0]      op;
        logic [TAG_W-1:0]     dest_tag;

        logic                 src1_ready;
        logic [TAG_W-1:0]     src1_tag;
        logic [XLEN-1:0]      src1_value;

        logic                 src2_ready;
        logic [TAG_W-1:0]     src2_tag;
        logic [XLEN-1:0]      src2_value;
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
    // Use registered src_ready (not src_ready_eff) to avoid combinational loop:
    // src1_ready_eff depends on cdb_valid, which depends on issue_accept,
    // which depends on issue_found — using _eff here creates a cycle that
    // causes oscillation when a lower-index entry is woken by the CDB of
    // the currently-selected higher-index entry.
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
        issue_op         = '0;
        issue_dest_tag   = '0;
        issue_src1_value = '0;
        issue_src2_value = '0;

        if (issue_found) begin
            issue_op       = entries[issue_idx].op;
            issue_dest_tag = entries[issue_idx].dest_tag;

            issue_src1_value = (cdb_valid &&
                                entries[issue_idx].busy &&
                                !entries[issue_idx].src1_ready &&
                                (entries[issue_idx].src1_tag == cdb_tag))
                             ? cdb_value
                             : entries[issue_idx].src1_value;

            issue_src2_value = (cdb_valid &&
                                entries[issue_idx].busy &&
                                !entries[issue_idx].src2_ready &&
                                (entries[issue_idx].src2_tag == cdb_tag))
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
            // CDB wakeup
            for (i = 0; i < RS_SIZE; i++) begin
                if (entries[i].busy) begin
                    if (cdb_valid && !entries[i].src1_ready &&
                        (entries[i].src1_tag == cdb_tag)) begin
                        next_entries[i].src1_ready = 1'b1;
                        next_entries[i].src1_value = cdb_value;
                    end

                    if (cdb_valid && !entries[i].src2_ready &&
                        (entries[i].src2_tag == cdb_tag)) begin
                        next_entries[i].src2_ready = 1'b1;
                        next_entries[i].src2_value = cdb_value;
                    end
                end
            end

            // remove issued entry
            if (issue_fire) begin
                next_entries[issue_idx] = '0;
            end

            // insert new dispatched entry
            if (dispatch_valid && free_found) begin
                next_entries[free_idx].busy       = 1'b1;
                next_entries[free_idx].op         = dispatch_op;
                next_entries[free_idx].dest_tag   = dispatch_dest_tag;

                next_entries[free_idx].src1_ready = dispatch_src1_ready;
                next_entries[free_idx].src1_tag   = dispatch_src1_tag;
                next_entries[free_idx].src1_value = dispatch_src1_value;

                next_entries[free_idx].src2_ready = dispatch_src2_ready;
                next_entries[free_idx].src2_tag   = dispatch_src2_tag;
                next_entries[free_idx].src2_value = dispatch_src2_value;
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
