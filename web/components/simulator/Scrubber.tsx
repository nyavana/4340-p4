'use client';

interface Props {
  cycle: number;
  minCycle: number;
  maxCycle: number;
  isPlaying: boolean;
  speed: number;
  onCycleChange: (c: number) => void;
  onPlayPause: () => void;
  onStep: (delta: number) => void;
  onJumpNextEvent: () => void;
  onSpeedChange: (s: number) => void;
}

export function Scrubber({
  cycle,
  minCycle,
  maxCycle,
  isPlaying,
  speed,
  onCycleChange,
  onPlayPause,
  onStep,
  onJumpNextEvent,
  onSpeedChange,
}: Props) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-4 flex flex-wrap items-center gap-4">
      <button
        onClick={() => onStep(-1)}
        className="px-2 py-1 text-iris-600 hover:text-plum-500"
        aria-label="step back"
      >
        ⏮
      </button>
      <button
        onClick={onPlayPause}
        className="rounded-full bg-plum-500 text-white w-10 h-10 flex items-center justify-center hover:bg-plum-600"
      >
        {isPlaying ? '⏸' : '▶'}
      </button>
      <button
        onClick={() => onStep(1)}
        className="px-2 py-1 text-iris-600 hover:text-plum-500"
        aria-label="step forward"
      >
        ⏭
      </button>
      <button
        onClick={onJumpNextEvent}
        className="px-3 py-1 rounded-full bg-orchid-50 text-plum-500 text-xs hover:bg-orchid-100"
      >
        Jump to next event
      </button>
      <input
        type="range"
        min={minCycle}
        max={maxCycle}
        value={cycle}
        onChange={(e) => onCycleChange(Number(e.target.value))}
        className="flex-1 min-w-[200px] accent-iris-500"
      />
      <span className="font-mono text-sm text-ink-muted tabular-nums">
        cycle {cycle.toLocaleString()} / {maxCycle.toLocaleString()}
      </span>
      <select
        value={speed}
        onChange={(e) => onSpeedChange(Number(e.target.value))}
        className="rounded-md border border-snow-600 bg-white px-2 py-1 text-sm"
      >
        <option value={1}>1×</option>
        <option value={4}>4×</option>
        <option value={16}>16×</option>
      </select>
    </div>
  );
}
