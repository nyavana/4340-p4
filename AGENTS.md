# Repository Guidelines

## Project Structure & Module Organization

This repository contains a synthesizable RV32IM out-of-order processor in SystemVerilog. Primary RTL lives in `verilog/`; `verilog/pipeline.sv` is the top level and shared constants are in `verilog/sys_defs.svh`. Older Project 3 RTL is archived under `verilog/p3/`. Module testbenches live in `test/` and follow the pairing `verilog/<module>.sv` with `test/<module>_test.sv`. RISC-V assembly and C workloads live in `programs/`. Documentation is under `doc/`, with `doc/project-overview.md` and `doc/makefile-reference.md` as the best starting points. Generated run artifacts go to `output/`, and generated synthesis outputs go under `synth/`.

## Build, Test, and Development Commands

Load lab tools before building:

```sh
module load vcs verdi synopsys-synth
```

Common targets:

```sh
make simv              # build the RTL simulator
make no_hazard.out     # run a small full-processor program
make <module>.pass     # run one RTL module testbench
make <module>.syn.pass # run one synthesized-netlist module testbench
make simulate_all -j   # run all programs on RTL
make slack             # report synthesis timing slack
make clean             # remove executables and per-run output
```

See `doc/makefile-reference.md` for the full target list.

## Coding Style & Naming Conventions

Use SystemVerilog `logic`, `always_comb`, and `always_ff` consistently with the existing RTL. Keep filenames, modules, and signals lower_snake_case, and keep macros or global constants uppercase in `sys_defs.svh`. Match nearby spacing and alignment; use spaces, not tabs. Add new tested modules by updating `TESTED_MODULES` in the `Makefile` and adding any dependency block needed by the generated targets.

## Testing Guidelines

Tests are VCS SystemVerilog testbenches. A testbench passes only when it prints `@@@ Passed`; failures should print `@@@ Incorrect`, because `.pass` targets grep for those strings. For new RTL, add focused tests in `test/<module>_test.sv`, then run `make <module>.pass`. If the module is synthesizable, also run `make <module>.syn.pass`. For pipeline-visible changes, run at least one program with `make <program>.out`; broad changes should run `make simulate_all -j`.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries such as `fix ...`, `draft ...`, and `mark ...`. Keep commits focused and mention the affected module or document. Pull requests should target `release`, summarize behavioral changes, list the Make targets run, and call out any timing, synthesis, or generated-artifact differences. Include linked issues or assignment context when available.

## Security & Configuration Tips

Toolchain paths are hardcoded in the `Makefile` and `setup-paths.sh`; update them only when moving environments. Change `CLOCK_PERIOD` once at the top of the `Makefile`, not inside individual tests.
