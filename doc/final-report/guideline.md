# Final Report — Writing Guideline

Style and composition rules for the EECS 4340 final report. Companion files: `spec.md` (structure and content per section) and `figure-guide.md` (per-figure rendering plan).

## 1. Voice and tone

Write the report in plain, accessible language. The target audience is a general technical reader who may not have a background in Electrical Engineering, Computer Engineering, FPGA design, embedded systems, or low-level hardware/software development.

Make the explanation easy to understand for a general technical reader. Avoid unnecessary jargon, and explain required technical terms when they first appear. Spell out acronyms before using them (ROB on first use → "Reorder Buffer (ROB)").

The writing does not need to be extremely technical or explain every implementation detail. Keep the report approachable and focused on the main ideas, design decisions, and project outcomes. Readers who want exact implementation details, low-level behavior, or specific code logic can refer to the codebase directly.

Focus on clarity, context, and reasoning. Do not only describe what was implemented; also explain *why* each part is needed, what problem it solves, and how it contributes to the overall project.

Use short paragraphs, clear section headings, and smooth transitions. Prefer simple, direct sentences over overly formal or academic wording.

The final writing should be technically accurate but approachable, so that a reader with no EE/CE background can still understand the project's purpose, design, implementation, and results.

## 2. Composition rules

These are the structural commitments from the brainstorming pass. They apply across every section of the report.

### 2.1 Problem-first openers for every advanced feature

Every leaf subsection in §V (the seven advanced-feature subsections) opens with a single short paragraph that answers, in plain language: *what problem does this feature solve?* No design detail, no Verilog references — just the motivation a general reader would need to care about what comes next.

Only after the problem paragraph do we introduce the design, the tradeoffs, and the result. Same shape every time so the reader builds a rhythm.

### 2.2 Standalone document, no cross-references

The report does not reference internal docs (`doc/project-overview.md`, `doc/advanced-features/*`, `doc/base-design/*`, `doc/weekly-reports/*`, etc.). Every fact, number, table, and figure carried by the report must be self-contained inside the report itself.

Internal docs remain in-tree as engineer-facing companions and are valuable as **source material** when drafting (the source-material map is in `spec.md` §7). Reusing paragraphs verbatim from them is discouraged because they are written for engineers, not the general technical reader.

The report does not contain phrases like "see `advanced-features-merge-report.md` for details" or "as documented in CLAUDE.md." If a fact is worth carrying, it goes in the report; if it is not, it does not need a pointer.

### 2.3 Why-not-just-what

This is the central voice rule from §1, restated as a composition check: every paragraph that describes a design choice should also state the reason. *"We use a single CDB"* is incomplete; *"We use a single CDB because the spec caps CDB count at the superscalar width and our base design is one-wide"* is complete.

When the *why* is the spec ("memory latency is fixed at 100 ns") versus a design choice ("we picked write-back over write-through"), name which it is. Spec constraints are not design choices; conflating them invites the reader to think we made bad calls.

### 2.4 Honest scoping

When the report cannot cleanly attribute a number or measure a quantity, say so. The rubric explicitly rewards honest measurement over uncritical claims:

> *"your grade won't suffer from showing us that something is actually a bad idea. What we want to see is that you can measure how good or bad the idea/feature was."* — `doc/project-description.md` §1.5

This applies in §VII (per-feature attribution: superscalar and 2-way set-assoc D-cache are structurally inseparable from the build, and we say so) and in §VIII (the −797.58 ps full-pipeline slack miss: own it, name the residual cone, and name why the next retune was deferred).

### 2.5 No claims of point values

The report enumerates the seven advanced features and their spec categories (§V opening table). It does not claim "this is worth N points" — point assignment is the grader's job.

### 2.6 Length is a soft target

The page budget in `spec.md` §4 is recommendation, not contract. Tighter is fine. Meaningfully longer is not.

## 3. Figures and tables

### 3.1 Markdown-draft phase

Use placeholder syntax in the markdown draft so figure work doesn't block writing:

```
[FIGURE 1: Top-level pipeline block diagram. Stages + buses + sidebands.]
```

Tables are drafted in markdown using GFM table syntax. They migrate to LaTeX `tabular` cleanly.

### 3.2 LaTeX-migration phase

Each figure has a per-figure rendering plan in `figure-guide.md`. The plan lists boxes, arrows, layout hint, and tool suggestion (TikZ for block diagrams, WaveDrom JSON for the timing diagram).

Color discipline: monochrome with at most one accent (e.g., dashed lines for sideband signals). The report renders fine on grayscale.

### 3.3 Captions

One short sentence stating what the figure shows. Optional second sentence highlighting the interesting bit. Do not start with "Diagram of …" or "Figure showing …".

## 4. Rubric-tracking

For reference while drafting. Not all sections of the report carry equal grade weight; allocate energy and word count proportionally:

| Rubric line | Weight | Section that carries it |
|---|---|---|
| Base features | 23% | §III + §IV |
| Correctness and testing | 20% | §VI |
| Performance | 20% | §VII |
| Advanced features | 17% | §V |
| Analysis | 10% | §VII (mostly), §V "Result" paragraphs |
| Documentation | 7% | the entire report; voice and clarity |
| Milestones | 3% | one sentence in §I |

§VII is the highest-leverage section: 30% of the grade is decided by it. It gets ~2.5 pages, the largest section after §V.

## 5. Quick checklist before declaring a section done

- [ ] Plain-language opener (problem-first for §V leaves; framing-first for others).
- [ ] Acronyms spelled out on first use; technical terms explained.
- [ ] No cross-references to internal `doc/` files.
- [ ] Every design choice has a *why* in the same paragraph.
- [ ] Honest about what wasn't measured or didn't work.
- [ ] No claims of point values.
- [ ] Figure placeholders use `[FIGURE N: caption]` syntax.
- [ ] Length within the rough budget in `spec.md` §4.
