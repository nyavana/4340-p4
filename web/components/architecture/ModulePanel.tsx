'use client';
import { SidePanel } from '@/components/ui/SidePanel';
import { MODULES } from '@/lib/architecture';
import { FEATURES } from '@/lib/features';

interface Props {
  moduleId: string | null;
  onClose: () => void;
}

export function ModulePanel({ moduleId, onClose }: Props) {
  const m = MODULES.find((x) => x.id === moduleId);
  return (
    <SidePanel open={!!m} onClose={onClose}>
      {m && (
        <div>
          <p className="text-xs uppercase tracking-widest text-iris-600">{m.category}</p>
          <h2 className="mt-2 text-3xl font-semibold text-plum-500">{m.name}</h2>
          <p className="mt-4 text-ink leading-relaxed">{m.description}</p>

          {m.parameters.length > 0 && (
            <>
              <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
                Parameters
              </h3>
              <dl className="mt-3 grid grid-cols-2 gap-y-2 text-sm">
                {m.parameters.map((p) => (
                  <div key={p.key} className="contents">
                    <dt className="text-ink-muted">{p.key}</dt>
                    <dd className="text-ink font-mono">{p.value}</dd>
                  </div>
                ))}
              </dl>
            </>
          )}

          <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
            Source
          </h3>
          <ul className="mt-3 space-y-1 text-sm">
            {m.files.map((f) => (
              <li key={f.path}>
                <a
                  href={f.githubUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-iris-600 hover:text-plum-500 font-mono"
                >
                  {f.path}
                </a>
              </li>
            ))}
          </ul>

          {m.advancedFeatures.length > 0 && (
            <>
              <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
                Advanced features hosted here
              </h3>
              <ul className="mt-3 flex flex-wrap gap-2">
                {m.advancedFeatures.map((fid) => {
                  const f = FEATURES.find((x) => x.id === fid);
                  if (!f) return null;
                  return (
                    <li key={fid}>
                      <a
                        href={`/deep-dive${f.deepDiveAnchor}`}
                        className="inline-flex items-center rounded-full bg-orchid-50 text-plum-500 px-3 py-1 text-xs"
                      >
                        {f.name}
                      </a>
                    </li>
                  );
                })}
              </ul>
            </>
          )}
        </div>
      )}
    </SidePanel>
  );
}
