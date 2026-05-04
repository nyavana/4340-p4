'use client';
import type { RobEntry } from '@/lib/trace';

export function RobTable({ rob, committingTags }: { rob: RobEntry[]; committingTags: number[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">ROB</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle">
          <tr>
            <th className="text-left">tag</th>
            <th className="text-left">pc</th>
            <th>busy</th>
            <th>ready</th>
          </tr>
        </thead>
        <tbody>
          {rob.map((e) => (
            <tr key={e.tag} className={committingTags.includes(e.tag) ? 'bg-plum-50' : ''}>
              <td>{e.tag}</td>
              <td>{e.pc !== undefined ? `0x${e.pc.toString(16)}` : '—'}</td>
              <td className="text-center">{e.busy ? '●' : '·'}</td>
              <td className="text-center">{e.ready ? '✓' : '·'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
