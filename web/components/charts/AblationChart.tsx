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

import { ABLATION, type AblationRow } from '@/lib/results';

const ablationOnly: AblationRow[] = ABLATION.filter(
  (r) => r.source === 'ablation',
);

export function AblationChart() {
  return (
    <div className="h-[360px] w-full">
      <ResponsiveContainer>
        <BarChart
          data={ablationOnly}
          layout="vertical"
          margin={{ top: 8, right: 60, left: 60, bottom: 8 }}
        >
          <XAxis type="number" unit="%" domain={[0, 'auto']} stroke="#5F657A" />
          <YAxis
            type="category"
            dataKey="feature"
            width={150}
            stroke="#5F657A"
            tick={{ fontSize: 12 }}
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
              const r = (item as { payload: AblationRow }).payload;
              return [
                `+${v.toFixed(2)}% geomean (worst: ${r.worstCaseProgram} +${r.worstCaseDeltaPct.toFixed(2)}%)`,
                'Δ% when disabled',
              ];
            }}
          />
          <Bar dataKey="geomeanDeltaPctWhenDisabled">
            {ablationOnly.map((r) => (
              <Cell
                key={r.feature}
                fill={r.feature === 'all 5 disabled' ? '#77295D' : '#5364C0'}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
