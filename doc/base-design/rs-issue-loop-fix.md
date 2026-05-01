# RS issue-selector combinational loop (post-milestone-3 fix)

The week 4 deferred bug (the `mult_no_lsq` hang at cycle 2192) was a
combinational loop in the RS issue selector. The week 4 findings doc
pointed at the `icache.sv` / `test/mem.sv` boundary, which was the
wrong location, but it had the right *kind* of bug: simulator time
stops inside a single timestamp because VCS keeps re-evaluating
combinational logic in delta cycles that never converge.

## The cycle

Three pieces of code formed a closed loop.

1. `verilog/rs.sv`, the issue-selection `always_comb`. It picked the
   first ready entry by checking `src1_ready_eff[i]` and
   `src2_ready_eff[i]`, which OR the registered `src*_ready` with a
   same-cycle CDB wakeup. So `issue_found` depended on `cdb_valid` and
   `cdb_tag`.
2. `verilog/pipeline.sv:200`, the `issue_accept` assign. When the ALU
   was the chosen path, `issue_accept` reduced to `rs_issue_valid`,
   which is `issue_valid`, which is `issue_found`.
3. `verilog/pipeline.sv:688`, the ALU branch of CDB arbitration:
   `else if (issue_accept && !issue_is_mult) cdb_valid = 1; cdb_tag = rs_issue_dest_tag;`.
   This drove `cdb_valid` and `cdb_tag` from whichever entry the
   selector had picked.

So:

```
issue_found  ->  src*_ready_eff[i]  ->  cdb_valid  ->  issue_accept
             ->  issue_valid        ->  issue_found
```

A loop.

## When it bites

The loop only matters when one RS slot is wakeable from the CDB tag of
*another* slot the ALU is currently issuing. If the wakeable slot is
the lower-index one, swapping the selection changes `cdb_tag`, which
un-wakes the lower slot, which swaps the selection back. VCS sits
inside that timestamp and never advances.

On `mult_no_lsq` this trips at cycle ≈2192, in the second iteration of
the loop. Iter-2 `add x11` is in `rs[1]` and is wakeable from iter-2
`mul x11` on the CDB. Iter-2 `mul x12` is in `rs[0]` and wants to issue
but depends on the not-yet-finished `add x11`. The selector ping-pongs
between `rs[0]` and `rs[1]`, time freezes, and the writeback file is
stuck at exactly 44 lines.

The pattern is generic. Any program with a chain of RAW dependencies
running through the ALU and the CDB will eventually land in a state
that trips it. That is why almost every "tight loop" program in
`programs/` was hanging before this fix, including the C programs that
[`milestone3-report.md`](../weekly-reports/milestone3-report.md) blamed on "tight memory
loops with no slack." The LSQ wasn't the problem. The diagnosis was
wrong.

## The fix

In `verilog/rs.sv`, the issue selector now uses the *registered*
`entries[i].src1_ready` / `src2_ready` instead of the combinational
`_eff` versions:

```systemverilog
// Use registered src_ready (not src_ready_eff) to avoid combinational loop:
// src1_ready_eff depends on cdb_valid, which depends on issue_accept,
// which depends on issue_found — using _eff here creates a cycle that
// causes oscillation when a lower-index entry is woken by the CDB of
// the currently-selected higher-index entry.
for (i = 0; i < RS_SIZE; i++) begin
    if (!issue_found &&
        entries[i].busy &&
        entries[i].src1_ready &&
        entries[i].src2_ready) begin
        issue_found = 1'b1;
        issue_idx   = i[$clog2(RS_SIZE)-1:0];
    end
end
```

The CDB-bypass path is preserved on the issued entry's `src_value`
output (`rs.sv:133-145`), where it does not feed back into selection.
The functional consequence: an instruction whose dependency arrives on
the same cycle's CDB now waits one extra cycle to issue. That is the
standard P6 wakeup-then-select behavior, and on the test programs the
CPI is unchanged.

Credit where it's due: I did not find this loop on my own. The same
comment that now sits above the issue selector was written by `xh2718`
of `CSEE4340-26/p4.GaPiChiXuXu` in their commit
[`397ea7d`](https://github.com/CSEE4340-26/p4.GaPiChiXuXu/commit/397ea7d421499bc0f43a9a99cd950ad374e0d985).
Their commit did several unrelated things (added a load FU, filled in
`sys_defs.svh` placeholders, fixed merge markers in the Makefile) for
a tree at an earlier milestone. I pulled out only the relevant `rs.sv`
change and applied that one piece on top of `milestone3` head.

## Test results after the fix

All 34 programs in `programs/` reach `HALTED_ON_WFI`. Up from 18.

The 18 that were already passing produce identical cycle counts to
the cycle, so the fix does not regress anything. The 15 that were
hanging or timing out all halt cleanly. `mytest`, which is not in the
milestone3 results table at all, also halts.

Before / after on the previously-failing programs:

| program | before | after |
|---|---|---|
| `fib` | hang | 2,415 cyc / 150 instr |
| `parallel` | hang | 2,325 cyc / 200 instr |
| `mult_no_lsq` | hang | 2,833 cyc / 283 instr |
| `mult` | hang | 7,558 cyc / 326 instr |
| `copy` | hang | 3,701 cyc / 132 instr |
| `backtrack` | hang | 264,002 cyc / 7,202 instr |
| `bfs` | hang | 112,494 cyc / 3,484 instr |
| `graph` | hang | 461,494 cyc / 11,126 instr |
| `matrix_mult_rec` | hang | 726,606 cyc / 21,677 instr |
| `mergesort` | hang | 303,270 cyc / 9,482 instr |
| `quicksort` | hang | 958,030 cyc / 95,471 instr |
| `sort_search` | hang | 883,184 cyc / 181,994 instr |
| `outer_product` | hang | 4,848,166 cyc / 746,143 instr |
| `dft` | timeout | 1,708,161 cyc / 57,874 instr |
| `alexnet` | timeout | 9,465,750 cyc / 209,069 instr |

`alexnet` and `outer_product` are the slow ones at roughly 11 and 16
seconds of wall-clock on this machine. Everything else finishes in
under 5 seconds.

## Caveats

"Halts cleanly" is the same metric the milestone 3 README uses to call
something a pass. It is not full functional verification. There is no
golden reference output for these programs in this repo. For the 18
previously-passing programs the identical cycle counts are strong
evidence of zero regression. For the 15 newly-passing programs only
the WFI / clean halt is verified. The writeback tails look reasonable
(final stores, then the `PC=...,---` lines into the WFI region), but
nothing here proves that, say, `quicksort` actually emits a sorted
array.

The `src1_ready_eff` / `src2_ready_eff` declarations and the
`always_comb` block that drives them in `rs.sv:65-101` are now dead.
Nothing reads them. Functionally harmless, but synthesis will warn
about a "driven but not read" net. Worth deleting in a follow-up.

## Commit

`fix(rs): use registered src_ready in issue select to break combinational loop`
([`194b97d`](https://github.com/nyavana/4340-p4/commit/194b97d))
on `milestone3`. Fast-forward from `2532ed4`.

## Follow-up: test sync (2026-04-17)

`test/rs_test.sv` still encoded the pre-fix behaviour where a CDB
pulse wakes an entry combinationally into issue. With the
registered `src*_ready` selector the wake-up takes one cycle to
latch before the selector fires, so two tests
(`test_dependency_wakeup_then_issue` and
`test_same_cycle_cdb_bypass_issue`) produced four false failures
at the assertion right after `drive_cdb + #1`. The tests now
insert `@(posedge clock); #1` between the CDB pulse and
`expect_issue`, which matches the wakeup-then-select semantics in
`rs.sv`.

Side note: the value-bypass mux on the issue output
(`rs.sv:159-168`) is structurally dead once the selector requires
registered ready on both operands. By the time `issue_found` is
true the entry has `src*_ready=1`, so the bypass condition
`!entries[issue_idx].src*_ready` is false. The mux can stay as a
defensive fallback; deleting it is a separate cleanup.

Commit: `update rs_test.sv due to makefile problem` (`d66fcae`),
which also adds a `mult.pass` / `mult.syn.pass` override so the
`mult` testbench does not collide with the `mult.mem` program's
`output/mult.out`. The `TB_ONLY_MODULES` filter in the Makefile
keeps `mult` out of the generic `output/%.out` testbench rule,
and the testbench now writes to `output/mult_tb.out`; `make
mult.out` still runs the `mult.mem` program as before.
