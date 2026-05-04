'use client';

import { motion, AnimatePresence } from 'framer-motion';
import type { CycleSnapshot } from '@/lib/trace';

const LANES = ['Fetch', 'Decode', 'RS / LSQ', 'Exec', 'CDB', 'Commit'] as const;

const TAG_COLORS = [
  '#77295D',
  '#5364C0',
  '#77B7F0',
  '#C34FA2',
  '#3B142F',
  '#293260',
  '#33506A',
  '#612851',
];

function colorForTag(tag: number): string {
  return TAG_COLORS[tag % TAG_COLORS.length];
}

interface Pill {
  tag: number;
  lane: number;
  label: string;
  key: string;
}

function pillsFromSnapshot(s: CycleSnapshot): Pill[] {
  const pills: Pill[] = [];

  s.fetch.forEach((i, k) => {
    if (i.rob_tag !== undefined) {
      pills.push({
        tag: i.rob_tag,
        lane: 0,
        label: i.instr_text ?? `pc=${(i.pc ?? 0).toString(16)}`,
        key: `f-${i.rob_tag}-${k}`,
      });
    }
  });

  s.decode.forEach((i, k) => {
    if (i.rob_tag !== undefined) {
      pills.push({
        tag: i.rob_tag,
        lane: 1,
        label: i.instr_text ?? '',
        key: `d-${i.rob_tag}-${k}`,
      });
    }
  });

  s.rs.forEach((e, k) => {
    pills.push({
      tag: e.tag,
      lane: 2,
      label: e.op ?? `t${e.tag}`,
      key: `rs-${e.tag}-${k}`,
    });
  });

  s.lsq.forEach((e, k) => {
    pills.push({
      tag: e.tag,
      lane: 2,
      label: `LSQ ${e.op ?? ''}`,
      key: `lsq-${e.tag}-${k}`,
    });
  });

  if (s.exec.alu0?.rob_tag !== undefined) {
    pills.push({
      tag: s.exec.alu0.rob_tag,
      lane: 3,
      label: 'ALU0',
      key: 'exec-alu0',
    });
  }
  if (s.exec.alu1?.rob_tag !== undefined) {
    pills.push({
      tag: s.exec.alu1.rob_tag,
      lane: 3,
      label: 'ALU1',
      key: 'exec-alu1',
    });
  }
  if (s.exec.mult_stage_n !== undefined) {
    pills.push({
      tag: -1,
      lane: 3,
      label: `MULT s${s.exec.mult_stage_n}`,
      key: 'exec-mult',
    });
  }

  s.cdb.forEach((c, k) => {
    pills.push({
      tag: c.tag,
      lane: 4,
      label: `CDB t${c.tag}`,
      key: `cdb-${c.tag}-${k}`,
    });
  });

  s.commit.forEach((i, k) => {
    if (i.rob_tag !== undefined) {
      pills.push({
        tag: i.rob_tag,
        lane: 5,
        label: i.instr_text ?? `t${i.rob_tag}`,
        key: `c-${i.rob_tag}-${k}`,
      });
    }
  });

  return pills;
}

export function PipelineLanes({ snapshot }: { snapshot: CycleSnapshot | null }) {
  const pills = snapshot ? pillsFromSnapshot(snapshot) : [];
  const grouped: Pill[][] = LANES.map((_, lane) => pills.filter((p) => p.lane === lane));

  return (
    <div className="grid grid-cols-6 gap-2 h-[480px]">
      {LANES.map((laneLabel, idx) => (
        <div
          key={laneLabel}
          className="flex flex-col bg-white rounded-soft border border-snow-600 p-3"
        >
          <p className="text-xs uppercase tracking-widest text-ink-subtle mb-3">{laneLabel}</p>
          <div className="flex-1 overflow-y-auto space-y-2">
            {grouped[idx].length === 0 ? (
              <p className="text-[10px] text-ink-subtle italic mt-1">empty</p>
            ) : (
              <AnimatePresence>
                {grouped[idx].map((p) => (
                  <motion.div
                    key={p.key}
                    layout
                    initial={{ opacity: 0, y: -6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 6 }}
                    className="rounded-md px-2 py-1 text-xs text-white font-mono"
                    style={{ background: p.tag >= 0 ? colorForTag(p.tag) : '#5F657A' }}
                  >
                    {p.label}
                  </motion.div>
                ))}
              </AnimatePresence>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
