export interface InstrRef {
  rob_tag?: number;
  pc?: number;
  instr_text?: string;
}

export interface RobEntry {
  tag: number;
  pc?: number;
  instr_text?: string;
  busy?: boolean;
  ready?: boolean;
  value?: number;
}
export interface RsEntry {
  tag: number;
  op?: string;
  src1_tag?: number;
  src1_ready?: boolean;
  src2_tag?: number;
  src2_ready?: boolean;
}
export interface LsqEntry {
  tag: number;
  op?: string;
  addr?: number;
  data?: number;
  state?: string;
}
export interface CdbSlot {
  tag: number;
  value?: number;
}
export interface ExecState {
  alu0?: InstrRef;
  alu1?: InstrRef;
  mult_stage_n?: number;
  branch?: InstrRef;
  lsq_head?: InstrRef;
}

export interface CycleSnapshot {
  cycle: number;
  pc: number;
  fetch: InstrRef[];
  decode: InstrRef[];
  rob: RobEntry[];
  rs: RsEntry[];
  lsq: LsqEntry[];
  exec: ExecState;
  cdb: CdbSlot[];
  commit: InstrRef[];
  events: string[];
}

export interface Trace {
  program: string;
  snapshots: CycleSnapshot[];
}

export const TRACE_PROGRAMS = [
  { id: 'parallel', label: 'parallel.s — ILP demo' },
  { id: 'mult_no_lsq', label: 'mult_no_lsq.s — multiplier + ETB' },
  { id: 'fib_rec', label: 'fib_rec.s — recursion + RAS' },
] as const;

export type TraceProgramId = (typeof TRACE_PROGRAMS)[number]['id'];

export async function loadTrace(id: TraceProgramId): Promise<Trace> {
  const res = await fetch(`/traces/${id}.json`);
  if (!res.ok) throw new Error(`failed to load trace ${id}: ${res.status}`);
  return res.json();
}

export function findFirstEventCycle(snapshots: CycleSnapshot[]): number {
  const idx = snapshots.findIndex((s) => s.events.length > 0);
  return idx >= 0 ? snapshots[idx].cycle : (snapshots[0]?.cycle ?? 0);
}
