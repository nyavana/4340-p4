'use client';

// ArchDiagram.tsx
//
// Interactive landing-page architecture diagram for the EECS 4340 OoO RV32IM
// processor.  Renders the 13 modules from `lib/architecture.ts` as boxes with
// arrows showing the dataflow grounded in `verilog/pipeline.sv`.
//
// Interactions:
//   - Hover lifts the box (Framer Motion, scale 1.03).
//   - Click invokes `onSelect(moduleId)`; the parent (Task 14) opens the side
//     panel.
//   - When `highlightedFeatureIds` is non-empty, modules whose
//     `advancedFeatures` intersect the highlight set get an orchid-pink
//     translucent underlay (drawn behind the white box) plus a subtle glow
//     filter.
//
// Layout: viewBox 0 0 1200 720, boxes 180w x 56h, rx=8.  All boxes carry a
// 4 px-wide colored band on their left edge encoding `module.category`
// (frontend / backend / memory / control).  The universal box stroke stays
// plum (`#77295D`); arrows are iris (`#5364C0`); the writeback feedback edge
// from CDB back to ROB+RAT is dashed.
//
// Sibling reference: `web/components/diagrams/PipelineOverviewDiagram.tsx`
// renders the same topology without interaction.

import { useMemo } from 'react';
import { motion } from 'framer-motion';
import { MODULES, type PipelineModule } from '@/lib/architecture';

// --------------------------------------------------------------------------
// Color tokens (mirrors web/app/globals.css @theme).  These palette values
// must match the css custom properties so the diagram remains visually in
// sync with the rest of the site.
// --------------------------------------------------------------------------
const PLUM = '#77295D';
const IRIS = '#5364C0';
const ORCHID = '#C34FA2';
const INK = '#241B2A';
const WHITE = '#FFFFFF';

const CATEGORY_COLOR: Record<PipelineModule['category'], string> = {
  frontend: '#591F46', // plum-600
  backend: '#5364C0', // iris-500
  memory: '#77B7F0', // sky-500
  control: '#C34FA2', // orchid-500
};

// --------------------------------------------------------------------------
// Geometry constants
// --------------------------------------------------------------------------
const BOX_W = 180;
const BOX_H = 56;
const RX = 8;
const STROKE_W = 1.5;
const BAND_W = 4;            // left-edge category band width
const HIGHLIGHT_PAD = 7;     // orchid underlay padding around highlighted boxes
const HIGHLIGHT_RX = 12;

// Per-module top-left coordinates inside the 1200x720 viewBox.  Keyed by
// `module.id` so we can layer the boxes in any z-order without losing the
// mapping.
const POSITIONS: Record<string, { x: number; y: number }> = {
  // top row: I-cache, fetch, branch predictor
  'icache':           { x: 210, y: 30 },
  'fetch':            { x: 510, y: 30 },
  'branch-predictor': { x: 810, y: 30 },

  // pipeline spine
  'decode':           { x: 510, y: 130 },
  'rob':              { x: 510, y: 230 },

  // issue queues
  'rs':               { x: 310, y: 350 },
  'lsq':              { x: 710, y: 350 },

  // execution units
  'alu':              { x: 110, y: 470 },
  'mult':             { x: 310, y: 470 },
  'branch-resolver':  { x: 510, y: 470 },
  'dcache':           { x: 910, y: 470 },

  // back end
  'cdb':              { x: 510, y: 580 },
  'commit':           { x: 510, y: 660 },
};

// Helpers for arrow endpoints.
const cx = (id: string) => POSITIONS[id].x + BOX_W / 2;
const top = (id: string) => POSITIONS[id].y;
const bottom = (id: string) => POSITIONS[id].y + BOX_H;
const right = (id: string) => POSITIONS[id].x + BOX_W;

// --------------------------------------------------------------------------
// Highlight detection — returns true when a module hosts any feature whose
// id appears in `highlightedFeatureIds`.
// --------------------------------------------------------------------------
function isHighlighted(
  mod: PipelineModule,
  highlightedFeatureIds: readonly string[],
): boolean {
  if (highlightedFeatureIds.length === 0) return false;
  return mod.advancedFeatures.some((f) => highlightedFeatureIds.includes(f));
}

// --------------------------------------------------------------------------
// Single module box, animated via Framer Motion.
// --------------------------------------------------------------------------
interface ModuleBoxProps {
  module: PipelineModule;
  highlighted: boolean;
  onSelect: (id: string) => void;
}

function ModuleBox({ module: mod, highlighted, onSelect }: ModuleBoxProps) {
  const { x, y } = POSITIONS[mod.id];
  const bandColor = CATEGORY_COLOR[mod.category];

  return (
    <motion.g
      onClick={() => onSelect(mod.id)}
      whileHover={{ scale: 1.03 }}
      transition={{ type: 'spring', stiffness: 320, damping: 22 }}
      style={{
        cursor: 'pointer',
        transformBox: 'fill-box',
        transformOrigin: 'center',
      }}
      role="button"
      tabIndex={0}
      aria-label={`${mod.name} — click for details`}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onSelect(mod.id);
        }
      }}
    >
      {/* White box (drawn on top of any highlight underlay) */}
      <rect
        x={x}
        y={y}
        width={BOX_W}
        height={BOX_H}
        rx={RX}
        ry={RX}
        fill={WHITE}
        stroke={PLUM}
        strokeWidth={STROKE_W}
      />

      {/* Left-edge category band.  Drawn as a thin filled rect that hugs the
          left edge of the box.  Covers the rounded corner by overlapping the
          rect; we clip via clipPath so the band itself stays rounded on the
          left side. */}
      <clipPath id={`band-clip-${mod.id}`}>
        <rect x={x} y={y} width={BOX_W} height={BOX_H} rx={RX} ry={RX} />
      </clipPath>
      <rect
        x={x}
        y={y}
        width={BAND_W}
        height={BOX_H}
        fill={bandColor}
        clipPath={`url(#band-clip-${mod.id})`}
      />

      {/* Label */}
      <text
        x={x + BOX_W / 2 + BAND_W / 2}
        y={y + BOX_H / 2 + 4}
        textAnchor="middle"
        fontFamily="inherit"
        fontSize={13}
        fontWeight={600}
        fill={INK}
        pointerEvents="none"
      >
        {mod.name}
      </text>

      {/* Subtle "highlighted" border on top of plum stroke when active */}
      {highlighted && (
        <rect
          x={x}
          y={y}
          width={BOX_W}
          height={BOX_H}
          rx={RX}
          ry={RX}
          fill="none"
          stroke={ORCHID}
          strokeWidth={2}
          pointerEvents="none"
        />
      )}
    </motion.g>
  );
}

// --------------------------------------------------------------------------
// Highlight underlay — drawn behind every box so the orchid glow reads as a
// halo rather than a frame.
// --------------------------------------------------------------------------
interface HighlightUnderlayProps {
  module: PipelineModule;
}

function HighlightUnderlay({ module: mod }: HighlightUnderlayProps) {
  const { x, y } = POSITIONS[mod.id];
  return (
    <rect
      x={x - HIGHLIGHT_PAD}
      y={y - HIGHLIGHT_PAD}
      width={BOX_W + HIGHLIGHT_PAD * 2}
      height={BOX_H + HIGHLIGHT_PAD * 2}
      rx={HIGHLIGHT_RX}
      ry={HIGHLIGHT_RX}
      fill="rgba(195, 79, 162, 0.15)"
      filter="url(#orchid-glow)"
      pointerEvents="none"
    />
  );
}

// --------------------------------------------------------------------------
// Arrow paths.  Each arrow is described as a list of (x,y) waypoints; we
// emit them as polyline-style `M ... L ...` commands.  The trailing arrow is
// drawn by the shared `<marker>`.
// --------------------------------------------------------------------------
interface ArrowProps {
  d: string;
  dashed?: boolean;
  label?: string;
  labelAt?: { x: number; y: number };
}

function Arrow({ d, dashed = false, label, labelAt }: ArrowProps) {
  return (
    <g>
      <path
        d={d}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        strokeDasharray={dashed ? '5 4' : undefined}
        opacity={dashed ? 0.7 : 1}
        markerEnd="url(#arrow-head)"
      />
      {label && labelAt && (
        <text
          x={labelAt.x}
          y={labelAt.y}
          fontFamily="inherit"
          fontSize={10}
          fill={INK}
          opacity={0.7}
        >
          {label}
        </text>
      )}
    </g>
  );
}

// Build an L-shaped path from (x1,y1) down to a waypoint y, across to x2,
// down to y2.  Used for the many vertical-then-horizontal-then-vertical
// arrows in this diagram.
function lShape(x1: number, y1: number, x2: number, y2: number, midY: number): string {
  return `M ${x1} ${y1} L ${x1} ${midY} L ${x2} ${midY} L ${x2} ${y2}`;
}

// --------------------------------------------------------------------------
// Public component.
// --------------------------------------------------------------------------
interface Props {
  highlightedFeatureIds?: string[];
  onSelect: (moduleId: string) => void;
}

export function ArchDiagram({ highlightedFeatureIds = [], onSelect }: Props) {
  // Memoize the highlighted-module list so the underlay layer only re-walks
  // when the prop changes.
  const highlightedModules = useMemo(
    () => MODULES.filter((m) => isHighlighted(m, highlightedFeatureIds)),
    [highlightedFeatureIds],
  );

  // Pre-computed arrow paths.  Mid-Y values are picked to leave the central
  // spine clear and to avoid boxes.
  const arrows: ArrowProps[] = [
    // I-Cache -> Fetch (right-then-up into Fetch top)
    { d: lShape(right('icache'), top('icache') + BOX_H / 2, cx('fetch') - BOX_W / 2 - 8, top('fetch') + BOX_H / 2, top('fetch') + BOX_H / 2) },
    // Branch Predictor -> Fetch (left-then into Fetch right edge)
    { d: lShape(POSITIONS['branch-predictor'].x, top('branch-predictor') + BOX_H / 2, right('fetch') + 8, top('fetch') + BOX_H / 2, top('branch-predictor') + BOX_H / 2) },
    // Fetch -> Decode
    { d: `M ${cx('fetch')} ${bottom('fetch')} L ${cx('decode')} ${top('decode')}` },
    // Decode -> ROB+RAT
    { d: `M ${cx('decode')} ${bottom('decode')} L ${cx('rob')} ${top('rob')}` },
    // ROB+RAT -> RS (left fork)
    { d: lShape(cx('rob'), bottom('rob'), cx('rs'), top('rs'), bottom('rob') + 50) },
    // ROB+RAT -> LSQ (right fork)
    { d: lShape(cx('rob'), bottom('rob'), cx('lsq'), top('lsq'), bottom('rob') + 50) },
    // RS -> ALU
    { d: lShape(cx('rs'), bottom('rs'), cx('alu'), top('alu'), bottom('rs') + 50) },
    // RS -> MULT
    { d: `M ${cx('mult')} ${bottom('rs')} L ${cx('mult')} ${top('mult')}` },
    // RS -> Branch Resolver
    { d: lShape(cx('rs'), bottom('rs'), cx('branch-resolver'), top('branch-resolver'), bottom('rs') + 50) },
    // LSQ -> D-Cache
    { d: lShape(cx('lsq'), bottom('lsq'), cx('dcache'), top('dcache'), bottom('lsq') + 50) },
    // ALU -> CDB
    { d: lShape(cx('alu'), bottom('alu'), cx('cdb'), top('cdb'), bottom('alu') + 50) },
    // MULT -> CDB
    { d: lShape(cx('mult'), bottom('mult'), cx('cdb'), top('cdb'), bottom('mult') + 50) },
    // Branch Resolver -> CDB
    { d: `M ${cx('branch-resolver')} ${bottom('branch-resolver')} L ${cx('cdb')} ${top('cdb')}` },
    // D-Cache -> CDB
    { d: lShape(cx('dcache'), bottom('dcache'), cx('cdb'), top('cdb'), bottom('dcache') + 50) },
    // CDB -> Commit
    { d: `M ${cx('cdb')} ${bottom('cdb')} L ${cx('commit')} ${top('commit')}` },
    // CDB -> ROB+RAT (writeback feedback) — dashed, runs along right side.
    {
      d: `M ${right('cdb')} ${top('cdb') + BOX_H / 2} L ${right('cdb') + 60} ${top('cdb') + BOX_H / 2} L ${right('cdb') + 60} ${top('rob') + BOX_H / 2} L ${right('rob')} ${top('rob') + BOX_H / 2}`,
      dashed: true,
      label: 'writeback',
      labelAt: { x: right('cdb') + 65, y: (top('cdb') + top('rob')) / 2 + BOX_H / 2 - 2 },
    },
  ];

  return (
    <div className="w-full">
      <svg
        viewBox="0 0 1200 720"
        className="w-full h-auto"
        xmlns="http://www.w3.org/2000/svg"
        role="img"
        aria-label="Interactive architecture diagram of the out-of-order RV32IM processor"
      >
        <defs>
          {/* Arrowhead marker shared by every arrow. */}
          <marker
            id="arrow-head"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill={IRIS} />
          </marker>

          {/* Soft orchid glow used by the highlighted-feature underlay. */}
          <filter id="orchid-glow" x="-25%" y="-25%" width="150%" height="150%">
            <feGaussianBlur stdDeviation="4" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Layer 1: highlight underlays (behind everything else). */}
        <g>
          {highlightedModules.map((m) => (
            <HighlightUnderlay key={`hi-${m.id}`} module={m} />
          ))}
        </g>

        {/* Layer 2: arrows.  Drawn before boxes so an arrow that grazes a box
            edge is hidden behind the box rather than crossing on top of the
            label. */}
        <g>
          {arrows.map((arrow, i) => (
            <Arrow key={`arrow-${i}`} {...arrow} />
          ))}
        </g>

        {/* Layer 3: module boxes (interactive). */}
        <g>
          {MODULES.map((mod) => (
            <ModuleBox
              key={mod.id}
              module={mod}
              highlighted={isHighlighted(mod, highlightedFeatureIds)}
              onSelect={onSelect}
            />
          ))}
        </g>
      </svg>

      {/* Category legend */}
      <div className="mt-4 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-ink-muted">
        <LegendDot color="bg-plum-600" label="Frontend" />
        <LegendDot color="bg-iris-500" label="Backend" />
        <LegendDot color="bg-sky-500" label="Memory" />
        <LegendDot color="bg-orchid-500" label="Control" />
      </div>
    </div>
  );
}

interface LegendDotProps {
  color: string;
  label: string;
}

function LegendDot({ color, label }: LegendDotProps) {
  return (
    <span className="inline-flex items-center gap-2">
      <span className={`inline-block h-3 w-3 rounded-full ${color}`} aria-hidden />
      <span>{label}</span>
    </span>
  );
}
