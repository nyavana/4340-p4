// Branch predictor diagram — Figure 2.
//
// Sourced from `verilog/branch_predictor.sv` and cross-referenced with
// the final report §V.C.  RTL confirms:
//   - BTB:  32 entries, PC[6:2] index, PC[31:7] tag.
//   - BHT:  64 entries, 2-bit saturating counters, indexed by
//           PC[7:2] XOR GHR[5:0]  (gshare fold).
//   - GHR:  6 bits wide (matches BHT index width).
//   - RAS:  16 entries, circular stack.
// RTL matches the report.

const PLUM = '#77295D';
const ORCHID = '#C34FA2';
const IRIS = '#5364C0';
const INK = '#241B2A';

export function BranchPredictorDiagram() {
  return (
    <svg
      viewBox="0 0 800 460"
      className="w-full h-auto"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Branch predictor block diagram: BTB, gshare BHT with GHR XOR fold, and RAS stack feeding an output mux."
    >
      <defs>
        {/* Iris-blue arrowhead for normal data-flow arrows. */}
        <marker
          id="bp-arrow-iris"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={IRIS} />
        </marker>
        {/* Orchid-pink arrowhead for highlighted (gshare / RAS-override) paths. */}
        <marker
          id="bp-arrow-orchid"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={ORCHID} />
        </marker>
      </defs>

      {/* ------------------------------------------------------------ */}
      {/* Fetch PC (input)                                             */}
      {/* ------------------------------------------------------------ */}
      <g>
        <rect
          x="20"
          y="200"
          width="130"
          height="50"
          rx="8"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="85"
          y="223"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          Fetch PC
        </text>
        <text x="85" y="240" textAnchor="middle" fontSize="11" fill={INK}>
          predict_PC[31:0]
        </text>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* PC fan-out: a junction dot at x=180, then three branches.    */}
      {/* ------------------------------------------------------------ */}
      <line
        x1="150"
        y1="225"
        x2="180"
        y2="225"
        stroke={IRIS}
        strokeWidth="1.5"
      />
      <circle cx="180" cy="225" r="3" fill={IRIS} />

      {/* PC -> BTB (top branch) */}
      <path
        d="M 180 225 L 180 90 L 290 90"
        fill="none"
        stroke={IRIS}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-iris)"
      />
      <text x="195" y="80" fontSize="10" fill={INK}>
        PC[6:2] index, PC[31:7] tag
      </text>

      {/* PC -> XOR (middle branch) — orchid because this is the gshare fold */}
      <path
        d="M 180 225 L 245 225"
        fill="none"
        stroke={ORCHID}
        strokeWidth="1.5"
      />
      <text x="188" y="218" fontSize="10" fill={INK}>
        PC[7:2]
      </text>

      {/* PC -> RAS (bottom branch) */}
      <path
        d="M 180 225 L 180 360 L 290 360"
        fill="none"
        stroke={IRIS}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-iris)"
      />
      <text x="195" y="378" fontSize="10" fill={INK}>
        is_return / push / pop
      </text>

      {/* ------------------------------------------------------------ */}
      {/* BTB                                                          */}
      {/* ------------------------------------------------------------ */}
      <g>
        <rect
          x="290"
          y="60"
          width="190"
          height="70"
          rx="8"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="385"
          y="84"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          BTB (32 entries)
        </text>
        <text x="385" y="103" textAnchor="middle" fontSize="11" fill={INK}>
          {'{valid, tag, target, is_uncond}'}
        </text>
        <text x="385" y="119" textAnchor="middle" fontSize="11" fill={INK}>
          direct-mapped, PC[6:2] index
        </text>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* gshare XOR symbol  (highlighted in orchid)                   */}
      {/* ------------------------------------------------------------ */}
      <g>
        <circle
          cx="265"
          cy="225"
          r="20"
          fill="white"
          stroke={ORCHID}
          strokeWidth="1.5"
        />
        {/* + sign inside the circle */}
        <line
          x1="265"
          y1="210"
          x2="265"
          y2="240"
          stroke={ORCHID}
          strokeWidth="1.5"
        />
        <line
          x1="250"
          y1="225"
          x2="280"
          y2="225"
          stroke={ORCHID}
          strokeWidth="1.5"
        />
        <text
          x="265"
          y="265"
          textAnchor="middle"
          fontSize="10"
          fontWeight="600"
          fill={ORCHID}
        >
          gshare XOR
        </text>
      </g>

      {/* GHR -> XOR (orchid, gshare-specific) */}
      <path
        d="M 175 295 L 175 225 L 245 225"
        fill="none"
        stroke={ORCHID}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-orchid)"
      />
      <text x="100" y="290" fontSize="10" fill={INK}>
        GHR[5:0]
      </text>

      {/* XOR -> BHT */}
      <path
        d="M 285 225 L 320 225"
        fill="none"
        stroke={ORCHID}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-orchid)"
      />
      <text x="288" y="218" fontSize="10" fill={INK}>
        idx[5:0]
      </text>

      {/* ------------------------------------------------------------ */}
      {/* BHT                                                          */}
      {/* ------------------------------------------------------------ */}
      <g>
        <rect
          x="320"
          y="190"
          width="190"
          height="70"
          rx="8"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="415"
          y="214"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          BHT (64 entries)
        </text>
        <text x="415" y="233" textAnchor="middle" fontSize="11" fill={INK}>
          2-bit saturating counters
        </text>
        <text x="415" y="249" textAnchor="middle" fontSize="11" fill={INK}>
          taken if counter[1] = 1
        </text>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* GHR shift register                                           */}
      {/* ------------------------------------------------------------ */}
      <g>
        <rect
          x="80"
          y="295"
          width="160"
          height="50"
          rx="8"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="160"
          y="318"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          GHR (6-bit shift reg)
        </text>
        <text x="160" y="335" textAnchor="middle" fontSize="11" fill={INK}>
          updated on cond. commit
        </text>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* RAS — drawn as a stack of small rectangles                   */}
      {/* ------------------------------------------------------------ */}
      <g>
        <rect
          x="290"
          y="320"
          width="190"
          height="100"
          rx="8"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="385"
          y="342"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          RAS (16 entries)
        </text>
        {/* mini stack icon: 4 stacked rectangles, top one is "top" */}
        <g>
          {/* top of stack — highlighted because it's what feeds the override */}
          <rect
            x="320"
            y="352"
            width="60"
            height="12"
            fill="white"
            stroke={ORCHID}
            strokeWidth="1.5"
          />
          <rect
            x="320"
            y="368"
            width="60"
            height="12"
            fill="white"
            stroke={PLUM}
            strokeWidth="1"
          />
          <rect
            x="320"
            y="384"
            width="60"
            height="12"
            fill="white"
            stroke={PLUM}
            strokeWidth="1"
          />
          <rect
            x="320"
            y="400"
            width="60"
            height="12"
            fill="white"
            stroke={PLUM}
            strokeWidth="1"
          />
          <text
            x="395"
            y="362"
            fontSize="10"
            fontWeight="600"
            fill={ORCHID}
          >
            ← top (sp-1)
          </text>
          <text x="395" y="395" fontSize="10" fill={INK}>
            circular,
          </text>
          <text x="395" y="408" fontSize="10" fill={INK}>
            speculative-only
          </text>
        </g>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* Output mux — selects between BTB target and RAS top          */}
      {/* ------------------------------------------------------------ */}
      <g>
        {/* Trapezoid mux shape */}
        <path
          d="M 600 100 L 660 130 L 660 330 L 600 360 Z"
          fill="white"
          stroke={PLUM}
          strokeWidth="1.5"
        />
        <text
          x="630"
          y="225"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill={INK}
        >
          mux
        </text>
        <text x="630" y="243" textAnchor="middle" fontSize="10" fill={INK}>
          ras_override?
        </text>
      </g>

      {/* BTB -> mux (taken / target / is_uncond) */}
      <path
        d="M 480 95 L 600 130"
        fill="none"
        stroke={IRIS}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-iris)"
      />
      <text x="495" y="115" fontSize="10" fill={INK}>
        BTB target
      </text>

      {/* BHT counter -> mux (carries the taken bit through the BTB-side path) */}
      <path
        d="M 510 215 L 600 195"
        fill="none"
        stroke={IRIS}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-iris)"
      />
      <text x="515" y="208" fontSize="10" fill={INK}>
        taken (counter[1])
      </text>

      {/* RAS top -> mux (RAS-OVERRIDE PATH, orchid highlight) */}
      <path
        d="M 480 358 L 600 330"
        fill="none"
        stroke={ORCHID}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-orchid)"
      />
      <text x="490" y="378" fontSize="10" fontWeight="600" fill={ORCHID}>
        RAS top (override)
      </text>

      {/* ------------------------------------------------------------ */}
      {/* Outputs                                                      */}
      {/* ------------------------------------------------------------ */}
      <path
        d="M 660 230 L 760 230"
        fill="none"
        stroke={IRIS}
        strokeWidth="1.5"
        markerEnd="url(#bp-arrow-iris)"
      />
      <g>
        <text x="673" y="200" fontSize="11" fontWeight="600" fill={INK}>
          pred_target
        </text>
        <text x="673" y="222" fontSize="11" fontWeight="600" fill={INK}>
          pred_taken
        </text>
        <text x="673" y="258" fontSize="11" fontWeight="600" fill={INK}>
          pred_is_uncond
        </text>
      </g>

      {/* ------------------------------------------------------------ */}
      {/* Caption                                                      */}
      {/* ------------------------------------------------------------ */}
      <text x="20" y="440" fontSize="11" fill={INK}>
        <tspan fontWeight="600">Highlighted in pink:</tspan> the gshare XOR
        fold (PC[7:2] ⊕ GHR[5:0]) and the RAS-override path that bypasses
        the BTB on detected returns.
      </text>
    </svg>
  );
}
