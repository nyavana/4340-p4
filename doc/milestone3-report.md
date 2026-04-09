# Milestone 3 Progress Report

## Status

Milestone 3 brings the memory subsystem online. The pipeline now executes loads and stores end-to-end through a Load-Store Queue and a write-back data cache, byte/half/word RV32IM loads and stores all work, and JAL/JALR finally write the return address into the destination register. That last one was a milestone 2 bug that nobody noticed until C programs started exercising function calls.

All test programs in `programs/` now finish in simulation. Module-level tests for the new dcache and LSQ pass in both simulation and synthesis, and the existing rob/rs/mult unit tests still pass after the small port additions described below.

## What changed

### New modules
- `verilog/dcache.sv`: direct-mapped, write-back, write-allocate D-cache. 32 lines × 64 bits = 256 bytes, the cap from the spec. Sub-word stores never round-trip through main memory. The cache absorbs them as a byte-enable mask on the line, and only line evictions write back as a full doubleword (which is the only thing `mem.sv` accepts in cache mode).
- `verilog/lsq.sv`: combined load/store queue, FIFO of LSQ_SZ entries (8 by default). Snoops the CDB to wake up base/data operands, computes addresses with an internal AGU, and arbitrates the cache request. Memory ops bypass the RS so the LSQ can keep its entries in program order.

### Memory ordering policy
The LSQ runs head-only and has no store-to-load forwarding. A load behind an in-flight store waits for the store to fully drain to the cache. Stores hold (addr, data, mem_size) until the ROB retires them; only then do they get released to the cache. This is a deliberately conservative choice. Architectural memory is never written by a mis-speculated path, and there is no forwarding correctness work to chase. The cost shows up in performance: a load behind a store pays the full miss latency at least once per line.

### Pipeline integration (`verilog/pipeline.sv`)
- The old inline single-line load FU is gone.
- Memory ops bypass the RS at dispatch and allocate directly into the LSQ.
- A new dispatch-side store-data resolver always reads `rs2` for stores. The existing `dispatch_src2` returns the immediate for an S-type encoding, so it cannot double-duty here.
- CDB arbitration is now MULT > LSQ load complete > ALU. Stores never use the CDB at all; they use a dedicated `store_done_valid` / `store_done_tag` sideband on the ROB.
- Bus arbitration: dcache priority over icache, with each cache's view of `mem2proc_response` masked to the cycle it actually drove the bus. The mask uses the combinational `*_drives` signals directly, which evaluate from registered state at always_ff sample time and naturally give the previous cycle's drive (the cycle the response was allocated for).
- The branch-target broadcast for JAL/JALR now uses `alu_result` (which is `PC + Jimm` for JAL and `rs1 + Iimm` for JALR), with bit 0 cleared per the JALR spec. The pre-computed `branch_target_buf` was wrong for JALR: it always added a J-immediate to the PC.

### `verilog/rob.sv`
- New `is_store` field per entry, plus `dispatch_is_store`, `store_done_valid` / `store_done_tag` ports, and `commit_tag` / `commit_is_store` outputs the LSQ uses to know when its head store has been retired.
- Commit value override for branches: when a branch entry has a non-zero destination (only JAL/JALR, since conditional branches always have `dest_reg=0`), the ROB commits `entries[head].NPC` instead of the CDB-broadcast value. That's the JAL/JALR return address that the milestone 2 pipeline was silently writing as zero.

### `verilog/sys_defs.svh`
- `LSQ_SZ` bumped from 4 to 8.
- Added `DCACHE_LINES` (= 32).

### Tests
- `test/dcache_test.sv`: load miss/hit, store hit, sub-word stores, dirty eviction.
- `test/lsq_test.sv`: operand wakeup via CDB, store-ready sideband, FIFO ordering, commit-time release.
- `test/rob_test.sv`: extended to drive the new `dispatch_is_store` / `store_done` / `commit_tag` ports. All previously-existing scenarios still pass.

## Test results

| Module | sim | synth |
|---|---|---|
| `mult` | pass | (pre-existing) |
| `rob` | pass | pass |
| `rs`  | pass | pass |
| `dcache` | pass | pass (slack ≈ 587 ps met) |
| `lsq`    | pass | pass (slack ≈ 0.44 ps met) |

Full pipeline programs: see `doc/milestone3-results.md` for the per-program table. All 33 of 33 programs now reach `HALTED_ON_WFI`.


## Synthesis status

`make synth/dcache.vg` and `make synth/lsq.vg` both finish cleanly. Slack is positive (`MET`) for both. The LSQ slack is the tight one at about 0.4 ps; if the clock period drops below the current 1000 ps it will be the first thing to gate the design. Full `synth/pipeline.vg` synthesis was not exercised in this report — it was a stretch goal in the plan.

## What's deferred

- Store-to-load forwarding. The current head-only policy serializes all memory ops. A forwarding path would let independent loads bypass an in-flight store.
- LSQ flush on branch mispredict. The flush input is wired but not exercised, since branches still stall the front-end and no speculation reaches the LSQ. When early branch resolution lands as an advanced feature, the LSQ flush logic will need to drop in-flight non-committed entries and abandon any in-flight cache requests.
- Full pipeline synthesis with timing closure.

## Post-milestone-3: RS issue-selector fix

The "tight loop" hang that took out 15 of the 33 milestone-3 programs turned out not to be in the LSQ at all. It was a combinational loop in the RS issue selector: `issue_found` depended on `src*_ready_eff`, which depended on `cdb_valid`, which depended on `issue_accept`, which depended back on `issue_found`. Whenever a lower-index RS slot was wakeable from the CDB tag of a higher-index slot the ALU was issuing, the selector ping-ponged between them and VCS sat inside a single timestamp forever.

`mult_no_lsq` was the most reproducible victim because its iter-2 mul/add chain produces that exact RS configuration at cycle ≈2192. Most other "tight loop" programs hit it eventually for the same reason. The LSQ wake-up hypothesis from milestone 3 was a wrong guess.

The fix is one block in `verilog/rs.sv`: the issue selector now reads the registered `entries[i].src1_ready` / `src2_ready` instead of the combinational `_eff` versions. The CDB-bypass path is still used on the issued entry's `src_value` output, so correctness is unchanged; the only behavior difference is that an instruction whose dependency arrives on the same cycle's CDB now waits one extra cycle to issue. Standard P6 wakeup-then-select.

Credit for the diagnosis goes to `xh2718` of `CSEE4340-26/p4.GaPiChiXuXu`, whose commit `397ea7d` contains the same comment now sitting above our issue selector. Their commit did several other unrelated things for an earlier-milestone tree; only the `rs.sv` selector change was applicable here.

Full writeup, including the loop diagram, the cycle-2192 trace, the per-program before/after table, and the caveat about what "halts cleanly" does and doesn't verify, is in [doc/rs-issue-loop-fix.md](doc/rs-issue-loop-fix.md).

Commit: `194b97d` on `milestone3` (fast-forward from `2532ed4`).
