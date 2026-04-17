
# EECS 4340 Final Project

Welcome to the  EECS 4340 Final Project!

This is the repository for your implementation of an out-of-order,
synthesizable, RISC-V processor with advanced features.

This README has information on changes from project 3 and specific
requirements on your processor for submitting to the autograder.


## Project Overview

This is an out-of-order RISC-V processor built on top of the VeriSimpleV
pipeline from Project 3. It's a P6-style design: instructions execute
out-of-order but commit in order through a ReOrder Buffer. The Register
Alias Table sits inside the ROB rather than as a separate module, and a
single Common Data Bus broadcasts results back to anything still waiting.

### Base design

- Architecture: P6 out-of-order with in-order commit, so branch mispredicts
  and exceptions stay precise.
- Functional units: 2 simple ALUs (1 cycle), 1 pipelined multiplier (the
  one from Project 2), 1 branch target unit, 1 memory address unit.
- Caches: separate I-cache and D-cache, 256 bytes each. 512 bytes total is
  a hard cap from the spec.
- Branch prediction: a BTB plus a bimodal direction predictor.

### Planned advanced features

The proposal aims for two of the harder features and a handful of simpler
ones:

- 2-way superscalar (hard): widen fetch, issue, execute, and retire to two
  instructions per cycle while still committing in order.
- Early tag broadcast (hard): push destination tags into the wakeup logic
  the moment execution knows the result is ready, instead of waiting on
  the CDB.
- A smarter branch predictor than plain bimodal.
- I-cache and/or D-cache prefetching. Memory latency is 100 ns, so
  anything that hides it helps.
- Set-associative caches instead of direct-mapped.


## Getting Started

Start the project by working on your first module, either the ReOrder
Buffer (ROB) or the Reservation Station (RS). Implement the modules in
files in the `verilog/` folder, and write testbenches for them in the
`test/` folder. If you're writing the ROB, name these like:
`verilog/rob.sv` and `test/rob_test.sv` which implement and test the
module named `rob`.

Once you have something written, try running the new Makefile targets.
Add `rob` to the TESTED_MODULES variable in the Maekefile, then run
`make rob.pass` to compile, run, and check the testbench. Do the same
for synthesis with `make rob.syn.pass`. And finally, check your
testbench's coverage with `make rob.coverage.`

After you have the first module written and tested, keep going and work
towards a full processor. Plan to pass the `mult_no_lsq` program for the
second milestone (verify with the .wb file).

## Changes from Project 3

Many of the files from project 3 are still present or kept the same,
but there are a number of notable changes:

### The Makefile

The final project requires writing many modules, so we've added a new
section to the Makefile to compile arbitrary modules and testbenches.

To make it work for a module `mod`, create the files `verilog/mod.sv`
and `test/mod_test.sv` which implement and test the module. If you
update the `TESTED_MODULES` variable in the Makefile, then it will
be able to link the new targets below.

The most straightforward targets are `make mod.pass`,
`make mod.syn.pass` and `make mod.coverage`, which check if the module
passes the testbench in simulation, if it passes the testbench in
synthesis, and print the output of coverage for the module.

``` make
# ---- Module Testbenches ---- #
# NOTE: these require files like: 'verilog/rob.sv' and 'test/rob_test.sv'
#       which implement and test the module: 'rob'
make <module>.pass   <- greps for "@@@ Passed" or "@@@ Incorrect" in the output
make <module>.out    <- run the testbench (via <module>.simv)
make <module>.simv   <- compile the testbench executable
make <module>.verdi  <- run in verdi (via <module>.simv)
make <module>.syn.pass   <- greps for "@@@ Passed" or "@@@ Incorrect" in the output
make <module>.syn.out    <- run the synthesized module on the testbench
make <module>.syn.simv   <- compile the synthesized module with the testbench
make synth/<module>.vg   <- synthesize the module
make <module>.syn.verdi  <- run in verdi (via <module>.syn.simv)

# ---- module testbench coverage ---- #
make <module>.coverage    <- print the coverage hierarchy report to the terminal
make <module>.cov.verdi   <- open the coverage report in verdi
make <module>.cov         <- compiles a coverage executable for the module and testbench
make <module>.cov.vdb     <- runs the executable and creates the <module>.cov.vdb directory
make <module>_cov_report  <- run urg to create human readable coverage reports
```

### `verilog/sys_defs.svh`

`sys_defs` has received a few changes to prepare the final project:

1.  We've defined `CACHE_MODE`, affecting `test/mem.sv` and changing
    the way the processor interacts with memory.

2.  We've added a memory latency of 100ns, so memory is now much
    slower, and handling it with caching is necessary.

3.  There is a new 'Parameters' section giving you a starting point
    for some common macros that will likely need to be decided on like
    the size of the ROB, the number of functional units, etc.

### Pipeline Files

The two files `verilog/pipeline.sv` and `test/pipeline_test.sv` have
been edited to comment-out or remove project 3 specific code, so you
should be able to re-use them when you want to start integrating your
modules into a full processor again.

## New Files

We've added an `icache` module in `verilog/icache.sv`. That file has
more comments explaining how it works, but the idea is it stores
memory's response tag until memory returns that tag with the data. More
about how our processor's memory works will be presented in the final
lab section.

The file `psel_gen.sv` implements an incredibly efficient parameterized
priority selector (remember project 1?!). many tasks in superscalar
processors come down to priority selection, so instead of writing
manual for-loops, try to use this module. It is faster than any
priority selector the instructors are aware of (as far as my last
conversation about it with Brehob).

As promised, we've also copied the multiplier from project 2 and moved
the `` `STAGES`` definition to `sys_defs.svh` as `` `MULT_STAGES``.
This is set to 4 to start, but you can change it to 2 or 8 depending on
your processor's clock period.

### `verilog/p3` and the `decoder.sv`

The project 3 files are no longer relevant to your final processor, but
they are still good references, so project 3's starter verilog source
files have been moved to `verilog/p3/`. Notably, the decoder has been
pulled out as a new file `verilog/decoder.sv`.

## P3 Makefile Target Reference

This is the Makefile target reference from project 3, I've left it here
for reference. Most of the P3 portion of the Makefile is unchanged.

To run a program on the processor, run `make <my_program>.out`. This
will assemble a RISC-V `*.mem` file which will be loaded into `mem.sv`
by the testbench, and will also compile the processor and run the
program.

All of the "`<my_program>.abc`" targets are linked to do both the
executable compilation step and the `.mem` compilation steps if
necessary, so you can run each without needing to run anything else
first.

`make <my_program>.out` should be your main command for running
programs: it creates the `<my_program>.out`, `<my_program>.wb`, and
`<my_program>.ppln` output, writeback, and pipeline output files in the
`output/` directory. The output file includes the status of memory and
the CPI, the writeback file is the list of writes to registers done by
the program, and the pipeline file is the state of each of the pipeline
stages as the program is run.

The following Makefile rules are available to run programs on the
processor:

``` make
# ---- Program Execution ---- #
# These are your main commands for running programs and generating output
make <my_program>.out      <- run a program on simv
                              generate *.out, *.wb, and *.ppln files in 'output/'
make <my_program>.syn.out  <- run a program on syn_simv and do the same

# ---- Executable Compilation ---- #
make simv      <- compiles simv from the TESTBENCH and SOURCES
make syn_simv  <- compiles syn_simv from TESTBENCH and SYNTH_FILES
make *.vg      <- synthesize modules in SOURCES for use in syn_simv
make slack     <- grep the slack status of any synthesized modules

# ---- Program Memory Compilation ---- #
# Programs to run are in the programs/ directory
make programs/<my_program>.mem  <- compile a program to a RISC-V memory file
make compile_all                <- compile every program at once (in parallel with -j)

# ---- Dump Files ---- #
make <my_program>.dump  <- disassembles compiled memory into RISC-V assembly dump files
make *.debug.dump       <- for a .c program, creates dump files with a debug flag
make dump_all           <- create all dump files at once (in parallel with -j)

# ---- Verdi ---- #
make <my_program>.verdi     <- run a program in verdi via simv
make <my_program>.syn.verdi <- run a program in verdi via syn_simv

# ---- Visual Debugger ---- #
make <my_program>.vis  <- run a program on the project 3 vtuber visual debugger!
make vis_simv          <- compile the vtuber executable from VTUBER and SOURCES

# ---- Cleanup ---- #
make clean            <- remove per-run files and compiled executable files
make nuke             <- remove all files created from make rules
```

## Progress: Week 3 and Week 4

### Week 3

There were three branches, and none of them built end-to-end on their own.
`milestone1` had `rs.sv` but no ROB. `milestone2` had `rob.sv` and a
refactored `pipeline.sv` but no `rs.sv`. `release` was the baseline plus
notes.

Week 3 was the merge that fixed this. `milestone2` got brought onto a new
`week3` branch rooted at `milestone1`, with conflicts in `Makefile` and
`verilog/sys_defs.svh` resolved by hand. After the merge, `make simv`
compiled cleanly for the first time and `make no_hazard.out` ran to
completion. `make mult_no_lsq.out` was flaky and got punted to Week 4.

### Week 4

`test/rob_test.sv` was added: a unit testbench for the ROB covering
dispatch, CDB complete, in-order commit despite out-of-order completion,
same-cycle RAT bypass, stale-clear protection, the `x0` guard, flush, full,
and wraparound. Both `make rob.pass` and `make rob.syn.pass` are green.

The other Week 4 thread was the `mult_no_lsq` hang. On this worktree it
isn't actually nondeterministic; it's deterministic. Simulator time stops
advancing around cycle 2192, after 44 correct writebacks that cover the
full setup phase and the first loop iteration. The RS, ROB, multiplier,
and core pipeline dataflow all check out, they do the right thing right
up until time freezes. The week 4 doc guessed the loop was at the
`icache` / `test/mem.sv` boundary; it nailed the *kind* of bug
(delta-cycle storm) but missed the location. The actual loop was in the
RS issue selector and got fixed post-milestone-3. See
[doc/rs-issue-loop-fix.md](doc/rs-issue-loop-fix.md) and the
[Post-milestone-3 update](#post-milestone-3-rs-issue-selector-fix)
section below.

## Progress: Milestone 3 (memory operations)

Milestone 3 added the memory subsystem. The pipeline now runs loads and
stores end-to-end through a Load-Store Queue and a write-back data cache,
the byte/half/word RV32IM memory ops all work, and JAL/JALR finally write
the return address into the destination register. That last one was a
milestone 2 bug nobody noticed until the first C program tried to call a
function and crashed on a wild jump.

For the full writeup of what changed and why, see
[`doc/milestone3-report.md`](doc/milestone3-report.md). The per-program
table is in [`doc/milestone3-results.md`](doc/milestone3-results.md).

### What got built

- `verilog/dcache.sv`: 32-line direct-mapped, write-back, write-allocate
  data cache. 256 bytes, the spec cap. Sub-word stores stay inside the
  cache via byte enables; only line evictions touch main memory.
- `verilog/lsq.sv`: combined load/store FIFO. It snoops the CDB to wake
  up base and data operands, has an internal AGU for the address, and
  only the head entry talks to the cache. Stores wait for the ROB to
  retire them before they touch the cache, so architectural memory is
  never written by a mis-speculated path.
- `verilog/pipeline.sv` rewritten: memory ops bypass the RS at dispatch
  and go directly into the LSQ; the inline single-line load FU is gone;
  CDB arbitration is now MULT > LSQ load complete > ALU; bus arbitration
  uses combinational `*_drives` signals to mask each cache's view of
  `mem2proc_response` to the cycle it actually drove the bus.
- `verilog/rob.sv`: new `is_store` field, `store_done` sideband, and the
  JAL/JALR return-address fix (commit value override for branches with a
  non-zero destination register).
- `test/dcache_test.sv` and `test/lsq_test.sv`: unit testbenches for the
  two new modules. Both pass in sim and synth.

### Module test status

| testbench | sim          | synth        |
|-----------|--------------|--------------|
| `mult`    | `@@@ Passed` | `@@@ Passed` |
| `rob`     | `@@@ Passed` | `@@@ Passed` |
| `rs`      | `@@@ Passed` | `@@@ Passed` |
| `dcache`  | `@@@ Passed` | `@@@ Passed` |
| `lsq`     | `@@@ Passed` | `@@@ Passed` |

Synthesis slack is positive on both new modules: `dcache` ≈ 587 ps,
`lsq` ≈ 0.44 ps (the LSQ is the tight one and would be the first thing
to gate a clock-period reduction).

### Full pipeline test results

All 34 programs in `programs/` reach `HALTED_ON_WFI`. The milestone 3
release shipped at 18/33; the remaining 15 (plus `mytest`, which
wasn't in the milestone-3 results table) were unblocked by a
post-milestone-3 fix to the RS issue selector. See the
[Post-milestone-3](#post-milestone-3-rs-issue-selector-fix) section
below for the explanation, or
[doc/rs-issue-loop-fix.md](doc/rs-issue-loop-fix.md) for the full
writeup. The pre-fix milestone-3 snapshot is preserved in
[doc/milestone3-results.md](doc/milestone3-results.md).

```
                  full pipeline test results

  passes  ##################################    34 / 34  (100%)
  fails                                          0 / 34  (  0%)
          |    |    |    |    |    |    |    |
          0    5    10   15   20   25   30   35
```

Per-program cycle counts:

```
  alexnet           9,465,750        halt                    106
  backtrack           264,002        insertion             3,630
  basic_malloc         50,037        insertionsort       842,214
  bfs                 112,494        matrix_mult_rec     726,606
  btest1               17,090        mergesort           303,270
  btest2               27,467        mult                  7,558
  copy                  3,701        mult_no_lsq           2,833
  copy_long             5,861        mytest                  419
  dft               1,708,161        no_hazard               731
  evens                 1,178        omegalul              3,964
  evens_long            2,979        outer_product     4,848,166
  fc_forward           55,381        parallel              2,325
  fib                   2,415        priority_queue       78,572
  fib_long              6,521        quicksort           958,030
  fib_rec              38,011        sampler               6,273
  graph               461,494        saxpy                 4,599
  haha                    940        sort_search         883,184
```

What got unblocked at milestone 3 specifically (loads, stores, and
the JAL/JALR return-address fix):

- `saxpy` and `copy_long` are the first programs with real loads and
  stores in a loop to finish.
- `basic_malloc`, `fc_forward`, `insertionsort`, `omegalul`, and
  `priority_queue` are the first five C programs to finish. They all
  depend on the JAL/JALR return-address fix.
- `fib_rec` and `sampler` were also unblocked by JAL/JALR.

Everything else came in with the post-milestone-3 RS fix.

Caveat: "halts cleanly" is the same metric the original milestone-3
results used. It is not full functional verification. There is no
golden reference output for these programs in the repo. For the 18
programs that were already passing at milestone 3 the identical cycle
counts are strong evidence of zero regression. For the 16 newly
passing (15 from the milestone-3 fail table plus `mytest`) only the
WFI / clean halt is verified, so nothing here proves that `quicksort`
actually emits a sorted array.

### What's deferred

- Store-to-load forwarding. The current head-only LSQ serializes all
  memory ops; a forwarding path would let independent loads bypass an
  in-flight store.
- LSQ flush on branch mispredict. The flush input is wired but not
  exercised, since branches still stall the front-end and no speculation
  reaches the LSQ.
- Full pipeline synthesis with timing closure.

## Post-milestone-3: RS issue-selector fix

The "tight loop" hang that took out 15 of the 33 milestone-3 programs
turned out not to be in the LSQ at all. It was a combinational loop in
the RS issue selector: `issue_found` depended on `src*_ready_eff`,
which depended on `cdb_valid`, which depended on `issue_accept`, which
depended back on `issue_found`. Whenever a lower-index RS slot was
wakeable from the CDB tag of a higher-index slot the ALU was issuing,
the selector ping-ponged between them and VCS sat inside a single
timestamp forever.

`mult_no_lsq` was the most reproducible victim because its iter-2
mul/add chain produces that exact RS configuration at cycle ≈2192.
Most other "tight loop" programs hit it eventually for the same
reason. The LSQ wake-up hypothesis from milestone 3 was a wrong guess.

The fix is one block in `verilog/rs.sv`: the issue selector now reads
the registered `entries[i].src1_ready` / `src2_ready` instead of the
combinational `_eff` versions. The CDB-bypass path is still used on
the issued entry's `src_value` output, so correctness is unchanged;
the only behavior difference is that an instruction whose dependency
arrives on the same cycle's CDB now waits one extra cycle to issue.
Standard P6 wakeup-then-select.

Credit for the diagnosis goes to `xh2718` of
`CSEE4340-26/p4.GaPiChiXuXu`, whose commit
[`397ea7d`](https://github.com/CSEE4340-26/p4.GaPiChiXuXu/commit/397ea7d421499bc0f43a9a99cd950ad374e0d985)
contains the same comment now sitting above our issue selector. Their
commit did several other unrelated things for an earlier-milestone
tree; only the `rs.sv` selector change was applicable here.

Full writeup, including the loop diagram, the cycle-2192 trace, the
per-program before/after table, and the caveat about what "halts
cleanly" does and doesn't verify, is in
[doc/rs-issue-loop-fix.md](doc/rs-issue-loop-fix.md).

Commit:
[`194b97d`](https://github.com/nyavana/4340-p4/commit/194b97d)
on `milestone3` (fast-forward from `2532ed4`).

## Progress: Milestone 4 (branch prediction) — base design complete and signed off

Milestone 4 is branch prediction. Direct-mapped 32-entry BTB, 64-entry
bimodal with 2-bit counters, combinational predict at fetch, registered
update at commit. `branch_pending` is tied to zero, so several branches
can be in flight at once; on a mispredict the ROB raises a one-cycle
`mispredict_valid` / `mispredict_target` sideband that flushes RS, LSQ,
and MULT and redirects the PC.

Base design is signed off. Evidence is in
[`doc/base-design-verification.md`](doc/base-design-verification.md): all
6 tested modules pass in sim and synth, and every one of the 34 programs
halts on WFI both on `milestone4` and on the same commit rebuilt with
`+define+SERIALIZE_BRANCHES` (the diagnostic serialized-front-end ifdef
already in `pipeline.sv`), with every `.wb` writeback stream byte-identical
between the two runs. The branch predictor doesn't touch architectural
state; it just reorders when non-branch instructions show up. Branch-heavy
benchmarks speed up: `fib_rec` −10.5%, `insertion` −6.5%,
`insertionsort` −6.4%, `sort_search` −5.9%, `fc_forward` −4.3%,
`outer_product` −3.8%, `quicksort` −3.5%. Nothing regresses.
Full-pipeline synthesis (`synth/pipeline.vg`) is built and reported: worst
slack −309 ps on the RS→MULT stage-0 combinational path. Retune is a
follow-up.

Four integration bugs showed up during bring-up, all hidden by the
old front-end serialization. They are written up in full in the
[branch-predictor report](doc/branch-predictor-report.md):

1. JAL/JALR silent-zero: `verilog/rs.sv` carries `branch_NPC` per
   entry and the CDB broadcasts it for uncond branches.
2. LSQ committed store lost on a flush + cache-done race:
   `verilog/lsq.sv` pops the preserved head store inside the flush
   branch when its own `dcache_done` lands on the flush cycle.
3. Stale D-cache response latched by the next head load:
   `verilog/lsq.sv` tracks `stale_response_count` and swallows
   the orphaned `dcache_done`. The `sort_search`-class same-cycle
   accept+flush edge is covered by the additional
   `head_load_releasable && !dcache_busy` arm.
4. Icache response latched into the wrong line after a PC change:
   `verilog/icache.sv` gates `got_mem_data` on `!changed_addr`.

For the module design, full cycle-count table, prediction accuracy
numbers, and known limitations (no RAS, direct-mapped BTB), see
[`doc/branch-predictor-report.md`](doc/branch-predictor-report.md).
