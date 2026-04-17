# `week3` Merge Report — milestone1 + milestone2

Date: 2026-04-07
Author: git user `nyavana`
Worktree: `/homes/user/stud/spring26/cy2822/eecs4340/4340-p4-week3`
Branch: `week3` (local only, not pushed to origin)
Merge commit: `8b483d5`

## Why this merge was needed

The project had three branches diverging from `817c826` ("Initial release"):

- `release` (`5802c8a`): baseline plus progress notes
- `milestone1` (`9be6622`): added `verilog/rs.sv` and `test/rs_test.sv`, set `ROB_SZ=8`/`RS_SZ=8`
- `milestone2` (`6f649b6`): added `verilog/rob.sv` and heavily refactored `verilog/pipeline.sv`

The two milestones turned out to be complementary, not alternatives. milestone2's `verilog/pipeline.sv` instantiates `rs rs_0 (...)` at lines 330-359, but `verilog/rs.sv` only existed on milestone1, so milestone2 could not compile on its own. milestone1 did not have the refactored pipeline or `rob.sv`, so it had no way to test integration. Nothing built end-to-end on either side.

The main working tree also had a lingering `<<<<<<< Updated upstream` / `>>>>>>> Stashed changes` marker block in `Makefile:180-184`. Those markers were leftovers from a failed `git stash pop`, and they had already been committed into milestone2, so any future merge of milestone2 would drag them along.

## Approach

1. Created a new git worktree at `../4340-p4-week3` on a new branch `week3` rooted at `milestone1`:
   ```
   git worktree add -b week3 ../4340-p4-week3 milestone1
   ```
   Note: `git worktree add -b week3 ... milestone1` first created a `milestone1` local tracking branch instead of `week3`, because `milestone1` was only a remote ref. Fixed with `git checkout -b week3` inside the worktree.

2. Merged `origin/milestone2` into `week3` with a non-fast-forward merge:
   ```
   git merge --no-ff origin/milestone2 \
     -m "merge: bring milestone2 (ROB + pipeline refactor) into milestone1 trunk on week3"
   ```

3. Resolved two conflict points by hand (see next section).

4. Finalized with `git merge --continue`.

## Conflicts encountered and how they were resolved

### `verilog/sys_defs.svh` — auto-merged cleanly

Nothing to do by hand. milestone1 edited the `ROB_SZ` / `RS_SZ` lines; milestone2 edited the `NUM_FU_*` lines. Git's three-way merge handled the disjoint changes automatically. Final Parameters block:

```systemverilog
`define N 1
`define ROB_SZ 8       // from milestone1
`define RS_SZ  8       // from milestone1
`define PHYS_REG_SZ (32 + `ROB_SZ)

`define BRANCH_PRED_SZ xx    // placeholder — not wired up
`define LSQ_SZ         xx    // placeholder — not wired up

`define NUM_FU_ALU  1        // from milestone2
`define NUM_FU_MULT 1        // from milestone2
`define NUM_FU_LOAD  xx
`define NUM_FU_STORE xx

`define MULT_STAGES 4
```

### `Makefile:180` — nested conflict, resolved by hand

milestone2 had committed the stash-pop leftovers, so the merge produced a conflict inside a conflict:

```makefile
<<<<<<< HEAD
TESTED_MODULES = mult rob RS rs
=======
<<<<<<< Updated upstream
TESTED_MODULES = mult rob
=======
TESTED_MODULES = mult rob rs
>>>>>>> Stashed changes
>>>>>>> origin/milestone2
```

Collapsed to a single clean line, dropping milestone1's `RS rs` typo:

```makefile
TESTED_MODULES = mult rob rs
```

The `SOURCES` block already listed both `verilog/rob.sv` and `verilog/rs.sv` (added on milestone2), and the `RS_DEPS =` / `ROB_DEPS =` dependency stanzas were already in place. No other Makefile edits were needed.

### Files merged cleanly (no conflict)

- `verilog/rob.sv` — added from milestone2
- `verilog/pipeline.sv` — heavy refactor, taken from milestone2 verbatim (milestone1 did not touch it)
- `test/pipeline_test.sv` — taken from milestone2
- `programs/mytest.s`, `programs/mytest.mem` — added from milestone2
- `verilog/rs.sv`, `test/rs_test.sv` — kept from milestone1 (milestone2 did not touch them)

## Verification results

All runs happened inside `../4340-p4-week3` with the VCS toolchain.

### `make simv` — PASS

Compiled with 0 errors and 0 warnings. This is the first time we could confirm that milestone1's `rs.sv` port signature lines up with milestone2's `rs rs_0` instantiation in `pipeline.sv:330-359`. Before this merge, `make simv` was impossible on either branch alone.

### `make no_hazard.out` — PASS

- 14 instructions executed
- 731 cycles
- Clean halt on `HALTED_ON_WFI`
- Writebacks match expected values:
  ```
  PC=00000000, REG[ 1]=00000001
  PC=00000004, REG[ 2]=00000002
  PC=00000008, REG[ 3]=00000008
  PC=0000000c, REG[ 4]=00000004
  PC=00000010, REG[ 5]=00000005
  ...
  ```
- CPI: 52.21. High because of the 100 ns memory latency on icache misses, which is expected for this workload.

### `make mult_no_lsq.out` — NONDETERMINISTIC (known follow-up)

Behavior differed across runs:

- Run A: 44 correct-looking writebacks in ~45 seconds, with multiplication results like `REG[11]=3d8587e8`, `REG[11]=48d5d725`. The processor ran through the setup phase and entered the loop body at `0x68`.
- Run B (same command sequence): 0 writebacks in 10+ minutes of sim time. Only the reset-phase output appeared; the testbench never committed an instruction.

This is a pre-existing pipeline bug inherited from milestone2, not something the merge introduced. It could not have been caught earlier because milestone2 was unbuildable on its own (no `rs.sv`). The merge is what made it visible at all.

## Final git state

```
*   8b483d5 merge: bring milestone2 (ROB + pipeline refactor) into milestone1 trunk on week3
|\
| * 6f649b6 change1                             (origin/milestone2)
* | 9be6622 Implemented RS and its testbench... (origin/milestone1, local milestone1)
|/
| * 5802c8a explain milestone 1 & 2 progress    (origin/release, local release)
|/
* 817c826 Initial release
```

Worktrees:
```
/homes/user/stud/spring26/cy2822/eecs4340/4340-p4        6f649b6 (detached HEAD)
/homes/user/stud/spring26/cy2822/eecs4340/4340-p4-week3  8b483d5 [week3]
```

Local branches in the week3 worktree: `week3` (current), `milestone1`, `release`. `origin/milestone2` is a remote-tracking ref; no local `milestone2` branch was created.

## Follow-up work

In rough priority order:

1. Debug the `mult_no_lsq` nondeterminism. Likely culprits:
   - CDB arbitration in `verilog/pipeline.sv:467-502`. MULT has priority over ALU via `issue_accept = rs_issue_valid && (is_mult ? !mult_busy : !mult_done)`.
   - Multiplier handshake around `mult_busy` / `mult_done` in `verilog/pipeline.sv:417-431`.
   - Uninitialized state in `verilog/rs.sv` or `verilog/rob.sv` causing X-propagation that sometimes resolves and sometimes does not.
   - Race between ROB commit → `PC_reg` redirect and in-flight instructions.
2. Write `test/rob_test.sv`. It is missing on all branches, so `make rob.pass` fails at compile. The existing `test/rs_test.sv` is a reasonable structural template.
3. Clean up the main worktree. Currently detached at `6f649b6`, with stale stash-pop markers in its copy of `Makefile`, an untracked `doc/` directory, an untracked `CLAUDE.md`, and a staged `D pdfs/eecs4340project4.pdf`. Decide what to preserve and what to drop. The stash-pop markers in the main worktree's Makefile are not the same as the conflict that was resolved in `week3`; the `week3` merge commit already has a clean Makefile.
4. Push `week3` to `origin` once the `mult_no_lsq` bug is fixed and the branch is ready for team review.

## Reference: files changed by the merge commit

```
 Makefile              |   5 +-
 programs/mytest.mem   |  12 +
 programs/mytest.s     |  12 +
 test/pipeline_test.sv |   2 +-
 verilog/pipeline.sv   | 594 +++++++++++++++++++++++++++++++++++++++++---------
 verilog/rob.sv        | 253 +++++++++++++++++++++
 verilog/sys_defs.svh  |   4 +-
 7 files changed, 774 insertions(+), 108 deletions(-)
```
