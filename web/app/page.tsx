'use client';
import { useState } from 'react';
import { Hero } from '@/components/landing/Hero';
import { ArchDiagram } from '@/components/architecture/ArchDiagram';
import { ModulePanel } from '@/components/architecture/ModulePanel';
import { AdvancedFeatureToggle } from '@/components/architecture/AdvancedFeatureToggle';
import { PerProgramSpeedupChart } from '@/components/charts/PerProgramSpeedupChart';
import { FeaturePills } from '@/components/landing/FeaturePills';

export default function HomePage() {
  const [selectedModuleId, setSelectedModuleId] = useState<string | null>(null);
  const [highlightedFeatureIds, setHighlightedFeatureIds] = useState<string[]>([]);

  return (
    <>
      <Hero />

      <section className="mx-auto max-w-7xl px-6 py-16">
        <h2 className="text-3xl font-semibold text-plum-500 mb-2">Architecture</h2>
        <p className="text-ink-muted max-w-2xl mb-8">
          Click any module to read what it does. Toggle the pills to highlight the advanced
          features in their host modules.
        </p>
        <AdvancedFeatureToggle
          selectedFeatureIds={highlightedFeatureIds}
          onChange={setHighlightedFeatureIds}
        />
        <ArchDiagram
          highlightedFeatureIds={highlightedFeatureIds}
          onSelect={setSelectedModuleId}
        />
      </section>

      <section className="mx-auto max-w-7xl px-6 py-16">
        <h2 className="text-3xl font-semibold text-plum-500 mb-2">Per-program results</h2>
        <p className="text-ink-muted max-w-2xl mb-8">
          Cycle-count change from disabling all five ablate-able advanced features
          (OoO base) to running all seven (all-on). Hover any bar for details.
        </p>
        <PerProgramSpeedupChart />
      </section>

      <FeaturePills />

      <ModulePanel moduleId={selectedModuleId} onClose={() => setSelectedModuleId(null)} />
    </>
  );
}
