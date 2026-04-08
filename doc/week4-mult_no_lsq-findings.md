# `mult_no_lsq` hang — investigation notes (week4, deferred)

Status: deferred. The root cause probably lies outside the modules
currently under investigation (pipeline / ROB / RS / mult), in memory
or cache modules that have not yet been audited. The next session
should start by auditing `verilog/icache.sv`, `verilog/mem.sv` (or
`test/mem.sv` if that is the one in use), and any memory-side glue in
`test/pipeline_test.sv`.

## What the plan originally said

From `doc/week4-followup-plan.md`:

> `mult_no_lsq` nondeterminism — the merged pipeline sometimes produces 44
> correct writebacks in 45 seconds, other times produces 0 in 10+ minutes.
> Pre-existing bug inherited from milestone2 (which was previously unbuildable,
> so the bug was invisible until week3 unblocked integration testing).

## What actually happens (observed in this worktree, week4)

All runs so far on this branch have produced the same 44-writeback tail:

```
PC=00000000 … PC=00000064   (26 setup/li instructions)
PC=00000068 … PC=000000a4   (iter-1 full loop body — addi/slti/4x mul/add, 4x srli, addi, bne)
PC=00000068 REG[5]=00000002  (iter-2 addi)
PC=0000006c REG[6]=00000001  (iter-2 slti)
<HANG>
```

The pipeline does not make further progress. Specifically, simulator
time stops advancing somewhere around cyc ≈ 2192–2200. Verified by
logging a `[tick N]` print once per cycle: the stream of ticks stops
hard between 2192 and 2200 and never prints another tick regardless of
how long the sim runs (tried 60s, 120s, 180s, 300s, 600s wall clock).
That rules out "slow but progressing" and points to a genuine zero-time
simulator spin: a combinational loop or infinite delta cycle.

## Last events before the stall

Per-event logging (dispatch / commit / CDB / blocked-issue) gives this trace:

```
[cyc=2184] COMMIT head=1 NPC=000000a8 dest=0 val=0 is_br=1 tk=1 tgt=00000068   (iter-1 bne, taken)
[cyc=2185] DISP PC=00000068 tag=2  (iter-2 addi x5,x5,1)
[cyc=2186] DISP PC=0000006c tag=3  (iter-2 slti x6,x5,16)
[cyc=2186] CDB tag=2 val=2
[cyc=2187] DISP PC=00000070 tag=4  (iter-2 mul x11,x2,x3)
[cyc=2187] COMMIT head=2 dest=5 val=2
[cyc=2187] CDB tag=3 val=1
[cyc=2188] DISP PC=00000074 tag=5  (iter-2 add x11,x11,x4 — depends on tag 4)
[cyc=2188] COMMIT head=3 dest=6 val=1
[cyc=2189] DISP PC=00000078 tag=6  (iter-2 mul x12,x11,x3   — depends on tag 5)
[cyc=2190] DISP PC=0000007c tag=7  (iter-2 add x12,x12,x4   — depends on tag 6)
[cyc=2191] DISP PC=00000080 tag=0  (iter-2 mul x13,x12,x3   — depends on tag 7, tag wrap)
[cyc=2192] DISP PC=00000084 tag=1  (iter-2 add x13,x13,x4   — depends on tag 0)
[cyc=2192] CDB tag=4 val=8ea394b4  (iter-2 mul x11 completes)
[cyc=2192] ISS_BLOCKED op=00 is_mult=0 mult_busy=1 mult_done=1   (iter-2 add x11 ready via CDB bypass, but gated by mult_done)
<no further events — sim time frozen>
```

State snapshot at cyc=2192 (from inline dump):

```
stall=0 brpend=0 rs_full=0 rob_full=0 dispfire=1 rs_iv=1 iss_op=00 ism=0 iss_acc=0
mb=1 md=1 cdb=1 cdb_tag=4 rob_head=4 rob_cnt=5
  rob[0]: busy=1 ready=0 dest=13   (iter-2 mul x13, tag 0)
  rob[4]: busy=1 ready=0 dest=11   (iter-2 mul x11 — about to become ready via CDB this cycle)
  rob[5]: busy=1 ready=0 dest=11   (iter-2 add x11)
  rob[6]: busy=1 ready=0 dest=12   (iter-2 mul x12)
  rob[7]: busy=1 ready=0 dest=12   (iter-2 add x12)
  rs[0]: op=0a dt=6 s1r=0 s1t=5   (mul x12, waiting on add x11)
  rs[1]: op=00 dt=5 s1r=0 s1t=4   (add x11, waiting on mul x11 → woken up this cycle by CDB)
  rs[2]: op=00 dt=7 s1r=0 s1t=6   (add x12, waiting on mul x12)
  rs[3]: op=0a dt=0 s1r=0 s1t=7   (mul x13, waiting on add x12)
```

This is a reasonable pipeline state. iter-2's mul-x11 just finished,
its CDB is going out on the bus, the dependent add-x11 in the RS has
been woken up combinationally and is trying to issue, but is correctly
blocked for exactly one cycle by `mult_done` pulling `!mult_done` low
in `issue_accept`. Nothing here is obviously broken at the
pipeline/RS/ROB/mult level.

## What we ruled out

1. Hypothesis A: `mult_done` stuck high. Ruled out. `mult_done` is the
   registered output of the last `mult_stage` and goes high for exactly
   one cycle per operation. `mult_busy` clears one cycle after.
2. Hypothesis B: `mult_busy` / `mult_done` race in `pipeline.sv:417-431`.
   Ruled out structurally. `issue_accept` requires `!mult_busy`, so a new
   mult cannot co-occur with `mult_done` of the previous one.
3. ROB unit tests. `test/rob_test.sv` (newly written) passes all 10 test
   cases on both `make rob.pass` and `make rob.syn.pass`, covering
   dispatch, CDB complete, in-order commit, same-cycle RAT bypass,
   stale-clear protection, x0 guard, flush, full, and wraparound. The
   ROB module in isolation is sound.
4. "Nondeterminism" in the plan. I could not reproduce the
   nondeterminism. Every run on this worktree hangs at the same cycle
   (≈2192) with the same 44 writebacks. The hang is deterministic here.

## What we suspect (to check next session)

Simulation time itself stops advancing. Not "the pipeline stops retiring
but clock edges still fire" — the scheduler never leaves cycle 2192.
That usually indicates a combinational cycle or an X-driven delta-cycle
storm that causes VCS's scheduler to spin inside a single timestamp.

Possible sources outside the modules already audited:

- `test/mem.sv`: the memory model. A cache miss is in flight at the hang
  point (the icache issued a BUS_LOAD a few cycles earlier for the line
  at PC ≈ 0x90). If `mem.sv` has a combinational path from one of its
  inputs back to `mem2proc_response` / `tag` / `data` that activates
  under a specific request pattern, it could spin here.
- `verilog/icache.sv`: the icache has combinational logic for
  `update_mem_tag`, `unanswered_miss`, and `got_mem_data`. A corner
  case where `changed_addr`, `miss_outstanding`, and `got_mem_data`
  all interact with `Imem2proc_response` / `_tag` could create a
  feedback loop, especially when the cache line for the mul just
  resolved and the next address is already issuing a new request.
- `verilog/pipeline.sv` CDB arbitration (less likely): the else-if
  path would form a loop `alu_result → cdb_value → issue_src1_value →
  alu_result` if `issue_accept` were ever 1 simultaneously with
  `!mult_done`. At cyc=2192 `mult_done=1` so this path is inactive,
  but worth double-checking that nothing spuriously drives `cdb_valid`
  and forces the path.
- An X on the memory side. If `mem2proc_tag` glitches (e.g. mem
  returns a tag of 0 or X on a specific cycle pattern), the icache's
  `got_mem_data` could toggle at delta-cycle resolution and never
  settle.

## Recommended debugging next steps

1. Instrument the `icache.sv` / `test/mem.sv` boundary. Dump every cycle
   `proc2Imem_command`, `proc2Imem_addr`, `mem2proc_response`,
   `mem2proc_tag`, `mem2proc_data`, and the icache's `current_mem_tag`,
   `miss_outstanding`, `unanswered_miss`, `got_mem_data`, and
   `icache_data[current_index].valid`. Look at cycles 2170–2200.
2. Force an ASCII dump of VCS's convergence iteration count. VCS has a
   warning for combinational loops (`+warn=noTFIPC` is on but that is
   unrelated). Compile without that filter and look for
   `[SETUP_WILL_NOT_BE_MET]` or `[EVNT]` convergence warnings.
3. Try `+vcs+initreg+zero` and `+vcs+initreg+random`. If zero-init
   reliably progresses but random-init hangs, there is an X-propagation
   somewhere even though the unit tests passed.
4. Run `no_hazard`, `fib`, `copy`, `saxpy`, `sampler` one by one with
   the same wall-clock budget. If they all hang at similar points
   involving icache line boundaries, memory/icache is strongly
   implicated. If only `mult_no_lsq` hangs, the interaction with the
   mult FU is relevant.
5. Temporarily hard-wire `MEM_LATENCY_IN_CYCLES` to 1 and see if the
   hang goes away. If it does, it is a memory-side interaction, not a
   core pipeline bug. Do not commit that change — `MEM_LATENCY_IN_CYCLES`
   is a hard constraint from the spec.
6. Open Verdi on the 44-writeback state. Once the GUI is available,
   step a single cycle past cyc=2192 and watch which signals are being
   re-evaluated. VCS's delta-cycle view will point at the loop.

## What is known-good after this session

- `test/rob_test.sv` written and committed on `week4`. `make rob.pass`
  and `make rob.syn.pass` both green.
- `make rs.pass` still green (no regression).
- The pipeline runs through all 26 setup instructions, a full first
  iteration of the loop (16 insts including 4 muls, 4 adds, 4 srli,
  the addi, and a taken bne), and the first 2 instructions of iter 2
  (addi and slti). The core P6 dataflow — rename, dispatch, issue,
  execute, mul, CDB broadcast, in-order commit, taken-branch redirect
  — is functional through at least 44 consecutive committed
  instructions.

## Files touched during the investigation (all reverted at the end)

- `test/pipeline_test.sv`: added `[tick]`, `[dbg cyc=…]`, per-event
  dispatch/commit/CDB/blocked-issue logging, lowered the
  `debug_counter` hard-halt from 50M to 2600 for fast iteration, added
  a state snapshot block. All of this has been reverted to the
  original file before moving on.

## Take-away

The hang is real and deterministic, but its root cause is almost
certainly not in `rob.sv`, `rs.sv`, or `pipeline.sv` proper. Those all
do the right thing right up until simulator time stops. The next
session should audit `test/mem.sv`, `verilog/icache.sv`, and the
mem-bus glue in `pipeline.sv`, and look for a combinational loop or
delta-cycle storm that only activates when a cache line for the iter-2
mul chain is being fetched concurrently with the mul FU's CDB
broadcast.
