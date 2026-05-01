# MULT operand register (`51b7f1c`) — synth follow-up

Date: 2026-05-01. Author: nyavana, on behalf of `verify-merged-features`.

This file documents a re-synthesis of `team/release` HEAD (`ab905c8`)
done to evaluate teammate `xh2718`'s commit `51b7f1c`
("pipeline: register mult operands to break LSQ-head→mult critical path")
on top of the `verify-merged-features` baseline. It is a follow-up
note, not a feature report — the fix is **not currently merged into
`verify-merged-features`** pending the discussion below.

## TL;DR

Pulled `51b7f1c` onto a fresh worktree based on `team/release` HEAD
(`ab905c8`) and re-synthesized at `CLOCK_PERIOD = 1000.0 ps`. Worst
slack on `synth/pipeline.vg` went from **−244.54 ps → −797.58 ps**.
Functionally sound (34/34 RTL programs halt at WFI, 7/7 module
testbenches pass), but the timing regression on top of the
`verify-merged-features` baseline is large enough to hold the merge
into `verify-merged-features` pending review.

## What the fix did right

The MULT-stage-0 cone that the `verify-merged-features` pass
(`advanced-features-merge-report.md` §6) listed as the worst path
(`lsq_0/head_reg[1] → mult_0/mstage[0]/product_sum_reg[*]`,
3 endpoints, −244.54 ps) **no longer appears in the worst-slack list**
after `51b7f1c`. Registering `mult_mcand` / `mult_mplier` and gating
the multiplier with `mult_start_reg` clearly killed that path. Net
`mult` endpoints in `synth/pipeline.rep` are clean.

## What the new worst path looks like

Two violators, both starting at `lsq_0/head_reg[2]`:

| Slack | Startpoint | Endpoint |
|---|---|---|
| **−797.58 ps** | `lsq_0/head_reg[2]` | `rob_0/entries_reg[2][take_branch]` |
| **−797.55 ps** | `lsq_0/head_reg[2]` | `lsq_0/entries_reg[3][addr][31]` |

Data arrival on both is ~1776 ps (vs. 978.47 ps required). Walking
the longer of the two through `synth/pipeline.rep:4200..4360`:

- **0 → ~290 ps** — LSQ broadcast-arbiter logic into
  `lsq_load_complete_tag[2]` (the CDB tag the LSQ drives).
- **~290 → ~470 ps** — RS operand-ready / operand-mux feeding
  `alu_signed_b[*][0]` in `pipeline.sv`.
- **~470 → ~800+ ps** — A single 32-bit ripple-carry adder
  (`add_1134_G2`); the carry chain alone accounts for ~200 ps.
- The adder output then fans out to **(a)** the LSQ entry's
  `addr[31]` flop and **(b)** the branch-resolver's `take_branch`,
  which writes back to the ROB entry. Both endpoints are downstream
  of the same adder.

Cone summary:

```
LSQ head_reg → broadcast_pos → CDB tag → RS src_ready / operand mux
  → ALU operand → 32-bit adder → { LSQ entries[*].addr, ROB entries[*].take_branch }
```

This is **not** the cone `51b7f1c` targeted; it does not traverse
`mult_0/mstage[0]` at all.

## What we don't know

We did **not** re-synthesize `verify-merged-features` (parent
`dbcd4f6`) against this same DC compile to confirm whether the
`LSQ → ALU-adder` path was at −797 ps before and just hidden behind
the worse MULT cone in `advanced-features-merge-report.md` §6, or
whether DC's re-allocation of optimization budget after `51b7f1c`
made it show up. The merge-report §6 only enumerated three endpoints
in the MULT cone and did not list any second-worst path, leaving both
interpretations open. A re-baseline is ~30 min on the cluster; this
note can be updated once that's run.

`51b7f1c`'s commit message reports `−1657 → −797 ps` on the author's
synth, which is consistent with the post-merge number we see here
provided the author's baseline did **not** include
`verify-merged-features`'s STLF pipelining fix
(`advanced-features-merge-report.md` §10.3). On top of that fix
specifically, the `51b7f1c` delta isn't visible in the worst-slack
headline — the MULT cone was already at −244.54 ps with the STLF
fix landed, so registering MULT operands shifts the bottleneck
elsewhere without improving the headline.

## Functional check

- All 34 programs halt at WFI on the RTL simulator (`simv`).
- `mult.pass`, `rob.pass`, `rs.pass`, `dcache.pass`, `lsq.pass`,
  `icache.pass`, `branch_predictor.pass` all green on RTL.
- Synth-side regression (`syn_simv` + `simulate_all_syn` +
  `*.syn.pass` + `cmp -s output/<p>.wb output/<p>.syn.wb`) was started
  but not completed in this pass; `syn_simv` builds clean. The
  pre-`51b7f1c` `verify-merged-features` already had full sim ↔ syn
  `.wb` byte-equality on all 34 programs, so the netlist with
  `51b7f1c` is expected to as well — but it is not verified in this
  follow-up.

## Suggested next steps

1. Re-synth `dbcd4f6` to settle whether the
   `LSQ → ALU-adder → ROB take_branch / LSQ entries.addr` cone is
   pre-existing or exposed by `51b7f1c`'s placement.
2. If pre-existing: `51b7f1c` is architecturally a real improvement
   (one fewer cone to close) but net-neutral on the worst-slack
   headline. The next closure step is the LSQ-broadcast → ALU-adder
   path, plausibly by registering `load_complete_value` /
   `load_complete_tag` between LSQ and CDB (the option already
   considered and deferred in
   `advanced-features-merge-report.md` §6).
3. If genuinely new: revisit `51b7f1c` — the new flop's placement /
   fanout may have inadvertently loaded shared nets on the
   LSQ→ALU cone.

Until (1) is decided, `verify-merged-features` stays at `dbcd4f6`
(−244.54 ps; existing docs are accurate). The `release` branch on
the team repo (`CSEE4340-26/p4.GaPiChiXuXu`) already contains
`51b7f1c`; the `verify-merged-features`-derived docs that were merged
forward into `release` via PR #3 are now stale on the `release`
branch and should be reconciled once the framing is settled.

## Reproduce locally

```sh
git fetch team
git worktree add ../wt-test team/release
cd ../wt-test
make synth/pipeline.vg && make slack
sed -n '4180,4360p' synth/pipeline.rep   # full STA path detail
```
