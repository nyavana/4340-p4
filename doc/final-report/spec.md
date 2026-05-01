# Final Report — Specification

This document is the spec for the EECS 4340 final project report. It pins down structure, length, voice, content per section, and source-material discipline so the report can be drafted to a fixed target without re-litigating decisions mid-write.

The spec lives at `doc/final-report/spec.md`. The companion files are `doc/final-report/guideline.md` (writing-style policy) and `doc/final-report/figure-guide.md` (per-figure rendering plan). All three are internal — the final report itself does not reference them.

---

## 1. Purpose and audience

The instructor's spec (`doc/project-description.md` §3) calls for a 10–20 page project report covering introduction, design, implementation, testing, and evaluation, with specific discussion and analysis of every advanced feature.

The audience is a general technical reader who may not have an EE/CE background. The grader is a course staff member who *does* know out-of-order processor design but is scoring against the published rubric. We optimize the writing for the general reader (per `guideline.md`) and the structure for the rubric:

- Base features — 23%
- Correctness and testing — 20%
- Performance — 20%
- Advanced features — 17%
- Analysis — 10%
- Documentation — 7%
- Milestones — 3%

Page budget is allocated proportionally. Testing + Performance + Analysis = 50% of the grade and get ~28% of the page budget. Advanced features = 17% of the grade and get ~30% of the page budget (because the rubric explicitly demands per-feature discussion).

## 2. Length and format

**Soft target: ~14–16 pages single-column equivalent**, which is roughly **10–12 pages IEEE two-column**. These are recommendations, not contracts. Tighter is fine; meaningfully longer is not.

The draft is written in **Markdown first**, in the same `doc/final-report/` directory. We migrate to **IEEE-style LaTeX** only after the markdown draft is reviewed and signed off. This avoids burning time on LaTeX formatting before the content is settled.

## 3. Voice and source-material policy

### 3.1 Voice

Hybrid policy from `guideline.md`:

- Plain language; explain technical terms on first use; spell out acronyms.
- Each advanced-feature subsection opens with a single "what problem does this solve, in plain language" paragraph before the design.
- The reader is assumed to know what a register file and a pipeline are, but not necessarily a Reorder Buffer or a Common Data Bus. Components are introduced in §II in one sentence each.

### 3.2 Source material

The final report **stands alone**. It does not reference internal docs (`doc/project-overview.md`, `doc/advanced-features/*`, `doc/base-design/*`, `doc/weekly-reports/*`). All facts and numbers carried by the report must be self-contained.

Internal docs remain in-tree as engineer-facing companions and are valuable as **source material** for the writer — pulling facts and numbers from them is encouraged. Reusing paragraphs verbatim is not, because the internal docs are written for engineers, not the general technical reader.

## 4. Top-level structure

| § | Title | Rough budget | Primary rubric line |
|---|---|---|---|
| — | Abstract | ~150 words | Documentation |
| I | Introduction | ~1 pg | Doc, framing |
| II | Background and Constraints | ~0.75 pg | Doc |
| III | Pipeline Architecture | ~2 pg | **Base features (23%)** |
| IV | Base Implementation Details | ~1.5 pg | Base, Correctness |
| V | Advanced Features | ~5 pg | **Advanced features (17%)** |
| VI | Verification and Testing Methodology | ~1.5 pg | **Testing (20%)** |
| VII | Performance Evaluation and Analysis | ~2.5 pg | **Performance (20%) + Analysis (10%)** |
| VIII | Discussion: Limitations and Future Work | ~0.5 pg | Doc |
| IX | Conclusion | ~0.25 pg | Doc |
| — | References | ~0.25 pg | — |

Single-column total: ~14.75 pg. IEEE two-column equivalent: ~10–11 pg. Within target.

There is **no separate "Milestones" section.** The intro mentions milestone 1/2/3 in one sentence for chronological framing; that's the entire treatment.

## 5. Section-by-section content

### Abstract

One paragraph, ~150 words. Drafts last (so the headline numbers are final). Must state: P6 OoO RV32IM design built on the P3 in-order starter; one-instruction base width; **seven advanced features** layered on top (2-way superscalar, early tag broadcast, gshare, return address stack, store-to-load forwarding, next-line prefetch, 2-way set-associative D-cache); all 34 test programs pass on RTL and synthesized netlist with byte-identical writeback parity; one-line headline numbers (geomean speedup, branch-prediction accuracy, CPI).

### §I — Introduction (~1 pg)

Three short subsections in spirit, no need for explicit numbering:

- **What the processor does.** RV32IM, runs the same programs P3 ran, but with out-of-order issue and execute. Why OoO at all (one stalled load shouldn't stall every later independent instruction).
- **What we built on top of the starter.** The starter ships an in-order pipeline + multiplier + I-cache + decoder skeleton. Everything else (ROB, RS, RAT, LSQ, D-cache, branch predictor, advanced features) is ours. One sentence per milestone for chronological grounding.
- **Roadmap of the report.** "§III walks through the architecture, §V covers the advanced features one at a time, §VII has the numbers."

### §II — Background and Constraints (~0.75 pg)

- **What "out-of-order" means**, in two paragraphs. Use a tiny example: a load and an independent add — in-order vs. out-of-order. Mention the classical hazards (RAW, WAR, WAW) by name only.
- **Component glossary**, one sentence each: ROB, RS, CDB, LSQ, branch predictor. Plain-language framing of *purpose*, not implementation.
- **Fixed constraints we worked under**, one short paragraph: 100 ns memory latency, 256 B I-cache + 256 B D-cache, single-CDB at base width, multiplier from P2. These are spec constraints, not design choices — the report must flag that explicitly.

No diagram in §II.

### §III — Pipeline Architecture (~2 pg)

The "what feeds what" walkthrough. Carries Figure 1 (top-level pipeline block diagram).

- **Top-level diagram + dataflow paragraph.** Figure 1 shows: Fetch (PC + I-cache + branch predictor) → Decode → Dispatch (allocate ROB + RS or LSQ) → Issue (RS→FU, LSQ-head→D-cache) → Execute (2 ALUs, 1 pipelined MULT, branch resolver, D-cache) → CDB broadcast → Commit (ROB head, regfile write, mispredict check). One paragraph reads the diagram aloud.
- **Pipeline stages, one paragraph each**: Fetch, Decode, Dispatch/rename, Issue/execute, Commit. Highlight the design choice: **no separate map table — the ROB *is* the physical register file** (`PHYS_REG_SZ = 32 + ROB_SZ`). Memory ops bypass the RS and go to the LSQ.
- **Why P6 over R10K.** One paragraph. Embedded-RAT-in-ROB is simpler at a 1-wide base; R10K's free list + map table is more complex and we did not need a unified physical register pool for the planned advanced-feature mix.

§III does **not** enumerate the load-bearing implementation rules. That is §IV.

### §IV — Base Implementation Details (~1.5 pg)

Six short paragraphs, one each:

1. **ROB and rename.** Embedded RAT, single `dispatch_fire` allocates ROB + RS in lockstep. Stale-RAT-clear at commit (only clear if the RAT entry still points at the committing slot). JAL/JALR commit-value override (CDB carries branch target; ROB overrides with NPC for any branch with a non-zero `rd`).
2. **Reservation Station.** Issue selector reads the *registered* `src_ready`, not the combinational bypass. Briefly tell the war story: a combinational bypass form created a feedback loop (`issue_found → src*_ready_eff → cdb_valid → issue_accept → issue_found`) that froze the simulator on tight-loop programs (`mult_no_lsq` plus a dozen others, all stalling near the same cycle horizon). Fix: registered ready bits. CDB-bypass mux still wires through to the issued entry's value, so correctness holds at one extra cycle when an operand arrives on the same cycle's CDB.
3. **CDB priority and store sideband.** Priority MULT > LSQ load > ALU. Stores never use the CDB — they signal completion through `store_done_*` to the ROB; the LSQ entry is released to the cache only at commit. Branches always broadcast on the CDB but the PC redirect happens at *commit*, not at execute.
4. **LSQ.** FIFO, head-only access to the cache, holds store data until commit. Memory ops never enter the RS. Simplest design that satisfies the rubric's memory-ordering requirement.
5. **D-cache (base).** Write-back, write-allocate, byte-granular dirty/valid masks for sub-word stores, full-line writeback only.
6. **Branch predictor (base).** Bimodal 2-bit-counter table + BTB, redirects same cycle as fetch. **Note for the reader:** this is the base predictor required by the rubric and the comparison baseline for §V.C. The live code in the final build uses the gshare + RAS predictor described in §V.C, which replaces bimodal but keeps the BTB.

**Out-of-order-issue demonstration code goes inline at the end of §IV.** A short snippet (load + independent add + dependent add) plus one or two sentences explaining how the RS lets the independent add issue before the load returns. This is a hard rubric requirement.

### §V — Advanced Features (~5 pg)

§V opens with the **spec-compliance feature table** (lifted in spirit from `feature-spec-verification.md` §2) so the grader can score the 17 advanced-feature points directly:

| # | Feature | Spec category (§4.2) | Tier |
|---|---|---|---|
| 1 | 2-way superscalar | Superscalar execution | difficult |
| 2 | Early tag broadcast | Early tag broadcast (L7) | difficult |
| 3 | gshare predictor | Fetch — sophisticated branch predictors † | simpler |
| 4 | Return Address Stack | Fetch — return address stack | simpler |
| 5 | Store-to-load forwarding | Memory hier. — load/store forwarding | simpler |
| 6 | Next-line prefetch (stream buffer) | Memory hier. — prefetching † | simpler |
| 7 | 2-way set-associative D-cache | Memory hier. — associative caches † | simpler |

That is **2 difficult + 5 simpler = 7 features**, satisfying the spec's "at least one difficult plus some others" rule.

Subsections, organized for prose flow but each leaf gets its own *Problem / Design / Tradeoffs / Result* slot:

- **§V.A — 2-way Superscalar.** *Problem:* 1-wide pipeline caps IPC at 1. *Design:* 2-way fetch/decode/dispatch/commit, 2 CDBs, 2 ALUs, 1 MULT FU, 1-port LSQ. *Tradeoffs:* port logic everywhere, area+slack cost, single-port LSQ still serializes adjacent loads. *Result:* headline speedup from §VII.
- **§V.B — Early Tag Broadcast.** *Problem:* dependents of multi-cycle MULT wait too long. *Design:* dedicated early-tag wire from MULT stage 0; sets RS `src_ready` for issue eligibility only; value still arrives via CDB. The unit-test scenario in `rs_test.sv` guards against the early tag accidentally bypassing the *value* path. *Tradeoffs:* only deterministic, non-replay FUs eligible; per-program win is gated on the second CDB existing. *Result:* per-program speedup from §VII; concentrated on multiply-heavy programs.
- **§V.C — Branch-prediction enhancements.** Shared-parent paragraph: both gshare and RAS live in the same `branch_predictor.sv` module and share the GHR/BHT budget. Sub-leaves:
    - **§V.C.1 — gshare.** *Problem:* bimodal aliases two PCs that share index bits even when their patterns differ. *Design:* index by `PC[hi:lo] ⊕ GHR`; GHR width = BHT index width; BHT 64 entries. *Tradeoffs:* GHR width balances aliasing vs. cold-start. *Result:* per-program prediction accuracy delta from §VII.
    - **§V.C.2 — Return Address Stack.** *Problem:* function returns are nearly 100% predictable but a generic indirect-branch predictor has to learn each frame. *Design:* 16-entry stack pushed on JAL writing `ra`, popped on `JALR x0, ra, 0`; overrides BTB on returns when non-empty. *Tradeoffs:* 16 entries deep is generous for the suite. *Result:* prediction-accuracy lift on recursion-heavy programs.
- **§V.D — D-cache enhancements.** Shared-parent paragraph: both features share the bus arbitration mask in `pipeline.sv`. Sub-leaves:
    - **§V.D.1 — 2-way set-associative D-cache.** *Problem:* direct-mapped 256 B has 32 sets; conflict-misses on stride-aligned arrays. *Design:* 16 sets × 2 ways, one LRU bit per set. *Tradeoffs:* comparator + LRU per set; helps only when conflicts dominate. *Result:* hit-rate change from §VII.
    - **§V.D.2 — Next-Line Prefetch / Stream Buffer.** *Problem:* sequential access wastes 100 ns latency on every fresh line. *Design:* one-line stream buffer between cache and memory; issues line+1 after a miss completes; same module reused on the I-cache side. *Tradeoffs:* one extra request on the bus; helps only when access is predictable. *Result:* per-program cycle reduction from §VII.
- **§V.E — Store-to-Load Forwarding.** *Problem:* a load following an in-flight store of the same address should not have to wait for cache. *Design:* LSQ-head load compares its address against older un-committed stores; clean match → forward in one cycle; partial overlap → fall through to cache. *Tradeoffs:* the verify-merged-features pass deferred forwarding by one cycle (mergesort: 200 072 → 200 073 cycles) to close synth slack from −504 ps to −244 ps; deliberate timing-vs-IPC tradeoff worth flagging. *Result:* per-program speedup on STLF-hitting programs.

The "Result" paragraph in each leaf states the headline number and points the reader at §VII's table for the per-program breakdown — we never tabulate the same data twice.

### §VI — Verification and Testing Methodology (~1.5 pg)

- **Three-layer test pyramid.** Unit testbenches (per-module, pass on literal `@@@ Passed` string) → full-pipeline RTL on 34 programs → synthesized-netlist re-run of both layers.
- **Unit tests, RTL.** Modules covered: `mult`, `rob`, `rs`, `lsq`, `dcache`, `icache`, `branch_predictor`. Summarize the scope of each scenario set in plain language: e.g., ROB tests cover dispatch, CDB completion, in-order commit, same-cycle RAT bypass, stale-clear protection, the x0 guard, flush, full-detection, and wraparound. The RS test suite includes a guard scenario specifically protecting the early-tag broadcast invariant from §V.B (early tag must not bypass the issue selector combinationally).
- **Unit tests, synthesized netlist.** `synth/<m>_svsim.sv` wrappers bridge unpacked-array ports DC flattens. The branch_predictor test was rewritten when bimodal was replaced with gshare — TB-side gshare model + colliding-PC selection in Test 7 to preserve saturate-then-flip semantic under XOR indexing. One paragraph because the rubric weights testing methodology.
- **Full-pipeline regression on 34 programs.** Pass criterion: clean halt on `@@@ System halted on WFI instruction` plus correct writeback. `make simulate_all` and `make simulate_all_syn`. All 34 pass on both layers. Suite spans toy, kernel-style, and a CNN forward pass.
- **Architectural-divergence sign-off.** Every `.syn.wb` byte-matches `.wb` (RTL=netlist parity), and post-merge `.wb` byte-matches the same commit rebuilt under `+define+SERIALIZE_BRANCHES` (OoO front-end = serialized front-end parity).
- **A/B configuration knobs.** Compile-time `+define` knobs that disable individual advanced features for ablation: `DISABLE_EARLY_TAG`, `DISABLE_GSHARE`, `DISABLE_RAS`, `DISABLE_STLF`, `DISABLE_PREFETCH`. Used to generate the per-feature attribution data in §VII. Two features (2-way superscalar, 2-way set-assoc D-cache) are structural and excluded from leave-one-out; their contribution is inferred analytically.

### §VII — Performance Evaluation and Analysis (~2.5 pg)

The combined 30%-of-grade section. Numbers live here.

- **Methodology.** How CPI is computed (`cycles / dynamic_instr_count`); two baselines used: the full-feature build ("all on") and the all-advanced-disabled build ("OoO base"). Per-feature attribution uses leave-one-out at the all-on configuration. Why this is the right methodology (measures *marginal* contribution at the operating point, which is what speedup claims should mean).
- **Per-program performance table.** Picks ~10 programs spanning the speedup range (worst case, median, best case e.g. `alexnet`). Columns: cycles_baseline, cycles_full, Δ%, CPI_full, branch_acc_full. Geomean and arithmetic-mean rows at the bottom. Source: `doc/advanced-features/per-feature-ablation.md` (sweep output) plus `doc/advanced-features/branch-accuracy-cpi-diff.md` (existing branch-accuracy data).
- **Continuation — full 34-row table.** Inline (not appendix; the report is standalone). Slightly smaller font is acceptable in LaTeX.
- **Headline finding.** Geomean cycle reduction across the suite, geomean CPI improvement, geomean branch-prediction accuracy lift. One short paragraph.
- **Per-feature attribution table.** Rows = features (ETB, gshare, RAS, STLF, prefetch — and analytical entries for superscalar + set-assoc); columns = geomean Δcycles%, geomean ΔCPI, programs where the feature dominates. **Honest-scoping paragraph:** superscalar and set-assoc are not ablated because they are structural; their contribution is inferred from CPI < 1.0 on ILP-rich code and from D-cache hit-rate analysis respectively. The rubric explicitly rewards measuring honestly over claiming uncritically.
- **Branch-prediction analysis.** Per-program accuracy. Programs where RAS contributes most (recursion-heavy). Programs where gshare's pattern correlation matters most (loop bodies with data-dependent branches). Programs where the bimodal baseline already does well (so neither helps much).
- **Cache analysis.** D-cache hit rate before vs after associativity + prefetch, where the harness exposes it. If not, fall back to per-program cycle reduction as a proxy and say so.
- **Synth slack summary.** Per-module slack table (`mult +0.23 ps` … `branch_predictor +570.88 ps` — all met). Then full-pipeline `synth/pipeline.vg` honestly: worst slack −244.54 ps on `lsq_0/head_reg[1] → mult_0/mstage[0]/product_sum_reg[*]`, three endpoints violate, all functionally bit-equivalent (`.syn.wb` matches `.wb` across all 34 programs). Static-timing reporting concern, not a correctness one.

### §VIII — Discussion: Limitations and Future Work (~0.5 pg)

Three or four short paragraphs:

- **Closing the −244 ps timing miss.** Two known options: register `load_complete_value` at the LSQ output (one extra cycle on every load); split MULT stage 0 (one extra cycle on every multiply). Both deferred — cost-vs-payoff didn't justify the rebuild against a working system.
- **Single-port LSQ on a 2-way machine.** Two adjacent loads still serialize. Natural next step: dual-ported LSQ + dual-ported D-cache (or banked).
- **Single MULT FU on a 2-way machine.** Caps IPC on multiply-heavy code. ETB recovers some; a second MULT FU would do better.
- **mult_no_lsq history.** One sentence: milestone-2 mult_no_lsq froze deterministically at cycle ~2192; landing the LSQ closed the gap. Engineering-honesty data point.
- **What we'd revisit.** One sentence: a unified physical register pool (R10K-style) if widening past 2-way.

### §IX — Conclusion (~0.25 pg)

One paragraph. What we built, what works, the headline number, the one honest limitation. Closes the report.

### References (~0.25 pg)

5–8 entries:

- Hennessy & Patterson, *Computer Architecture: A Quantitative Approach* — §3.6, §3.8, §3.9, §3.12.
- McFarling, "Combining Branch Predictors" (1993) — origin of gshare.
- Course lecture-number references where the spec uses them (L5, L7, L9, L10).
- VeriSimpleV starter / RV32IM ISA spec.

## 6. Figures and tables

Figures planned for the body. Per-figure rendering plan in `figure-guide.md`.

- **Figure 1 — Top-level pipeline block diagram.** §III. Stages + buses + the few sideband signals (early-tag, store_done).
- **Figure 2 — gshare + RAS branch predictor.** §V.C. GHR ⊕ PC indexing into BHT, BTB lookup, RAS push/pop.
- **Figure 3 — D-cache organization.** §V.D. 2-way set-assoc with LRU bit; stream buffer between cache and memory; bus arbitration.
- **Figure 4 — Store-to-load forwarding lanes.** §V.E. LSQ scan + forwarding mux + 1-cycle defer.
- **Figure 5 — Early-tag-broadcast timing.** §V.B. MULT stages with the early tag wire firing before the value arrives on the CDB.

Tables planned:

- **Table I — Spec-compliance feature mapping.** §V opener (the 7-row table above).
- **Table II — Per-program performance, representative subset.** §VII. ~10 rows.
- **Table III — Per-program performance, full 34-row continuation.** §VII inline.
- **Table IV — Per-feature attribution.** §VII.
- **Table V — Per-module synthesis slack.** §VII.

Markdown draft uses ASCII/Mermaid sketches and `[FIGURE N: caption]` placeholders. LaTeX migration replaces these with TikZ or rendered SVG per `figure-guide.md`.

## 7. Source-material map (writer's reference)

Where to find the facts for each section while drafting. **Never appears in the final report.** Pure internal aid.

| Section | Primary source(s) |
|---|---|
| §I Introduction | `doc/project-overview.md` §1, §3 |
| §II Background | None — written fresh; constraints from `doc/project-description.md` §4.1 |
| §III Architecture | `doc/project-overview.md` §4–6; `verilog/pipeline.sv` for the top-level dataflow |
| §IV Base impl | `doc/base-design/base-design-verification.md`, `doc/base-design/rs-issue-loop-fix.md`, `doc/base-design/branch-predictor-report.md`; `CLAUDE.md` "load-bearing rules" list |
| §V.A Superscalar | `doc/advanced-features/superscalar-report.md` |
| §V.B ETB | `doc/advanced-features/early-tag-broadcast-report.md` |
| §V.C gshare/RAS | `doc/advanced-features/branch-predictor-advanced-report.md` |
| §V.D D-cache | `doc/advanced-features/dcache-advanced-report.md` |
| §V.E STLF | `doc/advanced-features/stlf-report.md` |
| §VI Testing | `doc/advanced-features/advanced-features-merge-report.md` §2–6, §10; `doc/advanced-features/feature-spec-verification.md` |
| §VII Eval | `doc/advanced-features/branch-accuracy-cpi-diff.md`, `doc/advanced-features/per-feature-ablation.md` (in-flight), `doc/advanced-features/advanced-features-merge-report.md` §3, §11 |
| §VIII Discussion | `CLAUDE.md` "Currently broken / known-stale" + "Recently fixed" |
| §IX Conclusion | None — synthesized from above |

## 8. Out-of-scope

The report does **not** include:

- A separate "Milestones" or "Group charter" section. Milestones get one sentence in §I; the charter is proposal-only.
- Cross-references to internal docs in `doc/`. The report is standalone.
- Per-commit or per-branch git history. Engineering-process detail belongs in `doc/weekly-reports/`, not the report.
- Full code listings beyond the OoO-issue demonstration snippet in §IV.
- Synthesis netlists or wave dumps as figures.
- A claim of advanced-feature point values. We list the 7 features and let the grader assign points.

## 9. Workflow

### 9.1 Agent and tooling rules

These rules apply to every writing pass on the report — drafting, revising, LaTeX migration, and final review.

- **Opus 4.7 only for writing.** When subagents are dispatched for any writing task (drafting a section, revising prose, migrating to LaTeX, writing the abstract, etc.), they MUST use Opus 4.7 (`model: opus` on the Agent tool, which resolves to the current Opus generation; explicitly select Opus 4.7 if the dispatcher offers a generation choice). Sonnet and Haiku are not approved for prose work on this report. Mechanical, non-prose tasks (running sweeps, parsing data, running `make`, regenerating tables from CSVs) may use Sonnet — those are not "writing."
- **Invoke `/humanizer` during writing.** Every drafting subagent must invoke the `humanizer` skill *while writing* (not only at review time). The skill flags AI-writing tells — inflated symbolism, promotional language, em-dash overuse, rule-of-three, AI-vocabulary words, vague attributions — and the prose should be free of those before the section is considered drafted. The drafting prompt for each subagent must include "Use the humanizer skill while writing this section."
- **Invoke `/humanizer` again as a final review pass.** Once the full markdown draft is complete (all sections drafted and self-reviewed), run a final `/humanizer` pass over the entire draft as a dedicated review step. Treat its findings as required edits, not advisory. This is step 9.2.4 below.
- **No emoji or decorative formatting** in the report. The skills' default behavior (no emoji unless asked) holds.

### 9.2 Workflow steps

1. **Markdown draft** — written in `doc/final-report/draft.md` (one file), section by section, against this spec. Figures stubbed as `[FIGURE N: caption]`. Tables drafted in markdown. Subagent dispatched per section uses Opus 4.7 and runs `/humanizer` while drafting (see §9.1).
2. **Per-section self-review** — placeholder scan, internal-consistency check against this spec, voice check against `guideline.md` §5 quick checklist.
3. **User review (per section or per cluster of sections)** — read-through, request changes.
4. **Whole-draft `/humanizer` pass** — dedicated review run over the completed markdown draft. Apply edits in place. Repeat until no findings remain.
5. **LaTeX migration** — convert markdown to IEEE-style two-column LaTeX in `doc/final-report/main.tex`. Use `figure-guide.md` to render Figures 1–5 in TikZ or import as SVG. Subagent dispatched here also uses Opus 4.7 (typesetting still touches prose — captions, table headers, paragraph adjustments for column-width fit).
6. **Final review** — page count, figure rendering, reference list, abstract drafted last with finalized headline numbers. One last `/humanizer` pass on any prose changed during LaTeX migration.

The markdown draft is the canonical source until step 5. Don't dual-maintain.
