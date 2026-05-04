// PipelineOverviewDiagram.tsx
//
// Static, non-interactive overview of the full out-of-order RV32IM pipeline.
// Used in /deep-dive §3 (Architecture overview).  Same topology as the
// landing-page interactive ArchDiagram, but stripped of interaction, side
// panels, and feature-toggle highlights.
//
// Topology grounded in verilog/pipeline.sv (the RTL is the source of truth):
//   - 1 ICache + 1 Stream Buffer + 1 Branch Predictor feed Fetch
//   - 1 Decode stage (2-wide)
//   - 1 ROB (RAT lives inside it) feeding both RS and LSQ at dispatch
//   - 1 Reservation Station (2-wide issue) drives ALU0, ALU1, MULT
//   - 1 LSQ (FIFO, head-only) drives the D-Cache
//   - 1 MULT (5-stage, with early-tag broadcast)
//   - Branch resolution happens inside the two ALUs (the GEN_ALU loop in
//     pipeline.sv computes branch_take alongside alu_result), not as a
//     dedicated FU.  We still draw a "Branch Resolver" box for pedagogical
//     clarity — it is conceptually distinct from arithmetic ops and the
//     report describes it that way.
//   - 2-slot CDB with priority MULT > LD > ALU per slot
//   - 2-wide commit into the architectural regfile
//
// {/* NOTE: RTL has a Stream Buffer only on the I-cache side (sb_0 wired to
//     proc2Pmem_*).  The PRD topology lists a Stream Buffer on the D-cache;
//     RTL wins, so this diagram shows the prefetcher only on the I-cache. */}

const PLUM = '#77295D';
const IRIS = '#5364C0';
const INK = '#241B2A';
const WHITE = '#FFFFFF';

// Layout constants.  All coordinates are in the 800x560 viewBox.
const BOX_W = 150;
const BOX_W_NARROW = 110;
const BOX_W_WIDE = 200;
const BOX_H = 44;
const BOX_H_TALL = 56;
const RX = 8;
const STROKE_W = 1.5;

interface BoxProps {
  x: number;
  y: number;
  w: number;
  h?: number;
  label: string;
  sublabel?: string;
}

function Box({ x, y, w, h = BOX_H, label, sublabel }: BoxProps) {
  return (
    <g>
      <rect
        x={x}
        y={y}
        width={w}
        height={h}
        rx={RX}
        ry={RX}
        fill={WHITE}
        stroke={PLUM}
        strokeWidth={STROKE_W}
      />
      <text
        x={x + w / 2}
        y={sublabel ? y + h / 2 - 2 : y + h / 2 + 4}
        textAnchor="middle"
        fontFamily="inherit"
        fontSize={13}
        fontWeight={600}
        fill={INK}
      >
        {label}
      </text>
      {sublabel && (
        <text
          x={x + w / 2}
          y={y + h / 2 + 13}
          textAnchor="middle"
          fontFamily="inherit"
          fontSize={11}
          fill={INK}
          opacity={0.75}
        >
          {sublabel}
        </text>
      )}
    </g>
  );
}

export function PipelineOverviewDiagram() {
  // Row Y-coordinates (top of each row of boxes).
  const yIcache = 16; // I-cache, branch predictor (top inputs to fetch)
  const yFetch = 92;
  const yDecode = 162;
  const yRob = 226; // dispatch + ROB (single wide box)
  const yIssueQ = 296; // RS / LSQ
  const yExec = 366; // ALU0, ALU1, MULT, Branch resolver, D-cache
  const yCdb = 432; // CDB (kept inside viewBox by overlap)

  // Column X-coordinates.
  // Top row: I-cache | Stream buffer | Branch predictor — left of center.
  const xICache = 70;
  const xStreamBuf = xICache + BOX_W + 20;
  const xPredictor = xStreamBuf + BOX_W + 20; // right side of top row

  // Center column for fetch/decode/ROB.
  const xCenter = (800 - BOX_W) / 2; // 325

  // ROB is wider so it can label "Dispatch + ROB (RAT inside)".
  const xRob = (800 - BOX_W_WIDE) / 2; // 300

  // RS on the left side of center; LSQ on the right side.
  const xRs = xCenter - 110;
  const xLsq = xCenter + 110;

  // Execution units: ALU0, ALU1, MULT, Branch resolver, D-cache.
  // Five units arranged across the width.
  const execGap = 12;
  const xAlu0 = 30;
  const xAlu1 = xAlu0 + BOX_W_NARROW + execGap;
  const xMult = xAlu1 + BOX_W_NARROW + execGap;
  const xBranch = xMult + BOX_W_NARROW + execGap;
  const xDcache = xBranch + BOX_W_NARROW + execGap;

  // CDB box (wide, centered).
  const xCdb = (800 - BOX_W_WIDE) / 2;

  // Centerline X of each unit (for arrow endpoints).
  const cx = (x: number, w: number = BOX_W) => x + w / 2;

  return (
    <svg
      viewBox="0 0 800 560"
      className="w-full h-auto"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Pipeline overview: 13-stage out-of-order RV32IM datapath"
    >
      {/* arrowhead marker */}
      <defs>
        <marker
          id="arrow"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={IRIS} />
        </marker>
      </defs>

      {/* ============================================================ */}
      {/* Boxes                                                         */}
      {/* ============================================================ */}

      {/* Top row: front-end inputs */}
      <Box x={xICache} y={yIcache} w={BOX_W} label="I-Cache" sublabel="2-way, 256 B" />
      <Box x={xStreamBuf} y={yIcache} w={BOX_W} label="Stream Buffer" sublabel="next-line prefetch" />
      <Box x={xPredictor} y={yIcache} w={BOX_W} label="Branch Predictor" sublabel="gshare + BTB + RAS" />

      {/* Fetch */}
      <Box x={xCenter} y={yFetch} w={BOX_W} label="Fetch" sublabel="2-wide" />

      {/* Decode */}
      <Box x={xCenter} y={yDecode} w={BOX_W} label="Decode" sublabel="2-wide" />

      {/* Dispatch + ROB */}
      <Box
        x={xRob}
        y={yRob}
        w={BOX_W_WIDE}
        h={BOX_H_TALL}
        label="Dispatch + ROB"
        sublabel="2-wide alloc, RAT inside"
      />

      {/* RS / LSQ */}
      <Box x={xRs} y={yIssueQ} w={BOX_W} label="Reservation Station" sublabel="2-wide issue" />
      <Box x={xLsq} y={yIssueQ} w={BOX_W} label="LSQ" sublabel="FIFO, head-only" />

      {/* Execution units */}
      <Box x={xAlu0} y={yExec} w={BOX_W_NARROW} label="ALU0" />
      <Box x={xAlu1} y={yExec} w={BOX_W_NARROW} label="ALU1" />
      <Box x={xMult} y={yExec} w={BOX_W_NARROW} label="MULT" sublabel="5-stage, ETB" />
      <Box x={xBranch} y={yExec} w={BOX_W_NARROW} label="Branch" sublabel="resolver" />
      <Box x={xDcache} y={yExec} w={BOX_W_NARROW} label="D-Cache" sublabel="2-way, 256 B" />

      {/* CDB */}
      <Box
        x={xCdb}
        y={yCdb}
        w={BOX_W_WIDE}
        label="CDB"
        sublabel="2 slots — MULT > LD > ALU per slot"
      />

      {/* Commit */}
      <Box
        x={xCdb}
        y={yCdb + BOX_H + 10}
        w={BOX_W_WIDE}
        label="Commit → Arch RegFile"
        sublabel="2-wide retire"
      />

      {/* ============================================================ */}
      {/* Arrows                                                        */}
      {/* ============================================================ */}

      {/* I-cache → Fetch */}
      <path
        d={`M ${cx(xICache)} ${yIcache + BOX_H} L ${cx(xICache)} ${yFetch - 12} L ${cx(xCenter)} ${yFetch - 12} L ${cx(xCenter)} ${yFetch}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Stream buffer → Fetch (cuts in from above) */}
      <path
        d={`M ${cx(xStreamBuf)} ${yIcache + BOX_H} L ${cx(xStreamBuf)} ${yFetch}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Branch predictor → Fetch (predicts next PC) */}
      <path
        d={`M ${cx(xPredictor)} ${yIcache + BOX_H} L ${cx(xPredictor)} ${yFetch - 12} L ${cx(xCenter) + BOX_W / 2 + 8} ${yFetch - 12} L ${cx(xCenter) + BOX_W / 2 + 8} ${yFetch + BOX_H / 2} L ${xCenter + BOX_W} ${yFetch + BOX_H / 2}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Fetch → Decode */}
      <path
        d={`M ${cx(xCenter)} ${yFetch + BOX_H} L ${cx(xCenter)} ${yDecode}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Decode → Dispatch+ROB */}
      <path
        d={`M ${cx(xCenter)} ${yDecode + BOX_H} L ${cx(xCenter)} ${yRob}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Dispatch+ROB → RS  (left fork) */}
      <path
        d={`M ${cx(xRob, BOX_W_WIDE)} ${yRob + BOX_H_TALL} L ${cx(xRob, BOX_W_WIDE)} ${yIssueQ - 14} L ${cx(xRs)} ${yIssueQ - 14} L ${cx(xRs)} ${yIssueQ}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Dispatch+ROB → LSQ  (right fork) */}
      <path
        d={`M ${cx(xRob, BOX_W_WIDE)} ${yRob + BOX_H_TALL} L ${cx(xRob, BOX_W_WIDE)} ${yIssueQ - 14} L ${cx(xLsq)} ${yIssueQ - 14} L ${cx(xLsq)} ${yIssueQ}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* RS → ALU0 / ALU1 / MULT / Branch  (fan-out from RS bottom) */}
      {[xAlu0, xAlu1, xMult, xBranch].map((xUnit) => (
        <path
          key={`rs-fanout-${xUnit}`}
          d={`M ${cx(xRs)} ${yIssueQ + BOX_H} L ${cx(xRs)} ${yExec - 14} L ${cx(xUnit, BOX_W_NARROW)} ${yExec - 14} L ${cx(xUnit, BOX_W_NARROW)} ${yExec}`}
          fill="none"
          stroke={IRIS}
          strokeWidth={STROKE_W}
          markerEnd="url(#arrow)"
        />
      ))}

      {/* LSQ → D-Cache */}
      <path
        d={`M ${cx(xLsq)} ${yIssueQ + BOX_H} L ${cx(xLsq)} ${yExec - 14} L ${cx(xDcache, BOX_W_NARROW)} ${yExec - 14} L ${cx(xDcache, BOX_W_NARROW)} ${yExec}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* All execution units → CDB (fan-in to centered CDB box) */}
      {[
        { x: xAlu0, w: BOX_W_NARROW },
        { x: xAlu1, w: BOX_W_NARROW },
        { x: xMult, w: BOX_W_NARROW },
        { x: xBranch, w: BOX_W_NARROW },
        { x: xDcache, w: BOX_W_NARROW },
      ].map((u) => (
        <path
          key={`exec-to-cdb-${u.x}`}
          d={`M ${cx(u.x, u.w)} ${yExec + BOX_H} L ${cx(u.x, u.w)} ${yCdb - 12} L ${cx(xCdb, BOX_W_WIDE)} ${yCdb - 12} L ${cx(xCdb, BOX_W_WIDE)} ${yCdb}`}
          fill="none"
          stroke={IRIS}
          strokeWidth={STROKE_W}
          markerEnd="url(#arrow)"
        />
      ))}

      {/* CDB → Commit */}
      <path
        d={`M ${cx(xCdb, BOX_W_WIDE)} ${yCdb + BOX_H} L ${cx(xCdb, BOX_W_WIDE)} ${yCdb + BOX_H + 10}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        markerEnd="url(#arrow)"
      />

      {/* Wakeup feedback: CDB → RS / LSQ (dashed back-edge on the right) */}
      <path
        d={`M ${xCdb + BOX_W_WIDE} ${yCdb + BOX_H / 2} L ${xCdb + BOX_W_WIDE + 30} ${yCdb + BOX_H / 2} L ${xCdb + BOX_W_WIDE + 30} ${yIssueQ + BOX_H / 2} L ${xLsq + BOX_W} ${yIssueQ + BOX_H / 2}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={STROKE_W}
        strokeDasharray="4 3"
        opacity={0.65}
        markerEnd="url(#arrow)"
      />
      <text
        x={xCdb + BOX_W_WIDE + 36}
        y={(yCdb + yIssueQ) / 2 + BOX_H / 2}
        fontFamily="inherit"
        fontSize={10}
        fill={INK}
        opacity={0.7}
      >
        wakeup
      </text>
    </svg>
  );
}
