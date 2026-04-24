`include "sys_defs.svh"
`include "ISA.svh"

// =====================================================================
// Pipeline top: 1-wide P6 out-of-order RISC-V core with the milestone-3
// memory subsystem in place.
//
// Memory subsystem changes from milestone 2:
//   - The inline single-line load FU is gone.  Loads and stores now go
//     through the LSQ (verilog/lsq.sv) and the D-cache (verilog/dcache.sv).
//   - Memory ops bypass the RS entirely so the LSQ can keep its entries
//     in program order.  Non-memory ops still go through the RS.
//   - Stores are held in the LSQ until the ROB commits them, then they
//     are released to the cache.  Architectural memory is never written
//     speculatively.
//   - Bus arbitration is now between icache and dcache, with the dcache
//     having priority.  A 1-cycle owner-tracking flag routes the
//     mem2proc_response back to the cache that issued the request.
// =====================================================================

module pipeline (
    input        clock,
    input        reset,
    input [3:0]  mem2proc_response,
    input [63:0] mem2proc_data,
    input [3:0]  mem2proc_tag,

    output logic [1:0]       proc2mem_command,
    output logic [`XLEN-1:0] proc2mem_addr,
    output logic [63:0]      proc2mem_data,

    output logic [3:0]       pipeline_completed_insts,
    output EXCEPTION_CODE    pipeline_error_status,
    output logic [4:0]       pipeline_commit_wr_idx,
    output logic [`XLEN-1:0] pipeline_commit_wr_data,
    output logic             pipeline_commit_wr_en,
    output logic [`XLEN-1:0] pipeline_commit_NPC
);

    localparam TAG_W = $clog2(`ROB_SZ);

    // ================================================================
    // Wire / logic declarations
    // ================================================================

    // PC / fetch
    logic [`XLEN-1:0] PC_reg;
    INST              fetched_inst, fetched_inst1;
    logic [`XLEN-1:0] fetched_NPC, fetched_NPC1;
    logic             slot1_candidate, slot1_ok, dispatch_fire1;

    // Stall / dispatch
    logic branch_pending;
    logic stall;
    logic dispatch_fire;
    logic is_mem_op;

    // ICache
    logic [1:0]       proc2Imem_command;
    logic [`XLEN-1:0] proc2Imem_addr;
    logic [63:0]      Icache_data_out;
    logic             Icache_valid_out;

    // Decoder outputs
    ALU_OPA_SELECT dec_opa_select, dec1_opa_select;
    ALU_OPB_SELECT dec_opb_select, dec1_opb_select;
    logic          dec_has_dest, dec1_has_dest;
    ALU_FUNC       dec_alu_func, dec1_alu_func;
    logic          dec_rd_mem, dec_wr_mem, dec1_rd_mem, dec1_wr_mem;
    logic          dec_cond_branch, dec_uncond_branch, dec1_cond_branch, dec1_uncond_branch;
    logic          dec_csr_op, dec_halt, dec_illegal, dec1_csr_op, dec1_halt, dec1_illegal;

    // Regfile outputs
    logic [`XLEN-1:0] rf_rs1_value, rf_rs2_value, rf1_rs1_value, rf1_rs2_value;

    // ROB outputs
    logic                   rob_full, rob_almost_full;
    logic [TAG_W-1:0]       rob_dispatch_tag [2];
    logic [1:0]             rob_commit_valid;
    logic [TAG_W-1:0]       rob_commit_tag [2];
    logic [1:0]             rob_commit_is_store;
    logic [4:0]             rob_commit_dest_reg [2];
    logic [`XLEN-1:0]       rob_commit_value [2];
    logic [`XLEN-1:0]       rob_commit_NPC [2];
    logic [1:0]             rob_commit_halt;
    logic [1:0]             rob_commit_illegal;
    logic [1:0]             rob_commit_is_branch;
    logic [1:0]             rob_commit_take_branch;
    logic [`XLEN-1:0]       rob_commit_branch_target [2];
    logic                   rat_q1_pending, rat_q1_ready;
    logic [TAG_W-1:0]       rat_q1_tag;
    logic [`XLEN-1:0]       rat_q1_value;
    logic                   rat_q2_pending, rat_q2_ready;
    logic [TAG_W-1:0]       rat_q2_tag;
    logic [`XLEN-1:0]       rat_q2_value;
    logic                   rat_q3_pending, rat_q3_ready;
    logic [TAG_W-1:0]       rat_q3_tag;
    logic [`XLEN-1:0]       rat_q3_value;
    logic                   rat_q4_pending, rat_q4_ready;
    logic [TAG_W-1:0]       rat_q4_tag;
    logic [`XLEN-1:0]       rat_q4_value;

    // RS outputs
    logic                   rs_full, rs_almost_full;
    logic [1:0]             rs_issue_valid;
    logic [7:0]             rs_issue_op [2];
    logic [TAG_W-1:0]       rs_issue_dest_tag [2];
    logic [`XLEN-1:0]       rs_issue_src1_value [2];
    logic [`XLEN-1:0]       rs_issue_src2_value [2];
    logic [2:0]             rs_issue_branch_funct3 [2];
    logic [`XLEN-1:0]       rs_issue_branch_target [2];
    logic [`XLEN-1:0]       rs_issue_branch_NPC [2];

    // Dispatch operand resolution
    logic             dispatch_src1_ready, dispatch_src2_ready;
    logic [TAG_W-1:0] dispatch_src1_tag,   dispatch_src2_tag;
    logic [`XLEN-1:0] dispatch_src1_value, dispatch_src2_value;
    logic             dispatch_data_ready;
    logic [TAG_W-1:0] dispatch_data_tag;
    logic [`XLEN-1:0] dispatch_data_value;
    logic [7:0]       dispatch_op;
    logic [`XLEN-1:0] dispatch_imm;
    logic [1:0]       dispatch_mem_size;
    logic             dispatch_is_signed;

    logic             dispatch1_src1_ready, dispatch1_src2_ready;
    logic [TAG_W-1:0] dispatch1_src1_tag,   dispatch1_src2_tag;
    logic [`XLEN-1:0] dispatch1_src1_value, dispatch1_src2_value;
    logic [7:0]       dispatch1_op;
    logic [`XLEN-1:0] dispatch1_imm;
    logic [1:0]       dispatch1_mem_size;
    logic             dispatch1_is_signed;
    logic [`XLEN-1:0] dispatch1_branch_target;
    logic [2:0]       dispatch1_branch_funct3;

    // Issue routing
    logic [1:0] issue_is_mult, issue_is_branch, issue_accept;
    logic       selected_mult_valid;
    logic       selected_mult_slot;
    integer     available_alu_slots;

    // Branch buffer (legacy shared latch path — kept only for the
    // non-branch instruction flow.  Per-branch info now lives in the
    // RS and ROB entries.)
    logic [`XLEN-1:0] branch_target_buf;
    logic [2:0]       branch_funct3_buf;

    // Dispatch-time branch target and funct3 that feed the RS per-entry
    // fields.  Computed combinationally from the fetched instruction.
    logic [`XLEN-1:0] dispatch_branch_target;
    logic [2:0]       dispatch_branch_funct3;

    // Predictor ports
    logic             pred_valid;
    logic             pred_taken;
    logic [`XLEN-1:0] pred_target;
    logic             pred_is_uncond;
    // Commit-side mispredict
    logic             mispredict_valid;
    logic [`XLEN-1:0] mispredict_target;
    logic [1:0]             rob_commit_is_uncond_branch;
    logic [`XLEN-1:0]       rob_commit_branch_PC [2];

    // MULT FU.  mult_flushed marks an in-flight mult whose ROB slot was
    // invalidated by a mispredict; when the stages finally complete we
    // suppress the CDB broadcast so we don't write into a re-allocated
    // entry.
    logic             mult_busy, mult_done;
    logic             mult_flushed;
    logic [TAG_W-1:0] mult_dest_tag_reg;
    ALU_FUNC          mult_alu_func_reg;
    logic [63:0]      mult_product;
    logic [63:0]      mult_mcand, mult_mplier;
    logic             mult_done_valid; // mult_done && !mult_flushed
    logic             mult_early_done;

    // Early-tag sideband.  Pulses one cycle before `mult_done_valid`,
    // carrying the ROB tag that will retire on the next CDB broadcast so
    // the RS / LSQ can flip registered src*_ready the same cycle and issue
    // the consumer on the CDB cycle instead of one cycle later.
    //
    // Rule: early_cdb_* is a wakeup-only sideband — it NEVER feeds the RS
    // issue selector combinationally (see rs-issue-loop-fix.md).
    logic             early_cdb_valid;
    logic [TAG_W-1:0] early_cdb_tag;

    // ALU
    logic [`XLEN-1:0] alu_result [2];
    logic signed [`XLEN-1:0] alu_signed_a [2], alu_signed_b [2];
    logic             branch_take [2];
    logic signed [`XLEN-1:0] br_signed_a [2], br_signed_b [2];

    // CDB
    logic [1:0]             cdb_valid;
    logic [TAG_W-1:0]       cdb_tag [2];
    logic [`XLEN-1:0]       cdb_value [2];
    logic [1:0]             cdb_take_branch;
    logic [`XLEN-1:0]       cdb_branch_target [2];
    logic                   lsq_load_selected;

    // LSQ
    logic             lsq_full;
    logic             lsq_dcache_load, lsq_dcache_store;
    logic [`XLEN-1:0] lsq_dcache_addr;
    logic [63:0]      lsq_dcache_wr_data;
    logic [7:0]       lsq_dcache_wr_be;
    logic             lsq_load_complete_valid;
    logic [TAG_W-1:0] lsq_load_complete_tag;
    logic [`XLEN-1:0] lsq_load_complete_value;
    logic             lsq_load_complete_accept;
    logic             lsq_store_ready_valid;
    logic [TAG_W-1:0] lsq_store_ready_tag;

    // DCache
    logic [63:0]      dcache_rd_data;
    logic             dcache_done;
    logic             dcache_busy;
    logic [1:0]       dc_proc2mem_command;
    logic [`XLEN-1:0] dc_proc2mem_addr;
    logic [63:0]      dc_proc2mem_data;
    logic [3:0]       dcache_resp_in;
    logic [3:0]       icache_resp_in;

    // Stream buffer (instruction prefetcher)
    logic [1:0]       proc2Pmem_command;
    logic [`XLEN-1:0] proc2Pmem_addr;
    logic [63:0]      sb_data_out;
    logic             sb_valid_out;
    logic [3:0]       sb_resp_in;
    integer           prefetch_hit_count;

    // Unified fetch data/valid (icache or stream buffer)
    logic [63:0]      fetch_data_out;
    logic             fetch_valid_out;

    // Error status latch
    EXCEPTION_CODE error_status_reg;

    // ================================================================
    // Combinational assignments
    // ================================================================

    assign fetch_data_out  = sb_valid_out ? sb_data_out : Icache_data_out;
    assign fetch_valid_out = Icache_valid_out || sb_valid_out;

    assign fetched_inst  = PC_reg[2] ? fetch_data_out[63:32] : fetch_data_out[31:0];
    assign fetched_inst1 = PC_reg[2] ? INST'(`NOP)            : fetch_data_out[63:32];
    assign fetched_NPC   = PC_reg + 4;
    assign fetched_NPC1  = PC_reg + 8;

    assign is_mem_op = dec_rd_mem || dec_wr_mem;
    assign slot1_candidate = Icache_valid_out && !PC_reg[2];
    assign slot1_ok = slot1_candidate && !dec_rd_mem && !dec_wr_mem && !dec_cond_branch && !dec_uncond_branch &&
                      !dec_halt && !dec_illegal && !dec1_rd_mem && !dec1_wr_mem && !dec1_cond_branch &&
                      !dec1_uncond_branch && !dec1_halt && !dec1_illegal;

    assign stall = !fetch_valid_out || rob_full || branch_pending ||
                   (is_mem_op ? lsq_full : rs_full);
    assign dispatch_fire = !stall;
    assign dispatch_fire1 = dispatch_fire && slot1_ok && !rob_almost_full && !rs_almost_full;

    // Compute the branch target and funct3 at dispatch for the RS entry.
    // For conditional branches, target = PC + Bimm; for unconditional
    // JAL, target = PC + Jimm (JALR computes in the ALU from rs1 and is
    // not latched here -- the RS-carried branch_target is unused for JALR
    // because its CDB broadcast comes from alu_result).  funct3 only
    // matters for conditional branches.
    always_comb begin
        dispatch_branch_funct3 = fetched_inst.b.funct3;
        if (dec_uncond_branch)
            dispatch_branch_target = PC_reg + `RV32_signext_Jimm(fetched_inst);
        else
            dispatch_branch_target = PC_reg + `RV32_signext_Bimm(fetched_inst);

        dispatch1_branch_funct3 = fetched_inst1.b.funct3;
        if (dec1_uncond_branch)
            dispatch1_branch_target = fetched_NPC + `RV32_signext_Jimm(fetched_inst1);
        else
            dispatch1_branch_target = fetched_NPC + `RV32_signext_Bimm(fetched_inst1);
    end

    // op[7]=rd_mem, op[6]=uncond_branch, op[5]=cond_branch, op[4:0]=alu_func
    assign dispatch_op   = {dec_rd_mem, dec_uncond_branch, dec_cond_branch, dec_alu_func};
    assign dispatch1_op  = {dec1_rd_mem, dec1_uncond_branch, dec1_cond_branch, dec1_alu_func};

    // mem_size from funct3[1:0] (00=BYTE, 01=HALF, 10=WORD)
    assign dispatch_mem_size   = fetched_inst.r.funct3[1:0];
    assign dispatch_is_signed  = !fetched_inst.r.funct3[2];
    assign dispatch1_mem_size  = fetched_inst1.r.funct3[1:0];
    assign dispatch1_is_signed = !fetched_inst1.r.funct3[2];

    // Dispatched immediate (sign-extended I-imm for loads, S-imm for stores)
    always_comb begin
        if (dec_wr_mem)
            dispatch_imm = `RV32_signext_Simm(fetched_inst);
        else
            dispatch_imm = `RV32_signext_Iimm(fetched_inst);

        if (dec1_wr_mem)
            dispatch1_imm = `RV32_signext_Simm(fetched_inst1);
        else
            dispatch1_imm = `RV32_signext_Iimm(fetched_inst1);
    end

    assign issue_is_mult[0]   = (rs_issue_op[0][4:0] >= 5'(ALU_MUL)) &&
                                 (rs_issue_op[0][4:0] <= 5'(ALU_MULHU));
    assign issue_is_mult[1]   = (rs_issue_op[1][4:0] >= 5'(ALU_MUL)) &&
                                 (rs_issue_op[1][4:0] <= 5'(ALU_MULHU));
    assign issue_is_branch[0] = rs_issue_op[0][5] | rs_issue_op[0][6];
    assign issue_is_branch[1] = rs_issue_op[1][5] | rs_issue_op[1][6];

    always_comb begin
        integer nonmult_used;
        integer reserved_cdb;
        issue_accept[0]      = 1'b0;
        issue_accept[1]      = 1'b0;
        selected_mult_valid  = 1'b0;
        selected_mult_slot   = 1'b0;
        reserved_cdb         = (mult_done_valid ? 1 : 0) + (lsq_load_complete_valid ? 1 : 0);
        available_alu_slots  = 2 - reserved_cdb;
        nonmult_used         = 0;

        if (rs_issue_valid[0]) begin
            if (issue_is_mult[0]) begin
                if (!mult_busy && !mult_done_valid) begin
                    issue_accept[0]     = 1'b1;
                    selected_mult_valid = 1'b1;
                    selected_mult_slot  = 1'b0;
                end
            end else if (nonmult_used < available_alu_slots) begin
                issue_accept[0] = 1'b1;
                nonmult_used = nonmult_used + 1;
            end
        end

        if (rs_issue_valid[1]) begin
            if (issue_is_mult[1]) begin
                if (!selected_mult_valid && !mult_busy && !mult_done_valid) begin
                    issue_accept[1]     = 1'b1;
                    selected_mult_valid = 1'b1;
                    selected_mult_slot  = 1'b1;
                end
            end else if (nonmult_used < available_alu_slots) begin
                issue_accept[1] = 1'b1;
                nonmult_used = nonmult_used + 1;
            end
        end
    end

    assign alu_signed_a[0] = rs_issue_src1_value[0];
    assign alu_signed_b[0] = rs_issue_src2_value[0];
    assign br_signed_a[0]  = rs_issue_src1_value[0];
    assign br_signed_b[0]  = rs_issue_src2_value[0];
    assign alu_signed_a[1] = rs_issue_src1_value[1];
    assign alu_signed_b[1] = rs_issue_src2_value[1];
    assign br_signed_a[1]  = rs_issue_src1_value[1];
    assign br_signed_b[1]  = rs_issue_src2_value[1];

    // Bus arbitration: dcache has priority over icache.
    //
    // The same `icache_drives` / `dcache_drives` signals are used both
    // for the bus mux (combinational, drives the current cycle) and for
    // the response routing read inside the cache's always_ff at the
    // next posedge.  Inside the always_ff, comb signals reflect the
    // PREVIOUS cycle's register values, so reading icache_drives there
    // gives "did icache drive last cycle" - exactly the cycle the
    // response on mem2proc_response was allocated for.  No additional
    // delay register is needed.
    // ----------------------------------------------------------------
    // Three-level priority: dcache > icache (demand) > stream buffer (prefetch).
    // The *_drives wires serve double duty: combinational bus mux this cycle,
    // and response-routing mask sampled at the next posedge (inside each
    // module's always_ff), giving "who drove last cycle" without an extra register.
    wire dcache_drives = (dc_proc2mem_command != BUS_NONE);
    wire icache_drives = !dcache_drives && (proc2Imem_command != BUS_NONE);
    wire pfetch_drives = !dcache_drives && !icache_drives && (proc2Pmem_command != BUS_NONE);

    assign proc2mem_command = dcache_drives ? dc_proc2mem_command :
                              icache_drives ? proc2Imem_command   :
                              pfetch_drives ? proc2Pmem_command   : BUS_NONE;
    assign proc2mem_addr    = dcache_drives ? dc_proc2mem_addr    :
                              icache_drives ? proc2Imem_addr      :
                              pfetch_drives ? proc2Pmem_addr      : '0;
    assign proc2mem_data    = dcache_drives ? dc_proc2mem_data    : 64'b0;

    assign icache_resp_in = icache_drives ? mem2proc_response : 4'b0;
    assign dcache_resp_in = dcache_drives ? mem2proc_response : 4'b0;
    assign sb_resp_in     = pfetch_drives ? mem2proc_response : 4'b0;

    // Pipeline outputs
    assign pipeline_completed_insts ={3'b000, rob_commit_valid[0]} + {3'b000, rob_commit_valid[1]};
    assign pipeline_commit_wr_en    = rob_commit_valid[0] && (rob_commit_dest_reg[0] != 5'd0);
    assign pipeline_commit_wr_idx   = rob_commit_dest_reg[0];
    assign pipeline_commit_wr_data  = rob_commit_value[0];
    assign pipeline_commit_NPC      = rob_commit_NPC[0];
    assign pipeline_error_status    = error_status_reg;

    // ================================================================
    // PC register
    //
    // Priority:
    //   1. mispredict_valid: redirect to correct target, flush everything
    //   2. dispatch_fire && pred_valid && pred_taken: follow the predictor
    //   3. dispatch_fire: PC + 4
    //   4. stall: hold
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset)
            PC_reg <= '0;
        else if (mispredict_valid)
            PC_reg <= mispredict_target;
        else if (dispatch_fire) begin
            if (pred_valid && pred_taken)
                PC_reg <= pred_target;
            else if (dispatch_fire1)
                PC_reg <= PC_reg + 8;
            else
                PC_reg <= PC_reg + 4;
        end
    end

    // ================================================================
    // ICache
    // ================================================================
    icache icache_0 (
        .clock              (clock),
        .reset              (reset),
        .Imem2proc_response (icache_resp_in),
        .Imem2proc_data     (mem2proc_data),
        .Imem2proc_tag      (mem2proc_tag),
        .proc2Icache_addr   ({PC_reg[`XLEN-1:3], 3'b0}),
        .proc2Imem_command  (proc2Imem_command),
        .proc2Imem_addr     (proc2Imem_addr),
        .Icache_data_out    (Icache_data_out),
        .Icache_valid_out   (Icache_valid_out)
    );

    // ================================================================
    // Stream buffer (instruction prefetcher)
    // ================================================================
    stream_buffer sb_0 (
        .clock              (clock),
        .reset              (reset),
        .mem2sb_response    (sb_resp_in),
        .mem2proc_data      (mem2proc_data),
        .mem2proc_tag       (mem2proc_tag),
        .demand_addr        ({PC_reg[`XLEN-1:3], 3'b0}),
        .proc2Pmem_command  (proc2Pmem_command),
        .proc2Pmem_addr     (proc2Pmem_addr),
        .sb_data_out        (sb_data_out),
        .sb_valid_out       (sb_valid_out),
        .prefetch_hit_count (prefetch_hit_count)
    );

    // ================================================================
    // Branch predictor (BTB + bimodal)
    //
    // Predict port: combinational lookup on the current fetch PC.
    // Update port: registered, one-per-committing-branch write driven
    // by the ROB's commit-side branch info.
    // ================================================================
    logic             pred_valid_raw;
    logic             pred_taken_raw;
    logic [`XLEN-1:0] pred_target_raw;
    logic             pred_is_uncond_raw;
`ifdef DISABLE_PREDICTOR
    assign pred_valid     = 1'b0;
    assign pred_taken     = 1'b0;
    assign pred_target    = '0;
    assign pred_is_uncond = 1'b0;
`else
    assign pred_valid     = pred_valid_raw;
    assign pred_taken     = pred_taken_raw;
    assign pred_target    = pred_target_raw;
    assign pred_is_uncond = pred_is_uncond_raw;
`endif
    branch_predictor branch_predictor_0 (
        .clock            (clock),
        .reset            (reset),

        .predict_PC       (PC_reg),
        .pred_valid       (pred_valid_raw),
        .pred_taken       (pred_taken_raw),
        .pred_target      (pred_target_raw),
        .pred_is_uncond   (pred_is_uncond_raw),

        .update_valid     ((rob_commit_valid[0] && rob_commit_is_branch[0]) || (rob_commit_valid[1] && rob_commit_is_branch[1])),
        .update_PC        ((rob_commit_valid[0] && rob_commit_is_branch[0]) ? rob_commit_branch_PC[0] : rob_commit_branch_PC[1]),
        .update_target    ((rob_commit_valid[0] && rob_commit_is_branch[0]) ? rob_commit_branch_target[0] : rob_commit_branch_target[1]),
        .update_taken     ((rob_commit_valid[0] && rob_commit_is_branch[0]) ? rob_commit_take_branch[0] : rob_commit_take_branch[1]),
        .update_is_uncond ((rob_commit_valid[0] && rob_commit_is_branch[0]) ? rob_commit_is_uncond_branch[0] : rob_commit_is_uncond_branch[1])
    );

    // ================================================================
    // Decoder
    // ================================================================
    decoder decoder_0 (
        .inst          (fetched_inst),
        .valid         (fetch_valid_out),
        .opa_select    (dec_opa_select),
        .opb_select    (dec_opb_select),
        .has_dest      (dec_has_dest),
        .alu_func      (dec_alu_func),
        .rd_mem        (dec_rd_mem),
        .wr_mem        (dec_wr_mem),
        .cond_branch   (dec_cond_branch),
        .uncond_branch (dec_uncond_branch),
        .csr_op        (dec_csr_op),
        .halt          (dec_halt),
        .illegal       (dec_illegal)
    );

    decoder decoder_1 (
        .inst          (fetched_inst1),
        .valid         (slot1_candidate),
        .opa_select    (dec1_opa_select),
        .opb_select    (dec1_opb_select),
        .has_dest      (dec1_has_dest),
        .alu_func      (dec1_alu_func),
        .rd_mem        (dec1_rd_mem),
        .wr_mem        (dec1_wr_mem),
        .cond_branch   (dec1_cond_branch),
        .uncond_branch (dec1_uncond_branch),
        .csr_op        (dec1_csr_op),
        .halt          (dec1_halt),
        .illegal       (dec1_illegal)
    );

    // ================================================================
    // Regfile
    // ================================================================
    regfile regfile_0 (
        .clock      (clock),
        .read_idx_1 (fetched_inst.r.rs1),
        .read_idx_2 (fetched_inst.r.rs2),
        .read_idx_3 (fetched_inst1.r.rs1),
        .read_idx_4 (fetched_inst1.r.rs2),
        .write_en_0   (rob_commit_valid[0] && (rob_commit_dest_reg[0] != 5'd0)),
        .write_idx_0  (rob_commit_dest_reg[0]),
        .write_data_0 (rob_commit_value[0]),
        .write_en_1   (rob_commit_valid[1] && (rob_commit_dest_reg[1] != 5'd0)),
        .write_idx_1  (rob_commit_dest_reg[1]),
        .write_data_1 (rob_commit_value[1]),
        .read_out_1 (rf_rs1_value),
        .read_out_2 (rf_rs2_value),
        .read_out_3 (rf1_rs1_value),
        .read_out_4 (rf1_rs2_value)
    );

    // ================================================================
    // Src1 / src2 / store-data operand resolution
    // ================================================================

    // src1: rs1 for branches/mem ops or when opa_select=OPA_IS_RS1, else const
    always_comb begin
        if (dec_cond_branch || is_mem_op || (dec_opa_select == OPA_IS_RS1)) begin
            if (!rat_q1_pending) begin
                dispatch_src1_ready = 1'b1;
                dispatch_src1_tag   = '0;
                dispatch_src1_value = rf_rs1_value;
            end else if (rat_q1_ready) begin
                dispatch_src1_ready = 1'b1;
                dispatch_src1_tag   = rat_q1_tag;
                dispatch_src1_value = rat_q1_value;
            end else begin
                dispatch_src1_ready = 1'b0;
                dispatch_src1_tag   = rat_q1_tag;
                dispatch_src1_value = '0;
            end
        end else begin
            dispatch_src1_ready = 1'b1;
            dispatch_src1_tag   = '0;
            case (dec_opa_select)
                OPA_IS_NPC:  dispatch_src1_value = fetched_NPC;
                OPA_IS_PC:   dispatch_src1_value = PC_reg;
                default:     dispatch_src1_value = '0;
            endcase
        end
    end

    // src2: used by RS for ALU/branch operands. Memory ops do NOT
    // go through the RS so this resolver doesn't have to handle them.
    always_comb begin
        if (dec_cond_branch || (dec_opb_select == OPB_IS_RS2)) begin
            if (!rat_q2_pending) begin
                dispatch_src2_ready = 1'b1;
                dispatch_src2_tag   = '0;
                dispatch_src2_value = rf_rs2_value;
            end else if (rat_q2_ready) begin
                dispatch_src2_ready = 1'b1;
                dispatch_src2_tag   = rat_q2_tag;
                dispatch_src2_value = rat_q2_value;
            end else begin
                dispatch_src2_ready = 1'b0;
                dispatch_src2_tag   = rat_q2_tag;
                dispatch_src2_value = '0;
            end
        end else begin
            dispatch_src2_ready = 1'b1;
            dispatch_src2_tag   = '0;
            case (dec_opb_select)
                OPB_IS_I_IMM: dispatch_src2_value = `RV32_signext_Iimm(fetched_inst);
                OPB_IS_S_IMM: dispatch_src2_value = `RV32_signext_Simm(fetched_inst);
                OPB_IS_B_IMM: dispatch_src2_value = `RV32_signext_Bimm(fetched_inst);
                OPB_IS_U_IMM: dispatch_src2_value = `RV32_signext_Uimm(fetched_inst);
                OPB_IS_J_IMM: dispatch_src2_value = `RV32_signext_Jimm(fetched_inst);
                default:      dispatch_src2_value = '0;
            endcase
        end
    end

    // store-data: always rs2 for the LSQ. The decoder gives stores
    // opb_select=OPB_IS_S_IMM, so we can't reuse dispatch_src2 here.
    always_comb begin
        if (!rat_q2_pending) begin
            dispatch_data_ready = 1'b1;
            dispatch_data_tag   = '0;
            dispatch_data_value = rf_rs2_value;
        end else if (rat_q2_ready) begin
            dispatch_data_ready = 1'b1;
            dispatch_data_tag   = rat_q2_tag;
            dispatch_data_value = rat_q2_value;
        end else begin
            dispatch_data_ready = 1'b0;
            dispatch_data_tag   = rat_q2_tag;
            dispatch_data_value = '0;
        end
    end

    always_comb begin
        logic dep0;
        dep0 = dispatch_fire && dec_has_dest && (fetched_inst.r.rd != `ZERO_REG) &&
               (fetched_inst1.r.rs1 == fetched_inst.r.rd);
        if (dec1_cond_branch || (dec1_opa_select == OPA_IS_RS1)) begin
            if (dep0) begin
                dispatch1_src1_ready = 1'b0;
                dispatch1_src1_tag   = rob_dispatch_tag[0];
                dispatch1_src1_value = '0;
            end else if (!rat_q3_pending) begin
                dispatch1_src1_ready = 1'b1;
                dispatch1_src1_tag   = '0;
                dispatch1_src1_value = rf1_rs1_value;
            end else if (rat_q3_ready) begin
                dispatch1_src1_ready = 1'b1;
                dispatch1_src1_tag   = rat_q3_tag;
                dispatch1_src1_value = rat_q3_value;
            end else begin
                dispatch1_src1_ready = 1'b0;
                dispatch1_src1_tag   = rat_q3_tag;
                dispatch1_src1_value = '0;
            end
        end else begin
            dispatch1_src1_ready = 1'b1;
            dispatch1_src1_tag   = '0;
            case (dec1_opa_select)
                OPA_IS_NPC: dispatch1_src1_value = fetched_NPC1;
                OPA_IS_PC:  dispatch1_src1_value = fetched_NPC;
                default:    dispatch1_src1_value = '0;
            endcase
        end
    end

    always_comb begin
        logic dep1;
        dep1 = dispatch_fire && dec_has_dest && (fetched_inst.r.rd != `ZERO_REG) &&
               (fetched_inst1.r.rs2 == fetched_inst.r.rd);
        if (dec1_cond_branch || (dec1_opb_select == OPB_IS_RS2)) begin
            if (dep1) begin
                dispatch1_src2_ready = 1'b0;
                dispatch1_src2_tag   = rob_dispatch_tag[0];
                dispatch1_src2_value = '0;
            end else if (!rat_q4_pending) begin
                dispatch1_src2_ready = 1'b1;
                dispatch1_src2_tag   = '0;
                dispatch1_src2_value = rf1_rs2_value;
            end else if (rat_q4_ready) begin
                dispatch1_src2_ready = 1'b1;
                dispatch1_src2_tag   = rat_q4_tag;
                dispatch1_src2_value = rat_q4_value;
            end else begin
                dispatch1_src2_ready = 1'b0;
                dispatch1_src2_tag   = rat_q4_tag;
                dispatch1_src2_value = '0;
            end
        end else begin
            dispatch1_src2_ready = 1'b1;
            dispatch1_src2_tag   = '0;
            case (dec1_opb_select)
                OPB_IS_I_IMM: dispatch1_src2_value = `RV32_signext_Iimm(fetched_inst1);
                OPB_IS_S_IMM: dispatch1_src2_value = `RV32_signext_Simm(fetched_inst1);
                OPB_IS_B_IMM: dispatch1_src2_value = `RV32_signext_Bimm(fetched_inst1);
                OPB_IS_U_IMM: dispatch1_src2_value = `RV32_signext_Uimm(fetched_inst1);
                OPB_IS_J_IMM: dispatch1_src2_value = `RV32_signext_Jimm(fetched_inst1);
                default:      dispatch1_src2_value = '0;
            endcase
        end
    end

    // ================================================================
    // ROB
    // ================================================================
    rob rob_0 (
        .clock                (clock),
        .reset                (reset),
        .flush                (mispredict_valid),

        .dispatch_valid       ({dispatch_fire1, dispatch_fire}),
        .dispatch_dest_reg    ('{(dec_has_dest ? fetched_inst.r.rd : 5'd0), (dec1_has_dest ? fetched_inst1.r.rd : 5'd0)}),
        .dispatch_NPC         ('{fetched_NPC, fetched_NPC1}),
        .dispatch_PC          ('{PC_reg, fetched_NPC}),
        .dispatch_halt        ({dec1_halt, dec_halt}),
        .dispatch_illegal     ({dec1_illegal, dec_illegal}),
        .dispatch_is_branch   ({(dec1_cond_branch || dec1_uncond_branch), (dec_cond_branch || dec_uncond_branch)}),
        .dispatch_is_uncond_branch ({dec1_uncond_branch, dec_uncond_branch}),
        .dispatch_is_store    ({dec1_wr_mem, dec_wr_mem}),

        // Only slot0 uses predictor metadata in this minimal 2-wide frontend.
        .dispatch_predicted_taken  ({1'b0, ((dec_cond_branch || dec_uncond_branch) && pred_valid && pred_taken)}),
        .dispatch_predicted_target ('{((dec_cond_branch || dec_uncond_branch) ? pred_target : 32'b0), 32'b0}),

        .rob_full             (rob_full),
        .rob_almost_full      (rob_almost_full),
        .dispatch_tag         (rob_dispatch_tag),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_tag),
        .cdb_value            (cdb_value),
        .cdb_take_branch      (cdb_take_branch),
        .cdb_branch_target    (cdb_branch_target),

        .store_done_valid     ({1'b0, lsq_store_ready_valid}),
        .store_done_tag       ('{lsq_store_ready_tag, rob_commit_tag[0]}),

        .commit_valid         (rob_commit_valid),
        .commit_tag           (rob_commit_tag),
        .commit_is_store      (rob_commit_is_store),
        .commit_dest_reg      (rob_commit_dest_reg),
        .commit_value         (rob_commit_value),
        .commit_NPC           (rob_commit_NPC),
        .commit_halt          (rob_commit_halt),
        .commit_illegal       (rob_commit_illegal),
        .commit_is_branch     (rob_commit_is_branch),
        .commit_take_branch   (rob_commit_take_branch),
        .commit_branch_target (rob_commit_branch_target),
        .commit_is_uncond_branch (rob_commit_is_uncond_branch),
        .commit_branch_PC     (rob_commit_branch_PC),

        .mispredict_valid     (mispredict_valid),
        .mispredict_target    (mispredict_target),

        .query1_arch_reg      (fetched_inst.r.rs1),
        .query1_pending       (rat_q1_pending),
        .query1_ready         (rat_q1_ready),
        .query1_tag           (rat_q1_tag),
        .query1_value         (rat_q1_value),

        .query2_arch_reg      (fetched_inst.r.rs2),
        .query2_pending       (rat_q2_pending),
        .query2_ready         (rat_q2_ready),
        .query2_tag           (rat_q2_tag),
        .query2_value         (rat_q2_value),

        .query3_arch_reg      (fetched_inst1.r.rs1),
        .query3_pending       (rat_q3_pending),
        .query3_ready         (rat_q3_ready),
        .query3_tag           (rat_q3_tag),
        .query3_value         (rat_q3_value),

        .query4_arch_reg      (fetched_inst1.r.rs2),
        .query4_pending       (rat_q4_pending),
        .query4_ready         (rat_q4_ready),
        .query4_tag           (rat_q4_tag),
        .query4_value         (rat_q4_value)
    );

    // ================================================================
    // RS - non-memory ops only
    // ================================================================
    rs rs_0 (
        .clock               (clock),
        .reset               (reset),
        .flush               (mispredict_valid),

        .dispatch_valid      ({dispatch_fire1, (dispatch_fire && !is_mem_op)}),
        .dispatch_op         ('{dispatch_op, dispatch1_op}),
        .dispatch_dest_tag   ('{rob_dispatch_tag[0], rob_dispatch_tag[1]}),

        .dispatch_src1_ready ({dispatch_fire1 ? dispatch1_src1_ready : 1'b0, dispatch_src1_ready}),
        .dispatch_src1_tag   ('{dispatch_src1_tag, dispatch1_src1_tag}),
        .dispatch_src1_value ('{dispatch_src1_value, dispatch1_src1_value}),

        .dispatch_src2_ready ({dispatch_fire1 ? dispatch1_src2_ready : 1'b0, dispatch_src2_ready}),
        .dispatch_src2_tag   ('{dispatch_src2_tag, dispatch1_src2_tag}),
        .dispatch_src2_value ('{dispatch_src2_value, dispatch1_src2_value}),

        .dispatch_branch_funct3 ('{dispatch_branch_funct3, dispatch1_branch_funct3}),
        .dispatch_branch_target ('{dispatch_branch_target, dispatch1_branch_target}),
        .dispatch_branch_NPC    ('{fetched_NPC, fetched_NPC1}),

        .rs_full             (rs_full),
        .rs_almost_full      (rs_almost_full),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),

        .early_cdb_valid     (early_cdb_valid),
        .early_cdb_tag       (early_cdb_tag),

        .issue_accept        (issue_accept),
        .issue_valid         (rs_issue_valid),
        .issue_op            (rs_issue_op),
        .issue_dest_tag      (rs_issue_dest_tag),
        .issue_src1_value    (rs_issue_src1_value),
        .issue_src2_value    (rs_issue_src2_value),
        .issue_branch_funct3 (rs_issue_branch_funct3),
        .issue_branch_target (rs_issue_branch_target),
        .issue_branch_NPC    (rs_issue_branch_NPC)
    );

    // ================================================================
    // LSQ - memory ops only
    // ================================================================
    lsq lsq_0 (
        .clock               (clock),
        .reset               (reset),
        .flush               (mispredict_valid),

        .dispatch_valid      (dispatch_fire && is_mem_op),
        .dispatch_is_store   (dec_wr_mem),
        .dispatch_rob_tag    (rob_dispatch_tag[0]),
        .dispatch_mem_size   (dispatch_mem_size),
        .dispatch_is_signed  (dispatch_is_signed),

        .dispatch_base_ready (dispatch_src1_ready),
        .dispatch_base_tag   (dispatch_src1_tag),
        .dispatch_base_value (dispatch_src1_value),

        .dispatch_data_ready (dispatch_data_ready),
        .dispatch_data_tag   (dispatch_data_tag),
        .dispatch_data_value (dispatch_data_value),

        .dispatch_imm        (dispatch_imm),
        .dispatch_dbg_pc     (PC_reg),

        .lsq_full            (lsq_full),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),

        .early_cdb_valid     (early_cdb_valid),
        .early_cdb_tag       (early_cdb_tag),

        .store_ready_valid   (lsq_store_ready_valid),
        .store_ready_tag     (lsq_store_ready_tag),

        .rob_commit_valid    ((rob_commit_valid[0] && rob_commit_is_store[0]) ||
                            (rob_commit_valid[1] && rob_commit_is_store[1])),
        .rob_commit_tag      ((rob_commit_valid[0] && rob_commit_is_store[0]) ? rob_commit_tag[0] :
                            ((rob_commit_valid[1] && rob_commit_is_store[1]) ? rob_commit_tag[1] : rob_commit_tag[0])),

        .dcache_load         (lsq_dcache_load),
        .dcache_store        (lsq_dcache_store),
        .dcache_addr         (lsq_dcache_addr),
        .dcache_wr_data      (lsq_dcache_wr_data),
        .dcache_wr_be        (lsq_dcache_wr_be),
        .dcache_done         (dcache_done),
        .dcache_busy         (dcache_busy),
        .dcache_rd_data      (dcache_rd_data),

        .load_complete_valid (lsq_load_complete_valid),
        .load_complete_tag   (lsq_load_complete_tag),
        .load_complete_value (lsq_load_complete_value),
        .load_complete_accept(lsq_load_complete_accept)
    );

    // The LSQ load broadcast is accepted whenever no MULT result is on
    // the CDB this cycle.  When MULT wins arbitration the LSQ holds the
    // value in its per-entry buffer and re-asserts next cycle.  A
    // flushed (poisoned) mult is not blocked on, so the LSQ can still win.
    assign lsq_load_complete_accept = lsq_load_selected;

    // ================================================================
    // D-Cache
    // ================================================================
    dcache dcache_0 (
        .clock              (clock),
        .reset              (reset),

        .Dmem2proc_response (dcache_resp_in),
        .Dmem2proc_data     (mem2proc_data),
        .Dmem2proc_tag      (mem2proc_tag),

        .proc_load          (lsq_dcache_load),
        .proc_store         (lsq_dcache_store),
        .proc_addr          (lsq_dcache_addr),
        .proc_wr_data       (lsq_dcache_wr_data),
        .proc_wr_be         (lsq_dcache_wr_be),

        .proc_rd_data       (dcache_rd_data),
        .proc_done          (dcache_done),
        .proc_busy          (dcache_busy),

        .proc2Dmem_command  (dc_proc2mem_command),
        .proc2Dmem_addr     (dc_proc2mem_addr),
        .proc2Dmem_data     (dc_proc2mem_data)
    );

    // ================================================================
    // Branch info buffer (legacy, retained for follow-up removal)
    //
    // branch_pending is now tied to 0: the branch predictor lets fetch
    // continue past unresolved branches, and mispredict recovery runs at
    // commit through the ROB sideband.  Per-branch target / funct3 info
    // now lives inside the RS entry (see rs.sv branch_* fields), so the
    // shared latches are unused -- they are kept for one commit so a
    // follow-up diff can delete them cleanly.
    // ================================================================
`ifdef SERIALIZE_BRANCHES
    // Diagnostic: milestone-3-style branch serialization.  Kept
    // behind an ifdef so `make simulate_all` keeps using the
    // speculative path.  Used to capture "golden" writeback streams
    // for wb-diff root-causing.
    logic branch_pending_reg;
    always_ff @(posedge clock) begin
        if (reset)
            branch_pending_reg <= 1'b0;
        else if (mispredict_valid)
            branch_pending_reg <= 1'b0;
        else if ((rob_commit_valid[0] && rob_commit_is_branch[0]) || (rob_commit_valid[1] && rob_commit_is_branch[1]))
            branch_pending_reg <= 1'b0;
        else if (dispatch_fire && (dec_cond_branch || dec_uncond_branch))
            branch_pending_reg <= 1'b1;
    end
    assign branch_pending    = branch_pending_reg;
`else
    assign branch_pending    = 1'b0;
`endif
    assign branch_target_buf = '0;
    assign branch_funct3_buf = '0;

    // ================================================================
    // MULT functional unit
    // ================================================================
    always_comb begin
        if (selected_mult_slot) begin
            case (ALU_FUNC'(rs_issue_op[1][4:0]))
                ALU_MUL, ALU_MULH: begin
                    mult_mcand  = {{32{rs_issue_src1_value[1][31]}}, rs_issue_src1_value[1]};
                    mult_mplier = {{32{rs_issue_src2_value[1][31]}}, rs_issue_src2_value[1]};
                end
                ALU_MULHU: begin
                    mult_mcand  = {32'b0, rs_issue_src1_value[1]};
                    mult_mplier = {32'b0, rs_issue_src2_value[1]};
                end
                ALU_MULHSU: begin
                    mult_mcand  = {{32{rs_issue_src1_value[1][31]}}, rs_issue_src1_value[1]};
                    mult_mplier = {32'b0, rs_issue_src2_value[1]};
                end
                default: begin
                    mult_mcand  = {32'b0, rs_issue_src1_value[1]};
                    mult_mplier = {32'b0, rs_issue_src2_value[1]};
                end
            endcase
        end else begin
            case (ALU_FUNC'(rs_issue_op[0][4:0]))
                ALU_MUL, ALU_MULH: begin
                    mult_mcand  = {{32{rs_issue_src1_value[0][31]}}, rs_issue_src1_value[0]};
                    mult_mplier = {{32{rs_issue_src2_value[0][31]}}, rs_issue_src2_value[0]};
                end
                ALU_MULHU: begin
                    mult_mcand  = {32'b0, rs_issue_src1_value[0]};
                    mult_mplier = {32'b0, rs_issue_src2_value[0]};
                end
                ALU_MULHSU: begin
                    mult_mcand  = {{32{rs_issue_src1_value[0][31]}}, rs_issue_src1_value[0]};
                    mult_mplier = {32'b0, rs_issue_src2_value[0]};
                end
                default: begin
                    mult_mcand  = {32'b0, rs_issue_src1_value[0]};
                    mult_mplier = {32'b0, rs_issue_src2_value[0]};
                end
            endcase
        end
    end

    mult mult_0 (
        .clock      (clock),
        .reset      (reset),
        .mcand      (mult_mcand),
        .mplier     (mult_mplier),
        .start      (selected_mult_valid),
        .product    (mult_product),
        .done       (mult_done),
        .early_done (mult_early_done)
    );

    // Early-tag producer.  Gated off by `mult_flushed` (producer poisoned
    // by an older mispredict) and by `mispredict_valid` (new mispredict
    // this cycle also clears every downstream consumer).  Consumers get a
    // tag that is 1 cycle early; the real CDB broadcast on the next cycle
    // will carry the value.
    //
    // `+define+DISABLE_EARLY_TAG` at the Makefile level forces the wire
    // to 0 without any other code change; this is the A/B regression
    // toggle called out in design §6 / requirement "Pipeline exposes a
    // compile-time escape hatch".
    `ifndef DISABLE_EARLY_TAG
        assign early_cdb_valid = mult_early_done && !mult_flushed && !mispredict_valid;
    `else
        assign early_cdb_valid = 1'b0;
    `endif
    assign early_cdb_tag = mult_dest_tag_reg;

    always_ff @(posedge clock) begin
        if (reset) begin
            mult_busy         <= 1'b0;
            mult_flushed      <= 1'b0;
            mult_dest_tag_reg <= '0;
            mult_alu_func_reg <= ALU_ADD;
        end else begin
            if (mult_done) begin
                mult_busy    <= 1'b0;
                mult_flushed <= 1'b0;
            end
            if (mispredict_valid && mult_busy && !mult_done)
                mult_flushed <= 1'b1;
            if (selected_mult_valid) begin
                mult_busy         <= 1'b1;
                mult_flushed      <= 1'b0;
                mult_dest_tag_reg <= selected_mult_slot ? rs_issue_dest_tag[1] : rs_issue_dest_tag[0];
                mult_alu_func_reg <= selected_mult_slot ? ALU_FUNC'(rs_issue_op[1][4:0]) : ALU_FUNC'(rs_issue_op[0][4:0]);
            end
        end
    end

    assign mult_done_valid = mult_done && !mult_flushed;

    genvar ai;
    generate
        for (ai = 0; ai < 2; ai++) begin : GEN_ALU
            always_comb begin
                case (ALU_FUNC'(rs_issue_op[ai][4:0]))
                    ALU_ADD:  alu_result[ai] = rs_issue_src1_value[ai] + rs_issue_src2_value[ai];
                    ALU_SUB:  alu_result[ai] = rs_issue_src1_value[ai] - rs_issue_src2_value[ai];
                    ALU_AND:  alu_result[ai] = rs_issue_src1_value[ai] & rs_issue_src2_value[ai];
                    ALU_OR:   alu_result[ai] = rs_issue_src1_value[ai] | rs_issue_src2_value[ai];
                    ALU_XOR:  alu_result[ai] = rs_issue_src1_value[ai] ^ rs_issue_src2_value[ai];
                    ALU_SLT:  alu_result[ai] = {31'b0, alu_signed_a[ai] < alu_signed_b[ai]};
                    ALU_SLTU: alu_result[ai] = {31'b0, rs_issue_src1_value[ai] < rs_issue_src2_value[ai]};
                    ALU_SRL:  alu_result[ai] = rs_issue_src1_value[ai] >> rs_issue_src2_value[ai][4:0];
                    ALU_SLL:  alu_result[ai] = rs_issue_src1_value[ai] << rs_issue_src2_value[ai][4:0];
                    ALU_SRA:  alu_result[ai] = `XLEN'(alu_signed_a[ai] >>> rs_issue_src2_value[ai][4:0]);
                    default:  alu_result[ai] = `XLEN'hdeadbeef;
                endcase
            end
            always_comb begin
                case (rs_issue_branch_funct3[ai])
                    3'b000: branch_take[ai] = (rs_issue_src1_value[ai] == rs_issue_src2_value[ai]);
                    3'b001: branch_take[ai] = (rs_issue_src1_value[ai] != rs_issue_src2_value[ai]);
                    3'b100: branch_take[ai] = (br_signed_a[ai] < br_signed_b[ai]);
                    3'b101: branch_take[ai] = (br_signed_a[ai] >= br_signed_b[ai]);
                    3'b110: branch_take[ai] = (rs_issue_src1_value[ai] < rs_issue_src2_value[ai]);
                    3'b111: branch_take[ai] = (rs_issue_src1_value[ai] >= rs_issue_src2_value[ai]);
                    default: branch_take[ai] = 1'b0;
                endcase
            end
        end
    endgenerate

    always_comb begin
        integer slot;
        integer used;
        lsq_load_selected = 1'b0;
        for (slot = 0; slot < 2; slot++) begin
            cdb_valid[slot]         = 1'b0;
            cdb_tag[slot]           = '0;
            cdb_value[slot]         = '0;
            cdb_take_branch[slot]   = 1'b0;
            cdb_branch_target[slot] = '0;
        end
        used = 0;
        if (mult_done_valid && used < 2) begin
            cdb_valid[used] = 1'b1;
            cdb_tag[used]   = mult_dest_tag_reg;
            case (mult_alu_func_reg)
                ALU_MUL:    cdb_value[used] = mult_product[`XLEN-1:0];
                ALU_MULH:   cdb_value[used] = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHU:  cdb_value[used] = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHSU: cdb_value[used] = mult_product[2*`XLEN-1:`XLEN];
                default:    cdb_value[used] = mult_product[`XLEN-1:0];
            endcase
            used = used + 1;
        end
        if (lsq_load_complete_valid && used < 2) begin
            cdb_valid[used] = 1'b1;
            cdb_tag[used]   = lsq_load_complete_tag;
            cdb_value[used] = lsq_load_complete_value;
            lsq_load_selected = 1'b1;
            used = used + 1;
        end
        for (slot = 0; slot < 2; slot++) begin
            if (issue_accept[slot] && !issue_is_mult[slot] && used < 2) begin
                cdb_valid[used] = 1'b1;
                cdb_tag[used]   = rs_issue_dest_tag[slot];
                if (rs_issue_op[slot][6]) begin
                    cdb_value[used]         = rs_issue_branch_NPC[slot];
                    cdb_take_branch[used]   = 1'b1;
                    cdb_branch_target[used] = {alu_result[slot][`XLEN-1:1], 1'b0};
                end else if (rs_issue_op[slot][5]) begin
                    cdb_value[used]         = '0;
                    cdb_take_branch[used]   = branch_take[slot];
                    cdb_branch_target[used] = rs_issue_branch_target[slot];
                end else begin
                    cdb_value[used]         = alu_result[slot];
                end
                used = used + 1;
            end
        end
    end

    // ================================================================
    // Error status register (latches halt/illegal on commit)
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset)
            error_status_reg <= NO_ERROR;
        else if (rob_commit_valid[0] || rob_commit_valid[1]) begin
            if ((rob_commit_valid[0] && rob_commit_halt[0]) || (rob_commit_valid[1] && rob_commit_halt[1]))
                error_status_reg <= HALTED_ON_WFI;
            else if ((rob_commit_valid[0] && rob_commit_illegal[0]) || (rob_commit_valid[1] && rob_commit_illegal[1]))
                error_status_reg <= ILLEGAL_INST;
        end
    end

endmodule // pipeline
