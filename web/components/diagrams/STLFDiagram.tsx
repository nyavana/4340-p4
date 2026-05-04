// STLFDiagram — store-to-load forwarding (Figure 4 in the report).
//
// Ground truth: verilog/lsq.sv  (LSQ_SZ = 8 from verilog/sys_defs.svh).
// The LSQ walks older entries oldest-to-youngest looking for a store on
// the same 8-byte line whose byte mask fully covers the load's byte
// range and whose data is already known.  When that store is found, its
// data is muxed in for the load completion value; otherwise the load
// falls back to the D-cache return.  A one-cycle latch sits between the
// forwarding compare and the CDB broadcast (lsq.sv step 3.5) so the
// forwarded load travels the same registered fast path as a cache hit.
// No RTL/report disagreement to flag.

const PLUM = '#77295D';
const ORCHID = '#C34FA2';
const IRIS = '#5364C0';
const RED = '#DC2626';
const INK = '#241B2A';
const PLUM_50 = '#F4E7EE';
const SNOW = '#EDF1FD';

const LSQ_ENTRIES = 8;
const ENTRY_W = 64;
const ENTRY_H = 44;
const ENTRY_GAP = 6;
const FIFO_X = 60;
const FIFO_Y = 50;
const HEAD_INDEX = 0;

const COMPARATOR_X = 110;
const COMPARATOR_Y = 200;
const COMPARATOR_W = 360;
const COMPARATOR_H = 90;

const MUX_X = 600;
const MUX_Y = 215;
const MUX_W = 90;
const MUX_H = 110;

export function STLFDiagram() {
  const fifoEntries = Array.from({ length: LSQ_ENTRIES }, (_, i) => i);
  const entryX = (i: number) => FIFO_X + i * (ENTRY_W + ENTRY_GAP);

  // Older stores: indices 1..6 are older than the load at head (index 0
  // in this drawing, which is "head on the left").  In the RTL, "older"
  // is the strict prefix of the LSQ ahead of the load; the diagram
  // labels the indices L/S generically.  The dotted comparator inputs
  // represent the address comparator fanning out across older entries.
  const headCenterX = entryX(HEAD_INDEX) + ENTRY_W / 2;
  const headBottomY = FIFO_Y + ENTRY_H;

  return (
    <svg
      viewBox="0 0 800 460"
      className="w-full h-auto"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Store-to-load forwarding: LSQ FIFO, address comparator over older stores, and the mux that selects between forwarded store data and the D-cache return."
    >
      <defs>
        <marker
          id="stlf-arrow-iris"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M0,0 L10,5 L0,10 z" fill={IRIS} />
        </marker>
        <marker
          id="stlf-arrow-orchid"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M0,0 L10,5 L0,10 z" fill={ORCHID} />
        </marker>
      </defs>

      {/* Title */}
      <text
        x={400}
        y={24}
        textAnchor="middle"
        fontSize={14}
        fontWeight={600}
        fill={INK}
      >
        Store-to-Load Forwarding (LSQ, 8 entries)
      </text>

      {/* "head" label + arrow on the head entry */}
      <text
        x={entryX(HEAD_INDEX) + ENTRY_W / 2}
        y={FIFO_Y - 18}
        textAnchor="middle"
        fontSize={11}
        fontWeight={600}
        fill={PLUM}
      >
        head (load)
      </text>
      <line
        x1={entryX(HEAD_INDEX) + ENTRY_W / 2}
        y1={FIFO_Y - 12}
        x2={entryX(HEAD_INDEX) + ENTRY_W / 2}
        y2={FIFO_Y - 2}
        stroke={PLUM}
        strokeWidth={1.5}
        markerEnd="url(#stlf-arrow-iris)"
      />

      {/* "older stores" bracket spanning entries 1..6 */}
      <text
        x={(entryX(1) + entryX(6) + ENTRY_W) / 2}
        y={FIFO_Y - 18}
        textAnchor="middle"
        fontSize={11}
        fill={INK}
      >
        older entries (scanned for matching stores)
      </text>

      {/* "tail" label */}
      <text
        x={entryX(LSQ_ENTRIES - 1) + ENTRY_W / 2}
        y={FIFO_Y - 4}
        textAnchor="middle"
        fontSize={10}
        fill={INK}
        opacity={0.7}
      >
        tail →
      </text>

      {/* LSQ FIFO row */}
      {fifoEntries.map((i) => {
        const isHead = i === HEAD_INDEX;
        return (
          <g key={`entry-${i}`}>
            <rect
              x={entryX(i)}
              y={FIFO_Y}
              width={ENTRY_W}
              height={ENTRY_H}
              rx={4}
              fill={isHead ? PLUM_50 : 'white'}
              stroke={PLUM}
              strokeWidth={1.5}
            />
            <text
              x={entryX(i) + ENTRY_W / 2}
              y={FIFO_Y + 18}
              textAnchor="middle"
              fontSize={11}
              fontWeight={isHead ? 600 : 500}
              fill={INK}
            >
              {isHead ? 'LD' : i % 2 === 0 ? 'ST' : 'LD'}
            </text>
            <text
              x={entryX(i) + ENTRY_W / 2}
              y={FIFO_Y + 33}
              textAnchor="middle"
              fontSize={9}
              fill={INK}
              opacity={0.6}
            >
              addr
            </text>
          </g>
        );
      })}

      {/* Comparator block (orchid pink — STLF-specific) */}
      <g>
        {/* trapezoid */}
        <path
          d={`M ${COMPARATOR_X},${COMPARATOR_Y}
              L ${COMPARATOR_X + COMPARATOR_W},${COMPARATOR_Y}
              L ${COMPARATOR_X + COMPARATOR_W - 30},${COMPARATOR_Y + COMPARATOR_H}
              L ${COMPARATOR_X + 30},${COMPARATOR_Y + COMPARATOR_H} z`}
          fill="white"
          stroke={ORCHID}
          strokeWidth={1.5}
        />
        <text
          x={COMPARATOR_X + COMPARATOR_W / 2}
          y={COMPARATOR_Y + 28}
          textAnchor="middle"
          fontSize={12}
          fontWeight={600}
          fill={ORCHID}
        >
          address comparator
        </text>
        <text
          x={COMPARATOR_X + COMPARATOR_W / 2}
          y={COMPARATOR_Y + 46}
          textAnchor="middle"
          fontSize={10}
          fill={INK}
        >
          same 8-byte line? full byte-mask cover?
        </text>
        <text
          x={COMPARATOR_X + COMPARATOR_W / 2}
          y={COMPARATOR_Y + 62}
          textAnchor="middle"
          fontSize={10}
          fill={INK}
          opacity={0.75}
        >
          walk older stores oldest → youngest
        </text>
        <text
          x={COMPARATOR_X + COMPARATOR_W / 2}
          y={COMPARATOR_Y + 78}
          textAnchor="middle"
          fontSize={10}
          fill={INK}
          opacity={0.75}
        >
          (youngest matching store wins)
        </text>
      </g>

      {/* Head load address feed: head entry → comparator (solid iris) */}
      <line
        x1={headCenterX}
        y1={headBottomY}
        x2={headCenterX}
        y2={COMPARATOR_Y}
        stroke={IRIS}
        strokeWidth={1.5}
        markerEnd="url(#stlf-arrow-iris)"
      />
      <text
        x={headCenterX - 6}
        y={(headBottomY + COMPARATOR_Y) / 2}
        textAnchor="end"
        fontSize={10}
        fill={IRIS}
      >
        load addr
      </text>

      {/* Older-store address fanout into the comparator (dotted) */}
      {[1, 2, 3, 4, 5, 6].map((i) => {
        const x1 = entryX(i) + ENTRY_W / 2;
        const y1 = headBottomY;
        const targetX =
          COMPARATOR_X + 30 + ((i - 1) / 5) * (COMPARATOR_W - 60);
        return (
          <line
            key={`older-${i}`}
            x1={x1}
            y1={y1}
            x2={targetX}
            y2={COMPARATOR_Y}
            stroke={ORCHID}
            strokeWidth={1}
            strokeDasharray="3 3"
            opacity={0.7}
          />
        );
      })}
      <text
        x={COMPARATOR_X + COMPARATOR_W / 2 + 110}
        y={COMPARATOR_Y - 6}
        textAnchor="middle"
        fontSize={9}
        fill={ORCHID}
        opacity={0.85}
      >
        older store addresses (dotted)
      </text>

      {/* Forwarding mux (orchid pink — STLF-specific) */}
      <g>
        <path
          d={`M ${MUX_X},${MUX_Y}
              L ${MUX_X + MUX_W},${MUX_Y + 18}
              L ${MUX_X + MUX_W},${MUX_Y + MUX_H - 18}
              L ${MUX_X},${MUX_Y + MUX_H} z`}
          fill="white"
          stroke={ORCHID}
          strokeWidth={1.5}
        />
        <text
          x={MUX_X + MUX_W / 2 - 5}
          y={MUX_Y + MUX_H / 2 + 4}
          textAnchor="middle"
          fontSize={12}
          fontWeight={600}
          fill={ORCHID}
        >
          mux
        </text>
        {/* input labels */}
        <text x={MUX_X - 4} y={MUX_Y + 22} textAnchor="end" fontSize={10} fill={INK}>
          0
        </text>
        <text
          x={MUX_X - 4}
          y={MUX_Y + MUX_H - 14}
          textAnchor="end"
          fontSize={10}
          fill={INK}
        >
          1
        </text>
      </g>

      {/* D-cache return path → mux input 0 */}
      <g>
        <rect
          x={420}
          y={MUX_Y + 6}
          width={120}
          height={28}
          rx={4}
          fill="white"
          stroke={PLUM}
          strokeWidth={1.5}
        />
        <text
          x={480}
          y={MUX_Y + 24}
          textAnchor="middle"
          fontSize={11}
          fontWeight={500}
          fill={INK}
        >
          D-cache return
        </text>
        <line
          x1={540}
          y1={MUX_Y + 20}
          x2={MUX_X}
          y2={MUX_Y + 20}
          stroke={IRIS}
          strokeWidth={1.5}
          markerEnd="url(#stlf-arrow-iris)"
        />
      </g>

      {/* Forwarded store data path: comparator → mux input 1 (orchid) */}
      <g>
        <path
          d={`M ${COMPARATOR_X + COMPARATOR_W - 30},${COMPARATOR_Y + COMPARATOR_H - 8}
              C ${COMPARATOR_X + COMPARATOR_W + 30},${COMPARATOR_Y + COMPARATOR_H - 8}
                ${MUX_X - 30},${MUX_Y + MUX_H - 22}
                ${MUX_X},${MUX_Y + MUX_H - 22}`}
          fill="none"
          stroke={ORCHID}
          strokeWidth={1.5}
          markerEnd="url(#stlf-arrow-orchid)"
        />
        <text
          x={MUX_X - 8}
          y={MUX_Y + MUX_H - 30}
          textAnchor="end"
          fontSize={10}
          fontWeight={500}
          fill={ORCHID}
        >
          forwarded store data
        </text>
      </g>

      {/* select line into mux (from comparator: "did we forward?") */}
      <line
        x1={COMPARATOR_X + COMPARATOR_W / 2}
        y1={COMPARATOR_Y + COMPARATOR_H}
        x2={COMPARATOR_X + COMPARATOR_W / 2}
        y2={COMPARATOR_Y + COMPARATOR_H + 28}
        stroke={ORCHID}
        strokeWidth={1.2}
        strokeDasharray="4 3"
      />
      <text
        x={COMPARATOR_X + COMPARATOR_W / 2}
        y={COMPARATOR_Y + COMPARATOR_H + 42}
        textAnchor="middle"
        fontSize={10}
        fill={ORCHID}
      >
        select = stlf_ready[head]
      </text>

      {/* Mux output → STLF latch → CDB */}
      <g>
        <line
          x1={MUX_X + MUX_W}
          y1={MUX_Y + MUX_H / 2}
          x2={MUX_X + MUX_W + 18}
          y2={MUX_Y + MUX_H / 2}
          stroke={IRIS}
          strokeWidth={1.5}
        />
        {/* 1-cycle latch (small register box) */}
        <rect
          x={MUX_X + MUX_W + 18}
          y={MUX_Y + MUX_H / 2 - 18}
          width={48}
          height={36}
          rx={4}
          fill="white"
          stroke={PLUM}
          strokeWidth={1.5}
        />
        <text
          x={MUX_X + MUX_W + 18 + 24}
          y={MUX_Y + MUX_H / 2 - 2}
          textAnchor="middle"
          fontSize={10}
          fontWeight={600}
          fill={INK}
        >
          load_buf
        </text>
        <text
          x={MUX_X + MUX_W + 18 + 24}
          y={MUX_Y + MUX_H / 2 + 10}
          textAnchor="middle"
          fontSize={9}
          fill={INK}
          opacity={0.7}
        >
          (1-cycle)
        </text>
        <line
          x1={MUX_X + MUX_W + 66}
          y1={MUX_Y + MUX_H / 2}
          x2={MUX_X + MUX_W + 96}
          y2={MUX_Y + MUX_H / 2}
          stroke={IRIS}
          strokeWidth={1.5}
          markerEnd="url(#stlf-arrow-iris)"
        />
        <text
          x={MUX_X + MUX_W + 96}
          y={MUX_Y + MUX_H / 2 - 8}
          textAnchor="end"
          fontSize={10}
          fontWeight={600}
          fill={INK}
        >
          → CDB
        </text>
        <text
          x={MUX_X + MUX_W + 96}
          y={MUX_Y + MUX_H / 2 + 14}
          textAnchor="end"
          fontSize={9}
          fill={INK}
          opacity={0.7}
        >
          load completion value
        </text>
      </g>

      {/* Blocking-condition annotations (red ✗) */}
      <g transform={`translate(20, ${COMPARATOR_Y + COMPARATOR_H + 60})`}>
        <rect
          x={0}
          y={0}
          width={430}
          height={86}
          rx={8}
          fill={SNOW}
          stroke={PLUM}
          strokeWidth={1}
          opacity={0.9}
        />
        <text x={12} y={18} fontSize={11} fontWeight={600} fill={INK}>
          Blocking conditions (load waits for cache):
        </text>

        <text x={20} y={38} fontSize={13} fontWeight={700} fill={RED}>
          ✗
        </text>
        <text x={36} y={38} fontSize={11} fill={INK}>
          older store with unresolved addr
        </text>

        <text x={20} y={56} fontSize={13} fontWeight={700} fill={RED}>
          ✗
        </text>
        <text x={36} y={56} fontSize={11} fill={INK}>
          older store data not yet arrived
        </text>

        <text x={20} y={74} fontSize={13} fontWeight={700} fill={RED}>
          ✗
        </text>
        <text x={36} y={74} fontSize={11} fill={INK}>
          partial overlap (load needs bytes store didn{'’'}t write)
        </text>
      </g>

      {/* Legend */}
      <g transform={`translate(470, ${COMPARATOR_Y + COMPARATOR_H + 60})`}>
        <rect
          x={0}
          y={0}
          width={310}
          height={86}
          rx={8}
          fill="white"
          stroke={PLUM}
          strokeWidth={1}
          opacity={0.95}
        />
        <text x={10} y={16} fontSize={10} fontWeight={600} fill={INK}>
          Legend
        </text>
        <rect x={10} y={24} width={14} height={10} fill={PLUM_50} stroke={PLUM} strokeWidth={1} />
        <text x={30} y={33} fontSize={10} fill={INK}>
          head load (LSQ entry)
        </text>
        <line x1={10} y1={48} x2={24} y2={48} stroke={ORCHID} strokeWidth={1.5} />
        <text x={30} y={51} fontSize={10} fill={INK}>
          STLF-specific (comparator, mux)
        </text>
        <line x1={10} y1={64} x2={24} y2={64} stroke={IRIS} strokeWidth={1.5} />
        <text x={30} y={67} fontSize={10} fill={INK}>
          data path (load addr, mux output)
        </text>
        <text x={10} y={81} fontSize={13} fontWeight={700} fill={RED}>
          ✗
        </text>
        <text x={26} y={81} fontSize={10} fill={INK}>
          condition that blocks the forward
        </text>
      </g>
    </svg>
  );
}
