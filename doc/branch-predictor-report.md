# Branch Predictor Report (in progress)

Status as of 2026-04-17: the change is today, the three bugs that
surfaced during bring-up, and the plan for the two programs that
still hang.

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

None of these three showed up in the predictor module's own unit test.
They only surface once `branch_pending` goes away and multiple
branches plus their speculative tails can be in flight at the same
time. All three had to be fixed before most of the regression suite
would halt.

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

32 of 34 programs in `programs/` halt cleanly at `HALTED_ON_WFI`:

| Program            | Baseline cycles | New cycles | Delta            |
|--------------------|----------------:|-----------:|------------------|
| alexnet            |       9,465,750 |  9,409,839 | −56 k (−0.6%)    |
| backtrack          |         264,002 |    259,127 | −4.9 k (−1.8%)   |
| basic_malloc       |          50,037 |     49,632 | −405 (−0.8%)     |
| bfs                |         112,494 |    112,055 | −439 (−0.4%)     |
| btest1             |          17,090 |     17,089 | −1               |
| btest2             |          27,467 |     27,339 | −128 (−0.5%)     |
| copy               |           3,701 |      3,701 | 0                |
| copy_long          |           5,861 |      5,861 | 0                |
| dft                |       1,708,161 |  1,697,139 | −11 k (−0.6%)    |
| evens              |           1,178 |      1,172 | −6               |
| evens_long         |           2,979 |      2,975 | −4               |
| fc_forward         |          55,381 |     53,010 | −2.4 k (−4.3%)   |
| fib                |           2,415 |      2,415 | 0                |
| fib_long           |           6,521 |      6,521 | 0                |
| fib_rec            |          38,011 |     34,107 | −3.9 k (−10.3%)  |
| graph              |         461,494 |    457,835 | −3.7 k (−0.8%)   |
| haha               |             940 |        940 | 0                |
| halt               |             106 |        106 | 0                |
| insertion          |           3,630 |      3,394 | −236 (−6.5%)     |
| insertionsort      |         842,214 |    787,292 | −55 k (−6.5%)    |
| matrix_mult_rec    |         726,606 |    720,553 | −6.1 k (−0.8%)   |
| mergesort          |         303,270 |    303,210 | −60              |
| mult               |           7,558 |      7,558 | 0                |
| mult_no_lsq        |           2,833 |      2,749 | −84 (−3.0%)      |
| mytest             |             419 |        419 | 0                |
| no_hazard          |             731 |        731 | 0                |
| omegalul           |           3,964 |      3,964 | 0                |
| outer_product      |       4,848,166 |  4,658,300 | −190 k (−3.9%)   |
| parallel           |           2,325 |      2,325 | 0                |
| priority_queue     |          78,572 |     77,911 | −661 (−0.8%)     |
| **quicksort**      |         958,030 |    **hang** | —               |
| sampler            |           6,273 |      6,247 | −26              |
| saxpy              |           4,599 |      4,519 | −80 (−1.7%)      |
| **sort_search**    |         883,184 |    **hang** | —               |

On the three branch-heavy acceptance programs from the spec scenario:
`fib_rec` improves by 10.3%, `insertionsort` by 6.5%, and
`priority_queue` by 0.8%. Nothing regressed among the programs that
already halted at milestone 3.

A per-branch prediction-accuracy counter has not been wired up yet;
this is task 7.5 in the open change and is what the next chunk of
work should start with once the two hangs are unblocked.

## The two remaining hangs: `quicksort` and `sort_search`

Both programs commit work for a while and then hit the 50 M-cycle
harness cap. Neither shows the earlier "re-enter `main` from PC=0"
signature that `fib_rec` had before the JAL/JALR CDB fix: `main` is
entered exactly once in both traces. Neither shows the "every load
of `x27` reads 0" signature that was the store-loss bug. The three
bugs already fixed are not in play.

What we know about the two stuck programs:

- **`quicksort`**: 315 k committed instructions in 50 M cycles.
  That is CPI around 158: the pipeline is almost entirely stalled.
  Commit counts per PC cluster tightly around 18 k per PC in the
  same basic block, which looks like a loop going nowhere rather
  than a pipeline that is just slow.
- **`sort_search`**: 11 M committed instructions in 50 M cycles.
  CPI around 4.5, which is close to healthy for this core. But
  the commit count is roughly 10× the baseline's architectural
  instruction count. So forward progress is real, and the program
  is re-doing the same work many times over.

Hypotheses to test, in roughly the order I'd test them:

1. **A store on the LSQ head committing on the same cycle as a
   flush.** The preserve-committed-store logic keeps the entry
   alive, but the `in_flight` bit timing and the interaction with
   `dcache_done` on a flush cycle is the kind of edge the unit
   tests would not catch. Concretely: if a committed store is
   popping on the flush cycle, does it pop, stay, or double-pop?
2. **A stale response path that still is not covered.** The LSQ
   swallows exactly one stale `dcache_done` per flush (the one
   from an in-flight load). Stores have a symmetric case, and a
   back-to-back flush pair can queue up two stale responses.
3. **An RS wakeup dropped on flush whose producer survived.** An
   RS entry whose source tag points at a still-valid ROB entry
   (rare, but possible if the RS and ROB flushes land on
   different cycles).
4. **JALR target written by a load whose base was woken from a
   different ROB tag under speculative pressure.** This was the
   root cause on `fib_rec`. It is nominally fixed, but re-check
   it on `quicksort`, whose function prologues are more
   elaborate than `fib_rec`'s.
5. **Deep recursion starving commit via a full ROB or LSQ.** If
   the pipeline dispatches eight instructions into the ROB and
   none of them can commit because head is waiting on an operand
   whose producer was flushed, the pipeline deadlocks.

## Debug plan (open)

1. Add a small hang detector to `test/pipeline_test.sv`. Every 1 k
   cycles, snapshot the ROB head tag, LSQ head tag, `PC_reg`,
   `stall`, and `mispredict_valid` into a ring of the last ~16
   snapshots. On timeout, dump the ring. Run it on `quicksort` and
   `sort_search` to see whether the pipeline is genuinely stuck or
   just slow, and on what.
2. Instrument the LSQ flush path: `$display` the entries it
   preserves and the new `head/tail/count` on every flush cycle.
   Replay `quicksort` for a few hundred k cycles and look for a
   committed store that gets dropped or preserved wrong.
3. Write a targeted unit test in `lsq_test.sv` for hypothesis 1:
   committed store at head mid-drain, flush fires on the same
   cycle `dcache_done` is asserted. The store must pop exactly
   once and the LSQ must be empty next cycle.
4. Count committed branches vs `mispredict_valid` pulses to get a
   mispredict rate per run. A near-100% mispredict rate on a
   specific PC points straight at the loop that is degenerating.
5. If the hang survives all of the above, trim `quicksort` down
   with smaller input arrays and diff the trace against a run
   that completes.

Task 7.5 in the openspec change adds a per-program
prediction-accuracy counter. Do that first: it makes steps 3 and 4
much easier to read.

## Known limitations (by design, not bugs)

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
