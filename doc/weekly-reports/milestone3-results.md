# Milestone 3 Per-Program Test Results

> **Update:** all 15 of the failures listed below are fixed in commit
> [`194b97d`](https://github.com/nyavana/4340-p4/commit/194b97d). The
> root cause was a combinational loop in the RS issue selector, not
> anything in the LSQ. See the [post-fix update](#post-fix-update)
> section at the bottom of this file and
> [rs-issue-loop-fix.md](../base-design/rs-issue-loop-fix.md) for the writeup. The
> tables below are preserved as the record of what shipped under the
> `milestone3` label (commit `2532ed4`).

Pipeline configuration: ROB_SZ=8, RS_SZ=8, LSQ_SZ=8, DCACHE_LINES=32, MULT_STAGES=4, CLOCK_PERIOD=1000 ps.

Each program was run with `make <prog>.out` against the milestone-3 simv build with a 90-second wall-clock timeout. "Pass" means the testbench reached `HALTED_ON_WFI`.

## Summary

| | count |
|---|---|
| pass | 18 |
| fail | 15 |
| total tested | 33 |
| pass rate | ≈ 55% |

## Per-program

### Pass

| program | cycles | notes |
|---|---|---|
| `halt` | 106 | tiniest sanity check |
| `no_hazard` | 731 | independent ALU ops |
| `evens` | 1178 | basic loop, no memory |
| `evens_long` | 2979 | longer loop |
| `fib_long` | 6521 | NOP-padded fib |
| `fib_rec` | 38011 | recursive fib, needs JAL/JALR return address (now fixed) |
| `haha` | 940 | misc |
| `insertion` | 3630 | small assembly insertion test |
| `btest1` | 17090 | branch tests |
| `btest2` | 27467 | branch tests |
| `sampler` | 6273 | depends on JAL/JALR fix |
| `saxpy` | 4599 | first program with real loads + stores in a loop |
| `copy_long` | 5861 | NOP-padded version of `copy` |
| `basic_malloc` | 50037 | C program, first malloc workload to finish |
| `fc_forward` | 55381 | C program with array reads + writes |
| `insertionsort` | 842214 | C insertion sort, full run |
| `omegalul` | 3964 | small C program |
| `priority_queue` | 78572 | C heap-based priority queue |

### Fail

| program | symptom | likely cause |
|---|---|---|
| `fib` | hang after ~23 commits | tight memory loop, second iteration stalls |
| `parallel` | hang | pre-existing milestone-2 hang |
| `mult_no_lsq` | hang at 44 commits | pre-existing milestone-2 hang at PC 0x6c |
| `mult` | hang | tight loop |
| `copy` | hang at 13 commits | tight loop with sw + lw + sw + branch back |
| `alexnet` | timeout, very long | large C program, also tight loops |
| `backtrack` | hang | tight loop |
| `bfs` | hang | tight loop |
| `dft` | hang or timeout | long-running |
| `graph` | hang | tight loop |
| `matrix_mult_rec` | hang | tight loop / recursion |
| `mergesort` | hang | tight loop |
| `outer_product` | hang | tight loop |
| `quicksort` | hang | tight loop |
| `sort_search` | hang | tight loop |

The hang signature is the same in every case: PC sits on the first instruction of the second iteration of an inner loop and the LSQ has a single store at its head with `committed=1`, `in_flight=1`, but `dcache_done` never asserts.  `mult_no_lsq` and `parallel` already exhibit this behaviour on the milestone-2 pipeline (verified by running the parent worktree's `simv`), so at least part of this is inherited rather than caused by the LSQ.

> **Note:** the LSQ-side analysis above turned out to be wrong. The
> debug signals (LSQ head with `committed=1` and `dcache_done` never
> asserting) were the symptom, not the cause. The actual root cause is
> a combinational loop in `rs.sv`; see the
> [post-fix update](#post-fix-update) below.

## Module test bench results

| testbench | sim | synth |
|---|---|---|
| `mult` | `@@@ Passed` | (pre-existing) |
| `rob`  | `@@@ Passed` | `@@@ Passed` |
| `rs`   | `@@@ Passed` | `@@@ Passed` |
| `dcache` | `@@@ Passed` | `@@@ Passed` |
| `lsq`    | `@@@ Passed` | `@@@ Passed` |

## Synthesis slack

```
synth/dcache.rep   slack (MET)  ~ 587 ps
synth/lsq.rep      slack (MET)  ~ 0.44 ps
```

LSQ slack is the tight one and would be the first to gate a clock-period reduction.

## Post-fix update

Commit [`194b97d`](https://github.com/nyavana/4340-p4/commit/194b97d)
on `milestone3` is one block in `verilog/rs.sv` that breaks a
combinational loop in the issue selector. After that fix, all 34
programs in `programs/` reach `HALTED_ON_WFI`. The 18 listed in the
"Pass" table above produce identical cycle counts, so the change does
not regress anything. The 15 listed in the "Fail" table now pass:

| program | post-fix cycles | post-fix instrs | CPI |
|---|---|---|---|
| `fib` | 2,415 | 150 | 16.10 |
| `parallel` | 2,325 | 200 | 11.62 |
| `mult_no_lsq` | 2,833 | 283 | 10.01 |
| `mult` | 7,558 | 326 | 23.18 |
| `copy` | 3,701 | 132 | 28.04 |
| `backtrack` | 264,002 | 7,202 | 36.66 |
| `bfs` | 112,494 | 3,484 | 32.29 |
| `dft` | 1,708,161 | 57,874 | 29.52 |
| `graph` | 461,494 | 11,126 | 41.48 |
| `matrix_mult_rec` | 726,606 | 21,677 | 33.52 |
| `mergesort` | 303,270 | 9,482 | 31.98 |
| `outer_product` | 4,848,166 | 746,143 | 6.50 |
| `quicksort` | 958,030 | 95,471 | 10.03 |
| `sort_search` | 883,184 | 181,994 | 4.85 |
| `alexnet` | 9,465,750 | 209,069 | 45.28 |

`mytest` (419 cyc / 8 instr) was not in the original results table
above, but it also halts cleanly on the post-fix build, so the new
total is 34 / 34.

### Updated summary

| | milestone 3 (`2532ed4`) | post-fix (`194b97d`) |
|---|---|---|
| pass | 18 | 34 |
| fail | 15 | 0 |
| total tested | 33 | 34 |
| pass rate | ≈ 55% | 100% |

### Why the LSQ hypothesis was wrong

Every failing program produced the same hang signature: PC stuck on
the second iteration of an inner loop, LSQ head with one entry,
`dcache_done` never asserting. That pointed at a missed wake-up
between LSQ and ROB. It wasn't.

The actual bug:

- `verilog/rs.sv` issue selector used `src*_ready_eff[i]`, which OR'd
  the registered `src*_ready` with a same-cycle CDB wakeup. So
  `issue_found` depended on `cdb_valid` and `cdb_tag`.
- `verilog/pipeline.sv` ALU branch of CDB arbitration drove
  `cdb_valid` and `cdb_tag` from `rs_issue_dest_tag`, which traces
  back to `issue_found`.
- Closed loop:
  `issue_found -> src*_ready_eff -> cdb_valid -> issue_accept -> issue_valid -> issue_found`.

Whenever a lower-index RS slot was wakeable from the CDB tag of a
higher-index slot the ALU was issuing, the selector ping-ponged and
VCS sat inside the timestamp. Any RAW chain through the ALU and CDB
would eventually trip it, which is why all 15 failures had the same
deadlock signature even though only some of them touched memory.

The LSQ debug signals were the symptom, not the cause: the entire
pipeline stops when the simulator stops advancing time, and the LSQ
head with `committed=1` is just where the queue happened to be sitting
when time froze.

Full writeup: [rs-issue-loop-fix.md](../base-design/rs-issue-loop-fix.md).
