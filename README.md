# EECS 4340 Final Project

A synthesizable, P6-style out-of-order RISC-V (RV32IM) processor in
SystemVerilog. The design is 2-way superscalar in fetch, decode,
dispatch, ALU, CDB, and commit, and sits on top of the in-order
VeriSimpleV pipeline from project 3.

The canonical branch is `verify-merged-features` (base design plus the
full advanced-features merge wave). Pull requests target `release`.

## Status

All 34 programs in `programs/` halt at WFI in simulation and on the
post-synthesis netlist. Every architectural-writeback file (`.wb`) is
byte-identical between RTL and synth. Full-pipeline synthesis at
1000 ps misses timing by −244.54 ps on a path inside the MULT stage-0
multiply tree (three endpoints violate); the netlist is functionally
bit-equivalent to the RTL, so the gap is a static-timing concern, not
a glitch path. All module testbenches (`mult`, `rob`, `rs`, `dcache`,
`lsq`, `icache`, `branch_predictor`) pass on both simulation and the
synthesized netlist.

## Features

- **P6 out-of-order, in-order commit.** The RAT lives inside the ROB,
  so ROB entries double as physical registers.
- **2-way superscalar** in fetch, decode, dispatch, ALU, CDB, and
  commit. The LSQ, multiplier, and caches stay 1-wide.
- **Functional units:** two single-cycle ALUs, one pipelined
  multiplier with early tag broadcast, an inline branch resolver, and
  a single-port LSQ feeding the D-cache.
- **D-cache:** 2-way set-associative, write-back, write-allocate,
  256 B. Sub-word stores are absorbed via per-byte valid/dirty masks;
  only line evictions touch main memory.
- **I-cache:** with a next-line stream-buffer prefetcher.
- **Branch prediction:** gshare direction predictor, 32-entry
  direct-mapped BTB, 16-entry RAS. Combinational predict at fetch,
  registered update at commit.
- **Memory disambiguation:** store-to-load forwarding from in-flight
  stores in the LSQ.

Configurable parameters live in [`verilog/sys_defs.svh`](verilog/sys_defs.svh).

## Architecture

The diagram below traces data flow from PC through fetch, rename,
issue, execute, and commit.

```
                              mispredict / RAS push / BTB hit
                  ┌─────────────────────────────────────────────┐
                  │                                             │
                  ▼                                             │
            ┌──────────┐    ┌─────────┐    ┌────────────────────┴────┐
   PC ────▶│  IF       │───▶│   ID    │───▶│  Rename / Dispatch (×2) │
            │ icache +  │    │ decoder │    │  RAT inside ROB         │
            │ stream-   │    └─────────┘    └────────┬────────────────┘
            │ buffer    │                            │
            │ +BP/BTB/  │                  ┌─────────┴──────────┐
            │  RAS      │                  ▼                    ▼
            └──────────┘             ┌────────┐           ┌─────────┐
                                     │   RS   │           │   LSQ   │
                                     └───┬────┘           └────┬────┘
                          ┌──────────┬───┴────┬─────────┐      │
                          ▼          ▼        ▼         ▼      ▼
                       ALU0       ALU1      MULT      BR    dcache
                                          (8 stg)              │
                                          early tag ───┐       │
                          │          │        │        │       │
                          └──────────┴────┬───┴────────┴───────┘
                                          ▼
                                ┌───────────────────┐
                                │   CDB (2 slots)   │   priority:
                                │ MULT > LD > ALU/BR│   per slot
                                └─────────┬─────────┘
                                          ▼
                              ┌─────────────────────────┐
                              │  ROB commit (in order)  │
                              │  regfile + mispredict   │
                              └─────────────────────────┘
```

## Repository layout

```
verilog/         RTL sources (pipeline.sv is the top level)
test/            Module testbenches (verilog/<m>.sv ↔ test/<m>_test.sv)
programs/        RV32IM benchmarks (.s and .c)
synth/           Synthesis outputs and per-module .vg netlists
output/          Per-run *.out / *.wb / *.ppln files (gitignored)
doc/             Project documentation (see Documentation below)
Makefile         All build, test, synth, and program-execution targets
sys_defs.svh     Centralized parameters (in verilog/)
```

## Prerequisites

- Synopsys VCS, Verdi, and Design Compiler.
- RISC-V GNU toolchain. Paths are hardcoded in the `Makefile`; cloning
  to a different machine requires editing `RISCV32_HOME`.
- elf2hex.

On the lab cluster the Synopsys tools are made available with:

```sh
module load vcs verdi synopsys-synth
```

## Quick start

```sh
make simv                                 # build the RTL simulator
make no_hazard.out                        # run the smallest program
make rob.pass                             # run a module testbench

make simulate_all -j                      # all 34 programs on simv
make slack                                # check synthesis timing
```

`CLOCK_PERIOD = 1000.0` ps is exported by the Makefile to both VCS and
the synthesis TCL. Change it once at the top of the Makefile, never
per testbench.

The full target reference (program execution, synth, Verdi, coverage,
visual debugger, cleanup) is in
[`doc/makefile-reference.md`](doc/makefile-reference.md).

## Module testbenches

The Makefile generates per-module test targets for every name in
`TESTED_MODULES` (`mult`, `rob`, `rs`, `dcache`, `lsq`, `icache`,
`branch_predictor`). A testbench passes only if it `$display`s the
literal string `@@@ Passed`; failures print `@@@ Incorrect`. The
`.pass` rule is just `grep`.

```sh
make <m>.pass        # RTL run
make <m>.syn.pass    # synthesized-netlist run
make <m>.coverage    # coverage hierarchy report
```

For the full target list, the `mult.pass` / `mult.out` namespace
collision, and instructions for adding a new tested module, see
[`doc/makefile-reference.md`](doc/makefile-reference.md).

## Configuration

| Knob | Effect |
|------|--------|
| `+define+SERIALIZE_BRANCHES` | Falls back to a serialized front-end. Used as the regression baseline; every `.wb` is byte-identical between this and the post-merge default. |
| `+define+DISABLE_EARLY_TAG`  | Forces `early_cdb_valid = 0`. Makes the multiplier behave as if early tag broadcast were not wired up. |
| `CLOCK_PERIOD` (Makefile)    | Picosecond clock period exported to VCS and synthesis. Defaults to `1000.0`. |

## Performance

The advanced-features merge wave reduces cycle count by roughly 30–50%
over the base design across most programs. Per-program numbers and
the branch-accuracy / CPI diff between the bimodal baseline and the
post-merge configuration are in
[`doc/advanced-features/advanced-features-merge-report.md`](doc/advanced-features/advanced-features-merge-report.md)
and
[`doc/advanced-features/branch-accuracy-cpi-diff.md`](doc/advanced-features/branch-accuracy-cpi-diff.md).

"Halts at WFI" is the correctness criterion; this repo does not run a
golden-output check on program semantics. For programs that already
passed at milestone 3, identical cycle counts are strong evidence of
zero regression. For the rest, only the WFI is verified.

## Documentation

Start with [`doc/project-overview.md`](doc/project-overview.md), then
the RTL: `verilog/pipeline.sv`, then `rob.sv`, `rs.sv`, `lsq.sv`.

| Path | Contents |
|------|----------|
| [`doc/project-overview.md`](doc/project-overview.md) | Architectural orientation; read first. |
| [`doc/base-design/`](doc/base-design/) | Base-design verification, original BTB and bimodal predictor, RS issue-loop fix. |
| [`doc/advanced-features/`](doc/advanced-features/) | Merge umbrella plus per-feature reports: superscalar, ETB, gshare and RAS, advanced D-cache, STLF. |
| [`doc/weekly-reports/`](doc/weekly-reports/) | Milestone and week-by-week notes. |
| [`doc/makefile-reference.md`](doc/makefile-reference.md) | Full Makefile target reference. |
| [`doc/legacy/original-readme.md`](doc/legacy/original-readme.md) | Pre-rewrite README, archived 2026-05-01. |

## Known limitations

- Full-pipeline synthesis misses timing at 1000 ps. Worst slack is
  −244.54 ps inside the MULT stage-0 multiply tree (three endpoints
  violate). Closing the gap would cost an extra cycle on every load
  (registering `load_complete_value` at the LSQ output) or every
  multiply (splitting MULT stage 0); both were considered and
  deferred. The netlist is bit-equivalent to RTL.
- No golden-output verification. "Halts at WFI" is the only
  end-to-end correctness check.
