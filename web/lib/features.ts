export type FeatureTier = 'difficult' | 'simpler';

export interface AdvancedFeature {
  id: string;                       // 'superscalar', 'etb', 'gshare', 'ras', 'stlf', 'prefetch', 'set-associative'
  name: string;
  tier: FeatureTier;
  oneLiner: string;                 // <= 90 chars; for landing-page pill
  hostModuleIds: string[];          // architecture.ts module ids the feature lives in
  marginalDeltaPctWhenDisabled: number | null;  // null for analytical (structural)
  worstCaseProgram: string | null;
  worstCaseDeltaPct: number | null;
  deepDiveAnchor: string;           // '#superscalar' etc., used for /deep-dive#anchor links
}

export const FEATURES: AdvancedFeature[] = [
  {
    id: 'superscalar',
    name: '2-way Superscalar',
    tier: 'difficult',
    oneLiner: 'Two-wide fetch, decode, dispatch, and commit. Doubles the IPC ceiling.',
    hostModuleIds: ['fetch', 'decode', 'rob', 'rs', 'cdb', 'commit'],
    marginalDeltaPctWhenDisabled: null,
    worstCaseProgram: null,
    worstCaseDeltaPct: null,
    deepDiveAnchor: '#superscalar',
  },
  {
    id: 'etb',
    name: 'Early Tag Broadcast',
    tier: 'difficult',
    oneLiner: 'MULT wakes its dependents one cycle before the result lands on the CDB.',
    hostModuleIds: ['mult', 'rs'],
    marginalDeltaPctWhenDisabled: 0.10,
    worstCaseProgram: 'outer_product',
    worstCaseDeltaPct: 1.07,
    deepDiveAnchor: '#etb',
  },
  {
    id: 'gshare',
    name: 'gshare Predictor',
    tier: 'simpler',
    oneLiner: 'XOR-folded global history with PC bits to specialize on hot branches.',
    hostModuleIds: ['branch-predictor'],
    marginalDeltaPctWhenDisabled: 0.19,
    worstCaseProgram: 'fib_rec',
    worstCaseDeltaPct: 9.65,
    deepDiveAnchor: '#gshare',
  },
  {
    id: 'ras',
    name: 'Return Address Stack',
    tier: 'simpler',
    oneLiner: '16-entry hardware stack. Returns predicted by where they were called.',
    hostModuleIds: ['branch-predictor'],
    marginalDeltaPctWhenDisabled: 0.10,
    worstCaseProgram: 'basic_malloc',
    worstCaseDeltaPct: 0.52,
    deepDiveAnchor: '#ras',
  },
  {
    id: 'stlf',
    name: 'Store-to-Load Forwarding',
    tier: 'simpler',
    oneLiner: 'A load behind a fully-covering older store completes from the LSQ.',
    hostModuleIds: ['lsq'],
    marginalDeltaPctWhenDisabled: 0.20,
    worstCaseProgram: 'insertionsort',
    worstCaseDeltaPct: 1.64,
    deepDiveAnchor: '#stlf',
  },
  {
    id: 'prefetch',
    name: 'Next-line Prefetch',
    tier: 'simpler',
    oneLiner: 'One-line stream buffer fetches line N+1 in parallel on a miss for line N.',
    hostModuleIds: ['icache', 'dcache'],
    marginalDeltaPctWhenDisabled: 37.14,
    worstCaseProgram: 'alexnet',
    worstCaseDeltaPct: 94.22,
    deepDiveAnchor: '#prefetch',
  },
  {
    id: 'set-associative',
    name: '2-way Set-Associative D-Cache',
    tier: 'simpler',
    oneLiner: '16 sets × 2 ways with 1-bit LRU. Resolves direct-mapped conflict misses.',
    hostModuleIds: ['dcache'],
    marginalDeltaPctWhenDisabled: null,
    worstCaseProgram: null,
    worstCaseDeltaPct: null,
    deepDiveAnchor: '#set-associative',
  },
];
