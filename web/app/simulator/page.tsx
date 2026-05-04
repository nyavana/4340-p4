'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  loadTrace,
  TRACE_PROGRAMS,
  findFirstEventCycle,
  type Trace,
  type TraceProgramId,
  type CycleSnapshot,
} from '@/lib/trace';
import { PipelineLanes } from '@/components/simulator/PipelineLanes';
import { RobTable } from '@/components/simulator/RobTable';
import { RsTable } from '@/components/simulator/RsTable';
import { LsqTable } from '@/components/simulator/LsqTable';
import { Scrubber } from '@/components/simulator/Scrubber';
import { EventCaption } from '@/components/simulator/EventCaption';
import { MobileFallback } from '@/components/simulator/MobileFallback';

const STEP_INTERVAL_MS = 200;

export default function SimulatorPage() {
  const [programId, setProgramId] = useState<TraceProgramId>('parallel');
  const [trace, setTrace] = useState<Trace | null>(null);
  const [cycle, setCycle] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [speed, setSpeed] = useState(1);
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadTrace(programId)
      .then((t) => {
        if (cancelled) return;
        setTrace(t);
        setCycle(findFirstEventCycle(t.snapshots));
        setIsPlaying(false);
      })
      .catch((err) => {
        console.error(err);
      });
    return () => {
      cancelled = true;
    };
  }, [programId]);

  useEffect(() => {
    if (!isPlaying || !trace) return;
    const max = trace.snapshots[trace.snapshots.length - 1].cycle;
    tickRef.current = setInterval(() => {
      setCycle((c) => {
        const next = c + speed;
        if (next > max) {
          setIsPlaying(false);
          return max;
        }
        return next;
      });
    }, STEP_INTERVAL_MS);
    return () => {
      if (tickRef.current) clearInterval(tickRef.current);
    };
  }, [isPlaying, speed, trace]);

  const snapshot: CycleSnapshot | null = useMemo(() => {
    if (!trace || trace.snapshots.length === 0) return null;
    let lo = 0;
    let hi = trace.snapshots.length - 1;
    let ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (trace.snapshots[mid].cycle <= cycle) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return trace.snapshots[ans];
  }, [trace, cycle]);

  const jumpNextEvent = () => {
    if (!trace) return;
    const idx = trace.snapshots.findIndex((s) => s.cycle > cycle && s.events.length > 0);
    if (idx >= 0) setCycle(trace.snapshots[idx].cycle);
  };

  if (!trace) {
    return <p className="mx-auto max-w-7xl px-6 py-16 text-ink-muted">Loading trace…</p>;
  }
  if (trace.snapshots.length === 0) {
    return (
      <p className="mx-auto max-w-7xl px-6 py-16 text-ink-muted">
        Trace is empty for {programId}. Run capture_trace.py on the lab PC and check that
        web/public/traces/ is populated.
      </p>
    );
  }

  const minCycle = trace.snapshots[0].cycle;
  const maxCycle = trace.snapshots[trace.snapshots.length - 1].cycle;
  const committingTags = (snapshot?.commit ?? [])
    .map((c) => c.rob_tag)
    .filter((t): t is number => t !== undefined);

  return (
    <>
      <MobileFallback />
      <div className="hidden lg:block mx-auto max-w-[1600px] px-6 py-8 space-y-4">
        <div className="flex items-center gap-4">
          <h1 className="text-2xl font-semibold text-plum-500">Pipeline visualizer</h1>
          <select
            value={programId}
            onChange={(e) => setProgramId(e.target.value as TraceProgramId)}
            className="rounded-md border border-snow-600 bg-white px-3 py-1.5 text-sm"
          >
            {TRACE_PROGRAMS.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-[1fr_320px] gap-4">
          <div className="space-y-4">
            <PipelineLanes snapshot={snapshot} />
            <EventCaption events={snapshot?.events ?? []} />
          </div>
          <div className="space-y-4">
            <RobTable rob={snapshot?.rob ?? []} committingTags={committingTags} />
            <RsTable rs={snapshot?.rs ?? []} />
            <LsqTable lsq={snapshot?.lsq ?? []} />
          </div>
        </div>

        <Scrubber
          cycle={cycle}
          minCycle={minCycle}
          maxCycle={maxCycle}
          isPlaying={isPlaying}
          speed={speed}
          onCycleChange={setCycle}
          onPlayPause={() => setIsPlaying((p) => !p)}
          onStep={(d) => setCycle((c) => Math.max(minCycle, Math.min(maxCycle, c + d)))}
          onJumpNextEvent={jumpNextEvent}
          onSpeedChange={setSpeed}
        />
      </div>
    </>
  );
}
