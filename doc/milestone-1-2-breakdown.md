# Milestones 1 and 2: a code-level breakdown

This is a walk through what actually changed in the codebase between the starter
code and the two milestone snapshots, with line references so you can follow along
in the source. The three trees being compared are:

- `4340-p4/` — starter code, 5-stage in-order pipeline left mostly unwired
- `4340-p4-milestone1/` — adds the reservation station as a standalone module
- `4340-p4-milestone2/` — adds the reorder buffer and rewires `pipeline.sv` into
  an out-of-order machine

The high-level goal of the project is to take a stubbed RV32IM pipeline and turn
it into a synthesizable out-of-order processor. Milestones 1 and 2 are the first
two checkpoints on the way there. M1 builds one piece (the RS) in a bench harness.
M2 builds the second piece (the ROB) and tries to glue both into the pipeline.

## Why the project shape matters

Before getting into the diffs, one detail is worth pinning down. The simulation
memory has a 100 ns access latency, which at the 1 GHz clock used here translates
to roughly 100 cycles per cache miss. An in-order pipeline parked behind a single
miss is wasting almost the entire cycle budget. The whole reason the OoO
machinery gets built is to keep the processor doing something useful while a
load is in flight. Reservation stations buffer waiting instructions; the ROB
lets later instructions execute and then retire in program order.

That framing shows up directly in the milestone choices. M1 ships the structure
that holds waiting instructions. M2 ships the structure that lets them retire.

## Baseline: what the starter actually contains

The `4340-p4/verilog/` tree has nine source files at baseline:

| file | lines | role |
|---|---|---|
| `ISA.svh` | 236 | instruction field macros |
| `decoder.sv` | 191 | combinational decoder |
| `icache.sv` | 131 | instruction cache with 100 ns latency tags |
| `mult.sv` | 41 | pipelined multiplier top |
| `mult_stage.sv` | 40 | one stage of the pipelined multiplier |
| `pipeline.sv` | 132 | top-level — *intentionally empty* |
| `psel_gen.sv` | 117 | parameterized priority selector |
| `regfile.sv` | 55 | dual-read single-write regfile |
| `sys_defs.svh` | 359 | parameter and typedef header |

There is no `rob.sv` and no `rs.sv` at baseline. The reference in-order stages
from Project 3 are tucked into `verilog/p3/` so they can be read but not used.

The interesting file is `verilog/pipeline.sv`. Open it and you find a complete
module declaration, all the right ports, packet typedef stubs, and a 16-line
memory arbitration block at lines 99–114 that hands the bus to the data side
when there is a memory request and otherwise sends an instruction fetch. That
is the entire body. The pipeline output assignments at lines 122–130 reference
`mem_wb_reg`, but `mem_wb_reg` is just a declared wire. Nothing drives it.
There are no stage instantiations. There is no register update. The file
elaborates cleanly and produces no work.

`verilog/sys_defs.svh` is the other artifact that signals "you fill this in."
Lines 27–28 read:

```systemverilog
`define ROB_SZ xx
`define RS_SZ xx
```

and lines 36–39 do the same for the functional unit counts:

```systemverilog
`define NUM_FU_ALU xx
`define NUM_FU_MULT xx
`define NUM_FU_LOAD xx
`define NUM_FU_STORE xx
```

`xx` is not a SystemVerilog literal. The file does not compile until those are
replaced. That is the gating mechanism. The moment a student wires up a module
that depends on these values, the build forces them to commit to numbers.

## Milestone 1: the reservation station, on its own

`diff -rq` between baseline `verilog/` and milestone 1 `verilog/` reports two
changes: a brand new file, `rs.sv`, and edits to `sys_defs.svh`. That is the
entire footprint inside `verilog/`. Nothing in the existing logic is rewired.
M1 is purely additive.

### The new file: `verilog/rs.sv`

212 lines. Parameterized at the top:

```systemverilog
module rs #(
    parameter RS_SIZE = `RS_SZ,
    parameter XLEN    = `XLEN,
    parameter TAG_W   = $clog2(`ROB_SZ),
    parameter OP_W    = 8
)
```

The `TAG_W` derivation is the giveaway that `ROB_SZ` has to be defined for this
file to compile. Hence the `sys_defs.svh` edits below.

The data each entry holds is declared at lines 42–54. Nothing exotic: a `busy`
flag, the opcode, the destination tag, and a `ready/tag/value` triple for each
of the two source operands. Two arrays exist in parallel: the registered
`entries` and a combinational `next_entries` that gets computed every cycle and
clocked in by the single `always_ff` block at lines 198–210. The two-array
discipline is what keeps the file readable. The next-state logic is one big
`always_comb` and the sequential update is trivial.

The interesting bit of the design is the wakeup-and-issue path. Two combinational
loops compute `src1_ready_eff` and `src2_ready_eff` at lines 87–101, and they
each take the OR of "the entry already had its operand" and "the CDB is broadcasting
this exact tag right now":

```systemverilog
src1_ready_eff[i] = entries[i].src1_ready ||
                    (cdb_valid && entries[i].busy &&
                     !entries[i].src1_ready &&
                     (entries[i].src1_tag == cdb_tag));
```

This is the same-cycle bypass. Without it, an instruction whose operand was
produced this cycle would have to wait one extra cycle to notice. The wakeup
would only happen on the next clock edge, after `entries[i].src1_ready` was
latched. One extra cycle on every dependency chain adds up fast. The issue
selector at lines 104–118 then does a linear scan and picks the first entry
whose effective ready bits are both set.

One thing worth flagging: this is index-priority, not age-priority. The
allocator at lines 71–82 grabs the lowest free slot, so by the time you scan
for the oldest ready entry you are really scanning by slot index. For
`RS_SIZE = 8` and a single dispatch per cycle the two orderings tend to agree,
but they are not the same thing. Worth knowing if anyone scales the RS up.

Free-slot allocation also uses a linear scan (`free_idx` at lines 71–82). Same
pattern: pick the first hole. The file does not use `psel_gen.sv`, even though
that helper sits right there in the starter for exactly this kind of arbitration.
For a width-1 scheduler the manual scan is easier to debug. It is something to
revisit when the design goes superscalar.

Issue cleanup happens at line 177–179:

```systemverilog
if (issue_fire) begin
    next_entries[issue_idx] = '0;
end
```

`issue_fire` is just `issue_valid && issue_accept`. The downstream consumer is
in charge of telling the RS when it has actually taken the instruction. This is
a clean handshake and it survives integration in M2 unchanged.

### The header edit: `verilog/sys_defs.svh`

Two lines:

```systemverilog
`define ROB_SZ 8 // temporary only for testing
`define RS_SZ 8 // temporary only for testing
```

The comments are the author's, and they are honest: 8 is not a design choice,
it is the smallest value that lets `rs.sv` and `rs_test.sv` compile. The
functional unit defines (`NUM_FU_*`) stay at `xx` because the RS does not
care how many ALUs there are.

### The testbench: `test/rs_test.sv`

475 lines. It instantiates the RS, ticks the clock, and walks through dispatch
with and without ready operands, CDB wakeup forwarding, FIFO issue ordering,
and the full/backpressure case. The bench tracks `error_count` and `test_count`
locally and prints `@@@ Passed` / `@@@ Incorrect` so the existing `make rs.pass`
target works.

### The Makefile change

One line, around line 180:

```makefile
TESTED_MODULES = mult rob RS rs
```

Both the uppercase module name and the lowercase test target appear, which is
slightly redundant but matches how the existing `mult` and `rob` entries handle
the case-insensitive convention. The result is that `make rs.pass`, `make rs.cov`,
and `synth/rs.vg` all become first-class targets.

### What did not change

`pipeline.sv` is byte-identical to the baseline. So is everything else in the
verilog tree. The RS exists in isolation, not connected to anything yet. That
separation is the whole point of M1. Prove the scheduling logic against a
focused bench before debugging it through the lens of a half-built pipeline.

## Milestone 2: ROB plus full pipeline integration

This is the big one. M1 was a 212-line addition to a directory and a couple of
header tweaks. M2 rewrites `pipeline.sv` from 132 lines to 518 lines, adds a
253-line `rob.sv`, and changes the meaning of nearly every signal that flows
between fetch and writeback.

### The new file: `verilog/rob.sv`

253 lines. The entry struct at lines 61–72 looks like a standard ROB entry,
with branch-recovery fields baked in from the start:

```systemverilog
typedef struct packed {
    logic            busy;
    logic            ready;
    logic [4:0]      dest_reg;
    logic [XLEN-1:0] value;
    logic [XLEN-1:0] NPC;
    logic            halt;
    logic            illegal;
    logic            is_branch;
    logic            take_branch;
    logic [XLEN-1:0] branch_target;
} rob_entry_t;
```

`busy` is the allocation bit, `ready` is the completion bit, and the entry can
sit at any non-ready state in between. The branch bookkeeping (`is_branch`,
`take_branch`, `branch_target`) gets carried per entry so that when the head
finally retires, the pipeline can decide whether the predicted-not-taken default
was right and redirect the PC if it was not.

What makes `rob.sv` more than just a buffer is the Register Alias Table living
inside it, lines 82–85:

```systemverilog
logic             rat_busy      [32];
logic [TAG_W-1:0] rat_tag       [32];
```

One bit and one tag per architectural register. `rat_busy[r]` says "some ROB
entry will write `x[r]`," and `rat_tag[r]` says which one. This is the renaming
mechanism. When dispatch fires for an instruction with `dest_reg = r`, the RAT
entry for r is overwritten with the new tail tag (lines 217–220):

```systemverilog
if (dispatch_dest_reg != 5'd0) begin
    next_rat_busy[dispatch_dest_reg] = 1'b1;
    next_rat_tag [dispatch_dest_reg] = tail;
end
```

The `!= 5'd0` guard is what keeps `x0` permanently unrenamed. Reads of `x0`
always fall through to the regfile and return zero. Writes to `x0` are tracked
in the ROB entry but never reach the RAT.

The `query1_*` and `query2_*` ports at lines 45–55 are how the rest of the
pipeline asks the RAT a question. "Is this architectural register currently
owned by a ROB entry, and if so, is the value ready, or do I need to wait for
a tag?" Two queries per cycle, matching the source pair on a dispatched
instruction. The query logic at lines 117–150 has the same-cycle CDB bypass
the RS does:

```systemverilog
if (cdb_valid && (q1_tag_int == cdb_tag) && !entries[q1_tag_int].ready) begin
    query1_ready = 1'b1;
    query1_value = cdb_value;
end
```

So if the ROB entry that owns this query's source register happens to be
broadcasting on the CDB this cycle, the RAT returns the CDB value directly.
Without this you'd see an extra cycle of bubbling on every back-to-back
producer/consumer pair.

The next-state block at lines 156–224 is laid out with explicit priority,
documented in the comment at line 154:

> Priority: flush > CDB complete > commit > dispatch

The ordering matters. CDB has to land before commit so that an entry which
becomes ready *this* cycle can also retire *this* cycle. Commit has to land
before dispatch so that the head slot can be reused on the same edge it is
freed. The `count` field is declared `[TAG_W:0]` at line 92 with one extra
bit, which is what lets the buffer cleanly distinguish full from empty.

The RAT clear at lines 191–196 is the subtle case to get right:

```systemverilog
if (entries[head].dest_reg != 5'd0 &&
    rat_busy[entries[head].dest_reg] &&
    rat_tag [entries[head].dest_reg] == head) begin
    next_rat_busy[entries[head].dest_reg] = 1'b0;
end
```

The retiring entry only clears the RAT if it is still the *latest* writer of
its destination register. If a younger instruction has already overwritten the
RAT entry for this architectural register, the older retiring instruction must
not undo that. This is the kind of bug you only catch by tripping over it once,
and the file handles it at the right spot.

`flush` at lines 168–177 wipes everything and resets head/tail/count. The port
exists, but as you'll see in `pipeline.sv`, it is currently tied to `1'b0` at
the integration site. There is no branch-mispredict pathway yet. Branches stall
the front end instead. More on that below.

### The big rewrite: `verilog/pipeline.sv`

Going from 132 to 518 lines. Most of the bulk is glue: signal declarations
(lines 25–119), instantiations (the ROB at lines 283–325, the RS at 330–359),
operand-resolution muxes (lines 222–278), and the inline ALU/MULT/CDB logic
(lines 386–502). The architectural decisions live in a few specific places.

#### Stall logic

Line 127 is the new stall expression:

```systemverilog
assign stall = !Icache_valid_out || rs_full || rob_full || branch_pending;
```

Four conditions in OR. The original stall in M1 (and at baseline, conceptually)
was just `!Icache_valid_out`. Three new terms get added in M2:

- `rs_full` — no room in the scheduler, can't dispatch
- `rob_full` — no room in the ROB, can't allocate a tag
- `branch_pending` — there's an unresolved branch in flight, the front end
  refuses to fetch past it

The branch case is the most expensive stall and also the easiest one to fix
later. A branch predictor turns this stall off and replaces it with speculative
fetch and a potential flush. M2 does not have one. Until then, every taken
branch costs roughly the depth of the in-flight window plus the fetch-to-commit
latency.

#### PC update

Line 159–166:

```systemverilog
always_ff @(posedge clock) begin
    if (reset)
        PC_reg <= '0;
    else if (rob_commit_valid && rob_commit_take_branch)
        PC_reg <= rob_commit_branch_target;
    else if (!stall)
        PC_reg <= PC_reg + 4;
end
```

Three cases, in priority order: reset, branch redirect on commit, linear
advance. Notice that the branch redirect comes from the ROB commit port, not
from the execution unit. Branch outcomes only redirect the PC at retirement.
That makes the design architecturally sound for branch recovery even without
a predictor: by the time PC moves, the branch is committed and no younger
speculation needs squashing. There is no younger speculation to squash anyway,
because `branch_pending` froze the front end the moment the branch went out.

#### Source operand resolution

Lines 222–278 are the two `always_comb` blocks that decide what each source
operand looks like at dispatch time. The pattern for src1 is:

1. If the instruction is a conditional branch, or the decoder picked
   `OPA_IS_RS1`, this source comes from the architectural register file. Ask
   the RAT first — if no in-flight instruction owns this register, take the
   regfile value directly. If an in-flight instruction does own it, take the
   tag/value pair the RAT returned (which itself already had the same-cycle
   CDB bypass applied inside `rob.sv`).
2. Otherwise the operand is a constant: PC, NPC, or zero.

The src2 mux follows the same pattern but folds in the immediate selectors as
the constant case (`OPB_IS_I_IMM`, `OPB_IS_S_IMM`, etc., lines 269–276).

One subtlety the code gets right: a conditional branch needs both rs1 and rs2
even when the decoder set `opa_select`/`opb_select` for something else, since
the branch comparison uses the architectural register values. The explicit
`dec_cond_branch ||` term in both muxes is what takes care of that.

#### CDB arbitration

Lines 468–502. There is one CDB and two producers, the multiplier and the
inline ALU. The arbitration policy is "MULT wins":

```systemverilog
if (mult_done) begin
    cdb_valid = 1'b1;
    cdb_tag   = mult_dest_tag_reg;
    ...
end else if (issue_accept && !issue_is_mult) begin
    cdb_valid = 1'b1;
    cdb_tag   = rs_issue_dest_tag;
    ...
end
```

"MULT wins" is the natural choice when one producer is pipelined and the other
is single-cycle. The MULT can't stall midstream. Its result will land this
cycle whether the CDB is free or not, so giving it priority is the only way to
avoid dropping results on the floor. The ALU result, by contrast, is computed
combinationally from the RS issue port and is only consumed if `issue_accept`
is true, which already includes the `!mult_done` check at line 136:

```systemverilog
assign issue_accept = rs_issue_valid &&
                      (issue_is_mult ? !mult_busy : !mult_done);
```

So the RS will not issue a non-mult instruction in any cycle where the MULT
is about to broadcast. That keeps the CDB single-driver and avoids races.

#### Writeback

Line 150:

```systemverilog
assign pipeline_commit_wr_en = rob_commit_valid && (rob_commit_dest_reg != 5'd0);
```

Compare to the baseline (line 127):

```systemverilog
assign pipeline_commit_wr_en = wb_regfile_en;
```

The writeback enable now comes from ROB commit, not from a wb-stage register
(which never existed in any meaningful sense at baseline). The `!= 5'd0` guard
prevents spurious writes to `x0`. The regfile is wired the same way one block
down at lines 210–212.

#### The error latch

Lines 117–118 and 507–516:

```systemverilog
EXCEPTION_CODE error_status_reg;
...
always_ff @(posedge clock) begin
    if (reset)
        error_status_reg <= NO_ERROR;
    else if (rob_commit_valid) begin
        if (rob_commit_halt)
            error_status_reg <= HALTED_ON_WFI;
        else if (rob_commit_illegal)
            error_status_reg <= ILLEGAL_INST;
    end
end
```

Halt and illegal-instruction faults are latched at commit, not at dispatch.
That's the right place to latch them. An illegal instruction that gets
squashed by an earlier branch should never show up in the architectural status,
and only latching at commit guarantees the visible exception state is always
in program order.

### The header edit: `verilog/sys_defs.svh`

```systemverilog
`define ROB_SZ xx
`define RS_SZ xx
...
`define NUM_FU_ALU 1
`define NUM_FU_MULT 1
```

ROB_SZ and RS_SZ revert to `xx`. The M1 values of 8 were testing-only, and now
that the modules are integrated into the actual pipeline, sizing is left for
the implementer to think about. NUM_FU_ALU and NUM_FU_MULT both get set to 1,
matching the single ALU and single multiplier instantiated in `pipeline.sv`.
Load and store FU counts stay at `xx` because there's still no LSQ.

This means the M2 `sys_defs.svh` will not preprocess cleanly until somebody
sets ROB_SZ and RS_SZ. The `$clog2(`ROB_SZ)` calls in `rs.sv` and `rob.sv`
require it.

### The Makefile state

The M2 Makefile is mid-merge. Lines 180–184:

```makefile
<<<<<<< Updated upstream
TESTED_MODULES = mult rob
=======
TESTED_MODULES = mult rob rs
>>>>>>> Stashed changes
```

The conflict markers are still in the file. This is a snapshot taken in the
middle of an integration; nobody has run `git diff --check` on it yet. It
needs to be resolved manually before `make` will even parse the file.

The `SOURCES` block at lines 331–339 is more interesting because it reveals a
mismatch with the actual directory contents:

```makefile
SOURCES = verilog/pipeline.sv \
          verilog/decoder.sv \
          verilog/rob.sv \
          verilog/rs.sv \
          verilog/regfile.sv \
          verilog/icache.sv \
          verilog/mult.sv \
          verilog/mult_stage.sv \
```

`verilog/rs.sv` is listed but it does not exist in `4340-p4-milestone2/verilog/`.
The file was deleted, or moved out, or never re-added when the M2 snapshot was
captured. Likewise `test/rs_test.sv` is gone from the test directory. The build
will not find these files. The snapshot is mid-merge: somebody is partway
through pulling M1 into M2 and the Makefile is referring to files that haven't
landed yet. It is worth knowing about so nobody spends a long afternoon trying
to figure out why `make` cannot find `rs.sv`.

The fix is mechanical: bring `rs.sv` back into `verilog/`, decide between
`mult rob` and `mult rob rs` for `TESTED_MODULES`, and remove the merge markers.
The pipeline instantiation at `pipeline.sv:330` already references the `rs`
module by name, so the missing file is the only thing standing between the
snapshot and a working build.

### The pipeline test change

`test/pipeline_test.sv` line 259 changes from `#2;` to `#0.1;`. The other
delays in the file (`#1;` at line 226, `#100` at line 308) are unchanged. The
practical effect is that the testbench now spaces its sub-cycle events at 100 ps
instead of 2 ns. With OoO execution, more combinational events resolve per
clock edge, and a 2 ns delay can race past valid intermediate states. Tightening
to 100 ps lets the simulator settle correctly.

### What was removed

`test/rs_test.sv` is gone from M2. Once the RS is part of the pipeline, the
meaningful integration test is the program-level bench running real RV32IM
code. Removing the standalone bench before the integration is verified feels
a bit eager though. If something at the pipeline level starts misbehaving,
there is no longer a fallback bench to confirm the RS works on its own.

## Side-by-side summary

| | baseline | milestone 1 | milestone 2 |
|---|---|---|---|
| pipeline type | 5-stage in-order, stubbed | unchanged | out-of-order |
| `rs.sv` | absent | new, 212 lines | referenced in Makefile, file missing |
| `rob.sv` | absent | absent | new, 253 lines |
| register renaming | none | none | RAT lives inside `rob.sv` |
| CDB | absent | absent | `cdb_valid/tag/value` plus branch fields |
| branch recovery | n/a | n/a | redirect at commit, no predictor |
| stall causes | cache miss only | cache miss only | cache miss + rs_full + rob_full + branch_pending |
| writeback path | mem/wb stage | mem/wb stage | ROB commit → regfile |
| `ROB_SZ` / `RS_SZ` | xx / xx | 8 / 8 (testing only) | xx / xx |
| `NUM_FU_ALU` / `NUM_FU_MULT` | xx / xx | xx / xx | 1 / 1 |
| `pipeline.sv` lines | 132 | 132 | 518 |
| build state | clean stub | clean | broken (mid-merge) |

## What's still missing after M2

The M2 snapshot has the skeleton of an OoO machine but it is nowhere near
feature-complete. The interesting gaps are visible right in the source.

The ROB's `flush` input is wired to `1'b0` at `pipeline.sv:286`. Branch
mispredict recovery is therefore a no-op. The design avoids needing it by
stalling the front end on every branch (the `branch_pending` term in the stall
expression). A real branch predictor will require driving `flush` with the
misprediction signal and walking the RAT back to the pre-branch state. The
infrastructure for the flush half is already in `rob.sv` at lines 168–177,
which handles the buffer reset and the RAT clear. The predictor side and the
RAT checkpointing side do not exist yet.

There is no LSQ and there is no data cache. The M2 pipeline can only run code
that doesn't touch memory after fetch. That is exactly the constraint the
`mult_no_lsq.s` test program targets: pure register/ALU/MUL traffic, no loads,
no stores. The "no_lsq" in the filename is a promise that this program does
not need a load-store queue to execute correctly. Real programs do.

Superscalar width is still 1 (`define N 1` in `sys_defs.svh`). Both the RS
free-slot scan and the issue scan are linear-priority, which is fine at width
1 and would need to become parallel when N grows. The starter file
`psel_gen.sv` is sitting right there for exactly this reason. Neither M1 nor
M2 use it yet.

And the merge markers in the Makefile plus the missing `rs.sv` need to be
cleaned up before the M2 snapshot will build at all.

## Reading order if you want to follow the code

If you want to read the source files in an order that makes the OoO logic
make sense, do them in this sequence:

1. `4340-p4/verilog/pipeline.sv` — to see the empty starting point
2. `4340-p4-milestone1/verilog/rs.sv` — the standalone scheduler
3. `4340-p4-milestone2/verilog/rob.sv` — the buffer with RAT
4. `4340-p4-milestone2/verilog/pipeline.sv` — how it all gets glued together,
   especially lines 222–278 (operand resolution), 283–359 (ROB and RS
   instantiation), and 468–502 (CDB arbitration)

Read `rs.sv` and `rob.sv` against each other if you can. They share the
same-cycle CDB bypass pattern, the same `entries`/`next_entries` discipline,
and the same explicit-priority next-state block. The two modules were clearly
written to fit together, even though the M2 snapshot has not finished pulling
them into the same tree.
