# `week4` Follow-up Plan

Plan for the three items left open by the `week3` merge (see `doc/week3-merge-report.md`). All work happens in a new git worktree.

## Context

After the week3 merge, three things were still open:

1. `mult_no_lsq` nondeterminism. The merged pipeline sometimes produces 44 correct writebacks in 45 seconds, other times produces 0 in 10+ minutes. Pre-existing bug inherited from milestone2, which was previously unbuildable, so the bug was invisible until week3 made integration testing possible.
2. Missing `test/rob_test.sv`. `verilog/rob.sv` has no unit test, so `make rob.pass` fails at compile.
3. Stale state in the main worktree: detached HEAD at `6f649b6`, stash-pop conflict markers baked into milestone2's committed Makefile, untracked `CLAUDE.md` and `doc/`, and a working-tree deletion of `pdfs/eecs4340project4.pdf`.

All three are now unblocked because `week3` is in a buildable state. The plan addresses them in a new `week4` branch, with the cleanup (#3) sequenced last so the main worktree stays untouched while the investigation and test writing are in progress.

## Setup — new worktree

Create a new worktree rooted at the `week3` merge commit so the bugfix and the new test land on top of the working merge:

```
cd /homes/user/stud/spring26/cy2822/eecs4340/4340-p4
git worktree add -b week4 ../4340-p4-week4 week3
cd ../4340-p4-week4
git status          # expect: on branch week4, clean
```

Note: recall from week3 that `git worktree add -b <new> <path> <ref>` can misbehave when `<ref>` is a remote-only branch. `week3` is a local branch, so this should work directly, but verify with `git branch -vv` after creation.

Commit hygiene: each of the three tasks below produces one or more focused commits on `week4`. Use separate commits per task so bisect stays useful and the cleanup can be reverted independently of the bugfix.

---

## Task 1 — Debug `mult_no_lsq` nondeterminism

### Reproduce reliably

1. Run `make mult_no_lsq.out` 5-10 times in a row, recording:
   - Wall-clock duration
   - Number of writebacks produced (`wc -l output/mult_no_lsq.wb`)
   - Whether the `.out` file shows `System halted on WFI` (success) or the `debug_counter > 50000000` early-termination message
2. If the failure is intermittent, capture one successful and one failing run's `.wb`, `.ppln`, and `.out` files side-by-side. The divergence point narrows the bug.
3. If `.wb` is consistently empty, the pipeline never commits a single instruction. That is a different failure mode from the 44-writeback run; record which one reproduces.

### Narrow with Verdi

```
make mult_no_lsq.verdi
```

Focus signals in the waveform:
- `pipeline.PC_reg` — is fetch advancing past reset?
- `pipeline.Icache_valid_out`, `pipeline.stall`, `pipeline.dispatch_fire` — is dispatch ever firing?
- `pipeline.rs_full`, `pipeline.rob_full` — is a queue stuck full?
- `pipeline.rs_issue_valid`, `pipeline.issue_accept`, `pipeline.issue_is_mult` — is the RS issuing?
- `pipeline.mult_busy`, `pipeline.mult_done` — does the multiplier handshake cycle correctly?
- `pipeline.cdb_valid`, `pipeline.cdb_tag`, `pipeline.cdb_value` — is the CDB ever active?
- `pipeline.rob_commit_valid`, `pipeline.rob_commit_dest_reg` — is the ROB head ever ready?
- `pipeline.branch_pending` — is the front-end stuck waiting on a branch that never commits?

### Specific hypotheses to test (roughly most to least likely)

Hypothesis A. CDB arbitration starves the ALU while mult is busy.
`verilog/pipeline.sv:135-136` has:
```systemverilog
assign issue_accept = rs_issue_valid &&
                      (issue_is_mult ? !mult_busy : !mult_done);
```
If `mult_done` is ever stuck high for multiple cycles, the ALU can never accept an issue. Check the `mult_done` waveform for a persistent-high window. Fix if confirmed: latch `mult_done` for exactly one cycle and clear it once consumed by the CDB.

Hypothesis B. `mult_busy` / `mult_done` race at `pipeline.sv:417-431`.
```systemverilog
always_ff @(posedge clock) begin
    if (reset) ...
    else begin
        if (mult_done) mult_busy <= 1'b0;
        if (issue_accept && issue_is_mult) begin
            mult_busy <= 1'b1;
            ...
        end
    end
end
```
If `mult_done` fires on the same cycle a new mult issues, both assignments target `mult_busy` and the `if` order wins. But `issue_accept` requires `!mult_busy`, so a new mult should not be accepted while mult is busy. Verify with `$display` that `mult_done` and `issue_accept && issue_is_mult` never co-occur.

Hypothesis C. Uninitialized state in `verilog/rs.sv` (X-propagation).
The RS was written against milestone1 (no ROB) and is now interacting with milestone2's ROB for the first time. Audit `verilog/rs.sv` for any `logic` not explicitly reset in the `always_ff` reset branch. Also try running with `simv +vcs+initreg+random` and `+vcs+initreg+zero` and compare. If behavior changes between random and zero init, there is an uninitialized read.

Hypothesis D. Same-cycle CDB bypass in the ROB's RAT query.
`verilog/rob.sv:117-150` bypasses the CDB value into `query1_value` / `query2_value` when `rat_busy && cdb_valid && (q_tag_int == cdb_tag) && !entries[q_tag_int].ready`. If `entries[cdb_tag].ready` is updated combinationally elsewhere, the `!ready` guard can flip mid-cycle. Verify in waveforms that `query*_value` is stable across a cycle when CDB is firing.

Hypothesis E. PC redirect on branch commit loses fetched work.
`verilog/pipeline.sv:159-166`:
```systemverilog
if (reset) PC_reg <= '0;
else if (rob_commit_valid && rob_commit_take_branch) PC_reg <= rob_commit_branch_target;
else if (!stall) PC_reg <= PC_reg + 4;
```
When a branch commits and redirects PC, any in-flight instructions younger than the branch are not flushed; the ROB does not assert `flush` on branch commit. This is a correctness bug regardless: a conditional branch that commits as "taken" must invalidate speculative work behind it. The current front-end only fetches past a branch after it commits (via `branch_pending`), so speculative work should not exist in practice. Verify there are no paths that let a second instruction dispatch while `branch_pending` is high.

### Fix and verify

1. Write a one-line reproducer comment in the fix commit pointing at the waveform artifact that demonstrated the bug.
2. Re-run `mult_no_lsq.out` 10 times in a row. All 10 must halt on WFI with identical `.wb` output.
3. Also run `no_hazard.out`, `fib.out`, `copy.out`, `saxpy.out`, `sampler.out` as regression. All must halt cleanly.
4. Commit as `fix(pipeline): <root cause> breaking mult_no_lsq`.

### Success criteria

- `make mult_no_lsq.out` is deterministic across 10 runs.
- `.wb` output is consistent and matches what a reference run (or manual trace) expects.
- No regressions in `no_hazard.out` (which already passes).

---

## Task 2 — Write `test/rob_test.sv`

### Read before writing

- `verilog/rob.sv`: port list, entry struct, priority order in the next-state block (`flush > CDB complete > commit > dispatch`).
- `test/rs_test.sv`: structural template for clock generation, reset, `@@@ Passed` / `@@@ Incorrect` printing, and any shared helpers.
- `verilog/sys_defs.svh`: `ROB_SZ` is currently 8. Tests must parameterize off `` `ROB_SZ `` rather than hardcoding.

### Test cases to cover

1. Basic dispatch → CDB complete → commit.
   Dispatch one instruction with `dispatch_dest_reg = 5`. Drive `cdb_valid` / `cdb_tag = returned_dispatch_tag` / `cdb_value = 32'hDEAD_BEEF`. Verify `commit_valid`, `commit_dest_reg == 5`, `commit_value == 32'hDEAD_BEEF`.

2. In-order commit despite out-of-order completion.
   Dispatch three instructions (tags 0, 1, 2). Complete tag 2 via CDB first, then tag 1, then tag 0. Verify no commit until tag 0 completes, then three successive commits in order 0, 1, 2.

3. RAT query returns pending + tag for a pending write.
   Dispatch an instruction writing to `rd = 7`. In the same cycle (or next), drive `query1_arch_reg = 7` and verify `query1_pending == 1`, `query1_ready == 0`, `query1_tag == dispatch_tag`.

4. Same-cycle CDB bypass in RAT query.
   Set up the state from test 3, then on the same cycle as the CDB completes the instruction, drive the query. Verify `query1_ready == 1` and `query1_value == cdb_value`.

5. RAT clears on commit when still the latest writer.
   Dispatch inst writing to reg 5 → complete → commit. Then query reg 5. Verify `query1_pending == 0`.

6. RAT stale-clear protection.
   Dispatch inst0 to reg 5 (tag 0), dispatch inst1 to reg 5 (tag 1). RAT now points at tag 1. Complete inst0 via CDB, then commit inst0. Query reg 5. Verify `query1_pending == 1` and `query1_tag == 1` (the RAT was not cleared by inst0's commit because it is no longer the latest writer).

7. x0 guard.
   Dispatch inst writing to x0. Verify RAT never marks x0 as busy (query x0 → `pending == 0`). Also verify commit of an x0-destined instruction does not touch RAT state.

8. Flush clears everything.
   Dispatch several instructions, assert `flush` for one cycle, then query all 32 arch regs. Verify all `pending == 0`, and verify `rob_full == 0` on subsequent dispatch.

9. Full detection.
   Dispatch `` `ROB_SZ `` instructions in consecutive cycles. Verify `rob_full` asserts exactly when the ROB has `ROB_SZ` entries.

10. Wraparound.
    Dispatch and commit `` `ROB_SZ + 3 `` instructions sequentially (each completes and commits before the next dispatches). Verify head/tail wrap correctly and no stuck state.

### Structure

- Match `test/rs_test.sv`'s reporting convention: `$display("@@@ Passed")` on success, `$display("@@@ Incorrect: <reason>")` on any failure, `$finish` after.
- Each test case should be a labeled `begin ... end` block with a clear `$display("Test N: <name>")` at the start for grep-ability.
- Use a task/function for `dispatch_one`, `complete_cdb`, `commit_one`, `query_reg` to keep test bodies readable.

### Add to build

In `../4340-p4-week4/Makefile`:
- `TESTED_MODULES = mult rob rs` already includes `rob`. No change needed.
- `ROB_DEPS =` is already declared (line ~201). No change unless `test/rob_test.sv` depends on another source file.

### Success criteria

- `make rob.pass` prints `@@@ Passed`.
- `make rob.syn.pass` also prints `@@@ Passed` (the synthesized ROB behaves identically).
- `make rob.coverage` shows reasonable line/fsm/branch coverage over `verilog/rob.sv` (aim for ≥80% lines).
- Commit as `test(rob): add unit testbench covering dispatch, CDB, commit, RAT bypass, flush`.

---

## Task 3 — Clean up the main worktree

### Current state (verified)

```
HEAD detached at 6f649b6 (milestone2 tip)
Changes not staged for commit:
    deleted:    pdfs/eecs4340project4.pdf
Untracked files:
    CLAUDE.md
    doc/
```

The main worktree's `Makefile` has the stash-pop conflict markers committed into the `6f649b6` commit. They are not a local modification. The markers will remain until the worktree is switched to a different branch (for example `week3`, which already has them resolved).

### What to preserve

- `CLAUDE.md` — project guide written during `/init`. Should live on `week3` (or `week4`) so future sessions find it.
- `doc/project-description.md`, `doc/project-proposal.md` — project spec references. Should be committed to a stable branch (either `release` or `week3`).
- `doc/week3-merge-report.md` — post-merge audit. Should live on `week3`.
- `doc/week4-followup-plan.md` — this file. Should live on `week4`.

### What to discard

- The `6f649b6` detached checkout itself. Not a branch, not needed.
- The working-tree deletion of `pdfs/eecs4340project4.pdf`. The PDF was replaced by `doc/project-description.md` and `doc/project-proposal.md`, so the deletion is intentional. Accept it.

### Execution steps (run from the week4 worktree, operating on main's state)

1. First, preserve the untracked content on `week3`. From the week4 worktree:
   ```
   # Copy the untracked files from main into week4's tree so they can be committed
   cp /homes/user/stud/spring26/cy2822/eecs4340/4340-p4/CLAUDE.md .
   mkdir -p doc
   cp /homes/user/stud/spring26/cy2822/eecs4340/4340-p4/doc/*.md doc/

   git add CLAUDE.md doc/
   git commit -m "docs: add CLAUDE.md project guide and doc/ references

   Preserves the project documentation and merge/follow-up reports that
   were sitting untracked in the main worktree. CLAUDE.md was produced by
   /init; doc/ holds the spec, week3 merge report, and this week4 plan."
   ```
   This lands the docs on `week4`, which branches from `week3`. If the docs should live on `week3` itself instead, cherry-pick the commit back: `git checkout week3 && git cherry-pick week4 && git checkout week4`.

2. Attach the main worktree to a proper branch. From the main worktree directory:
   ```
   cd /homes/user/stud/spring26/cy2822/eecs4340/4340-p4
   git checkout week3      # or week4 — see alternatives below
   ```
   The main worktree now tracks `week3`, which has the clean Makefile (stash-pop markers resolved) and will pick up the docs commit from step 1 if it is cherry-picked.

3. Handle the `pdfs/` deletion. After the checkout in step 2, the working-tree deletion should no longer appear, since `week3` and `week4` do not mark `pdfs/eecs4340project4.pdf` as modified relative to their tips. Verify with `git status`. If the deletion persists, decide:
   - Accept: `git rm pdfs/eecs4340project4.pdf && git commit -m "chore: remove obsolete project PDF (replaced by doc/)"`
   - Restore: `git restore pdfs/eecs4340project4.pdf`
   Recommended: accept the deletion.

4. Verify clean state:
   ```
   cd /homes/user/stud/spring26/cy2822/eecs4340/4340-p4
   git status                    # expect: clean working tree on a named branch
   git branch -vv                # expect: * week3 (or whichever branch was chosen)
   grep -n '<<<<<<<' Makefile    # expect: no output
   ```

### Alternative layouts to consider before executing

- A (recommended): main worktree on `week3`, week4 worktree on `week4`. Docs committed to `week4` and cherry-picked back to `week3` so both branches see them.
- B: main worktree on `week4` (absorbs the new work), delete the separate `week4` worktree after merging. Simpler long-term but loses the worktree separation the user explicitly wanted.
- C: main worktree on `release`, kept as a pristine reference. week3 and week4 worktrees handle all active work. Docs committed to `release`.

Confirm the preferred layout with the user before running step 2.

### Success criteria

- `git status` in the main worktree shows `On branch <named>` (not detached) and `nothing to commit, working tree clean`.
- `grep -n '<<<<<<<' Makefile` returns no output anywhere in any worktree.
- `git worktree list` shows both worktrees attached to named branches.
- `CLAUDE.md`, `doc/week3-merge-report.md`, and `doc/week4-followup-plan.md` are committed and reachable from both `week3` and the main worktree's branch.
- Commit as `chore: reattach main worktree and preserve project docs`.

---

## Execution order

1. Setup: create the `week4` worktree.
2. Task 2 first (`rob_test.sv`). Self-contained, gives fast feedback via `make rob.pass`, and does not touch the code paths involved in Task 1. Finishing it first also leaves a known-good ROB test harness that might help surface Task 1's bug when run alongside the full pipeline.
3. Task 1 second (`mult_no_lsq` debug). The open-ended one. Needs Verdi and iteration.
4. Task 3 last (cleanup). Best done once week4 has real commits to preserve, since it touches the main worktree.

## Verification — end-to-end for all three

After all three tasks are complete, from `../4340-p4-week4`:

```
make simv                              # still compiles
make rob.pass                          # new test passes
make rs.pass                           # existing test still passes
make rob.syn.pass                      # synthesized ROB still passes
make no_hazard.out                     # regression
for i in 1 2 3 4 5 6 7 8 9 10; do
    rm -f output/mult_no_lsq.*
    make mult_no_lsq.out > /dev/null
    echo "run $i: $(wc -l < output/mult_no_lsq.wb) writebacks"
done                                   # expect: all 10 runs identical
git log --oneline week3..week4         # expect: 3+ focused commits
```

And in the main worktree:

```
cd /homes/user/stud/spring26/cy2822/eecs4340/4340-p4
git status                             # clean, attached to a named branch
git branch -vv                          # expect: current branch tracks correctly
```

## Out of scope for this plan

- Pushing any branch to `origin`. Defer until the branches are ready for team review.
- Implementing any of the advanced features from the project proposal (BTB, early tag broadcast, superscalar, etc.). Those come after the pipeline is correct and stable.
- Writing the `test/pipeline_test.sv` debug framework enhancements flagged as P4 TODO in the existing testbench.
- Re-tuning `CLOCK_PERIOD`, `MULT_STAGES`, `ROB_SZ`, or `RS_SZ` for synthesis slack. Separate optimization task.
