export interface ProgramResult {
  program: string;
  cyclesOoOBase: number;        // OoO base (all 5 ablate-able features off)
  cyclesAllOn: number;          // all 7 features on
  deltaPct: number;             // (allOn - base) / base * 100, signed
  cpiAllOn: number;
  branchAccAllOn: number | null; // null if program has no conditional branches
}

export interface AblationRow {
  feature: string;
  geomeanDeltaPctWhenDisabled: number;
  worstCaseProgram: string;
  worstCaseDeltaPct: number;
  source: 'ablation' | 'analytical';
}

export const PROGRAM_RESULTS: ProgramResult[] = [
  { program: 'alexnet',         cyclesOoOBase: 9_186_436, cyclesAllOn: 4_730_247, deltaPct: -48.51, cpiAllOn: 22.63, branchAccAllOn: 84.74 },
  { program: 'backtrack',       cyclesOoOBase:   250_581, cyclesAllOn:   146_853, deltaPct: -41.40, cpiAllOn: 20.39, branchAccAllOn: 83.74 },
  { program: 'basic_malloc',    cyclesOoOBase:    49_284, cyclesAllOn:    27_798, deltaPct: -43.60, cpiAllOn: 29.45, branchAccAllOn: 56.39 },
  { program: 'bfs',             cyclesOoOBase:   111_376, cyclesAllOn:    66_438, deltaPct: -40.35, cpiAllOn: 19.07, branchAccAllOn: 64.31 },
  { program: 'btest1',          cyclesOoOBase:    17_087, cyclesAllOn:    10_357, deltaPct: -39.39, cpiAllOn: 44.84, branchAccAllOn: 60.00 },
  { program: 'btest2',          cyclesOoOBase:    27_207, cyclesAllOn:    14_013, deltaPct: -48.50, cpiAllOn: 30.66, branchAccAllOn: 33.33 },
  { program: 'copy',            cyclesOoOBase:     3_686, cyclesAllOn:     3_472, deltaPct:  -5.81, cpiAllOn: 26.30, branchAccAllOn: 87.50 },
  { program: 'copy_long',       cyclesOoOBase:     5_773, cyclesAllOn:     5_264, deltaPct:  -8.82, cpiAllOn:  8.89, branchAccAllOn: 88.23 },
  { program: 'dft',             cyclesOoOBase: 1_685_731, cyclesAllOn: 1_008_057, deltaPct: -40.20, cpiAllOn: 17.42, branchAccAllOn: 82.48 },
  { program: 'evens',           cyclesOoOBase:     1_166, cyclesAllOn:     1_170, deltaPct:  +0.34, cpiAllOn: 11.82, branchAccAllOn: 76.74 },
  { program: 'evens_long',      cyclesOoOBase:     2_934, cyclesAllOn:     2_563, deltaPct: -12.65, cpiAllOn:  7.63, branchAccAllOn: 76.74 },
  { program: 'fc_forward',      cyclesOoOBase:    51_721, cyclesAllOn:    33_419, deltaPct: -35.39, cpiAllOn:  4.97, branchAccAllOn: 82.88 },
  { program: 'fib',             cyclesOoOBase:     2_371, cyclesAllOn:     2_048, deltaPct: -13.62, cpiAllOn: 13.65, branchAccAllOn: 86.66 },
  { program: 'fib_long',        cyclesOoOBase:     6_240, cyclesAllOn:     4_940, deltaPct: -20.83, cpiAllOn:  7.74, branchAccAllOn: 85.71 },
  { program: 'fib_rec',         cyclesOoOBase:    32_018, cyclesAllOn:    29_132, deltaPct:  -9.01, cpiAllOn:  2.44, branchAccAllOn: 65.56 },
  { program: 'graph',           cyclesOoOBase:   450_656, cyclesAllOn:   259_337, deltaPct: -42.45, cpiAllOn: 23.31, branchAccAllOn: 59.83 },
  { program: 'haha',            cyclesOoOBase:       935, cyclesAllOn:       528, deltaPct: -43.53, cpiAllOn: 29.33, branchAccAllOn: null  },
  { program: 'halt',            cyclesOoOBase:       106, cyclesAllOn:       106, deltaPct:   0.00, cpiAllOn: 106.0, branchAccAllOn: null  },
  { program: 'insertion',       cyclesOoOBase:     3_093, cyclesAllOn:     3_159, deltaPct:  +2.13, cpiAllOn:  5.27, branchAccAllOn: 87.27 },
  { program: 'insertionsort',   cyclesOoOBase:   750_097, cyclesAllOn:   554_803, deltaPct: -26.04, cpiAllOn:  3.88, branchAccAllOn: 88.46 },
  { program: 'matrix_mult_rec', cyclesOoOBase:   712_425, cyclesAllOn:   662_478, deltaPct:  -7.01, cpiAllOn: 30.56, branchAccAllOn: 94.37 },
  { program: 'mergesort',       cyclesOoOBase:   294_331, cyclesAllOn:   200_073, deltaPct: -32.02, cpiAllOn: 21.10, branchAccAllOn: 75.38 },
  { program: 'mult',            cyclesOoOBase:     7_565, cyclesAllOn:     7_430, deltaPct:  -1.78, cpiAllOn: 22.79, branchAccAllOn: 83.33 },
  { program: 'mult_no_lsq',     cyclesOoOBase:     2_920, cyclesAllOn:     2_251, deltaPct: -22.91, cpiAllOn:  7.95, branchAccAllOn: 88.23 },
  { program: 'no_hazard',       cyclesOoOBase:       725, cyclesAllOn:       422, deltaPct: -41.79, cpiAllOn: 30.14, branchAccAllOn: null  },
  { program: 'omegalul',        cyclesOoOBase:     3_944, cyclesAllOn:     2_220, deltaPct: -43.71, cpiAllOn: 30.00, branchAccAllOn: 33.33 },
  { program: 'outer_product',   cyclesOoOBase: 3_983_006, cyclesAllOn: 3_166_519, deltaPct: -20.50, cpiAllOn:  4.24, branchAccAllOn: 85.18 },
  { program: 'parallel',        cyclesOoOBase:     2_328, cyclesAllOn:     2_135, deltaPct:  -8.29, cpiAllOn: 10.68, branchAccAllOn: 87.50 },
  { program: 'priority_queue',  cyclesOoOBase:    77_416, cyclesAllOn:    43_389, deltaPct: -43.95, cpiAllOn: 29.82, branchAccAllOn: 56.47 },
  { program: 'quicksort',       cyclesOoOBase:   871_758, cyclesAllOn:   568_772, deltaPct: -34.76, cpiAllOn:  5.96, branchAccAllOn: 84.28 },
  { program: 'sampler',         cyclesOoOBase:     6_220, cyclesAllOn:     3_378, deltaPct: -45.69, cpiAllOn: 30.71, branchAccAllOn: 74.35 },
  { program: 'saxpy',           cyclesOoOBase:     4_515, cyclesAllOn:     4_230, deltaPct:  -6.31, cpiAllOn: 22.62, branchAccAllOn: 85.00 },
  { program: 'sort_search',     cyclesOoOBase:   718_427, cyclesAllOn:   600_637, deltaPct: -16.40, cpiAllOn:  3.30, branchAccAllOn: 85.81 },
];

export const SUITE_SUMMARY = {
  programCount: 33,
  geomeanDeltaPct: -27.46,
  arithMeanDeltaPct: -25.54,
  geomeanCpi: 14.87,
  arithMeanCpi: 20.77,
  geomeanBranchAcc: 74.03,
  arithMeanBranchAcc: 76.13,
  branchAccLiftOverBimodalPp: 8.87,
  bimodalArithMeanBranchAcc: 67.25,
};

export const ABLATION: AblationRow[] = [
  { feature: 'Next-line prefetch',     geomeanDeltaPctWhenDisabled: 37.14, worstCaseProgram: 'alexnet',       worstCaseDeltaPct: 94.22, source: 'ablation' },
  { feature: 'STLF',                   geomeanDeltaPctWhenDisabled:  0.20, worstCaseProgram: 'insertionsort', worstCaseDeltaPct:  1.64, source: 'ablation' },
  { feature: 'gshare',                 geomeanDeltaPctWhenDisabled:  0.19, worstCaseProgram: 'fib_rec',       worstCaseDeltaPct:  9.65, source: 'ablation' },
  { feature: 'ETB',                    geomeanDeltaPctWhenDisabled:  0.10, worstCaseProgram: 'outer_product', worstCaseDeltaPct:  1.07, source: 'ablation' },
  { feature: 'RAS',                    geomeanDeltaPctWhenDisabled:  0.10, worstCaseProgram: 'basic_malloc',  worstCaseDeltaPct:  0.52, source: 'ablation' },
  { feature: '2-way superscalar',      geomeanDeltaPctWhenDisabled:   NaN, worstCaseProgram: '—',             worstCaseDeltaPct:   NaN, source: 'analytical' },
  { feature: '2-way set-assoc D-cache', geomeanDeltaPctWhenDisabled:  NaN, worstCaseProgram: '—',             worstCaseDeltaPct:   NaN, source: 'analytical' },
  { feature: 'all 5 disabled',         geomeanDeltaPctWhenDisabled: 37.86, worstCaseProgram: 'alexnet',       worstCaseDeltaPct: 94.21, source: 'ablation' },
];

export const TIMING = {
  clockTargetPs: 1000,
  worstSlackPs: -797.58,
  criticalPath: 'lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]',
  secondWorstSlackPs: -797.55,
  moduleTbsAllPass: true,
};
