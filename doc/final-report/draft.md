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

Figure 1 traces a single instruction from one end of the machine to the other. Fetch reads the PC, looks up the I-cache, and asks the branch predictor in parallel whether this PC is a taken branch the predictor already knows about. Decode turns the raw 32-bit instruction word into the fields the rest of the pipeline expects. Dispatch allocates a ROB slot for every instruction, and either an RS slot or an LSQ slot depending on whether the instruction touches memory. Issue picks ready instructions out of the RS and hands them to a functional unit; the LSQ head, separately, talks to the D-cache when its turn comes. Execute happens on two ALUs, one pipelined multiplier, one inline branch resolver, and one D-cache port. Results travel back on the CDB, which wakes up waiting consumers in the RS and writes the value into the right ROB entry. Commit retires the ROB head in program order, writes the architectural register file, and runs the mispredict check that compares the resolved branch outcome against what the predictor guessed at fetch.

Fetch is two-wide on the front end. The PC drives the I-cache, and on a hit the cache returns a line wide enough to hand back two instructions in a single cycle. The branch predictor reads the same PC in parallel and may redirect fetch on the same cycle if it sees a taken branch or a return. Two structures help here. The BTB caches the targets of taken branches the program has executed before, so a predicted-taken conditional or a predicted JAL goes to the right place without waiting for the branch unit far downstream. The RAS handles function returns, where the target depends on which call site invoked the function rather than on the return instruction itself. A generic indirect-branch predictor would have to relearn the right target every time control passed through a different call site; the RAS sidesteps that by pushing the link address on every JAL that writes the link register and popping it on the matching return. Returns are nearly always predictable this way, so a small structure earns its keep.

Decode is reused largely unchanged from the in-order Project 3 pipeline. It reads the raw instruction word and produces the operand selects, the ALU function code, and the small set of flags (memory access, conditional branch, unconditional branch, halt, illegal) that the dispatch stage needs to route the instruction correctly. Reusing the decoder kept the renaming, dispatch, and ROB logic the focus of the design effort, since those are the parts an out-of-order pipeline actually changes.

Dispatch is where the most distinctive design choice in the project lives. Most P6-style pipelines keep a separate map table from architectural register to physical register, alongside a separate physical register file. We do not. The ROB doubles as the physical register file, and the RAT lives inside the ROB itself. Each ROB slot holds the in-flight result of one instruction, and the RAT is a 32-entry table that maps each architectural register to whichever ROB slot will produce its next value. Dispatch allocates a ROB slot, writes the new mapping into the RAT (except for x0, which is never tracked), and either inserts the instruction into the RS or hands it to the LSQ. We picked this shape because the ROB already has the right lifetime for an in-flight result: an entry is allocated at dispatch and freed at commit, which is exactly when a physical register would need to come and go. Folding the two structures together means one less thing to maintain and verify, and the renaming logic at dispatch is simpler because the ROB tail is the new physical register tag with no free list to manage. Memory operations skip the RS entirely and go straight into the LSQ, because the LSQ already enforces program order between loads and stores; routing memory ops through the RS would only add a structure for them to sit in.

Issue and execute are where the out-of-order shape pays for itself. The RS scans its entries each cycle and picks the oldest one whose two source operands are both ready, then hands it to a functional unit. The two ALUs handle the simple integer operations in one cycle each. The multiplier is pipelined with a fixed latency, so a long multiply does not stall the rest of the pipeline once it enters the unit. Conditional branches resolve in their own inline unit next to the ALUs; the same unit also produces the target for JAL and JALR. Loads and stores live on the LSQ side: only the head of the LSQ talks to the D-cache, which keeps memory ordering simple. Every value-producing result travels back on the CDB, which wakes up RS entries waiting on that tag and writes the value into the ROB. Stores are the one exception. A store does not produce a register value, so it has nothing to broadcast; it signals completion to the ROB through a sideband (`store_done`) instead, which keeps the CDB free for instructions that actually have a result to deliver. Branches do broadcast on the CDB, because their resolved target is the value other parts of the machine need, but the actual PC redirect happens at commit and not at execute.

Commit is what makes the architectural state look in-order even though execution was not. The ROB head retires once it is busy and ready, writes its value into the architectural register file, and then runs the mispredict check on any branch that is committing. If the resolved direction or target does not match what the predictor said at fetch, the ROB raises a single-cycle redirect signal that flushes the RS, flushes the LSQ, kills any multiply still in flight, and steers the PC to the correct target on the next cycle. In-order commit is what lets the machine speculate aggressively in the front end and still recover cleanly when the speculation turns out to be wrong. Without it, a mispredicted branch would leave the register file in some partially-updated state that does not correspond to any valid program point.

The team chose the P6 style, with the RAT embedded in the ROB and the ROB doubling as the physical register file, over the R10K style, which keeps a separate map table, a separate free list, and a unified physical register pool larger than the architectural register count. R10K makes more sense once a machine widens out and the unified pool starts to pay for itself, because instructions can rename freely without being bottlenecked by ROB allocation. At a one-wide base, though, the R10K bookkeeping costs more than it returns: a separate map table to read and write every cycle, a free list to keep consistent with allocation and reclaim, and a register pool with its own sizing and freeing policy. The advanced features we planned (superscalar, early tag broadcast, branch-prediction enhancements, store-to-load forwarding, and cache improvements) do not need the unified pool to work, so the simpler P6 shape gave us the same correctness guarantees with less hardware to build and less RTL to verify. The tradeoff would tilt the other way past two-wide, but at the width we settled on, P6 was the cleaner fit.

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
