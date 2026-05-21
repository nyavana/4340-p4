'use client';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, ReferenceLine } from 'recharts';
import { PROGRAM_RESULTS, SUITE_SUMMARY } from '@/lib/results';

const BIN_COUNT = 10;
const BIN_MAX = 110;
const BIN_WIDTH = BIN_MAX / BIN_COUNT;

function bin() {
  const buckets = Array.from({ length: BIN_COUNT }, (_, i) => ({
    range: `${(i * BIN_WIDTH).toFixed(0)}–${((i + 1) * BIN_WIDTH).toFixed(0)}`,
    count: 0,
  }));
  for (const r of PROGRAM_RESULTS) {
    const idx = Math.min(BIN_COUNT - 1, Math.floor(r.cpiAllOn / BIN_WIDTH));
    buckets[idx].count += 1;
  }
  return buckets;
}

export function CpiHistogram() {
  const geomeanBucket = `${(Math.floor(SUITE_SUMMARY.geomeanCpi / BIN_WIDTH) * BIN_WIDTH).toFixed(0)}–${((Math.floor(SUITE_SUMMARY.geomeanCpi / BIN_WIDTH) + 1) * BIN_WIDTH).toFixed(0)}`;
  return (
    <div className="h-[360px] w-full">
      <ResponsiveContainer>
        <BarChart data={bin()} margin={{ left: 20, right: 20, top: 32, bottom: 8 }}>
          <XAxis
            dataKey="range"
            stroke="#5F657A"
            tick={{ fontSize: 11 }}
            label={{ value: 'CPI bucket', position: 'insideBottom', offset: -4, fontSize: 12 }}
          />
          <YAxis allowDecimals={false} stroke="#5F657A" />
          <Tooltip contentStyle={{ background: 'white', border: '1px solid #D8DDF2', borderRadius: 12 }} />
          <Bar dataKey="count" fill="#5364C0" />
          <ReferenceLine
            x={geomeanBucket}
            stroke="#C34FA2"
            strokeDasharray="4 4"
            label={{
              value: `geomean ${SUITE_SUMMARY.geomeanCpi.toFixed(2)}`,
              fill: '#C34FA2',
              fontSize: 11,
              position: 'top',
            }}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
