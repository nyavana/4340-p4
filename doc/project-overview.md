# Project Overview

This document is the orientation guide for the EECS 4340 final project repository.
It is meant for someone who has never opened the source before and wants to know:

- what the project is,
- what we have built so far,
- where each file lives and what it does,
- how to actually run things,
- and where the rough edges are.

The full specification is in [`project-description.md`](project-description.md).
Our team's plan for hitting it is in [`project-proposal.md`](project-proposal.md).
This file complements those two; it does not repeat them.

---

## 1. What the project is

We are extending the VeriSimpleV RISC-V pipeline from Project 3 into a synthesizable
**out-of-order** processor. The team picked a **P6-style** design: in-order fetch and
decode, register renaming through a Register Alias Table, out-of-order issue and
execute, broadcast on a Common Data Bus, and in-order commit through a Reorder
Buffer. The processor is built and tested module by module, then integrated into a
single top-level `pipeline.sv` that runs real RISC-V binaries through the existing
testbench harness.

Our processor today is one instruction wide. The architecture has room for more,
and the proposal calls out 2-way superscalar plus early tag broadcast as the
"difficult" advanced features we want to add later.

---

## 2. The constraints we cannot break

These are baked into the spec, not into our design choices. They appear here so a
new contributor does not accidentally cross one of them.

1. **I-cache and D-cache are each capped at 256 bytes**, 512 bytes total.
2. **Memory latency is fixed at 100 ns.** In `verilog/sys_defs.svh:79` it is
   computed as `MEM_LATENCY_IN_CYCLES = ceil(100 / CLOCK_PERIOD)`. Do not "fix" a
   slow program by lowering it.
3. **Number of CDBs may not exceed the superscalar width** of the narrowest stage
   of the pipeline. We are 1-wide today, so we have one CDB.
4. **The multiplier must be the one from Project 2**, in `verilog/mult.sv` and
   `verilog/mult_stage.sv`. The number of pipeline stages (`MULT_STAGES`) is
   tunable, the underlying logic is not.

---

## 3. Timeline of what we built

### 3.1 Starter (`4340-p4`, instructor-provided)

The starter ships with the in-order P3 pipeline as a reference, a multiplier from
P2, an instruction cache, a register file, a decoder, a priority selector helper,
and a stripped-down `pipeline.sv` skeleton. There is no ROB, no RS, no RAT, no
LSQ, no branch predictor. `verilog/sys_defs.svh` carries placeholder `xx` values
for `ROB_SZ`, `RS_SZ`, `LSQ_SZ`, and other parameters that the team is expected to
fill in. `make simv` does not build out of the box because the skeleton
`pipeline.sv` references modules that do not exist yet.

### 3.2 Week 1 / Milestone 1

Two team members worked on two complementary pieces in parallel branches on
the GitHub repo `CSEE4340-26/p4.GaPiChiXuXu`:

- Branch **`milestone1`** added `verilog/rs.sv` (the Reservation Station) and its
  unit test `test/rs_test.sv`, and set `ROB_SZ` and `RS_SZ` to concrete values.
- Branch **`milestone2`** added `verilog/rob.sv` (the Reorder Buffer with the RAT
  embedded) and a complete refactor of `verilog/pipeline.sv` from the in-order
  skeleton into the P6 dataflow we use today.

These two branches had to land together: `pipeline.sv` from `milestone2`
instantiates `rs rs_0 (...)`, but `rs.sv` only existed on `milestone1`. Neither
branch built end-to-end on its own.

### 3.3 Week 3: the integration merge

A new `week3` branch was created off `milestone1`, then `milestone2` was merged
into it. The auto-merge handled `sys_defs.svh` (the two branches edited disjoint
parameter lines). Two conflicts had to be resolved by hand:

- `Makefile:180` had a `<<<<<<< Updated upstream` block left over from a botched
  `git stash pop`, on top of the milestone1/milestone2 conflict. It was collapsed
  to `TESTED_MODULES = mult rob rs`.
- A nested conflict in the same hunk introduced an `RS rs` typo. That got
  cleaned up at the same time.

After the merge:
- `make simv` compiled cleanly for the first time on any branch.
- `make no_hazard.out` ran end-to-end: 14 instructions, 731 cycles, clean halt
  on `HALTED_ON_WFI`, all writebacks correct.
- `make mult_no_lsq.out` revealed a deeper bug that had been invisible before
  (because `milestone2` was previously unbuildable).

The full merge writeup, including conflict resolution and verification, is in
[`week3-merge-report.md`](week3-merge-report.md).

### 3.4 Week 4: Milestone 2 stabilization

Week 4 was about closing the two biggest gaps the integration exposed.

The first gap was the missing ROB testbench. `make rob.pass` did not even
compile, because `test/rob_test.sv` did not exist. We wrote it, and it now
covers ten scenarios: dispatch, CDB completion, in-order commit, same-cycle
RAT bypass, stale-clear protection, the x0 guard, flush, full detection, and
wraparound. Both `make rob.pass` and `make rob.syn.pass` are green.

The second gap was `mult_no_lsq`. On the v2 branch this hangs deterministically:
the simulator stops advancing time around cycle 2192, after 44 correct
writebacks. The pipeline gets through the setup phase, a full first iteration
of the loop, and the first two instructions of the second iteration before it
freezes. We ruled out the multiplier handshake, the ROB, and the RS in
isolation. The current suspicion is a combinational cycle or delta-cycle storm
at the icache / `mem.sv` boundary. Full investigation in
[`week4-mult_no_lsq-findings.md`](week4-mult_no_lsq-findings.md); the earlier
debugging plan is in [`week4-followup-plan.md`](week4-followup-plan.md).

The current canonical state of the project is the `week4-merge-v2` branch on
`nyavana/4340-p4`, mirrored locally in `4340-p4-week4-merge-m2-v2/`.

### 3.5 Week 5: Milestone 3 — memory ops via LSQ + write-back D-cache

Week 5 was the memory milestone. The pipeline now runs loads and stores
end-to-end through a Load-Store Queue and a write-back data cache, all the
RV32IM byte/half/word variants work, and JAL/JALR finally write the return
address into the destination register. That last one was a milestone 2 bug
that nobody noticed until C programs started making function calls and
jumping to address zero.

The new pieces:

- `verilog/dcache.sv`: a 32-line, 64-bit-wide, direct-mapped, write-back,
  write-allocate D-cache. 256 bytes total, exactly at the spec cap. Sub-word
  stores are absorbed as a byte-enable mask on the line; only line evictions
  write back, and the writeback is always a full doubleword (the only thing
  `mem.sv` accepts in cache mode).
- `verilog/lsq.sv`: a combined load/store queue, FIFO of 8 entries by
  default. Snoops the CDB to wake up base/data operands, computes addresses
  with an internal AGU, and arbitrates the cache request. Memory ops bypass
  the RS so the LSQ can keep its entries in program order.

The memory ordering policy is deliberately conservative: head-only, no
store-to-load forwarding. A load behind an in-flight store waits for the
store to fully drain to the cache. Stores hold their (addr, data, mem_size)
until the ROB retires them; only then do they get released. Architectural
memory is never written by a mis-speculated path, and there is no forwarding
correctness work to chase. The cost is performance: a load behind a store
pays the full miss latency at least once per line.

Pipeline integration touched several places:

- The old inline single-line load FU is gone. Memory ops bypass the RS at
  dispatch and allocate directly into the LSQ.
- A new dispatch-side store-data resolver always reads `rs2` for stores.
  The existing `dispatch_src2` returns the immediate for an S-type encoding,
  so it cannot double-duty here.
- CDB priority is now MULT > LSQ load complete > ALU. Stores never use the
  CDB; they use a dedicated `store_done_valid` / `store_done_tag` sideband
  on the ROB.
- Bus arbitration: dcache priority over icache, with each cache's view of
  `mem2proc_response` masked to the cycle it actually drove the bus.
- The branch-target broadcast for JAL/JALR now uses `alu_result` (which is
  `PC + Jimm` for JAL and `rs1 + Iimm` for JALR), with bit 0 cleared per the
  JALR spec. The pre-computed `branch_target_buf` was wrong for JALR: it
  always added a J-immediate to the PC.

The ROB grew an `is_store` field per entry, the new `store_done` sideband
ports, and a commit value override for branches with non-zero destinations
(JAL/JALR), which now commit `entries[head].NPC` instead of the
CDB-broadcast value. That is the return address the milestone 2 pipeline
was silently writing as zero.

The result: 18 of 33 test programs reach `HALTED_ON_WFI`, up from roughly
30% at the milestone 2 baseline. New passes include `saxpy` (the first real
loads-and-stores-in-a-loop program), `fib_rec`, `sampler`, and five C
programs (`basic_malloc`, `fc_forward`, `insertionsort`, `omegalul`,
`priority_queue`) — all of which depend on the JAL/JALR fix. Both
`make dcache.pass` / `make dcache.syn.pass` and `make lsq.pass` /
`make lsq.syn.pass` are green. Full per-program results are in
[`milestone3-results.md`](milestone3-results.md), and the full writeup is
in [`milestone3-report.md`](milestone3-report.md).

The cycle-2192 `mult_no_lsq` hang is still unresolved. It now shares its
signature with about a dozen other programs that have tight back-to-back
inner loops: PC sits on the first instruction of the second iteration, the
LSQ has a single store at its head with `committed=1` and `in_flight=1`,
and `dcache_done` never asserts. The same workload with NOPs added between
every instruction (`copy_long`) passes cleanly, so the deadlock is timing-
or wakeup-related rather than functional. Diagnosing it is the top item to
chase next.

The current canonical state of the project is the `milestone3` branch in
`4340-p4-milestone3/`.

---

## 4. Architecture in one read-through

The processor is one big module, `pipeline.sv`, plus two large submodules
(`rob.sv` and `rs.sv`) and a handful of leaf modules (`icache`, `regfile`,
`decoder`, `mult`, `mult_stage`, `psel_gen`).

Walk through it the way an instruction does.

**1. Fetch.** `PC_reg` drives the icache. The icache returns a 64-bit line, and
the pipeline picks the high or low half based on `PC_reg[2]`. The fetch stalls
when any of the following is true: the icache is not ready, the RS is full, the
ROB is full, or there is a branch already in flight (`branch_pending`). See
`pipeline.sv:131-185`.

**2. Decode.** The fetched word goes into `decoder.sv`, which produces operand
selects, the ALU function, and a handful of flags (`rd_mem`, `cond_branch`,
`uncond_branch`, `halt`, `illegal`, …). The decoder is the same one we used in
P3, copied verbatim.

**3. Rename and operand resolution.** For each source register the pipeline
queries the ROB's embedded RAT (`rob.sv` query ports `query1_*` / `query2_*`).
The query returns one of three answers:

- *Not pending*: no in-flight ROB entry owns this register. Read the regfile.
- *Pending and ready*: an in-flight entry owns it but its value is already in
  the ROB. Forward that value.
- *Pending and not ready*: an in-flight entry owns it but it has not finished
  yet. The instruction goes into the RS with that ROB tag and waits.

The query also implements **same-cycle CDB bypass**: if the CDB is broadcasting
the very tag the RAT points at this cycle, the query returns ready with the
CDB value, so the new instruction can be dispatched immediately as ready.
Constant operands (PC, NPC, immediates) bypass the RAT entirely. See
`pipeline.sv:243-299`.

**4. Dispatch.** A single dispatch fires both ROB allocation and RS allocation in
the same cycle. The ROB hands back `dispatch_tag` (= current tail), which becomes
the renamed destination tag for the instruction. The RAT is updated in the same
cycle (except for `x0`, which is never tracked). At the same time, if this is a
branch, the pipeline latches its target and `funct3` into `branch_target_buf` /
`branch_funct3_buf` and asserts `branch_pending`, which stalls the front-end
until the branch commits. See `pipeline.sv:304-402`.

**5. Issue.** The RS finds the oldest entry whose two source operands are both
ready (with same-cycle CDB wakeup folded in) and drives `issue_valid` plus the
opcode and operand values out to the execution side. The issue is gated by
`issue_accept`, which ensures the right functional unit is free. The MULT FU has
priority: while `mult_done` is pulsing, the ALU CDB path is held off so that
MULT and ALU never collide on the bus. Memory ops do **not** flow through the
RS — they bypass it at dispatch and go straight into the LSQ, which keeps loads
and stores in program order. See `rs.sv:104-147` and `pipeline.sv:140-147`.

**6. Execute.** Three units:

- The **ALU** is single-cycle and inline in `pipeline.sv:490-504`. It handles
  add, sub, the logic ops, the shifts, SLT, and SLTU.
- The **multiplier** is the pipelined `mult` module from P2, defaulting to four
  stages. The pipeline pre-extends operands to 64 bits depending on whether the
  multiply is signed or unsigned, and selects the upper or lower 32 bits of the
  product depending on the variant. `pipeline.sv:407-452`.
- **Conditional branches** resolve inline next to the ALU using the latched
  `branch_funct3_buf` to pick BEQ / BNE / BLT / BGE / BLTU / BGEU. JAL and
  JALR use `alu_result` as the branch target (with bit 0 cleared for JALR),
  not the dispatch-time `branch_target_buf` — that buffer is only correct for
  conditional branches and JAL with a J-immediate. The branch outcome and the
  computed target ride the CDB on the same cycle.

The **LSQ** (`verilog/lsq.sv`) handles all loads and stores. Memory ops are
allocated into the LSQ at dispatch, not the RS. The LSQ snoops the CDB to
wake up its base/data operands, computes effective addresses with an internal
AGU, arbitrates for the D-cache one entry at a time from the head, and drives
either `load_done_*` (for loads) or `store_done_*` (for stores) when the
cache responds. The policy is head-only with no store-to-load forwarding: a
load behind an unresolved store waits. Stores hold their data until the ROB
commits the matching entry; only then are they released to the cache. This
guarantees that architectural memory is never written by a mis-speculated
path.

The **D-cache** (`verilog/dcache.sv`) is a 32-line, write-back, write-allocate
direct-mapped cache, 256 bytes total. Sub-word stores never round-trip
through main memory: the cache absorbs them as a byte-enable mask on the
line, and only line evictions write back as a full doubleword. The dcache
takes priority over the icache on the shared memory bus.

**7. CDB.** One bus. Three potential drivers, with this priority (`pipeline.sv`):

1. MULT, when `mult_done` pulses,
2. LSQ load, when `load_done` pulses,
3. ALU and branch results, when both MULT and LSQ-load are quiet.

Stores never use the CDB at all. They report completion to the ROB through a
dedicated `store_done_valid` / `store_done_tag` sideband, which keeps the CDB
free for value-producing instructions. Branches always broadcast on the CDB,
but the PC redirect happens at commit, not at execute.

**8. ROB completion.** When the CDB fires, the ROB marks the targeted entry
ready, latches its value, and (for branches) latches `take_branch` and
`branch_target`. Stores complete through the parallel `store_done` sideband
instead of the CDB; the ROB just marks the matching entry ready without
touching its value. The next-state ordering inside `rob.sv` is **flush >
CDB / store_done > commit > dispatch**. That ordering is what makes
dispatch-and-commit-in-the-same-cycle correct.

**9. Commit.** The ROB head retires when it is busy and ready. Commit drives the
regfile write port, latches `HALTED_ON_WFI` or `ILLEGAL_INST` into
`error_status_reg`, and on a taken branch redirects `PC_reg` to the committed
target. For JAL/JALR, the committed value is overridden to be the entry's
NPC (the return address), since the CDB-broadcast value for those is the
branch target, not the link value. The RAT entry for the committing
destination is cleared *only* if it still points at this ROB slot, so a
younger instruction that already re-renamed the same architectural register
does not get its mapping clobbered. The ROB also exposes `commit_tag` and
`commit_is_store` so the LSQ can release its head store at exactly the right
cycle.

That is the entire dataflow. There is no separate physical register file: the
ROB entries themselves are the physical registers, which is why
`PHYS_REG_SZ = 32 + ROB_SZ` in `sys_defs.svh:29`.

---

## 5. File-by-file reference

All paths are relative to the project root.

### 5.1 `verilog/sys_defs.svh`

The single source of truth for global parameters and shared types.

- Superscalar width `N`, ROB and RS sizes, `PHYS_REG_SZ`.
- `LSQ_SZ` (= 8) and `DCACHE_LINES` (= 32, the spec cap at 256 bytes).
- Memory parameters: `CACHE_MODE`, `MEM_LATENCY_IN_CYCLES`, `NUM_MEM_TAGS`.
- Multiplier stage count (`MULT_STAGES`, default 4).
- The `INST` union typedef, `EXCEPTION_CODE`, `ALU_OPA_SELECT`, `ALU_OPB_SELECT`,
  `ALU_FUNC`, `MEM_SIZE`, `BUS_COMMAND`.
- The `IF_ID_PACKET` / `ID_EX_PACKET` / `EX_MEM_PACKET` / `MEM_WB_PACKET`
  structs from the in-order P3 pipeline. Our P6 design does not use them; they
  are kept for reference and to keep the legacy `verilog/p3/` tree compiling.

`BRANCH_PRED_SZ` is still the literal `xx` placeholder — the predictor has
not landed yet.

### 5.2 `verilog/ISA.svh`

The RISC-V opcode and immediate-extraction macros (`RV32_LUI`, `RV32_BEQ`,
`RV32_signext_Iimm`, …). Read-only data; only the decoder and the few inline
sign-extends in `pipeline.sv` consume it.

### 5.3 `verilog/decoder.sv`

Combinational instruction decoder. Reused from P3 unchanged. Takes a 32-bit
`INST` plus a `valid` bit and produces:

- `opa_select` / `opb_select` (which mux input goes into operand A and B),
- `alu_func` (which ALU operation),
- `has_dest`, `rd_mem`, `wr_mem`, `cond_branch`, `uncond_branch`, `csr_op`,
  `halt`, `illegal`.

When `valid` is low the decoder behaves like a NOP. Unknown encodings set
`illegal = 1`.

### 5.4 `verilog/regfile.sv`

The architectural register file. Two read ports and one write port.

- `x0` always reads as zero. Writes to `x0` are ignored.
- Internal forwarding: if a read index matches the write index this cycle and
  `write_en` is high, the read returns `write_data` (the new value).

In our P6 design the regfile is read at fetch (speculatively, by index), and
written only at commit. Physical register values live in the ROB, not here.

### 5.5 `verilog/icache.sv`

A 32-line, 64-bit-wide, direct-mapped, **blocking** instruction cache. 256 bytes
total, which exactly hits the spec cap.

The interesting part is the distinction between **cache tags** and **memory
tags**. The cache tag is the upper bits of the address that index into the
line. The memory tag is a 4-bit transaction id that `mem.sv` hands out to keep
multiple in-flight memory requests straight (up to 15 of them, with tag 0
reserved as a sentinel).

On a miss the cache asserts `BUS_LOAD`, captures the response tag from
`Imem2proc_response`, and waits for the memory to come back with that same tag
on `Imem2proc_tag` along with the data on `Imem2proc_data`. While it is waiting
it does not issue another request. If the address changes mid-wait the cache
abandons the request entirely. See `icache.sv:86-129`.

The cache gives the dcache priority on the shared memory bus. From the
`pipeline.sv` side, when the dcache is driving the bus the icache's view of
`mem2proc_response` and `mem2proc_tag` is masked so the cache does not
mistake the dcache's response for its own. The mask uses the combinational
`*_drives` signals directly, which evaluate from registered state at
`always_ff` sample time and naturally give the previous cycle's drive — the
cycle the response was actually allocated for.

### 5.6 `verilog/dcache.sv`

A 32-line, 64-bit-wide, direct-mapped, write-back, write-allocate data cache.
256 bytes total, the same spec cap as the icache.

Each line holds a tag, a valid bit, a dirty bit, 64 bits of data, and an
8-bit byte-valid mask. The byte-valid mask is what lets sub-word stores
stay local: the cache marks only the bytes that have been written, and on
a writeback (always a full doubleword, since that is all `mem.sv` accepts
in cache mode) the unmodified bytes come from the previous line state.

Three request paths share one state machine:

- **Load.** On a hit, the cache returns the requested word/half/byte in the
  same cycle. On a miss, it issues a `BUS_LOAD`, captures the memory tag,
  waits for the line to come back, fills the entry, and then completes the
  load. If the entry being evicted is dirty, the writeback fires first, and
  the load waits behind it.
- **Store.** On a hit, the cache OR-merges the new bytes into the line and
  marks the entry dirty. On a miss, it does a write-allocate (load the line,
  then merge), with the same dirty-eviction handling.
- **Writeback.** Driven only by line evictions on a miss. Stores never go
  directly to main memory; they live in the cache until the line is kicked
  out.

The cache exposes `dcache_busy` so the LSQ can hold its head request, and
`dcache_done_load` / `dcache_done_store` pulses so the LSQ knows when to
advance.

### 5.7 `verilog/rob.sv`

The Reorder Buffer with the Register Alias Table embedded inside it. There is
no separate map-table module; the RAT lives here as `rat_busy[32]` and
`rat_tag[32]`.

Each ROB entry holds:

```
busy, ready, dest_reg, value, NPC,
halt, illegal, is_branch, is_store, take_branch, branch_target
```

Three groups of ports:

- **Dispatch side.** Inputs: `dispatch_valid`, `dispatch_dest_reg`,
  `dispatch_NPC`, `dispatch_halt`, `dispatch_illegal`, `dispatch_is_branch`,
  `dispatch_is_store`. Outputs: `rob_full`, `dispatch_tag` (= current tail).
- **Complete side.** The CDB inputs: `cdb_valid`, `cdb_tag`, `cdb_value`,
  `cdb_take_branch`, `cdb_branch_target`. The ROB marks
  `entries[cdb_tag].ready = 1` and stores the value. Stores complete
  through a parallel sideband (`store_done_valid`, `store_done_tag`)
  instead of the CDB, so they do not have to fight value-producing
  instructions for the bus.
- **Commit side.** Outputs that drive the regfile write and the PC redirect:
  `commit_valid`, `commit_dest_reg`, `commit_value`, `commit_NPC`,
  `commit_halt`, `commit_illegal`, `commit_is_branch`, `commit_take_branch`,
  `commit_branch_target`, plus `commit_tag` and `commit_is_store` so the
  LSQ knows when its head store has been retired and can release it to the
  cache. Commit fires whenever the head entry is busy and ready. For JAL
  and JALR (the only branches with a non-zero destination), the committed
  value is overridden to the entry's NPC, since the CDB-broadcast value is
  the branch target and the link register needs the return address. That
  override is what fixed the milestone 2 silent-zero JAL/JALR bug.

Two **RAT query ports** answer rename questions at dispatch time. They include
same-cycle CDB bypass: if the CDB is completing the same tag the RAT points at
right now, the query returns `ready=1` with `cdb_value`. That bypass is what
lets a producer and a consumer dispatched in the same window get away with one
fewer stall cycle.

The next-state combinational block has a strict priority: **flush, then CDB
complete, then commit, then dispatch.** Reordering those blocks will break
either same-cycle CDB completion or same-cycle dispatch-on-the-tail-after-commit.
The stale RAT clear at commit (`rob.sv:189-200`) only clears the RAT entry if
it still points at the head being committed; if a younger instruction has
already re-renamed the same architectural register, the older commit leaves
the RAT alone.

Flush is wired to `1'b0` from `pipeline.sv` for now. It will become live
when the branch predictor lands and we need to recover from a mispredict.

### 5.8 `verilog/rs.sv`

The Reservation Station. Holds entries waiting for operands, snoops the CDB to
wake them up, and issues the oldest ready entry to the functional units.

Each entry holds:

```
busy, op[7:0], dest_tag,
src1_ready, src1_tag, src1_value,
src2_ready, src2_tag, src2_value
```

The `op` field is the 8-bit packed dispatch opcode. From `pipeline.sv:138`:

```
op[7]   = rd_mem            (load)
op[6]   = uncond_branch     (JAL/JALR)
op[5]   = cond_branch       (B-type)
op[4:0] = alu_func
```

The pipeline reads those bits back in `pipeline.sv:140-147` to decide
`issue_is_mult`, `issue_is_branch`, `issue_is_load`.

Three combinational blocks dominate `rs.sv`:

1. **Free-slot search.** A simple priority for-loop finds the lowest-index free
   entry; that index becomes the dispatch slot.
2. **Effective ready computation.** For every entry, its `src*_ready` is OR'd
   with `(cdb_valid && cdb_tag == src*_tag)` to fold in the same-cycle CDB
   wakeup. That is what lets an instruction be issued in the same cycle it
   receives its last operand on the CDB.
3. **Issue selection.** Another priority for-loop picks the oldest entry with
   both effective-ready bits set. The selected entry's opcode, dest tag, and
   operand values drive the issue ports. The forwarded value uses the CDB
   bypass mux directly so the value is correct even if the CDB is supplying it
   this cycle.

The next-state block applies wakeup, then removes the issued entry (if
`issue_fire`), then inserts the dispatched entry (if there is room).

The current implementation uses hand-rolled priority loops rather than
`psel_gen.sv`. That is fine at `RS_SZ=8`, and trivial to swap out if we go
superscalar.

Note that since milestone 3, the RS no longer holds memory ops at all.
Loads and stores bypass the RS at dispatch and go straight into the LSQ;
the RS only sees ALU, MULT, and branch ops.

### 5.9 `verilog/lsq.sv`

The Load-Store Queue. A circular FIFO of 8 entries (`LSQ_SZ`), in program
order, that owns every load and store from dispatch through retirement.

Each entry holds:

```
busy, is_store, mem_size, signed_load,
addr_ready, addr_value, base_tag, base_value, base_ready, imm,
data_ready, data_tag, data_value, data_committed,
dest_tag, in_flight
```

Three things happen in the entry's lifetime:

1. **Allocate at dispatch.** The pipeline drives `dispatch_valid` along with
   the ROB tag, the base register's RAT lookup, the immediate, and (for
   stores) the data register's RAT lookup. The LSQ writes a new tail entry
   with whatever operands were already ready and the rename tags for
   anything that was not.
2. **Wake up via the CDB.** Each entry snoops `cdb_valid` / `cdb_tag` /
   `cdb_value`. When the CDB tag matches a `base_tag` or `data_tag`, the
   matching field flips ready and stores the value. Same-cycle wakeup is
   folded in the same way the RS handles it.
3. **Drain at the head.** The head entry is the only one that can drive the
   D-cache. For loads, the LSQ waits until the address is ready and there
   is no unresolved store ahead of it (which is always the case for the
   head, by definition), then issues the cache request and reports back on
   `load_done_valid` / `load_done_tag` / `load_done_value` when the cache
   responds. For stores, the LSQ has to wait until the ROB commits the
   matching entry — that is what `commit_tag` and `commit_is_store` from
   the ROB are for. Only then is the store released to the cache, and the
   `store_done` sideband fires when it lands.

The head-only policy and the lack of store-to-load forwarding are
deliberate. There is no forwarding correctness work to chase, and
architectural memory cannot be written on a mis-speculated path. The
trade-off is that a load behind a store pays the full cache miss latency
at least once per line.

A `flush` input exists for branch-mispredict recovery, but it is currently
tied off because branches still serialize the front-end via
`branch_pending`. When early branch resolution lands as an advanced
feature, the LSQ flush will need to drop in-flight non-committed entries
and abandon any in-flight cache requests.

### 5.10 `verilog/mult.sv` and `verilog/mult_stage.sv`

The pipelined multiplier from P2. `mult.sv` is just a wiring shim that chains
`MULT_STAGES` instances of `mult_stage`. Each stage processes
`SHIFT = 64 / MULT_STAGES` bits of the multiplier per clock, accumulating into
a running 64-bit sum and shifting the operands. Latency is `MULT_STAGES` cycles,
throughput is one per cycle once the pipeline is primed.

The pipeline drives this with `start = issue_accept && issue_is_mult`, and
captures the result on `done`. `MULT_STAGES` is set in `sys_defs.svh:42`. It
should be retuned against synthesis slack later; right now it sits at the
default of 4.

The pipeline pre-extends operands before sending them in: signed-extended for
`MUL` / `MULH`, zero-extended for `MULHU`, mixed for `MULHSU`. After the
multiply finishes, the pipeline picks the lower or upper 32 bits of the
product depending on the variant. See `pipeline.sv:407-452` and
`pipeline.sv:535-540`.

### 5.11 `verilog/psel_gen.sv`

A parameterized priority selector. Takes a `WIDTH`-bit request vector and
returns up to `REQS` simultaneous one-hot grants, using a wired-AND
implementation that synthesizes faster than a hand-rolled for-loop. The
1-wide design does not use it yet, but a superscalar build will need it
to pick multiple oldest-ready entries from the RS in one cycle.

### 5.12 `verilog/pipeline.sv`

The top-level. Wires all of the above into the dataflow described in
section 4. About 720 lines now, most of it port plumbing, the
operand-resolution muxes, the inline ALU, the inline branch resolver, the
multiplier handshake, the LSQ instantiation and store-data resolver, the
dcache instantiation, the dcache/icache bus arbitration, the CDB priority
arbiter, and the PC update logic. There is no other top-level glue file;
everything is here.

Notable signals to grep for when navigating it:

- `stall` — global front-end stall. Set by icache miss, RS full, ROB full, or
  pending branch.
- `branch_pending` — set at dispatch of any branch, cleared when the branch
  commits. Serializes branches.
- `branch_target_buf`, `branch_funct3_buf` — branch info latched at dispatch
  so the inline branch resolver can use it later when the branch issues.
- `dispatch_fire` — handshake bit that drives both ROB and RS dispatch.
- `dispatch_tag` — the renamed destination tag, equal to the ROB tail.
- `cdb_valid`, `cdb_tag`, `cdb_value`, `cdb_take_branch`, `cdb_branch_target` —
  the broadcast bus.
- `store_done_valid`, `store_done_tag` — the store completion sideband from
  the LSQ to the ROB. Stores never use the CDB.
- `issue_accept`, `mult_busy`, `mult_done`, `load_done` — the issue
  arbitration that prevents multiple FUs from colliding on the CDB.
- `error_status_reg` — latched halt/illegal exception code that the testbench
  watches to know when to stop.

### 5.13 `verilog/p3/`

Legacy P3 in-order pipeline (`pipeline.sv`, `stage_if.sv`, `stage_id.sv`,
`stage_ex.sv`, `stage_mem.sv`, plus its own `regfile.sv` and `ISA.svh`). Not
compiled into the P4 build. It is kept around as a reference, and because the
decoder and a few datapath details in our P4 work were lifted from here.

---

## 6. Test infrastructure

All testbenches live in `test/`. The build system expects each tested module to
have a matching testbench file: `verilog/foo.sv` pairs with `test/foo_test.sv`,
declared in the Makefile as `TESTED_MODULES = mult rob rs dcache lsq`.

A testbench is considered passing only if it `$display`s the literal string
`@@@ Passed`. The `.pass` Makefile targets are just `grep`. Failures should
print `@@@ Incorrect`.

### 6.1 `test/mem.sv`

The simulated main memory. 64 KB, 64-bit lines, 100 ns latency. Hands out 4-bit
transaction tags (1–15) on requests, returns data with the matching tag after
the latency. Used by both `pipeline_test.sv` and `vtuber_test.sv`. This is a
test-side model, not a synthesizable module.

### 6.2 `test/pipeline_test.sv`

The full-processor testbench. Loads a `.mem` file into `mem.sv`, drives the
clock, watches `pipeline_completed_insts` and `pipeline_error_status`, and
dumps writebacks (`<prog>.wb`) and a per-cycle pipeline trace (`<prog>.ppln`)
to `output/`. Correctness is verified by comparing the `.wb` file against a
golden file.

### 6.3 `test/mult_test.sv`

Unit testbench for the pipelined multiplier. Drives random and edge-case
operand pairs, waits for `done`, checks the product against a software
multiply.

### 6.4 `test/rob_test.sv`

Unit testbench for the ROB. Ten test cases:

1. Basic dispatch → CDB complete → commit.
2. In-order commit despite out-of-order completion.
3. RAT query returns pending + tag for a pending write.
4. Same-cycle CDB bypass in the RAT query.
5. RAT clears on commit when still the latest writer.
6. RAT stale-clear protection when a younger writer has already renamed.
7. The `x0` guard (RAT never tracks `x0`).
8. Flush clears everything.
9. Full detection.
10. Wraparound.

The testbench was the main Week 4 deliverable. In Week 5 it was extended to
drive the new `dispatch_is_store` / `store_done` / `commit_tag` ports, and
all of the original scenarios still pass. Both `make rob.pass` and
`make rob.syn.pass` are green.

### 6.5 `test/rs_test.sv`

Unit testbench for the RS. Exercises dispatch, free-slot allocation, CDB
wakeup, oldest-ready issue selection, and the same-cycle CDB forwarding path.

### 6.6 `test/dcache_test.sv`

Unit testbench for the D-cache, written in Week 5. Covers load miss, load
hit, store hit, sub-word stores (byte and halfword), and dirty eviction
(forcing a writeback by hammering one cache index until a dirty line gets
kicked out). `make dcache.pass` and `make dcache.syn.pass` both pass; the
synth report has about 587 ps of slack.

### 6.7 `test/lsq_test.sv`

Unit testbench for the LSQ, also from Week 5. Drives operand wakeup via the
CDB, the store-ready sideband, FIFO ordering, and commit-time release of
the head store. `make lsq.pass` and `make lsq.syn.pass` both pass. The
synth slack on the LSQ is the tight one — about 0.4 ps — so it would be
the first thing to gate a clock-period reduction.

### 6.8 `test/vtuber_test.sv`, `test/vtuber.cpp`, `test/riscv_inst.h`

The ncurses visual debugger inherited from P3. `make <prog>.vis` runs it for a
given program. Useful for staring at the pipeline state at a specific cycle.

### 6.9 `test/pipeline_print.c`

DPI-C helpers for pretty-printing pipeline state from `pipeline_test.sv`.
Mostly commented out by default; uncomment and recompile when you need a
verbose dump.

---

## 7. How to run things

You need the synthesis and simulation toolchain on `PATH` first:

```
module load vcs verdi synopsys-synth
```

`setup-paths.sh` adds the RISC-V GCC toolchain and `elf2hex` to `PATH`. The
Makefile already hardcodes `RISCV32_HOME` and `ELF2HEX_HOME`, so you only need
to source `setup-paths.sh` if you are invoking the cross-compiler by hand.

Common targets:

```
make no_hazard.out          # run the no_hazard.s assembly program on simv
make mult_no_lsq.out        # run mult_no_lsq.s — currently hangs, see status
make <prog>.syn.out         # run <prog> on the synthesized pipeline
make <prog>.verdi           # open <prog> in Verdi
make <prog>.vis             # open <prog> in the ncurses visual debugger

make rob.pass               # run the ROB unit test
make rs.pass                # run the RS unit test
make mult.pass              # run the multiplier unit test
make dcache.pass            # run the D-cache unit test
make lsq.pass               # run the LSQ unit test
make rob.syn.pass           # same, but on the synthesized module
make rob.coverage           # generate the coverage hierarchy report

make synth/pipeline.vg      # synthesize the full processor
make synth/rob.vg           # synthesize a single module
make slack                  # grep slack out of all synth/*.rep files
```

The global clock period is set in the Makefile via `export CLOCK_PERIOD =
1000.0` (picoseconds). It is passed into VCS as a `+define` and read by the
synthesis TCL script. Change it there, not in any individual testbench.

`make clean` clears executables and per-run output. `make nuke` also wipes
synthesis artifacts and `programs/*.mem` — avoid it casually because
re-synthesizing the full pipeline is slow.

---

## 8. Where we are right now

**Working:**

- `make simv` builds with zero errors and zero warnings.
- `make no_hazard.out` runs end-to-end. 14 instructions, 731 cycles, clean
  halt on `HALTED_ON_WFI`, all writebacks correct.
- `make rob.pass`, `make rs.pass`, `make mult.pass`, `make dcache.pass`, and
  `make lsq.pass` all pass in simulation. The ROB, RS, dcache, and LSQ also
  pass on the synthesized netlist (`*.syn.pass`).
- 18 of 33 test programs in `programs/` reach `HALTED_ON_WFI` end-to-end —
  about 55%, up from roughly 30% at the milestone 2 baseline. The new
  passes include `saxpy` (the first program with real loads and stores in
  a loop), `fib_rec`, `sampler`, and five C programs (`basic_malloc`,
  `fc_forward`, `insertionsort`, `omegalul`, `priority_queue`). Per-program
  numbers are in [`milestone3-results.md`](milestone3-results.md).
- The full memory subsystem works: byte/half/word RV32IM loads and stores
  through the LSQ and write-back D-cache, with sub-word stores absorbed as
  byte-enable masks. Writebacks only fire on dirty evictions.
- JAL/JALR write the correct return address to the destination register
  (the milestone 2 silent-zero bug, fixed via the ROB commit-value override).
- The core P6 dataflow — rename, dispatch, issue, execute, MULT, CDB
  broadcast, in-order commit, taken-branch redirect at commit, LSQ-managed
  memory ops — runs cleanly through hundreds of thousands of committed
  instructions on the longer C programs (`insertionsort` at 842k cycles,
  `priority_queue` at 79k cycles).

**Known broken or missing:**

- About a dozen test programs hang with the same signature: PC sits on the
  first instruction of the second iteration of an inner loop, the LSQ has a
  single store at its head with `committed=1` and `in_flight=1`, and
  `dcache_done` never asserts. This includes `mult_no_lsq` (the original
  cycle-2192 hang) and `parallel`, both of which already hung at milestone
  2 — so part of this is inherited rather than caused by the LSQ. The same
  workload with NOPs added between every instruction (`copy_long`) passes,
  so the deadlock is a missed wakeup or arbitration corner case rather than
  a functional bug. Diagnosing it is the top item to chase next.
- The longer C programs (`alexnet`, `mergesort`, `quicksort`, `dft`, …)
  either hit the same hang in their inner loops or time out under the
  90-second test budget.
- Store-to-load forwarding is not implemented. The LSQ runs head-only, so a
  load behind a store pays the full miss latency.
- LSQ flush on branch mispredict is wired but not exercised. It will need
  to drop in-flight non-committed entries and abandon any in-flight cache
  requests once early branch resolution lands.
- There is no branch predictor and no BTB. Branches stall the front-end via
  `branch_pending` and only redirect the PC at commit, so only one branch
  can be in flight at a time. The base spec requires a BTB plus a bimodal
  predictor; this is the next big chunk of work.
- `BRANCH_PRED_SZ` is still the literal `xx` placeholder.
- The pipeline is one wide. Fetch, decode, dispatch, issue, and commit are
  all scalar.
- Full `synth/pipeline.vg` was not exercised this milestone — the per-module
  synth runs are the only timing data we have. Per-module slack is positive
  (`MET`) for everything; the LSQ is the tight one at about 0.4 ps.

---

## 9. What is still ahead

The first job is unsticking the tight-loop hang. It now affects roughly a
dozen programs, all with the same LSQ-head-store-stuck signature, so a fix
should clear most of the failing tests at once. The most likely culprit is a
missed wakeup between the LSQ head moving forward and the next store
asserting `store_ready` to a ROB entry the ROB has just committed in the
same cycle. The dcache/icache bus arbitration is the secondary suspect, and
the icache / `mem.sv` boundary that was the original `mult_no_lsq` lead is
still on the table.

After that, the base spec still needs the branch predictor and BTB, so
branches no longer serialize the front-end through `branch_pending`. Right
now only one branch can be in flight at a time, which puts a hard ceiling on
CPI. Once branches can speculate, the LSQ flush logic that is already wired
in becomes live for the first time.

From there, the proposal calls for two difficult advanced features. The main
one is going 2-way superscalar across fetch, dispatch, issue, and commit.
That is also where `psel_gen.sv` finally earns its keep, and where the spec
lets us add a second CDB (the "CDB count ≤ superscalar width" rule). The
other is early tag broadcast, where producer FUs publish their destination
tag one cycle before the value lands on the CDB so dependents can wake up
earlier. The proposal targets 16-18 advanced-feature points overall, with
at least one "difficult" feature implemented; superscalar plus early tag
broadcast is the primary path to that target.

Beyond the difficult features, the proposal lists several simpler ones we
want to pick up: a more sophisticated branch predictor, store-to-load
forwarding in the LSQ, instruction or data prefetching, and set-associative
caches. Full `synth/pipeline.vg` synthesis with timing closure also still
needs to happen — only per-module synth has been exercised so far.

---

## 10. Where to look next

If you are reading this for the first time and want a single starting point:

- Skim `verilog/pipeline.sv` for the wire declarations and stall logic.
- Then the ROB / RS / LSQ instantiation block in `pipeline.sv` for how the
  three queues talk to each other and the branch buffer.
- Then `verilog/rob.sv` for the next-state priority block (flush > CDB /
  store_done > commit > dispatch). That one block contains most of the
  renaming subtleties, plus the JAL/JALR commit-value override.
- Then `verilog/rs.sv` for wakeup and issue logic on the ALU/MULT/branch
  side.
- Then `verilog/lsq.sv` for the memory-side equivalent: dispatch, CDB
  wakeup, head-only drain, and the commit-time store release.
- Then `verilog/dcache.sv` for the byte-enable mask trick that lets sub-word
  stores skip a round trip to memory.
- Then [`milestone3-report.md`](milestone3-report.md) and
  [`milestone3-results.md`](milestone3-results.md) for the current status,
  the open tight-loop hang, and the per-program test table.
- And [`week3-merge-report.md`](week3-merge-report.md) plus
  [`week4-mult_no_lsq-findings.md`](week4-mult_no_lsq-findings.md) for the
  earlier integration history and the original `mult_no_lsq` investigation.

That should be enough to get oriented and start contributing.
