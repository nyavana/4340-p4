# Final Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the EECS 4340 final-project report — a 14–16 page single-column-equivalent document covering design, implementation, testing, and evaluation of the team's P6 out-of-order RV32IM processor — first as a markdown draft, then migrated to IEEE-style two-column LaTeX.

**Architecture:** Per-section drafting tasks dispatched to Opus 4.7 subagents (per `spec.md` §9.1), with a single shared `draft.md` built incrementally. After all sections are drafted and self-reviewed, run a whole-draft `/humanizer` review pass, then migrate to LaTeX with TikZ-rendered figures.

**Tech Stack:**
- Markdown for drafting (`draft.md`)
- IEEE LaTeX template (two-column, `main.tex`, `refs.bib`)
- TikZ for block diagrams (Figures 1–4); WaveDrom JSON or `tikz-timing` for the timing diagram (Figure 5)
- Subagent dispatching: `model: opus` (writing tasks) per `spec.md` §9.1; `model: sonnet` is reserved for purely mechanical helper tasks
- `/humanizer` skill invoked during every drafting subagent and as a dedicated whole-draft review pass

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `doc/final-report/spec.md` | exists (`a35b992`) | Master spec — content per section, length, voice, source-material map |
| `doc/final-report/guideline.md` | exists (`a35b992`) | Writing-style policy (voice, composition, figure protocol, quick-checklist) |
| `doc/final-report/figure-guide.md` | exists (`a35b992`) | Per-figure rendering plan (boxes, arrows, layout, tool, caption) |
| `doc/final-report/plan.md` | this file | Executable plan — task list with subagent prompts |
| `doc/final-report/draft.md` | created in Task 1 | Single markdown draft, built section by section |
| `doc/final-report/main.tex` | created in Task 19 | IEEE-style two-column LaTeX |
| `doc/final-report/refs.bib` | created in Task 19 | BibTeX bibliography |
| `doc/final-report/figures/fig{1..4}.tex` | created in Tasks 20–23 | TikZ source for block diagrams |
| `doc/final-report/figures/fig5_timing.tex` | created in Task 24 | `tikz-timing` source for the ETB timing diagram |

The markdown draft is the canonical source until LaTeX migration starts (Phase 4). Don't dual-maintain.

---

## Shared subagent prompt template

Every drafting task in Phase 2 dispatches a subagent with the same shape. Defined once here; each task fills in the parameters.

```
[BRIEFING]

You are drafting a section of the EECS 4340 final-project report. The team built a synthesizable P6-style out-of-order RV32IM processor.

[REQUIRED READING — do this first]

1. doc/final-report/spec.md §5 entry for the section you are drafting (the content checklist).
2. doc/final-report/guideline.md (entire file — voice, composition rules, quick-checklist).
3. doc/final-report/spec.md §7 source-material map → the specific files listed for your section.
4. The current state of doc/final-report/draft.md so your section is consistent with everything written so far.

[YOUR TASK]

Draft section <SECTION_ID> ("<SECTION_TITLE>") by appending to doc/final-report/draft.md.

Length target: <LENGTH_TARGET> (soft; tighter is fine).

[VOICE AND DISCIPLINE — non-negotiable]

- Use the `humanizer` skill while writing. Run it during drafting, not only at review time. Apply its findings inline.
- Plain language, general technical reader (no EE/CE background assumed).
- Spell out acronyms on first use.
- Every design choice gets a `why` in the same paragraph.
- No cross-references to any internal doc (doc/project-overview.md, doc/advanced-features/*, doc/base-design/*, doc/weekly-reports/*, CLAUDE.md). The report stands alone.
- No claims of point values or grade weight.
- Be honest when a number cannot be cleanly attributed (see spec §3 of guideline.md).

[OUTPUT]

Write only the new section. Do not modify other sections in draft.md. Use the heading hierarchy already established.

[REPORT BACK]

When done: confirm the section was appended, name the figures or tables you stubbed (if any), and note any spec items you intentionally omitted with a one-line reason.
```

Per the spec, dispatch with `model: opus` (Opus 4.7).

---

## Phase 1 — Setup

### Task 1: Initialize the draft skeleton

**Files:**
- Create: `doc/final-report/draft.md`

- [x] **Step 1: Write the skeleton with section headers and figure/table placeholders** (done inline; commit `9c89a33`)

```markdown
# Out-of-Order RISC-V Processor — Final Project Report

EECS 4340, Spring 2026.

## Abstract

[ABSTRACT — drafted last, after §VII headline numbers are final.]

## I. Introduction

[TODO §I — drafted in Task 2.]

## II. Background and Constraints

[TODO §II — drafted in Task 3.]

## III. Pipeline Architecture

[FIGURE 1: Top-level pipeline block diagram. Stages + buses + the few sideband signals (early-tag, store_done).]

[TODO §III — drafted in Task 4.]

## IV. Base Implementation Details

[TODO §IV — drafted in Task 5. Inline OoO-issue demonstration code snippet at the end.]

## V. Advanced Features

[TABLE I: Spec-compliance feature mapping — 7 rows.]

[TODO §V opener — drafted in Task 6.]

### V.A. 2-way Superscalar

[TODO §V.A — drafted in Task 7.]

### V.B. Early Tag Broadcast

[FIGURE 5: Early-tag-broadcast timing.]

[TODO §V.B — drafted in Task 8.]

### V.C. Branch-Prediction Enhancements

[FIGURE 2: gshare + RAS branch predictor.]

[TODO §V.C — drafted in Task 9. Two leaves: gshare and RAS.]

### V.D. D-cache Enhancements

[FIGURE 3: D-cache organization.]

[TODO §V.D — drafted in Task 10. Two leaves: 2-way set-associative D-cache and next-line prefetch.]

### V.E. Store-to-Load Forwarding

[FIGURE 4: Store-to-load forwarding lanes.]

[TODO §V.E — drafted in Task 11.]

## VI. Verification and Testing Methodology

[TODO §VI — drafted in Task 12.]

## VII. Performance Evaluation and Analysis

[TABLE II: Per-program performance, representative subset.]

[TABLE III: Per-program performance, full 34-row continuation.]

[TABLE IV: Per-feature attribution.]

[TABLE V: Per-module synthesis slack.]

[TODO §VII — drafted in Task 13.]

## VIII. Discussion: Limitations and Future Work

[TODO §VIII — drafted in Task 14.]

## IX. Conclusion

[TODO §IX — drafted in Task 15.]

## References

[TODO references — drafted in Task 15.]
```

- [x] **Step 2: Commit** (commit `9c89a33`)

```bash
git add doc/final-report/draft.md doc/final-report/plan.md
git commit -m "scaffold final-report draft skeleton and plan"
```

---

## Phase 2 — Per-section drafting (sequential, Opus 4.7, with /humanizer)

Each task in this phase has the same shape:

1. Dispatch a subagent using the [shared prompt template](#shared-subagent-prompt-template) with the task-specific parameters.
2. Read the returned section in `draft.md`.
3. Run the guideline.md §5 quick checklist against it.
4. If checklist fails on any item: re-dispatch with corrective notes; if it passes, proceed.
5. User review checkpoint (per-section or per-cluster — user's call).
6. Commit.

The "Step" syntax below shows the dispatcher actions. The subagent's actual writing time is 5–15 minutes per section and is not a "step" in the bite-sized sense — it is the work the dispatched subagent performs.

### Task 2: Draft §I Introduction ✅ done (commits 2d2fa1b, db68499)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §I — drafted in Task 2.]`)

- [x] **Step 1: Dispatch the drafting subagent**

Use the Agent tool with `model: opus` and the shared prompt template, filling in:

- `<SECTION_ID>` = "I"
- `<SECTION_TITLE>` = "Introduction"
- `<LENGTH_TARGET>` = "~1 page (≈400–500 words)"

Plus this section-specific addendum at the end of the prompt:

```
[SECTION-SPECIFIC NOTES FOR §I]

Per spec §5 §I, this section has three parts in spirit (no need to number them):
1. What the processor does — RV32IM, runs the same programs as P3, but out-of-order. Why OoO at all.
2. What we built on top of the starter — list what came from the P3 starter (in-order pipeline, multiplier, I-cache, decoder skeleton) and what is the team's contribution (ROB, RS, RAT, LSQ, D-cache, branch predictor, advanced features). One sentence per milestone (1, 2, 3) for chronological grounding — but no separate Milestones section anywhere in the report.
3. Roadmap of the report — one or two sentences pointing the reader at §III, §V, §VII.

Source material: doc/project-overview.md §1, §3.
```

- [x] **Step 2: Read the returned section in `draft.md`**

- [x] **Step 3: Run the guideline §5 quick checklist** (spec reviewer + quality reviewer dispatched per skill)

- [x] **Step 4: Revisions** — milestone-attribution fix + roadmap trim (commit `db68499`)

- [x] **Step 5: Commit** — see commits `2d2fa1b` (initial draft) and `db68499` (fixes)

---

### Task 3: Draft §II Background and Constraints ✅ done (commits 5b0e17b, f0a6dac)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §II — drafted in Task 3.]`)

- [x] **Step 1: Dispatch with parameters**

- `<SECTION_ID>` = "II"
- `<SECTION_TITLE>` = "Background and Constraints"
- `<LENGTH_TARGET>` = "~0.75 page (≈300–400 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §II]

Per spec §5 §II:
1. Two short paragraphs explaining what "out-of-order" means in plain language. Use a tiny example: a load and an independent add — show in-order vs. out-of-order. Mention RAW, WAR, WAW hazards by name only (no deep treatment).
2. One-sentence component glossary (purpose, not implementation): ROB, RS, CDB, LSQ, branch predictor.
3. One short paragraph on the fixed spec constraints: 100 ns memory latency, 256 B I-cache + 256 B D-cache, single CDB at base width, multiplier from P2. Flag explicitly that these are spec constraints, not design choices — the report must say so so readers do not interpret them as bad calls.

No diagram in §II.

Source material: spec text in doc/project-description.md §4.1.
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §II background and constraints"
```

---

### Task 4: Draft §III Pipeline Architecture ✅ done (commits 46d255e + RAS fix)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §III — drafted in Task 4.]`)

- [x] **Step 1: Dispatch with parameters**

- `<SECTION_ID>` = "III"
- `<SECTION_TITLE>` = "Pipeline Architecture"
- `<LENGTH_TARGET>` = "~2 pages (≈800–1000 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §III]

Per spec §5 §III:
1. Top-level diagram + dataflow paragraph. The diagram is a placeholder ([FIGURE 1: ...]) — do NOT render it. Reference it in the prose as "Figure 1." Describe the dataflow in one paragraph: Fetch (PC + I-cache + branch predictor) → Decode → Dispatch (ROB + RS or LSQ) → Issue → Execute (2 ALUs, 1 pipelined MULT, branch resolver, D-cache) → CDB → Commit (regfile + mispredict check).
2. Pipeline stages, one paragraph each: Fetch, Decode, Dispatch/rename, Issue/execute, Commit. Highlight the single most distinctive design choice — there is no separate map table; the ROB *is* the physical register file (PHYS_REG_SZ = 32 + ROB_SZ). Memory ops bypass the RS and go to the LSQ.
3. One paragraph: why P6 over R10K. Embedded-RAT-in-ROB is simpler at a 1-wide base; R10K's free-list + map-table is more complex and the team did not need a unified physical register pool given the planned advanced-feature mix.

Do NOT enumerate the load-bearing implementation rules. Those belong in §IV.

Source material: doc/project-overview.md §4–6; verilog/pipeline.sv for the dataflow.
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §III pipeline architecture"
```

---

### Task 5: Draft §IV Base Implementation Details ✅ done (commits fb140f1, 531db85, plus polish)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §IV — drafted in Task 5. ...]`)

- [x] **Step 1: Dispatch with parameters**

- `<SECTION_ID>` = "IV"
- `<SECTION_TITLE>` = "Base Implementation Details"
- `<LENGTH_TARGET>` = "~1.5 pages (≈600–750 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §IV]

Per spec §5 §IV: six short paragraphs, one each:

1. ROB and rename. Embedded RAT, single dispatch_fire allocates ROB+RS in lockstep. The stale-RAT-clear-at-commit invariant (only clear if the RAT entry still points at the committing slot — younger renames must survive). The JAL/JALR commit-value override (CDB carries branch target; ROB overrides with NPC for any branch with non-zero rd, so the link register gets the return address rather than the branch target).
2. Reservation Station. Issue selector reads the *registered* src_ready, not the combinational bypass. Briefly tell the war story: a combinational bypass form created a feedback loop that froze the simulator on tight-loop programs (mult_no_lsq plus a dozen others). Fix: registered ready bits. The CDB-bypass mux still wires through to the issued entry's value, so correctness holds at the cost of one extra cycle when an operand arrives on the same cycle's CDB.
3. CDB priority and store sideband. Priority MULT > LSQ load > ALU. Stores never use the CDB — they signal completion through a sideband to the ROB; the LSQ entry releases to cache only at commit. Branches always broadcast on the CDB, but the PC redirect happens at *commit*, not at execute.
4. LSQ. FIFO, head-only access to the cache, holds store data until commit. Memory ops never enter the RS. Simplest design that satisfies the rubric's memory-ordering requirement.
5. D-cache (base). Write-back, write-allocate, byte-granular dirty/valid masks for sub-word stores, full-line writeback only.
6. Branch predictor (base). Bimodal 2-bit-counter table + BTB, redirects same cycle as fetch. Add a clarifying sentence: this is the rubric-required *base* predictor and is the comparison baseline for §V.C; the live final build replaces bimodal with gshare + RAS but keeps the BTB.

Then, **immediately at the end of §IV**, add the OoO-issue demonstration code (rubric requirement). One short snippet — a load followed by an independent add followed by a dependent add — and one or two sentences explaining how the RS lets the independent add issue before the load returns. Format the snippet as a fenced code block with `assembly` or `text` syntax; pick instructions short enough to fit cleanly. Use realistic RV32 mnemonics. The snippet is part of the section, not a separate appendix.

Source material:
- doc/base-design/base-design-verification.md
- doc/base-design/rs-issue-loop-fix.md
- doc/base-design/branch-predictor-report.md
- CLAUDE.md "Load-bearing rules" list (rules 1, 2, 3, 4, 5, 6 are in scope here)
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist** plus verify the OoO-issue snippet is present at the end
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §IV base implementation details"
```

---

### Task 6: Draft §V opener (introduction + spec-compliance table)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V opener — drafted in Task 6.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V (opener only)"
- `<SECTION_TITLE>` = "Advanced Features — opening"
- `<LENGTH_TARGET>` = "~0.5 page (≈200–250 words plus Table I)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V OPENER]

Per spec §5 §V: §V opens with the spec-compliance feature table so the grader can score the 17 advanced-feature points directly. Render the table inline (Table I) with these exact columns and rows:

| # | Feature | Spec category (§4.2) | Tier |
|---|---|---|---|
| 1 | 2-way superscalar | Superscalar execution | difficult |
| 2 | Early tag broadcast | Early tag broadcast (L7) | difficult |
| 3 | gshare predictor | Fetch — sophisticated branch predictors † | simpler |
| 4 | Return Address Stack | Fetch — return address stack | simpler |
| 5 | Store-to-load forwarding | Memory hier. — load/store forwarding | simpler |
| 6 | Next-line prefetch (stream buffer) | Memory hier. — prefetching † | simpler |
| 7 | 2-way set-associative D-cache | Memory hier. — associative caches † | simpler |

After the table, two short paragraphs:
- "That is 2 difficult + 5 simpler = 7 advanced features, satisfying the spec rule of at least one difficult plus other simpler features. Each is described in the subsections that follow."
- A one-paragraph framing of how each subsection is structured: every leaf opens with a plain-language statement of the *problem* it solves before introducing the design.

Do NOT write the leaf subsections — those are Tasks 7–11.

Source material: doc/advanced-features/feature-spec-verification.md §2.
```

- [ ] **Step 2: Read returned opener**
- [ ] **Step 3: Verify Table I renders cleanly and the framing paragraphs are present**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V opener with feature-mapping table"
```

---

### Task 7: Draft §V.A — 2-way Superscalar

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V.A — drafted in Task 7.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V.A"
- `<SECTION_TITLE>` = "2-way Superscalar"
- `<LENGTH_TARGET>` = "~0.75–1 page (≈300–400 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V.A]

Per spec §5 §V.A — Superscalar. Use the 4-part shape: Problem / Design / Tradeoffs / Result.

- Problem (plain language): a 1-wide pipeline retires at most one instruction per cycle; real programs often have stretches with two ready independent instructions; the single-issue ceiling becomes the bottleneck rather than underlying ILP.
- Design: 2-way fetch (two instructions per icache hit), 2-way decode, 2-way dispatch (allocate 2 ROB + 2 RS or LSQ entries in lockstep), 2 CDBs (rubric rule: ≤ superscalar width), 2-way commit. Single multiplier kept (the queue is in front, not behind it). LSQ stays single-port — only one memory op issues per cycle.
- Tradeoffs: more port logic everywhere; RS becomes 2-issue; ROB allocates and commits two slots per cycle; RAT handles same-cycle write-then-read. Synth area and slack pay for it. Single-port LSQ means two adjacent loads still serialize.
- Result: cite the geomean speedup figure on the 34-program suite from §VII; one sentence pointing at §VII for per-program detail. Do NOT tabulate numbers here.

Source material: doc/advanced-features/superscalar-report.md.
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V.A superscalar"
```

---

### Task 8: Draft §V.B — Early Tag Broadcast

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V.B — drafted in Task 8.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V.B"
- `<SECTION_TITLE>` = "Early Tag Broadcast"
- `<LENGTH_TARGET>` = "~0.75–1 page (≈300–400 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V.B]

Per spec §5 §V.B — ETB. Same Problem/Design/Tradeoffs/Result shape.

- Problem (plain language): a dependent of a multi-cycle multiply normally waits until the multiply's result broadcasts on the CDB before becoming eligible to issue. The multiplier's latency is fixed and known, so the dependent could wake up much earlier and be ready to issue the moment the value arrives.
- Design: when a producer enters MULT stage 0, its destination tag is broadcast on a dedicated "early-tag" sideband wire. RS entries matching that tag set their src_ready *for issue eligibility only*. The actual value still arrives later through the normal CDB bypass. A unit-test scenario in rs_test.sv guards against the early tag accidentally bypassing the value path through the issue selector — the registered-src_ready rule from §IV applies here.
- Tradeoffs: only works for FUs with deterministic, non-replay-able latency (MULT — not loads). Per-program win is gated on the second CDB existing (from §V.A) — without dual CDB, the dependent can't broadcast same-cycle as another consumer.
- Result: cite the per-program speedup numbers from §VII. From the ablation data (doc/advanced-features/per-feature-ablation.md), be honest: ETB's marginal contribution at the operating point (with all other features enabled) is small in geomean — about 0.10% across the 34-program suite — though the design is an example of how to wake up dependents on guaranteed-latency producers earlier than CDB broadcast allows. State this honestly per the guideline §5.

Reference Figure 5 (timing diagram) by name; do not draw it.

Source material:
- doc/advanced-features/early-tag-broadcast-report.md
- doc/advanced-features/per-feature-ablation.md
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist** plus verify the honest-scoping note about marginal contribution
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V.B early tag broadcast"
```

---

### Task 9: Draft §V.C — Branch-Prediction Enhancements (gshare + RAS)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V.C — drafted in Task 9. Two leaves: gshare and RAS.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V.C"
- `<SECTION_TITLE>` = "Branch-Prediction Enhancements"
- `<LENGTH_TARGET>` = "~1 page (≈400–500 words for both leaves combined)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V.C]

Per spec §5 §V.C. Structure:
- One short shared-parent paragraph: both gshare and RAS live in the same branch_predictor.sv module and share the GHR/BHT budget. They are presented together for that reason but counted as two separate advanced features.
- Then two leaves, each with the Problem/Design/Tradeoffs/Result shape:

V.C.1 — gshare:
- Problem: bimodal indexes the BHT by PC alone; two branches sharing PC index bits but with different patterns collide on the same counter and pollute each other's prediction.
- Design: index by PC[hi:lo] XOR GHR; GHR width = BHT index width; BHT has 64 entries.
- Tradeoffs: GHR width balances aliasing (too narrow → re-aliasing) vs. cold-start (too wide → slow specialization).
- Result: cite the per-program prediction-accuracy delta from §VII. From the ablation data, marginal contribution is small in geomean (~0.19%) but reaches +9.65% on fib_rec — call out that recursion-with-data-dependence programs benefit most.

V.C.2 — Return Address Stack:
- Problem: function returns are nearly 100% predictable as "go back where the matching call came from" but a generic indirect-branch predictor has to learn the target on every recursion frame and gets it wrong each time.
- Design: 16-entry stack pushed on JAL writing ra, popped on JALR x0,ra,0; overrides BTB on returns when non-empty.
- Tradeoffs: 16 entries deep is generous for the benchmark suite (deepest recursion observed is much smaller).
- Result: prediction-accuracy lift on recursion-heavy programs from §VII. Geomean marginal contribution from the ablation is ~0.10%; honest framing.

Reference Figure 2 by name; do not draw it.

Source material:
- doc/advanced-features/branch-predictor-advanced-report.md
- doc/advanced-features/per-feature-ablation.md
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**, verify both leaves are present, verify the honest-scoping notes
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V.C branch-prediction enhancements"
```

---

### Task 10: Draft §V.D — D-cache Enhancements (set-assoc + prefetch)

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V.D — drafted in Task 10. ...]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V.D"
- `<SECTION_TITLE>` = "D-cache Enhancements"
- `<LENGTH_TARGET>` = "~1 page (≈400–500 words for both leaves combined)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V.D]

Per spec §5 §V.D. Structure:
- Shared-parent paragraph: both features share the bus arbitration mask in pipeline.sv and the stream-buffer module is reused on the I-cache side as well as the D-cache.
- Two leaves with the Problem/Design/Tradeoffs/Result shape:

V.D.1 — 2-way Set-Associative D-cache:
- Problem: a direct-mapped 256 B D-cache has 32 sets; two arrays whose stride lands on the same set evict each other on every access even with plenty of cache space "available" elsewhere.
- Design: 16 sets × 2 ways with one LRU bit per set; victim-select on miss takes the LRU way.
- Tradeoffs: comparator + LRU bit per set; helps only when conflicts dominate.
- Result: hit-rate change from §VII. This feature is structural in the ablation methodology and not leave-one-out-ablate-able; its contribution is inferred analytically (note this honestly).

V.D.2 — Next-Line Prefetch / Stream Buffer:
- Problem: predictable sequential access (instruction fetch, array walks) wastes the 100 ns memory latency on every fresh line; a small stream buffer can fetch line+1 in the background.
- Design: one-line stream buffer between cache and memory; issues line+1 after a miss completes; on a subsequent miss whose target line is sitting in the stream buffer, the line transfers into the cache instantly. Same module reused on the I-cache side.
- Tradeoffs: one extra request on the bus per miss; helps only when access is predictable. Bus arbitration: dcache > icache (demand) > stream buffer.
- Result: this is the dominant feature in the ablation data — geomean marginal contribution +38.57%, with mytest +95.31% as the largest single-program effect. Almost the entire 39.28% gap from the all-advanced-disabled floor is attributable to prefetch. Cite this directly; it is the most striking finding in §VII.

Reference Figure 3 by name; do not draw it.

Source material:
- doc/advanced-features/dcache-advanced-report.md
- doc/advanced-features/per-feature-ablation.md
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist** plus verify the prefetch-dominance result is stated cleanly
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V.D dcache enhancements"
```

---

### Task 11: Draft §V.E — Store-to-Load Forwarding

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §V.E — drafted in Task 11.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "V.E"
- `<SECTION_TITLE>` = "Store-to-Load Forwarding"
- `<LENGTH_TARGET>` = "~0.75 page (≈250–350 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §V.E]

Per spec §5 §V.E. Problem/Design/Tradeoffs/Result:

- Problem: a load that follows an in-flight store of the same address would otherwise wait for the store to commit and the cache to absorb the write before reading the value — many cycles for what should logically be a register-to-register move.
- Design: at the LSQ head, the load's address is compared against the addresses of older un-committed stores; on a clean match (same address, full byte-cover, store data already known) the load completes in one cycle with the store's data — no D-cache access. Partial overlap (e.g., word load over byte store) does not forward; the load stalls until the store commits.
- Tradeoffs: the verify-merged-features pass deferred the forwarded value by one cycle relative to the original implementation — a tiny perf cost (mergesort: 200,072 → 200,073 cycles) bought a large synth slack improvement (−504 ps → −244 ps). Mention this as a deliberate timing-vs-IPC tradeoff.
- Result: per-program speedup on STLF-hitting programs from §VII. From the ablation data, geomean marginal contribution is small (~0.20%); insertionsort sees the largest individual effect (+1.64%). Be honest about scale.

Reference Figure 4 by name; do not draw it.

Source material:
- doc/advanced-features/stlf-report.md
- doc/advanced-features/per-feature-ablation.md
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §V.E store-to-load forwarding"
```

---

### Task 12: Draft §VI Verification and Testing Methodology

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §VI — drafted in Task 12.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "VI"
- `<SECTION_TITLE>` = "Verification and Testing Methodology"
- `<LENGTH_TARGET>` = "~1.5 pages (≈600–750 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §VI]

Per spec §5 §VI. The rubric weights testing at 20%; this section needs to clearly demonstrate methodology, not just claim correctness.

Six paragraphs (one each):
1. Three-layer test pyramid: unit testbenches → full-pipeline RTL on 34 programs → synthesized-netlist re-run. Each layer catches a different class of bug.
2. Unit tests, RTL. Modules covered: mult, rob, rs, lsq, dcache, icache, branch_predictor. Plain-language description of what each scenario set covers (ROB tests cover dispatch, CDB completion, in-order commit, same-cycle RAT bypass, stale-clear protection, the x0 guard, flush, full detection, wraparound). Specifically call out that the RS suite includes a guard scenario protecting the early-tag-broadcast invariant (early tag must not bypass the issue selector combinationally) — this is exactly the kind of testing-methodology evidence the rubric asks for.
3. Unit tests, synthesized netlist. Wrapper modules (synth/<m>_svsim.sv) bridge unpacked-array port shapes that DC flattens into packed buses. The branch_predictor test was rewritten when bimodal was replaced with gshare — TB-side gshare model + colliding-PC selection in Test 7 to preserve the saturate-then-flip semantic under XOR indexing. One full paragraph because methodology matters.
4. Full-pipeline regression on 34 programs. Pass criterion: clean halt on `@@@ System halted on WFI instruction` plus correct writeback file. `make simulate_all` and `make simulate_all_syn`. All 34 pass on both layers. Suite spans toy programs, kernel-style code, and a CNN forward pass.
5. Architectural-divergence sign-off. Every .syn.wb byte-matches its .wb counterpart (RTL=netlist parity), and the post-merge .wb byte-matches the same commit rebuilt under +define+SERIALIZE_BRANCHES (OoO front-end = serialized front-end parity). Two layers of byte-level equivalence. Strongest "we did not break the ISA" claim the harness can make.
6. A/B configuration knobs for ablation. Compile-time +define knobs that disable individual advanced features: DISABLE_EARLY_TAG, DISABLE_GSHARE, DISABLE_RAS, DISABLE_STLF, DISABLE_PREFETCH. Used to generate the per-feature attribution data presented in §VII. State that two features (2-way superscalar, 2-way set-assoc D-cache) are structural and excluded from leave-one-out; their contribution is inferred analytically.

Source material:
- doc/advanced-features/advanced-features-merge-report.md §2–6, §10
- doc/advanced-features/feature-spec-verification.md
- doc/advanced-features/per-feature-ablation.md (methodology section)
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §VI verification and testing methodology"
```

---

### Task 13: Draft §VII Performance Evaluation and Analysis

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §VII — drafted in Task 13.]`)

This is the highest-leverage section: 30% of the grade is decided by it.

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "VII"
- `<SECTION_TITLE>` = "Performance Evaluation and Analysis"
- `<LENGTH_TARGET>` = "~2.5 pages (≈1000–1300 words plus four tables)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §VII]

Per spec §5 §VII. This is the analysis section the rubric weights heaviest. Render four tables (II, III, IV, V) inline and write the prose around them.

Subsections / paragraphs:

1. Methodology. How CPI is computed (cycles / dynamic_instr_count from the harness). Two baselines used: the full-feature build ("all on") and the all-advanced-disabled build ("OoO base"; reachable by setting DISABLE_EARLY_TAG + DISABLE_GSHARE + DISABLE_RAS + DISABLE_STLF + DISABLE_PREFETCH together). Per-feature attribution uses leave-one-out at the all-on configuration — measures *marginal* contribution at the operating point, which is what speedup claims should mean.

2. Table II — per-program performance, representative subset (~10 rows). Pick programs spanning the speedup range: include alexnet (best case), mytest (largest prefetch-dominated swing), median programs, and one or two worst-case rows. Columns: cycles_OoO_base, cycles_all_on, Δ%, CPI_all_on, branch_acc_all_on. Geomean and arithmetic-mean rows at the bottom.

3. Table III — per-program performance, full 34-row continuation. Inline (not appendix; the report is standalone). In LaTeX it may need \small font; in markdown render with the same column set, possibly trimmed.

4. Headline finding paragraph. Geomean cycle reduction across the suite (vs. OoO-base), geomean CPI, geomean branch-prediction-accuracy lift. One short paragraph stating the numbers plainly.

5. Per-feature attribution. Render Table IV with rows = features (ETB, gshare, RAS, STLF, prefetch — the five leave-one-out features) and analytical entries for superscalar + set-assoc, columns = geomean Δcycles%, programs where the feature dominates, source (ablation vs. analytical). Numbers come from doc/advanced-features/per-feature-ablation.md. The headline of this paragraph: prefetch dominates the marginal contribution (geomean +38.57% when disabled; mytest +95.31%); ETB, gshare, RAS, STLF each contribute 0.10–0.20% in geomean. The five together account for 39.28% — almost identical to the all-five-off result (98%+ explained by prefetch alone). State this as the central honest finding; the rubric explicitly rewards measuring honestly. Note that superscalar and 2-way set-assoc are structurally inseparable from the build and their contribution is inferred (CPI < 1.0 on ILP-rich code; D-cache hit-rate analysis respectively).

6. Branch-prediction analysis paragraph. Per-program accuracy. Programs where RAS contributes most (recursion-heavy: backtrack, fib_rec). Programs where gshare's pattern correlation matters most. Programs where the bimodal baseline already does well so neither helps much.

7. Cache analysis paragraph. D-cache hit rate before vs after associativity + prefetch where the harness exposes it. If not, fall back to per-program cycle reduction as a proxy and say so.

8. Synth slack summary. Render Table V with per-module rows: mult +0.23 ps, lsq +0.05 ps, dcache +19.28 ps, rs +229.79 ps, rob +282.83 ps, icache +448.51 ps, branch_predictor +570.88 ps — all met. Then full-pipeline synth/pipeline.vg honestly: worst slack −244.54 ps on lsq_0/head_reg[1] → mult_0/mstage[0]/product_sum_reg[*]; three endpoints violate; functionally bit-equivalent (every .syn.wb byte-matches .wb across all 34 programs). Static-timing reporting concern, not a correctness one.

Source material:
- doc/advanced-features/per-feature-ablation.md (PRIMARY — the ablation table is the bulk of Tables II–IV)
- doc/advanced-features/branch-accuracy-cpi-diff.md (branch-accuracy data, supplemental)
- doc/advanced-features/advanced-features-merge-report.md §3, §11 (synth slack summary)
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**, verify all four tables are present, verify the prefetch-dominance finding is stated cleanly and honestly
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §VII performance evaluation and analysis"
```

---

### Task 14: Draft §VIII Discussion: Limitations and Future Work

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §VIII — drafted in Task 14.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "VIII"
- `<SECTION_TITLE>` = "Discussion: Limitations and Future Work"
- `<LENGTH_TARGET>` = "~0.5 page (≈200–250 words)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §VIII]

Per spec §5 §VIII. Short, honest, factual. Three or four short paragraphs:

- Closing the −244 ps timing miss. Two known options: register load_complete_value at the LSQ output (one extra cycle on every load); split MULT stage 0 (one extra cycle on every multiply). Both deferred — cost-vs-payoff did not justify the rebuild against a working system.
- Single-port LSQ on a 2-way machine. Two adjacent loads still serialize. Natural next step: dual-ported LSQ + dual-ported D-cache (or banked).
- Single MULT FU on a 2-way machine. Caps IPC on multiply-heavy code. ETB recovers some of this; a second MULT FU would do better.
- mult_no_lsq history: one sentence — milestone-2 mult_no_lsq froze deterministically near cycle 2192; landing the LSQ closed the gap. Engineering-honesty data point.
- One sentence on what the team would revisit: a unified physical register pool (R10K-style) if widening past 2-way.
- Optional one-sentence reflection on the ablation finding: that prefetch carried most of the per-feature speedup is itself a useful design lesson — the simpler features paid off less than expected when stacked on top of an already-tuned base.

Source material: CLAUDE.md "Currently broken / known-stale" + "Recently fixed" sections.
```

- [ ] **Step 2: Read returned section**
- [ ] **Step 3: Run guideline §5 checklist**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §VIII limitations and future work"
```

---

### Task 15: Draft §IX Conclusion + References

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[TODO §IX — drafted in Task 15.]` and `[TODO references — drafted in Task 15.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "IX + References"
- `<SECTION_TITLE>` = "Conclusion and References"
- `<LENGTH_TARGET>` = "~0.5 page total (Conclusion ~0.25 page, References ~0.25 page)"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR §IX + REFERENCES]

§IX Conclusion: one paragraph. State plainly:
- What the team built: a synthesizable P6 OoO RV32IM processor with seven advanced features layered on the in-order P3 starter.
- That all 34 test programs pass on both RTL and synthesized netlist with byte-identical writeback parity.
- The headline number from §VII (cite verbatim).
- The one honest limitation: the −244 ps full-pipeline static-timing miss, with the netlist functionally bit-equivalent to the RTL.

References (5–8 entries): IEEE-style numbered list. Include:
- Hennessy & Patterson, Computer Architecture: A Quantitative Approach (cite §3.6, §3.8, §3.9, §3.12 in the prose by section).
- McFarling, "Combining Branch Predictors," 1993, WRL Technical Note TN-36.
- Course lecture references where the spec uses them (L5, L7, L9, L10).
- VeriSimpleV starter / RV32IM ISA spec (whichever version the course points to).

Cite each reference at least once in the prose somewhere in the report (a draft pass over the existing sections should add the [N] citations where appropriate; if no opportunity, the reference is unnecessary and should be removed).
```

- [ ] **Step 2: Read returned conclusion + references**
- [ ] **Step 3: Run guideline §5 checklist** plus verify each reference is cited at least once in the prose**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report §IX conclusion and references"
```

---

## Phase 3 — Whole-draft review and abstract

### Task 16: Whole-draft `/humanizer` pass

**Files:**
- Modify: `doc/final-report/draft.md` (apply humanizer findings inline)

- [ ] **Step 1: Dispatch the humanizer subagent**

Use the Agent tool with `model: opus`. Prompt:

```
You are doing the whole-draft humanizer review pass on the EECS 4340 final-project report.

[REQUIRED]
1. Read doc/final-report/draft.md in full.
2. Read doc/final-report/guideline.md (voice rules).
3. Invoke the `humanizer` skill against the entire draft.
4. Apply the humanizer's findings inline to draft.md. Treat findings as required edits, not advisory.

The skill flags AI-writing tells: inflated symbolism, promotional language, em-dash overuse, rule-of-three, AI-vocabulary words, vague attributions, passive voice, negative parallelisms, filler phrases. Edit until none remain.

[CONSTRAINTS]
- Do not change the meaning or any numerical claim.
- Do not add or remove sections.
- Do not introduce cross-references to internal doc/ files.
- Preserve all figure and table placeholders verbatim.

[REPORT BACK]
List the categories of edits applied (e.g., "removed 14 em dashes; rewrote 6 negative parallelisms"). Confirm no findings remain on a final pass.
```

- [ ] **Step 2: Read the cleaned draft**

Spot-check 2–3 sections; confirm no semantic changes and no introduced cross-references.

- [ ] **Step 3: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "humanize final-report draft (whole-draft pass)"
```

### Task 17: User review checkpoint

- [ ] **Step 1: Notify the user the draft is ready for full read-through**

State plainly: "Markdown draft of the final report is complete and humanized at `doc/final-report/draft.md`. Please read end-to-end and request any changes before we draft the abstract and migrate to LaTeX."

- [ ] **Step 2: Wait for user response**

This is a hard gate. Do not proceed to Task 18 until the user explicitly approves.

- [ ] **Step 3: Apply any revisions the user requests**

If revisions are needed, dispatch a focused subagent (Opus 4.7, with humanizer skill) for each revision. Re-run the per-section guideline checklist on changed sections. Commit per revision.

### Task 18: Draft the Abstract

**Files:**
- Modify: `doc/final-report/draft.md` (replace `[ABSTRACT — drafted last, after §VII headline numbers are final.]`)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

- `<SECTION_ID>` = "Abstract"
- `<SECTION_TITLE>` = "Abstract"
- `<LENGTH_TARGET>` = "exactly one paragraph, ~150 words"

Section-specific addendum:

```
[SECTION-SPECIFIC NOTES FOR THE ABSTRACT]

Read the completed draft.md first to extract the actual final headline numbers. Do not invent.

Must state, in one paragraph:
- P6 OoO RV32IM design built on the P3 in-order starter.
- One-instruction base width.
- Seven advanced features (enumerate by name in one clause): 2-way superscalar, early tag broadcast, gshare, return address stack, store-to-load forwarding, next-line prefetch, 2-way set-associative D-cache.
- All 34 test programs pass on RTL and synthesized netlist with byte-identical writeback parity.
- One-line headline numbers from §VII (geomean cycle reduction, branch-prediction accuracy, geomean CPI). Quote verbatim from the body.
- One honest limitation reference (the static-timing miss).

The abstract is the only place where the entire report is condensed — every word must earn its keep. Use the humanizer skill while writing.
```

- [ ] **Step 2: Read returned abstract**
- [ ] **Step 3: Verify headline numbers match §VII**
- [ ] **Step 4: Revisions if needed**
- [ ] **Step 5: Commit**

```bash
git add doc/final-report/draft.md
git commit -m "draft final-report abstract"
```

---

## Phase 4 — LaTeX migration

### Task 19: Set up the IEEE LaTeX skeleton

**Files:**
- Create: `doc/final-report/main.tex`
- Create: `doc/final-report/refs.bib`
- Create: `doc/final-report/figures/` (directory)

- [ ] **Step 1: Create the IEEE-style two-column LaTeX skeleton**

Write `doc/final-report/main.tex` with:

```latex
\documentclass[conference]{IEEEtran}
\IEEEoverridecommandlockouts

\usepackage{cite}
\usepackage{amsmath,amssymb,amsfonts}
\usepackage{algorithmic}
\usepackage{graphicx}
\usepackage{textcomp}
\usepackage{xcolor}
\usepackage{booktabs}
\usepackage{tikz}
\usepackage{tikz-timing}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, fit}

\begin{document}

\title{Out-of-Order RISC-V Processor: Design, Implementation, and Evaluation}

\author{
\IEEEauthorblockN{[Team member names]}
\IEEEauthorblockA{EECS 4340, Spring 2026 \\ Columbia University}
}

\maketitle

\begin{abstract}
% [Paste from draft.md §Abstract after Task 18]
\end{abstract}

\section{Introduction}
% [Paste from draft.md §I]

\section{Background and Constraints}
% [Paste from draft.md §II]

\section{Pipeline Architecture}
% [Paste from draft.md §III]

\begin{figure}[t]
  \centering
  \input{figures/fig1_pipeline}
  \caption{Top-level pipeline. Fetch and commit are in-order; issue and execute are out-of-order. The Reorder Buffer doubles as the physical register file, and a single Common Data Bus is the only result-broadcast network in the base configuration.}
  \label{fig:pipeline}
\end{figure}

\section{Base Implementation Details}
% [Paste from draft.md §IV]

\section{Advanced Features}
% [Paste from draft.md §V opener and subsections]

\begin{figure}[t]
  \centering
  \input{figures/fig5_timing}
  \caption{Early Tag Broadcast timing.}
  \label{fig:etb}
\end{figure}

\begin{figure}[t]
  \centering
  \input{figures/fig2_predictor}
  \caption{Branch predictor combining gshare with a 16-entry Return Address Stack.}
  \label{fig:predictor}
\end{figure}

\begin{figure}[t]
  \centering
  \input{figures/fig3_dcache}
  \caption{Two-way set-associative D-cache with one-line stream buffer.}
  \label{fig:dcache}
\end{figure}

\begin{figure}[t]
  \centering
  \input{figures/fig4_stlf}
  \caption{Store-to-load forwarding.}
  \label{fig:stlf}
\end{figure}

\section{Verification and Testing Methodology}
% [Paste from draft.md §VI]

\section{Performance Evaluation and Analysis}
% [Paste from draft.md §VII; tables become \begin{table}...\end{table}]

\section{Discussion: Limitations and Future Work}
% [Paste from draft.md §VIII]

\section{Conclusion}
% [Paste from draft.md §IX]

\bibliographystyle{IEEEtran}
\bibliography{refs}

\end{document}
```

- [ ] **Step 2: Create `refs.bib` with the references identified in Task 15**

Translate the prose reference list from draft.md into BibTeX entries (one `@book` for H&P, `@techreport` for McFarling, etc.). Use stable, citeable keys (`hennessy2017`, `mcfarling1993`, etc.).

- [ ] **Step 3: Create `doc/final-report/figures/` directory**

```bash
mkdir -p doc/final-report/figures
```

- [ ] **Step 4: Commit**

```bash
git add doc/final-report/main.tex doc/final-report/refs.bib doc/final-report/figures/.gitkeep
git commit -m "scaffold IEEE LaTeX skeleton for final report"
```

### Task 20: Render Figure 1 (top-level pipeline block diagram)

**Files:**
- Create: `doc/final-report/figures/fig1_pipeline.tex`

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

Use Agent tool with `model: opus`. Prompt:

```
Render Figure 1 (Top-level pipeline block diagram) as a TikZ source file.

[REQUIRED READING]
1. doc/final-report/figure-guide.md — entry "Figure 1 — Top-level pipeline block diagram". This entry lists every box, named arrow, layout hint, annotation, and caption draft you need.
2. doc/final-report/main.tex — the figure is included as `\input{figures/fig1_pipeline}`; the surrounding `\begin{figure}` and `\caption` already exist there.

[OUTPUT]
Write doc/final-report/figures/fig1_pipeline.tex. Do not include `\documentclass`, `\begin{figure}`, or `\caption` — only the TikZ picture itself, starting with `\begin{tikzpicture}` and ending with `\end{tikzpicture}`.

[STYLE]
- Two-column-figure width: target a TikZ picture that fits roughly 8 cm wide. Use `\resizebox{\columnwidth}{!}{...}` if needed in the wrapping `\input` (do not add it inside this file).
- Monochrome with one accent: use a dashed line style for the early-tag and store-done sidebands. No color.
- Labels in `\small` font.

[VALIDATION]
After writing, ensure the file compiles inside the existing main.tex skeleton: run `pdflatex doc/final-report/main.tex` from the repo root and confirm no compile error mentioning `fig1_pipeline.tex`. If main.tex is not yet ready to compile end-to-end, just check that the TikZ syntax is well-formed (matched braces, no undefined macros).
```

- [ ] **Step 2: Verify the file compiles cleanly inside main.tex** (or syntactically if main.tex is incomplete)
- [ ] **Step 3: Commit**

```bash
git add doc/final-report/figures/fig1_pipeline.tex
git commit -m "render figure 1: top-level pipeline block diagram"
```

### Task 21: Render Figure 2 (gshare + RAS branch predictor)

**Files:**
- Create: `doc/final-report/figures/fig2_predictor.tex`

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete) (same template as Task 20, swap "Figure 1" → "Figure 2", `fig1_pipeline.tex` → `fig2_predictor.tex`, point at the figure-guide.md entry "Figure 2 — gshare + RAS branch predictor")
- [ ] **Step 2: Verify compile**
- [ ] **Step 3: Commit**

```bash
git add doc/final-report/figures/fig2_predictor.tex
git commit -m "render figure 2: gshare + RAS branch predictor"
```

### Task 22: Render Figure 3 (D-cache organization)

**Files:**
- Create: `doc/final-report/figures/fig3_dcache.tex`

- [ ] **Step 1: Dispatch** (template as above, point at "Figure 3 — D-cache organization")
- [ ] **Step 2: Verify compile**
- [ ] **Step 3: Commit**

```bash
git add doc/final-report/figures/fig3_dcache.tex
git commit -m "render figure 3: dcache organization"
```

### Task 23: Render Figure 4 (store-to-load forwarding lanes)

**Files:**
- Create: `doc/final-report/figures/fig4_stlf.tex`

- [ ] **Step 1: Dispatch** (template as above, point at "Figure 4 — Store-to-load forwarding lanes")
- [ ] **Step 2: Verify compile**
- [ ] **Step 3: Commit**

```bash
git add doc/final-report/figures/fig4_stlf.tex
git commit -m "render figure 4: store-to-load forwarding lanes"
```

### Task 24: Render Figure 5 (early-tag-broadcast timing)

**Files:**
- Create: `doc/final-report/figures/fig5_timing.tex`

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

Same template as Task 20, but flag that this is a *timing* diagram, not a block diagram.

```
[ADDITIONAL NOTES FOR FIGURE 5]

Use the `tikz-timing` LaTeX package (already loaded in main.tex). The figure-guide.md entry "Figure 5 — Early-tag-broadcast timing" lists every signal, the cycle-by-cycle pulse pattern, and the annotations.

If `tikz-timing` proves awkward, fall back to a hand-built TikZ waveform using rectangular pulses on a horizontal time axis. Either is acceptable. Do not import an external SVG.
```

- [ ] **Step 2: Verify compile**
- [ ] **Step 3: Commit**

```bash
git add doc/final-report/figures/fig5_timing.tex
git commit -m "render figure 5: early-tag-broadcast timing"
```

### Task 25: Migrate prose to LaTeX

**Files:**
- Modify: `doc/final-report/main.tex` (fill in all `% [Paste from draft.md ...]` placeholders)

- [x] **Step 1: Dispatch with parameters** (all Phase-2 drafting complete)

Use Agent tool with `model: opus`. Prompt:

```
Migrate the markdown draft of the final-project report into the existing IEEE LaTeX skeleton.

[REQUIRED READING]
1. doc/final-report/draft.md — source content for every section.
2. doc/final-report/main.tex — the skeleton already has placeholders (`% [Paste from draft.md §X]`) marking where each section goes.
3. doc/final-report/figure-guide.md — for table column-width considerations during conversion.
4. doc/final-report/guideline.md — voice rules; the migration must preserve them.

[YOUR TASK]
Replace each placeholder in main.tex with the corresponding LaTeX-formatted content from draft.md. Conversion rules:
- Markdown `**bold**` → `\textbf{...}`
- Markdown `*italic*` or `_italic_` → `\emph{...}`
- Markdown inline `` `code` `` → `\texttt{...}`
- Markdown fenced code blocks → `\begin{verbatim}...\end{verbatim}` for the OoO-issue snippet in §IV
- Markdown tables → `\begin{table}[t] \centering \caption{...} \label{...} \begin{tabular}{...} \toprule ... \bottomrule \end{tabular} \end{table}`. Use `booktabs` rules. For the long Table III, use `\small` to fit the column width; consider `\begin{table*}` for full-width spanning if needed.
- Markdown emphasis on field labels (e.g., `*Problem:*`) → `\emph{Problem:}` inline.
- Inline math is unlikely; keep prose plain.

[CONSTRAINTS]
- Do not edit prose for content. This is a typesetting task, not a rewriting task.
- If a paragraph in draft.md needs a small wording adjustment for column-width fit (e.g., breaking a long line), invoke the `humanizer` skill on the paragraph after adjustment to confirm the rewording does not introduce AI-writing tells.
- Confirm `\cite{...}` keys match entries in refs.bib.

[VALIDATION]
After writing, run `pdflatex doc/final-report/main.tex` twice (for cross-references) and `bibtex doc/final-report/main` between the two runs. Confirm no `Undefined reference`, no `Citation undefined`, no overfull boxes wider than 5pt. Report any unresolved warnings.

[REPORT BACK]
- Confirm all placeholders are filled.
- Report final compiled page count.
- List any wording adjustments made for column-width fit (per humanizer rule above).
```

- [ ] **Step 2: Compile and verify**

Run:

```bash
cd doc/final-report
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

Confirm no errors. Note any warnings.

- [ ] **Step 3: Commit**

```bash
git add doc/final-report/main.tex
git commit -m "migrate final-report draft to IEEE LaTeX"
```

### Task 26: Final review

**Files:**
- Modify: `doc/final-report/main.tex` (fixes from review)

- [ ] **Step 1: Page-count check**

Open the compiled PDF. Confirm page count is within 10–20 pages (spec target). Two-column equivalent should land near 10–12 pages of content.

- [ ] **Step 2: Figure rendering review**

Open each figure in the compiled PDF. Confirm each renders as the figure-guide.md caption describes. Check legibility of labels at print size.

- [ ] **Step 3: Reference list review**

Confirm every `\cite{key}` resolves, every entry in refs.bib is cited at least once, citations are formatted IEEE-style.

- [ ] **Step 4: Final humanizer pass on any prose changed during migration**

If Task 25's report listed wording adjustments, dispatch one more humanizer subagent (Opus 4.7) over those specific paragraphs only.

- [ ] **Step 5: Spot-check the abstract**

Re-read the abstract in the compiled PDF. Confirm headline numbers still match §VII.

- [ ] **Step 6: Commit final-version PDF (optional, depending on team policy)**

If the team's policy is to commit the compiled artifact:

```bash
git add doc/final-report/main.pdf
git commit -m "commit compiled final-report PDF"
```

Otherwise leave the PDF untracked (it rebuilds from source).

---

## Self-review against the spec

Done while writing; recording for the record.

**Spec coverage:**
- §1 Purpose and audience: covered by the implicit audience-note in every drafting task and by the guideline §5 checklist.
- §2 Length: each drafting task carries an explicit length target.
- §3 Voice and source-material: enforced by the shared subagent prompt template ("REQUIRED READING" item 2 + 3 and "VOICE AND DISCIPLINE" block).
- §4 Top-level structure: Tasks 2–15 cover every numbered section.
- §5 Section-by-section content: each task has a section-specific addendum mirroring spec §5's content checklist for that section.
- §6 Figures and tables: Figures rendered in Tasks 20–24; Table I rendered as part of Task 6 (§V opener); Tables II–V rendered as part of Task 13 (§VII).
- §7 Source-material map: each section task names the specific source-material files in the addendum.
- §8 Out-of-scope: enforced by the prompt template's "VOICE AND DISCIPLINE" block (no cross-references, no point-value claims, no separate Milestones section).
- §9 Workflow: Task 16 (whole-draft humanizer), Task 17 (user review), Task 18 (abstract last), Task 25 (LaTeX migration), Task 26 (final review with second humanizer pass) — all covered.

**Placeholder scan:** No "TBD," no "implement later," no untyped "similar to Task N" without repeating the parameters. All subagent prompts contain the actual content the engineer needs.

**Type consistency:** The `<SECTION_ID>`, `<SECTION_TITLE>`, `<LENGTH_TARGET>` parameter names are consistent across all per-section drafting tasks. File names (`fig1_pipeline.tex`, `fig2_predictor.tex`, etc.) match between the LaTeX skeleton in Task 19 and the per-figure tasks in 20–24.
