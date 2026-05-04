'use client';

// AdvancedFeatureToggle.tsx
//
// Toggle row for the landing-page architecture diagram.  Lets the visitor
// pick which advanced features to highlight on the diagram via orchid
// underlays + glow (driven by `ArchDiagram`'s `highlightedFeatureIds` prop).
//
// Layout:
//   [Show all advanced features / Hide advanced features]
//   [2-way Superscalar] [Early Tag Broadcast] [gshare Predictor] ...
//
// The "all on" master button toggles the full set on/off.  Individual pills
// add/remove their own id from the selection set.  All state is hoisted to
// the parent (Task 14) — this component is a pure controlled input.

import { FEATURES } from '@/lib/features';
import clsx from 'clsx';

interface Props {
  selectedFeatureIds: string[];
  onChange: (ids: string[]) => void;
}

export function AdvancedFeatureToggle({ selectedFeatureIds, onChange }: Props) {
  const allOn = selectedFeatureIds.length === FEATURES.length;
  return (
    <div className="mb-6 flex flex-wrap items-center gap-3">
      <button
        onClick={() => onChange(allOn ? [] : FEATURES.map((f) => f.id))}
        className={clsx(
          'rounded-full px-4 py-1.5 text-sm transition-colors',
          allOn
            ? 'bg-plum-500 text-white'
            : 'bg-snow-500 text-ink-muted border border-snow-600',
        )}
      >
        {allOn ? 'Hide advanced features' : 'Show all advanced features'}
      </button>
      {FEATURES.map((f) => {
        const on = selectedFeatureIds.includes(f.id);
        return (
          <button
            key={f.id}
            onClick={() =>
              onChange(
                on
                  ? selectedFeatureIds.filter((id) => id !== f.id)
                  : [...selectedFeatureIds, f.id],
              )
            }
            className={clsx(
              'rounded-full px-3 py-1 text-xs transition-colors',
              on
                ? 'bg-orchid-500 text-white'
                : 'bg-orchid-50 text-plum-500 hover:bg-orchid-100',
            )}
          >
            {f.name}
          </button>
        );
      })}
    </div>
  );
}
