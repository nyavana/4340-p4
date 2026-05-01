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

A single `dispatch_fire` signal allocates a ROB slot and either an RS or LSQ slot in the same cycle, so the two structures never disagree about which instructions are in flight. The RAT lives inside the ROB: a 32-entry table that says, for each architectural register r, which ROB slot will produce its next value. Two correctness corners bit us at least once. First, the stale-RAT-clear at commit: when the ROB commits a slot that wrote r, the RAT entry for r is cleared only if it still points at that slot. A younger instruction may have already re-renamed r, and its mapping has to survive; clearing unconditionally would erase a newer producer. Second, the JAL/JALR commit-value override. JAL is the unconditional jump-and-link and JALR is its register-indirect cousin; both write the next-PC (NPC, the address of the instruction after the jump) into a link register so the callee can return. The branch resolver computes the resolved target, which is what travels on the CDB and is the right value for the PC redirect. But for any branch whose destination register is non-zero, the link register has to hold the return address, not the target. So the ROB at commit overrides the broadcast value with NPC for those instructions. We found this the hard way: as soon as programs made function calls, every recursive return came back to the wrong PC because CDB consumers had already latched zero into the link register.

The RS issue selector reads the *registered* `src_ready` bits, not a combinational version that ORs in the current cycle's CDB wakeup. The earlier combinational form looked fine on paper but created a feedback loop. Issue picks an entry. Its tag drives the CDB, which wakes up a different entry whose ready bit was off a moment ago. The selector flips to that entry. The new selection broadcasts a different tag, the previously-woken entry goes back to sleep, and the selector flips back. The simulator sat inside that delta cycle and never advanced. The simulator did not crash; the program just stopped making progress. `mult_no_lsq` froze at cycle 2192 every run, and roughly a dozen other tight-loop programs froze near the same horizon for the same reason. The fix is to use the registered ready bit, which costs one extra cycle when an operand arrives on the same cycle's CDB. The CDB-bypass mux still wires through to the issued entry's *value* output, so correctness holds.

The base design has one CDB with a fixed priority order: MULT first, then an LSQ load, then the ALU. MULT is pipelined and multi-cycle, so once a multiply is in flight its value pops out at a fixed time and asking it to come back later is awkward. ALU operations are one-cycle and replay cheaply, so they sit at the bottom and retry next cycle if they lose. Loads are in between. Stores never use the CDB at all because they have no register value to deliver: when a store finishes its cache handshake, the LSQ raises a one-cycle `store_done` sideband to the ROB, and the store stays parked in the LSQ until the ROB commits it. Branches do broadcast on the CDB, because the resolved target is a value the rest of the machine needs, but the PC redirect happens at commit. That keeps mispredict recovery clean: only one branch is ever oldest in the ROB, so there is exactly one place the redirect can fire.

The LSQ is a first-in first-out (FIFO) queue: loads and stores enter at the tail in dispatch order, only the head talks to the cache, and stores hold their data until commit. Memory operations never enter the RS. The simplicity is deliberate. A one-port head-only LSQ already enforces what the rubric requires, which is that loads and stores retire in program order. Routing memory ops through the RS as well would give two structures overlapping responsibility for memory ordering, and any bug in one would be a bug in both.

The base D-cache is write-back, write-allocate, with byte-granular dirty and valid masks for sub-word stores. RV32IM has byte, half-word, and word load and store variants, so the cache has to track which bytes within a line are valid and which are dirty. Writebacks are always full doublewords; a partial-byte store is absorbed into the cache and only line eviction writes to memory. Write-back over write-through because memory latency is fixed at 100 ns and writing a doubleword on every byte store would dominate runtime. Write-allocate because most stores are followed by reads to the same address.

The base branch predictor is a bimodal direction predictor (a table of 2-bit saturating counters) plus a small BTB that caches taken-branch targets. Both lookups are combinational on the fetch PC, so a predicted-taken hit redirects fetch on the same cycle the PC is read. This is the base predictor the rubric requires and the comparison baseline used in §V.C. The final build replaces the bimodal table with gshare and adds the RAS while keeping the BTB; we keep the bimodal version as the baseline so every speedup claim about gshare and the RAS is measured against the same starting point.

A short RV32 sequence makes the out-of-order story concrete:

```assembly
lw   x10, 0(x5)      # load from memory; latency depends on the cache
addi x11, x12, 1     # independent of the load, ready immediately
add  x13, x10, x11   # depends on the load result in x10
```

An in-order pipeline would freeze the `addi` behind the load even though the `addi`'s sources are already in the register file; our RS dispatches all three, sees the `addi` is ready, and issues it to an ALU while the load is still talking to the D-cache, so the `addi` finishes and broadcasts on the CDB ahead of the load. The dependent `add` waits in the RS for the load's tag and only issues once that tag appears on the CDB.

## V. Advanced Features

TABLE I. Advanced features implemented in this design and how each one maps onto the spec's §4.2 categories.

| # | Feature | Spec category (§4.2) | Tier |
|---|---|---|---|
| 1 | 2-way superscalar | Superscalar execution | difficult |
| 2 | Early tag broadcast | Early tag broadcast (L7) | difficult |
| 3 | gshare predictor | Fetch, sophisticated branch predictors † | simpler |
| 4 | Return Address Stack | Fetch, return address stack | simpler |
| 5 | Store-to-load forwarding | Memory hierarchy, load/store forwarding | simpler |
| 6 | Next-line prefetch (stream buffer) | Memory hierarchy, prefetching † | simpler |
| 7 | 2-way set-associative D-cache | Memory hierarchy, associative caches † | simpler |

We layered seven advanced features on top of the base out-of-order pipeline: two from the difficult tier and five from the simpler tier. The assignment asks for at least one difficult feature alongside other simpler ones, so the count works out. Each of the seven gets its own subsection below, and Table I is the index the reader can use to track which subsection covers which spec category.

The subsections follow the same shape every time. Each one opens with the problem the feature is trying to solve, in plain language that does not assume a hardware background. Then it describes the design we built, the tradeoffs we accepted (area, timing, complexity, or a small loss elsewhere in the pipeline), and finally the result we measured. The two difficult features get dedicated subsections of their own (§V.A for 2-way superscalar and §V.B for early tag broadcast). The five simpler features are grouped under shared parents to keep related design decisions together: branch-prediction enhancements in §V.C, D-cache enhancements in §V.D, and store-to-load forwarding in §V.E. Even when two leaves share a parent, each leaf still gets its own four-part treatment, so the seven-feature count stays clear and the per-feature reasoning never collapses into a single paragraph.

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
