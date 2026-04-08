# Milestone 3 Per-Program Test Results

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
