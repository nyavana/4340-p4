/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  lsq.sv                                              //
//                                                                     //
//  Description :  Combined Load-Store Queue. Holds memory operations  //
//                 in program order, snoops the CDB to wake up         //
//                 operands, computes addresses with an internal AGU,  //
//                 and arbitrates access to the D-cache.               //
//                                                                     //
//                 Memory ordering policy (intentionally conservative  //
//                 for milestone 3):                                   //
//                                                                     //
//                   - Only the LSQ head interacts with the D-cache.   //
//                   - Loads issue as soon as their base operand is    //
//                     ready (no store-to-load forwarding -- a load    //
//                     behind an in-flight store waits for the store   //
//                     to fully drain to the cache).                   //
//                   - Stores hold (addr, data) in the LSQ until the   //
//                     ROB commits them.  At that point and only then  //
//                     does the store get released to the D-cache, so  //
//                     architectural memory is never polluted by a     //
//                     mispredicted path.                              //
//                                                                     //
//                 Sub-word handling: the entry stores mem_size and    //
//                 is_signed; on a load the cache returns a 64-bit     //
//                 line and the LSQ extracts the right slice and       //
//                 sign/zero-extends it before broadcasting on the     //
//                 CDB.  On a store the LSQ replicates the payload     //
//                 across the line and builds an 8-bit byte-enable     //
//                 mask so the cache can update only the bytes the    //
//                 RISC-V instruction is supposed to write.            //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module lsq #(
    parameter LSQ_SIZE = `LSQ_SZ,
    parameter XLEN     = `XLEN,
    parameter TAG_W    = $clog2(`ROB_SZ),
    parameter IDX_W    = $clog2(`LSQ_SZ)
)(
    input  logic              clock,
    input  logic              reset,
    input  logic              flush, // not used yet (no speculation past branches)

    // ---- Dispatch ----
    input  logic              dispatch_valid,
    input  logic              dispatch_is_store,
    input  logic [TAG_W-1:0]  dispatch_rob_tag,
    input  logic [1:0]        dispatch_mem_size, // 00=BYTE, 01=HALF, 10=WORD
    input  logic              dispatch_is_signed,

    input  logic              dispatch_base_ready,
    input  logic [TAG_W-1:0]  dispatch_base_tag,
    input  logic [XLEN-1:0]   dispatch_base_value,

    input  logic              dispatch_data_ready,
    input  logic [TAG_W-1:0]  dispatch_data_tag,
    input  logic [XLEN-1:0]   dispatch_data_value,

    input  logic [XLEN-1:0]   dispatch_imm, // already sign-extended
    input  logic [XLEN-1:0]   dispatch_dbg_pc, // debug-only: PC of the memory op

    output logic              lsq_full,

    // ---- CDB snoop (operand wakeup) ----
    input  logic              cdb_valid,
    input  logic [TAG_W-1:0]  cdb_tag,
    input  logic [XLEN-1:0]   cdb_value,

    // ---- Sideband to ROB so a store can become commit-ready ----
    output logic              store_ready_valid,
    output logic [TAG_W-1:0]  store_ready_tag,

    // ---- Snoop ROB commit so a store knows it has been retired ----
    input  logic              rob_commit_valid,
    input  logic [TAG_W-1:0]  rob_commit_tag,

    // ---- D-cache request ----
    output logic              dcache_load,
    output logic              dcache_store,
    output logic [XLEN-1:0]   dcache_addr,    // 8-byte aligned
    output logic [63:0]       dcache_wr_data,
    output logic [7:0]        dcache_wr_be,
    input  logic              dcache_done,
    input  logic              dcache_busy,    // dcache.proc_busy: 1 while
                                              // servicing a miss.  Used by
                                              // the flush path to tell "this
                                              // load is actively in the
                                              // cache pipeline" apart from
                                              // "LSQ asserted dcache_load
                                              // but the cache was busy".
    input  logic [63:0]       dcache_rd_data,

    // ---- Load completion (broadcast on CDB by pipeline.sv) ----
    output logic              load_complete_valid,
    output logic [TAG_W-1:0]  load_complete_tag,
    output logic [XLEN-1:0]   load_complete_value,
    input  logic              load_complete_accept // CDB took the broadcast this cycle
);

    // -------------------------------------------------------
    // Entry definition
    // -------------------------------------------------------
    typedef struct packed {
        logic              busy;
        logic              is_store;
        logic [TAG_W-1:0]  rob_tag;
        logic [1:0]        mem_size;
        logic              is_signed;

        logic              base_ready;
        logic [TAG_W-1:0]  base_tag;
        logic [XLEN-1:0]   base_value;

        logic              data_ready;
        logic [TAG_W-1:0]  data_tag;
        logic [XLEN-1:0]   data_value;

        logic [XLEN-1:0]   imm;
        logic              addr_valid;
        logic [XLEN-1:0]   addr;

        logic              committed;        // ROB has retired this store
        logic              in_flight;        // request handed to D-cache, waiting on done
        logic              load_buf_valid;   // load: data is buffered, waiting for CDB accept
        logic [XLEN-1:0]   load_buf_value;   // sub-word-extracted load result
        logic [XLEN-1:0]   dbg_pc;           // debug-only: PC of the memory op (unused in logic)
    } lsq_entry_t;

    lsq_entry_t entries      [LSQ_SIZE-1:0];
    lsq_entry_t next_entries [LSQ_SIZE-1:0];

    logic [IDX_W-1:0] head, tail;
    logic [IDX_W-1:0] next_head, next_tail;
    logic [IDX_W:0]   count, next_count;

    // When a mispredict flushes an in-flight load, the D-cache keeps
    // servicing its latched request and will eventually assert
    // dcache_done for data that no LSQ entry owns.  This counter
    // (width IDX_W+1, so it can hold up to LSQ_SIZE) tracks how many
    // stale dcache_done pulses are still outstanding so a later head
    // load is not falsely latched with somebody else's data.  A
    // counter (rather than a single bit) covers the case of two
    // flushes landing inside the same miss window -- rare in the
    // one-outstanding-miss D-cache today, but cheap to do right and
    // removes a correctness hazard for any future multi-miss cache.
    logic [IDX_W:0]   stale_response_count;
    logic [IDX_W:0]   next_stale_response_count;

    assign lsq_full = (count == LSQ_SIZE[IDX_W:0]);

    // -------------------------------------------------------
    // Head decode
    // -------------------------------------------------------
    wire head_busy            = entries[head].busy;
    wire head_is_store        = head_busy && entries[head].is_store;
    wire head_is_load         = head_busy && !entries[head].is_store;
    wire head_addr_ready      = head_busy && entries[head].addr_valid;
    wire head_store_operands  = head_addr_ready && entries[head].data_ready;

    // Stores need to wait for ROB commit before touching the cache.
    wire head_store_releasable = head_is_store && head_store_operands &&
                                 entries[head].committed;
    wire head_load_releasable  = head_is_load && head_addr_ready;

    // -------------------------------------------------------
    // Drive the D-cache request
    //
    // Loads are gated off once load_buf_valid is set so we don't
    // re-issue a request that already has its result in the buffer.
    // -------------------------------------------------------
    assign dcache_load  = head_load_releasable && !entries[head].load_buf_valid;
    assign dcache_store = head_store_releasable;
    assign dcache_addr  = {entries[head].addr[XLEN-1:3], 3'b0};

    // Build the byte-enable mask and the replicated payload from
    // mem_size + addr[2:0] + data_value.  See header comment for the
    // packing scheme.
    always_comb begin
        dcache_wr_data = 64'b0;
        dcache_wr_be   = 8'b0;
        case (entries[head].mem_size)
            2'b00: begin // BYTE
                dcache_wr_data = {8{entries[head].data_value[7:0]}};
                dcache_wr_be   = 8'b1 << entries[head].addr[2:0];
            end
            2'b01: begin // HALF
                dcache_wr_data = {4{entries[head].data_value[15:0]}};
                dcache_wr_be   = 8'b11 << {entries[head].addr[2:1], 1'b0};
            end
            2'b10: begin // WORD
                dcache_wr_data = {2{entries[head].data_value[31:0]}};
                dcache_wr_be   = 8'b1111 << {entries[head].addr[2], 2'b00};
            end
            default: begin // DOUBLE (unused on RV32)
                dcache_wr_data = {32'b0, entries[head].data_value};
                dcache_wr_be   = 8'hff;
            end
        endcase
    end

    // -------------------------------------------------------
    // Sub-word load extraction
    // -------------------------------------------------------
    logic [7:0]  load_byte_v;
    logic [15:0] load_half_v;
    logic [31:0] load_word_v;
    logic [XLEN-1:0] load_value_extracted;

    always_comb begin
        case (entries[head].addr[2:0])
            3'd0:    load_byte_v = dcache_rd_data[7:0];
            3'd1:    load_byte_v = dcache_rd_data[15:8];
            3'd2:    load_byte_v = dcache_rd_data[23:16];
            3'd3:    load_byte_v = dcache_rd_data[31:24];
            3'd4:    load_byte_v = dcache_rd_data[39:32];
            3'd5:    load_byte_v = dcache_rd_data[47:40];
            3'd6:    load_byte_v = dcache_rd_data[55:48];
            default: load_byte_v = dcache_rd_data[63:56];
        endcase

        case (entries[head].addr[2:1])
            2'd0:    load_half_v = dcache_rd_data[15:0];
            2'd1:    load_half_v = dcache_rd_data[31:16];
            2'd2:    load_half_v = dcache_rd_data[47:32];
            default: load_half_v = dcache_rd_data[63:48];
        endcase

        load_word_v = entries[head].addr[2] ? dcache_rd_data[63:32]
                                            : dcache_rd_data[31:0];

        case (entries[head].mem_size)
            2'b00: load_value_extracted = entries[head].is_signed
                                          ? {{24{load_byte_v[7]}}, load_byte_v}
                                          : {24'b0, load_byte_v};
            2'b01: load_value_extracted = entries[head].is_signed
                                          ? {{16{load_half_v[15]}}, load_half_v}
                                          : {16'b0, load_half_v};
            2'b10: load_value_extracted = load_word_v;
            default: load_value_extracted = load_word_v;
        endcase
    end

    // -------------------------------------------------------
    // Load completion broadcast.
    //
    // We always go through a per-entry buffer (load_buf_valid /
    // load_buf_value).  The cache result is latched on dcache_done and
    // the broadcast keeps re-asserting until pipeline.sv arbitrates the
    // CDB and acks via load_complete_accept.  This decouples the
    // cache-done event from the CDB and prevents the load from being
    // dropped when MULT happens to win arbitration on the same cycle.
    // -------------------------------------------------------
    assign load_complete_valid = head_is_load && entries[head].load_buf_valid;
    assign load_complete_tag   = entries[head].rob_tag;
    assign load_complete_value = entries[head].load_buf_value;

    // -------------------------------------------------------
    // Store ready sideband to ROB
    //   - Asserted while the head store has operands ready but ROB
    //     has not yet retired it.  Re-asserts each cycle until
    //     committed; the ROB tolerates this since it just sets
    //     ready=1 idempotently.
    //   - Stops once committed so the slot can be reused safely.
    // -------------------------------------------------------
    assign store_ready_valid = head_is_store && head_store_operands &&
                               !entries[head].committed;
    assign store_ready_tag   = entries[head].rob_tag;

    // -------------------------------------------------------
    // Next-state combinational
    //
    // Order of effects (each writes different fields, no conflicts):
    //   1. CDB wakeup of base / data operands
    //   2. AGU: compute addr if base is ready and addr_valid is 0
    //   3. Mark store as committed if ROB just commit'd it
    //   4. Mark in_flight when issuing to dcache
    //   5. Pop the head when dcache_done is observed
    //   6. Allocate a new entry on dispatch_valid
    // -------------------------------------------------------
    integer i;
    logic [IDX_W:0] dec_count;
    logic [IDX_W:0] flush_new_count;
    logic [IDX_W-1:0] flush_scan_idx;

    always_comb begin
        for (i = 0; i < LSQ_SIZE; i++)
            next_entries[i] = entries[i];
        next_head  = head;
        next_tail  = tail;
        next_count = count;
        flush_new_count = '0;
        flush_scan_idx  = head;
        next_stale_response_count = stale_response_count;

        if (flush) begin
            // Remember that a stale D-cache response is in flight if we
            // just dropped the load that owned it.  A committed store
            // being preserved across flush does NOT bump the counter --
            // that response still belongs to a valid LSQ entry.
            //
            // Edge case A: if dcache_done is already asserted on the
            // flush cycle AND the flushed head was an in-flight load,
            // the response is for that load and has already arrived.
            // We ignore it (the else branch never runs on flush cycles),
            // so the counter should NOT be bumped -- otherwise the NEXT
            // real response would be swallowed by mistake.
            //
            // Edge case B: the head is a brand-new releasable load and
            // the cache is IDLE this cycle.  The cache will accept the
            // request combinationally (state_IDLE && proc_load && !hit)
            // and commit to a fetch at the next posedge.  The LSQ has
            // not yet latched in_flight=1 (that happens next cycle).
            // When flush hits on this same cycle, the cache is still
            // going to fetch the dropped load's address -- its eventual
            // dcache_done is stale and must be swallowed.  Without this
            // arm, sort_search hung because the orphaned fetch's data
            // (belonging to the flushed load's address) was latched as
            // if it were the new head's load result.
            if (entries[head].busy && !entries[head].is_store && !dcache_done &&
                (entries[head].in_flight ||
                 (head_load_releasable && !dcache_busy)))
                next_stale_response_count = stale_response_count + 1'b1;
            // On branch mispredict the LSQ must drop every speculative
            // entry younger than the mispredicting branch, but it MUST
            // preserve any already-committed store sitting at the head
            // waiting to drain to the D-cache.  Commits are in order, so
            // committed stores form a contiguous run starting at head.
            for (i = 0; i < LSQ_SIZE; i++) begin
                if (!entries[i].is_store || !entries[i].committed)
                    next_entries[i] = '0;
            end
            // Walk from head forward; the new tail sits at the first slot
            // whose retained entry is non-busy.  A contiguous-run flag
            // (instead of `break`) keeps this friendly to all simulators.
            begin : flush_scan
                logic still_contig;
                still_contig = 1'b1;
                for (i = 0; i < LSQ_SIZE; i++) begin
                    flush_scan_idx = IDX_W'((head + i) % LSQ_SIZE);
                    if (still_contig) begin
                        if (next_entries[flush_scan_idx].busy)
                            flush_new_count = flush_new_count + 1'b1;
                        else
                            still_contig = 1'b0;
                    end
                end
            end
            next_head  = head;
            next_tail  = IDX_W'((head + flush_new_count) % LSQ_SIZE);
            next_count = flush_new_count;

            // Flush + dcache_done race on a committed head store.
            // The D-cache's done pulse this cycle is the store's own
            // completion -- architectural memory has already been
            // written.  If we left the store queued, the LSQ would
            // re-issue dcache_store next cycle and either double-write
            // (hit path) or lock up waiting for a second done that
            // never comes (miss path already consumed the bus handshake).
            // Pop the head on this cycle so the preserved store sees
            // its own done exactly once.
            if (flush_new_count > 0 &&
                entries[head].busy && entries[head].is_store &&
                entries[head].committed && dcache_done) begin
                next_entries[head] = '0;
                next_head  = (head == IDX_W'(LSQ_SIZE-1)) ? '0 : head + 1'b1;
                next_count = next_count - 1'b1;
            end
        end else begin
            // 1) CDB wakeup
            for (i = 0; i < LSQ_SIZE; i++) begin
                if (entries[i].busy && cdb_valid) begin
                    if (!entries[i].base_ready &&
                        entries[i].base_tag == cdb_tag) begin
                        next_entries[i].base_ready = 1'b1;
                        next_entries[i].base_value = cdb_value;
                    end
                    if (entries[i].is_store &&
                        !entries[i].data_ready &&
                        entries[i].data_tag == cdb_tag) begin
                        next_entries[i].data_ready = 1'b1;
                        next_entries[i].data_value = cdb_value;
                    end
                end
            end

            // 2) AGU - use the freshly woken value if any
            for (i = 0; i < LSQ_SIZE; i++) begin
                if (next_entries[i].busy &&
                    !next_entries[i].addr_valid &&
                    next_entries[i].base_ready) begin
                    next_entries[i].addr =
                        next_entries[i].base_value + next_entries[i].imm;
                    next_entries[i].addr_valid = 1'b1;
                end
            end

            // 3) ROB commit -> latch committed for the head store
            if (rob_commit_valid && head_is_store &&
                entries[head].rob_tag == rob_commit_tag) begin
                next_entries[head].committed = 1'b1;
            end

            // 4 + 5) Cache handshake at head
            //
            // Loads:
            //   - dcache_done && !load_buf_valid (any cycle the result
            //     arrives, hit or miss): latch into load_buf_*, mark
            //     load_buf_valid, drop in_flight.
            //   - load_buf_valid && load_complete_accept: pop.
            //   - !in_flight && !load_buf_valid && releasable && !done:
            //     mark in_flight (miss bookkeeping).
            //
            // Stores:
            //   - dcache_done (whether in_flight or hit): pop.
            //   - !in_flight && releasable && !done: mark in_flight.
            //
            dec_count = next_count;
            if (stale_response_count != '0 && dcache_done) begin
                // Swallow a stale response -- don't let anyone latch it.
                next_stale_response_count = stale_response_count - 1'b1;
            end else if (entries[head].busy && head_is_load) begin
                if (entries[head].load_buf_valid) begin
                    if (load_complete_accept) begin
                        next_entries[head] = '0;
                        next_head = (head == IDX_W'(LSQ_SIZE-1)) ? '0 : head + 1'b1;
                        dec_count = next_count - 1'b1;
                    end
                end else if (head_load_releasable && dcache_done) begin
                    next_entries[head].load_buf_valid = 1'b1;
                    next_entries[head].load_buf_value = load_value_extracted;
                    next_entries[head].in_flight      = 1'b0;
                end else if (head_load_releasable && !entries[head].in_flight &&
                             !dcache_busy) begin
                    // Only latch in_flight when the cache is actually
                    // IDLE (and therefore accepting our request this
                    // cycle).  If dcache_busy=1 then the cache is still
                    // on a previous fetch -- marking in_flight here would
                    // falsely claim ownership of somebody else's
                    // outstanding response and, on back-to-back flushes,
                    // would over-count stale responses in the counter.
                    next_entries[head].in_flight = 1'b1;
                end
            end else if (entries[head].busy && head_is_store) begin
                if (entries[head].in_flight && dcache_done) begin
                    next_entries[head] = '0;
                    next_head = (head == IDX_W'(LSQ_SIZE-1)) ? '0 : head + 1'b1;
                    dec_count = next_count - 1'b1;
                end else if (!entries[head].in_flight && head_store_releasable &&
                             dcache_done) begin
                    next_entries[head] = '0;
                    next_head = (head == IDX_W'(LSQ_SIZE-1)) ? '0 : head + 1'b1;
                    dec_count = next_count - 1'b1;
                end else if (!entries[head].in_flight && head_store_releasable) begin
                    next_entries[head].in_flight = 1'b1;
                end
            end
            next_count = dec_count;

            // 6) Allocate on dispatch
            if (dispatch_valid && !lsq_full) begin
                next_entries[tail]            = '0;
                next_entries[tail].busy       = 1'b1;
                next_entries[tail].is_store   = dispatch_is_store;
                next_entries[tail].rob_tag    = dispatch_rob_tag;
                next_entries[tail].mem_size   = dispatch_mem_size;
                next_entries[tail].is_signed  = dispatch_is_signed;
                next_entries[tail].imm        = dispatch_imm;
                next_entries[tail].dbg_pc     = dispatch_dbg_pc;

                next_entries[tail].base_ready = dispatch_base_ready;
                next_entries[tail].base_tag   = dispatch_base_tag;
                next_entries[tail].base_value = dispatch_base_value;

                next_entries[tail].data_ready = dispatch_data_ready;
                next_entries[tail].data_tag   = dispatch_data_tag;
                next_entries[tail].data_value = dispatch_data_value;

                if (dispatch_base_ready) begin
                    next_entries[tail].addr       =
                        dispatch_base_value + dispatch_imm;
                    next_entries[tail].addr_valid = 1'b1;
                end

                next_tail  = (tail == IDX_W'(LSQ_SIZE-1)) ? '0 : tail + 1'b1;
                next_count = next_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------
    // Sequential
    // -------------------------------------------------------
    always_ff @(posedge clock) begin
        integer j;
        if (reset) begin
            for (j = 0; j < LSQ_SIZE; j++)
                entries[j] <= '0;
            head  <= '0;
            tail  <= '0;
            count <= '0;
            stale_response_count <= '0;
        end else begin
            for (j = 0; j < LSQ_SIZE; j++)
                entries[j] <= next_entries[j];
            head  <= next_head;
            tail  <= next_tail;
            count <= next_count;
            stale_response_count <= next_stale_response_count;
        end
    end

endmodule // lsq
