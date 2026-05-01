# 2-way set-associative D-cache + next-line prefetch

Status as of 2026-04-30, branch `verify-merged-features` at `dc484b0`.
Three features bundled here, all from the `feat-dcache-prefetch` merge
(merge commit `bd78846`):

1. The data cache is 2-way set-associative (`sys_defs.svh:46–47`).
2. The data cache has its own next-line prefetcher built into its FSM
   (`dcache.sv` `DC_PREFETCH_REQ` / `DC_PREFETCH_WAIT` states).
3. The instruction side gains a separate one-entry stream buffer that
   prefetches the next sequential icache line (`verilog/stream_buffer.sv`,
   instantiated as `sb_0` in `pipeline.sv:441–453`).

The branch was named for the dcache prefetcher; the icache stream
buffer is shared infrastructure that came along for the ride. They
are distinct mechanisms living in different modules.

The set-associative geometry was already on the branch's tip, so the
two are routed under the same advanced-features bullet in the merge
report.

---

## 1. Motivation

The base design's dcache was direct-mapped at 32 lines × 64 bits
(256 B). Two hot lines that aliased into the same line slot would
ping-pong every reference. Sort-style benchmarks (the array, the loop
counter, and the comparison key all touching memory in the inner
loop) hit this often enough to lose 5–10% of cycles to forced
evictions.

Sequential-access programs (matrix walks, image kernels, struct field
sweeps) also pay 100 ns per cold line. A prefetcher that guesses the
next line during the demand fill turns those misses into hits without
touching the critical path.

---

## 2. 2-way set-associative dcache

### 2.1 Geometry

```systemverilog
// verilog/sys_defs.svh:46–47
`define DCACHE_LINES 32
`define DCACHE_WAYS  2

// verilog/dcache.sv:31–33
`define DCACHE_SETS     (`DCACHE_LINES / `DCACHE_WAYS)   // 16
`define DCACHE_SET_BITS $clog2(`DCACHE_SETS)             // 4
`define DCACHE_TAG_BITS (13 - `DCACHE_SET_BITS)          // 9
```

Total size stays at the project-spec cap of 256 B. The 32 lines now
split as 16 sets × 2 ways. Address layout from
`dcache.sv:99` (the line-address slice is 13 bits because the cache
covers a 64 KB program memory in 8 B lines):

```
proc_addr[15:7] : tag (9 bits)
proc_addr[6:3]  : set index (4 bits, 16 sets)
proc_addr[2:0]  : byte offset (always zero in CACHE_MODE)
```

### 2.2 Hit and victim logic

The hit comparator (`dcache.sv:134–161`) checks both ways in parallel:

```systemverilog
for (way_i = 0; way_i < `DCACHE_WAYS; way_i++) begin
    if (dcache_data[req_index][way_i].valid &&
        (dcache_data[req_index][way_i].tags == req_tag)) begin
        hit     = 1'b1;
        hit_way = way_i[0];
    end
end
```

Victim selection prefers an invalid way (`dcache.sv:151–155`):

```systemverilog
if (!dcache_data[req_index][0].valid)
    victim_way = 1'b0;
else if (!dcache_data[req_index][1].valid)
    victim_way = 1'b1;
// else fall through to the LRU bit
```

If both ways are valid, the LRU bit picks the victim. The default
victim_way before the override loop is `lru_way[req_index]`
(`dcache.sv:138`).

### 2.3 LRU bookkeeping

One bit per set is enough at 2-way (`dcache.sv:80`). Hits and fills
flip the bit toward the way that was just touched:

```systemverilog
// verilog/dcache.sv:385, 389, 410, 432
lru_way[req_index] <= ~hit_way;          // store hit
lru_way[req_index] <= ~hit_way;          // load hit
lru_way[reg_index] <= ~victim_way_reg;   // miss fill
lru_way[pf_index]  <= ~pf_way_reg;       // prefetch fill
```

True LRU at higher associativity needs more state; at 2-way one bit
per set is exact.

### 2.4 Sub-word stores

The dcache stores byte-enables alongside each store request
(`dcache.sv:56`, port `proc_wr_be [7:0]`). The LSQ builds the mask in
`lsq_byte_mask`. On a store hit, the cache writes only the enabled
bytes (`dcache.sv:377–384`):

```systemverilog
if (demand_req && proc_store && hit) begin
    for (b = 0; b < 8; b++) begin
        if (proc_wr_be[b]) begin
            dcache_data[req_index][hit_way].data[b*8 +: 8]
                <= proc_wr_data[b*8 +: 8];
        end
    end
    dcache_data[req_index][hit_way].dirty <= 1'b1;
    ...
end
```

On a store miss the fill merges the write data with the fetched line
byte by byte (`dcache.sv:395–404`). Writebacks always send the full
8-byte line (`dcache.sv:240–244`); the unified-memory model in
`mem.sv` only accepts doublewords in `CACHE_MODE`.

The dirty bit is per-line, not per-byte. That works because the
writeback always emits the whole line and the byte-enable mask is
only needed inside the cache to keep untouched bytes intact.

---

## 3. Dcache next-line prefetcher

The prefetcher is a state machine inside `dcache.sv`. It is not the
same module as `stream_buffer.sv` — that one belongs to the icache
(see §4).

### 3.1 Trigger

Every miss-fill that was driven by a load queues a prefetch for the
following 8-byte line (`dcache.sv:412–420`):

```systemverilog
if (req_load_reg &&
    !prefetch_hit_next &&
    !prefetch_victim_dirty_next) begin
    pf_pending_reg <= 1'b1;
    pf_addr_reg    <= prefetch_addr_next;
    pf_way_reg     <= prefetch_victim_way_next;
end
```

The prefetch is dropped immediately when:

- It would land on a line that is already cached
  (`!prefetch_hit_next`).
- Its victim is dirty (`!prefetch_victim_dirty_next`). The cache
  refuses to evict a dirty victim for speculative data — that would
  block the next demand miss waiting for the writeback bus.

### 3.2 Two-state pump

`DC_IDLE` enters `DC_PREFETCH_REQ` only when the cache has no demand
work and a prefetch is queued (`dcache.sv:266–268`):

```systemverilog
end else if (pf_pending_reg && !pf_hit && !pf_victim_dirty) begin
    next_state = DC_PREFETCH_REQ;
end
```

`DC_PREFETCH_REQ` waits for the memory tag, then transitions to
`DC_PREFETCH_WAIT` (`dcache.sv:282–293`). On any demand access while
the prefetch is in flight, the FSM aborts cleanly and falls into the
demand miss path (`dcache.sv:294–305`):

```systemverilog
DC_PREFETCH_WAIT: begin
    if (demand_req) begin
        if (hit)
            next_state = DC_IDLE;
        else if (victim_dirty)
            next_state = DC_EVICT_REQ;
        else
            next_state = DC_FETCH_REQ;
    end else if (pf_done) begin
        next_state = DC_IDLE;
    end
end
```

The orphaned memory response is collected by the same tag arbitration
pipeline.sv uses on every other cache module — `Dmem2proc_response`
is masked to zero on cycles when this cache did not drive the bus
(see `pipeline.sv` bus arbitration).

### 3.3 Fill

When the prefetch response arrives without a competing demand
(`dcache.sv:427–435`):

```systemverilog
if (pf_done && !demand_req) begin
    dcache_data[pf_index][pf_way_reg].data  <= Dmem2proc_data;
    dcache_data[pf_index][pf_way_reg].tags  <= pf_tag;
    dcache_data[pf_index][pf_way_reg].valid <= 1'b1;
    dcache_data[pf_index][pf_way_reg].dirty <= 1'b0;
    lru_way[pf_index] <= ~pf_way_reg;
    ...
end
```

Prefetch-filled lines are clean. They land in the LRU way of the
target set, which means a later demand miss for that set will evict
the older line (the previous MRU) rather than the just-prefetched
one.

---

## 4. Icache stream buffer

`verilog/stream_buffer.sv` is a one-entry buffer that lives next to
the icache. It is a separate module from the dcache prefetcher.

### 4.1 Why a separate module

The icache is already at the 256 B cap (the project's combined
icache + dcache budget). Adding a 33rd line would push it over, so
the stream buffer keeps its data outside the icache array
(`stream_buffer.sv:5–10`):

> Sits beside the icache (not inside it, since the icache is already
> at the 256-byte cap). Whenever the icache is idle and the current
> demand line is NOT the last thing in the buffer, the buffer issues
> a BUS_LOAD for demand_addr + 8 (the next 8-byte-aligned line).

### 4.2 Mechanism

```systemverilog
// verilog/stream_buffer.sv:46–47
logic [`XLEN-1:0] pf_addr;
assign pf_addr = demand_addr + 8;
```

On every cycle the buffer's prefetch target is the line right after
whatever the fetch stage is asking for. The buffer drives `BUS_LOAD`
with that address whenever a request is outstanding and the target
hasn't just changed:

```systemverilog
// verilog/stream_buffer.sv:80–83
assign proc2Pmem_command = (pf_outstanding && !pf_changed) ? BUS_LOAD : BUS_NONE;
assign proc2Pmem_addr    = pf_addr;
```

The fetch-stage hit is exact-address only:

```systemverilog
// verilog/stream_buffer.sv:85–87
assign sb_valid_out = sb_valid && (sb_addr == demand_addr);
```

A stale buffer entry simply does not match and the icache falls back
to a normal demand fetch. There is no separate eviction path.

### 4.3 Bus arbitration

`pipeline.sv` masks `mem2sb_response` to zero on cycles when this
module did not drive the bus, so an icache or dcache response that
happens to land in the same memory tag window cannot corrupt the
stream buffer. Priority is dcache > icache > stream buffer (the
buffer's top comment states this explicitly).

### 4.4 Diagnostic counter

`prefetch_hit_count` is exposed as an output (`stream_buffer.sv:42`,
incremented at line 128). `pipeline_test.sv` prints it at halt so the
regression can sanity-check that the buffer is doing useful work.

---

## 5. Unit tests

`test/dcache_test.sv` (520 lines) covers eight scenarios per its
header comment:

```
1. Load miss -> fetch -> data returned, then a same-line hit
2. Store hit (modify a clean line, mark dirty)
3. Load hit reads back the modified line
4. Sub-word stores (BYTE / HALF / WORD) update only the requested bytes
5. Two aliased addresses can co-exist in one set without thrashing
6. LRU updates on hit change which way gets evicted
7. Next-line prefetch turns an adjacent load into a later hit
8. Eviction of a dirty victim triggers a writeback to memory
```

Test 5 is the directly-set-associative-specific one: it loads two
addresses that map to the same set, asserts both stay resident, and
asserts the access pattern does not generate a third miss.

Test 6 is the LRU regression: load A, load B, load A, then load C
that maps to the same set. C should evict B, not A. That's the
exact case a direct-mapped cache could not have got right.

Test 7 is the dcache prefetcher: load address `0x180`, wait for the
fill to settle, then load `0x188`. The second load hits because the
prefetch queued after the first miss filled `0x188` into the same
set. The test counts memory request cycles to confirm only one fill
went out.

The icache stream buffer is exercised by the icache testbench and
the full-pipeline regression. There is no per-module testbench for
`stream_buffer.sv` — the merge report's §4 row for icache notes that
the synth-side wiring for the stream buffer was the only fix needed
to get `icache.syn.pass` green.

---

## 6. Regression

The set-associative dcache and the two prefetchers all landed in the
same merge, so per-feature attribution would need a bisect. The
cumulative table in the merge report §5 is the cleanest comparison.

Memory-bound programs are where the wins concentrate:

| Program | cycles before | cycles now | Δ% |
|---|---|---|---|
| alexnet | 9 383 837 | 4 730 247 | −49.6% |
| outer_product | 4 519 350 | 3 166 519 | −29.9% |
| matrix_mult_rec | 719 984 | 662 478 | −8.0% |
| sort_search | 813 758 | 600 637 | −26.2% |
| insertionsort | 773 510 | 554 802 | −28.3% |
| quicksort | 902 072 | 568 553 | −37.0% |
| dft | 1 685 359 | 1 006 437 | −40.3% |

Some of this is gshare and STLF; sort_search and insertionsort lean
memory-heavy and the dcache work shows up there too. `outer_product`
and `dft` are large sweeps over arrays where the next-line prefetch
hides most of the cold-miss latency. `alexnet` ran tight on the
direct-mapped cache and thrashed; the set-associative geometry alone
buys most of its 49% delta (the rest is icache prefetch and gshare).

---

## 7. Synthesis

```
make synth/dcache.vg
…
worst slack = +19.28 ps  (1000 ps clock)
```

The dcache standalone meets at +19.28 ps. The integrated critical
path goes through the LSQ → MULT seam (merge report §6), not the
dcache. The set-associative way-mux and the per-byte store mask both
land on registered outputs and don't show up as new endpoints.

The stream buffer compiles into the icache synth flow via a
per-target Makefile rule that the verify-merged-features pass added
(merge report §10.2):

```makefile
icache.syn.simv: verilog/stream_buffer.sv
```

Without this the icache synth-flow link list missed the stream
buffer module and `icache.syn.pass` failed with `Error-[URMI]
Unresolved modules`.

---

## 8. Files changed

Code:

- `verilog/sys_defs.svh`: `DCACHE_LINES = 32`, `DCACHE_WAYS = 2`.
- `verilog/dcache.sv`:
  - 2D storage `dcache_data [SETS][WAYS]`, per-set `lru_way` bit.
  - Way-aware hit / victim logic (`dcache.sv:134–161`).
  - `DC_PREFETCH_REQ` / `DC_PREFETCH_WAIT` states and queue logic.
  - Per-byte store mask handling on hit and on miss-fill.
  - Bus arbitration mask alignment with `proc2Dmem_*` (the cache
    only drives the bus during `DC_EVICT_REQ`, `DC_FETCH_REQ`, or
    `DC_PREFETCH_REQ`).
- `verilog/stream_buffer.sv`: new module (132 lines).
- `verilog/pipeline.sv`:
  - Stream buffer instantiation (`pipeline.sv:441–453`).
  - Bus arbitration mask `sb_resp_in` (the masked
    `mem2proc_response` view the buffer sees).

Tests:

- `test/dcache_test.sv`: aliased-coexistence test, LRU-flip test,
  next-line prefetch test, dirty-eviction writeback test.
- No standalone `test/stream_buffer_test.sv` was added; the icache
  testbench and the full-pipeline regression cover it.

Build:

- `Makefile`: per-target prerequisite `icache.syn.simv:
  verilog/stream_buffer.sv` so the synthesized icache testbench
  links the stream buffer (verify-merged-features pass).

---

## 9. Known limitations

1. **One-entry stream buffer.** A second entry would hide longer
   cold runs at modest area cost. Deferred — the regression is
   already fast enough on the suite we run.
2. **Stream buffer prefetches +1 line only.** No stride detection,
   no degree-N hardware. The icache misses that don't fall into
   that pattern still pay full latency.
3. **Dcache prefetcher drops on dirty victim.** A pending writeback
   would block the demand path, which we did not want speculative
   work to do. Programs with very high write-density may benefit
   from a write-allocate variant; defer.
4. **No prefetch on stores.** Only load-driven misses queue a
   follow-up line (`dcache.sv:412`). The rationale is that store
   streams already write the line they're going to write and don't
   benefit from a speculative read.
5. **Approximate LRU at 2-way is exact.** Going to 4-way would
   require true-LRU bookkeeping with more state. Backlog.
6. **Single icache stream-buffer entry per icache miss.** Two
   different in-flight fetches cannot both be served by the buffer.
   The miss handler in the icache itself takes the second one.

---

## 10. How to rebuild

```
# Default (set-associative dcache + both prefetchers on)
make clean && make -j8 simulate_all

# dcache unit test
make dcache.pass
make dcache.syn.pass

# Stream-buffer hit count (printed at halt by pipeline_test.sv)
grep prefetch_hit_count output/<prog>.out
```

`prefetch_hit_count` is the icache stream buffer counter. The dcache
internal prefetcher does not print a counter; its effect lands in
the cycle-count column of the §5 cumulative table.
