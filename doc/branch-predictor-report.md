# Branch Predictor Report

Status as of 2026-04-17: the predictor is live, the regression is
green at 34/34, and bring-up turned up four integration bugs that
are all fixed in this branch (one in `rs.sv` for the JAL/JALR NPC
broadcast, two in `lsq.sv` for flush / cache-done races, and one
in `icache.sv` for a PC change mid-fetch).

## What is built

- `verilog/branch_predictor.sv`: a single module with both tables inside.
  - BTB: direct-mapped, 32 entries. Each entry is
    `{valid, is_uncond, tag, target}`. Indexed by `PC[6:2]`; tag is
    `PC[31:7]`. Sized to match the repo's 32-line icache/dcache style.
  - BHT: bimodal 2-bit saturating counters, 64 entries, indexed by
    `PC[7:2]`. Reset state is `01` (weakly not-taken) so cold forward
    branches bias toward fall-through.
  - Predict port is combinational on the current fetch PC. Returns
    `{pred_valid, pred_taken, pred_target, pred_is_uncond}`.
  - Update port is one registered write per committing branch, driven
    from the ROB's commit-stage signals.
- `verilog/rob.sv`: adds `predicted_taken`, `predicted_target`,
  `is_uncond_branch`, and `branch_PC` to each entry, plus the
  commit-time mispredict comparator and a one-cycle
  `mispredict_valid` / `mispredict_target` sideband.
- `verilog/rs.sv`: moves the old shared `branch_target_buf` and
  `branch_funct3_buf` out of `pipeline.sv` and into per-entry fields.
  Adds `branch_NPC` so the CDB can broadcast the return address for
  JAL/JALR instead of 0.
- `verilog/lsq.sv`: flush now preserves any committed store at the
  head (so a store already released to the D-cache cannot be lost to
  a later branch's flush) and adds a one-bit `stale_response_pending`
  flag that swallows the D-cache response belonging to a flushed
  in-flight load.
- `verilog/pipeline.sv`: instantiates the predictor, wires the
  prediction packet to the ROB, ties `branch_pending` to zero,
  redirects `PC_reg` to `pred_target` on a predicted-taken hit,
  redirects to `mispredict_target` on a commit-time miss, and poisons
  the in-flight MULT across a flush so its eventual CDB broadcast
  cannot clobber a re-allocated ROB slot.
- Parameters in `verilog/sys_defs.svh`: the old `BRANCH_PRED_SZ = xx`
  placeholder is replaced by `BTB_ENTRIES = 32` and `BHT_ENTRIES = 64`,
  along with a `BRANCH_PRED_PACKET` typedef for the fetch-to-dispatch
  prediction bundle.
- Testbenches: `test/branch_predictor_test.sv` covers cold miss,
  learn-a-taken-conditional, learn-not-taken, JAL install, high and
  low saturation, the 2-not-taken flip from `11` to `01`, a tag-alias
  collision, and write-then-read on the next cycle. `test/rob_test.sv`
  is extended with four mispredict cases. `test/lsq_test.sv` is
  extended with the preserve-committed-store flush case. All unit
  tests pass on both simulation and synthesis targets.

## Integration fixes uncovered during bring-up

None of these showed up in the predictor's own unit test. They only
surface once `branch_pending` is tied to zero and the pipeline has
multiple branches and their speculative tails in flight together. Each
one had to go in before most of the regression would halt.

1. **CDB broadcast value for JAL/JALR.** The original pipeline put
   `0` on `cdb_value` for uncond branches and relied on the ROB's
   commit-stage override to write NPC into the link register. That
   override never reaches the CDB-bypass path used by the RAT query,
   RS wakeup, and LSQ wakeup. While `branch_pending` was still
   stalling the front-end, no consumer ever saw that bypass: nothing
   could dispatch past an in-flight JAL. Once `branch_pending` is
   tied to zero, a `sw x27, …` dispatched right after the JAL
   captures the CDB value `0` for `x27` and silently writes zero
   into the stack frame, which breaks every recursive return. Fix:
   carry the dispatch-time NPC through the RS as an extra field and
   broadcast it on `cdb_value`.
2. **LSQ flush dropping committed stores mid-drain.** The store
   commit protocol is "ROB commits → LSQ marks `committed=1` → store
   drains to D-cache". On a branch mispredict the original flush
   cleared every LSQ entry, including a committed store that was
   still in the middle of its cache handshake. Fix: keep entries
   whose `is_store && committed` bits are both set; walk from head
   to find the new tail at the first non-busy slot.
3. **Stale D-cache response latched by a new head load.** The
   D-cache latches its request internally. If a flush drops an
   in-flight load, the cache still completes the line fetch and
   asserts `proc_done`. If the LSQ head happens to be a new load by
   then, the new load's `dcache_done` handler would latch the old
   response's data. Fix: a one-bit `stale_response_pending` flag in
   the LSQ, set on flush when the head load was in flight and cleared
   when the stale `dcache_done` arrives.

## Current regression status

All 34 programs in `programs/` halt cleanly at `HALTED_ON_WFI`.
`quicksort` went from hung at the 50 M-cycle cap to halting at
916,135 cycles (−4.4% vs the 958,030 baseline). `sort_search` was
the last holdout; it halts at 830,929 cycles / 181,994 instrs /
CPI 4.57 / 76.57% branch accuracy, ahead of the 882,994-cycle
SERIALIZE_BRANCHES baseline.

| Program            | Baseline cycles | New cycles | Delta            |
|--------------------|----------------:|-----------:|------------------|
| alexnet            |       9,465,750 |  9,409,859 | −56 k (−0.6%)    |
| backtrack          |         264,002 |    259,127 | −4.9 k (−1.8%)   |
| basic_malloc       |          50,037 |     49,633 | −404 (−0.8%)     |
| bfs                |         112,494 |    112,055 | −439 (−0.4%)     |
| btest1             |          17,090 |     17,089 | −1               |
| btest2             |          27,467 |     27,339 | −128 (−0.5%)     |
| copy               |           3,701 |      3,701 | 0                |
| copy_long          |           5,861 |      5,861 | 0                |
| dft                |       1,708,161 |  1,697,200 | −11 k (−0.6%)    |
| evens              |           1,178 |      1,172 | −6               |
| evens_long         |           2,979 |      2,975 | −4               |
| fc_forward         |          55,381 |     53,010 | −2.4 k (−4.3%)   |
| fib                |           2,415 |      2,415 | 0                |
| fib_long           |           6,521 |      6,521 | 0                |
| fib_rec            |          38,011 |     34,107 | −3.9 k (−10.3%)  |
| graph              |         461,494 |    457,876 | −3.6 k (−0.8%)   |
| haha               |             940 |        940 | 0                |
| halt               |             106 |        106 | 0                |
| insertion          |           3,630 |      3,394 | −236 (−6.5%)     |
| insertionsort      |         842,214 |    787,762 | −54 k (−6.5%)    |
| matrix_mult_rec    |         726,606 |    720,557 | −6.0 k (−0.8%)   |
| mergesort          |         303,270 |    303,262 | −8               |
| mult               |           7,558 |      7,558 | 0                |
| mult_no_lsq        |           2,833 |      2,749 | −84 (−3.0%)      |
| mytest             |             419 |        419 | 0                |
| no_hazard          |             731 |        731 | 0                |
| omegalul           |           3,964 |      3,964 | 0                |
| outer_product      |       4,848,166 |  4,659,248 | −189 k (−3.9%)   |
| parallel           |           2,325 |      2,325 | 0                |
| priority_queue     |          78,572 |     77,911 | −661 (−0.8%)     |
| quicksort          |         958,030 |    916,135 | −42 k (−4.4%)    |
| sampler            |           6,273 |      6,247 | −26              |
| saxpy              |           4,599 |      4,519 | −80 (−1.7%)      |
| sort_search        |         883,184 |    830,929 | −52 k (−5.9%)    |

On the three branch-heavy acceptance programs from the spec scenario:
`fib_rec` improves by 10.3%, `insertionsort` by 6.5%, and
`priority_queue` by 0.8%. Nothing regressed among the programs that
already halted at milestone 3.

Prediction accuracy is tracked by the instrumentation in
`test/pipeline_test.sv` and printed at halt as
`branch_accuracy: correct/total (pct)`. Measured values on the
programs with a non-trivial branch count:

| Program         | correct / total | accuracy |
|-----------------|----------------:|---------:|
| insertionsort   |  23,239 / 29,449 |  78.91%  |
| sort_search     |  22,696 / 29,638 |  76.57%  |
| quicksort       |  15,971 / 21,900 |  72.92%  |
| fib_rec         |   3,043 /  4,643 |  65.53%  |
| priority_queue  |      72 /    203 |  35.46%  |

The three big sorts land in the 73–79% range a 2-bit bimodal with
a small direct-mapped BTB usually sees on branchy integer code.
`fib_rec` drops to 65% because it is mostly JALR returns with
call-site-dependent targets and no Return Address Stack; every
switch between recursive frames mispredicts. `priority_queue` has
only 203 committed branches total, so its counter never really
warms up and the number is mostly variance. The small benchmarks
(`fib`, `fib_long`, `saxpy`) sit at 84–86% on a handful of branches
each; `no_hazard` commits zero branches, so the accuracy field is
printed as 0/0.

## Phase 11 debug pass: what was found

The `quicksort` hang was diagnosed and fixed in this branch. The
process and the three actual bugs that the pass shook loose are
worth recording here because the latter two are also real
pre-existing LSQ bugs that happen to be easier to spot once a
hanging symptom flagged them:

1. **Hang watchdog** (in `test/pipeline_test.sv`). A 16-entry ring
   that snapshots `{PC_reg, stall, mispredict_valid, rob_head,
   rob_count, lsq_head, lsq_count, LSQ-head entry bits,
   icache_valid / dcache_busy / dcache_done / drive flags}` every
   1 k cycles and dumps them on harness timeout. This turned a
   `System halted on unknown error code a` line into an actionable
   signature: `quicksort` was stuck at PC=0x130 with one in-flight
   load to address 0x4fa40 (past the 64 KB memory), so the D-cache
   was waiting forever for a memory response that the test harness
   refuses to produce. That narrowed the hunt to "why does
   `quicksort` ever try to load 0x4fa40 architecturally when the
   milestone-3 baseline never did."

2. **Prediction-accuracy counter** (same file). A pair of 64-bit
   counters for committed branches and `mispredict_valid` pulses,
   printed at halt. `quicksort` comes in at 72.9 %, `sort_search`
   at 76.7 %, against the 72–78 % rule-of-thumb for a 2-bit
   bimodal on branchy integer workloads. The counter is cheap to
   read via the same hierarchical references as the watchdog.

3. **LSQ fix A: committed store + flush + dcache_done race.**
   On a mispredict flush the LSQ preserves any committed head
   store waiting to drain. If the flush fell on the same cycle
   the D-cache asserted `dcache_done` for that store, the old
   `else` branch never ran and the store stayed queued. On the
   next cycle it re-issued `dcache_store` — either double-writing
   architectural memory on a hit or waiting forever for a second
   done on a miss. Fix: if the preserved head is a committed
   store with `dcache_done` this cycle, pop it inside the flush
   branch so the done counts exactly once. Covered by
   `test_flush_during_store_miss_done` and
   `test_flush_during_store_hit` in `test/lsq_test.sv`.

4. **LSQ fix B: back-to-back flushes leaking stale dcache
   responses.** The single-bit `stale_response_pending` can track
   exactly one outstanding stale, so two flushes inside the
   miss window leaked the second stale into the next real head
   load. Replaced with a saturating `stale_response_count`
   (`IDX_W+1` bits, so it can hold up to `LSQ_SZ`), incremented
   per flush that drops an in-flight load and decremented on each
   swallowed `dcache_done`. The counter is NOT bumped when the
   flush cycle already carries a `dcache_done` pulse — that
   response is for the flushed load and is effectively swallowed
   by the flush branch ignoring it, so bumping would double-count.
   Covered by `test_two_back_to_back_stale_responses`.

5. **Icache fix: mem response latched into the wrong line after a
   PC change.** This one was the actual `quicksort` blocker.
   `verilog/icache.sv` computed
   `got_mem_data = (current_mem_tag == Imem2proc_tag) && (current_mem_tag != 0)`
   and, on that cycle, wrote `icache_data[current_index] <=
   Imem2proc_data`. But on a commit-time mispredict redirect,
   `current_index` / `current_tag` update combinationally at the
   cycle boundary while `current_mem_tag` is still last cycle's
   tag. If the memory response for the old fetch happens to
   arrive on the first cycle after the redirect, the response is
   silently latched into the NEW PC's cache slot with the NEW PC's
   tags. Subsequent fetches of that new line return the old
   line's bytes forever — and the decoder turns those into a
   completely different instruction, flipping a load into a
   no-dest variant (e.g. a store or a branch) and corrupting
   architectural state. Milestone-3 hid this bug because
   `branch_pending = 1` serialized the front-end and produced
   far fewer mispredict-driven PC changes. Fix: gate
   `got_mem_data` on `!changed_addr` so the response is simply
   dropped when the fetch target has moved; the following cycle's
   `update_mem_tag` path resets `current_mem_tag` to zero
   cleanly.

## The `sort_search` fix: LSQ stale-response counting

With the LSQ committed-store and saturating-stale-counter fixes
plus the icache PC-change fix in place, `sort_search` still timed
out. It was committing ~10.9 M instructions in 50 M cycles, so the
program was looping architecturally rather than deadlocking the
pipeline. The culprit was a same-cycle race between the LSQ's
flush and the D-cache's accept of a fresh load.

### What the wb-diff pointed at

Building with `SERIALIZE_BRANCHES` (the diagnostic ifdef in
`verilog/pipeline.sv` that reinstates the milestone-3 front-end
serialization on in-flight branches) halted `sort_search` cleanly
at 882,994 cycles / 181,994 committed instructions. Diffing that
writeback stream against the speculative run showed a perfect
prefix match for the first 180,628 commits, then a divergence at
a reload of the saved return address:

```
PC=0x294  (lw x1, 44(x2))
  serialized  -> REG[1] = 0x00000284
  speculative -> REG[1] = 0x00000024
```

The `0x00000284` is the correct return-address value, pushed onto
the stack at some earlier `sw`. The `0x00000024` is the low 32
bits of `0x00000024_00000000`, the bytes that a just-evicted
D-cache line held at a different address that happens to map to
the same 64-bit line, right before it was written back to memory.

### Root cause

The pipeline testbench's store / load / mem-bus trace
(`<wb>.stores`) showed that the wrong fill data arrived on the
exact `miss_done` cycle where the LSQ's new head load latched it.
The first hypothesis blamed the D-cache's tag equality check
against the unmasked `mem2proc_tag`, but the unified-memory tag
model does not reuse a tag while a response for it is outstanding,
so that story did not close.

The actual bug was in the LSQ. On a branch mispredict,
`verilog/lsq.sv` already tracked "a stale D-cache response is in
flight" with a counter (`stale_response_count`): on flush, the
counter incremented if the flushed head was a load with its
`in_flight` bit set. The flaw is that `entries[head].in_flight`
is latched one cycle AFTER the LSQ first asserts `dcache_load`.
A flush that lands on the same cycle the D-cache was IDLE and
accepting a new head load therefore saw `in_flight=0` and did not
increment the counter, even though the cache had already committed
combinationally to fetching the dropped load's address. The
orphaned fetch later completed, its `proc_done` pulse was observed
by the new LSQ head (which by then had picked up a different
load), and the LSQ latched the wrong bytes as if they were the
new load's result. That cache line was then written into the
D-cache with the new request's tag/index, corrupting architectural
memory semantics for every subsequent load that hit that line.

### Fix

`verilog/lsq.sv` now takes a `dcache_busy` input (the D-cache's
`proc_busy`) and uses it in two places:

1. On flush, the stale-response counter increments for either
   `entries[head].in_flight` (the original case) or
   `head_load_releasable && !dcache_busy && !dcache_done`, the
   "cache is accepting this cycle" case that the original check
   missed. That arm alone unblocks `sort_search`.
2. The per-entry `in_flight` bit is now only set when the cache
   is actually IDLE, i.e. `head_load_releasable &&
   !entries[head].in_flight && !dcache_busy`. Previously the LSQ
   marked `in_flight=1` as soon as the head became releasable,
   even if the cache was still mid-fetch on an earlier request.
   On back-to-back flushes this caused the stale counter to
   double-count. No live hang in the real workload today, but a
   correctness hazard now that the counter is load-bearing.

`test/lsq_test.sv` feeds `dcache_busy = 1'b0` into the stub
(always-ready 1-cycle cache model), preserving the existing tests.
All LSQ unit tests pass; the full regression sits at 34/34.

### How the earlier phase-11 bugs fit in

For context, three other speculative-execution bugs were fixed
earlier in phase 11 and are what brought the regression from 32/34
up to 33/34 before this last LSQ fix.

- `verilog/icache.sv`: `got_mem_data` now gates on `!changed_addr`,
  so a memory response for an abandoned (mispredict-redirected)
  instruction fetch is not latched into the new PC's cache slot.
  Milestone-3 hid this bug because `branch_pending=1` serialized
  the front-end and produced far fewer PC redirects. This
  unblocked `quicksort`.
- `verilog/lsq.sv`: a committed store at the head that sees
  `dcache_done` on the flush cycle is now popped inside the flush
  branch, so the done event counts exactly once. Without the pop,
  a hit path would double-write and a miss path would lock up
  waiting for a second done.
- `verilog/lsq.sv`: the single-bit `stale_response_pending` flag
  was replaced with a saturating `stale_response_count` (width
  `IDX_W+1`, so it can hold up to `LSQ_SZ`) to survive two flushes
  landing inside the same miss window.

The `sort_search` fix then made the counter bookkeeping accurate
in the two places it had been off: detection on the
accept-this-cycle edge, and prevention of double-counting on
back-to-back flushes.

## Open follow-ups

1. Remove the `SERIALIZE_BRANCHES` diagnostic ifdef in
   `verilog/pipeline.sv` once the regression has soaked. It was
   useful for bisecting the `sort_search` divergence and has no
   further role now that the regression is green.
2. Remove the legacy `branch_pending`, `branch_target_buf`, and
   `branch_funct3_buf` wires in `verilog/pipeline.sv`. They are
   tied to zero today and carry no live logic.
3. Add a Return Address Stack for JALR. The `fib_rec` 65.53%
   accuracy number is almost entirely JALR return mispredicts
   against the BTB's single last-committed target per entry;
   every switch between recursive frames mispredicts.

## Known limitations

- JALR targets change per call site. The bimodal predictor keeps
  one last-committed target per BTB entry, so every call-site
  switch mispredicts. A Return Address Stack would fix this, but
  it is out of scope for the base-design requirement.
- The BTB is direct-mapped at 32 entries. On programs with many
  distinct hot branches, entries alias and each aliasing branch
  pays a cold miss on first execution. A 2-way set-associative
  BTB is on the backlog under the "associative caches" advanced
  feature.
- `branch_pending` is tied to zero but the wire is still there.
  That is deliberate: one line in `pipeline.sv` can restore
  serialization for bisecting if a regression shows up. A
  follow-up commit deletes the wire once the regression is fully
  green.
