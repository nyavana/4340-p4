'use client';

import {
  Bar,
  BarChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { PROGRAM_RESULTS, SUITE_SUMMARY } from '@/lib/results';

const data = PROGRAM_RESULTS
  .filter((r) => r.branchAccAllOn !== null)
  .map((r) => ({
    program: r.program,
    branchAccAllOn: r.branchAccAllOn as number,
  }))
  .sort((a, b) => b.branchAccAllOn - a.branchAccAllOn);

export function BranchAccLiftChart() {
  return (
    <div className="h-[640px] w-full">
      <ResponsiveContainer>
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 8, right: 60, left: 60, bottom: 8 }}
        >
          <XAxis type="number" unit="%" domain={[0, 100]} stroke="#5F657A" />
          <YAxis
            type="category"
            dataKey="program"
            width={120}
            stroke="#5F657A"
            tick={{ fontSize: 11 }}
          />
          <ReferenceLine
            x={SUITE_SUMMARY.geomeanBranchAcc}
            stroke="#C34FA2"
            strokeDasharray="4 4"
            label={{
              value: `geomean ${SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%`,
              fill: '#C34FA2',
              fontSize: 11,
              position: 'top',
            }}
          />
          <Tooltip
            contentStyle={{
              background: 'white',
              border: '1px solid #D8DDF2',
              borderRadius: 12,
            }}
          />
          <Bar dataKey="branchAccAllOn" fill="#5364C0" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
