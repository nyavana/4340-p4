# Early tag broadcast: design, integration, and regression

Status as of 2026-04-19: ETB is landed on branch `early-tag-broadcast`,
correctness-only. 34/34 programs halt at `HALTED_ON_WFI`. Every `.wb`
file is byte-identical to the `+define+SERIALIZE_BRANCHES` sign-off
baseline whether the pipeline is built with ETB on (default) or with
`+define+DISABLE_EARLY_TAG`. Per-program cycle counts are unchanged
from pre-ETB on all 34 programs. The mechanism works but CDB
contention in the 1-wide pipeline swallows the one-cycle save.

This document is the companion report for the change. It lives next to
[`branch-predictor-report.md`](branch-predictor-report.md) and
[`rs-issue-loop-fix.md`](rs-issue-loop-fix.md) and is cross-linked from
[`project-overview.md`](project-overview.md) §3.7.

---

## 1. Motivation

The 1-wide P6 pipeline already pays this schedule on every MULT to
ALU consumer chain:

| cycle | event                                                                                            |
|-------|--------------------------------------------------------------------------------------------------|
| T     | `mult_done=1`; `mult_done_valid=1` drives the CDB with the MULT's tag and value.                 |
| T+1   | `entries[i].src*_ready=1` registered; the RS selector picks the dependent; it issues at T+1.     |

The 1-cycle gap between T and T+1 is the cost of the
`rs-issue-loop-fix` rule: the selector reads the **registered**
`src*_ready`, not the combinational bypass, so it can never see the
CDB's effect on the same cycle the CDB fires. Without that rule the
selector closes a combinational loop through the CDB arbiter and hangs
programs with tight inner loops (~15 programs in milestone 3, see
[`rs-issue-loop-fix.md`](rs-issue-loop-fix.md)). The rule is
load-bearing and stays.

Early tag broadcast closes that gap without touching the selector.
The multiplier publishes the tag one cycle before the value lands on
the CDB, the RS (and LSQ) flip the registered ready bit on that early
cycle, and the dependent is eligible to issue at T rather than T+1.

The value still rides the real CDB at T; the early tag is a tag-only
sideband. To bridge the "ready, value-not-yet-latched" window, the
RS and LSQ entries grow a `src*_val_present` bit and the issue
value-mux forwards from `cdb_value` in that window.

---

## 2. Mechanism

### 2.1 Producer: `mult.sv`

`mult.sv` pipelines the multiply across `MULT_STAGES` instances of
`mult_stage` chained through `internal_dones`. The second-to-last
stage's `done` flop (`internal_dones[MULT_STAGES-2]`) fires exactly
one cycle before the final `done`.

```systemverilog
// verilog/mult.sv
output logic early_done;
...
assign early_done = internal_dones[`MULT_STAGES-2];
```

It is an already-registered flop, so driving it combinationally into
the pipeline is safe. A `$fatal` guards `MULT_STAGES < 2` so the tap
can never collapse to a zero-width vector.

### 2.2 Producer gating: `pipeline.sv`

```systemverilog
// verilog/pipeline.sv
logic             early_cdb_valid;
logic [TAG_W-1:0] early_cdb_tag;

`ifndef DISABLE_EARLY_TAG
    assign early_cdb_valid = mult_early_done && !mult_flushed && !mispredict_valid;
`else
    assign early_cdb_valid = 1'b0;
`endif
assign early_cdb_tag = mult_dest_tag_reg;
```

Two gates: `mult_flushed` (an older mispredict poisoned this multiply
before it finished) and `mispredict_valid` (a mispredict on this cycle
is about to wipe every downstream consumer anyway). Both are
redundant with the RS/LSQ `flush` input but cheap to do at the
producer side, and they short-circuit any subtle race where a flushed
multiply would otherwise wake a re-dispatched consumer.

### 2.3 Consumer: `rs.sv`

Every RS entry grows a second per-source bit: `src*_val_present`. The
invariants are:

- **Dispatch.** `src*_ready` and `src*_val_present` are both set to
  `dispatch_src*_ready`. If the operand is ready at dispatch, the
  value was either read from the regfile or produced by the RAT query
  CDB bypass, and in both cases it is in `dispatch_src*_value` and can
  be trusted.
- **ETB wakeup.** Flips `src*_ready` to 1; leaves `src*_val_present` at 0.
- **CDB wakeup.** Flips both to 1 and latches `cdb_value`.
  Gated on `!src*_val_present` rather than `!src*_ready`, so the CDB
  can still land the value on an entry that was already woken by the
  early tag the cycle before.
- **Issue selector.** Reads only the registered `src*_ready`. ETB
  never feeds `issue_found` combinationally.
- **Issue value mux.** Forwards from `cdb_value` when either
  `cdb_valid && !src*_ready && src*_tag == cdb_tag` (standard
  same-cycle CDB bypass, guarded by `!src*_ready` so a stale tag match
  on a fully-resolved entry cannot overwrite a latched value) *or*
  `!src*_val_present` (the ETB case, where the entry is ready but the
  value is still on the CDB this cycle).

The two-arm mux is deliberately asymmetric: the `!src*_ready` guard is
kept on the tag-match arm because ROB tags are recycled, so a later
broadcast of a recycled tag could otherwise forward a value from a
different instruction. The ETB window is covered entirely by the
`!src*_val_present` arm.

### 2.4 Consumer: `lsq.sv`

The LSQ mirrors the RS change. Each entry has `base_val_present` and
`data_val_present`. The ETB wakeup block and the CDB wakeup block
follow the same rules as the RS.

The LSQ AGU reads `next_entries[i].base_val_present` (combinationally
folded in after the CDB wakeup of the same cycle), so an entry whose
base was CDB-woken this cycle gets `addr_valid=1` set on the same
cycle. That timing is unchanged from the pre-ETB path. An ETB-only
wakeup cycle is intentionally not permitted to fire the AGU; the
address is not computable without the value, and the 1-cycle save the
AGU would otherwise claim is outside the scope of this feature (the
design doc §3 marks "drop the `!ready` guard on the AGU" as brittle
and defers it).

### 2.5 Flush semantics

The RS and LSQ `flush` input is wired to `mispredict_valid`. On
flush, both modules clear all non-committed entries (LSQ preserves the
committed head store mid-handshake, as before). The new `*_val_present`
bits are zeroed by the existing `'0` assignment, no extra flush
bookkeeping needed. Together with the producer-side `!mispredict_valid`
gate, any in-flight ETB pulse is dropped on the flush cycle.

---

## 3. Timing diagram

Abbreviations: `R` = `src*_ready`, `V` = `src*_val_present`, `CDB` =
`cdb_valid && cdb_tag == src*_tag`.

### 3.1 Baseline (no ETB): CDB-only path

```
           cycle N         cycle N+1       cycle N+2
MULT       done=1          (mult_busy=0)
CDB        valid=1         --              --
RS entry   R=0, V=0        R=1, V=1        R=1, V=1
selector   skip (R=0)      skip (R=0 ←     pick (R=1)
                           was combinational;
                           registered only next cycle)
issue      --              --              issue_fire
```

Dependent issues on cycle N+2.

### 3.2 With ETB

```
           cycle N-1       cycle N         cycle N+1
MULT       early_done=1    done=1          --
early_cdb  valid=1, tag=T  --              --
CDB        --              valid=1, tag=T  --
RS entry   R=0, V=0        R=1, V=0 ←ETB   R=1, V=1
selector   skip            pick (R=1)      ---
value-mux                  !V → cdb_value  ---
issue                      issue_fire      ---
```

Dependent issues on cycle N, one cycle earlier than the baseline,
*if* the consumer is not a CDB-contending FU. In the current 1-wide
pipeline the consumer is almost always an ALU, which broadcasts on
the CDB combinationally from its issue cycle, and `issue_accept` for
non-MULT ops is gated on `!mult_done_valid`. On cycle N,
`mult_done_valid=1`, so `issue_accept=0` and the consumer is held.
It issues at N+1 anyway. See §5.

---

## 4. Unit tests

Three new scenarios landed in existing testbenches, one per tested
module. None is a regression-gate on a specific cycle count (that
would over-constrain future timing tweaks), but each asserts an
invariant the wakeup path cannot satisfy without ETB actually firing.

### 4.1 `test/mult_test.sv`: `early_done` leads `done` by exactly one cycle

A fresh multiply is driven after reset; the scenario scans cycles
until `done=1`, then asserts that `early_done` was high on the
previous cycle and has not been high twice in the window. A second
note documents that `mult.sv` has no flush port. The pipeline gate at
`pipeline.sv` is what suppresses the early pulse across mispredict,
and the full-pipeline regression exercises it.

### 4.2 `test/rs_test.sv`: three scenarios

- `test_early_tag_wakeup_issues_with_cdb_value`: dispatch a 1-source
  pending entry, pulse `early_cdb_valid` on cycle N, pulse the real
  CDB with value V on N+1, assert the RS issues on N+1 with V as
  `issue_src1_value`. This is the "V flows through the bypass mux"
  invariant.
- `test_early_tag_does_not_bypass_selector_combinationally`: dispatch
  a pending entry, toggle `early_cdb_valid` within a cycle, assert
  `issue_valid` stays 0 on that cycle. This locks down the
  `rs-issue-loop-fix` rule against future regressions.
- `test_early_tag_wakeup_preserves_src_value`: assert the ETB path
  does not latch a value into `src*_value`.

### 4.3 `test/lsq_test.sv`: `test_early_tag_wakes_base_before_cdb`

Dispatches a load whose base is pending on tag T. Pulses
`early_cdb_valid` with tag T on cycle N. Asserts that on cycle N+1 the
head entry's `base_ready=1` but `base_val_present=0`. Then drives the
real CDB with value V on N+1 and asserts `base_val_present=1` and the
`dcache_load` request goes out with the correct address on cycle N+2.

Note: the task list originally asked for `addr_ready=1 one cycle
earlier than the CDB-only control path` on the LSQ. The observable
ETB effect at the LSQ is that `base_ready` flips one cycle sooner;
`addr_ready` is unchanged because the AGU already fires combinationally
on the CDB cycle through `next_entries[]`. Making the AGU fire
*earlier* would require a value bypass the design defers as brittle.
The unit test asserts the observable effect rather than the task
list's phrasing.

All six `pass` targets are green in both sim and synth:

```
make mult.pass           → @@@ Passed
make mult.syn.pass       → @@@ Passed
make rs.pass             → @@@ Passed
make rs.syn.pass         → @@@ Passed
make lsq.pass            → @@@ Passed
make lsq.syn.pass        → @@@ Passed
```

---

## 5. Regression

34 programs, three modes, `make -j8 simulate_all`:

| mode                           | halt     | `.wb` vs `SERIALIZE_BRANCHES` baseline | cycle-for-cycle vs pre-ETB |
|--------------------------------|----------|----------------------------------------|----------------------------|
| pre-ETB (milestone4 @`cf77b62`) | 34/34 WFI | byte-identical                         | reference                  |
| ETB on (default)               | 34/34 WFI | byte-identical                         | byte-identical             |
| `+define+DISABLE_EARLY_TAG`    | 34/34 WFI | byte-identical                         | byte-identical             |

The tool log is preserved under the worktree's `.baseline-etb-off/`,
`.baseline-etb-on-final.txt`, and `.baseline-etb-off/cycle-delta-table.txt`
(not committed, reference only). Every row of the delta table is
`delta = 0 cycles, +0.000%`. This is expected; see §6.

---

## 6. Why the cycle counts don't move: known limitation

The mechanism is cycle-accurate and wakes the registered ready bit one
cycle earlier than the CDB-only path. What stops the save from
materializing on the current suite is CDB arbitration, a structural
property of the 1-wide pipeline:

- On the cycle MULT broadcasts its result (cycle T), `mult_done_valid = 1`.
- `pipeline.sv` gates non-MULT issue on that same signal:
  `issue_accept = (issue_is_mult ? !mult_busy : !mult_done_valid && !lsq_load_complete_valid)`.
- An ALU consumer that the RS selector picked on cycle T is held (no
  `issue_fire`) because the ALU would collide with MULT on the CDB.
- The consumer issues on cycle T+1, which is exactly where the
  CDB-only path had it.

With ETB off: the consumer's `src*_ready` flips at T+1 (registered),
selector picks at T+1, issues at T+1.

With ETB on: the consumer's `src*_ready` flips at T (registered from
ETB at T-1), selector picks at T, issue held by CDB contention, issues
at T+1.

Same-cycle delta: 0. Reproducer: any MULT -> dependent ALU chain, for
example `mult_no_lsq`. No delta observed on any of the 34 programs.

### 6.1 When will the save materialize?

Two structural changes unblock it. Either is sufficient, and the
proposal's 2-way superscalar does both:

- **A second CDB.** With CDB count > 1, the MULT's broadcast on CDB-0
  at cycle T no longer blocks an ALU consumer from broadcasting on
  CDB-1 at the same cycle. The ETB-woken consumer issues at T with
  its operand via the value-mux bypass, and the save lands.
- **A registered ALU result.** Breaking the combinational
  `rs_issue_*` -> `alu_result` -> `cdb_value` path into a stage would
  let the ALU consumer *issue* at T without *broadcasting* until T+1,
  then broadcast at T+1 while MULT has vacated the CDB. This would
  save the cycle without adding a CDB, at the cost of a 1-cycle
  latency hit on the ALU path.

A teammate is working on superscalar. The ETB wiring is designed to
plug into that change with no consumer-side restructuring; the
`val_present` bookkeeping and the two-arm value mux already have the
right invariants.

### 6.2 Why this is still worth doing now

Two reasons, both called out in the proposal:

- **Correctness baseline.** Getting the cycle-accurate early tag
  wiring, the value-mux semantics, and the flush gating all right
  under the existing single-CDB test infrastructure is cheaper than
  doing it alongside superscalar, and it drops half the consumer-side
  integration risk from the superscalar merge.
- **Does no harm.** 34/34 `.wb` byte-identical in both modes is the
  load-bearing guarantee for the sign-off baseline. The new unit-test
  scenarios catch selector-bypass and value-mux regressions before a
  full-program regression would.

---

## 7. Synthesis

Per-module synth is green:

| module | `.syn.pass` | worst slack (signed-off clock 1000 ps) |
|--------|-------------|----------------------------------------|
| `mult` | `@@@ Passed` | ≥ +90 ps (unchanged)                  |
| `rs`   | `@@@ Passed` | ≥ +199 ps on `entries[*].src*_ready` endpoints |
| `lsq`  | `@@@ Passed` | ≥ +90 ps                               |

Full-pipeline synth (`synth/pipeline.vg`) was not re-run as part of
this change. The pre-ETB worst slack was −309.07 ps on the
`rs_0/entries[*].src_ready -> mult_0/mstage[0]/product_sum_reg[*]`
path (see `base-design-verification.md` §4). ETB adds the
`mult_0.early_done -> rs_0/entries[*].src*_ready` combinational fan-in,
which is a short path through a single flop's output and a fan-out
gate. It is a known risk (listed in the change's `design.md` §Risks).
If the pipeline-level retune lands negative, the mitigation is to
register the ETB signal once on the pipeline side before feeding it
into the RS. That adds one cycle to the ETB wakeup but does not
affect correctness. Deferred to the superscalar bring-up, at which
point the RS-to-MULT path is being rebuilt anyway.

---

## 8. Files changed

Code:

- `verilog/mult.sv`: new `early_done` output, `$fatal` on
  `MULT_STAGES < 2`.
- `verilog/pipeline.sv`: `early_cdb_*` declaration, producer gate with
  `DISABLE_EARLY_TAG` ifdef, wired into RS and LSQ.
- `verilog/rs.sv`: `src*_val_present`, early-tag wakeup, CDB wakeup
  gate change, value-mux two-arm rule, selector comment noting the
  invariant.
- `verilog/lsq.sv`: symmetrical `base_val_present` / `data_val_present`,
  early-tag wakeup, CDB wakeup gate change.

Tests:

- `test/mult_test.sv`: new `early_done` scenario.
- `test/rs_test.sv`: three new scenarios.
- `test/lsq_test.sv`: new base-wakeup scenario.

Docs:

- `doc/early-tag-broadcast-report.md`: this file.
- `doc/project-overview.md`: §3.7, §8 bullet, §9 paragraph.
- `README.md`: progress section after the milestone-4 block.
- `CLAUDE.md`: two bullets in "Current status and what's deferred".

---

## 9. Known limitations (carry-over list)

- **No cycle reduction on current suite.** Root-caused in §6. The
  escape hatch `+define+DISABLE_EARLY_TAG` is there to keep the
  regression A/B-able once superscalar lands.
- **AGU does not fire on the ETB cycle itself.** The LSQ AGU waits
  for `base_val_present=1` before computing the address. A bypass
  that would let it fire on the ETB cycle was explicitly rejected in
  the design doc as brittle (stale-tag matches). Re-open if a
  future load-heavy profile makes the 1-cycle AGU-earlier path worth
  the risk.
- **Synthesis retune not landed.** Per §7. Deferred to the
  superscalar bring-up.

---

## 10. How to rebuild the A/B

```
# ETB on (default)
cd 4340-p4-early-tag-broadcast
make clean && make -j8 simulate_all

# ETB off
cd 4340-p4-early-tag-broadcast
make clean && make -j8 simulate_all \
    VCS_BAD_WARNINGS="+warn=noTFIPC +warn=noDEBUG_DEP +warn=noENUMASSIGN +define+DISABLE_EARLY_TAG"

# Compare cycle counts
for f in output/*.out; do
    grep -oE '[0-9]+ cycles / [0-9]+ instrs' "$f" | tail -1
done
```
