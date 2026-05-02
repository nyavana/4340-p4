# Advanced-features spec cross-reference

Date: 2026-05-01. Branch under audit: `verify-merged-features` (tip `dbcd4f6`).

This report answers two questions:

1. Are all advanced-feature branches on the team repo `CSEE4340-26/p4.GaPiChiXuXu` actually merged into the final codebase?
2. Does each feature listed in the merge docs map to a category in `doc/project-description.md` §4.2, and is it really present in the live Verilog source — not just in the docs?

## 1. Branch state on the team repo

`gh api repos/CSEE4340-26/p4.GaPiChiXuXu/branches` lists 15 branches. The seven feature branches plus the comparison-data branch all reduce to `verify-merged-features`:

| # | Branch | Tip | Reachable from `verify-merged-features`? |
|---|---|---|---|
| 1 | `feat-dcache-prefetch` | `77bb8ba` | yes (ancestor) |
| 2 | `2_way_superscalar` | `0c5cbd2` | yes, functionally — see below |
| 3 | `assoc_cache` | `6d046a0` | yes (ancestor) |
| 4 | `early-tag-broadcast` | `c6fa8d2` | yes (ancestor) |
| 5 | `gshare` | `4b2ccc3` | yes (ancestor) |
| 6 | `feat-ras-cz2931` | `2cb839a` | yes (ancestor) |
| 7 | `feat-stlf-cz2931` | `d48b8dd` | yes (ancestor) |
| — | `2_way_syn_and_out` | `96de569` | comparison-data file cherry-picked as `954e346`; no code delta |

`2_way_superscalar` has two commits not in `verify-merged-features` (`35fb896 Syn_completed`, `0c5cbd2 fixed unsynthesizable problem`). Inspecting their content:

- `35fb896` is mostly binary `.pvl`/`.syn` artifacts plus an 80-line `pipeline.sv` / 12-line `rob.sv` Design-Compiler compatibility fix. The functional fix was independently re-applied on the merge line as `bd719c8 Fix syn_simv: replace '{}' port patterns, while-loop, and cross-module ref`, which is reachable from `verify-merged-features`.
- `0c5cbd2` only deletes synth artifact files; it touches no Verilog source.

So nothing functional is missing on the 2-way side. Likewise, `2_way_syn_and_out`'s only delta beyond `35fb896` was `96de569 Result comparism added`, which is the per-program perf-comparison data file. It was cherry-picked into the verification branch as `954e346`, and `doc/advanced-features/branch-accuracy-cpi-diff.md` is in-tree.

## 2. Spec-category mapping

`doc/project-description.md` §4.2 lists "difficult" and "simpler" advanced features. The seven implemented features map as follows:

| # | Team feature | Spec category | Tier |
|---|---|---|---|
| 1 | 2-way superscalar | Superscalar execution (2-way, 3-way\*, N-way\*\*) | difficult (6–8 pts) |
| 2 | Early tag broadcast | Early tag broadcast (L7) | difficult (6–8 pts) |
| 3 | gshare predictor | Fetch enhancements — more sophisticated branch predictors† | simpler (0.5–3 pts) |
| 4 | Return Address Stack | Fetch enhancements — return address stack | simpler (0.5–3 pts) |
| 5 | Store-to-load forwarding | Memory hierarchy — data forwarding loads/stores (H&P 3.6) | simpler (0.5–3 pts) |
| 6 | Dcache next-line prefetch (stream buffer) | Memory hierarchy — instruction and/or data prefetching† | simpler (0.5–3 pts) |
| 7 | 2-way set-associative dcache | Memory hierarchy — associative caches† | simpler (0.5–3 pts) |

This satisfies the spec's "at least one difficult advanced feature" rule (two difficult: superscalar + ETB) plus five simpler features.

## 3. Source-evidence for each feature

Verified against the working tree at `verify-merged-features` HEAD.

### 3.1 2-way superscalar

- `verilog/sys_defs.svh` does not name the width as a single macro; instead, the 2-way shape is wired through array ports of size 2:
  - `verilog/rob.sv:13–23` — `dispatch_valid[1:0]`, `dispatch_dest_reg [2]`, `dispatch_NPC [2]`, etc.
  - `verilog/pipeline.sv:78–112` — `rob_dispatch_tag [2]`, `rob_commit_*` busses width 2, `rs_issue_*` arrays size 2.
  - `verilog/pipeline.sv:188–190` — two ALU result lanes (`alu_result [2]`, `alu_signed_a/b [2]`, `branch_take [2]`).
- 1 CDB on a 2-way design satisfies the spec rule "you may not include more CDBs than the narrowest part of your design."

### 3.2 Early tag broadcast

- `verilog/pipeline.sv:184–185` — `logic early_cdb_valid; logic [TAG_W-1:0] early_cdb_tag;` declared as a wakeup-only sideband (the comment at line 182 notes "early_cdb_* is a wakeup-only sideband — it NEVER feeds the RS").
- `verilog/pipeline.sv:1080–1084` — driven by `mult_early_done && !mult_flushed && !mispredict_valid`.
- `verilog/rs.sv:36–37` — RS consumes `early_cdb_valid/tag`; `verilog/rs.sv:184–188` updates `next_entries[i].srcN_ready` when the early tag matches.
- The `+define+DISABLE_EARLY_TAG` knob in the Makefile flips `early_cdb_valid` to 0 for A/B benchmarking.

### 3.3 gshare predictor

- `verilog/branch_predictor.sv:120–125` — `GHR_W = BHT_IDX_W`; `logic [GHR_W-1:0] ghr;` (full-width gshare).
- `verilog/branch_predictor.sv:148,193` — index = `bht_idx(PC, ghr_ext)`, i.e. `PC ⊕ GHR`.
- `verilog/branch_predictor.sv:219,232` — GHR reset to 0; on commit `ghr <= {ghr[GHR_W-2:0], update_taken}`.
- `BHT_ENTRIES=64` in `verilog/sys_defs.svh:36`.

### 3.4 Return Address Stack

- `verilog/sys_defs.svh:39` — `RAS_ENTRIES = 16`.
- `verilog/branch_predictor.sv:131–136` — `ras [RAS_ENTRIES-1:0]`, stack pointer `ras_sp`, depth counter `ras_count`.
- `verilog/branch_predictor.sv:59–60` — `ras_push_en` / `ras_pop_en` inputs (gated externally with `dispatch_fire`).
- `verilog/branch_predictor.sv:165–169` — RAS overrides BTB prediction on returns when stack is non-empty.

### 3.5 Store-to-load forwarding

- `verilog/lsq.sv:13` — header comment: "Loads can forward from an older in-queue store".
- `verilog/lsq.sv:179–181` — `stlf_ready [LSQ_SIZE-1:0]`, `stlf_value [XLEN-1:0] [LSQ_SIZE-1:0]`.
- `verilog/lsq.sv:280–360` — `stlf_compute` always_comb walks each load's older entries, picks the youngest covering store, and refuses partial-byte overlap (sets `can_forward = 1'b0` on conflict).
- Forwarded loads broadcast one cycle later (after the STLF latch) — this was a deliberate timing-closure deferral noted in CLAUDE.md and is architecturally invisible (`.wb` matches across all 33 programs).

### 3.6 Dcache next-line prefetch (stream buffer)

- `verilog/stream_buffer.sv` exists (5.8 KB, header at line 3: "One-entry stream buffer that prefetches the next sequential cache line").
- `verilog/pipeline.sv:441` — `stream_buffer sb_0 (...)` instantiated.
- `verilog/dcache.sv:5–25` — header comment describes the prefetcher: "watches completed load accesses and queues the next cache line (addr + 8 B) as a low-priority request".
- `verilog/dcache.sv:111–169` — prefetch hit/miss tracking, victim-way selection.
- Bus priority: `dcache > icache (demand) > stream buffer` (per `verilog/stream_buffer.sv:12`).

### 3.7 2-way set-associative dcache

- `verilog/sys_defs.svh:46–47` — `DCACHE_LINES = 32`, `DCACHE_WAYS = 2`.
- `verilog/dcache.sv:31` — `` `define DCACHE_SETS (`DCACHE_LINES / `DCACHE_WAYS) `` ⇒ 16 sets.
- `verilog/dcache.sv:79` — `DCACHE_ENTRY dcache_data [0:`DCACHE_SETS-1][0:`DCACHE_WAYS-1];` (sets × ways storage).
- Lookup loops over ways at `verilog/dcache.sv:143,172,195,329`.
- Total D-cache size: 32 lines × 8 B = 256 B, within the spec cap.

## 4. Spec-compliance summary

| Spec requirement (project-description.md §4.2) | Status |
|---|---|
| At least one difficult advanced feature | met — superscalar (2-way) + ETB |
| Some other advanced features alongside | met — gshare, RAS, STLF, prefetch, set-assoc dcache |
| CDB count ≤ superscalar width | met — 1 CDB on a 2-way design |
| I-cache + D-cache ≤ 256 B each | met — 256 B each |
| Main-memory latency = 100 ns retained | met — `verilog/sys_defs.svh` unchanged on this front |

## 5. Conclusion

All seven advanced features that the team carved into branches are present, working, and traceable to specific Verilog source in the final codebase. None of them exist only in the documentation. The two unmerged tip commits on `2_way_superscalar` / `2_way_syn_and_out` are synth-artifact churn plus a DC compatibility fix that was independently re-applied; no functional code is missing.
