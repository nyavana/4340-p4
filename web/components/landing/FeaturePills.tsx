import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { FEATURES } from '@/lib/features';

export function FeaturePills() {
  return (
    <section className="mx-auto max-w-7xl px-6 py-24">
      <h2 className="text-3xl font-semibold text-plum-500 mb-3">Seven advanced features</h2>
      <p className="text-ink-muted max-w-2xl mb-12">
        Two from the difficult tier and five from the simpler tier, layered on top of the
        base out-of-order pipeline.
      </p>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {FEATURES.map((f) => (
          <Link key={f.id} href={`/deep-dive${f.deepDiveAnchor}`}>
            <Card className="h-full hover:shadow-strong transition-shadow cursor-pointer">
              <div className="flex items-start justify-between">
                <h3 className="text-lg font-semibold text-plum-500">{f.name}</h3>
                <span className="text-xs uppercase tracking-widest text-iris-600">
                  {f.tier}
                </span>
              </div>
              <p className="mt-3 text-sm text-ink-muted">{f.oneLiner}</p>
              {f.marginalDeltaPctWhenDisabled !== null ? (
                <p className="mt-4 text-xs text-ink-subtle">
                  Disabling raises geomean cycles by{' '}
                  <span className="text-orchid-600 font-mono">
                    +{f.marginalDeltaPctWhenDisabled.toFixed(2)}%
                  </span>
                </p>
              ) : (
                <p className="mt-4 text-xs text-ink-subtle">Structural — see deep dive</p>
              )}
            </Card>
          </Link>
        ))}
      </div>
    </section>
  );
}
