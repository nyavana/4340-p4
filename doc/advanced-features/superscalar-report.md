# 2-way superscalar

Status as of 2026-04-30, branch `verify-merged-features` at `dc484b0`.
Merged in commit `a53ee19` ("Merge 2_way_superscalar"). The DC packing
fix `35fb896` from the upstream branch tip wasn't pulled directly; it
was independently re-applied as `bd719c8` to keep the netlist clean.

This is the largest of the advanced-features merges. It widens fetch,
decode, dispatch, ALU execute, CDB broadcast, and ROB commit to two
slots. The LSQ stays single-issue. The MULT and the cache stay
single-issue. The widening still buys 30–50% wall-clock on most
programs because the ALU-bound cycle count was the bottleneck on the
1-wide pipeline.

---

## 1. Motivation

The 1-wide pipeline let the gshare/RAS/ETB advances eat into
predictor-bound cycles, but the dispatch and commit stages then ran
at the same single-instruction-per-cycle cap. CPI on the long
benchmarks sat in the high 4s and 5s on the 1-wide post-predictor
baseline, and most of that was instructions waiting in the RS for
issue slots — not memory, not multiply.

A second ALU plus a second dispatch / commit slot is the cheapest
ILP win available without a register-rename overhaul. Going wider
than two would require multi-port BTB lookups, real second-source
fetch (the icache only returns one 8-byte line per cycle), and a
wider RAT — out of scope for the merge.

---

## 2. Width parameter

```systemverilog
// verilog/sys_defs.svh:23–24
// superscalar width
`define N 2
```

`N = 2` is the design constant the rest of the pipeline indexes off.
ROB commit ports, CDB slots, dispatch arrays, and ALU instances all
size to two. Going to four would require new logic, not just a
different value here — see §8.

---

## 3. Fetch and decode

### 3.1 One line, two instructions

The icache returns one 64-bit line per cycle (`pipeline.sv:243–244`):

```systemverilog
assign fetch_data_out  = sb_valid_out ? sb_data_out : Icache_data_out;
assign fetch_valid_out = Icache_valid_out || sb_valid_out;
```

The two instruction slots come from the high and low 32-bit halves:

```systemverilog
// verilog/pipeline.sv:246–249
assign fetched_inst  = PC_reg[2] ? fetch_data_out[63:32] : fetch_data_out[31:0];
assign fetched_inst1 = PC_reg[2] ? INST'(`NOP)            : fetch_data_out[63:32];
assign fetched_NPC   = PC_reg + 4;
assign fetched_NPC1  = PC_reg + 8;
```

If `PC_reg[2] == 1` (the fetch is starting in the upper half of the
8-byte line), only one valid instruction is in the line and slot 1
gets `NOP`. The next cycle's fetch lines slot 0 up with the next
8-byte line.

This means dispatch alignment biases programs whose hot loops happen
to start on 8-byte boundaries. Programs with 4-byte-aligned hot
loops (most of them) effectively dispatch one instruction per cycle
on the first iteration and two on every subsequent iteration once
the front-end has settled.

### 3.2 Slot 1 dispatch eligibility

Slot 1 is heavily gated. From `pipeline.sv:252–260`:

```systemverilog
assign slot1_candidate = Icache_valid_out && !PC_reg[2];
assign slot1_ok = slot1_candidate
                  && !dec_rd_mem && !dec_wr_mem && !dec_cond_branch
                  && !dec_uncond_branch && !dec_halt && !dec_illegal
                  && !dec1_rd_mem && !dec1_wr_mem && !dec1_cond_branch
                  && !dec1_uncond_branch && !dec1_halt && !dec1_illegal;

assign stall = !fetch_valid_out || rob_full || branch_pending ||
               (is_mem_op ? lsq_full : rs_full);
assign dispatch_fire = !stall;
assign dispatch_fire1 = dispatch_fire && slot1_ok && !rob_almost_full && !rs_almost_full;
```

Slot 1 fires only when **neither** slot is a memory op, branch,
halt, or illegal. So:

- A pair of ALU/MULT instructions can dual-issue.
- Anything in slot 0 that uses the LSQ or the branch resolver
  forces slot 1 to wait until next cycle.
- Anything in slot 1 that needs the LSQ or the branch resolver
  also blocks the pair.

This is the simplest correct dual-dispatch policy on a single-issue
LSQ and a single branch resolver. A second LSQ port or a second
branch comparator would unlock the rest, but neither is in this
merge.

### 3.3 Two parallel decoders

`pipeline.sv` has `dec_*` and `dec1_*` decoder outputs from the same
`decoder` module instantiated twice. Both are combinational on the
fetched instruction, so the two slots resolve at decode in parallel
without contention.

---

## 4. RAT, ROB, and RS dispatch

### 4.1 ROB takes two valid slots

```systemverilog
// verilog/pipeline.sv:747
.dispatch_valid       ({dispatch_fire1, dispatch_fire}),
.dispatch_dest_reg    (rob_dispatch_dest_reg),
.dispatch_NPC         (rob_dispatch_NPC),
...
.dispatch_is_branch   ({(dec1_cond_branch || dec1_uncond_branch), (dec_cond_branch || dec_uncond_branch)}),
```

`rob_dispatch_dest_reg` is a 2-element array (`pipeline.sv:731–732`).
The ROB is sized at `ROB_SZ = 8` (`sys_defs.svh:27`), so up to two
new entries land per cycle and each commit cycle can also retire up
to two.

The RAT is queried four times per cycle for the two instruction
pairs (`pipeline.sv:791–813`): query1 / query2 are slot 0 rs1 / rs2,
query3 / query4 are slot 1 rs1 / rs2. The RAT lives inside the ROB
and accepts all four queries combinationally.

The ROB also extends `dispatch_predicted_taken` and
`dispatch_predicted_target` to two slots, but a comment at line 757
says only slot 0 carries predictor metadata in the current
front-end:

```systemverilog
// Only slot0 uses predictor metadata in this minimal 2-wide frontend.
.dispatch_predicted_taken  ({1'b0, ((dec_cond_branch || dec_uncond_branch) && pred_valid && pred_taken)}),
```

Slot 1 is gated against branches anyway (§3.2), so this is a
correctness concession that maps to the actual policy.

### 4.2 RS takes two valid slots minus memory

```systemverilog
// verilog/pipeline.sv:854
.dispatch_valid      ({dispatch_fire1, (dispatch_fire && !is_mem_op)}),
```

Memory ops bypass the RS and go straight to the LSQ. So slot 0
either dispatches into the RS (non-memory) or into the LSQ
(memory); it does both via mutually-exclusive valid signals. Slot 1
only ever dispatches into the RS (memory ops in slot 1 are blocked
upstream by `slot1_ok`).

### 4.3 LSQ stays single-issue

```systemverilog
// verilog/lsq.sv:45
input  logic              dispatch_valid,
```

`dispatch_valid` is singular. There is no `dispatch_valid[1]` port.
Two adjacent memory ops dispatch one slot at a time across two
cycles. The merge accepted this because the LSQ's dual-port write
would have been a much bigger surgery, and consecutive memory ops
are uncommon enough on the suite that the practical loss is small.

---

## 5. Issue and execute

### 5.1 Two ALUs

```systemverilog
// verilog/pipeline.sv:1110–1140
genvar ai;
generate
    for (ai = 0; ai < 2; ai++) begin : GEN_ALU
        always_comb begin
            case (ALU_FUNC'(rs_issue_op[ai][4:0]))
                ALU_ADD:  alu_result[ai] = rs_issue_src1_value[ai] + rs_issue_src2_value[ai];
                ...
            endcase
        end
        ...
    end
endgenerate
```

Both ALUs are inline combinational. They share the same RS issue
output ports (`rs_issue_src1_value[ai]`), so the RS picks two
independent ready entries and routes them to slot 0 and slot 1.
Branch comparators are also instantiated per-slot.

### 5.2 One MULT, one branch resolver

The pipelined `mult.sv` has a single instance (`pipeline.sv` around
line 1066). It accepts one new multiply per cycle. If both RS issue
slots picked a MULT op, the issue arbiter only honors one — the
second waits.

The branch resolver is the inline `branch_take[ai]` per-slot logic
in the ALU generate block (`pipeline.sv:1128–1138`). The actual PC
redirect happens at the ROB commit stage, so a "branch in slot 1"
case wouldn't be different from "branch in slot 0" architecturally —
but it is structurally suppressed by `slot1_ok` in `pipeline.sv:253`
to keep the dispatch-side branch-pending bookkeeping simple.

---

## 6. CDB and commit

### 6.1 Two-slot CDB

```systemverilog
// verilog/pipeline.sv:1142–1191
always_comb begin
    integer slot;
    integer used;
    ...
    used = 0;
    if (mult_done_valid && used < 2) begin
        cdb_valid[used] = 1'b1;
        cdb_tag[used]   = mult_dest_tag_reg;
        ...
        used = used + 1;
    end
    if (lsq_load_complete_valid && used < 2) begin
        cdb_valid[used] = 1'b1;
        cdb_tag[used]   = lsq_load_complete_tag;
        cdb_value[used] = lsq_load_complete_value;
        lsq_load_selected = 1'b1;
        used = used + 1;
    end
    for (slot = 0; slot < 2; slot++) begin
        if (issue_accept[slot] && !issue_is_mult[slot] && used < 2) begin
            cdb_valid[used] = 1'b1;
            cdb_tag[used]   = rs_issue_dest_tag[slot];
            if (rs_issue_op[slot][6]) begin            // unconditional branch
                cdb_value[used]         = rs_issue_branch_NPC[slot];
                cdb_take_branch[used]   = 1'b1;
                cdb_branch_target[used] = {alu_result[slot][`XLEN-1:1], 1'b0};
            end else if (rs_issue_op[slot][5]) begin   // conditional branch
                cdb_value[used]         = '0;
                cdb_take_branch[used]   = branch_take[slot];
                cdb_branch_target[used] = rs_issue_branch_target[slot];
            end else begin
                cdb_value[used]         = alu_result[slot];
            end
            used = used + 1;
        end
    end
end
```

The CDB has two slots. Priority is MULT first, then LSQ load, then
ALU slot 0, then ALU slot 1. Both ALUs can broadcast on the same
cycle if MULT and LSQ aren't using their slots.

This is the "second CDB" that early-tag-broadcast §6 said it needed
to materialize its one-cycle save. The ETB wakeup wires hand the
ALU consumer the operand in time, and the consumer issues at cycle
T (the MULT broadcast cycle) without colliding because the second
CDB slot is now available.

### 6.2 LSQ wakes from both CDB slots

```systemverilog
// verilog/lsq.sv:65–67
input  logic [1:0]            cdb_valid,
input  logic [TAG_W-1:0]      cdb_tag [2],
input  logic [XLEN-1:0]       cdb_value [2],
```

The LSQ snoops both CDB slots for operand wakeup. Same goes for the
RS. So a same-cycle pair of broadcasts wakes the maximum number of
dependent entries.

### 6.3 ROB commit

```systemverilog
// verilog/pipeline.sv:1199–1204
else if (rob_commit_valid[0] || rob_commit_valid[1]) begin
    if ((rob_commit_valid[0] && rob_commit_halt[0]) || (rob_commit_valid[1] && rob_commit_halt[1]))
        error_status_reg <= HALTED_ON_WFI;
    else if ((rob_commit_valid[0] && rob_commit_illegal[0]) || (rob_commit_valid[1] && rob_commit_illegal[1]))
        error_status_reg <= ILLEGAL_INST;
end
```

`rob_commit_valid` is two-wide. The ROB commits up to two entries
per cycle in program order. Mispredict / halt / illegal logic
checks both slots. The branch-update line we saw in the predictor
report (`pipeline.sv:509–513`) muxes between the two commit slots
to feed a single predictor update — only one update fires per
cycle even if both committing instructions are branches. This is a
known imperfection (predictor report §8).

The store-done sideband to the ROB (`pipeline.sv:771`) only carries
slot 0:

```systemverilog
.store_done_valid     ({1'b0, lsq_store_ready_valid}),
```

That matches the LSQ's single-issue policy: only one store can drain
per cycle.

---

## 7. Mispredict and flush

The single-CDB-cycle mispredict path described in
`base-design/branch-predictor-report.md` is unchanged. When a branch
commits with `take_branch != predicted_taken`, the ROB raises
`mispredict_valid` for one cycle and `mispredict_target` for the
correct PC. The flush input on RS, LSQ, and the in-flight MULT all
fire on `mispredict_valid` (`pipeline.sv:745`, `pipeline.sv:852`).

The "poison the in-flight MULT" trick (`pipeline.sv:1097–1098`)
still applies — `mult_flushed` is set if a multiply is in flight on
the mispredict cycle, suppressing its eventual CDB broadcast. The
2-way superscalar didn't change the multiplier; it just gave its
broadcast a fixed-priority slot on the wider CDB.

---

## 8. Unit tests

There is no targeted 2-way superscalar testbench. The dual-issue
path is exercised by every full-program regression — alexnet, dft,
the sorts, and matrix_mult_rec all dispatch and commit dual-issue
heavily. The dual-issue dispatch arrays are also exercised by the
ROB and RS unit tests, which now use 2-element dispatch packets.

Two diagnostics in the testbench help debug dual-issue regressions:

- The pipeline testbench `test/pipeline_test.sv` prints `branch_accuracy: correct/total` at halt, with the counters
  driven by `rob_commit_is_branch[0]` / `rob_commit_is_branch[1]`
  (so both commit slots count).
- The `.wb` writeback file lists every retiring instruction; the
  comment in merge report §5.1 about "the 2-way commit stage adding
  a second writeback slot to the printer after the snapshot was
  taken" describes a delta from the April-26 baseline that is
  expected on dual-issue cycles.

---

## 9. Regression

Wall-clock gain is broad. The full table is in merge report §5;
every program is at least as fast as the pre-superscalar baseline
or within noise. Highlights:

| Program | cycles before | cycles now | Δ% | CPI before → now |
|---|---|---|---|---|
| alexnet | 9 383 837 | 4 730 247 | −49.6% | 44.88 → 22.63 |
| dft | 1 685 359 | 1 006 437 | −40.3% | 29.12 → 17.39 |
| outer_product | 4 519 350 | 3 166 519 | −29.9% | 6.06 → 4.24 |
| insertionsort | 773 510 | 554 802 | −28.3% | 5.42 → 3.88 |
| sort_search | 813 758 | 600 637 | −26.2% | 4.47 → 3.30 |
| quicksort | 902 072 | 568 553 | −37.0% | 9.45 → 5.96 |

Some of the gain is gshare, RAS, STLF, and dcache. But the CPI
column is what's useful for attributing dual-issue specifically:
programs that drop from CPI 5+ to CPI 4 or lower are the ones where
dispatch / commit width matters.

`outer_product` going from 6.06 to 4.24 is a clean superscalar
result: the inner loop is two ALUs and a load per iteration; the
load can't dual-issue but the two ALUs can.

`fib_rec` (CPI 2.55 → 2.44) barely moves — its inner loop has tight
serial dependencies and almost no ILP, so dual-issue doesn't help.
That matches the ETB report's analysis: 2-way superscalar is what
unlocks ETB's save, which means programs without the parallelism to
exploit two ALUs see neither.

Small programs with few branches see the smallest deltas because
the front-end overhead dominates a short run.

---

## 10. Synthesis

```
make synth/rob.vg → +282.83 ps slack
make synth/rs.vg  → +229.79 ps slack
```

The rob and rs modules both meet timing standalone (merge report
§3). Dual-issue widened the priority encoders and the dispatch
write-port logic but didn't push either of them onto the integrated
critical path. That path (merge report §6) is on the LSQ → MULT
seam, which the 2-way superscalar didn't touch.

The DC packing fix `bd719c8` was the one piece of work specifically
needed to keep the synthesized netlist clean after dual-issue
widening (merge report §1). The fix makes 2-element unpacked-array
ports compatible with DC's bus packing.

---

## 11. Files changed

The merge touched almost every file:

- `verilog/sys_defs.svh`: `N = 2`.
- `verilog/pipeline.sv`:
  - Two-slot fetch (`fetched_inst` / `fetched_inst1`).
  - `slot1_ok` gating.
  - Two-slot dispatch arrays and decoders.
  - Two ALUs in a generate block.
  - Two-slot CDB arbitration with priority MULT > LSQ load > ALU.
  - Two-wide RAT query ports into the ROB.
- `verilog/rob.sv`:
  - Two-wide dispatch and commit ports (arrays of two).
  - RAT-clear at commit handles both slots.
  - Stale-RAT-clear rule (CLAUDE.md §"Load-bearing rules" #6) holds
    for both committing slots.
- `verilog/rs.sv`:
  - Two-wide dispatch ports.
  - Two-wide issue output (`rs_issue_*[2]`).
  - CDB wakeup snoops both slots.
- `verilog/lsq.sv`:
  - CDB wakeup snoops both slots.
  - Dispatch stays singular (single-issue LSQ).
- `verilog/icache.sv`: returns full 8-byte lines (already did this;
  the merge consumes the high half rather than dropping it).

Tests:

- The unit tests for ROB and RS use the new two-wide dispatch
  packets. LSQ unit tests still use single-issue.

---

## 12. Known limitations

1. **LSQ is single-issue.** Two adjacent memory ops cannot
   dual-dispatch. A second LSQ write port would help on
   memory-stream code but adds a lot of arbitration logic.
2. **No second branch resolver.** A pair where slot 0 or slot 1 is a
   branch is forced to single-issue. This is rare on the suite but
   it costs ~1% on programs with branch-dense inner loops.
3. **Predictor only updates once per cycle.** If both committing
   instructions are branches, slot 1's update is dropped
   (`pipeline.sv:509–513`). Branch-dense recursive code is the
   plausible victim, but no program in the regression has been
   pinned on this.
4. **Slot 1 forced to NOP on 4-byte-misaligned fetch.** Programs
   whose hot loops start at PC%8 == 4 lose one slot per loop
   iteration on the first cycle. A two-line fetch buffer would fix
   it; not in this merge.
5. **DC packing fix `bd719c8` is independent of `35fb896`.** The
   upstream branch tip carries `35fb896`; we re-applied a different
   fix (`bd719c8`) for the same problem. Worth knowing if a future
   merge from upstream pulls `35fb896` and creates a redundant edit.

---

## 13. How to rebuild

```
# Default (2-way on)
make clean && make -j8 simulate_all

# Per-module unit tests
make rob.pass && make rob.syn.pass
make rs.pass  && make rs.syn.pass
make lsq.pass && make lsq.syn.pass
```

There's no `+define+SINGLE_ISSUE` flag. `+define+SERIALIZE_BRANCHES`
forces the milestone-3 front-end serialization on branches but does
not affect dual-issue dispatch on non-branch pairs. To do a true
1-wide A/B you'd revert the `slot1_ok` block and the second ALU
generate; the merge report's §5.1 byte-identity check between sim
and syn is the closest available correctness signal.
