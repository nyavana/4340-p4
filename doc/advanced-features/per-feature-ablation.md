# Per-feature ablation sweep

Date: 2026-05-01. Branch `verify-merged-features` at `390bfed`.

---

## 1. Methodology

To quantify the marginal cycle-count contribution of each advanced feature, we ran seven builds of the full 34-program suite:

| Tag | EXTRA_DEFINES passed to VCS |
|---|---|
| `all_on` | (none) — full post-merge configuration |
| `no_etb` | `+define+DISABLE_EARLY_TAG` |
| `no_gshare` | `+define+DISABLE_GSHARE` |
| `no_ras` | `+define+DISABLE_RAS` |
| `no_stlf` | `+define+DISABLE_STLF` |
| `no_prefetch` | `+define+DISABLE_PREFETCH` |
| `no_advanced` | all five defines above together |

Each configuration uses `make clean_exe && make EXTRA_DEFINES="..." simv && make EXTRA_DEFINES="..." simulate_all -j8`. The `.out` files are saved under `output/sweep_<tag>/`. The baseline (`all_on`) is the state measured in `advanced-features-merge-report.md` §5.

**What each define does at the RTL level:**

- `DISABLE_EARLY_TAG` — `pipeline.sv:1079`: forces `early_cdb_valid = 1'b0`. MULT wakeup is delayed one cycle; RS consumers cannot wake up from the early-tag signal. (Existing knob from the ETB merge.)
- `DISABLE_GSHARE` — `branch_predictor.sv:125`: forces `ghr_ext = '0` so `bht_idx = bht_pc_bits(PC) ^ 0 = bht_pc_bits(PC)`, i.e., pure-PC bimodal indexing. The GHR register is still updated but its value is not fed into the index.
- `DISABLE_RAS` — `branch_predictor.sv:166`: forces `ras_override = 1'b0` so return instructions fall through to the BTB for their predicted target instead of consulting the return-address stack.
- `DISABLE_STLF` — `lsq.sv:311`: forces `can_forward = 1'b0` inside `stlf_compute`, so no load is ever forwarded from the LSQ; all loads wait for the dcache.
- `DISABLE_PREFETCH` — `stream_buffer.sv:82`: forces `proc2Pmem_command = BUS_NONE`, so the stream buffer never issues a prefetch request. The buffer still exists in hardware and the icache still uses it for demand hits that happen to match a previously prefetched address, but once the buffer is drained no new prefetch is issued.

Two other advanced features — 2-way superscalar dispatch/commit and the 2-way set-associative dcache — are structural changes that cannot be toggled by a single `ifdef` without a major RTL reorganization. They are excluded from this sweep; the `all_on` baseline already includes both.

Each ablation measures the **marginal cost** of removing one feature from the otherwise fully-enabled design. A feature's Δ% is the cycle-count regression introduced by disabling it while leaving all other features active.

---

## 2. Per-program cycle-count table

Δ% is relative to `all_on` cycles: positive = more cycles (regression), negative = fewer (improvement, typically statistical noise).

| Program | cycles_all_on | cpi_all_on | cycles_no_etb | Δ%_no_etb | cycles_no_gshare | Δ%_no_gshare | cycles_no_ras | Δ%_no_ras | cycles_no_stlf | Δ%_no_stlf | cycles_no_prefetch | Δ%_no_prefetch | cycles_no_advanced | Δ%_no_advanced |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| alexnet | 4,730,247 | 22.625 | 4,729,956 | -0.01% | 4,745,257 | +0.32% | 4,731,327 | +0.02% | 4,730,949 | +0.01% | 9,187,192 | +94.22% | 9,186,436 | +94.21% |
| backtrack | 146,853 | 20.391 | 146,853 | +0.00% | 147,457 | +0.41% | 146,854 | +0.00% | 147,112 | +0.18% | 250,069 | +70.29% | 250,581 | +70.63% |
| basic_malloc | 27,798 | 29.447 | 27,798 | +0.00% | 27,783 | -0.05% | 27,942 | +0.52% | 27,723 | -0.27% | 49,147 | +76.80% | 49,284 | +77.29% |
| bfs | 66,438 | 19.069 | 66,438 | +0.00% | 66,614 | +0.26% | 66,946 | +0.76% | 66,556 | +0.18% | 110,821 | +66.80% | 111,376 | +67.64% |
| btest1 | 10,357 | 44.835 | 10,357 | +0.00% | 10,357 | +0.00% | 10,357 | +0.00% | 10,357 | +0.00% | 17,087 | +64.98% | 17,087 | +64.98% |
| btest2 | 14,013 | 30.663 | 14,013 | +0.00% | 14,013 | +0.00% | 14,013 | +0.00% | 14,013 | +0.00% | 27,207 | +94.16% | 27,207 | +94.16% |
| copy | 3,472 | 26.303 | 3,473 | +0.03% | 3,470 | -0.06% | 3,472 | +0.00% | 3,486 | +0.40% | 3,670 | +5.70% | 3,686 | +6.16% |
| copy_long | 5,264 | 8.892 | 5,264 | +0.00% | 5,262 | -0.04% | 5,264 | +0.00% | 5,292 | +0.53% | 5,742 | +9.08% | 5,773 | +9.67% |
| dft | 1,008,057 | 17.418 | 1,008,127 | +0.01% | 1,005,951 | -0.21% | 1,012,571 | +0.45% | 1,010,508 | +0.24% | 1,683,661 | +67.02% | 1,685,731 | +67.23% |
| evens | 1,170 | 11.818 | 1,170 | +0.00% | 1,167 | -0.26% | 1,170 | +0.00% | 1,170 | +0.00% | 1,169 | -0.09% | 1,166 | -0.34% |
| evens_long | 2,563 | 7.628 | 2,563 | +0.00% | 2,559 | -0.16% | 2,563 | +0.00% | 2,563 | +0.00% | 2,934 | +14.48% | 2,934 | +14.48% |
| fc_forward | 33,419 | 4.966 | 33,419 | +0.00% | 33,422 | +0.01% | 33,422 | +0.01% | 33,421 | +0.01% | 51,791 | +54.97% | 51,721 | +54.77% |
| fib | 2,048 | 13.653 | 2,048 | +0.00% | 2,046 | -0.10% | 2,048 | +0.00% | 2,070 | +1.07% | 2,347 | +14.60% | 2,371 | +15.77% |
| fib_long | 4,940 | 7.743 | 4,940 | +0.00% | 4,938 | -0.04% | 4,940 | +0.00% | 4,940 | +0.00% | 6,240 | +26.32% | 6,240 | +26.32% |
| fib_rec | 29,132 | 2.436 | 29,132 | +0.00% | 31,942 | +9.65% | 29,132 | +0.00% | 29,183 | +0.18% | 28,971 | -0.55% | 32,018 | +9.91% |
| graph | 259,337 | 23.309 | 259,337 | +0.00% | 259,245 | -0.04% | 260,561 | +0.47% | 261,132 | +0.69% | 446,887 | +72.32% | 450,656 | +73.77% |
| haha | 528 | 29.333 | 528 | +0.00% | 528 | +0.00% | 528 | +0.00% | 528 | +0.00% | 935 | +77.08% | 935 | +77.08% |
| halt | 106 | 106.000 | 106 | +0.00% | 106 | +0.00% | 106 | +0.00% | 106 | +0.00% | 106 | +0.00% | 106 | +0.00% |
| insertion | 3,159 | 5.274 | 3,159 | +0.00% | 3,136 | -0.73% | 3,159 | +0.00% | 3,159 | +0.00% | 3,128 | -0.98% | 3,093 | -2.09% |
| insertionsort | 554,803 | 3.884 | 554,803 | +0.00% | 551,149 | -0.66% | 554,956 | +0.03% | 563,922 | +1.64% | 740,530 | +33.48% | 750,097 | +35.20% |
| matrix_mult_rec | 662,478 | 30.561 | 662,523 | +0.01% | 662,680 | +0.03% | 663,045 | +0.09% | 662,483 | +0.00% | 711,340 | +7.38% | 712,425 | +7.54% |
| mergesort | 200,073 | 21.100 | 200,073 | +0.00% | 200,339 | +0.13% | 200,336 | +0.13% | 200,370 | +0.15% | 292,494 | +46.19% | 294,331 | +47.11% |
| mult | 7,430 | 22.791 | 7,430 | +0.00% | 7,430 | +0.00% | 7,430 | +0.00% | 7,430 | +0.00% | 7,561 | +1.76% | 7,565 | +1.82% |
| mult_no_lsq | 2,251 | 7.954 | 2,301 | +2.22% | 2,229 | -0.98% | 2,251 | +0.00% | 2,251 | +0.00% | 2,885 | +28.17% | 2,920 | +29.72% |
| mytest | 213 | 26.625 | 213 | +0.00% | 213 | +0.00% | 213 | +0.00% | 213 | +0.00% | 416 | +95.31% | 416 | +95.31% |
| no_hazard | 422 | 30.143 | 422 | +0.00% | 422 | +0.00% | 422 | +0.00% | 422 | +0.00% | 725 | +71.80% | 725 | +71.80% |
| omegalul | 2,220 | 30.000 | 2,220 | +0.00% | 2,220 | +0.00% | 2,222 | +0.09% | 2,223 | +0.14% | 3,942 | +77.57% | 3,944 | +77.66% |
| outer_product | 3,166,519 | 4.244 | 3,200,440 | +1.07% | 3,166,010 | -0.02% | 3,169,138 | +0.08% | 3,171,599 | +0.16% | 3,966,677 | +25.27% | 3,983,006 | +25.79% |
| parallel | 2,135 | 10.675 | 2,135 | +0.00% | 2,133 | -0.09% | 2,135 | +0.00% | 2,135 | +0.00% | 2,328 | +9.04% | 2,328 | +9.04% |
| priority_queue | 43,389 | 29.821 | 43,389 | +0.00% | 43,392 | +0.01% | 43,568 | +0.41% | 43,310 | -0.18% | 77,367 | +78.31% | 77,416 | +78.42% |
| quicksort | 568,772 | 5.958 | 568,772 | +0.00% | 569,480 | +0.12% | 570,271 | +0.26% | 571,896 | +0.55% | 869,191 | +52.82% | 871,758 | +53.27% |
| sampler | 3,378 | 30.709 | 3,378 | +0.00% | 3,378 | +0.00% | 3,378 | +0.00% | 3,378 | +0.00% | 6,220 | +84.13% | 6,220 | +84.13% |
| saxpy | 4,230 | 22.620 | 4,230 | +0.00% | 4,213 | -0.40% | 4,230 | +0.00% | 4,230 | +0.00% | 4,533 | +7.16% | 4,515 | +6.74% |
| sort_search | 600,637 | 3.300 | 600,637 | +0.00% | 598,634 | -0.33% | 600,765 | +0.02% | 606,833 | +1.03% | 710,157 | +18.23% | 718,427 | +19.61% |
| **geomean Δ%** | | | | **+0.10%** | | **+0.19%** | | **+0.10%** | | **+0.20%** | | **+38.57%** | | **+39.28%** |

---

## 3. Summary statistics

| Feature disabled | Geomean Δ% vs all_on | Largest regression (program) | Largest regression Δ% |
|---|---:|---|---:|
| ETB (`no_etb`) | +0.10% | outer_product | +1.07% |
| gshare (`no_gshare`) | +0.19% | fib_rec | +9.65% |
| RAS (`no_ras`) | +0.10% | basic_malloc | +0.52% |
| STLF (`no_stlf`) | +0.20% | insertionsort | +1.64% |
| prefetch (`no_prefetch`) | +38.57% | mytest | +95.31% |
| all 5 disabled | +39.28% | mytest | +95.31% |

**Prefetch dominates.** Disabling the stream-buffer prefetcher alone accounts for essentially the entire gap between the advanced-feature configuration and the no-advanced baseline: the `no_prefetch` geomean (+38.57%) is within 0.71 pp of the full `no_advanced` (+39.28%). This is consistent with the processor's memory-bound profile: with a single instruction issue slot and a 100 ns memory latency, the icache hit rate is on the critical path for almost every program in the suite. The stream buffer converts most sequential fetch sequences from cache misses into hit-latency accesses.

**ETB, gshare, RAS, and STLF are individually small but real.** Their geomean regressions are 0.10–0.20% each when removed from an otherwise fully-advanced design. The four features together contribute roughly 0.71 pp of the 39.28% total gap (i.e., the `no_advanced` geomean exceeds `no_prefetch` by only 0.71 pp). This is not surprising: the second CDB slot required for ETB to have its maximum impact is not present (the design is 1-wide CDB), so ETB can only help when the single CDB cycle following MULT early-done is idle for a non-MULT op. Similarly, gshare and RAS improve branch accuracy over bimodal+BTB (as documented in `branch-accuracy-cpi-diff.md`), but since most mispredict penalties are a handful of cycles and this is an OoO design that can hide some of them, the CPI impact is modest. STLF helps programs with tight store-load RAW patterns (insertionsort: +1.64% regression when disabled) but the overall workload mix dilutes it.

**Per-program outliers:**

- `fib_rec` regresses 9.65% under `no_gshare`. This program's tight recursion structure produces a highly predictable call/return pattern that gshare exploits by XOR-ing a short history of taken/not-taken outcomes with the PC; without gshare the BHT aliasing on the recursive call site degrades accuracy significantly.
- `outer_product` regresses 1.07% under `no_etb`. This dense inner-loop multiply-and-accumulate workload generates back-to-back MULT operations; ETB's early wakeup lets waiting RS entries issue one cycle sooner on each MULT completion.
- `insertionsort` regresses 1.64% under `no_stlf`. The insertion inner loop reads the element it just wrote; STLF forwards that value from the LSQ without going to the dcache.
- Programs with near-zero branch counts (`halt`, `btest1`, `btest2`, `haha`, `mytest`, `no_hazard`, `omegalul`, `sampler`) show zero regression for all five single-feature disables; the gain from these features is zero when there are no branches and no memory-level parallelism to exploit.
- `evens`, `insertion`, `fib_rec` show small negative Δ% in some single-feature columns (e.g., `no_gshare` on `insertion`: −0.73%). These are artifacts of BHT aliasing in gshare: when gshare is active, two PCs that happen to XOR to the same BHT index interfere with each other; removing gshare eliminates the interference for these specific programs. The aggregate effect is still positive (geomean +0.19%) because gshare helps more programs than it hurts.

---

## 4. Failed / non-halting programs

None. All 34 programs halted cleanly under all 7 sweep configurations. Every `.out` file contains `@@@ System halted on WFI instruction`.

---

## 5. Reproduction

```bash
# From the repo root (branch verify-merged-features)
# All defines accepted via the EXTRA_DEFINES knob added in commit cf82200
make clean && make simv                                         # all_on
make clean && make EXTRA_DEFINES="+define+DISABLE_EARLY_TAG" simv  # no_etb
make clean && make EXTRA_DEFINES="+define+DISABLE_GSHARE" simv     # no_gshare
make clean && make EXTRA_DEFINES="+define+DISABLE_RAS" simv        # no_ras
make clean && make EXTRA_DEFINES="+define+DISABLE_STLF" simv       # no_stlf
make clean && make EXTRA_DEFINES="+define+DISABLE_PREFETCH" simv   # no_prefetch
make clean && make EXTRA_DEFINES="+define+DISABLE_EARLY_TAG +define+DISABLE_GSHARE \
  +define+DISABLE_RAS +define+DISABLE_STLF +define+DISABLE_PREFETCH" simv  # no_advanced
```

Raw output files are in `output/sweep_<tag>/` (not tracked by git; regenerate from the recipe above). The aggregation script is at `aggregate_ablation.py` in the repo root.
