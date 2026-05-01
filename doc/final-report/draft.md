# Out-of-Order RISC-V Processor — Final Project Report

EECS 4340, Spring 2026.

## Abstract

[ABSTRACT — drafted last, after §VII headline numbers are final.]

## I. Introduction

This processor runs RV32IM RISC-V binaries, the same RV32IM subset (the 32-bit base integer ISA plus the M extension for multiply and divide) that the Project 3 in-order pipeline ran. The new part is what happens between fetch and writeback. Instructions can issue and execute out of program order, then commit back in order. In an in-order pipeline, one stalled load freezes every instruction behind it, even instructions that have nothing to do with the load's address or its result. Out-of-order execution lets independent work continue while a slow operation finishes, which is the whole point of the design.

The course-supplied starter is an in-order pipeline with a few pieces we kept: a pipelined multiplier from Project 2, an instruction cache, a register file, and a decoder. Everything that makes the design out-of-order is ours. We added a Reorder Buffer (ROB) that holds in-flight instructions and commits them in program order, a Reservation Station (RS) that holds dispatched instructions until their operands are ready, an embedded Register Alias Table (RAT) that handles renaming directly inside the ROB, a Load-Store Queue (LSQ) that orders memory operations, a write-back data cache, and a branch predictor with a Branch Target Buffer (BTB). The Common Data Bus (CDB) ties execution back to the ROB and the waiting consumers. On top of the base design we layered seven advanced features: 2-way superscalar fetch and commit, early tag broadcast on the multiplier, a gshare direction predictor, a Return Address Stack (RAS), store-to-load forwarding, a next-line prefetcher, and a 2-way set-associative data cache.

The work landed in three milestones. Milestone 1 produced the ROB and RS modules in parallel branches and stitched them into a P6-style top-level pipeline. Milestone 2 stabilized the integration and got non-memory operations running end to end. Milestone 3 added the LSQ and write-back data cache, which brought every RV32IM load and store variant online. After Milestone 3 we turned to performance: a bimodal branch predictor went in first, then the seven advanced features were merged one branch at a time.

The rest of the report is organized so the architecture comes before the features and the numbers come after both. Section III walks through the pipeline with a top-level block diagram and a paragraph per stage. Section V covers the seven advanced features one at a time, each with the problem it solves, the design we picked, the tradeoffs, and the measured result. Section VII carries the cycle counts, the per-feature speedups, the branch-prediction accuracy data, and the synthesis slack numbers, including the one critical path that still misses the 1000 ps clock.

## II. Background and Constraints

In an in-order pipeline, instructions execute in the same order the program lists them. That is simple to reason about and simple to build, but it has a familiar weakness. Suppose a load misses the cache and stalls for the full memory latency, and the very next instruction is an add that does not touch the load's destination register. The add has nothing to wait for, but the in-order pipeline makes it wait anyway, because the load is in front of it.

Out-of-order execution lets the add issue and complete while the load is still in flight. The pipeline tracks operand readiness instead of program position, so independent work runs whenever its inputs are available. The catch is that results now come back in a different order than the program wrote them, and the architectural state has to look as if everything still happened in program order. That is what the Reorder Buffer is for: it holds in-flight results and retires them at the head, in order, so the register file and memory only see the program-order view. Three classical hazards drive most of the design choices: Read-After-Write (RAW), Write-After-Read (WAR), and Write-After-Write (WAW). Renaming handles WAR and WAW by giving each instruction a fresh destination tag; the Reservation Station and CDB handle RAW by waking instructions up the moment their producers broadcast.

The ROB is the in-order checkpoint of the machine: it holds every dispatched instruction until commit and is what makes the architectural state look in-order. The RS is where a dispatched instruction waits for its operands and then hands itself to a functional unit once they arrive. The CDB is the shared wire that carries each completed result back to the ROB and to any waiting consumers. The LSQ is the memory-side equivalent of the ROB: it tracks loads and stores in program order and is the only path to the data cache. The branch predictor guesses the direction and target of each branch at fetch so the front end keeps moving instead of waiting for the branch to resolve at the far end of the pipeline.

Several numbers in this design were fixed by the assignment, not chosen by us. Main memory has a 100 ns access latency. The instruction cache and the data cache are each capped at 256 bytes. The number of Common Data Buses cannot exceed the narrowest stage of the pipeline, so a one-wide pipeline is allowed at most one CDB and a two-wide pipeline at most two. The multiplier is the pipelined unit inherited from Project 2. We mention these here because they shape every later trade-off, and a reader who did not know they were spec-imposed would otherwise read them as bad calls on our part.

## III. Pipeline Architecture

[FIGURE 1: Top-level pipeline block diagram. Stages + buses + the few sideband signals (early-tag, store_done).]

[TODO §III — drafted in Task 4.]

## IV. Base Implementation Details

[TODO §IV — drafted in Task 5. Inline OoO-issue demonstration code snippet at the end.]

## V. Advanced Features

[TABLE I: Spec-compliance feature mapping — 7 rows.]

[TODO §V opener — drafted in Task 6.]

### V.A. 2-way Superscalar

[TODO §V.A — drafted in Task 7.]

### V.B. Early Tag Broadcast

[FIGURE 5: Early-tag-broadcast timing.]

[TODO §V.B — drafted in Task 8.]

### V.C. Branch-Prediction Enhancements

[FIGURE 2: gshare + RAS branch predictor.]

[TODO §V.C — drafted in Task 9. Two leaves: gshare and RAS.]

### V.D. D-cache Enhancements

[FIGURE 3: D-cache organization.]

[TODO §V.D — drafted in Task 10. Two leaves: 2-way set-associative D-cache and next-line prefetch.]

### V.E. Store-to-Load Forwarding

[FIGURE 4: Store-to-load forwarding lanes.]

[TODO §V.E — drafted in Task 11.]

## VI. Verification and Testing Methodology

[TODO §VI — drafted in Task 12.]

## VII. Performance Evaluation and Analysis

[TABLE II: Per-program performance, representative subset.]

[TABLE III: Per-program performance, full 34-row continuation.]

[TABLE IV: Per-feature attribution.]

[TABLE V: Per-module synthesis slack.]

[TODO §VII — drafted in Task 13.]

## VIII. Discussion: Limitations and Future Work

[TODO §VIII — drafted in Task 14.]

## IX. Conclusion

[TODO §IX — drafted in Task 15.]

## References

[TODO references — drafted in Task 15.]
