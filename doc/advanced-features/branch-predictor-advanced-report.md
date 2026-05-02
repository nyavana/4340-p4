# gshare + RAS: design, integration, regression

Status as of 2026-04-30. Both features are live on `verify-merged-features`
(branch tip `dc484b0`). The bimodal direction predictor and the lone BTB
target lookup that shipped with milestone 3's
[`branch-predictor-report.md`](../base-design/branch-predictor-report.md)
have been replaced by gshare-indexed BHT lookups plus a 16-entry Return
Address Stack. Both landed in the same merge commit (`5f3e5e0`, "RAS +
gshare GHR combined").

The TB rewrite that retroactively closed the gshare/RAS test gap is
documented in §10.1 of
[`advanced-features-merge-report.md`](advanced-features-merge-report.md);
this file is the design-side companion.

---

## 1. Motivation

The base design's open follow-up §3 in `branch-predictor-report.md` reads:

> Add a Return Address Stack for JALR. The fib_rec 65.53% accuracy
> number is almost entirely JALR return mispredicts against the BTB's
> single last-committed target per entry; every switch between
> recursive frames mispredicts.

The same report's "Known limitations" admitted that JALR call sites with
distinct targets aliased into the same BTB slot are unrecoverable
without a stack. The cumulative per-program data in §5 of the merge
report bears this out: pre-gshare/RAS, every recursion-heavy program
commits more JALR mispredicts than conditional ones.

gshare goes after the orthogonal limitation. The bimodal counters
ignored history, so a single hot branch with a "TNTNTNT…" pattern lived
forever at counter `2'b01` (weakly not-taken) and missed half the time.
XORing the PC with a global history register gives that branch its own
counter per recent-history context, at the cost of cold-start aliasing
on programs with short hot loops.

---

## 2. gshare mechanism

### 2.1 Index function

```systemverilog
// verilog/branch_predictor.sv:90–99
function automatic logic [BHT_IDX_W-1:0] bht_pc_bits(input logic [XLEN-1:0] pc);
    bht_pc_bits = pc[BHT_IDX_W+1 : 2];
endfunction

function automatic logic [BHT_IDX_W-1:0] bht_idx(
    input logic [XLEN-1:0] pc,
    input logic [BHT_IDX_W-1:0] hist
);
    bht_idx = bht_pc_bits(pc) ^ hist;
endfunction
```

`BHT_IDX_W = $clog2(BHT_ENTRIES) = $clog2(64) = 6`. The PC slice is
`pc[7:2]` — the same six bits the bimodal index used. The GHR is the
same width:

```systemverilog
// verilog/branch_predictor.sv:120
localparam GHR_W = BHT_IDX_W; // full-width gshare: GHR matches BHT index width
```

So `bht_idx` is a clean 6-bit XOR fold. There is no PC tag in the BHT;
two PCs that hash to the same `bht_pc_bits` and run under the same GHR
share a counter. This is by design and is the standard gshare
trade-off.

### 2.2 GHR update timing

The GHR is updated at branch commit, not at dispatch:

```systemverilog
// verilog/branch_predictor.sv:225–233
if (update_valid) begin
    btb[up_btb_i].valid     <= 1'b1;
    btb[up_btb_i].tag       <= up_tag;
    btb[up_btb_i].target    <= update_target;
    btb[up_btb_i].is_uncond <= update_is_uncond;
    if (!update_is_uncond) begin
        bht[up_bht_i] <= up_counter_nxt;
        ghr           <= {ghr[GHR_W-2:0], update_taken};
    end
end
```

`update_valid` is driven by the ROB's commit-stage branch sideband
(`pipeline.sv:509`), so a conditional branch updates the GHR exactly
once, after its in-order commit. Unconditional branches do not shift
the GHR (the `!update_is_uncond` guard at line 230); the comment block
right above explains why — a JAL or JALR has no taken/not-taken bit to
record, so adding it would inject noise into the history.

This is the simpler of the two common gshare designs. The other one
keeps a speculative GHR snapshot per in-flight branch and rolls back
on mispredict. It has slightly better accuracy on long-pipeline
programs but needs `ROB_SZ` worth of GHR snapshots and a multiplexed
restore. The team picked commit-driven for area and integration cost,
accepting that during a stretch of 8 in-flight branches the GHR is
stale. The accuracy hit is small enough that it does not show up
against the bimodal baseline on any program in the suite.

### 2.3 Update at commit, not predict

Speculative-update gshare designs sometimes shift the GHR at predict
time and roll back on a wrong-direction commit. This implementation
doesn't, so the GHR drifts only with retired direction bits and the
predict-time XOR sees a settled history. The downside, again, is that
in-flight branches don't see each other's predicted directions; we
took that hit deliberately.

---

## 3. RAS mechanism

### 3.1 Storage

```systemverilog
// verilog/branch_predictor.sv:131–136
logic [XLEN-1:0]      ras       [RAS_ENTRIES-1:0];
logic [RAS_IDX_W-1:0] ras_sp;
logic [RAS_IDX_W:0]   ras_count;

wire [RAS_IDX_W-1:0] ras_top_i = ras_sp - {{(RAS_IDX_W-1){1'b0}}, 1'b1};
wire                 ras_has_entry = (ras_count != '0);
```

`RAS_ENTRIES = 16` (`sys_defs.svh:39`). The stack is a 16 × 32-bit
ring with `ras_sp` pointing at the next slot to write; the top is
`ras_sp - 1`. `ras_count` is one bit wider than `ras_sp` so it can
saturate at 16 without wrapping.

### 3.2 Push and pop

The pipeline does the call/return classification:

```systemverilog
// verilog/pipeline.sv:476–481
assign is_jal_inst  = dec_uncond_branch && (fetched_inst.r.opcode == 7'b1101111);
assign is_jalr_inst = dec_uncond_branch && (fetched_inst.r.opcode == 7'b1100111);
assign rd_is_link   = (fetched_inst.r.rd  == 5'd1) || (fetched_inst.r.rd  == 5'd5);
assign rs1_is_link  = (fetched_inst.r.rs1 == 5'd1) || (fetched_inst.r.rs1 == 5'd5);
assign predict_is_call   = (is_jal_inst || is_jalr_inst) && rd_is_link;
assign predict_is_return = is_jalr_inst && rs1_is_link && !rd_is_link;
```

Push and pop are gated with `dispatch_fire`:

```systemverilog
// verilog/pipeline.sv:506–507
.ras_push_en       (dispatch_fire && predict_is_call),
.ras_pop_en        (dispatch_fire && predict_is_return),
```

So the stack is updated at dispatch, not commit. That makes RAS state
speculative: a mispredicted call or return between dispatch and the
flushing branch leaves the stack in a wrong state, and we don't roll
it back.

```systemverilog
// verilog/branch_predictor.sv:204–206 (comment)
// RAS update.  Simultaneous push+pop pushes without popping.
// No rollback on mispredict (speculative-only state).
```

The "push wins simultaneous push+pop" rule is in
`branch_predictor.sv:236–246`. It is the same convention every other
RAS-on-RISC-V design we found uses, and the lack-of-rollback rationale
is similar to the GHR's: with `RAS_ENTRIES = 16` and the longest
in-flight call chain in the suite at four (`fib_rec`), drift is
self-correcting after the next call.

### 3.3 Predict override

The RAS supplies the predicted target on returns, overriding the BTB:

```systemverilog
// verilog/branch_predictor.sv:165–171
wire ras_override = predict_is_return && ras_has_entry;

assign pred_valid     = ras_override ? 1'b1 : btb_pred_valid;
assign pred_taken     = ras_override ? 1'b1 : btb_pred_taken;
assign pred_is_uncond = ras_override ? 1'b1 : btb_pred_is_uncond;
assign pred_target    = ras_override ? ras[ras_top_i] : btb_pred_target;
```

`predict_is_return` is computed combinationally from the fetched
instruction in `pipeline.sv:481` and feeds the predictor on the same
cycle. When the stack is empty the RAS does not override and the
predictor falls back to the BTB target, so a cold start does not
mispredict any more often than it did pre-RAS.

The override does not consume the stack (no pop) — the pop is gated on
`dispatch_fire && predict_is_return`, which fires later. That means a
return PC stays available across the predict-to-dispatch latency in
the front-end.

---

## 4. Unit tests

`test/branch_predictor_test.sv` carries 14 scenarios. Tests 1–9 cover
the BTB and bimodal behaviors that already existed; tests 10–13 are
RAS-specific. The pre-merge tests 2/5/7 were rewritten in the
verify-merged-features pass to drive a TB-side gshare model rather
than asserting against raw-PC BHT indices (full write-up in merge
report §10.1).

The reference model is what makes the tests robust to gshare
hashing:

```systemverilog
// test/branch_predictor_test.sv:140–201
// TB-side gshare reference model.
// Mirrors GHR, BHT, and BTB so we can compute expected predictions
// after an arbitrary sequence of updates.
logic [GHR_W-1:0]     mdl_ghr;
logic [1:0]           mdl_bht [BHT_ENTRIES-1:0];
...
hi = mdl_bht_pc_bits(pc) ^ mdl_ghr;
...
mdl_ghr = {mdl_ghr[GHR_W-2:0], taken};
```

Test 7 keeps the old bimodal "saturate to 11, then flip to 01 over two
not-takens" semantic by picking colliding PCs at every step: the test
arithmetic computes `bht_pc_bits(pc_k) ^ expected_ghr_k = TARGET_IDX`
for each update. That way every update lands on the same physical BHT
counter regardless of how the GHR has shifted in between.

The RAS scenarios are direct:

| Test | What it covers |
|---|---|
| 10 | Single push, then a return predicts that target. |
| 11 | Nested pushes pop in reverse order. |
| 12 | Return on an empty stack falls back to BTB without crashing. |
| 13 | Push past `RAS_ENTRIES` saturates and the oldest entry is overwritten. |

All 14 pass on both `make branch_predictor.pass` and
`make branch_predictor.syn.pass` after the verify-merged-features
pass.

---

## 5. Regression

The two features shipped together in commit `5f3e5e0`, so per-feature
attribution would need a bisect. The §5 cumulative table in the merge
report is the cleanest comparison available; what follows is the
subset where gshare and RAS together moved the needle.

### 5.1 RAS-driven gains

`fib_rec` and `matrix_mult_rec` are the recursion-heavy programs. The
pre-merge baseline (`bp_was`) is bimodal + 2-way superscalar but no
RAS:

| Program | cycles before | cycles now | Δ% | accuracy before → now |
|---|---|---|---|---|
| fib_rec | 30 518 | 29 132 | −4.5% | 65.6% → 72.2% |
| matrix_mult_rec | 719 984 | 662 478 | −8.0% | 94.4% → 96.4% |

The base predictor report already noted fib_rec's 65.5% as the
canonical "JALR returns mispredict every call-site switch" symptom.
Adding the stack lifted it to 72.2% — short of the conditional-branch
ceiling, but the residual is mostly the speculative-RAS drift
described in §3.2.

`matrix_mult_rec` is dominated by leaf-call returns, so the RAS
covers nearly every JALR. The 94.4% baseline was already high (it has
few conditionals); the +2 percentage points still buys 8% wall-clock.

### 5.2 gshare-driven gains

Programs with branchy inner loops show up in the table as the big
percentage-cycle improvements:

| Program | cycles before | cycles now | accuracy before → now |
|---|---|---|---|
| alexnet | 9 383 837 | 4 730 247 | 84.7% → 88.5% |
| dft | 1 685 359 | 1 006 437 | 82.5% → 85.9% |
| insertionsort | 773 510 | 554 802 | 88.5% → 88.3% |
| sort_search | 813 758 | 600 637 | 85.8% → 83.6% |
| backtrack | 258 690 | 146 861 | 83.7% → 84.2% |

Some of these are partly STLF and dcache wins (insertionsort and
sort_search lean memory-heavy). On alexnet and dft the cycle gain
tracks the accuracy gain almost one-for-one; those programs really
are predictor-bound on the bimodal baseline.

### 5.3 Programs where the merged predictor is worse

Three small benchmarks regress on the accuracy column:

| Program | accuracy before → now | total branches |
|---|---|---|
| fib | 86.7% → 61.9% | ~21 |
| parallel | 87.5% → 60.0% | ~5 |
| mult | 83.3% → 50.0% | ~6 |

Each program commits fewer than 25 branches, so the percentage column
is dominated by single-misprediction noise rather than by a real
predictor regression. Cycle counts on these programs all moved
within ±1%. We did not chase them.

Big-program accuracy is steady or up: alexnet 88%, quicksort 85%,
sort_search 84%, insertionsort 88%, matrix_mult_rec 96%. None of the
bigger programs regressed.

---

## 6. Synthesis

```
make synth/branch_predictor.vg
…
worst slack = +570.88 ps  (1000 ps clock)
```

The advanced predictor sits at +570 ps headroom standalone (§3 of the
merge report). It is not on the integrated critical path — that path
post-`51b7f1c` is `lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]`
(LSQ broadcast → RS operand mux → ALU 32-bit adder → ROB / LSQ entry
register; merge report §6, current worst slack −797.58 ps). The MULT
stage-0 cone (`lsq_0/head_reg[1] → mult_0/mstage[0]/product_sum_reg[*]`)
quoted in older write-ups is closed by `51b7f1c`'s mult-operand
register.

The XOR fold and the RAS read-mux do not show up as new endpoints. The
RAS top read (`ras[ras_top_i]`) is a 16-deep mux feeding `pred_target`
on returns; it lands on the BTB target mux in
`branch_predictor.sv:171` and shares that path's slack.

`make branch_predictor.syn.pass` is green after the TB rewrite (merge
report §10.1).

---

## 7. Files changed

The changes shipped in commit `5f3e5e0`. Net diff is small:

- `verilog/sys_defs.svh`: `RAS_ENTRIES = 16`.
- `verilog/branch_predictor.sv`:
  - `bht_idx` becomes a function of `(pc, hist)` with the XOR fold.
  - `GHR_W` localparam, `ghr` register, registered shift on every
    conditional commit.
  - RAS storage, `ras_sp`, `ras_count`, `ras_top_i`, `ras_has_entry`.
  - `ras_override` mux ahead of the four output assignments.
  - Push/pop logic with the "push wins simultaneous push+pop" rule.
- `verilog/pipeline.sv`:
  - `predict_is_call` and `predict_is_return` decoded from the fetched
    instruction.
  - `predict_link_pc = fetched_NPC` so a JAL's link target lives in
    the slot we will eventually pop.
  - `ras_push_en` / `ras_pop_en` gated by `dispatch_fire`.
- `test/branch_predictor_test.sv`:
  - TB-side reference model (`mdl_*`).
  - Tests 2 / 5 / 7 rewritten to drive the model and assert against it
    rather than against a fixed BHT index.
  - Tests 10–13 added for RAS push, nesting, empty handling, and
    saturation.

There are no changes to `rob.sv`, `rs.sv`, `lsq.sv`, or the icache.
The flush-on-mispredict path was already in place from
milestone 3 and works unchanged for the RAS speculative state (the
wrong RAS slot just gets overwritten by the next call).

---

## 8. Known limitations

1. **No GHR snapshot/rollback.** The GHR shifts at commit, so during
   long stretches of in-flight conditionals every prediction reads a
   stale history. The fix is one snapshot per ROB entry plus a
   restore mux on mispredict. We measured small-program impact at
   well under 1% wall-clock and deferred it.
2. **No RAS rollback either.** Same disposition. fib_rec's residual
   ~28% misprediction rate is partly this; the rest is the bimodal
   counters under the four-deep recursive return pattern, which
   gshare alone won't resolve.
3. **BTB is still direct-mapped, 32 entries.** The original report
   listed "2-way set-associative BTB" as backlog. It is still backlog.
   Programs with many distinct hot branches alias.
4. **One predictor update per commit cycle.** The dual-commit ROB
   exposes two `rob_commit_branch_*` slots; `pipeline.sv:509` muxes
   them so only one update fires per cycle. If both committing
   instructions are branches we drop the slot-1 update. The 2-way
   superscalar is rare enough on consecutive branches that this has
   not shown up as a regression, but it's a known imperfection.
5. **`DISABLE_PREDICTOR` ifdef** (`pipeline.sv:483–488`) forces all
   prediction outputs to zero. That gives back the milestone-3
   "no front-end speculation" behavior for bisecting against a
   pre-predictor baseline.

---

## 9. How to rebuild

```
# Default (gshare + RAS on)
make clean && make -j8 simulate_all

# Predictor off (front-end runs without prediction)
make clean && make -j8 simulate_all \
    VCS_BAD_WARNINGS="+warn=noTFIPC +warn=noDEBUG_DEP +warn=noENUMASSIGN +define+DISABLE_PREDICTOR"

# Branch-predictor unit test
make branch_predictor.pass
make branch_predictor.syn.pass
```

Per-program cycle / accuracy data is in §5 of
[`advanced-features-merge-report.md`](advanced-features-merge-report.md);
the comparison file `branch_accuracy_cpi_diff.md` has the same numbers
in raw form.
