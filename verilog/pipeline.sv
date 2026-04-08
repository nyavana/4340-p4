`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

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
    // ALL wire/logic declarations (must precede any use in SV)
    // ================================================================

    // PC / fetch
    logic [`XLEN-1:0] PC_reg;
    INST              fetched_inst;
    logic [`XLEN-1:0] fetched_NPC;

    // Stall / dispatch
    logic branch_pending;
    logic stall;
    logic dispatch_fire;

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

    // Dispatch operand resolution
    logic             dispatch_src1_ready, dispatch_src2_ready;
    logic [TAG_W-1:0] dispatch_src1_tag,   dispatch_src2_tag;
    logic [`XLEN-1:0] dispatch_src1_value, dispatch_src2_value;
    logic [7:0]       dispatch_op;

    // Issue routing
    logic issue_is_mult, issue_is_branch, issue_is_load, issue_accept;

    // Branch buffer
    logic [`XLEN-1:0] branch_target_buf;
    logic [2:0]       branch_funct3_buf;

    // MULT FU
    logic             mult_busy, mult_done;
    logic [TAG_W-1:0] mult_dest_tag_reg;
    ALU_FUNC          mult_alu_func_reg;
    logic [63:0]      mult_product;
    logic [63:0]      mult_mcand, mult_mplier;

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

    // Load FU
    logic             load_busy, load_done, load_requesting;
    logic [TAG_W-1:0] load_dest_tag_reg;
    logic [`XLEN-1:0] load_addr_reg;
    logic [3:0]       load_mem_tag;
    logic [`XLEN-1:0] load_result;

    // Error status latch
    EXCEPTION_CODE error_status_reg;

    // ================================================================
    // Combinational assignments
    // ================================================================

    assign fetched_inst = PC_reg[2] ? Icache_data_out[63:32] : Icache_data_out[31:0];
    assign fetched_NPC  = PC_reg + 4;

    assign stall        = !Icache_valid_out || rs_full || rob_full || branch_pending;
    assign dispatch_fire = !stall;

    // op[7]=rd_mem, op[6]=uncond_branch, op[5]=cond_branch, op[4:0]=alu_func
    assign dispatch_op  = {dec_rd_mem, dec_uncond_branch, dec_cond_branch, dec_alu_func};

    assign issue_is_mult   = (rs_issue_op[4:0] >= 5'(ALU_MUL)) &&
                             (rs_issue_op[4:0] <= 5'(ALU_MULHU));
    assign issue_is_branch = rs_issue_op[5] | rs_issue_op[6];
    assign issue_is_load   = rs_issue_op[7];
    assign issue_accept    = rs_issue_valid &&
                             (issue_is_mult ? !mult_busy :
                              issue_is_load ? !load_busy :
                                              !mult_done && !load_done);

    assign alu_signed_a = rs_issue_src1_value;
    assign alu_signed_b = rs_issue_src2_value;
    assign br_signed_a  = rs_issue_src1_value;
    assign br_signed_b  = rs_issue_src2_value;

    // Load FU combinational signals
    assign load_requesting = load_busy && (load_mem_tag == 4'b0);
    assign load_done       = load_busy && (load_mem_tag != 4'b0) &&
                             (mem2proc_tag == load_mem_tag);
    assign load_result     = load_addr_reg[2] ? mem2proc_data[63:32]
                                              : mem2proc_data[31:0];

    // Memory bus: dcache (load) has priority over icache
    assign proc2mem_command = load_requesting ? BUS_LOAD           : proc2Imem_command;
    assign proc2mem_addr    = load_requesting ? {load_addr_reg[`XLEN-1:3], 3'b0}
                                              : proc2Imem_addr;
    assign proc2mem_data    = '0;

    // Pipeline outputs
    assign pipeline_completed_insts = {3'b0, rob_commit_valid};
    assign pipeline_commit_wr_en    = rob_commit_valid && (rob_commit_dest_reg != 5'd0);
    assign pipeline_commit_wr_idx   = rob_commit_dest_reg;
    assign pipeline_commit_wr_data  = rob_commit_value;
    assign pipeline_commit_NPC      = rob_commit_NPC;
    assign pipeline_error_status    = error_status_reg;

    // ================================================================
    // PC register
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset)
            PC_reg <= '0;
        else if (rob_commit_valid && rob_commit_take_branch)
            PC_reg <= rob_commit_branch_target;
        else if (!stall)
            PC_reg <= PC_reg + 4;
    end

    // ================================================================
    // ICache
    // ================================================================
    icache icache_0 (
        .clock              (clock),
        .reset              (reset),
        // Mask memory response/tag when dcache is using the bus,
        // so icache doesn't misinterpret dcache's transaction as its own.
        .Imem2proc_response (load_requesting ? 4'b0 : mem2proc_response),
        .Imem2proc_data     (mem2proc_data),
        .Imem2proc_tag      (load_done ? 4'b0 : mem2proc_tag),
        .proc2Icache_addr   ({PC_reg[`XLEN-1:3], 3'b0}),
        .proc2Imem_command  (proc2Imem_command),
        .proc2Imem_addr     (proc2Imem_addr),
        .Icache_data_out    (Icache_data_out),
        .Icache_valid_out   (Icache_valid_out)
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
    // Src operand resolution (opa/opb mux + RAT override)
    // ================================================================

    // src1: depends on opa_select or branch (always rs1 for cond branch)
    always_comb begin
        if (dec_cond_branch || (dec_opa_select == OPA_IS_RS1)) begin
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
            // Constant operand (PC, NPC, 0)
            dispatch_src1_ready = 1'b1;
            dispatch_src1_tag   = '0;
            case (dec_opa_select)
                OPA_IS_NPC:  dispatch_src1_value = fetched_NPC;
                OPA_IS_PC:   dispatch_src1_value = PC_reg;
                default:     dispatch_src1_value = '0;
            endcase
        end
    end

    // src2: depends on opb_select or branch (always rs2 for cond branch)
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
            // Immediate constant
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

    // ================================================================
    // ROB
    // ================================================================
    rob rob_0 (
        .clock                (clock),
        .reset                (reset),
        .flush                (1'b0),

        .dispatch_valid       (dispatch_fire),
        .dispatch_dest_reg    (dec_has_dest ? fetched_inst.r.rd : 5'd0),
        .dispatch_NPC         (fetched_NPC),
        .dispatch_halt        (dec_halt),
        .dispatch_illegal     (dec_illegal),
        .dispatch_is_branch   (dec_cond_branch || dec_uncond_branch),

        .rob_full             (rob_full),
        .dispatch_tag         (rob_dispatch_tag),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_tag),
        .cdb_value            (cdb_value),
        .cdb_take_branch      (cdb_take_branch),
        .cdb_branch_target    (cdb_branch_target),

        .commit_valid         (rob_commit_valid),
        .commit_dest_reg      (rob_commit_dest_reg),
        .commit_value         (rob_commit_value),
        .commit_NPC           (rob_commit_NPC),
        .commit_halt          (rob_commit_halt),
        .commit_illegal       (rob_commit_illegal),
        .commit_is_branch     (rob_commit_is_branch),
        .commit_take_branch   (rob_commit_take_branch),
        .commit_branch_target (rob_commit_branch_target),

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
    // RS
    // ================================================================
    rs rs_0 (
        .clock               (clock),
        .reset               (reset),
        .flush               (1'b0),

        .dispatch_valid      (dispatch_fire),
        .dispatch_op         (dispatch_op),
        .dispatch_dest_tag   (rob_dispatch_tag),

        .dispatch_src1_ready (dispatch_src1_ready),
        .dispatch_src1_tag   (dispatch_src1_tag),
        .dispatch_src1_value (dispatch_src1_value),

        .dispatch_src2_ready (dispatch_src2_ready),
        .dispatch_src2_tag   (dispatch_src2_tag),
        .dispatch_src2_value (dispatch_src2_value),

        .rs_full             (rs_full),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),

        .issue_accept        (issue_accept),
        .issue_valid         (rs_issue_valid),
        .issue_op            (rs_issue_op),
        .issue_dest_tag      (rs_issue_dest_tag),
        .issue_src1_value    (rs_issue_src1_value),
        .issue_src2_value    (rs_issue_src2_value)
    );

    // ================================================================
    // Branch info buffer
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            branch_pending    <= 1'b0;
            branch_target_buf <= '0;
            branch_funct3_buf <= '0;
        end else begin
            if (dispatch_fire && (dec_cond_branch || dec_uncond_branch)) begin
                branch_pending    <= 1'b1;
                branch_funct3_buf <= fetched_inst.b.funct3;
                if (dec_uncond_branch)
                    branch_target_buf <= PC_reg + `RV32_signext_Jimm(fetched_inst);
                else
                    branch_target_buf <= PC_reg + `RV32_signext_Bimm(fetched_inst);
            end
            if (rob_commit_valid && rob_commit_is_branch)
                branch_pending <= 1'b0;
        end
    end

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
        .clock   (clock),
        .reset   (reset),
        .mcand   (mult_mcand),
        .mplier  (mult_mplier),
        .start   (issue_accept && issue_is_mult),
        .product (mult_product),
        .done    (mult_done)
    );

    always_ff @(posedge clock) begin
        if (reset) begin
            mult_busy         <= 1'b0;
            mult_dest_tag_reg <= '0;
            mult_alu_func_reg <= ALU_ADD;
        end else begin
            if (mult_done)
                mult_busy <= 1'b0;
            if (issue_accept && issue_is_mult) begin
                mult_busy         <= 1'b1;
                mult_dest_tag_reg <= rs_issue_dest_tag;
                mult_alu_func_reg <= ALU_FUNC'(rs_issue_op[4:0]);
            end
        end
    end

    // ================================================================
    // Load FU state machine
    // ================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            load_busy         <= 1'b0;
            load_dest_tag_reg <= '0;
            load_addr_reg     <= '0;
            load_mem_tag      <= 4'b0;
        end else begin
            // Clear busy when data arrives (load_done is combinational)
            if (load_done)
                load_busy <= 1'b0;

            // Capture memory response tag for our outstanding request
            if (load_requesting && mem2proc_response != 4'b0)
                load_mem_tag <= mem2proc_response;

            // Clear tag when done
            if (load_done)
                load_mem_tag <= 4'b0;

            // New load issued from RS: capture address (rs1+imm) and dest tag
            // issue_accept=0 when load_busy, so this won't conflict with load_done
            if (issue_accept && issue_is_load) begin
                load_busy         <= 1'b1;
                load_dest_tag_reg <= rs_issue_dest_tag;
                load_addr_reg     <= alu_result; // ALU computes rs1 + I_imm
                load_mem_tag      <= 4'b0;
            end
        end
    end

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

    // Conditional branch outcome
    always_comb begin
        case (branch_funct3_buf)
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
    //   Priority 1: MULT (multicycle, blocks ALU)
    //   Priority 2: LOAD (multicycle, blocks ALU)
    //   Priority 3: ALU  (single-cycle, blocked by mult_done / load_done)
    // ================================================================
    always_comb begin
        cdb_valid         = 1'b0;
        cdb_tag           = '0;
        cdb_value         = '0;
        cdb_take_branch   = 1'b0;
        cdb_branch_target = '0;

        if (mult_done) begin
            cdb_valid = 1'b1;
            cdb_tag   = mult_dest_tag_reg;
            case (mult_alu_func_reg)
                ALU_MUL:    cdb_value = mult_product[`XLEN-1:0];
                ALU_MULH:   cdb_value = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHU:  cdb_value = mult_product[2*`XLEN-1:`XLEN];
                ALU_MULHSU: cdb_value = mult_product[2*`XLEN-1:`XLEN];
                default:    cdb_value = mult_product[`XLEN-1:0];
            endcase
        end else if (load_done) begin
            cdb_valid = 1'b1;
            cdb_tag   = load_dest_tag_reg;
            cdb_value = load_result;
        end else if (issue_accept && !issue_is_mult && !issue_is_load) begin
            cdb_valid = 1'b1;
            cdb_tag   = rs_issue_dest_tag;
            if (rs_issue_op[6]) begin          // uncond branch (JAL)
                cdb_value         = '0;
                cdb_take_branch   = 1'b1;
                cdb_branch_target = branch_target_buf;
            end else if (rs_issue_op[5]) begin // cond branch
                cdb_value         = '0;
                cdb_take_branch   = branch_take;
                cdb_branch_target = branch_target_buf;
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
