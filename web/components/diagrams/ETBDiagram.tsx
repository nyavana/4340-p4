// Early Tag Broadcast (ETB) timing diagram — Figure 5.
//
// Sourced from `verilog/mult.sv` and `verilog/pipeline.sv` and
// cross-referenced with the final report §V.B.
//
// RTL ground truth (mult.sv):
//   - The early-tag tap is `internal_dones[`MULT_STAGES-2]`, i.e. the
//     `done` flop of the second-to-last multiplier stage. It rises
//     exactly one cycle before the final `done` lands on the CDB.
//   - mult.sv enforces `MULT_STAGES >= 2` at elab time so the tap is
//     well-defined.
// Pipeline gating (pipeline.sv ~L1099):
//   `early_cdb_valid = mult_early_done && !mult_flushed && !mispredict_valid`.
//   The wakeup wire is killed on flush / branch misprediction; we don't
//   draw the gating but it is reflected in the comment above.
//
// RTL/report disagreement note:
//   `verilog/sys_defs.svh` defines `MULT_STAGES` as **8** (not 5).
//   The CLAUDE.md summary and several report passages describe the
//   multiplier as "5-stage", which corresponds to an earlier sweep
//   value rather than the shipped configuration. The diagram shows 5
//   schematic boxes (stage 0..stage 4) for legibility — the tap-at-N-1
//   relationship and the 1-cycle savings hold for any MULT_STAGES >= 2,
//   so the schematic stays correct. If the report is updated to match
//   the shipped config, this diagram still tells the right story; only
//   the box count would change.

const PLUM = '#77295D';
const ORCHID = '#C34FA2';
const ORCHID_50 = '#F9EDF6';
const IRIS = '#5364C0';
const INK = '#241B2A';

export function ETBDiagram() {
  // ------------------------------------------------------------
  // Top panel layout (pipeline structure)
  // ------------------------------------------------------------
  // Five schematic stages, evenly spaced across the canvas.
  const stageY = 170;
  const stageH = 56;
  const stageW = 96;
  const stageGap = 20;
  const stageStartX = 60;
  const stageCount = 5;
  const stages = Array.from({ length: stageCount }, (_, i) => ({
    x: stageStartX + i * (stageW + stageGap),
    label: `stage ${i}`,
    isTap: i === stageCount - 2, // stage N-1 (second-to-last)
  }));
  const lastStage = stages[stageCount - 1];
  const tapStage = stages[stageCount - 2];
  const tapX = tapStage.x + stageW / 2;
  const tapY = stageY; // top edge of the tap stage

  // RS wakeup box (top-right).
  const rsBoxX = 600;
  const rsBoxY = 70;
  const rsBoxW = 170;
  const rsBoxH = 56;

  // CDB broadcast box (bottom-right of top panel).
  const cdbBoxX = 600;
  const cdbBoxY = 270;
  const cdbBoxW = 170;
  const cdbBoxH = 56;

  // ------------------------------------------------------------
  // Bottom panel layout (timing chart)
  // ------------------------------------------------------------
  const gridLeft = 230;
  const gridTop = 400;
  const cellW = 110;
  const cellH = 28;
  const cycleLabels = ['cycle N-1', 'cycle N', 'cycle N+1', 'cycle N+2'];
  const events = [
    { label: 'MULT enters stage 4', firesAt: 1 }, // cycle N
    { label: 'Early-tag wire fires', firesAt: 1, highlight: true }, // cycle N
    { label: 'RS ready bit flips (registered)', firesAt: 2 }, // cycle N+1
    { label: 'CDB broadcasts value, dependent issues', firesAt: 2 }, // cycle N+1
  ];

  return (
    <svg
      viewBox="0 0 800 540"
      className="w-full h-auto"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Early tag broadcast timing diagram: 5-stage pipelined multiplier with an early-tag tap at the second-to-last stage feeding RS wakeup logic, plus a 4-cycle timing chart showing the 1-cycle savings."
    >
      <defs>
        {/* Iris-blue arrowhead for normal data-flow arrows. */}
        <marker
          id="etb-arrow-iris"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={IRIS} />
        </marker>
        {/* Orchid-pink arrowhead for the highlighted early-tag wire. */}
        <marker
          id="etb-arrow-orchid"
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

      {/* ============================================================ */}
      {/* TOP PANEL — pipeline structure                                */}
      {/* ============================================================ */}

      {/* Panel title */}
      <text
        x="400"
        y="32"
        textAnchor="middle"
        fontSize="14"
        fontWeight="600"
        fill={INK}
      >
        Pipelined multiplier with early-tag tap
      </text>

      {/* "multiply enters" input label + arrow into stage 0 */}
      <text x={stageStartX - 6} y={stageY - 12} textAnchor="end" fontSize="11" fill={INK}>
        multiply enters
      </text>
      <line
        x1={stageStartX - 40}
        y1={stageY + stageH / 2}
        x2={stageStartX - 4}
        y2={stageY + stageH / 2}
        stroke={IRIS}
        strokeWidth={1.5}
        markerEnd="url(#etb-arrow-iris)"
      />

      {/* Five stage boxes + connecting arrows */}
      {stages.map((s, i) => (
        <g key={s.label}>
          <rect
            x={s.x}
            y={stageY}
            width={stageW}
            height={stageH}
            rx={8}
            ry={8}
            fill="white"
            stroke={PLUM}
            strokeWidth={1.5}
          />
          <text
            x={s.x + stageW / 2}
            y={stageY + stageH / 2 + 4}
            textAnchor="middle"
            fontSize="12"
            fill={INK}
          >
            {s.label}
          </text>
          {/* Connector arrow to next stage */}
          {i < stageCount - 1 && (
            <line
              x1={s.x + stageW}
              y1={stageY + stageH / 2}
              x2={stages[i + 1].x - 4}
              y2={stageY + stageH / 2}
              stroke={IRIS}
              strokeWidth={1.5}
              markerEnd="url(#etb-arrow-iris)"
            />
          )}
        </g>
      ))}

      {/* Early-tag tap point: small orchid dot on top edge of stage N-1 */}
      <circle cx={tapX} cy={tapY} r={5} fill={ORCHID} stroke={PLUM} strokeWidth={1} />

      {/* Early-tag wire: tap → up → right → into RS wakeup box */}
      {/* Routed as an L-shape so it doesn't cross the stage boxes. */}
      <polyline
        points={`${tapX},${tapY} ${tapX},${rsBoxY + rsBoxH / 2} ${rsBoxX - 4},${rsBoxY + rsBoxH / 2}`}
        fill="none"
        stroke={ORCHID}
        strokeWidth={2}
        markerEnd="url(#etb-arrow-orchid)"
      />
      {/* Label on the early-tag wire */}
      <text
        x={tapX + 10}
        y={tapY - 60}
        fontSize="11"
        fill={ORCHID}
        fontWeight="600"
      >
        early-tag wire
      </text>
      <text
        x={tapX + 10}
        y={tapY - 46}
        fontSize="10"
        fill={ORCHID}
      >
        (tap @ stage N-1)
      </text>

      {/* RS wakeup box (top right) */}
      <rect
        x={rsBoxX}
        y={rsBoxY}
        width={rsBoxW}
        height={rsBoxH}
        rx={8}
        ry={8}
        fill="white"
        stroke={ORCHID}
        strokeWidth={1.5}
      />
      <text
        x={rsBoxX + rsBoxW / 2}
        y={rsBoxY + rsBoxH / 2 - 2}
        textAnchor="middle"
        fontSize="12"
        fill={INK}
        fontWeight="600"
      >
        RS wakeup logic
      </text>
      <text
        x={rsBoxX + rsBoxW / 2}
        y={rsBoxY + rsBoxH / 2 + 14}
        textAnchor="middle"
        fontSize="10"
        fill={INK}
      >
        (registered ready bit)
      </text>

      {/* "done" arrow: stage 4 → CDB broadcast box */}
      {/* Routed: out the right of stage 4, down, then right into the box. */}
      <polyline
        points={`${lastStage.x + stageW},${stageY + stageH / 2} ${lastStage.x + stageW + 30},${stageY + stageH / 2} ${lastStage.x + stageW + 30},${cdbBoxY + cdbBoxH / 2} ${cdbBoxX - 4},${cdbBoxY + cdbBoxH / 2}`}
        fill="none"
        stroke={IRIS}
        strokeWidth={1.5}
        markerEnd="url(#etb-arrow-iris)"
      />
      <text
        x={lastStage.x + stageW + 36}
        y={stageY + stageH / 2 - 6}
        fontSize="11"
        fill={INK}
      >
        done
      </text>

      {/* CDB broadcast box (bottom right of top panel) */}
      <rect
        x={cdbBoxX}
        y={cdbBoxY}
        width={cdbBoxW}
        height={cdbBoxH}
        rx={8}
        ry={8}
        fill="white"
        stroke={PLUM}
        strokeWidth={1.5}
      />
      <text
        x={cdbBoxX + cdbBoxW / 2}
        y={cdbBoxY + cdbBoxH / 2 - 2}
        textAnchor="middle"
        fontSize="12"
        fill={INK}
        fontWeight="600"
      >
        CDB broadcast
      </text>
      <text
        x={cdbBoxX + cdbBoxW / 2}
        y={cdbBoxY + cdbBoxH / 2 + 14}
        textAnchor="middle"
        fontSize="10"
        fill={INK}
      >
        (value + tag)
      </text>

      {/* Divider between top and bottom panels */}
      <line
        x1="40"
        y1="360"
        x2="760"
        y2="360"
        stroke={PLUM}
        strokeWidth={0.5}
        strokeDasharray="4 4"
        opacity={0.5}
      />

      {/* ============================================================ */}
      {/* BOTTOM PANEL — timing chart                                  */}
      {/* ============================================================ */}

      {/* Bottom-panel title */}
      <text
        x="400"
        y="385"
        textAnchor="middle"
        fontSize="14"
        fontWeight="600"
        fill={INK}
      >
        Timing: early tag wakes RS one cycle before CDB
      </text>

      {/* Cycle column headers */}
      {cycleLabels.map((label, c) => {
        const cx = gridLeft + c * cellW + cellW / 2;
        const cy = gridTop - 8;
        return (
          <text
            key={label}
            x={cx}
            y={cy}
            textAnchor="middle"
            fontSize="11"
            fill={INK}
            fontWeight="600"
          >
            {label}
          </text>
        );
      })}

      {/* Event rows + grid cells */}
      {events.map((ev, r) => {
        const rowY = gridTop + r * cellH;
        return (
          <g key={ev.label}>
            {/* Row label (left of grid) */}
            <text
              x={gridLeft - 10}
              y={rowY + cellH / 2 + 4}
              textAnchor="end"
              fontSize="11"
              fill={ev.highlight ? ORCHID : INK}
              fontWeight={ev.highlight ? 600 : 400}
            >
              {ev.label}
            </text>
            {/* Four grid cells per row */}
            {cycleLabels.map((_, c) => {
              const cellX = gridLeft + c * cellW;
              const fires = ev.firesAt === c;
              const fillColor = ev.highlight && fires ? ORCHID_50 : 'white';
              return (
                <g key={c}>
                  <rect
                    x={cellX}
                    y={rowY}
                    width={cellW}
                    height={cellH}
                    rx={4}
                    ry={4}
                    fill={fillColor}
                    stroke={ev.highlight ? ORCHID : PLUM}
                    strokeWidth={ev.highlight ? 1.5 : 1}
                  />
                  {fires && (
                    <circle
                      cx={cellX + cellW / 2}
                      cy={rowY + cellH / 2}
                      r={5}
                      fill={ev.highlight ? ORCHID : PLUM}
                    />
                  )}
                </g>
              );
            })}
          </g>
        );
      })}

      {/* "1 cycle saved" annotation: arrow from early-tag-fires cell
          (cycle N, row 1) → RS-ready cell (cycle N+1, row 2) */}
      {(() => {
        const earlyCellX = gridLeft + 1 * cellW + cellW / 2;
        const earlyCellY = gridTop + 1 * cellH + cellH / 2;
        const rsCellX = gridLeft + 2 * cellW + cellW / 2;
        const rsCellY = gridTop + 2 * cellH + cellH / 2;
        return (
          <>
            <line
              x1={earlyCellX}
              y1={earlyCellY + 8}
              x2={rsCellX - 6}
              y2={rsCellY - 8}
              stroke={ORCHID}
              strokeWidth={1.5}
              strokeDasharray="3 3"
              markerEnd="url(#etb-arrow-orchid)"
            />
          </>
        );
      })()}

      {/* "1 cycle saved" callout to the right of the grid */}
      <g>
        {(() => {
          const calloutX = gridLeft + 4 * cellW + 20;
          const calloutY = gridTop + 1.5 * cellH;
          return (
            <>
              <text
                x={calloutX}
                y={calloutY - 6}
                fontSize="11"
                fontWeight="700"
                fill={ORCHID}
              >
                1 cycle saved
              </text>
              <text
                x={calloutX}
                y={calloutY + 10}
                fontSize="10"
                fill={INK}
              >
                vs. CDB-only wakeup
              </text>
            </>
          );
        })()}
      </g>
    </svg>
  );
}
