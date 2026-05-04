'use client';

const EVENT_DESCRIPTIONS: Record<string, string> = {
  mispredict: 'Branch predictor wrong — pipeline must flush in-flight instructions.',
  flush: 'Mispredict-driven flush: RS, LSQ, and in-flight MULT all reset.',
  etb_wakeup: 'Multiplier raised early-tag broadcast — RS consumer wakes one cycle ahead.',
};

export function EventCaption({ events }: { events: string[] }) {
  if (events.length === 0) return null;
  return (
    <div className="rounded-soft bg-orchid-50 border border-orchid-100 p-4">
      {events.map((e) => {
        const key = e.split(':')[0];
        const desc = EVENT_DESCRIPTIONS[key] ?? e;
        return (
          <p key={e} className="text-sm text-plum-500">
            <span className="font-mono text-xs uppercase tracking-widest mr-2">{key}</span>
            {desc}
          </p>
        );
      })}
    </div>
  );
}
