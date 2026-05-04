import { Card } from '@/components/ui/Card';
import { SUITE_SUMMARY, TIMING } from '@/lib/results';

interface Stat {
  label: string;
  value: string;
  sub?: string;
}

const STATS: Stat[] = [
  {
    label: 'Programs passing',
    value: '33 / 33',
    sub: 'RTL + synthesized netlist',
  },
  {
    label: 'Geomean cycle reduction',
    value: `${SUITE_SUMMARY.geomeanDeltaPct.toFixed(2)}%`,
    sub: 'OoO base → all-on',
  },
  {
    label: 'Geomean branch accuracy',
    value: `${SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%`,
    sub: `+${SUITE_SUMMARY.branchAccLiftOverBimodalPp.toFixed(2)} pp over bimodal`,
  },
  {
    label: 'Worst slack at 1000 ps',
    value: `${TIMING.worstSlackPs} ps`,
    sub: 'functionally bit-equivalent',
  },
];

export function HeadlineNumbers() {
  return (
    <div className="mt-16 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
      {STATS.map((s) => (
        <Card key={s.label}>
          <p className="text-xs uppercase tracking-widest text-ink-subtle">{s.label}</p>
          <p className="mt-3 text-3xl font-semibold text-plum-500">{s.value}</p>
          {s.sub && <p className="mt-2 text-sm text-ink-muted">{s.sub}</p>}
        </Card>
      ))}
    </div>
  );
}
