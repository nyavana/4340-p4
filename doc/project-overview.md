# Project Overview

Orientation doc. If you haven't opened the source before, read this first. It covers what we built, where it lives, how to run it, and which edges are still sharp. Spec is in [`project-description.md`](project-description.md), team plan in [`project-proposal.md`](project-proposal.md); this file doesn't repeat either.

---

## 1. What the project is

We are extending the VeriSimpleV RISC-V pipeline from Project 3 into a synthesizable
**out-of-order** processor. The team picked a **P6-style** design: in-order fetch and
decode, register renaming through a Register Alias Table, out-of-order issue and
execute, broadcast on a Common Data Bus, and in-order commit through a Reorder
Buffer. The processor is built and tested module by module, then integrated into a
single top-level `pipeline.sv` that runs real RISC-V binaries through the existing
testbench harness.

Our processor today is one instruction wide. The architecture has room for more,
and the proposal calls out 2-way superscalar plus early tag broadcast as the
"difficult" advanced features we want to add later.

---

## 2. The constraints we cannot break

These are baked into the spec, not into our design choices. They appear here so a
new contributor does not accidentally cross one of them.

1. **I-cache and D-cache are each capped at 256 bytes**, 512 bytes total.
2. **Memory latency is fixed at 100 ns.** In `verilog/sys_defs.svh:79` it is
   computed as `MEM_LATENCY_IN_CYCLES = ceil(100 / CLOCK_PERIOD)`. Do not "fix" a
   slow program by lowering it.
3. **Number of CDBs may not exceed the superscalar width** of the narrowest stage
   of the pipeline. We are 1-wide today, so we have one CDB.
4. **The multiplier must be the one from Project 2**, in `verilog/mult.sv` and
   `verilog/mult_stage.sv`. The number of pipeline stages (`MULT_STAGES`) is
   tunable, the underlying logic is not.

---

## 3. Timeline of what we built

### 3.1 Starter (`4340-p4`, instructor-provided)

The starter ships with the in-order P3 pipeline as a reference, a multiplier from
P2, an instruction cache, a register file, a decoder, a priority selector helper,
and a stripped-down `pipeline.sv` skeleton. There is no ROB, no RS, no RAT, no
LSQ, no branch predictor. `verilog/sys_defs.svh` carries placeholder `xx` values
for `ROB_SZ`, `RS_SZ`, `LSQ_SZ`, and other parameters that the team is expected to
fill in. `make simv` does not build out of the box because the skeleton
`pipeline.sv` references modules that do not exist yet.

### 3.2 Week 1 / Milestone 1

Two team members worked on two complementary pieces in parallel branches on
the GitHub repo `CSEE4340-26/p4.GaPiChiXuXu`:

- Branch **`milestone1`** added `verilog/rs.sv` (the Reservation Station) and its
  unit test `test/rs_test.sv`, and set `ROB_SZ` and `RS_SZ` to concrete values.
- Branch **`milestone2`** added `verilog/rob.sv` (the Reorder Buffer with the RAT
  embedded) and a complete refactor of `verilog/pipeline.sv` from the in-order
  skeleton into the P6 dataflow we use today.

These two branches had to land together: `pipeline.sv` from `milestone2`
instantiates `rs rs_0 (...)`, but `rs.sv` only existed on `milestone1`. Neither
branch built end-to-end on its own.

### 3.3 Week 3: the integration merge

A new `week3` branch was created off `milestone1`, then `milestone2` was merged
into it. The auto-merge handled `sys_defs.svh` (the two branches edited disjoint
parameter lines). Two conflicts had to be resolved by hand:

- `Makefile:180` had a `<<<<<<< Updated upstream` block left over from a botched
  `git stash pop`, on top of the milestone1/milestone2 conflict. It was collapsed
  to `TESTED_MODULES = mult rob rs`.
- A nested conflict in the same hunk introduced an `RS rs` typo. That got
  cleaned up at the same time.

After the merge:
- `make simv` compiled cleanly for the first time on any branch.
- `make no_hazard.out` ran end-to-end: 14 instructions, 731 cycles, clean halt
  on `HALTED_ON_WFI`, all writebacks correct.
- `make mult_no_lsq.out` revealed a deeper bug that had been invisible before
  (because `milestone2` was previously unbuildable).

The full merge writeup, including conflict resolution and verification, is in
[`week3-merge-report.md`](weekly-reports/week3-merge-report.md).

### 3.4 Week 4: Milestone 2 stabilization

Week 4 was about closing the two biggest gaps the integration exposed.

The first gap was the missing ROB testbench. `make rob.pass` did not even
compile, because `test/rob_test.sv` did not exist. We wrote it, and it now
covers ten scenarios: dispatch, CDB completion, in-order commit, same-cycle
RAT bypass, stale-clear protection, the x0 guard, flush, full detection, and
wraparound. Both `make rob.pass` and `make rob.syn.pass` are green.

The second gap was `mult_no_lsq`. On the v2 branch this hangs deterministically:
the simulator stops advancing time around cycle 2192, after 44 correct
writebacks. The pipeline gets through the setup phase, a full first iteration
of the loop, and the first two instructions of the second iteration before it
freezes. We ruled out the multiplier handshake, the ROB, and the RS in
isolation. The current suspicion is a combinational cycle or delta-cycle storm
at the icache / `mem.sv` boundary. Full investigation in
[`week4-mult_no_lsq-findings.md`](weekly-reports/week4-mult_no_lsq-findings.md); the earlier
debugging plan is in [`week4-followup-plan.md`](weekly-reports/week4-followup-plan.md).

The current canonical state of the project is the `week4-merge-v2` branch on
`nyavana/4340-p4`, mirrored locally in `4340-p4-week4-merge-m2-v2/`.

### 3.5 Week 5: Milestone 3 — memory ops via LSQ + write-back D-cache

Week 5 was the memory milestone. The pipeline now runs loads and stores
end-to-end through a Load-Store Queue and a write-back data cache, all the
RV32IM byte/half/word variants work, and JAL/JALR finally write the return
address into the destination register. That last one was a milestone 2 bug
that nobody noticed until C programs started making function calls and
jumping to address zero.

The new pieces:

- `verilog/dcache.sv`: a 32-line, 64-bit-wide, direct-mapped, write-back,
  write-allocate D-cache. 256 bytes total, exactly at the spec cap. Sub-word
  stores are absorbed as a byte-enable mask on the line; only line evictions
  write back, and the writeback is always a full doubleword (the only thing
  `mem.sv` accepts in cache mode).
- `verilog/lsq.sv`: a combined load/store queue, FIFO of 8 entries by
  default. Snoops the CDB to wake up base/data operands, computes addresses
  with an internal AGU, and arbitrates the cache request. Memory ops bypass
  the RS so the LSQ can keep its entries in program order.

The memory ordering policy is deliberately conservative: head-only, no
store-to-load forwarding. A load behind an in-flight store waits for the
store to fully drain to the cache. Stores hold their (addr, data, mem_size)
until the ROB retires them; only then do they get released. Architectural
memory is never written by a mis-speculated path, and there is no forwarding
correctness work to chase. The cost is performance: a load behind a store
pays the full miss latency at least once per line.

Pipeline integration touched several places:

- The old inline single-line load FU is gone. Memory ops bypass the RS at
  dispatch and allocate directly into the LSQ.
- A new dispatch-side store-data resolver always reads `rs2` for stores.
  The existing `dispatch_src2` returns the immediate for an S-type encoding,
  so it cannot double-duty here.
- CDB priority is now MULT > LSQ load complete > ALU. Stores never use the
  CDB; they use a dedicated `store_done_valid` / `store_done_tag` sideband
  on the ROB.
- Bus arbitration: dcache priority over icache, with each cache's view of
  `mem2proc_response` masked to the cycle it actually drove the bus.
- The branch-target broadcast for JAL/JALR now uses `alu_result` (which is
  `PC + Jimm` for JAL and `rs1 + Iimm` for JALR), with bit 0 cleared per the
  JALR spec. The pre-computed `branch_target_buf` was wrong for JALR: it
  always added a J-immediate to the PC.

The ROB grew an `is_store` field per entry, the new `store_done` sideband
ports, and a commit value override for branches with non-zero destinations
(JAL/JALR), which now commit `entries[head].NPC` instead of the
CDB-broadcast value. That is the return address the milestone 2 pipeline
was silently writing as zero.

The result: 18 of 33 test programs reach `HALTED_ON_WFI`, up from roughly
30% at the milestone 2 baseline. New passes include `saxpy` (the first real
loads-and-stores-in-a-loop program), `fib_rec`, `sampler`, and five C
programs (`basic_malloc`, `fc_forward`, `insertionsort`, `omegalul`,
`priority_queue`) — all of which depend on the JAL/JALR fix. Both
`make dcache.pass` / `make dcache.syn.pass` and `make lsq.pass` /
`make lsq.syn.pass` are green. Full per-program results are in
[`milestone3-results.md`](weekly-reports/milestone3-results.md), and the full writeup is
in [`milestone3-report.md`](weekly-reports/milestone3-report.md).

The cycle-2192 `mult_no_lsq` hang is still unresolved. It now shares its
signature with about a dozen other programs that have tight back-to-back
inner loops: PC sits on the first instruction of the second iteration, the
LSQ has a single store at its head with `committed=1` and `in_flight=1`,
and `dcache_done` never asserts. The same workload with NOPs added between
every instruction (`copy_long`) passes cleanly, so the deadlock is timing-
or wakeup-related rather than functional. Diagnosing it is the top item to
chase next.

### 3.6 Week 6: Milestone 4 — branch predictor, speculation, base-design sign-off

Week 6 closed the base design. Two pieces had to land together: a branch
predictor to redirect the front-end on predicted-taken hits without waiting
for commit, and a recovery path to undo the speculation when the prediction
turned out wrong.

The new module is `verilog/branch_predictor.sv`: a 32-entry direct-mapped BTB
indexed by `PC[6:2]` with a `PC[31:7]` tag, paired with a 64-entry bimodal
direction table of 2-bit saturating counters (reset to weakly-not-taken `01`).
The predict port is combinational on the fetch PC and returns
`{pred_valid, pred_taken, pred_target, pred_is_uncond}`. The update port is
registered and fires once per committing branch, driven out of the ROB. Unit
test covers cold miss, learning, saturation, flip, tag alias, and
write-then-read — nine scenarios, 100% line and branch coverage on the DUT,
green in both simulation and synthesis.

The integration removed the front-end serialization that had been in place
since milestone 2. `branch_pending` is now tied to zero; the predictor
redirects fetch on a predicted-taken hit, and multiple branches can be in
flight at once. The ROB does the mispredict check at commit: it carries
`predicted_taken`, `predicted_target`, `is_uncond_branch`, and `branch_PC` per
entry, and raises a one-cycle `mispredict_valid` / `mispredict_target` sideband
when prediction and outcome disagree. That sideband drives `flush` on the RS,
LSQ, and in-flight MULT and redirects `PC_reg`.

Removing `branch_pending` shook loose four latent bugs that the serialization
had been hiding:

- JAL/JALR were broadcasting `0` on the CDB as the "link value", with the real
  return address patched in only at commit. Same-cycle RAT-query and
  LSQ-wakeup consumers saw the zero and silently wrote it through. Fix: each
  RS entry now carries its own `branch_NPC`, and the CDB broadcasts that
  instead. The ROB commit-time override of `entries[head].NPC` is still
  required and still present.
- The LSQ flush had to preserve a committed store mid-handshake with the
  D-cache (a store the architecture has already released cannot be dropped),
  and had to swallow the D-cache response belonging to a flushed in-flight
  load. A 1-bit `stale_response_pending` handles the latter.
- In-flight MULT had to be poisoned across a flush so its eventual CDB
  broadcast could not clobber a re-allocated ROB slot.
- The icache had to tolerate PC changes mid-miss; an abandon path already
  existed for that case but had not been exercised until speculation was live.

Separately, a combinational loop through the RS issue selector
(`issue_found` → `src*_ready_eff` → `cdb_valid` → `issue_accept` → `issue_found`)
was root-caused and fixed. The selector now reads the registered
`entries[i].src*_ready`, not the combinational `_eff`. That fix alone unblocked
the `mult_no_lsq` cycle-2192 hang and roughly a dozen other tight-loop
programs from milestone 3. Writeup in
[`rs-issue-loop-fix.md`](base-design/rs-issue-loop-fix.md); the branch-predictor bring-up
and its four integration bugs are in
[`branch-predictor-report.md`](base-design/branch-predictor-report.md).

All 33 programs in `programs/` now halt cleanly at `HALTED_ON_WFI`. Using
`+define+SERIALIZE_BRANCHES` — a diagnostic ifdef in `pipeline.sv` that
reinstates milestone-3 front-end serialization — as the reference, every `.wb`
stream on `milestone4` is byte-identical to the same commit rebuilt with
serialization on. Zero architectural divergence from speculation.
Branch-heavy benchmarks speed up measurably: `fib_rec` −10.5%,
`insertionsort` −6.4%, `insertion` −6.5%, `sort_search` −5.9%,
`fc_forward` −4.3%, `outer_product` −3.8%, `quicksort` −3.5%. Nothing
regresses. Full evidence in
[`base-design-verification.md`](base-design/base-design-verification.md).

The current canonical state of the project is the `milestone4` branch in
`4340-p4-milestone4/`.

### 3.7 Week 7: Early tag broadcast (advanced feature, correctness-only)

Week 7 is the first advanced feature: early tag broadcast (ETB).  The
idea is small and localized — the multiplier raises an extra one-cycle-
early sideband naming the ROB tag that will retire on the next CDB
cycle, and the RS / LSQ use it to flip the registered `src*_ready` bit
a cycle sooner on entries whose operand is that tag.  Nothing about
dispatch, commit, or CDB width changes.

The producer is a single tap: `verilog/mult.sv` exposes
`early_done = internal_dones[MULT_STAGES-2]`, which is the `done` flop
of the second-to-last `mult_stage`.  It fires exactly one cycle before
the final `done`.  `verilog/pipeline.sv` combines that with the
registered producer tag into the `{early_cdb_valid, early_cdb_tag}`
sideband, gated by `!mult_flushed && !mispredict_valid` so a poisoned
multiply cannot wake a re-dispatched consumer.  A
`+define+DISABLE_EARLY_TAG` escape hatch at the Makefile level ties the
valid bit to 0 for regression A/B.

The consumers are `verilog/rs.sv` and `verilog/lsq.sv`.  Each entry
grows a pair of registered bits — `src*_val_present` on the RS,
`base_val_present` / `data_val_present` on the LSQ.  Dispatch
initializes them alongside `*_ready`; ETB flips only the `*_ready` bit
and leaves `*_val_present` at 0 for the one-cycle window; the real CDB
broadcast the next cycle latches the value and flips `val_present` to 1.
The CDB wakeup is gated on `!val_present` (rather than `!ready`), so an
entry already woken by ETB still receives the value on the CDB cycle.
The RS issue value-mux gains a `!val_present` arm that forwards
`cdb_value` when the selector picks an ETB-woken entry — this is the
only codepath that looks at `cdb_value` for an already-ready entry.

The load-bearing rule from `rs-issue-loop-fix.md` is preserved: the
issue selector reads the *registered* `src*_ready` only.  ETB never
feeds `issue_found` combinationally.  The wakeup block sets the
registered bit through `next_entries`, one cycle away from the
selector.  This is verified by a dedicated unit test
(`test_early_tag_does_not_bypass_selector_combinationally` in
`test/rs_test.sv`) that pulses `early_cdb_valid` and asserts
`issue_valid` stays 0 on that cycle.

Verification: all 33 programs halt at WFI with ETB on and with
`DISABLE_EARLY_TAG`; every `.wb` file is byte-identical to the
`SERIALIZE_BRANCHES` sign-off baseline in both modes; the 6 tested
modules pass in sim and synth; the new ETB-specific unit-test scenarios
pass in both sim and synth.

Per-program cycle counts are **unchanged** on all 33 programs (ETB-on
matches the pre-ETB `baseline-etb-off.txt` exactly).  The expected
MULT-chain speed-up is swallowed by CDB contention: on the cycle the
MULT broadcasts, `issue_accept` for non-MULT ops is
`!mult_done_valid` = 0, so the consumer still has to issue on cycle
N+2 whether ETB fired or not.  The mechanism works (unit tests confirm
`early_done` leads `done` by exactly one cycle and that `src*_ready` /
`base_ready` flip one cycle earlier); the observable perf win waits
for a second CDB to land with 2-way superscalar, which a teammate is
working on in parallel.  Design trade-offs, the cycle-by-cycle timing
diagram, and alternatives considered are in
[`early-tag-broadcast-report.md`](advanced-features/early-tag-broadcast-report.md).

### 3.8 Week 8: the rest of the advanced features land in one wave

Six teammates had been running their advanced features in parallel
branches off `milestone3`. Week 8 was about merging them in and
verifying nothing broke. The branches were `feat-dcache-prefetch`
(next-line stream-buffer prefetcher), `2_way_superscalar` (dual-issue
dispatch / commit, the second "difficult" feature), `assoc_cache`
(2-way set-associative D-cache), `gshare` (full-width GHR XOR
predictor replacing the bimodal direction table), `feat-ras-cz2931`
(16-entry Return Address Stack), and `feat-stlf-cz2931` (store-to-load
forwarding in the LSQ). ETB was already on `milestone3` from week 7.
A seventh branch, `2_way_syn_and_out`, carried a per-program CPI /
branch-accuracy comparison file that hadn't been folded back in.

The merges landed in this order on `milestone3`:
`dcache-prefetch` (`bd78846`) →
`2_way_superscalar` functional code (`a53ee19`) →
ETB integration with the new 2-way frontend (`3825a2f`) →
`gshare` (`e5c1e66`) →
`feat-ras-cz2931`, which also folded in a gshare GHR variant (`5f3e5e0`) →
`feat-stlf-cz2931` (`dc484b0`, head of `milestone3`).

The 2-way superscalar tip carried a Design Compiler compatibility fix
(replacing `'{...}` assignment patterns at port connections with named
temp arrays) that didn't make it into the merge. The equivalent fix
was independently re-applied to `milestone3` as `bd719c8`, so the
synth-clean state landed anyway — the unmerged tip commit is now
redundant.

We worktreed off `dc484b0` on a branch called `verify-merged-features`,
cherry-picked the missing comparison file (`96de569
branch_accuracy_cpi_diff.md`), and ran the full verification suite.
What came out:

- All 33 programs in `programs/` halt at WFI under both RTL sim
  (`make simulate_all`) and synthesized gate-level sim
  (`make simulate_all_syn`).
- Every `.syn.wb` is byte-identical to its `.wb`. Cycle counts on the
  synthesized netlist are `RTL + 1` exactly across the board (the
  canonical Synopsys gate-level reset offset). The merged stack
  synthesizes to a netlist that is functionally bit-equivalent to the
  RTL.
- Cumulative CPI improvement against the April-26 in-tree snapshot
  (the `+` side of `branch_accuracy_cpi_diff.md`, capturing
  `milestone3` after 2-way + dcache prefetch but before ETB / gshare /
  RAS / STLF) ranges from a few percent on the smallest programs to
  −49.6 % on `alexnet`. Branchy and memory-heavy programs see the
  largest gains: `btest2` −48.5 %, `sampler` −45.7 %,
  `priority_queue` −44.3 %, `basic_malloc` −44.0 %, `graph` −43.2 %,
  `bfs` −40.5 %, `dft` −40.3 %. Nothing regressed.
- Per-module synth all met timing at the 1000 ps clock. Tightest two:
  `lsq` at +0.05 ps and `mult` at +0.23 ps. The other five had
  ≥ +19 ps of slack.
- Full-pipeline synth (`synth/pipeline.vg`) worst slack is
  **−797.58 ps** on `lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]`
  with a companion endpoint `lsq_0/head_reg[2] → lsq_0/entries_reg[3][addr][31]`
  at −797.55 ps. Two endpoints violate. The path runs
  `LSQ broadcast → RS operand mux → ALU 32-bit adder → {ROB take_branch, LSQ addr}`
  — the MULT stage-0 cone referenced in older write-ups is closed by
  `51b7f1c`'s mult-operand register. Re-baseline of `dbcd4f6` (without
  `51b7f1c`) gave ≈ −1600 ps, so the mult-operand register recovered
  ~800 ps standalone. The earlier `−504.66 → −244.54 ps` STLF
  pipelining number used stale build artefacts and was retracted.
  Functional gate-level sim was bit-identical to RTL on the
  pre-`51b7f1c` baseline; the merge inserts a flop in front of the
  multiplier (no value change), so the property is expected to hold
  but `simulate_all_syn` was not re-run after the merge. Closing the
  residual fully would mean either registering
  `load_complete_value`/`load_complete_tag` between LSQ and CDB (one
  more cycle on every load) or rebalancing the broadcast → adder
  path; both deferred.
- The four unit-test infrastructure regressions are now fixed
  (verify-merged-features pass, 2026-04-30).
  `branch_predictor_test.sv` Tests 2 / 5 / 7 now run against a
  TB-side gshare model that mirrors GHR + BHT + BTB. Test 7 picks
  colliding PCs for each update step so `bht_pc_bits(pc_k) ^ ghr_pre_k`
  always equals a chosen target index, which keeps the original
  saturate-then-flip semantic intact under gshare. Test 6 was already
  passing because all-not-takens leaves GHR at 0.
  `rob.syn.pass`, `rs.syn.pass`, `lsq.syn.pass`, `icache.syn.pass` are
  green again. The first three use the existing `synth/<m>_svsim.sv`
  wrappers, which keep unpacked-array ports and repack into the
  netlist's packed buses with `{>>{ }}`; the Makefile pulls them in
  as per-target prerequisites of `.syn.simv`, and the testbenches pick
  `<m>_svsim` instead of `<m>` under `+define+SYNTH`. `lsq_test.sv`
  also got two `ifndef SYNTH` guards around `dut.count` XMRs.
  `icache.syn.simv` now lists `verilog/stream_buffer.sv` as an
  explicit dependency.

Full per-program tables, the verbatim slack endpoints, and the
recommendation list are in
[`advanced-features-merge-report.md`](advanced-features/advanced-features-merge-report.md).

Each advanced feature now has an in-tree per-feature report. They
are grouped per-module rather than one per merge branch: gshare and
RAS shipped together in `branch_predictor.sv`, the dcache features
all live in `dcache.sv` / `stream_buffer.sv`, and the 2-way
superscalar is its own write-up because it touches every stage.

- [`advanced-features/early-tag-broadcast-report.md`](advanced-features/early-tag-broadcast-report.md)
- [`advanced-features/superscalar-report.md`](advanced-features/superscalar-report.md)
- [`advanced-features/branch-predictor-advanced-report.md`](advanced-features/branch-predictor-advanced-report.md) — gshare + RAS
- [`advanced-features/dcache-advanced-report.md`](advanced-features/dcache-advanced-report.md) — set-associative + next-line prefetch + icache stream buffer
- [`advanced-features/stlf-report.md`](advanced-features/stlf-report.md)

Per-feature attribution is sometimes ambiguous: gshare and RAS landed
in the same merge commit, the dcache features came from one branch,
and the verify-merged-features pass folded the STLF timing fix into
the same RTL as the original merge. Where attribution is ambiguous
the reports say so and quote the cumulative §5 numbers from the
merge report rather than synthesizing per-feature deltas the
regression cannot prove.

---

## 4. Architecture in one read-through

The processor is one big module, `pipeline.sv`, plus two large submodules
(`rob.sv` and `rs.sv`) and a handful of leaf modules (`icache`, `regfile`,
`decoder`, `mult`, `mult_stage`, `psel_gen`).

Walk through it the way an instruction does.

**1. Fetch.** `PC_reg` drives the icache. The icache returns a 64-bit line, and
the pipeline picks the high or low half based on `PC_reg[2]`. The fetch stalls
when any of the following is true: the icache is not ready, the RS is full, or
the ROB is full. The `branch_pending` serialization that milestone 2 and 3
used is gone — `branch_pending` is tied to zero. In its place, the branch
predictor runs combinationally on the fetch PC: on a predicted-taken hit the
predictor redirects fetch the same cycle, and the prediction packet
(`BRANCH_PRED_PACKET`) rides through decode into the instruction's ROB
entry so the commit stage can check it later.

**2. Decode.** The fetched word goes into `decoder.sv`, which produces operand
selects, the ALU function, and a handful of flags (`rd_mem`, `cond_branch`,
`uncond_branch`, `halt`, `illegal`, …). The decoder is the same one we used in
P3, copied verbatim.

**3. Rename and operand resolution.** For each source register the pipeline
queries the ROB's embedded RAT (`rob.sv` query ports `query1_*` / `query2_*`).
The query returns one of three answers:

- *Not pending*: no in-flight ROB entry owns this register. Read the regfile.
- *Pending and ready*: an in-flight entry owns it but its value is already in
  the ROB. Forward that value.
- *Pending and not ready*: an in-flight entry owns it but it has not finished
  yet. The instruction goes into the RS with that ROB tag and waits.

The query also implements **same-cycle CDB bypass**: if the CDB is broadcasting
the very tag the RAT points at this cycle, the query returns ready with the
CDB value, so the new instruction can be dispatched immediately as ready.
Constant operands (PC, NPC, immediates) bypass the RAT entirely. See
`pipeline.sv:243-299`.

**4. Dispatch.** A single dispatch fires both ROB allocation and RS allocation in
the same cycle. The ROB hands back `dispatch_tag` (= current tail), which becomes
the renamed destination tag for the instruction. The RAT is updated in the same
cycle (except for `x0`, which is never tracked). Branch metadata — the
dispatch-time target, `funct3`, and NPC — rides into the RS entry itself
(`branch_target`, `branch_funct3`, `branch_NPC`), not into a shared latch. The
prediction packet rides into the branch's ROB entry so commit can compare
predicted vs. actual. See `pipeline.sv:304-402`.

**5. Issue.** The RS finds the oldest entry whose two source operands are both
ready (with same-cycle CDB wakeup folded in) and drives `issue_valid` plus the
opcode and operand values out to the execution side. The issue is gated by
`issue_accept`, which ensures the right functional unit is free. The MULT FU has
priority: while `mult_done` is pulsing, the ALU CDB path is held off so that
MULT and ALU never collide on the bus. Memory ops do **not** flow through the
RS — they bypass it at dispatch and go straight into the LSQ, which keeps loads
and stores in program order. See `rs.sv:104-147` and `pipeline.sv:140-147`.

**6. Execute.** Three units:

- The **ALU** is single-cycle and inline in `pipeline.sv:490-504`. It handles
  add, sub, the logic ops, the shifts, SLT, and SLTU.
- The **multiplier** is the pipelined `mult` module from P2, defaulting to four
  stages. The pipeline pre-extends operands to 64 bits depending on whether the
  multiply is signed or unsigned, and selects the upper or lower 32 bits of the
  product depending on the variant. `pipeline.sv:407-452`.
- **Conditional branches** resolve inline next to the ALU using the latched
  `branch_funct3_buf` to pick BEQ / BNE / BLT / BGE / BLTU / BGEU. JAL and
  JALR use `alu_result` as the branch target (with bit 0 cleared for JALR),
  not the dispatch-time `branch_target_buf` — that buffer is only correct for
  conditional branches and JAL with a J-immediate. The branch outcome and the
  computed target ride the CDB on the same cycle.

The **LSQ** (`verilog/lsq.sv`) handles all loads and stores. Memory ops are
allocated into the LSQ at dispatch, not the RS. The LSQ snoops the CDB to
wake up its base/data operands, computes effective addresses with an internal
AGU, arbitrates for the D-cache one entry at a time from the head, and drives
either `load_done_*` (for loads) or `store_done_*` (for stores) when the
cache responds. The policy is head-only with no store-to-load forwarding: a
load behind an unresolved store waits. Stores hold their data until the ROB
commits the matching entry; only then are they released to the cache. This
guarantees that architectural memory is never written by a mis-speculated
path.

The **D-cache** (`verilog/dcache.sv`) is a 32-line, write-back, write-allocate
direct-mapped cache, 256 bytes total. Sub-word stores never round-trip
through main memory: the cache absorbs them as a byte-enable mask on the
line, and only line evictions write back as a full doubleword. The dcache
takes priority over the icache on the shared memory bus.

**7. CDB.** One bus. Three potential drivers, with this priority (`pipeline.sv`):

1. MULT, when `mult_done` pulses,
2. LSQ load, when `load_done` pulses,
3. ALU and branch results, when both MULT and LSQ-load are quiet.

Stores never use the CDB at all. They report completion to the ROB through a
dedicated `store_done_valid` / `store_done_tag` sideband, which keeps the CDB
free for value-producing instructions. Branches always broadcast on the CDB,
but the PC redirect happens at commit, not at execute.

**8. ROB completion.** When the CDB fires, the ROB marks the targeted entry
ready, latches its value, and (for branches) latches `take_branch` and
`branch_target`. Stores complete through the parallel `store_done` sideband
instead of the CDB; the ROB just marks the matching entry ready without
touching its value. The next-state ordering inside `rob.sv` is **flush >
CDB / store_done > commit > dispatch**. That ordering is what makes
dispatch-and-commit-in-the-same-cycle correct.

**9. Commit.** The ROB head retires when it is busy and ready. Commit drives the
regfile write port and latches `HALTED_ON_WFI` or `ILLEGAL_INST` into
`error_status_reg`. The commit stage also runs the mispredict check: for each
committing branch it compares `predicted_taken` / `predicted_target` against
the entry's actual `take_branch` / `branch_target`, and on a mismatch raises a
one-cycle `mispredict_valid` / `mispredict_target` sideband. That sideband
flushes the RS, the LSQ, and any in-flight MULT, and redirects `PC_reg` to
the correct target. For JAL/JALR, the committed register value is overridden
to the entry's NPC — the return address — since the CDB-broadcast value
for those is the branch target. The RAT entry for the committing destination
is cleared *only* if it still points at this ROB slot, so a younger
instruction that already re-renamed the same architectural register does not
get its mapping clobbered. The ROB also exposes `commit_tag` and
`commit_is_store` so the LSQ can release its head store at exactly the right
cycle, and `commit_is_uncond_branch` / `commit_branch_PC` so the branch
predictor can update the BTB and BHT.

That is the entire dataflow. There is no separate physical register file: the
ROB entries themselves are the physical registers, which is why
`PHYS_REG_SZ = 32 + ROB_SZ` in `sys_defs.svh:29`.

---

## 5. File-by-file reference

All paths are relative to the project root.

### 5.1 `verilog/sys_defs.svh`

The single source of truth for global parameters and shared types.

- Superscalar width `N`, ROB and RS sizes, `PHYS_REG_SZ`.
- `LSQ_SZ` (= 8) and `DCACHE_LINES` (= 32, the spec cap at 256 bytes).
- Memory parameters: `CACHE_MODE`, `MEM_LATENCY_IN_CYCLES`, `NUM_MEM_TAGS`.
- Multiplier stage count (`MULT_STAGES`, default 4).
- The `INST` union typedef, `EXCEPTION_CODE`, `ALU_OPA_SELECT`, `ALU_OPB_SELECT`,
  `ALU_FUNC`, `MEM_SIZE`, `BUS_COMMAND`.
- The `IF_ID_PACKET` / `ID_EX_PACKET` / `EX_MEM_PACKET` / `MEM_WB_PACKET`
  structs from the in-order P3 pipeline. Our P6 design does not use them; they
  are kept for reference and to keep the legacy `verilog/p3/` tree compiling.

Branch-predictor sizing is set with `BTB_ENTRIES` (= 32) and `BHT_ENTRIES`
(= 64). The file also defines `BRANCH_PRED_PACKET`, the bundle that rides
from fetch into the ROB so commit can run the mispredict check.

### 5.2 `verilog/ISA.svh`

The RISC-V opcode and immediate-extraction macros (`RV32_LUI`, `RV32_BEQ`,
`RV32_signext_Iimm`, …). Read-only data; only the decoder and the few inline
sign-extends in `pipeline.sv` consume it.

### 5.3 `verilog/decoder.sv`

Combinational instruction decoder. Reused from P3 unchanged. Takes a 32-bit
`INST` plus a `valid` bit and produces:

- `opa_select` / `opb_select` (which mux input goes into operand A and B),
- `alu_func` (which ALU operation),
- `has_dest`, `rd_mem`, `wr_mem`, `cond_branch`, `uncond_branch`, `csr_op`,
  `halt`, `illegal`.

When `valid` is low the decoder behaves like a NOP. Unknown encodings set
`illegal = 1`.

### 5.4 `verilog/regfile.sv`

The architectural register file. Two read ports and one write port.

- `x0` always reads as zero. Writes to `x0` are ignored.
- Internal forwarding: if a read index matches the write index this cycle and
  `write_en` is high, the read returns `write_data` (the new value).

In our P6 design the regfile is read at fetch (speculatively, by index), and
written only at commit. Physical register values live in the ROB, not here.

### 5.5 `verilog/icache.sv`

A 32-line, 64-bit-wide, direct-mapped, **blocking** instruction cache. 256 bytes
total, which exactly hits the spec cap.

The interesting part is the distinction between **cache tags** and **memory
tags**. The cache tag is the upper bits of the address that index into the
line. The memory tag is a 4-bit transaction id that `mem.sv` hands out to keep
multiple in-flight memory requests straight (up to 15 of them, with tag 0
reserved as a sentinel).

On a miss the cache asserts `BUS_LOAD`, captures the response tag from
`Imem2proc_response`, and waits for the memory to come back with that same tag
on `Imem2proc_tag` along with the data on `Imem2proc_data`. While it is waiting
it does not issue another request. If the address changes mid-wait the cache
abandons the request entirely. See `icache.sv:86-129`.

The cache gives the dcache priority on the shared memory bus. From the
`pipeline.sv` side, when the dcache is driving the bus the icache's view of
`mem2proc_response` and `mem2proc_tag` is masked so the cache does not
mistake the dcache's response for its own. The mask uses the combinational
`*_drives` signals directly, which evaluate from registered state at
`always_ff` sample time and naturally give the previous cycle's drive — the
cycle the response was actually allocated for.

### 5.6 `verilog/dcache.sv`

A 32-line, 64-bit-wide, direct-mapped, write-back, write-allocate data cache.
256 bytes total, the same spec cap as the icache.

Each line holds a tag, a valid bit, a dirty bit, 64 bits of data, and an
8-bit byte-valid mask. The byte-valid mask is what lets sub-word stores
stay local: the cache marks only the bytes that have been written, and on
a writeback (always a full doubleword, since that is all `mem.sv` accepts
in cache mode) the unmodified bytes come from the previous line state.

Three request paths share one state machine:

- **Load.** On a hit, the cache returns the requested word/half/byte in the
  same cycle. On a miss, it issues a `BUS_LOAD`, captures the memory tag,
  waits for the line to come back, fills the entry, and then completes the
  load. If the entry being evicted is dirty, the writeback fires first, and
  the load waits behind it.
- **Store.** On a hit, the cache OR-merges the new bytes into the line and
  marks the entry dirty. On a miss, it does a write-allocate (load the line,
  then merge), with the same dirty-eviction handling.
- **Writeback.** Driven only by line evictions on a miss. Stores never go
  directly to main memory; they live in the cache until the line is kicked
  out.

The cache exposes `dcache_busy` so the LSQ can hold its head request, and
`dcache_done_load` / `dcache_done_store` pulses so the LSQ knows when to
advance.

### 5.7 `verilog/rob.sv`

The Reorder Buffer with the Register Alias Table embedded inside it. There is
no separate map-table module; the RAT lives here as `rat_busy[32]` and
`rat_tag[32]`.

Each ROB entry holds:

```
busy, ready, dest_reg, value, NPC,
halt, illegal, is_branch, is_store, take_branch, branch_target,
predicted_taken, predicted_target, is_uncond_branch, branch_PC
```

The last four fields feed the commit-time mispredict check and the predictor
update.

Four groups of ports:

- **Dispatch side.** Inputs: `dispatch_valid`, `dispatch_dest_reg`,
  `dispatch_NPC`, `dispatch_halt`, `dispatch_illegal`, `dispatch_is_branch`,
  `dispatch_is_store`, `dispatch_is_uncond_branch`, `dispatch_branch_PC`, and
  the prediction packet (`dispatch_predicted_taken`,
  `dispatch_predicted_target`). Outputs: `rob_full`, `dispatch_tag`
  (= current tail).
- **Complete side.** The CDB inputs: `cdb_valid`, `cdb_tag`, `cdb_value`,
  `cdb_take_branch`, `cdb_branch_target`. The ROB marks
  `entries[cdb_tag].ready = 1` and stores the value. Stores complete
  through a parallel sideband (`store_done_valid`, `store_done_tag`)
  instead of the CDB, so they do not have to fight value-producing
  instructions for the bus.
- **Commit side.** Outputs that drive the regfile write and the PC redirect:
  `commit_valid`, `commit_dest_reg`, `commit_value`, `commit_NPC`,
  `commit_halt`, `commit_illegal`, `commit_is_branch`, `commit_take_branch`,
  `commit_branch_target`, plus `commit_tag` and `commit_is_store` so the
  LSQ knows when its head store has been retired and can release it to the
  cache, and `commit_is_uncond_branch` / `commit_branch_PC` so the branch
  predictor can update its tables. Commit fires whenever the head entry is
  busy and ready. For JAL and JALR (the only branches with a non-zero
  destination), the committed value is overridden to the entry's NPC, since
  the CDB-broadcast value is the branch target and the link register needs
  the return address. That override is what fixed the milestone 2
  silent-zero JAL/JALR bug.
- **Mispredict side.** `mispredict_valid` / `mispredict_target` are a
  one-cycle sideband that commit raises whenever the committing branch's
  `predicted_taken` / `predicted_target` disagree with the actual
  `take_branch` / `branch_target`. The pipeline fans this out as `flush` on
  the RS, LSQ, and in-flight MULT, and redirects `PC_reg` to the correct
  target.

Two **RAT query ports** answer rename questions at dispatch time. They include
same-cycle CDB bypass: if the CDB is completing the same tag the RAT points at
right now, the query returns `ready=1` with `cdb_value`. That bypass is what
lets a producer and a consumer dispatched in the same window get away with one
fewer stall cycle.

The next-state combinational block has a strict priority: **flush, then CDB
complete, then commit, then dispatch.** Reordering those blocks will break
either same-cycle CDB completion or same-cycle dispatch-on-the-tail-after-commit.
The stale RAT clear at commit (`rob.sv:189-200`) only clears the RAT entry if
it still points at the head being committed; if a younger instruction has
already re-renamed the same architectural register, the older commit leaves
the RAT alone.

Flush is live. It is driven by the ROB's own `mispredict_valid` output,
fanned back in through `pipeline.sv`. On flush the ROB drops all
uncommitted entries behind the head, clears the RAT, and resets the
tail to the head (or head+1 if the head itself is mid-commit).

### 5.8 `verilog/rs.sv`

The Reservation Station. Holds entries waiting for operands, snoops the CDB to
wake them up, and issues the oldest ready entry to the functional units.

Each entry holds:

```
busy, op[7:0], dest_tag,
src1_ready, src1_tag, src1_value,
src2_ready, src2_tag, src2_value,
branch_funct3, branch_target, branch_NPC
```

The three branch fields replace the shared `branch_target_buf` /
`branch_funct3_buf` latches that milestone 2 and 3 used — each in-flight
branch now carries its own target, funct3, and link NPC. The CDB forwards
`branch_NPC` as the JAL/JALR link value (the ROB then overrides it with
the architectural NPC at commit), so same-cycle consumers on the RAT
query, RS wakeup, and LSQ wakeup paths see the correct return address.
Broadcasting 0 there produced the milestone 2 silent-zero bug.

The `op` field is the 8-bit packed dispatch opcode. From `pipeline.sv:138`:

```
op[7]   = rd_mem            (load)
op[6]   = uncond_branch     (JAL/JALR)
op[5]   = cond_branch       (B-type)
op[4:0] = alu_func
```

The pipeline reads those bits back in `pipeline.sv:140-147` to decide
`issue_is_mult`, `issue_is_branch`, `issue_is_load`.

Three combinational blocks dominate `rs.sv`:

1. **Free-slot search.** A simple priority for-loop finds the lowest-index free
   entry; that index becomes the dispatch slot.
2. **Effective ready computation.** For every entry, its `src*_ready` is OR'd
   with `(cdb_valid && cdb_tag == src*_tag)` to fold in the same-cycle CDB
   wakeup. That is what lets an instruction be issued in the same cycle it
   receives its last operand on the CDB.
3. **Issue selection.** Another priority for-loop picks the oldest entry with
   both effective-ready bits set. The selected entry's opcode, dest tag, and
   operand values drive the issue ports. The forwarded value uses the CDB
   bypass mux directly so the value is correct even if the CDB is supplying it
   this cycle.

The next-state block applies wakeup, then removes the issued entry (if
`issue_fire`), then inserts the dispatched entry (if there is room).

The current implementation uses hand-rolled priority loops rather than
`psel_gen.sv`. That is fine at `RS_SZ=8`, and trivial to swap out if we go
superscalar.

Note that since milestone 3, the RS no longer holds memory ops at all.
Loads and stores bypass the RS at dispatch and go straight into the LSQ;
the RS only sees ALU, MULT, and branch ops.

### 5.9 `verilog/lsq.sv`

The Load-Store Queue. A circular FIFO of 8 entries (`LSQ_SZ`), in program
order, that owns every load and store from dispatch through retirement.

Each entry holds:

```
busy, is_store, mem_size, signed_load,
addr_ready, addr_value, base_tag, base_value, base_ready, imm,
data_ready, data_tag, data_value, data_committed,
dest_tag, in_flight
```

Three things happen in the entry's lifetime:

1. **Allocate at dispatch.** The pipeline drives `dispatch_valid` along with
   the ROB tag, the base register's RAT lookup, the immediate, and (for
   stores) the data register's RAT lookup. The LSQ writes a new tail entry
   with whatever operands were already ready and the rename tags for
   anything that was not.
2. **Wake up via the CDB.** Each entry snoops `cdb_valid` / `cdb_tag` /
   `cdb_value`. When the CDB tag matches a `base_tag` or `data_tag`, the
   matching field flips ready and stores the value. Same-cycle wakeup is
   folded in the same way the RS handles it.
3. **Drain at the head.** The head entry is the only one that can drive the
   D-cache. For loads, the LSQ waits until the address is ready and there
   is no unresolved store ahead of it (which is always the case for the
   head, by definition), then issues the cache request and reports back on
   `load_done_valid` / `load_done_tag` / `load_done_value` when the cache
   responds. For stores, the LSQ has to wait until the ROB commits the
   matching entry — that is what `commit_tag` and `commit_is_store` from
   the ROB are for. Only then is the store released to the cache, and the
   `store_done` sideband fires when it lands.

The head-only policy and the lack of store-to-load forwarding are
deliberate. There is no forwarding correctness work to chase, and
architectural memory cannot be written on a mis-speculated path. The
trade-off is that a load behind a store pays the full cache miss latency
at least once per line.

The `flush` input is live and driven by the ROB's `mispredict_valid`. On
flush the LSQ walks from the head and keeps only `is_store && committed`
entries — a committed store mid-handshake with the D-cache cannot be
dropped, the architecture has already released it. Everything younger
goes away, and the tail is reset to the first non-busy slot. A one-bit
`stale_response_pending` counter swallows the D-cache response belonging
to a flushed in-flight load so it cannot be mistaken for the next LSQ
head's data. The `proc_busy` signal from the D-cache is wired back in so
the LSQ also swallows the response from a load the cache accepted on
the same cycle as the flush — without it `sort_search` looped forever
on an orphaned fetch.

### 5.10 `verilog/mult.sv` and `verilog/mult_stage.sv`

The pipelined multiplier from P2. `mult.sv` is just a wiring shim that chains
`MULT_STAGES` instances of `mult_stage`. Each stage processes
`SHIFT = 64 / MULT_STAGES` bits of the multiplier per clock, accumulating into
a running 64-bit sum and shifting the operands. Latency is `MULT_STAGES` cycles,
throughput is one per cycle once the pipeline is primed.

The pipeline drives this with `start = issue_accept && issue_is_mult`, and
captures the result on `done`. `MULT_STAGES` is set in `sys_defs.svh:42`. It
should be retuned against synthesis slack later; right now it sits at the
default of 4.

The pipeline pre-extends operands before sending them in: signed-extended for
`MUL` / `MULH`, zero-extended for `MULHU`, mixed for `MULHSU`. After the
multiply finishes, the pipeline picks the lower or upper 32 bits of the
product depending on the variant. See `pipeline.sv:407-452` and
`pipeline.sv:535-540`.

### 5.11 `verilog/psel_gen.sv`

A parameterized priority selector. Takes a `WIDTH`-bit request vector and
returns up to `REQS` simultaneous one-hot grants, using a wired-AND
implementation that synthesizes faster than a hand-rolled for-loop. The
1-wide design does not use it yet, but a superscalar build will need it
to pick multiple oldest-ready entries from the RS in one cycle.

### 5.12 `verilog/pipeline.sv`

The top-level. Wires all of the above into the dataflow described in
section 4. About 870 lines now, most of it port plumbing, the
operand-resolution muxes, the inline ALU, the inline branch resolver, the
multiplier handshake, the LSQ instantiation and store-data resolver, the
dcache instantiation, the dcache/icache bus arbitration, the CDB priority
arbiter, the branch-predictor instantiation and update drive, the
mispredict flush fan-out, and the PC update logic. There is no other
top-level glue file; everything is here.

Notable signals to grep for when navigating it:

- `stall` — global front-end stall. Set by icache miss, RS full, or ROB full.
  It is no longer gated by a pending branch.
- `mispredict_valid`, `mispredict_target` — the one-cycle sideband from the
  ROB that triggers an RS/LSQ/MULT flush and a PC redirect.
- `branch_pending`, `branch_target_buf`, `branch_funct3_buf` — all tied to
  zero, but the wires are still present. They are load-bearing for the
  `+define+SERIALIZE_BRANCHES` diagnostic ifdef that reinstates
  milestone-3 front-end serialization (the base-design sign-off baseline).
  Do not remove until a different reference replaces them.
- `dispatch_fire` — handshake bit that drives both ROB and RS dispatch.
- `dispatch_tag` — the renamed destination tag, equal to the ROB tail.
- `cdb_valid`, `cdb_tag`, `cdb_value`, `cdb_take_branch`, `cdb_branch_target` —
  the broadcast bus.
- `store_done_valid`, `store_done_tag` — the store completion sideband from
  the LSQ to the ROB. Stores never use the CDB.
- `issue_accept`, `mult_busy`, `mult_done`, `load_done` — the issue
  arbitration that prevents multiple FUs from colliding on the CDB.
- `error_status_reg` — latched halt/illegal exception code that the testbench
  watches to know when to stop.

### 5.13 `verilog/branch_predictor.sv`

The branch predictor. A 32-entry direct-mapped BTB (indexed by `PC[6:2]`
with a `PC[31:7]` tag) paired with a 64-entry bimodal direction table of
2-bit saturating counters. Sizes are `BTB_ENTRIES` and `BHT_ENTRIES` in
`sys_defs.svh`.

Two ports:

- **Predict (combinational).** Given a fetch PC, returns
  `{pred_valid, pred_taken, pred_target, pred_is_uncond}`. `pred_valid`
  requires a BTB tag hit; `pred_taken` combines the BTB's `is_uncond` bit
  with the BHT's top counter bit (uncond branches always predict taken
  once seen); `pred_target` is the BTB's stored target.
- **Update (registered).** Driven once per committing branch out of the
  ROB. Writes the BTB entry (tag, target, is_uncond) and updates the BHT
  counter (+1 if taken, −1 if not, saturating at `11` / `00`). On reset
  counters start at weakly-not-taken `01`.

Bring-up details, the four integration bugs removing `branch_pending`
exposed, and the per-program accuracy numbers are in
[`branch-predictor-report.md`](base-design/branch-predictor-report.md).

### 5.14 `verilog/p3/`

Legacy P3 in-order pipeline (`pipeline.sv`, `stage_if.sv`, `stage_id.sv`,
`stage_ex.sv`, `stage_mem.sv`, plus its own `regfile.sv` and `ISA.svh`). Not
compiled into the P4 build. It is kept around as a reference, and because the
decoder and a few datapath details in our P4 work were lifted from here.

---

## 6. Test infrastructure

All testbenches live in `test/`. The build system expects each tested module to
have a matching testbench file: `verilog/foo.sv` pairs with `test/foo_test.sv`,
declared in the Makefile as
`TESTED_MODULES = mult rob rs dcache lsq branch_predictor`.

A testbench is considered passing only if it `$display`s the literal string
`@@@ Passed`. The `.pass` Makefile targets are just `grep`. Failures should
print `@@@ Incorrect`.

### 6.1 `test/mem.sv`

The simulated main memory. 64 KB, 64-bit lines, 100 ns latency. Hands out 4-bit
transaction tags (1–15) on requests, returns data with the matching tag after
the latency. Used by both `pipeline_test.sv` and `vtuber_test.sv`. This is a
test-side model, not a synthesizable module.

### 6.2 `test/pipeline_test.sv`

The full-processor testbench. Loads a `.mem` file into `mem.sv`, drives the
clock, watches `pipeline_completed_insts` and `pipeline_error_status`, and
dumps writebacks (`<prog>.wb`) and a per-cycle pipeline trace (`<prog>.ppln`)
to `output/`. Correctness is verified by comparing the `.wb` file against a
golden file.

### 6.3 `test/mult_test.sv`

Unit testbench for the pipelined multiplier. Drives random and edge-case
operand pairs, waits for `done`, checks the product against a software
multiply.

### 6.4 `test/rob_test.sv`

Unit testbench for the ROB. Ten test cases:

1. Basic dispatch → CDB complete → commit.
2. In-order commit despite out-of-order completion.
3. RAT query returns pending + tag for a pending write.
4. Same-cycle CDB bypass in the RAT query.
5. RAT clears on commit when still the latest writer.
6. RAT stale-clear protection when a younger writer has already renamed.
7. The `x0` guard (RAT never tracks `x0`).
8. Flush clears everything.
9. Full detection.
10. Wraparound.

The testbench was the main Week 4 deliverable. In Week 5 it was extended to
drive the new `dispatch_is_store` / `store_done` / `commit_tag` ports, and
all of the original scenarios still pass. Both `make rob.pass` and
`make rob.syn.pass` are green.

### 6.5 `test/rs_test.sv`

Unit testbench for the RS. Exercises dispatch, free-slot allocation, CDB
wakeup, oldest-ready issue selection, and the same-cycle CDB forwarding path.

### 6.6 `test/dcache_test.sv`

Unit testbench for the D-cache, written in Week 5. Covers load miss, load
hit, store hit, sub-word stores (byte and halfword), and dirty eviction
(forcing a writeback by hammering one cache index until a dirty line gets
kicked out). `make dcache.pass` and `make dcache.syn.pass` both pass; the
synth report has about 587 ps of slack.

### 6.7 `test/lsq_test.sv`

Unit testbench for the LSQ, also from Week 5. Drives operand wakeup via the
CDB, the store-ready sideband, FIFO ordering, and commit-time release of
the head store. `make lsq.pass` and `make lsq.syn.pass` both pass. The
synth slack on the LSQ is the tight one — about 0.4 ps — so it would be
the first thing to gate a clock-period reduction.

### 6.8 `test/branch_predictor_test.sv`

Unit testbench for the branch predictor. Nine scenarios: cold-miss
(empty BTB returns `pred_valid=0`), first-time learning (an update
registers next cycle), direction-counter learning and saturation in
both directions, the strongly-taken → weakly-taken flip on one not-taken
observation, tag aliasing (same index, different tag → miss), and
write-then-read ordering. Unconditional branches are exercised with
`update_is_uncond=1` so the predictor can confirm the "always taken once
seen" path. Both `make branch_predictor.pass` and
`make branch_predictor.syn.pass` are green, with 100% line and branch
coverage on the DUT.

### 6.9 `test/vtuber_test.sv`, `test/vtuber.cpp`, `test/riscv_inst.h`

The ncurses visual debugger inherited from P3. `make <prog>.vis` runs it for a
given program. Useful for staring at the pipeline state at a specific cycle.

### 6.10 `test/pipeline_print.c`

DPI-C helpers for pretty-printing pipeline state from `pipeline_test.sv`.
Mostly commented out by default; uncomment and recompile when you need a
verbose dump.

---

## 7. How to run things

You need the synthesis and simulation toolchain on `PATH` first:

```
module load vcs verdi synopsys-synth
```

`setup-paths.sh` adds the RISC-V GCC toolchain and `elf2hex` to `PATH`. The
Makefile already hardcodes `RISCV32_HOME` and `ELF2HEX_HOME`, so you only need
to source `setup-paths.sh` if you are invoking the cross-compiler by hand.

Common targets:

```
make no_hazard.out          # run the no_hazard.s assembly program on simv
make mult_no_lsq.out        # run mult_no_lsq.s — currently hangs, see status
make <prog>.syn.out         # run <prog> on the synthesized pipeline
make <prog>.verdi           # open <prog> in Verdi
make <prog>.vis             # open <prog> in the ncurses visual debugger

make rob.pass               # run the ROB unit test
make rs.pass                # run the RS unit test
make mult.pass              # run the multiplier unit test
make dcache.pass            # run the D-cache unit test
make lsq.pass               # run the LSQ unit test
make branch_predictor.pass  # run the branch-predictor unit test
make rob.syn.pass           # same, but on the synthesized module
make rob.coverage           # generate the coverage hierarchy report

make synth/pipeline.vg      # synthesize the full processor
make synth/rob.vg           # synthesize a single module
make slack                  # grep slack out of all synth/*.rep files
```

The global clock period is set in the Makefile via `export CLOCK_PERIOD =
1000.0` (picoseconds). It is passed into VCS as a `+define` and read by the
synthesis TCL script. Change it there, not in any individual testbench.

`make clean` clears executables and per-run output. `make nuke` also wipes
synthesis artifacts and `programs/*.mem` — avoid it casually because
re-synthesizing the full pipeline is slow.

---

## 8. Where we are right now

**Working:**

- `make simv` builds with zero errors and zero warnings.
- `make no_hazard.out` runs end-to-end. 14 instructions, 731 cycles, clean
  halt on `HALTED_ON_WFI`, all writebacks correct.
- `make rob.pass`, `make rs.pass`, `make mult.pass`, `make dcache.pass`, and
  `make lsq.pass` all pass in simulation. The ROB, RS, dcache, and LSQ also
  pass on the synthesized netlist (`*.syn.pass`).
- All 34 test programs in `programs/` reach `HALTED_ON_WFI` end-to-end.
  Every `.wb` stream is byte-identical to the same commit rebuilt with
  `+define+SERIALIZE_BRANCHES`, so speculation introduces zero
  architectural divergence. The milestone 3 per-program numbers are in
  [`milestone3-results.md`](weekly-reports/milestone3-results.md); the milestone 4
  sign-off numbers, including the branch-heavy speedups, are in
  [`base-design-verification.md`](base-design/base-design-verification.md).
- The full memory subsystem works: byte/half/word RV32IM loads and stores
  through the LSQ and write-back D-cache, with sub-word stores absorbed as
  byte-enable masks. Writebacks only fire on dirty evictions.
- JAL/JALR write the correct return address to the destination register
  (the milestone 2 silent-zero bug, fixed via the ROB commit-value override).
- The core P6 dataflow — rename, dispatch, issue, execute, MULT, CDB
  broadcast, in-order commit, taken-branch redirect at commit, LSQ-managed
  memory ops — runs cleanly through hundreds of thousands of committed
  instructions on the longer C programs (`insertionsort` at 842k cycles,
  `priority_queue` at 79k cycles).

**Recent addition — BTB + bimodal predictor (milestone 4, regression green):**

- `verilog/branch_predictor.sv` now exists: direct-mapped 32-entry BTB
  plus a 64-entry bimodal (2-bit saturating) direction table. Predict
  port is combinational at fetch; update port is registered, one per
  committing branch. Unit test covers cold miss, learning, saturation,
  flip, tag alias, and write-then-read; all nine scenarios pass in
  simulation and on the synthesized netlist (100% line/branch
  coverage on the DUT).
- `branch_pending` is now tied to zero, so the front-end no longer
  serializes on an in-flight branch and multiple branches can be
  in flight. The prediction packet rides with each branch into its
  ROB entry; at commit the ROB compares predicted vs. actual and
  asserts `mispredict_valid` on a miss, which drives `flush` on the
  ROB, RS, and LSQ and redirects `PC_reg` to the correct target.
- The old shared `branch_target_buf` / `branch_funct3_buf` latches
  are gone. Each RS entry carries its own `branch_target`,
  `branch_funct3`, and `branch_NPC`. The CDB broadcast value for
  JAL/JALR is the return address (NPC) rather than 0, which is
  what any downstream CDB-bypass consumer needs.
- The LSQ flush preserves committed stores at the head and swallows
  the D-cache response from a flushed in-flight load (saturating
  counter, so back-to-back flushes never drop a real response). It
  also swallows the response from a load that the D-cache accepted
  on the same cycle as the flush. The last arm required wiring the
  D-cache's `proc_busy` into the LSQ; without it `sort_search`
  looped forever on an orphaned fetch whose data was latched by
  the next LSQ head.
- All 33 programs in `programs/` halt cleanly at `HALTED_ON_WFI`.
  Branch-heavy benchmarks speed up: `fib_rec` −10.3%,
  `insertionsort` −6.5%, `sort_search` −5.9% vs the serialized
  baseline, `quicksort` −4.4%. Nothing that passed at milestone 3
  regressed.
- For the four integration bugs that surfaced during bring-up and
  the full cycle-count table, see
  [`branch-predictor-report.md`](base-design/branch-predictor-report.md).

**Base-design sign-off (milestone 4):**

- The base design is signed off. Evidence is in
  [`doc/base-design/base-design-verification.md`](base-design/base-design-verification.md):
  per-module sim+synth pass matrix with coverage, a 34-program
  regression table, full-pipeline synth slack, and the list of
  intentionally deferred proposal items. Headline: on all 33 programs
  the `.wb` stream on `milestone4` is byte-identical to the same
  commit rebuilt with `+define+SERIALIZE_BRANCHES` — the diagnostic
  ifdef that reinstates milestone-3 front-end serialization — so the
  branch predictor does not introduce any architectural divergence.
- Full-pipeline synthesis (`synth/pipeline.vg`) is built and
  reported. Worst slack is **−302.55 ps** at the 1000 ps clock on the
  `rs_0/entries_reg[3][src*_ready] → mult_0/mstage[0]/product_sum_reg[*]`
  combinational operand path (originally recorded as −309.07 ps on a
  stale Apr 17 netlist; clean re-synth on 2026-05-01 lands at
  −302.55 ps, same cone class). Three endpoints violate, all on the
  same RS→MULT stage-0 class; everything else meets with ≥+382 ps
  slack. Retune (either a pipeline flop between RS issue and MULT
  stage 0, or a larger `CLOCK_PERIOD`) is a deliberate follow-up,
  not a silent period bump.

**Advanced-features merge wave — week 8 (post-merge verified):**

All six advanced-feature branches that were running in parallel are
now on `milestone3`:

- `feat-stlf-cz2931` (store-to-load forwarding in the LSQ).
- `feat-ras-cz2931` (16-entry Return Address Stack hooked into JALR
  prediction).
- `gshare` (full-width-GHR XOR direction predictor, replaces the
  bimodal table; the BTB and RAS sit on top unchanged).
- `2_way_superscalar` (dual-issue dispatch and commit, the second
  "difficult" feature alongside ETB).
- `feat-dcache-prefetch` (next-line stream-buffer prefetcher, also
  used by the icache).
- `assoc_cache` (2-way set-associative D-cache).

Verification on a worktree branch (`verify-merged-features`) anchored
on `milestone3` head `dc484b0`:

- 33 / 33 programs halt at WFI in both RTL sim and synthesized
  gate-level sim. Every `.syn.wb` is byte-identical to its `.wb`,
  with cycle counts at `RTL + 1` (the canonical reset offset). The
  netlist is functionally bit-equivalent to the RTL.
- Per-module synth all met timing at 1000 ps. Tightest: `lsq` +0.05
  ps and `mult` +0.23 ps. Headroom on those two is small enough
  that any future logic on those paths will violate.
- Full-pipeline synth slack post-merge (= `dbcd4f6` + `51b7f1c`) is
  **−797.58 ps** on `lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]`,
  with companion `lsq_0/head_reg[2] → lsq_0/entries_reg[3][addr][31]`
  at −797.55 ps. Two endpoints violate; everything else meets with
  large margin. Re-baseline of `dbcd4f6` (without `51b7f1c`) gave
  ≈ −1600 ps, so `51b7f1c` recovered ~800 ps standalone. The
  base-design baseline number (`−309.07 ps`) was re-verified at
  `−302.55 ps` on a clean rebuild 2026-05-01 (within DC re-run noise;
  same RS→MULT-stage-0 cone class). The post-merge `−504.66 ps` and
  `−244.54 ps` numbers from earlier write-ups were retracted as stale
  build artefacts. The deferral in `base-design-verification.md` §4
  now applies to the new `LSQ broadcast → ALU adder → ROB/LSQ`
  critical path.
- Cumulative CPI improvement against the April-26 in-tree snapshot
  ranges from a few percent on small programs to −49.6 % on
  `alexnet`. Branchy and memory-heavy programs see the largest
  gains; nothing regresses.
- Two test-infrastructure regressions surfaced (not netlist
  correctness regressions): `branch_predictor.pass` has four stale
  BHT-counter assertions that pre-date the gshare merge, and four
  of the `*.syn.pass` builds fail because the testbenches still
  declare 2-way ports as unpacked arrays while the synthesized
  netlist flattens them, plus the icache TB pulls in `stream_buffer`
  which the icache synth target doesn't include. Both are
  TB-side fixes.

Per-feature reports for the five undocumented features (everything
except ETB, which has its own write-up) are still owed. The
cumulative delta is measured; the per-feature attribution is not.

Full numbers, comparison tables, the verbatim violating endpoints,
and the recommendation list are in
[`advanced-features-merge-report.md`](advanced-features/advanced-features-merge-report.md).

**Known broken or missing:**

- `synth/pipeline.vg` timing at the 1000 ps clock is still **not closed**
  after the verify-merged-features pass plus the `51b7f1c` merge.
  Worst slack is now **−797.58 ps** (clean re-synth of post-merge
  HEAD; companion violator at −797.55 ps). The MULT stage-0 cone
  documented earlier is closed by `51b7f1c`; the residual lives in
  the LSQ-broadcast → ALU-adder → ROB/LSQ cone. The earlier
  `−244.54 / −504.66 ps` numbers used stale build artefacts and have
  been retracted. The netlist was functionally correct on the
  pre-`51b7f1c` baseline; re-verification across the merge is expected
  to hold (the change is a flop insertion, no value change) but
  `simulate_all_syn` was not re-run.
- Five of the six week-8 advanced features lack per-feature reports.
  The cumulative speed-up is documented; the per-feature isolation
  is not.

**Recently fixed (verify-merged-features, 2026-04-30):**

- `branch_predictor.pass` and `branch_predictor.syn.pass` now pass.
  Tests 2 / 5 / 7 in `test/branch_predictor_test.sv` were rewritten
  around a TB-side gshare model.
- `rob.syn.pass`, `rs.syn.pass`, `lsq.syn.pass`, `icache.syn.pass` all
  build and pass. The Makefile picks up the existing `*_svsim.sv`
  wrappers and `verilog/stream_buffer.sv` as per-target prerequisites
  of `.syn.simv`; the testbenches instantiate the wrapper under
  `+define+SYNTH`.
- 7/7 RTL module tests, 7/7 synth module tests, and 33/33 program
  runs (RTL and synth) all green. Every `.wb` matches its `.syn.wb`.

**Recent addition — early tag broadcast (advanced feature, correctness-only):**

- `verilog/mult.sv` exposes `early_done` one cycle before `done`;
  `verilog/pipeline.sv` drives a `{early_cdb_valid, early_cdb_tag}`
  sideband gated by `!mult_flushed && !mispredict_valid`. The RS and
  LSQ snoop it to flip the registered `src*_ready` / `base_ready` /
  `data_ready` bit one cycle sooner. `src*_val_present` companion bits
  keep the value-mux honest: ETB only flips ready, the real CDB lands
  the value the next cycle.
- The issue selector still reads the registered `src*_ready` only —
  the `rs-issue-loop-fix` rule is intact, and there is a dedicated
  unit-test scenario
  (`test_early_tag_does_not_bypass_selector_combinationally`) that
  catches any future combinational ETB->selector path regression.
- `+define+DISABLE_EARLY_TAG` at the Makefile level ties the valid
  bit to 0 for A/B. 33/33 programs halt at WFI with ETB on and with
  the escape hatch; every `.wb` file is byte-identical to the
  `SERIALIZE_BRANCHES` sign-off baseline in both modes.
- Per-program cycle counts are **identical** to pre-ETB on all 33
  programs. The early wakeup is real (unit tests verify `early_done`
  leads `done` by exactly one cycle and that the RS / LSQ ready bits
  flip one cycle sooner), but the consumer still issues on cycle N+2
  because `issue_accept` for non-MULT ops is gated on
  `!mult_done_valid`. CDB contention in the 1-wide pipeline swallows
  the save; it is unblocked by the second CDB that 2-way superscalar
  adds.
- Full writeup including the cycle-accurate timing diagram, design
  alternatives, and known limitations is in
  [`early-tag-broadcast-report.md`](advanced-features/early-tag-broadcast-report.md).

---

## 9. What is still ahead

The base design is signed off and the advanced-features merge wave
has landed and verified. What's left is closing three concrete gaps.

The first is **timing closure on the merged stack**. Full-pipeline
synth has **−797.58 ps** worst slack at the 1000 ps clock on the
post-`51b7f1c` `LSQ broadcast → RS operand mux → ALU 32-bit adder →
{ROB take_branch, LSQ addr}` cone. The MULT stage-0 cone the original
plan targeted is closed (`51b7f1c` registered MULT operands and the
start signal; clean re-synth shows ≈ −1600 ps → −797.58 ps, ~800 ps
recovered standalone). The next mechanical step is registering
`load_complete_value` / `load_complete_tag` between the LSQ broadcast
arbiter and the CDB — that adds one cycle of latency on every
completing load. Alternative is rebalancing the broadcast → adder
path or raising `CLOCK_PERIOD`, which the project doesn't want to do
silently. Neither is a sign-off blocker, but one of them needs to
land before the final report.

The second is the **per-feature documentation gap**. Of the six
advanced features merged in week 8, only ETB has a write-up
(`early-tag-broadcast-report.md`). The other five — 2-way superscalar,
gshare, RAS, STLF, dcache prefetch + stream buffer, and 2-way
associative dcache — are functionally integrated and demonstrably
working but undocumented at the per-feature level. The cumulative
delta is measured (§3.8 and `advanced-features-merge-report.md`);
the per-feature attribution requires either bisecting the merges or
adding `+define` ifdefs to disable each feature individually. Each
report should mirror the structure of `early-tag-broadcast-report.md`:
design intent, RTL touch points, parameters, unit-test coverage,
per-program cycle and accuracy delta vs the pre-feature baseline,
and an honest statement of measured speed-up.

The third is the **unit-test infrastructure refresh**.
`branch_predictor.pass` has four stale BHT-counter scenarios that
pre-date the gshare merge; they need to either reset the GHR between
updates or assert against `bht_idx(pc, ghr)` rather than raw PC.
`rob.syn.pass`, `rs.syn.pass`, and `lsq.syn.pass` need their
testbench port connections rewritten to match the netlist's flattened
2-way buses. `icache.syn.pass` needs `stream_buffer.sv` added to the
icache synth `SOURCES` (or a TB split that doesn't drag the prefetcher
into the netlist build). Until these go green, the project's syn-test
matrix shows 2 / 7 passing instead of the 6 / 7 the RTL side has.

Beyond those three, the proposal targets 16–18 advanced-feature
points overall with at least one "difficult" feature; both
"difficult" features (ETB and 2-way superscalar) are now landed,
and the simpler features (gshare, RAS, STLF, prefetch, set-associative
cache) cover the rest of the point budget. Whether the cumulative
score clears the bar is for the per-feature reports to argue once
they exist.

---

## 10. Where to look next

Reading order for a first-time walkthrough: `verilog/pipeline.sv` for wire
declarations and stall logic, then the ROB/RS/LSQ instantiation block in
the same file. Read `verilog/rob.sv` next — the next-state priority block
(flush > CDB/store_done > commit > dispatch) is where most of the rename
subtlety lives, alongside the JAL/JALR commit-value override. `verilog/rs.sv`
covers ALU/MULT/branch wakeup and issue; `verilog/lsq.sv` covers the
memory-side equivalent, including the commit-time store release.
`verilog/dcache.sv` has the byte-enable mask trick that keeps sub-word
stores from round-tripping to memory.

For context, `milestone3-report.md` covers memory bring-up,
`rs-issue-loop-fix.md` covers the combinational loop that killed
about fifteen tight-loop programs, `branch-predictor-report.md`
covers the predictor bring-up and the four integration bugs that
surfaced when `branch_pending` came off, `base-design-verification.md`
has the pre-merge sign-off numbers, `early-tag-broadcast-report.md`
has the ETB write-up, and `advanced-features-merge-report.md` has
the post-merge verification — pass matrix, slack endpoints, the
per-program comparison table, and the action list for what's owed.
`verilog/branch_predictor.sv` itself is small enough to read
end-to-end in one sitting. `week3-merge-report.md` and
`week4-mult_no_lsq-findings.md` are earlier history; skip them unless
you're bisecting an old regression.
