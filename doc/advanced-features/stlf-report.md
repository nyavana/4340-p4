# Store-to-load forwarding

Status as of 2026-04-30, branch `verify-merged-features` at `dc484b0`.
STLF is the most recent of the seven advanced-features merges
(`feat-stlf-cz2931`). The verify-merged-features pass pipelined the
forward path one extra cycle to hit timing; that change is the only
post-merge edit to `lsq.sv` and is described in §3 below.

---

## 1. Motivation

A load that hits a same-cycle younger store than the cache could
serve used to wait for the store to drain. With write-back caches,
"drain" means: store sits in the LSQ until ROB commit, then waits
for the cache to be free, then the cache marks the line dirty. The
load behind it pays however many cycles that took. On loops with a
store followed immediately by a dependent load (the canonical
RAW-through-memory pattern), this would cost 5–20 cycles per
iteration.

STLF lets the load read the store's data directly out of the LSQ as
soon as the store has both its address and its data ready. The cache
never sees the load.

---

## 2. Mechanism

### 2.1 Forwarding rules

```systemverilog
// verilog/lsq.sv:285–356 (stlf_compute)
for (int k = 0; k < LSQ_SIZE; k++) begin
    L_pos = (head + k) % LSQ_SIZE;
    if (... entries[L_pos].busy && !entries[L_pos].is_store
        && entries[L_pos].addr_valid && !entries[L_pos].load_buf_valid) begin
        ...
        for (int o = 0; o < LSQ_SIZE; o++) begin
            if (o < k) begin
                ...
                if (entries[O_pos].busy && entries[O_pos].is_store) begin
                    // address fully unresolved? block.
                    if (!entries[O_pos].addr_valid) begin
                        can_forward = 1'b0;
                    end else if (same_8B_line) begin
                        if ((store_mask & load_mask) != 8'b0) begin
                            if ((store_mask & load_mask) == load_mask) begin
                                if (!entries[O_pos].data_ready)
                                    can_forward = 1'b0;
                                else begin
                                    src_line  = lsq_store_line(...);
                                    found_src = 1'b1;
                                end
                            end else begin
                                can_forward = 1'b0; // partial overlap
                            end
                        end
                    end
                end
            end
        end
        if (can_forward && found_src) ...
    end
end
```

Forwarding fires when, walking from oldest to youngest of the
older-than-load entries, the most recent same-line store fully
covers the load's byte range and has its data ready. Anything that
breaks the chain blocks the forward:

| Condition | Effect |
|---|---|
| Older store with unresolved address | Block. We can't tell yet whether it aliases. |
| Older store on same line, no overlap | Skip. Doesn't help, doesn't block. |
| Older store on same line, partial overlap | Block. The load needs bytes only the cache has. |
| Older store on same line, full overlap, no data | Block until data resolves. |
| Older store on same line, full overlap, data ready | **Forward.** |

Age order is enforced by FIFO index walking (`lsq.sv:316`'s
`if (o < k)`). A younger store on the same line cannot forward to
this load, even if it would otherwise match — the load sees the
older one.

### 2.2 Sub-word handling

Both the store payload and the extracted load value go through the
sub-word helpers:

```systemverilog
// verilog/lsq.sv:332–334
src_line  = lsq_store_line(entries[O_pos].mem_size,
                           entries[O_pos].data_value);
// verilog/lsq.sv:349–352
stlf_value[L_pos] = lsq_extract_load(src_line,
                                     entries[L_pos].addr[2:0],
                                     entries[L_pos].mem_size,
                                     entries[L_pos].is_signed);
```

`lsq_store_line` replicates the value across the 64-bit line; the
byte mask says which bytes are real. `lsq_extract_load` is the same
function the cache-side load path uses (`lsq.sv:240–270`), so a
byte/half/word load forwarded from a wider store is sign-extended
the same way it would be off the cache.

### 2.3 Head-of-LSQ gating

The dcache request gate (`lsq.sv:186–187`) drops `dcache_load` for a
forwarded head load:

```systemverilog
assign dcache_load  = head_load_releasable &&
                      !entries[head].load_buf_valid &&
                      !stlf_ready[head];
```

So the cache never sees this load. The store sitting in front of it
in the LSQ also doesn't get poked early — stores still wait for
commit before they touch the cache.

---

## 3. Timing: the latch step

### 3.1 The original cone

Before the verify-merged-features pass, the broadcast arbiter and
the `load_complete_value` mux read directly from the combinational
`stlf_*` outputs:

```systemverilog
// (pre-verify-merged-features)
buf_ready_comb[i]    = entries[i].load_buf_valid || stlf_ready[i];
load_complete_value  = stlf_ready[broadcast_pos] ? stlf_value[broadcast_pos]
                                                 : entries[broadcast_pos].load_buf_value;
```

That made forwarded loads broadcast on the same cycle they were
detected. The path went:

```
LSQ head register
  → STLF byte-mask comparator (on every entry, every store)
    → broadcast arbiter (LSQ_SIZE-wide priority)
      → CDB
        → RS issue value-mux (CDB-bypass arm for the issued entry)
          → MULT stage 0 operand select
            → MULT-stage-0 multiply tree
```

Synth measured this at −504.66 ps slack on the 1000 ps clock — the
worst path in the integrated netlist (merge report §6).

### 3.2 The fix

The latch step (`lsq.sv:590–596`) was already there before the
timing fix. It registers `stlf_value` into per-entry
`load_buf_value` and asserts `load_buf_valid` whenever
`stlf_ready[i]` is high:

```systemverilog
// 3.5) STLF latch
for (i = 0; i < LSQ_SIZE; i++) begin
    if (stlf_ready[i]) begin
        next_entries[i].load_buf_valid = 1'b1;
        next_entries[i].load_buf_value = stlf_value[i];
    end
end
```

The change was to remove the OR with `stlf_ready` from
`buf_ready_comb` and the mux into `load_complete_value`. After:

```systemverilog
// verilog/lsq.sv:375–377
for (int i = 0; i < LSQ_SIZE; i++)
    buf_ready_comb[i] = entries[i].load_buf_valid &&
                        !entries[i].broadcast_done;
```

Forwarded loads now go through the same registered fast path as
cache-hit loads. They broadcast one cycle after STLF detection
instead of on the same cycle.

The merge report §10.3 has the full write-up. Net: slack improved
from −504.66 to −244.54 ps (about 260 ps recovered), the residual
moved into the MULT-stage-0 multiply tree, and `cmp -s` against the
pre-fix `.wb` files succeeded on every program. mergesort gained
exactly one cycle (200 072 → 200 073) because the STLF-fed
broadcast slipped one slot.

### 3.3 Why this is one cycle, not zero

A truly zero-cycle STLF would need either a registered MULT operand
input (which adds one cycle to every MULT consumer) or a registered
RS issue path (which adds one cycle to every issue). Both are
larger surgeries with broader regression risk than a one-cycle hit
on the small fraction of loads that actually forward. The team
chose the cheaper edit.

---

## 4. Unit tests

`test/lsq_test.sv` carries nine scenarios (`task automatic test_*`):

| Test | What it covers |
|---|---|
| 1 | Load with ready operand → dcache request → complete |
| 2 | Load with pending operand woken by CDB |
| 3 | Store asserts ready, waits for commit, drains |
| 4 | FIFO order: load at head must drain before later store |
| 5 | Flush clears queue |
| 6–7 | Flush + dcache_done race on store |
| 8 | Two back-to-back stale responses swallowed |
| 9 | Early tag wakes LSQ base one cycle before CDB |

There is no dedicated STLF unit-test scenario. The forwarding path
is exercised by the full-pipeline regression and was originally
covered through the day-to-day flow, not a targeted testbench. This
is a known gap; a future pass should add scenarios for at least
"older store fully covers younger load" and "older store partially
overlaps blocks the forward". The merge report's §8 documentation
gap is closed by this report, but the unit-test gap is not.

---

## 5. Regression

The cumulative table in merge report §5 is the cleanest comparison
available. STLF and the rest of the advanced features shipped in
overlapping merges, so per-feature attribution would need a bisect.
Programs with frequent RAW-through-memory chains see the largest
gains:

| Program | cycles before | cycles now | Δ% |
|---|---|---|---|
| insertionsort | 773 510 | 554 802 | −28.3% |
| quicksort | 902 072 | 568 553 | −37.0% |
| sort_search | 813 758 | 600 637 | −26.2% |
| mergesort | 302 356 | 200 073 | −33.8% |
| graph | 457 047 | 259 409 | −43.2% |
| backtrack | 258 690 | 146 861 | −43.2% |
| priority_queue | 77 843 | 43 384 | −44.3% |

`graph` and `priority_queue` are heavy on linked-list-style code
where the next pointer is freshly written and immediately read. The
sort programs all walk an array writing comparisons and reading
them on the next iteration. Without STLF those loads pay the
write-allocate plus drain cycles every loop iteration.

Programs without RAW-through-memory chains are barely affected by
STLF. The compute-bound benchmarks (mult, mult_no_lsq, fib) move
under ±2%.

---

## 6. Synthesis

```
make synth/lsq.vg
…
worst slack = +0.05 ps  (1000 ps clock)
```

LSQ standalone meets at the tightest slack of any tested module
(merge report §3). The integrated path through MULT stage 0 misses
by −244.54 ps after the latch fix; the LSQ side of that cone is
clean now, and the residual lives in the multiplier (merge report
§6).

`make lsq.syn.pass` is green after the synth-side wrapper wiring
fix in the verify-merged-features pass (merge report §10.2). The
testbench instantiates `lsq_svsim` under `+define+SYNTH` so the
unpacked-array port shape survives DC's flattening.

---

## 7. Files changed

Code changes that landed with the original feature merge:

- `verilog/lsq.sv`:
  - Per-entry `load_buf_valid` and `load_buf_value` (the registered
    forward latch).
  - `stlf_compute` always_comb block (lines 285–356) producing
    `stlf_ready[*]` and `stlf_value[*]`.
  - Step 3.5 latch (lines 590–596).
  - `dcache_load` head-gating to suppress the cache request when
    the head is forwardable (`lsq.sv:186–187`).
- `verilog/sys_defs.svh`: no change. `LSQ_SZ = 8` was already in
  place.

Code changes from the verify-merged-features timing pass:

- `verilog/lsq.sv:371`: `buf_ready_comb[i]` no longer ORs in
  `stlf_ready[i]`.
- `verilog/lsq.sv:400`: the `load_complete_value` mux returns
  `entries[broadcast_pos].load_buf_value` directly, no longer
  picking `stlf_value` on a `stlf_ready[broadcast_pos]` arm.

Tests:

- `test/lsq_test.sv`: existing nine scenarios cover the LSQ flush
  and CDB paths. None is STLF-specific.

---

## 8. Known limitations

1. **No partial-forward.** A load whose byte range overlaps an older
   store's byte range but isn't fully covered blocks until the store
   drains. The hardware to merge cache bytes with store bytes
   per-byte exists conceptually but isn't wired. A future pass
   could add it; the regression doesn't currently expose programs
   where this fires often enough to matter.
2. **One-cycle latency on the forwarded broadcast.** The latch step
   is the cheapest way to break the timing cone (§3). On a faster
   clock target the latch could probably be moved into the RS-issue
   value-mux instead, but that's its own design exercise.
3. **No per-feature STLF unit tests.** The forward path is covered
   only by the full-pipeline regression. Adding "older store fully
   covers", "older store partial-overlaps", and "older store has no
   data yet" scenarios would lock down the comparator semantics
   against future RTL edits.
4. **Comparator scans all entries every cycle.** It's
   `LSQ_SIZE * LSQ_SIZE = 64` byte-mask compares per cycle, which
   the synthesis tool unrolled fine at the current LSQ_SZ. Scaling
   the LSQ would require either a smarter dependency structure or
   accepting that the comparator becomes a long path.
5. **`dcache_busy` was added as a load-bearing input.** Required by
   the stale-response counter so a flush that lands on the
   accept-this-cycle edge increments correctly. Not strictly STLF
   business, but landed in the same area; called out in the
   base-design `branch-predictor-report.md` "sort_search fix"
   section.

---

## 9. How to rebuild

```
# Default
make clean && make -j8 simulate_all

# LSQ unit test
make lsq.pass
make lsq.syn.pass
```

There is no `+define` to disable STLF. To get a baseline without it
you'd revert the `stlf_compute` block and remove the latch step;
this hasn't been needed because the regression catches any STLF
correctness regression as a `.wb` divergence.
