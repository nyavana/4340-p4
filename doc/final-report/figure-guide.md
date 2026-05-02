# Final Report — Figure Rendering Guide

Per-figure plan for the LaTeX-migration phase. Each entry is self-contained: boxes, arrows, layout hint, suggested tool, and a caption draft. The goal is that an LLM in a separate session can render each figure without re-reading `verilog/`.

The markdown draft uses `[FIGURE N: caption]` placeholders. This guide is consulted only during LaTeX migration.

**General rendering policy:**
- Default tool: **TikZ** for block diagrams, **WaveDrom JSON** for timing diagrams. Both compile inline in IEEE-style LaTeX.
- Fallback: draw.io / Inkscape → SVG, then `\includegraphics` after `pdf2svg`.
- Color discipline: monochrome with at most one accent (e.g., dashed lines for sideband signals). No rainbows. The report renders fine on grayscale.
- Caption: one short sentence stating what the figure shows, plus one optional second sentence highlighting the interesting bit. No "Diagram of ..." starts.

---

## Figure 1 — Top-level pipeline block diagram

**Section:** §III, immediately after the dataflow paragraph.

**Layout:** Left-to-right. Five vertical bands corresponding to pipeline stages: Fetch, Decode, Dispatch/Rename, Issue/Execute, Commit. Buses run horizontally between bands.

**Boxes (left to right):**

- *Fetch band:* `PC reg`, `I-cache`, `branch predictor` (single box; internals are Figure 2). Stream buffer attached as a smaller box behind the I-cache.
- *Decode band:* `decoder` (single box).
- *Dispatch band:* `ROB / RAT` (single block — the embedded RAT lives inside the ROB), `RS`, `LSQ`. ROB sits central; RS and LSQ flank it.
- *Issue/Execute band:* `ALU 0`, `ALU 1`, `MULT (pipelined, N stages)`, `Branch resolver`, `D-cache`. MULT shown as a single elongated box labelled "MULT (pipelined)".
- *Commit band:* `Regfile`.

**Buses (named arrows):**

- PC bus: `PC reg → I-cache`, `PC reg → branch predictor`.
- Instruction bus: `I-cache → decoder → ROB/RAT + RS + LSQ` (split at dispatch).
- CDB: single bus crossing from Issue/Execute back to RS, ROB, and LSQ. Label "CDB (tag, value, valid)".
- Early-tag sideband: dashed wire from MULT to RS. Label "early-tag (wakeup only)". This is the single most distinctive sideband and should be visually distinct.
- Store-done sideband: dashed wire from D-cache to ROB. Label "store_done (no value)".
- Mispredict redirect: arrow from ROB back to PC reg. Label "mispredict_target". Drawn as a long curved feedback arrow above the bands.

**Annotations:**

- "1 CDB at base width (= superscalar width)" near the CDB.
- "ROB *is* the physical register file (PHYS_REG_SZ = 32 + ROB_SZ)" near the ROB box.
- "memory ops bypass the RS" near the dispatch fork to LSQ.

**What to leave out:** clocks, resets, individual byte lanes, internal MULT stages, regfile read ports.

**Caption draft:** *"Top-level pipeline. Fetch and commit are in-order; issue and execute are out-of-order. The Reorder Buffer doubles as the physical register file, and a single Common Data Bus is the only result-broadcast network in the base configuration."*

---

## Figure 2 — gshare + RAS branch predictor

**Section:** §V.C.

**Layout:** Top-down. Inputs at top (PC, update_valid, update_taken, predict_is_return), outputs at bottom (pred_taken, pred_target).

**Boxes:**

- *Input row:* `PC` (predict-side), `update_PC`, `update_taken`, `predict_is_return`.
- *Index logic:* `bht_idx() = PC[hi:lo] ⊕ GHR` (drawn as a small XOR gate fed by PC bits and GHR), `btb_idx() = PC[hi:lo]` (no XOR).
- *State storage:* `BHT (64 × 2-bit counter)`, `BTB (32 entries: valid, tag, target, is_uncond)`, `GHR (shift register, GHR_W bits)`, `RAS (16 entries, sp + count)`.
- *Decision block:* `MUX` selecting between BTB-derived prediction and RAS-derived prediction.

**Arrows:**

- `PC → btb_idx → BTB lookup → btb_pred_{valid,taken,target,is_uncond}`.
- `PC → bht_idx (XOR with GHR) → BHT lookup → counter[1] → btb_pred_taken`.
- `predict_is_return → AND with ras_count != 0 → ras_override`.
- `RAS top → MUX (when ras_override)`.
- BTB-derived prediction → MUX (otherwise).
- MUX → output `pred_taken`, `pred_target`.
- *Update path (drawn lighter):* `update_taken` → BHT counter saturating ±1; `update_PC + target` → BTB write; on commit: `GHR ← {GHR[GHR_W-2:0], update_taken}`.

**Annotations:**

- "GHR_W = BHT_IDX_W (full-width gshare)".
- "RAS depth 16; pushed on JAL writing ra; popped on JALR x0,ra,0".
- "saturating counter: 2'b00…2'b11; reset to 2'b01".

**Caption draft:** *"Branch predictor combining gshare with a 16-entry Return Address Stack. The RAS overrides the BTB on returns; gshare's XOR of PC with the global history register de-aliases counters that bimodal would share."*

---

## Figure 3 — D-cache organization

**Section:** §V.D.

**Layout:** Left-to-right. Address on the left, data flow to the right. Stream buffer drawn below the cache as a parallel path to memory.

**Boxes:**

- *Address fields:* `address` decomposed into `tag | set_idx | block_offset`. Show widths.
- *Cache storage:* `dcache_data[SETS][WAYS]` rendered as a 2D grid (16 sets × 2 ways). Each cell = (tag, valid bits, dirty bits, data).
- *Comparators:* one per way, fed by tag bits and the stored tag of the corresponding way. Output: `way_hit[w]`.
- *LRU bit:* one per set; updated on hit; selects victim on miss.
- *Hit mux:* selects data from the hitting way.
- *Sub-word logic:* byte-mask AND with valid/dirty masks; full-line writeback only.
- *Writeback buffer:* one entry, drives the bus on eviction of a dirty line.
- *Stream buffer:* one-line FIFO + control FSM, between cache and memory bus. Receives prefetch requests after misses; serves hits-in-stream-buffer instantly.

**Arrows:**

- `address → tag, set_idx, offset`.
- `set_idx → way 0 + way 1 storage row`.
- `way[i].tag → comparator[i] ← tag`.
- `way_hit[*] → hit mux → data out`.
- `miss → request to memory bus`; on completion, `populate way (LRU pick)` and `arm stream buffer for line+1`.
- `subsequent miss matches stream buffer → line transfer to cache without bus traffic`.
- `dirty eviction → writeback buffer → bus`.

**Annotations:**

- "256 B total = 16 sets × 2 ways × 8 B".
- "write-back, write-allocate, byte-granular dirty/valid masks".
- "stream buffer reused on the I-cache (not shown)".

**Caption draft:** *"Two-way set-associative D-cache with one-line stream buffer. The stream buffer arms after every demand miss and absorbs sequential line-walks without round-tripping to memory."*

---

## Figure 4 — Store-to-load forwarding lanes

**Section:** §V.E.

**Layout:** Left-to-right. LSQ as a circular buffer on the left; forwarding logic in the middle; CDB on the right.

**Boxes:**

- *LSQ entries:* drawn as a row of slots with `head` and `tail` pointers. Slots show `is_store` flag, `addr_valid`, `data_ready`, byte mask. One representative load slot mid-queue, two store slots older than it.
- *Per-load forwarding cone:*
    - Address comparator: compares load address (line-granularity, `addr[XLEN-1:3]`) against each older store.
    - Byte-mask intersect: AND of load mask with store mask. Three outcomes drawn: full cover (forward), partial overlap (block), no overlap (skip).
    - Source select: youngest covering store wins (drawn with priority encoder symbol).
- *Forwarding latch:* the +1-cycle defer added by the verify-merged-features pass. Drawn as a flip-flop on the path between forwarding cone and CDB.
- *CDB output port:* one of the broadcast lanes from the CDB.

**Arrows:**

- `load_addr → comparators` (drawn as fanout to each older store).
- `match + full byte cover + store data ready → forward valid`.
- `forward valid → latch → CDB broadcast (cycle later)`.
- "Block" path drawn as a stalled-edge with the load waiting on the cache.

**Annotations:**

- "+1 cycle defer added for synth slack (one-cycle-deferred broadcast; standalone slack contribution unverified after the build-artefacts re-baseline — see merge report §10.3)".
- "partial overlap blocks; load falls through to D-cache".

**Caption draft:** *"Store-to-load forwarding. A load at the LSQ head compares against older un-committed stores; a clean byte-cover match forwards the value through a one-cycle latch onto the CDB."*

---

## Figure 5 — Early-tag-broadcast timing

**Section:** §V.B.

**Layout:** Waveform diagram, cycles 0–9 along x-axis, signals along y-axis. **Use WaveDrom JSON.**

**Signals (top to bottom):**

- `clock` — square wave.
- `mult_busy` — high cycles 0–7.
- `mult_stage[0..7]` — pulses at successive cycles (one cell each).
- `early_cdb_valid` — pulse at cycle 0 (one cell).
- `early_cdb_tag` — value `<MULT_dest_tag>` from cycle 0.
- `dep_RS_src_ready` — low until cycle 1 (registered version of early_cdb match), then high.
- `cdb_valid` — pulse at cycle 7 (the value arriving).
- `cdb_value` — `<MULT result>` at cycle 7.
- `dep_RS_issue` — pulse at cycle 7 (issues with CDB-bypass for the just-arrived value).

**Annotations on the waveform:**

- Vertical guide at cycle 0 labelled "MULT enters stage 0; early-tag fires".
- Vertical guide at cycle 1 labelled "RS src_ready set (registered)".
- Vertical guide at cycle 7 labelled "CDB delivers value; dep issues same cycle via bypass".
- Above the dep_RS rows, a bracket: "without ETB, dep_RS_issue would happen at cycle 8".

**Caption draft:** *"Early Tag Broadcast timing. The MULT producer broadcasts its destination tag in stage 0; a dependent RS entry becomes issue-eligible after the registered ready bit settles, and issues the same cycle the value arrives via CDB bypass — one cycle earlier than without ETB."*

---

## Tables (no rendering plan needed)

Tables I–V (per `spec.md` §6) are rendered directly in markdown / LaTeX `tabular`. No special tooling. The only judgment call is **Table III (full 33-row continuation)** — in IEEE two-column it likely needs `\small` font and a column trim (drop one or two of the less load-bearing columns) to fit. Decide at LaTeX-migration time.
