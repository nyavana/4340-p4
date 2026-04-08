# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

This is the **EECS 4340 Final Project (Spring 2026)**: an out-of-order, synthesizable RISC-V processor built on top of the VeriSimpleV pipeline from Project 3. The design is **P6-style** (in-order commit via ROB, register renaming via RAT, CDB broadcast). See `doc/project-proposal.md` and `doc/project-description.md` for the full spec.

**Hard constraints from the spec:**
- I-cache and D-cache are each capped at 256 bytes (512 B total).
- `MEM_LATENCY_IN_CYCLES` is fixed at `ceil(100ns / CLOCK_PERIOD)` — don't "fix" slow programs by lowering it.
- Number of CDBs may not exceed the superscalar width of the narrowest pipeline stage.
- Multiplier must be the one from P2 (`verilog/mult.sv`, `verilog/mult_stage.sv`) — degree of pipelining (`MULT_STAGES`) is tunable.

**Planned advanced features** (from proposal): 2-way superscalar + early tag broadcast (difficult), plus sophisticated branch predictors, prefetching, and associative caches.

## Environment Setup

Synthesis/simulation tools must be loaded before running `make`:
```
module load vcs verdi synopsys-synth
```
`setup-paths.sh` adds the RISC-V GCC toolchain and `elf2hex` to `PATH`. The Makefile hardcodes these via `RISCV32_HOME` and `ELF2HEX_HOME`, so sourcing is only needed when invoking the tools directly.

The global clock period is set in the Makefile via `export CLOCK_PERIOD = 1000.0` (picoseconds). Change it there, not in testbenches — it's passed into VCS as a define and also referenced by the synthesis TCL script.

## Common Commands

### Running programs on the full processor
```
make <program>.out          # simulate programs/<program>.{s,c} on simv
make <program>.syn.out      # run on syn_simv (synthesized pipeline)
make <program>.verdi        # open in Verdi
make <program>.vis          # P3 ncurses visual debugger (vtuber)
```
Outputs land in `output/<program>.{out,wb,ppln}`. Correctness is verified by comparing the `.wb` file — the spec's milestone 2 target is `mult_no_lsq.wb`.

### Per-module testbenches
The Makefile has a generic target system for unit tests. For a module `foo`:
1. Create `verilog/foo.sv` (implements `module foo`) and `test/foo_test.sv` (testbench).
2. Add `foo` to `TESTED_MODULES` in the Makefile.
3. If the module has dependencies, add `FOO_DEPS = verilog/other.sv` and `$(call DEPS,foo): $(FOO_DEPS)`.

Then:
```
make foo.simv / foo.out / foo.pass   # simulate and grep for "@@@ Passed"/"@@@ Incorrect"
make foo.syn.pass                    # same, but on synthesized module (synth/foo.vg)
make foo.coverage                    # line+fsm+cond+tgl+branch coverage hierarchy
make foo.verdi / foo.syn.verdi       # debug in Verdi
```

A testbench is considered passing only if it `$display`s `@@@ Passed` or `@@@ Incorrect` — the `.pass` targets just grep for those strings.

### Synthesis
```
make synth/pipeline.vg      # synthesize the full pipeline
make synth/foo.vg           # synthesize a single module
make slack                  # grep slack from all synth/*.rep files
```
Synthesis is driven by `synth/eecs4340_synth.tcl`. It reads the `MODULE` and `SOURCES` env vars passed by the Makefile.

### Cleanup
`make clean` removes executables and per-run output. `make nuke` also wipes synthesis artifacts and `programs/*.mem` — avoid it casually, re-synthesizing the full pipeline is slow.

## Architecture

### Top-level dataflow (verilog/pipeline.sv)
The pipeline is currently a 1-wide P6 design. In order of dataflow:

1. **Fetch**: `PC_reg` → `icache` → `fetched_inst` (chooses high/low 32 bits of the 64-bit line based on `PC_reg[2]`). Stalls via the global `stall` signal on any of: `!Icache_valid_out`, `rs_full`, `rob_full`, `branch_pending`.
2. **Decode**: `decoder` produces `opa_select`/`opb_select`/`alu_func`/flags. `dispatch_op` is packed as `{uncond_branch, cond_branch, alu_func[4:0]}` (7 bits + 1 unused) and is the opcode the RS forwards to the FU.
3. **Rename / dispatch**: For each source register, `pipeline.sv` checks the ROB's RAT via `query{1,2}_*`. If `!rat_qN_pending`, read regfile; else if `rat_qN_ready`, use the ROB value; else mark not-ready and forward the tag. Constant operands (PC/NPC/imm) bypass RAT.
4. **ROB dispatch**: Allocates a tail entry; `dispatch_tag = tail` becomes the renamed destination tag. RAT is updated in the same cycle (never for `x0`).
5. **RS dispatch**: Accepts `(op, dest_tag, src1/src2 ready/tag/value)`. Must snoop CDB to wake up operands while waiting.
6. **Issue**: RS drives `issue_valid`; `pipeline.sv` determines `issue_is_mult` / `issue_is_branch` from `rs_issue_op` bits and gates with `issue_accept = rs_issue_valid && (is_mult ? !mult_busy : !mult_done)`.
7. **Execute**: single-cycle ALU is inline in `pipeline.sv`; multiplier is the pipelined `mult` module. Conditional branch resolution is also inline and uses a latched `branch_funct3_buf` / `branch_target_buf` filled at dispatch time (see "Branch handling" below).
8. **CDB**: one bus, MULT has priority (if `mult_done`, ALU is blocked via `issue_accept`). Carries `{tag, value, take_branch, branch_target}`.
9. **Commit**: ROB head retires when `busy && ready`; writes regfile, updates `PC_reg` on taken branches, and latches `HALTED_ON_WFI` / `ILLEGAL_INST` into `error_status_reg`.

### ROB with embedded RAT (verilog/rob.sv)
The ROB carries the **Register Alias Table inline** (`rat_busy[32]`, `rat_tag[32]`). There is no standalone map-table module. Key behaviors:
- `query{1,2}_*` ports answer dispatch-time rename queries and include **same-cycle CDB bypass** (if the CDB is completing the tag the RAT points at, the query returns `ready=1` with `cdb_value`).
- On commit, the RAT entry is cleared only if it still points at the committing ROB slot (prevents stale clears when a younger instruction has re-renamed the same arch reg).
- `flush` clears all entries, RAT, head/tail/count — use for branch mispredicts once early resolution is wired up.
- Ordering inside the combinational next-state block is: **flush > CDB complete > commit > dispatch**. Don't reorder without understanding the implication for same-cycle dispatch-commit.

### Branch handling (current, simplistic)
There is no BTB/predictor yet. Branches stall the front-end: at dispatch, `branch_pending` is set and `branch_target_buf`/`branch_funct3_buf` are latched. The branch sits in the RS until issue, resolves in the inline branch logic, broadcasts on CDB, and `PC_reg` is only redirected at **commit** time. This means **only one branch can be in-flight at a time**. Implementing the BTB + bimodal predictor (base requirement) and early resolution (potential advanced feature) will require replacing this scheme.

### Instruction cache (verilog/icache.sv)
32 lines × 64 bits = 256 bytes, direct-mapped, **blocking**. Coordinates memory tags (a 4-bit transaction ID returned by `mem.sv`, distinct from cache tags). The data cache does not yet exist — `pipeline.sv` wires `proc2mem_*` directly to the icache ports and ties `proc2mem_data` to zero. Implementing the D-cache will require arbitrating the shared memory bus.

### Parameters (verilog/sys_defs.svh)
`ROB_SZ`, `RS_SZ`, `BRANCH_PRED_SZ`, `LSQ_SZ`, `NUM_FU_LOAD`, `NUM_FU_STORE` are **currently `xx`** (placeholder). They **must** be set to concrete integers before anything will elaborate. `PHYS_REG_SZ` is `(32 + ROB_SZ)` — this only makes sense for a P6 design where ROB entries act as physical registers; an R10K rename would need a different definition. `MULT_STAGES` defaults to 4 but should be re-tuned against synthesis slack.

## Known Broken State (at time of writing)

These will bite you immediately — fix or work around before building:

1. **`Makefile:180-184` has an unresolved git merge conflict** (`<<<<<<< Updated stream` markers). `TESTED_MODULES` needs to be resolved to `mult rob rs` (or whatever subset is actually being tested).
2. **`verilog/rs.sv` does not exist** but `pipeline.sv` instantiates `rs rs_0 (...)`. The full processor (`make simv`) will not compile until this module is written with the port signature that `pipeline.sv` expects (see lines 330-359 of `pipeline.sv`).
3. **`test/rob_test.sv` and `test/rs_test.sv` do not exist** — `make rob.pass` / `make rs.pass` will fail until they're written.
4. **`sys_defs.svh` has `xx` placeholders** for `ROB_SZ`, `RS_SZ`, etc. — elaboration will error until these are set to integers.

## Conventions and References

- **Module files live in `verilog/`, testbenches in `test/`** with names `<mod>.sv` / `<mod>_test.sv`. The build system relies on this convention.
- **Use `psel_gen.sv`** (parameterized priority selector) instead of hand-rolled priority for-loops — comment in `verilog/psel_gen.sv` calls it out as faster than alternatives.
- **`verilog/p3/`** contains the Project 3 in-order pipeline source (decoder, stages, etc.). It's no longer compiled but is a useful reference, especially the decoder and stage logic.
- **Testbenches must print `@@@ Passed` or `@@@ Incorrect`** — the `.pass` Makefile targets rely on grep matching these exact strings.
- Unit-test synthesis with `make <mod>.syn.pass` alongside `make <mod>.pass`. Per the rubric: "If you don't get synthesis working it will be very difficult to earn points."
