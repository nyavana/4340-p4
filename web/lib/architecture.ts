/** A box on the landing-page architecture diagram. */
export interface PipelineModule {
  id: string;                     // unique stable id; used in URLs and as React key
  name: string;                   // display name in the box
  category: 'frontend' | 'backend' | 'memory' | 'control';
  description: string;            // 1-paragraph summary in the side panel
  parameters: { key: string; value: string }[];
  files: { path: string; githubUrl: string }[];
  advancedFeatures: string[];     // ids from features.ts
}

const REPO = 'https://github.com/CSEE4340-26/p4.GaPiChiXuXu';
const blob = (path: string) => `${REPO}/blob/release/${path}`;

export const MODULES: PipelineModule[] = [
  {
    id: 'fetch',
    name: 'Fetch (2-wide)',
    category: 'frontend',
    description:
      'Two-wide instruction fetch reading the I-cache. The PC drives both the cache and the branch predictor in parallel; on a predicted-taken hit, fetch redirects on the same cycle.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'icache',
    name: 'I-Cache',
    category: 'memory',
    description:
      '256-byte instruction cache returning an 8-byte line per hit (carries two instructions). Paired with a one-line stream-buffer prefetcher.',
    parameters: [{ key: 'capacity', value: '256 B' }, { key: 'line size', value: '8 B' }],
    files: [
      { path: 'verilog/icache.sv', githubUrl: blob('verilog/icache.sv') },
      { path: 'verilog/stream_buffer.sv', githubUrl: blob('verilog/stream_buffer.sv') },
    ],
    advancedFeatures: ['prefetch'],
  },
  {
    id: 'branch-predictor',
    name: 'Branch Predictor',
    category: 'frontend',
    description:
      'Combinational lookup at fetch: a 32-entry direct-mapped BTB, a 64-entry gshare direction predictor, and a 16-entry RAS for returns. Updates fire once per committing branch.',
    parameters: [
      { key: 'BTB entries', value: '32' },
      { key: 'BHT entries', value: '64' },
      { key: 'RAS depth', value: '16' },
    ],
    files: [{ path: 'verilog/branch_predictor.sv', githubUrl: blob('verilog/branch_predictor.sv') }],
    advancedFeatures: ['gshare', 'ras'],
  },
  {
    id: 'decode',
    name: 'Decode (2-wide)',
    category: 'frontend',
    description:
      'Two parallel decoders working on the two halves of a fetched line. Reused largely unchanged from the in-order Project 3 pipeline.',
    parameters: [],
    files: [{ path: 'verilog/decoder.sv', githubUrl: blob('verilog/decoder.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'rob',
    name: 'ROB + RAT',
    category: 'control',
    description:
      'Reorder Buffer doubles as the physical register file and embeds the 32-entry RAT inside it. Allocates and commits two slots per cycle. The stale-clear protection at commit prevents a younger producer from being erased.',
    parameters: [{ key: 'ROB_SZ', value: '16' }],
    files: [{ path: 'verilog/rob.sv', githubUrl: blob('verilog/rob.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'rs',
    name: 'Reservation Station',
    category: 'control',
    description:
      'Holds dispatched instructions until their two source operands are ready, then issues to a functional unit. The selector reads registered ready bits only — a combinational read created a feedback loop that froze the simulator on tight loops.',
    parameters: [{ key: 'RS_SZ', value: '16' }],
    files: [{ path: 'verilog/rs.sv', githubUrl: blob('verilog/rs.sv') }],
    advancedFeatures: ['superscalar', 'etb'],
  },
  {
    id: 'lsq',
    name: 'Load-Store Queue',
    category: 'memory',
    description:
      'FIFO of 8 entries. Memory ops bypass the RS at dispatch and allocate directly. Only the head talks to the cache. Stores hold (addr, data, mem_size) until commit; loads check older stores for STLF before going to cache.',
    parameters: [{ key: 'LSQ_SZ', value: '8' }],
    files: [{ path: 'verilog/lsq.sv', githubUrl: blob('verilog/lsq.sv') }],
    advancedFeatures: ['stlf'],
  },
  {
    id: 'alu',
    name: 'ALU × 2',
    category: 'backend',
    description:
      'Two 1-cycle integer ALUs, lets two independent integer ops finish per cycle.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'mult',
    name: 'Multiplier',
    category: 'backend',
    description:
      'Pipelined multiplier from Project 2, 5 stages. Drives the early-tag-broadcast sideband one cycle before the final result lands on the CDB.',
    parameters: [{ key: 'MULT_STAGES', value: '5' }],
    files: [
      { path: 'verilog/mult.sv', githubUrl: blob('verilog/mult.sv') },
      { path: 'verilog/mult_stage.sv', githubUrl: blob('verilog/mult_stage.sv') },
    ],
    advancedFeatures: ['etb'],
  },
  {
    id: 'branch-resolver',
    name: 'Branch Resolver',
    category: 'backend',
    description:
      'Inline unit that resolves conditional branches and produces JAL/JALR targets. Resolution travels on the CDB; PC redirect happens at commit, not at execute.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: [],
  },
  {
    id: 'dcache',
    name: 'D-Cache',
    category: 'memory',
    description:
      '256-byte 2-way set-associative, write-back, write-allocate D-cache with byte-granular valid/dirty masks for sub-word stores. One LRU bit per set. Carries its own internal next-line prefetcher (the shared stream_buffer.sv module is wired only to the I-cache front-end).',
    parameters: [
      { key: 'capacity', value: '256 B' },
      { key: 'sets', value: '16' },
      { key: 'ways', value: '2' },
      { key: 'line size', value: '8 B' },
    ],
    files: [{ path: 'verilog/dcache.sv', githubUrl: blob('verilog/dcache.sv') }],
    advancedFeatures: ['set-associative', 'prefetch'],
  },
  {
    id: 'cdb',
    name: 'CDB (2 slots)',
    category: 'control',
    description:
      'Two-slot Common Data Bus. Per-slot priority is MULT > LD > ALU. Stores never use the CDB; they signal completion via a sideband to the ROB.',
    parameters: [{ key: 'slots', value: '2' }],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'commit',
    name: 'Commit (2-wide) + Arch RegFile',
    category: 'control',
    description:
      'Retires up to 2 ROB entries per cycle in program order. Writes the architectural register file. Runs the mispredict check; on disagreement, raises a one-cycle redirect that flushes RS, LSQ, and in-flight MULT.',
    parameters: [],
    files: [
      { path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') },
      { path: 'verilog/regfile.sv', githubUrl: blob('verilog/regfile.sv') },
    ],
    advancedFeatures: ['superscalar'],
  },
];
