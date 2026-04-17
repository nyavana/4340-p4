# **EECS 4340: Computer Hardware Design**

## **Final Project (Project 4\) Proposal**

### **2\. Base Design Details**

*Extending the VeriSimpleV RISC-V pipeline from Project 3 to an out-of-order processor.*

* **Out-of-Order Architecture:** We choose P6-style architecture. We will support out-of-order execution with in-order commit to handle branch mispredictions and exceptions accurately.  
* **Functional Units:** We plan to split the integer ALU into the following multiple functional units to improve cycle time: 2 Simple ALUs (1 cycle), 1 Multiplier (pipelined from P2), 1 Branch Target Unit, 1 Memory Address Unit.  
* **Caches:** Separate Instruction and Data caches (Maximum 256 bytes each, 512 bytes total).  
* **Branch Prediction:** We will implement a Branch Target Buffer (BTB) and a Bimodal Branch Predictor as our base minimum for address and direction prediction.

### **3\. Advanced Features**

*(Targeting 16-18 points total to maximize performance and grade)*

**Difficult Advanced Feature (Aim for 2 and accomplish at least 1):**

* **\[Superscalar execution (2-way)\]:** Expand the pipeline to 2-wide fetch, issue, execute, and retire, allowing up to two independent instructions to progress per cycle while preserving in-order commit.  
* **\[Early tag broadcast\]:** Implement early tag broadcast by sending destination tags to the wakeup logic as soon as execution units determine the result is ready. 

**Simpler Advanced Features:**

* **\[More sophisticated branch predictors\]:** This will improve performance on complex loops and conditional branches where the base bimodal predictor lacks sufficient context.  
* **\[Instruction and/or data prefetching\]:** By fetching subsequent blocks into a buffer before they are explicitly requested, we aim to reduce latency of the base memory.  
* **\[Associative caches\]:** We plan to upgrade the required separate instruction and data caches from simple direct-mapped structures to set-associative designs.

### **4\. Milestone Schedule**

* **Milestone 1 (Due March 11):** We will implement and test individual modules from each member. This will include all working modules, comprehensive testbench, and successful output in both simulation and synthesis from them.  
* **Milestone 2 (Due March 25):** Integration of basic components into a functional pipeline. Most non-memory operations will correctly fetch, decode, execute, and commit.  
* **Milestone 3 (Due April 8):** Memory operations functional. Project working in simulation for \~75% of test programs and largely synthesizable.  
* **Final Code (Due April 22):** Complete, synthesizable Verilog code submitted via Courseworks.  
* **Final Report (Due May 4):** 10-20 page report outlining design, testing, and performance analysis (CPI/Clock period).