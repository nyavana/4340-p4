/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  pipeline_test.sv                                    //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline;       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

// P4 TODO: Add your own debugging framework. Basic printing of data structures
//          is an absolute necessity for the project. You can use C functions
//          like in test/pipeline_print.c or just do everything in verilog.
//          Be careful about running out of space on CAEN printing lots of state
//          for longer programs (alexnet, outer_product, etc.)


// these link to the pipeline_print.c file in this directory, and are used below to print
// detailed output to the pipeline_output_file, initialized by open_pipeline_output_file()
// import "DPI-C" function void open_pipeline_output_file(string file_name);
// import "DPI-C" function void print_header(string str);
// import "DPI-C" function void print_cycles();
// import "DPI-C" function void print_stage(string div, int inst, int npc, int valid_inst);
// import "DPI-C" function void print_reg(int wb_reg_wr_data_out_hi, int wb_reg_wr_data_out_lo,
//                                        int wb_reg_wr_idx_out, int wb_reg_wr_en_out);
// import "DPI-C" function void print_membus(int proc2mem_command, int mem2proc_response,
//                                           int proc2mem_addr_hi, int proc2mem_addr_lo,
//                                           int proc2mem_data_hi, int proc2mem_data_lo);
// import "DPI-C" function void print_close();


module testbench;
    // used to parameterize which files are used for memory and writeback/pipeline outputs
    // "./simv" uses program.mem, writeback.out, and pipeline.out
    // but now "./simv +MEMORY=<my_program>.mem" loads <my_program>.mem instead
    // use +WRITEBACK=<my_program>.wb and +PIPELINE=<my_program>.ppln for those outputs as well
    string program_memory_file;
    string writeback_output_file;
    // string pipeline_output_file;

    // variables used in the testbench
    logic        clock;
    logic        reset;
    logic [31:0] clock_count;
    logic [31:0] instr_count;
    int          wb_fileno;
    int          store_fileno;
    logic [63:0] debug_counter; // counter used for infinite loops, forces termination

    logic [1:0]       proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0]      proc2mem_data;
    logic [3:0]       mem2proc_response;
    logic [63:0]      mem2proc_data;
    logic [3:0]       mem2proc_tag;
`ifndef CACHE_MODE
    MEM_SIZE          proc2mem_size;
`endif

    logic [3:0]       pipeline_completed_insts;
    EXCEPTION_CODE    pipeline_error_status;
    logic [4:0]       pipeline_commit_wr_idx;
    logic [`XLEN-1:0] pipeline_commit_wr_data;
    logic             pipeline_commit_wr_en;
    logic [`XLEN-1:0] pipeline_commit_NPC;

    // Hang watchdog: a ring of the last WATCHDOG_RING_LEN snapshots,
    // one snapshot every WATCHDOG_PERIOD cycles.  Dumped on timeout
    // (debug_counter > 50M) so we can tell whether quicksort /
    // sort_search are genuinely stuck and on what instruction.
    localparam int WATCHDOG_PERIOD   = 1000;
    localparam int WATCHDOG_RING_LEN = 16;
    logic [63:0]      wd_cycle [WATCHDOG_RING_LEN];
    logic [`XLEN-1:0] wd_pc    [WATCHDOG_RING_LEN];
    logic             wd_stall [WATCHDOG_RING_LEN];
    logic             wd_misp  [WATCHDOG_RING_LEN];
    logic [31:0]      wd_rob_head [WATCHDOG_RING_LEN];
    logic [31:0]      wd_rob_cnt  [WATCHDOG_RING_LEN];
    logic [31:0]      wd_lsq_head [WATCHDOG_RING_LEN];
    logic [31:0]      wd_lsq_cnt  [WATCHDOG_RING_LEN];
    // Captures enough LSQ-head + cache state to tell whether a
    // persistent hang is a load waiting on the D-cache, a store stuck
    // on release, or an I-cache miss being starved by the D-cache.
    // lsqh_bits: {busy, is_store, committed, in_flight, addr_valid,
    //             base_ready, load_buf_valid, stale_resp_pending}
    logic [7:0]       wd_lsqh_bits [WATCHDOG_RING_LEN];
    logic [`XLEN-1:0] wd_lsqh_addr [WATCHDOG_RING_LEN];
    // cache_bits: {icache_valid, dcache_busy, dcache_done,
    //              dcache_drives, icache_drives}
    logic [4:0]       wd_cache_bits [WATCHDOG_RING_LEN];
    logic [31:0]      wd_idx;
    logic [31:0]      wd_nvalid;

    // Prediction-accuracy counters.  `branches_committed` counts every
    // committing branch; `mispredicts` counts the one-cycle
    // mispredict_valid pulses from the ROB.  Ratio printed at halt.
    logic [63:0] branches_committed;
    logic [63:0] mispredicts;

    // logic [`XLEN-1:0] if_NPC_dbg;
    // logic [31:0]      if_inst_dbg;
    // logic             if_valid_dbg;
    // logic [`XLEN-1:0] if_id_NPC_dbg;
    // logic [31:0]      if_id_inst_dbg;
    // logic             if_id_valid_dbg;
    // logic [`XLEN-1:0] id_ex_NPC_dbg;
    // logic [31:0]      id_ex_inst_dbg;
    // logic             id_ex_valid_dbg;
    // logic [`XLEN-1:0] ex_mem_NPC_dbg;
    // logic [31:0]      ex_mem_inst_dbg;
    // logic             ex_mem_valid_dbg;
    // logic [`XLEN-1:0] mem_wb_NPC_dbg;
    // logic [31:0]      mem_wb_inst_dbg;
    // logic             mem_wb_valid_dbg;


    // Instantiate the Pipeline
    pipeline core (
        // Inputs
        .clock             (clock),
        .reset             (reset),
        .mem2proc_response (mem2proc_response),
        .mem2proc_data     (mem2proc_data),
        .mem2proc_tag      (mem2proc_tag),

        // Outputs
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        .pipeline_completed_insts (pipeline_completed_insts),
        .pipeline_error_status    (pipeline_error_status),
        .pipeline_commit_wr_data  (pipeline_commit_wr_data),
        .pipeline_commit_wr_idx   (pipeline_commit_wr_idx),
        .pipeline_commit_wr_en    (pipeline_commit_wr_en),
        .pipeline_commit_NPC      (pipeline_commit_NPC)

        // .if_NPC_dbg       (if_NPC_dbg),
        // .if_inst_dbg      (if_inst_dbg),
        // .if_valid_dbg     (if_valid_dbg),
        // .if_id_NPC_dbg    (if_id_NPC_dbg),
        // .if_id_inst_dbg   (if_id_inst_dbg),
        // .if_id_valid_dbg  (if_id_valid_dbg),
        // .id_ex_NPC_dbg    (id_ex_NPC_dbg),
        // .id_ex_inst_dbg   (id_ex_inst_dbg),
        // .id_ex_valid_dbg  (id_ex_valid_dbg),
        // .ex_mem_NPC_dbg   (ex_mem_NPC_dbg),
        // .ex_mem_inst_dbg  (ex_mem_inst_dbg),
        // .ex_mem_valid_dbg (ex_mem_valid_dbg),
        // .mem_wb_NPC_dbg   (mem_wb_NPC_dbg),
        // .mem_wb_inst_dbg  (mem_wb_inst_dbg),
        // .mem_wb_valid_dbg (mem_wb_valid_dbg)
    );


    // Instantiate the Data Memory
    mem memory (
        // Inputs
        .clk              (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        // Outputs
        .mem2proc_response (mem2proc_response),
        .mem2proc_data     (mem2proc_data),
        .mem2proc_tag      (mem2proc_tag)
    );


    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end


    // Task to display # of elapsed clock edges
    task show_clk_count;
        real cpi;
        begin
            cpi = (clock_count + 1.0) / instr_count;
            $display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
                      clock_count+1, instr_count, cpi);
            $display("@@  %4.2f ns total time to execute\n@@\n",
                      clock_count * `CLOCK_PERIOD);
        end
    endtask // task show_clk_count


    // Show contents of a range of Unified Memory, in both hex and decimal
    task show_mem_with_decimal;
        input [31:0] start_addr;
        input [31:0] end_addr;
        int showing_data;
        begin
            $display("@@@");
            showing_data=0;
            for(int k=start_addr;k<=end_addr; k=k+1)
                if (memory.unified_memory[k] != 0) begin
                    $display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data=1;
                end else if(showing_data!=0) begin
                    $display("@@@");
                    showing_data=0;
                end
            $display("@@@");
        end
    endtask // task show_mem_with_decimal


    initial begin
        //$dumpvars;

        // P4 NOTE: You must keep memory loading here the same for the autograder
        //          Other things can be tampered with somewhat
        //          Definitely feel free to add new output files

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Loading memory file: %s", program_memory_file);
        end else begin
            $display("Loading default memory file: program.mem");
            program_memory_file = "program.mem";
        end
        if ($value$plusargs("WRITEBACK=%s", writeback_output_file)) begin
            $display("Using writeback output file: %s", writeback_output_file);
        end else begin
            $display("Using default writeback output file: writeback.out");
            writeback_output_file = "writeback.out";
        end
        // if ($value$plusargs("PIPELINE=%s", pipeline_output_file)) begin
        //     $display("Using pipeline output file: %s", pipeline_output_file);
        // end else begin
        //     $display("Using default pipeline output file: pipeline.out");
        //     pipeline_output_file = "pipeline.out";
        // end

        clock = 1'b0;
        reset = 1'b0;

        // Pulse the reset signal
        $display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
        reset = 1'b1;
        @(posedge clock);
        @(posedge clock);

        // store the compiled program's hex data into memory
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        @(posedge clock);
        #1;
        // This reset is at an odd time to avoid the pos & neg clock edges

        reset = 1'b0;
        $display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);

        wb_fileno = $fopen(writeback_output_file);
        // Side-channel store trace for debugging: every cycle the LSQ
        // hands a store to the D-cache, log (addr, data, be).  Writes
        // to <writeback_output_file>.stores next to the wb stream.
        store_fileno = $fopen({writeback_output_file, ".stores"});

        // Open the pipeline output file after throwing reset
        // open_pipeline_output_file(pipeline_output_file);
        // print_header("removed for line length");
    end


    // Count the number of posedges and number of instructions completed
    // till simulation ends
    always @(posedge clock) begin
        if(reset) begin
            clock_count <= 0;
            instr_count <= 0;
        end else begin
            clock_count <= (clock_count + 1);
            instr_count <= (instr_count + pipeline_completed_insts);
        end
    end

    // Prediction-accuracy counters and hang-watchdog snapshot ring.
    // The ROB's commit-side branch signal and the pipeline's
    // mispredict_valid are read through hierarchical references so no
    // extra ports have to be plumbed through the pipeline.
    always @(posedge clock) begin
        if (reset) begin
            branches_committed <= '0;
            mispredicts        <= '0;
            wd_idx             <= '0;
            wd_nvalid          <= '0;
            for (int k = 0; k < WATCHDOG_RING_LEN; k = k + 1) begin
                wd_cycle     [k] <= '0;
                wd_pc        [k] <= '0;
                wd_stall     [k] <= 1'b0;
                wd_misp      [k] <= 1'b0;
                wd_rob_head  [k] <= '0;
                wd_rob_cnt   [k] <= '0;
                wd_lsq_head  [k] <= '0;
                wd_lsq_cnt   [k] <= '0;
                wd_lsqh_bits [k] <= '0;
                wd_lsqh_addr [k] <= '0;
                wd_cache_bits[k] <= '0;
            end
        end else begin
            if (core.rob_commit_valid && core.rob_commit_is_branch)
                branches_committed <= branches_committed + 1'b1;
            if (core.mispredict_valid)
                mispredicts <= mispredicts + 1'b1;

            // Snapshot once every WATCHDOG_PERIOD cycles.
            if ((clock_count % WATCHDOG_PERIOD) == 0) begin
                wd_cycle   [wd_idx] <= {32'b0, clock_count};
                wd_pc      [wd_idx] <= core.PC_reg;
                wd_stall   [wd_idx] <= core.stall;
                wd_misp    [wd_idx] <= core.mispredict_valid;
                wd_rob_head[wd_idx] <= 32'(core.rob_0.head);
                wd_rob_cnt [wd_idx] <= 32'(core.rob_0.count);
                wd_lsq_head[wd_idx] <= 32'(core.lsq_0.head);
                wd_lsq_cnt [wd_idx] <= 32'(core.lsq_0.count);
                wd_lsqh_bits[wd_idx] <= {
                    core.lsq_0.entries[core.lsq_0.head].busy,
                    core.lsq_0.entries[core.lsq_0.head].is_store,
                    core.lsq_0.entries[core.lsq_0.head].committed,
                    core.lsq_0.entries[core.lsq_0.head].in_flight,
                    core.lsq_0.entries[core.lsq_0.head].addr_valid,
                    core.lsq_0.entries[core.lsq_0.head].base_ready,
                    core.lsq_0.entries[core.lsq_0.head].load_buf_valid,
                    (core.lsq_0.stale_response_count != '0)
                };
                wd_lsqh_addr[wd_idx] <= core.lsq_0.entries[core.lsq_0.head].addr;
                wd_cache_bits[wd_idx] <= {
                    core.Icache_valid_out,
                    core.dcache_busy,
                    core.dcache_done,
                    core.dcache_drives,
                    core.icache_drives
                };
                wd_idx              <= (wd_idx == WATCHDOG_RING_LEN - 1) ? '0 : wd_idx + 1'b1;
                if (wd_nvalid < WATCHDOG_RING_LEN)
                    wd_nvalid       <= wd_nvalid + 1'b1;
            end
        end
    end

    // Dumps the watchdog ring in temporal order (oldest first).
    task dump_watchdog_ring;
        int start_i;
        int k;
        int ring_i;
        begin
            $display("@@@");
            $display("@@@ Watchdog ring (last %0d snapshots, ~every %0d cycles):",
                     wd_nvalid, WATCHDOG_PERIOD);
            $display("@@@ cols: cycle PC st mi rH rN lH lN | lsqh[busy,st,cm,ifl,av,br,lbv,srp] addr | icv dcb dcd dcdr icdr");
            if (wd_nvalid < WATCHDOG_RING_LEN)
                start_i = 0;
            else
                start_i = wd_idx;
            for (k = 0; k < wd_nvalid; k = k + 1) begin
                ring_i = (start_i + k) % WATCHDOG_RING_LEN;
                $display("@@@ %8d %08x  %0d  %0d  %0d %0d  %0d %0d | %08b %08x | %05b",
                         wd_cycle[ring_i], wd_pc[ring_i],
                         wd_stall[ring_i], wd_misp[ring_i],
                         wd_rob_head[ring_i], wd_rob_cnt[ring_i],
                         wd_lsq_head[ring_i], wd_lsq_cnt[ring_i],
                         wd_lsqh_bits[ring_i], wd_lsqh_addr[ring_i],
                         wd_cache_bits[ring_i]);
            end
            $display("@@@");
        end
    endtask


    always @(negedge clock) begin
        if(reset) begin
            $display("@@\n@@  %t : System STILL at reset, can't show anything\n@@",
                     $realtime);
            debug_counter <= 0;
        end else begin
            #0.1;

            // print the pipeline debug outputs via c code to the pipeline output file
            // print_cycles();
            // print_stage(" ", if_inst_dbg,     if_NPC_dbg    [31:0], {31'b0,if_valid_dbg});
            // print_stage("|", if_id_inst_dbg,  if_id_NPC_dbg [31:0], {31'b0,if_id_valid_dbg});
            // print_stage("|", id_ex_inst_dbg,  id_ex_NPC_dbg [31:0], {31'b0,id_ex_valid_dbg});
            // print_stage("|", ex_mem_inst_dbg, ex_mem_NPC_dbg[31:0], {31'b0,ex_mem_valid_dbg});
            // print_stage("|", mem_wb_inst_dbg, mem_wb_NPC_dbg[31:0], {31'b0,mem_wb_valid_dbg});
            // print_reg(32'b0, pipeline_commit_wr_data[31:0],
            //     {27'b0,pipeline_commit_wr_idx}, {31'b0,pipeline_commit_wr_en});
            // print_membus({30'b0,proc2mem_command}, {28'b0,mem2proc_response},
            //     32'b0, proc2mem_addr[31:0],
            //     proc2mem_data[63:32], proc2mem_data[31:0]);

            // print register write information to the writeback output file
            if (pipeline_completed_insts > 0) begin
                if(pipeline_commit_wr_en)
                    $fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
                              pipeline_commit_NPC - 4,
                              pipeline_commit_wr_idx,
                              pipeline_commit_wr_data);
                else
                    $fdisplay(wb_fileno, "PC=%x, ---", pipeline_commit_NPC - 4);
            end

            // Log every store request the LSQ sends to the D-cache.
            // The LSQ only drives dcache_store for committed stores,
            // so this is the architectural memory trace.  `dcache_done`
            // gates us to the single cycle the store actually drains
            // so the same store isn't logged twice on a miss.
            if (core.lsq_0.dcache_store && core.dcache_done) begin
                logic [7:0]         sw_rob_tag;
                logic [`XLEN-1:0]   sw_pc;
                sw_rob_tag = {5'b0, core.lsq_0.entries[core.lsq_0.head].rob_tag};
                sw_pc      = core.lsq_0.entries[core.lsq_0.head].dbg_pc;
                $fdisplay(store_fileno, "PC=%x SW addr=%x data=%x be=%x rob=%0d",
                          sw_pc,
                          core.lsq_0.dcache_addr,
                          core.lsq_0.dcache_wr_data,
                          core.lsq_0.dcache_wr_be,
                          sw_rob_tag);
            end
            // Also log load fills -- any cycle the LSQ latches a
            // dcache_done for the head load.  Captures the extracted
            // 32-bit value the load will broadcast on the CDB.
            if (core.lsq_0.dcache_load && core.dcache_done) begin
                logic [`XLEN-1:0] ld_pc;
                ld_pc = core.lsq_0.entries[core.lsq_0.head].dbg_pc;
                $fdisplay(store_fileno, "PC=%x LW addr=%x rd=%x (full=%x)",
                          ld_pc,
                          core.lsq_0.dcache_addr,
                          core.lsq_0.load_value_extracted,
                          core.dcache_rd_data);
            end
            // Log every dcache eviction: when transitioning from
            // IDLE with a dirty valid line being replaced.  Captures
            // the evict address and data heading to memory.
            if (core.dcache_0.state == 3'd0 /* DC_IDLE */ &&
                (core.lsq_0.dcache_load || core.lsq_0.dcache_store) &&
                !core.dcache_0.hit &&
                core.dcache_0.dcache_data[core.dcache_0.req_index].valid &&
                core.dcache_0.dcache_data[core.dcache_0.req_index].dirty) begin
                $fdisplay(store_fileno, "EVICT idx=%0d tag=%x data=%x (req_addr=%x)",
                          core.dcache_0.req_index,
                          core.dcache_0.dcache_data[core.dcache_0.req_index].tags,
                          core.dcache_0.dcache_data[core.dcache_0.req_index].data,
                          core.lsq_0.dcache_addr);
            end
            // Log every memory-bus BUS_STORE: who wrote what to main
            // memory.  Useful for finding corruption paths that the
            // per-cache logs miss.
            if (proc2mem_command == 2'd2 /* BUS_STORE */)
                $fdisplay(store_fileno, "MEM_SW addr=%x data=%x (drives: dc=%b ic=%b)",
                          proc2mem_addr, proc2mem_data,
                          core.dcache_drives, core.icache_drives);
            // Log every memory response (tag arriving with data).
            if (mem2proc_tag != 4'b0)
                $fdisplay(store_fileno, "MEM_RESP tag=%x data=%x",
                          mem2proc_tag, mem2proc_data);

            // deal with any halting conditions
            if(pipeline_error_status != NO_ERROR || debug_counter > 50000000) begin
                $display("@@@ Unified Memory contents hex on left, decimal on right: ");
                show_mem_with_decimal(0,`MEM_64BIT_LINES - 1);
                // 8Bytes per line, 16kB total

                $display("@@  %t : System halted\n@@", $realtime);

                case(pipeline_error_status)
                    LOAD_ACCESS_FAULT:
                        $display("@@@ System halted on memory error");
                    HALTED_ON_WFI:
                        $display("@@@ System halted on WFI instruction");
                    ILLEGAL_INST:
                        $display("@@@ System halted on illegal instruction");
                    default:
                        $display("@@@ System halted on unknown error code %x",
                            pipeline_error_status);
                endcase
                $display("@@@\n@@");

                // Prediction-accuracy summary.  Percentage is printed in
                // integer basis points (x100) to avoid $itor/$rtoa.  A
                // run with zero committed branches reports 0/0 so the
                // line is still machine-parseable.
                begin
                    logic [63:0] correct;
                    logic [63:0] acc_bp;    // basis points = correct * 10000 / total
                    correct = branches_committed - mispredicts;
                    if (branches_committed == 0)
                        acc_bp = 64'd0;
                    else
                        acc_bp = (correct * 64'd10000) / branches_committed;
                    $display("@@@ branch_accuracy: %0d/%0d correct (%0d.%02d%%)",
                             correct, branches_committed,
                             acc_bp / 64'd100, acc_bp % 64'd100);
                end

                // Hang watchdog dump -- useful whenever we bail on the
                // 50 M-cycle timeout; harmless otherwise.
                if (debug_counter > 50000000)
                    dump_watchdog_ring();

                show_clk_count;
                // print_close(); // close the pipe_print output file
                $fclose(wb_fileno);
                $fclose(store_fileno);
                #100 $finish;
            end
            debug_counter <= debug_counter + 1;
        end // if(reset)
    end

endmodule // testbench
