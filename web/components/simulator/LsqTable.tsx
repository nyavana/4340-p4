'use client';
import type { LsqEntry } from '@/lib/trace';

export function LsqTable({ lsq }: { lsq: LsqEntry[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">LSQ</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle">
          <tr>
            <th className="text-left">tag</th>
            <th className="text-left">op</th>
            <th className="text-left">addr</th>
            <th>state</th>
          </tr>
        </thead>
        <tbody>
          {lsq.map((e) => (
            <tr key={e.tag}>
              <td>{e.tag}</td>
              <td>{e.op ?? '—'}</td>
              <td>{e.addr !== undefined ? `0x${e.addr.toString(16)}` : '—'}</td>
              <td className="text-center">{e.state ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
