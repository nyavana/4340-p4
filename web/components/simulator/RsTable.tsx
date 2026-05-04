'use client';
import type { RsEntry } from '@/lib/trace';

export function RsTable({ rs }: { rs: RsEntry[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">RS</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle">
          <tr>
            <th className="text-left">tag</th>
            <th className="text-left">op</th>
            <th>s1</th>
            <th>s2</th>
          </tr>
        </thead>
        <tbody>
          {rs.map((e) => (
            <tr key={e.tag}>
              <td>{e.tag}</td>
              <td>{e.op ?? '—'}</td>
              <td className="text-center">{e.src1_ready ? '✓' : `t${e.src1_tag ?? '?'}`}</td>
              <td className="text-center">{e.src2_ready ? '✓' : `t${e.src2_tag ?? '?'}`}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
