`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

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
    INST              fetched_inst;
    logic [`XLEN-1:0] fetched_NPC;

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
    ALU_OPA_SELECT dec_opa_select;
    ALU_OPB_SELECT dec_opb_select;
    logic          dec_has_dest;
    ALU_FUNC       dec_alu_func;
    logic          dec_rd_mem, dec_wr_mem;
    logic          dec_cond_branch, dec_uncond_branch;
    logic          dec_csr_op, dec_halt, dec_illegal;

    // Regfile outputs
    logic [`XLEN-1:0] rf_rs1_value, rf_rs2_value;

    // ROB outputs
    logic             rob_full;
    logic [TAG_W-1:0] rob_dispatch_tag;
    logic             rob_commit_valid;
    logic [TAG_W-1:0] rob_commit_tag;
    logic             rob_commit_is_store;
    logic [4:0]       rob_commit_dest_reg;
    logic [`XLEN-1:0] rob_commit_value;
    logic [`XLEN-1:0] rob_commit_NPC;
    logic             rob_commit_halt;
    logic             rob_commit_illegal;
    logic             rob_commit_is_branch;
    logic             rob_commit_take_branch;
    logic [`XLEN-1:0] rob_commit_branch_target;
    logic             rat_q1_pending, rat_q1_ready;
    logic [TAG_W-1:0] rat_q1_tag;
    logic [`XLEN-1:0] rat_q1_value;
    logic             rat_q2_pending, rat_q2_ready;
    logic [TAG_W-1:0] rat_q2_tag;
    logic [`XLEN-1:0] rat_q2_value;

    // RS outputs
    logic             rs_full;
    logic             rs_issue_valid;
    logic [7:0]       rs_issue_op;
    logic [TAG_W-1:0] rs_issue_dest_tag;
    logic [`XLEN-1:0] rs_issue_src1_value;
    logic [`XLEN-1:0] rs_issue_src2_value;
    logic [2:0]       rs_issue_branch_funct3;
    logic [`XLEN-1:0] rs_issue_branch_target;
    logic [`XLEN-1:0] rs_issue_branch_NPC;

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

    // Issue routing
    logic issue_is_mult, issue_is_branch, issue_accept;

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
    logic             rob_commit_is_uncond_branch;
    logic [`XLEN-1:0] rob_commit_branch_PC;

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
    logic [`XLEN-1:0] alu_result;
    logic signed [`XLEN-1:0] alu_signed_a, alu_signed_b;
    logic             branch_take;
    logic signed [`XLEN-1:0] br_signed_a, br_signed_b;

    // CDB
    logic             cdb_valid;
    logic [TAG_W-1:0] cdb_tag;
    logic [`XLEN-1:0] cdb_value;
    logic             cdb_take_branch;
    logic [`XLEN-1:0] cdb_branch_target;

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

    // Error status latch
    EXCEPTION_CODE error_status_reg;

    // ================================================================
    // Combinational assignments
    // ================================================================

    assign fetched_inst = PC_reg[2] ? Icache_data_out[63:32] : Icache_data_out[31:0];
    assign fetched_NPC  = PC_reg + 4;

    assign is_mem_op = dec_rd_mem || dec_wr_mem;

    // branch_pending is no longer used - the branch predictor lets fetch
    // run past unresolved branches, and mispredict recovery is handled at
    // commit via the ROB's mispredict sideband.
    assign stall = !Icache_valid_out || rob_full || branch_pending ||
                   (is_mem_op ? lsq_full : rs_full);
    assign dispatch_fire = !stall;

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
    end

    // op[7]=rd_mem, op[6]=uncond_branch, op[5]=cond_branch, op[4:0]=alu_func
    assign dispatch_op   = {dec_rd_mem, dec_uncond_branch, dec_cond_branch, dec_alu_func};

    // mem_size from funct3[1:0] (00=BYTE, 01=HALF, 10=WORD)
    assign dispatch_mem_size  = fetched_inst.r.funct3[1:0];
    assign dispatch_is_signed = !fetched_inst.r.funct3[2];

    // Dispatched immediate (sign-extended I-imm for loads, S-imm for stores)
    always_comb begin
        if (dec_wr_mem)
            dispatch_imm = `RV32_signext_Simm(fetched_inst);
        else
            dispatch_imm = `RV32_signext_Iimm(fetched_inst);
    end

    assign issue_is_mult   = (rs_issue_op[4:0] >= 5'(ALU_MUL)) &&
                             (rs_issue_op[4:0] <= 5'(ALU_MULHU));
    assign issue_is_branch = rs_issue_op[5] | rs_issue_op[6];
    assign issue_accept    = rs_issue_valid &&
                             (issue_is_mult ? !mult_busy
                                            : !mult_done_valid && !lsq_load_complete_valid);

    assign alu_signed_a = rs_issue_src1_value;
    assign alu_signed_b = rs_issue_src2_value;
    assign br_signed_a  = rs_issue_src1_value;
    assign br_signed_b  = rs_issue_src2_value;

    // ----------------------------------------------------------------
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
    wire dcache_drives = (dc_proc2mem_command != BUS_NONE);
    wire icache_drives = !dcache_drives && (proc2Imem_command != BUS_NONE);

    assign proc2mem_command = dcache_drives ? dc_proc2mem_command :
                              icache_drives ? proc2Imem_command   : BUS_NONE;
    assign proc2mem_addr    = dcache_drives ? dc_proc2mem_addr    : proc2Imem_addr;
    assign proc2mem_data    = dcache_drives ? dc_proc2mem_data    : 64'b0;

    // Mask each cache's view of mem2proc_response so it only sees
    // responses for requests IT drove.  At the next posedge when the
    // cache's always_ff samples the comb signals, icache_drives /
    // dcache_drives reflect the PREVIOUS cycle's register state -
    // exactly the cycle during which the response was allocated.
    assign icache_resp_in = icache_drives ? mem2proc_response : 4'b0;
    assign dcache_resp_in = dcache_drives ? mem2proc_response : 4'b0;

    // Pipeline outputs
    assign pipeline_completed_insts = {3'b0, rob_commit_valid};
    assign pipeline_commit_wr_en    = rob_commit_valid && (rob_commit_dest_reg != 5'd0);
    assign pipeline_commit_wr_idx   = rob_commit_dest_reg;
    assign pipeline_commit_wr_data  = rob_commit_value;
    assign pipeline_commit_NPC      = rob_commit_NPC;
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
    // Diagnostic: kill the predictor output so fetch behaves as
    // "always predict not-taken".  Used to isolate predictor-induced
    // bugs from the rest of the front-end.
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

        .update_valid     (rob_commit_valid && rob_commit_is_branch),
        .update_PC        (rob_commit_branch_PC),
        .update_target    (rob_commit_branch_target),
        .update_taken     (rob_commit_take_branch),
        .update_is_uncond (rob_commit_is_uncond_branch)
    );

    // ================================================================
    // Decoder
    // ================================================================
    decoder decoder_0 (
        .inst          (fetched_inst),
        .valid         (Icache_valid_out),
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

    // ================================================================
    // Regfile
    // ================================================================
    regfile regfile_0 (
        .clock      (clock),
        .read_idx_1 (fetched_inst.r.rs1),
        .read_idx_2 (fetched_inst.r.rs2),
        .write_en   (rob_commit_valid && (rob_commit_dest_reg != 5'd0)),
        .write_idx  (rob_commit_dest_reg),
        .write_data (rob_commit_value),
        .read_out_1 (rf_rs1_value),
        .read_out_2 (rf_rs2_value)
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

    // ================================================================
    // ROB
    // ================================================================
    rob rob_0 (
        .clock                (clock),
        .reset                (reset),
        .flush                (mispredict_valid),

        .dispatch_valid       (dispatch_fire),
        .dispatch_dest_reg    (dec_has_dest ? fetched_inst.r.rd : 5'd0),
        .dispatch_NPC         (fetched_NPC),
        .dispatch_PC          (PC_reg),
        .dispatch_halt        (dec_halt),
        .dispatch_illegal     (dec_illegal),
        .dispatch_is_branch   (dec_cond_branch || dec_uncond_branch),
        .dispatch_is_uncond_branch (dec_uncond_branch),
        .dispatch_is_store    (dec_wr_mem),

        // Only branches carry a real prediction; non-branches dispatch with
        // predicted_taken=0, predicted_target=0 so the commit-time
        // mispredict check is a no-op for them.
        .dispatch_predicted_taken  ((dec_cond_branch || dec_uncond_branch) && pred_valid && pred_taken),
        .dispatch_predicted_target ((dec_cond_branch || dec_uncond_branch) ? pred_target : 32'b0),

        .rob_full             (rob_full),
        .dispatch_tag         (rob_dispatch_tag),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_tag),
        .cdb_value            (cdb_value),
        .cdb_take_branch      (cdb_take_branch),
        .cdb_branch_target    (cdb_branch_target),

        .store_done_valid     (lsq_store_ready_valid),
        .store_done_tag       (lsq_store_ready_tag),

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
        .query2_value         (rat_q2_value)
    );

    // ================================================================
    // RS - non-memory ops only
    // ================================================================
    rs rs_0 (
        .clock               (clock),
        .reset               (reset),
        .flush               (mispredict_valid),

        .dispatch_valid      (dispatch_fire && !is_mem_op),
        .dispatch_op         (dispatch_op),
        .dispatch_dest_tag   (rob_dispatch_tag),

        .dispatch_src1_ready (dispatch_src1_ready),
        .dispatch_src1_tag   (dispatch_src1_tag),
        .dispatch_src1_value (dispatch_src1_value),

        .dispatch_src2_ready (dispatch_src2_ready),
        .dispatch_src2_tag   (dispatch_src2_tag),
        .dispatch_src2_value (dispatch_src2_value),

        .dispatch_branch_funct3 (dispatch_branch_funct3),
        .dispatch_branch_target (dispatch_branch_target),
        .dispatch_branch_NPC    (fetched_NPC),

        .rs_full             (rs_full),

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
        .dispatch_rob_tag    (rob_dispatch_tag),
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

        .rob_commit_valid    (rob_commit_valid),
        .rob_commit_tag      (rob_commit_tag),

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
    assign lsq_load_complete_accept = lsq_load_complete_valid && !mult_done_valid;

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
        else if (rob_commit_valid && rob_commit_is_branch)
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
        case (ALU_FUNC'(rs_issue_op[4:0]))
            ALU_MUL, ALU_MULH: begin
                mult_mcand  = {{32{rs_issue_src1_value[31]}}, rs_issue_src1_value};
                mult_mplier = {{32{rs_issue_src2_value[31]}}, rs_issue_src2_value};
            end
            ALU_MULHU: begin
                mult_mcand  = {32'b0, rs_issue_src1_value};
                mult_mplier = {32'b0, rs_issue_src2_value};
            end
            ALU_MULHSU: begin
                mult_mcand  = {{32{rs_issue_src1_value[31]}}, rs_issue_src1_value};
                mult_mplier = {32'b0, rs_issue_src2_value};
            end
            default: begin
                mult_mcand  = {32'b0, rs_issue_src1_value};
                mult_mplier = {32'b0, rs_issue_src2_value};
            end
        endcase
    end

    mult mult_0 (
        .clock      (clock),
        .reset      (reset),
        .mcand      (mult_mcand),
        .mplier     (mult_mplier),
        .start      (issue_accept && issue_is_mult),
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
            // Mispredict: any mult currently churning is targeting a ROB
            // slot that is about to be cleared / re-allocated.  Mark its
            // output as poisoned so we drop it when it eventually reports
            // done.
            if (mispredict_valid && mult_busy && !mult_done)
                mult_flushed <= 1'b1;
            if (issue_accept && issue_is_mult) begin
                mult_busy         <= 1'b1;
                mult_flushed      <= 1'b0;
                mult_dest_tag_reg <= rs_issue_dest_tag;
                mult_alu_func_reg <= ALU_FUNC'(rs_issue_op[4:0]);
            end
        end
    end

    assign mult_done_valid = mult_done && !mult_flushed;

    // ================================================================
    // ALU (single-cycle, inline)
    // ================================================================
    always_comb begin
        case (ALU_FUNC'(rs_issue_op[4:0]))
            ALU_ADD:  alu_result = rs_issue_src1_value + rs_issue_src2_value;
            ALU_SUB:  alu_result = rs_issue_src1_value - rs_issue_src2_value;
            ALU_AND:  alu_result = rs_issue_src1_value & rs_issue_src2_value;
            ALU_OR:   alu_result = rs_issue_src1_value | rs_issue_src2_value;
            ALU_XOR:  alu_result = rs_issue_src1_value ^ rs_issue_src2_value;
            ALU_SLT:  alu_result = {31'b0, alu_signed_a < alu_signed_b};
            ALU_SLTU: alu_result = {31'b0, rs_issue_src1_value < rs_issue_src2_value};
            ALU_SRL:  alu_result = rs_issue_src1_value >> rs_issue_src2_value[4:0];
            ALU_SLL:  alu_result = rs_issue_src1_value << rs_issue_src2_value[4:0];
            ALU_SRA:  alu_result = `XLEN'(alu_signed_a >>> rs_issue_src2_value[4:0]);
            default:  alu_result = `XLEN'hdeadbeef;
        endcase
    end

    // Conditional branch outcome (funct3 now travels with the RS entry)
    always_comb begin
        case (rs_issue_branch_funct3)
            3'b000: branch_take = (rs_issue_src1_value == rs_issue_src2_value); // BEQ
            3'b001: branch_take = (rs_issue_src1_value != rs_issue_src2_value); // BNE
            3'b100: branch_take = (br_signed_a < br_signed_b);                  // BLT
            3'b101: branch_take = (br_signed_a >= br_signed_b);                 // BGE
            3'b110: branch_take = (rs_issue_src1_value < rs_issue_src2_value);  // BLTU
            3'b111: branch_take = (rs_issue_src1_value >= rs_issue_src2_value); // BGEU
            default: branch_take = 1'b0;
        endcase
    end

    // ================================================================
    // CDB arbitration:
    //   Priority 1: MULT (multicycle)
    //   Priority 2: LSQ load complete (multicycle, blocked by mult_done)
    //   Priority 3: ALU (single-cycle, blocked by either of the above)
    //
    // Stores never go on the CDB; they use the store_done sideband on
    // the ROB instead.
    // ================================================================
    always_comb begin
        cdb_valid         = 1'b0;
        cdb_tag           = '0;
        cdb_value         = '0;
        cdb_take_branch   = 1'b0;
        cdb_branch_target = '0;

        if (mult_done_valid) begin
            cdb_valid = 1'b1;
            cdb_tag   = mult_dest_tag_reg;
            case (mult_alu_func_reg)
                ALU_MUL:    cdb_value = mult_product[`XLEN-1:0];
                ALU_MULH:   cdb_value = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHU:  cdb_value = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHSU: cdb_value = mult_product[2*`XLEN-1:`XLEN];
                default:    cdb_value = mult_product[`XLEN-1:0];
            endcase
        end else if (lsq_load_complete_valid) begin
            cdb_valid = 1'b1;
            cdb_tag   = lsq_load_complete_tag;
            cdb_value = lsq_load_complete_value;
        end else if (issue_accept && !issue_is_mult) begin
            cdb_valid = 1'b1;
            cdb_tag   = rs_issue_dest_tag;
            if (rs_issue_op[6]) begin          // uncond branch (JAL/JALR)
                // The ALU computes the target for both JAL (PC + J_imm)
                // and JALR (rs1 + I_imm).  Clearing bit 0 is a no-op
                // for JAL and matches the JALR spec.  The CDB value is the
                // return address (NPC) so that any CDB-bypass consumer
                // (RS/LSQ wakeup, RAT query bypass) sees the correct link
                // register value instead of 0.  The ROB's commit-value
                // override (entries[head].NPC) becomes redundant but is
                // left in place so correctness is not double-dependent on
                // this CDB fix.
                cdb_value         = rs_issue_branch_NPC;
                cdb_take_branch   = 1'b1;
                cdb_branch_target = {alu_result[`XLEN-1:1], 1'b0};
            end else if (rs_issue_op[5]) begin // cond branch
                cdb_value         = '0;
                cdb_take_branch   = branch_take;
                cdb_branch_target = rs_issue_branch_target;
            end else begin                     // regular ALU
                cdb_value         = alu_result;
                cdb_take_branch   = 1'b0;
                cdb_branch_target = '0;
            end
        end
    end

    // ================================================================
    // Error status register (latches halt/illegal on commit)
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset)
            error_status_reg <= NO_ERROR;
        else if (rob_commit_valid) begin
            if (rob_commit_halt)
                error_status_reg <= HALTED_ON_WFI;
            else if (rob_commit_illegal)
                error_status_reg <= ILLEGAL_INST;
        end
    end

endmodule // pipeline
