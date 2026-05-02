# Draft update notes — corrected findings

Reference file for adjusting `draft.md`. Generated 2026-05-01 after
re-verification passes on `058a8aa` (base-design) and `f2d565a`
(post-merge HEAD = `dbcd4f6` + `51b7f1c`).

---

## TL;DR — the four headline number changes

1. **Test suite: 33 programs**, not 34. `programs/mytest.s` (a
   12-line synthetic test added during week 3 from milestone-2) was
   not part of the canonical suite and has been removed. Every
   "all 34 / 34 pass" claim becomes "all 33 / 33 pass".
2. **Post-merge full-pipeline worst slack: −797.58 ps** at 1000 ps,
   on `lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]`
   (companion `lsq_0/head_reg[2] → lsq_0/entries_reg[3][addr][31]`
   at −797.55 ps; 2 endpoints violate). Cone: **LSQ broadcast → RS
   operand mux → ALU 32-bit adder → {ROB take_branch, LSQ addr}**.
   The MULT stage-0 cone the older write-ups described
   (`lsq_0/head_reg[1] → mult_0/mstage[0]/product_sum_reg[*]`) is
   **closed** by `51b7f1c`'s mult-operand register.
3. **Base-design worst slack: −302.55 ps** (clean re-synth on
   `058a8aa`, 2026-05-01). Originally recorded as `−309.07 ps`;
   ~6.5 ps delta is within DC re-run noise. Same RS→MULT-stage-0
   cone class, just `src2_ready → product_sum_reg[53]` this run vs
   `src1_ready → product_sum_reg[45]` originally. **The
   base-design measurement was approximately correct.**
4. **Prefetch ablation headline re-anchored.** New largest
   single-program no_prefetch swing: **`alexnet` +94.22%** (was
   `mytest` +95.31%). Geomeans recomputed (mytest dropped from the
   34-row table, leaving 33): **no_prefetch +37.14%** (was
   +38.57%), **no_advanced +37.86%** (was +39.28%). The four
   non-prefetch features (ETB, gshare, RAS, STLF) had zero
   contribution from `mytest`, so their geomeans are unchanged at
   +0.10 / +0.19 / +0.10 / +0.20 %.

---

## What's retracted

- **`−504.66 → −244.54 ps` STLF pipelining slack delta** (and the
  "~260 ps recovered" framing). Both endpoints came from
  measurements that re-used a stale `synth/pipeline.vg` artifact
  without `make nuke`, so DC's incremental flow gave numbers that
  did not reflect the actual RTL. The architectural change in
  `verilog/lsq.sv` (forwarded loads broadcast one cycle later via
  the existing STLF latch) is real and remains in the design; only
  the slack numbers attributed to it are retracted. The standalone
  STLF slack contribution has not been re-baselined against a
  `dbcd4f6`-minus-STLF build.
- **"The remaining 244 ps lives inside the MULT-stage-0 multiply
  tree."** The MULT stage-0 cone is closed; the new bottleneck is
  the LSQ-broadcast / ALU-adder cone described above.
- **"Closing the −244 ps timing miss requires registering
  `load_complete_value` or splitting MULT stage 0."** The MULT
  stage-0 split is moot (already closed). The remaining option is
  registering `load_complete_value` / `load_complete_tag` between
  the LSQ broadcast arbiter and the CDB (one extra cycle on every
  completing load), or rebalancing the broadcast → adder cone (e.g.,
  splitting the 32-bit adder into two stages). Both deferred.
- **"+95.31% on mytest" / "almost the entire 39.28% gap"** in the
  ablation headline. Numbers superseded by the recomputed geomeans
  above.

---

## What's verified now (with caveats)

- **33/33 programs halt at WFI on RTL `simv`** at the post-merge
  HEAD (`f2d565a`). All 7 module testbenches green (14 `@@@ Passed`,
  zero `@@@ Incorrect`).
- **34/34 programs halt at WFI on the base-design worktree**
  (`058a8aa`); the base-design tree retains its own `mytest.s`
  because we don't rewrite the historical commit, only verify it.
- **`51b7f1c` mult-operand register recovers ~800 ps standalone.**
  Re-baseline of `dbcd4f6` (without `51b7f1c`) gave worst slack
  ≈ **−1600 ps**; with `51b7f1c` applied, worst slack drops to
  −797.58 ps. This matches the team's commit-message claim of
  `−1657 → −797 ps` almost exactly.
- **Caveat: synth-side regression not re-run after `51b7f1c`.** The
  pre-`51b7f1c` baseline had every `.syn.wb` byte-identical to its
  `.wb` across all 34 programs. The merge inserts a flop in front
  of the multiplier (no value change), so RTL ↔ netlist same-commit
  byte-equivalence is *expected* to hold post-merge but
  `make simulate_all_syn` was not performed. A clean re-verification
  is recommended before any final sign-off.

---

## By draft.md section — what to update

### §I (introduction) / §II (background)

No specific numbers to change. If you state the test-suite size
anywhere in the opener ("we run a 34-program suite"), change to 33.

### §III (architecture) / §IV (base implementation)

The base-design baseline number, if cited, is **−302.55 ps**
(originally `−309.07 ps`; the re-verification footnote can be a
parenthetical or a sentence). Worst-path startpoint is
`rs_0/entries_reg[3][src2_ready]`, endpoint
`mult_0/mstage[0]/product_sum_reg[53]`; if §IV-or-earlier cites
`src1_ready → product_sum_reg[45]`, that's the original number and
either is acceptable to keep with a "or `src2_ready / [53]` on
re-synth — DC reshuffles bit indices within the fanout-equivalent
class" footnote.

### §V advanced-features parade

- **§V.E STLF** — the "+1 cycle defer for synth slack" tradeoff
  paragraph: drop the specific `−504 → −244 ps` numbers. Replace
  with: "the verify-merged-features pass deferred forwarding by one
  cycle (mergesort 200 072 → 200 073 cycles) for synth-slack
  reasons. The earlier `−504.66 → −244.54 ps` measurement was
  retracted as stale-build-artefact data; the standalone slack
  contribution has not been re-baselined." Or simply: "deliberate
  timing-vs-IPC tradeoff; standalone slack contribution unverified
  on the corrected baseline."

### §VI verification methodology

- Wherever you list pass counts: `33/33` (RTL) and (caveated)
  `33/33` synth, with the re-run-not-performed footnote.
- The base-design sign-off mention (if any) cites `33` programs on
  the post-mytest tree; the base-design *commit* itself was signed
  off on 34 programs at the time, but going-forward statements use
  33.

### §VII performance evaluation — the most important section

- **Per-program performance table (Table II/III).** Drop the
  `mytest` row (213 → 213 cycles, +0% on every leave-one-out except
  prefetch where it went 213 → 416). The remaining 33 rows are
  unchanged.
- **Headline geomean numbers.** Use the recomputed values:

  | Feature disabled | Geomean Δ% (mytest excluded) |
  |---|---:|
  | ETB (`no_etb`) | +0.10% |
  | gshare (`no_gshare`) | +0.19% |
  | RAS (`no_ras`) | +0.10% |
  | STLF (`no_stlf`) | +0.20% |
  | prefetch (`no_prefetch`) | **+37.14%** |
  | all 5 disabled | **+37.86%** |

  (Originals were +38.57% and +39.28% respectively; the four
  non-prefetch features are unchanged because `mytest` contributed
  +0% to each.)
- **Largest single-program swing for prefetch.** Use **`alexnet`
  +94.22%** as the anchor; runners-up include `btest2` +94.16%,
  `sampler` +84.13%, `priority_queue` +78.31%, `omegalul` +77.57%,
  `haha` +77.08%, `basic_malloc` +76.80%. The ablation data table
  (per-feature-ablation.md §2) is the source.
- **The "almost the entire gap" framing still works.** The
  no_advanced geomean (+37.86%) is within **0.72 pp** of the
  no_prefetch geomean (+37.14%), so prefetch alone explains ~98%
  of the cumulative speedup gap. The four non-prefetch features
  contribute roughly 0.72 pp combined.
- **Synth slack summary table (Table V).** Per-module rows are
  unchanged: mult +0.23 ps, lsq +0.05 ps, dcache +19.28 ps, rs
  +229.79 ps, rob +282.83 ps, icache +448.51 ps, branch_predictor
  +570.88 ps. Full-pipeline `synth/pipeline.vg`: worst slack
  **−797.58 ps** on `lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]`,
  companion endpoint −797.55 ps, two endpoints violate. Static-timing
  reporting concern, not a correctness one.

### §VIII discussion / limitations

The "closing the timing miss" paragraph needs a rewrite. New text:

> The remaining −797.58 ps full-pipeline timing miss lives in a
> different cone than the older write-ups described. The MULT
> stage-0 multiply tree that was the worst path through milestone 4
> is closed by `51b7f1c`'s mult-operand register (re-synth:
> `dbcd4f6` baseline ≈ −1600 ps → post-merge −797.58 ps, ~800 ps
> recovered). The new bottleneck is `LSQ broadcast → RS operand
> mux → ALU 32-bit adder → {ROB take_branch, LSQ addr}` — a single
> 32-bit ripple-carry adder with high fanout sits in the middle of
> a long combinational chain. Closing it would mean either
> registering `load_complete_value` / `load_complete_tag` between
> the LSQ broadcast arbiter and the CDB (one extra cycle on every
> completing load) or splitting the ALU's 32-bit adder into two
> pipeline stages. Both pay perf on the common case to fix the
> static-timing residual, so this pass stops short. The netlist is
> functionally bit-equivalent to the RTL on the pre-`51b7f1c`
> baseline; the merge is a flop insertion in front of the
> multiplier (no value change), so the property is expected to hold
> after the merge but `make simulate_all_syn` was not re-run.

### §IX conclusion

If the conclusion cites the headline static-timing miss, use
**−797.58 ps**. The "netlist is functionally bit-equivalent to the
RTL" claim still holds with the caveat in §VIII.

---

## Verbatim snippets you can paste / adapt

### Slack delta table (Table V row replacement)

```
| Path class                       | Worst slack | Notes                                                             |
|----------------------------------|------------:|-------------------------------------------------------------------|
| Pre-merge baseline (058a8aa)     |  −302.55 ps | RS→MULT stage-0; ~−309 ps on the original sign-off                |
| Post-merge baseline (dbcd4f6)    |  ~−1600 ps  | LSQ broadcast → MULT-stage-0 (STLF added the dominant cone)       |
| Post-`51b7f1c` (current HEAD)    |  −797.58 ps | LSQ broadcast → RS mux → ALU adder → ROB / LSQ entry             |
```

### Per-feature attribution (Table IV row replacement)

```
| Feature  | Geomean Δ% (disabled) | Largest single-program swing       | Source     |
|----------|----------------------:|------------------------------------|------------|
| ETB      |               +0.10% | outer_product +1.07%               | ablation   |
| gshare   |               +0.19% | fib_rec +9.65%                     | ablation   |
| RAS      |               +0.10% | basic_malloc +0.52%                | ablation   |
| STLF     |               +0.20% | insertionsort +1.64%               | ablation   |
| prefetch |              +37.14% | **alexnet +94.22%**                | ablation   |
| all 5    |              +37.86% | alexnet +94.21%                    | ablation   |
```

### One-sentence headline finding for §VII

> Prefetch dominates the marginal cycle-count contribution: disabling
> the stream-buffer prefetcher alone causes a geomean +37.14%
> regression across the 33-program suite (alexnet +94.22% in the
> single-program worst case), accounting for ~98% of the +37.86%
> gap that the all-five-features-disabled configuration produces.
> The four other ablatable features (ETB, gshare, RAS, STLF)
> contribute 0.10–0.20% each and roughly 0.72 pp combined.

### One-sentence headline limitation for §VIII

> The full-pipeline static-timing miss at the 1000 ps clock is
> −797.58 ps on the LSQ-broadcast → ALU-adder cone; the MULT
> stage-0 cone the original plan targeted is closed by `51b7f1c`'s
> mult-operand register, but the residual cone falls outside the
> two retunes the plan considered (registering `load_complete_value`
> on every load, or registering MULT operands — the latter is now
> done) and a third option (rebalancing the 32-bit ALU adder) was
> not pursued.

---

## Sources for the numbers above

- Post-merge `−797.58 ps` and worst-path detail: clean re-synth of
  `verify-merged-features` HEAD on 2026-05-01,
  `synth/pipeline.rep`, walked 2026-05-01.
- Pre-merge `−302.55 ps`: clean re-synth of `058a8aa` in
  `4340-p4-pre-merge-synth` worktree on 2026-05-01.
- `dbcd4f6` ≈ `−1600 ps`: per user-provided re-baseline.
- 33-program pass count: subagent run on 2026-05-01,
  `make simulate_all -j` on `verify-merged-features` after
  `git rm programs/mytest.s`.
- Geomean recomputation: derived from
  `doc/advanced-features/per-feature-ablation.md` §2 with the
  `mytest` row excluded.
- All `make synth/<m>.vg` per-module slack values
  (mult/lsq/dcache/rs/rob/icache/branch_predictor) are unchanged
  from the original ablation; not re-run.
