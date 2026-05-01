# Makefile reference

This is the full target reference for the project Makefile. The top-level
`README.md` only lists the handful of targets you reach for day to day; this
doc is the long form. Everything here is wired up in the `Makefile` at the
repo root — read it directly if a target is missing.

Before any target will compile, the Synopsys tools must be on `PATH`:

```sh
module load vcs verdi synopsys-synth
```

`RISCV32_HOME` and `ELF2HEX_HOME` are hardcoded in the Makefile.
`CLOCK_PERIOD` is exported as `1000.0` ps and propagated to both VCS (via
`+define`) and the synthesis TCL — change it once at the top of the
Makefile, never per-testbench.

## Module testbenches

Convention: a tested module `<m>` has implementation `verilog/<m>.sv` and
testbench `test/<m>_test.sv`, and the module name is listed in the
`TESTED_MODULES` variable in the Makefile. Current value:

```
TESTED_MODULES = mult rob rs dcache lsq icache branch_predictor
```

Each tested module gets the following targets generated:

```make
make <m>.pass         # grep "@@@ Passed" / "@@@ Incorrect" out of the RTL run
make <m>.out          # run the testbench and dump output
make <m>.simv         # compile the RTL testbench executable
make <m>.verdi        # open the testbench in Verdi (via <m>.simv)

make <m>.syn.pass     # same pass/fail check against the synthesized netlist
make <m>.syn.out      # run the synthesized testbench and dump output
make <m>.syn.simv     # compile the synth testbench executable
make synth/<m>.vg     # synthesize a single module
make <m>.syn.verdi    # open the synth run in Verdi (via <m>.syn.simv)

make <m>.coverage     # print the coverage hierarchy report to stdout
make <m>.cov          # compile a coverage executable for the module + testbench
make <m>.cov.vdb      # run that executable, producing <m>.cov.vdb
make <m>_cov_report   # urg-generated human-readable coverage reports
make <m>.cov.verdi    # open the coverage report in Verdi
```

A testbench passes only if it `$display`s the literal string `@@@ Passed`.
Failures should print `@@@ Incorrect`. The `.pass` rule is just `grep`.

`mult` collision: the project also ships a `mult.mem` program, so
`make mult.pass` runs the *testbench* (output written to
`output/mult_tb.out`) and `make mult.out` runs the *program*. This split is
wired in explicitly — don't try to unify them.

## Whole-processor program execution

To run a program on the full processor, use `make <prog>.out`. This
assembles a RISC-V `*.mem` file (loaded by `mem.sv`), compiles the
processor, and runs the program. Output goes into `output/`:

- `output/<prog>.out` — memory state at end + CPI summary
- `output/<prog>.wb` — list of architectural register writes (the
  byte-identical regression artifact between RTL and synth, and between
  the post-merge default and `+define+SERIALIZE_BRANCHES`)
- `output/<prog>.ppln` — per-cycle pipeline state

```make
# ---- Program execution ---- #
make <prog>.out         # run on simv (RTL)
make <prog>.syn.out     # run on syn_simv (post-synthesis netlist)

make simulate_all       # run every program on simv (use -j)
make simulate_all_syn   # run every program on syn_simv (use -j)

# ---- Executables ---- #
make simv               # RTL processor simulator
make syn_simv           # synthesized-netlist simulator
make synth/pipeline.vg  # synthesize the full processor (slow)
make slack              # grep "slack" out of all synth/*.rep files
make *.vg               # synthesize a module out of SOURCES for use in syn_simv

# ---- Program memory compilation ---- #
make programs/<prog>.mem  # assemble a program to a RISC-V memory image
make compile_all          # assemble every program in programs/ (use -j)

# ---- Disassembly ---- #
make <prog>.dump          # disassemble compiled memory into RISC-V assembly
make *.debug.dump         # for *.c programs, with debug flags
make dump_all             # all dump files at once (use -j)

# ---- Verdi ---- #
make <prog>.verdi         # run a program in Verdi via simv
make <prog>.syn.verdi     # run a program in Verdi via syn_simv

# ---- Visual debugger (P3 vtuber) ---- #
make <prog>.vis           # run a program in the ncurses visual debugger
make vis_simv             # compile the vtuber executable
```

## Cleanup

```make
make clean   # remove executables and per-run output (keeps .mem and synth)
make nuke    # also remove synth/, output/, and programs/*.mem (slow recovery)
```

## Adding a new tested module

1. Create `verilog/<m>.sv` and `test/<m>_test.sv` (the testbench should
   `$display` `@@@ Passed` on success and `@@@ Incorrect` on failure).
2. Add `<m>` to the `TESTED_MODULES` variable in the Makefile.
3. If the module needs other SystemVerilog files compiled in, add an
   `<M>_DEPS = ...` block alongside the existing per-module deps in the
   Makefile (search for `ROB_DEPS` for an example).
4. Verify with `make <m>.pass` and `make <m>.syn.pass`. For synthesis you
   may also need a `synth/<m>_svsim.sv` wrapper if the module has
   unpacked-array ports — see `synth/rob_svsim.sv` for the pattern
   (uses `{>>{ }}` to repack into the netlist's packed buses).
