'use client';

import {
  Bar,
  BarChart,
  Cell,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { PROGRAM_RESULTS, type ProgramResult } from '@/lib/results';

const sorted: ProgramResult[] = [...PROGRAM_RESULTS].sort(
  (a, b) => a.deltaPct - b.deltaPct,
);

export function PerProgramSpeedupChart() {
  return (
    <div className="h-[640px] w-full">
      <ResponsiveContainer>
        <BarChart
          data={sorted}
          layout="vertical"
          margin={{ top: 8, right: 60, left: 60, bottom: 8 }}
        >
          <XAxis type="number" domain={[-50, 5]} unit="%" stroke="#5F657A" />
          <YAxis
            type="category"
            dataKey="program"
            width={120}
            stroke="#5F657A"
            tick={{ fontSize: 11 }}
          />
          <ReferenceLine x={0} stroke="#D8DDF2" />
          <Tooltip
            contentStyle={{
              background: 'white',
              border: '1px solid #D8DDF2',
              borderRadius: 12,
            }}
            formatter={(value, _name, item) => {
              const v = value as number;
              const r = (item as { payload: ProgramResult }).payload;
              const branchAccText =
                r.branchAccAllOn !== null
                  ? `, branch acc ${r.branchAccAllOn.toFixed(2)}%`
                  : '';
              return [
                `${v.toFixed(2)}% (${r.cyclesOoOBase.toLocaleString()} → ${r.cyclesAllOn.toLocaleString()} cycles, CPI ${r.cpiAllOn.toFixed(2)}${branchAccText})`,
                'Δ%',
              ];
            }}
          />
          <Bar dataKey="deltaPct">
            {sorted.map((r) => (
              <Cell
                key={r.program}
                fill={r.deltaPct > 0 ? '#C34FA2' : '#5364C0'}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
