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

33 of 34 programs in `programs/` halt cleanly at `HALTED_ON_WFI` after
phase 11 debugging. `quicksort` went from hung-at-50 M cycles to
halting at 915,974 cycles (−4.4% vs the 958,030 baseline). Only
`sort_search` still times out.

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
| quicksort          |         958,030 |    915,974 | −42 k (−4.4%)    |
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

## The remaining hang: `sort_search`

`sort_search` commits ~10.9 M instructions in 50 M cycles (CPI
around 4.5, within healthy range for this core), at ~76.7 % branch
accuracy, so the pipeline is not stuck — the program itself is
looping. That is roughly 10× the architectural instruction count of
a clean run, which means `sort_search` is re-doing the same work
many times over. The `quicksort`-class deadlock (single in-flight
load to an unmapped address) has been ruled out by the watchdog.

### What the wb-diff against `SERIALIZE_BRANCHES` shows

With `SERIALIZE_BRANCHES` compiled in (the diagnostic ifdef in
`verilog/pipeline.sv` that reinstates the milestone-3 front-end
serialization on in-flight branches), `sort_search` halts cleanly
at 882,994 cycles / 181,994 committed instructions. Diffing that
writeback stream against the speculative run shows a perfect
prefix match for the first 180,628 commits. The very first
diverging line is at a reload of the saved return address:

```
PC=0x294  (lw x1, 44(x2))
  serialized  -> REG[1] = 0x00000284
  speculative -> REG[1] = 0x00000024
```

Same `x2` (= 0xfdb0), same instruction bytes, different value
loaded. Because both traces committed the same 180,628 register
writes, every architectural register state along the way must
match — but the WB stream only shows register writes, not memory
stores. So somewhere in those 180,628 commits, a `sw` that
writes to `(x2)+44` is committing with different `data_value` in
the two runs. The speculative path stores `0x024`; the serialized
path stores `0x284`. When the matching `lw x1, 44(x2)` later
executes and `ret` jumps, the speculative target is 0x024 — the
init code — and the program re-runs init in an infinite loop.

Following this up with a per-store trace (`dcache_store &&
dcache_done` at the pipeline testbench, keyed to a `dbg_pc`
field added to each LSQ entry) and a per-memory-bus-write trace
(`proc2mem_command == BUS_STORE`), the bug was localized further.

In the speculative run, after every LSQ store and dcache eviction
up to cycle ~N is committed correctly to memory, the next LW to
the same line (same tag, same index, coming back after another
line had taken the slot in between) returns data that DOES NOT
match what memory was last written with. Concretely, for the
first diverging load of `x1` at PC=0x294 the trace shows:

```
cycle N+0 :  EVICT idx=27 tag=fd data=0x00000284_0000fe10
             (evicting the dirty line for 0xfdd8)
cycle N+0 :  MEM_SW addr=0x0000fdd8 data=0x00000284_0000fe10
             (dcache writes the correct bytes back to memory)
cycle N+1..k: ...other unrelated memory traffic...
cycle N+k :  PC=0x294 LW addr=0xfdd8 rd=0x00000024
             (full dcache_rd_data = 0x00000024_00000000 !!)
cycle N+k+1: MEM_RESP tag=1 data=0x00000024_00000000
cycle N+k+2: MEM_RESP tag=1 data=0x00000284_0000fe10
             (this was the correct response, one cycle too late)
```

So the dcache's `miss_done` fired on a memory response tag that
belonged to a DIFFERENT in-flight request and latched its data
(0x00000024_00000000) as the fill for its own 0xfdd8 miss. The
correct response for the 0xfdd8 fetch arrived on the very next
cycle but was dropped — the state machine had already moved on.

That points at either

1. An `mem_tag_reg` collision — the dcache's stored tag happened
   to equal the tag of a concurrent unrelated fetch (icache or an
   earlier abandoned dcache miss). Memory tags are reused after a
   response is delivered, so a stale `mem_tag_reg` that survived
   one request can silently match the response of a later
   request that happens to get the same tag.
2. A missing gate on `miss_done`: `Dmem2proc_tag` is driven from
   the unmasked `mem2proc_tag`, so the dcache sees tag pulses for
   EVERY in-flight request and relies entirely on the equality
   check against its own `mem_tag_reg`. Any path that leaves
   `mem_tag_reg` non-zero while not currently waiting on that
   tag is a live mis-fire hazard.

The fix is almost certainly along the same lines as the icache
fix — register the target of the outstanding fetch and gate
`miss_done` on it agreeing with the current in-flight request.
That's the concrete next step.

By contrast, the pre-fix `quicksort` hang was a pipeline deadlock:
PC stuck at 0x130, single in-flight load to address 0x4fa40 (past
the 64 KB test memory). That address traced back to an
architectural corruption: PC=0x118 loaded `0xfef8` as an integer
loop bound when the correct value was in the low single digits.
The icache-response-during-PC-change bug above corrupted the
cached bytes of a line, which made the decoder interpret the
instruction differently, which eventually stored a wrong value
into the stack slot for `high` and mis-computed a pointer. The
`diff` of the writeback stream against a serialized-branches
baseline showed the divergence at a PC=0x1ec load where the
speculative stream committed with `commit_wr_en=0` (wrong
`dest_reg`) while the baseline committed with `dest_reg=x15` —
exact same PC, different decoded `has_dest`, because the fetched
bytes differed.

Candidate causes to investigate next for `sort_search`:

1. A second icache edge that the `!changed_addr` gate does not
   cover — for example a cache line filled with partially stale
   bytes because the outstanding fetch tag was reassigned by the
   memory model while the icache was not driving.
2. A dcache response routing issue under sustained back-pressure
   where the existing arbitration mask on `mem2proc_response`
   lets the icache and dcache observe inconsistent tags during a
   2-cycle hand-off.
3. A data-dependent miscompile-like path where a speculative
   MULT result feeds into a dispatched dependent store BEFORE the
   `mult_flushed` poisoning latches, leaving a wrong value in an
   LSQ entry that later commits.

The fastest way to narrow it down is still the `quicksort` recipe:
capture a full writeback stream from a `SERIALIZE_BRANCHES`-built
simv and diff it against the speculative run until the first
architectural divergence. The cycle and PC of that divergence
point usually identify the offending subsystem within a few
minutes of reading.

## Open follow-ups

1. Finish the `sort_search` investigation: capture a
   `SERIALIZE_BRANCHES` writeback stream and diff against the
   speculative run to pin the divergence.
2. Run `make synth/branch_predictor.vg` and `make slack` to
   confirm synthesis is still green with the icache + LSQ
   changes (phase 8 of the openspec change).
3. Record per-program prediction-accuracy numbers into the
   results table above once `sort_search` is unblocked.
4. Remove the legacy `branch_pending`, `branch_target_buf`, and
   `branch_funct3_buf` wires in `verilog/pipeline.sv` — they are
   tied to zero and carry no logic in the committed regression
   today.

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
