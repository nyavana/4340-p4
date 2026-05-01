`include "verilog/sys_defs.svh"

// One-entry stream buffer that prefetches the next sequential cache line.
//
// Sits beside the icache (not inside it, since the icache is already at the
// 256-byte cap).  Whenever the icache is idle and the current demand line is
// NOT the last thing in the buffer, the buffer issues a BUS_LOAD for
// demand_addr + 8 (the next 8-byte-aligned line).  When the pipeline later
// fetches that address, the buffer reports a hit and the pipeline can skip
// waiting for memory.
//
// Priority on the shared bus: dcache > icache (demand) > stream buffer.
// pipeline.sv enforces this by masking mem2sb_response to zero whenever the
// bus was not driven by this module.  The buffer sees a zero response and
// keeps retrying, exactly like the icache does for demand misses.
//
// Correctness guarantee: the buffer only reports a hit when sb_addr matches
// demand_addr exactly.  Stale entries are silently ignored; the icache always
// handles the demand as a fallback.

module stream_buffer (
    input  logic        clock,
    input  logic        reset,

    // From memory (masked by pipeline: non-zero only when this module drove the bus)
    input  logic [3:0]  mem2sb_response,
    input  logic [63:0] mem2proc_data,
    input  logic [3:0]  mem2proc_tag,

    // Current 8-byte-aligned fetch address from the pipeline (== {PC[31:3], 3'b0})
    input  logic [`XLEN-1:0] demand_addr,

    // To memory bus (pipeline muxes this in at lowest priority)
    output logic [1:0]       proc2Pmem_command,
    output logic [`XLEN-1:0] proc2Pmem_addr,

    // To fetch stage: hit when demand_addr is already in the buffer
    output logic [63:0] sb_data_out,
    output logic        sb_valid_out,

    // Analysis counters printed at halt (see pipeline_test.sv)
    output integer prefetch_hit_count
);

    // ---- Prefetch target: always one line ahead of the current demand ----
    logic [`XLEN-1:0] pf_addr;
    assign pf_addr = demand_addr + 8;

    // ---- One-entry buffer ----
    logic [63:0]      sb_data;
    logic [`XLEN-1:0] sb_addr;   // 8-byte-aligned address this entry is valid for
    logic             sb_valid;

    // ---- Request-tracking state (mirrors icache.sv pattern) ----
    logic [3:0]       pf_mem_tag;     // memory tag we're waiting on (0 = none)
    logic             pf_outstanding; // sent a request, haven't received tag yet
    logic [`XLEN-1:0] last_pf_addr;   // pf_addr from the previous cycle
    logic [`XLEN-1:0] pf_tag_addr;    // pf_addr at the moment memory assigned the tag

    // ---- Combinational signals ----

    // Did pf_addr change this cycle?  (demand_addr stepped to a new 8-byte line)
    wire pf_changed = (pf_addr != last_pf_addr);

    // Did memory return the data we were waiting for?
    wire got_pf_data = (pf_mem_tag != 0) && (pf_mem_tag == mem2proc_tag);

    // Does the buffer already hold the prefetch target?
    wire buf_has_target = sb_valid && (sb_addr == pf_addr);

    // Do we still need to keep requesting?
    //   · On a target change: restart unless the buffer already has the new target.
    //   · Otherwise: keep retrying until we receive a response tag.
    wire pf_unanswered = pf_changed ? !buf_has_target
                                    : pf_outstanding && (mem2sb_response == 0);

    // Whenever pf_outstanding or got_pf_data or address changes, resample the tag.
    wire update_pf_tag = pf_changed || pf_outstanding || got_pf_data;

    // Drive the bus only when outstanding AND the target hasn't just changed
    // (matches icache.sv: stop sending on address change, restart next cycle).
    assign proc2Pmem_command = (pf_outstanding && !pf_changed) ? BUS_LOAD : BUS_NONE;
    assign proc2Pmem_addr    = pf_addr;

    // Fetch-stage bypass: valid only when demand_addr exactly matches what we buffered
    assign sb_valid_out = sb_valid && (sb_addr == demand_addr);
    assign sb_data_out  = sb_data;

    // ---- Sequential logic ----
    always_ff @(posedge clock) begin
        if (reset) begin
            last_pf_addr       <= '1;  // all-ones → pf_changed=1 on first active cycle,
                                       // which starts the very first prefetch
            pf_mem_tag         <= 0;
            pf_outstanding     <= 0;
            pf_tag_addr        <= '0;
            sb_valid           <= 0;
            sb_data            <= '0;
            sb_addr            <= '0;
            prefetch_hit_count <= 0;
        end else begin
            last_pf_addr   <= pf_addr;
            pf_outstanding <= pf_unanswered;

            // Track the memory tag for the in-flight prefetch.
            // Also latch the address we tagged so we can store data correctly
            // even if pf_addr has advanced by the time data arrives.
            if (update_pf_tag) begin
                pf_mem_tag <= mem2sb_response;
                // Only update pf_tag_addr when the tag is being freshly assigned
                // (response != 0) and the target hasn't just changed this cycle
                // (if pf_changed, this response belongs to the old target).
                if (mem2sb_response != 0 && !pf_changed)
                    pf_tag_addr <= pf_addr;
            end

            // Fill the buffer when memory delivers the prefetched data.
            // Use pf_tag_addr (the address we actually sent the request for)
            // rather than the current pf_addr, which may have advanced.
            if (got_pf_data) begin
                sb_data  <= mem2proc_data;
                sb_addr  <= pf_tag_addr;
                sb_valid <= 1;
            end

            // Count demand fetches served from this buffer (for the report).
            if (sb_valid_out)
                prefetch_hit_count <= prefetch_hit_count + 1;
        end
    end

endmodule // stream_buffer
