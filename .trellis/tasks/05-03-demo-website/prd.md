# Interactive Demo Website — Design Spec

**Date:** 2026-05-03
**Author:** brainstorm session, nyavana + claude
**Target deploy:** Vercel (production), via `vercel deploy --prod` from `web/`
**Status:** spec — awaiting user approval before implementation

---

## 1. Goal

Build a public-facing, statically-deployed interactive website that demonstrates the
EECS 4340 final project — a synthesizable P6-style out-of-order RV32IM processor — so a
visitor (TA, classmate, recruiter, anyone curious) can understand the design's scope,
function, results, and trade-offs without reading the 20-page report.

The site is the *presentation* surface for work that's already done. The codebase is
final, all 33 test programs pass, the report is written, and the numbers are fixed. This
project does not modify any RTL.

## 2. Non-goals

- No live RTL execution in the browser. (Considered and rejected as scope creep.)
- No backend, no database, no API routes. Fully static export.
- No tests for the website itself beyond manual QA + Lighthouse before deploy.
- No mobile-first design for the pipeline visualizer. Visualizer is desktop-only;
  mobile shows a "view on a wider screen" panel and static screenshots.
- No automated CI for the site in v1. Manual `vercel deploy --prod`.

## 3. Site map

Three statically-rendered routes:

1. **`/` (landing).** Hero with headline numbers, interactive architecture diagram,
   abbreviated results, feature pills. Single scroll, ~5 sections.
2. **`/simulator`.** Cycle-by-cycle pipeline visualizer playing back pre-captured
   RTL traces of 3 programs.
3. **`/deep-dive`.** Long-form report content with native React SVG figures, Recharts
   charts, and a sticky table-of-contents.

Persistent top nav: project name + 3 route links + GitHub link.

## 4. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Framework | Next.js 15 (App Router) | Vercel-native, zero deploy config |
| Language | TypeScript (strict) | |
| UI runtime | React 19 | |
| Styling | Tailwind CSS v4 | Palette tokens from `doc/web/color/color_palette_guidance.md`, deviations allowed |
| Charts | Recharts | Bar charts, histograms, accessibility-friendly |
| Animation | Framer Motion | Hero polish, panel transitions, pipeline pill movement |
| Diagrams | Hand-rolled inline SVG | No D3/diagram library |
| Static figures | Native React SVG components | Re-drawn from RTL ground truth, *not* from existing TikZ |
| Trace data | Pre-captured JSON, fetched at runtime on `/simulator` | |
| Backend | None | Static export to Vercel CDN |
| Lint/format | ESLint (Next preset) + Prettier | |
| Package manager | npm | |
| Analytics | Vercel Analytics (opt-in) | Free tier |

## 5. Folder structure

```
web/
├── app/
│   ├── layout.tsx              # nav + footer
│   ├── page.tsx                # /
│   ├── simulator/page.tsx      # /simulator
│   ├── deep-dive/page.tsx      # /deep-dive
│   └── globals.css             # Tailwind base + design tokens
├── components/
│   ├── nav/
│   ├── landing/                # hero, headline-numbers, feature-pills
│   ├── architecture/           # ArchDiagram.tsx (interactive landing SVG)
│   ├── diagrams/               # 5 React SVG figures
│   ├── simulator/              # PipelineLanes, RobTable, RsTable, LsqTable, Scrubber, EventCaption
│   └── ui/                     # buttons, cards, side-panel
├── lib/
│   ├── architecture.ts         # MODULES array — landing diagram content
│   ├── results.ts              # Table II + III + branch-acc + CPI data
│   ├── features.ts             # 7 advanced features metadata
│   └── trace.ts                # trace-loading helpers + TypeScript types
├── public/
│   ├── traces/                 # parallel.json, mult_no_lsq.json, fib_rec.json
│   └── 4340-final-report.pdf   # rendered from doc/final-report/main.tex once at build prep
├── tools/
│   └── capture_trace.py        # runs on lab PC; excluded from deploy bundle
├── package.json
├── tsconfig.json
├── tailwind.config.ts
├── next.config.ts
├── vercel.json
└── README.md
```

The whole site lives under `web/`. Repo root is unchanged except for this folder.

## 6. Landing page (`/`)

### 6.1 Hero
Hero band with: project name ("Out-of-Order RV32IM Processor — EECS 4340 Spring 2026"),
one-sentence elevator pitch ("A synthesizable 2-way superscalar P6-style out-of-order
RISC-V processor in SystemVerilog"), four headline number cards, and a primary CTA
("Open the simulator").

**Headline numbers:**
- 33/33 programs pass on RTL + synthesized netlist
- −27.46% geomean cycle reduction (OoO base → all-on)
- 74.03% geomean branch prediction accuracy (+8.87 pp over bimodal arith. mean)
- −797.58 ps slack at 1000 ps target (functional bit-equivalent on all 33 programs)

### 6.2 Interactive architecture diagram

Wide SVG (≈1200×600) of the pipeline:

```
[Fetch (2-wide) + I-cache + Stream Buffer + Branch Predictor]
      ↓
[Decode (2-wide)]
      ↓
[Dispatch ─── ROB (alloc 2/cycle, RAT inside)]
   ↓ ↓
   ↓ └────────────┐
   ↓              ↓
[RS (2-wide issue)]  [LSQ (FIFO, head-only)]
   ↓                     ↓
   ├─► [ALU0]            ├─► [D-cache (2-way) + Stream Buffer]
   ├─► [ALU1]            ↓
   ├─► [MULT (5-stage, ETB)]
   └─► [Branch resolver]
      ↓
[CDB (2 slots, MULT > LD > ALU)]
      ↓
[Commit (2-wide) → Arch RegFile]
```

**Interaction:**
- Hover: box lifts (shadow + plum border), connected arrows glow.
- Click: side panel slides in from right with module name, one-paragraph description,
  parameter values from `verilog/sys_defs.svh`, file path, "View on GitHub" link.
- Toggle "Show advanced features": 7 advanced features highlighted in their host
  modules (ETB on MULT, gshare+RAS on predictor, STLF on LSQ, etc.). Each highlight
  is clickable → routes to that feature's section in `/deep-dive`.
- Mobile: vertical accordion of cards, each expanding inline.

**Content source:** `lib/architecture.ts` — typed `MODULES` array.

### 6.3 Abbreviated results

One Recharts bar chart: per-program Δ% sorted ascending (biggest speedups first).
Color-coded: plum/iris for speedups, orchid for the two regressions.

### 6.4 Feature pills

Seven cards, one per advanced feature. Each card: name, one-line description, the
"marginal Δ% when disabled" number, link to its full subsection in `/deep-dive`.

### 6.5 Footer

Small footer with team names, course/year, GitHub repo link, and a "View report (PDF)"
link.

## 7. `/simulator` page

### 7.1 Layout

Full-viewport, desktop-only:

- **Top half:** horizontal pipeline-flow diagram. Six lanes left → right:
  `Fetch | Decode | RS / LSQ | Exec (ALU0, ALU1, MULT, BR, MEM) | CDB | Commit`.
  Each in-flight instruction is a small pill colored by its ROB tag. Pills animate
  between snapshots via Framer Motion.
- **Right side panel:** three live tables stacked — ROB, RS, LSQ. Each row updates
  per cycle. Currently-committing entry highlighted plum.
- **Bottom strip:**
  - Program selector (parallel / mult_no_lsq / fib_rec)
  - Cycle counter + total cycles
  - Scrubber (slider over the cycle range)
  - Play / pause / step-back / step-forward / "jump to next event"
  - Speed (1× / 4× / 16×)
  - "Why this cycle matters" caption (visible only on event-flagged cycles)

### 7.2 Trace JSON shape

Per-cycle snapshots stored as an array. Schema:

```ts
interface CycleSnapshot {
  cycle: number;
  pc: number;
  fetch:    InstrRef[];                 // up to 2
  decode:   InstrRef[];                 // up to 2
  rob:      RobEntry[];                 // ROB_SZ entries
  rs:       RsEntry[];                  // RS_SZ entries
  lsq:      LsqEntry[];                 // LSQ_SZ entries
  exec:     ExecState;                  // alu0, alu1, mult_stage_n, branch, lsq_head
  cdb:      CdbSlot[];                  // up to 2
  commit:   InstrRef[];                 // up to 2
  events:   string[];                   // 'mispredict', 'etb_wakeup:tag=5', 'flush'
}
```

Full TypeScript types in `lib/trace.ts`.

### 7.3 Programs

Three pre-captured traces, in order of pedagogical value:

1. **`parallel.s`** (~2,300 cycles) — short, deliberately constructed for ILP demo.
2. **`mult_no_lsq.s`** (~2,200 cycles) — exercises the multiplier; ETB visible.
3. **`fib_rec.s`** (~29,000 cycles) — recursion; scrubber default opens on a
   ~200-cycle window centered on the first detected event in the trace
   (mispredict, ETB wakeup, or flush — whichever appears first). Full trace is
   still scrubbable end-to-end. Shows RAS + branch mispredict + flush.

Programs are configurable in `lib/trace.ts` — adding a new one is one entry +
one JSON file.

### 7.4 Out of scope (v1)

- Branch predictor internals (BHT/BTB/RAS state) — not visualized.
- D-cache contents — not visualized.
- Real-time editing of programs — out of scope.
- MULT pipeline shown as a single box with "stage N/5" label rather than as five
  separate stages — legibility over fidelity.

## 8. `/deep-dive` page

Single-page scroll with sticky table-of-contents on the left (desktop). Sections:

1. Headline numbers strip (mirrors landing).
2. Per-feature ablation chart (horizontal bars from Table III).
3. Architecture overview — `<PipelineOverviewDiagram />` + 2-3 paragraphs.
4. Seven advanced-feature subsections, each with: problem statement,
   relevant native React SVG diagram (where applicable), design summary,
   measured number + worst-case program callout.
5. Per-program speedup chart (Recharts bars over Table II).
6. Branch accuracy lift chart (bimodal vs all-on, sorted by lift).
7. CPI distribution histogram with geomean (14.87) and arith. mean (20.77) markers.
8. Synthesis & timing — critical-path explainer (LSQ → RS → ALU adder →
   ROB/LSQ), the two fix options, why we ship as-is.
9. Verification methodology — three-layer harness, two byte-equivalence checks.
10. Limitations & future work — single-port LSQ, single MULT, why R10K
    rename style would be next at 4-wide.
11. References + team + report-PDF link.

### 8.1 Native React SVG figures (5)

All redrawn from RTL ground truth, **not** from the existing TikZ files in
`doc/final-report/figures/`. Each implementing subagent reads the relevant
`verilog/<module>.sv` and cross-references with the report; if RTL and report
disagree, RTL wins, with the disagreement flagged as a comment.

| Figure | Component | Source RTL |
|---|---|---|
| Pipeline overview | `PipelineOverviewDiagram` | `verilog/pipeline.sv` |
| Branch predictor | `BranchPredictorDiagram` | `verilog/branch_predictor.sv` |
| D-cache | `DCacheDiagram` | `verilog/dcache.sv` |
| STLF | `STLFDiagram` | `verilog/lsq.sv` |
| ETB timing | `ETBDiagram` | `verilog/mult.sv`, `verilog/pipeline.sv` |

Style: plum strokes for boxes, iris blue for arrows, orchid pink for highlighted
elements (early-tag wire, RAS override path). Snow Mist background. Inter font.
Each component is ~150-300 lines.

### 8.2 Data sources

All chart data lives in `lib/results.ts` as typed const arrays (Table II per-program,
Table III ablation, branch-acc per-program, CPI per-program). Single source of truth.

## 9. Color & visual style

Starting palette from `doc/web/color/color_palette_guidance.md`:
plum `#77295D`, orchid `#C34FA2`, snow `#EDF1FD`, sky `#77B7F0`, iris `#5364C0`.

The palette is a *reference*, not a contract — adjustments allowed where readability,
chart distinguishability, or accessibility require them. Specifically:
- Charts may need a sixth color for the seventh feature category.
- Critical errors / regressions stay in a conventional red (not in the palette) per
  the palette guide's accessibility section.

Inter font family throughout (already set up via `next/font`).

## 10. Data capture (lab-PC workflow)

Three steps, executed once on the lab PC, copy-pasted into the user's terminal:

```sh
module load vcs verdi synopsys-synth
python3 web/tools/capture_trace.py parallel
python3 web/tools/capture_trace.py mult_no_lsq
python3 web/tools/capture_trace.py fib_rec
ls -lh web/public/traces/
# tar czf traces.tgz web/public/traces/  # send back to dev machine
```

`capture_trace.py` does:
1. `make <prog>.out` to generate `output/<prog>.ppln` and `output/<prog>.out`.
2. Parse `.ppln` (after reading `verilog/pipeline.sv`'s `$display` calls to know
   the format).
3. Parse `.wb` for committed register writes.
4. Detect events (mispredict, ETB, flush) by diffing snapshot deltas.
5. Write `web/public/traces/<prog>.json` (≤ ~5 MB; downsample if larger).

**Fallback path:** if `.ppln` is absent or in an unexpected format, the script
parses `.out` only and produces a commit-stream-only trace. The visualizer still
runs (commit lane + ROB pop animation) but loses the in-flight RS/ROB state. Both
code paths are written so the lab-PC trip is robust.

## 11. Deployment

Vercel CLI from `web/`:

```sh
npm install -g vercel
vercel login
vercel link              # one-time
vercel deploy            # preview deploy
vercel deploy --prod     # production
```

`vercel.json` is minimal — `framework: nextjs`, no build overrides. Vercel auto-detects
the Next.js setup and handles edge caching, image optimization, and CDN delivery.

## 12. Acceptance criteria

The website ships when all of these hold:

- [ ] All three routes (`/`, `/simulator`, `/deep-dive`) render without errors in
      Chrome and Firefox at 1280×800 and 1920×1080.
- [ ] Lighthouse Performance ≥ 90, Accessibility ≥ 95, SEO ≥ 90 on the landing page.
- [ ] All 7 advanced features have a section in `/deep-dive` with a measured number,
      and each links from the landing-page feature pill.
- [ ] All 33 programs have a Δ% bar in the landing chart and the deep-dive chart;
      hover tooltip shows cycles_OoO_base, cycles_all_on, CPI, branch acc.
- [ ] All 5 native React SVG figures render correctly and match their RTL ground truth.
- [ ] Pipeline visualizer plays at least one program (parallel.s) end-to-end with
      visible animation. ROB / RS / LSQ tables update each cycle.
- [ ] Scrubber, play/pause, step, jump-to-next-event, and speed controls all work.
- [ ] Site is deployed to Vercel production at a stable URL.
- [ ] No console errors or React warnings in any route.

## 13. Implementation discipline

Per user request: implementation work is dispatched to subagents (Agent tool), not
done sequentially in the main thread. Independent units of work (scaffolding,
each diagram, each page, the capture script) run in parallel where they have no
shared state.

The implementation plan itself is generated by the `superpowers:writing-plans` skill
after this spec is approved.

## 14. Out of scope (explicit)

- Live RTL execution / interpreter in the browser
- Editable assembly / "play with your own program"
- Branch predictor and D-cache internal-state visualizations
- Mobile-first responsive design for the simulator
- Automated CI auto-deploy
- Tests for the website code
- SEO landing pages per advanced feature
- Internationalization

These are explicit non-goals for v1. Any of them could be a v2 add later.
