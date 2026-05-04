// DCacheDiagram — Figure 3 of the EECS 4340 final report.
//
// Source-of-truth RTL: verilog/dcache.sv. Cross-reference: doc/final-report
// /4340-final-report.md §V.D.
//
// RTL/report disagreement (RTL wins, per task spec):
//   The PRD §8.1 and the report describe "per-byte valid mask (8 bits per
//   line)" alongside the per-byte dirty mask. The actual DCACHE_ENTRY in
//   verilog/dcache.sv carries a SINGLE `valid` bit per line and a SINGLE
//   `dirty` bit per line. The byte granularity exists only on the WRITE
//   path: the LSQ supplies an 8-bit `proc_wr_be` byte-enable that selects
//   which bytes of `data` get rewritten on a hit/store, and which bytes of
//   the fill response are overridden on a miss-and-store. The cache itself
//   stores no per-byte status bits.
//   This diagram therefore draws ONE valid bit + ONE dirty bit per line,
//   plus an 8-bit `proc_wr_be` byte-enable strip on the write path. That
//   matches the RTL exactly.
//
// Address layout (verilog/dcache.sv lines 10-13, 31-33, 99):
//   addr[2:0]   byte offset within line (3 bits, 8-byte lines)
//   addr[6:3]   set index               (4 bits, 16 sets)
//   addr[15:7]  tag                     (9 bits)
//   addr[31:16] unused
//
// Highlighting (orchid pink #C34FA2, per task spec) marks the
// set-associative-specific elements that distinguish this cache from a
// direct-mapped baseline:
//   - way 1 column of every set (faint orchid fill)
//   - LRU column (one bit per set)
//   - bus-arbitration mask box stroke (the prefetch-related shared
//     infrastructure between D-cache and I-cache stream buffer)

const PLUM = "#77295D";
const ORCHID = "#C34FA2";
const ORCHID_FILL = "rgba(195,79,162,0.15)";
const IRIS = "#5364C0";
const INK = "#241B2A";
const SNOW = "#EDF1FD";

export function DCacheDiagram() {
  // Cache grid geometry. We render 4 visible sets at the top, an ellipsis
  // row, and 1 visible set at the bottom (set 15) so the reader can see
  // both ends of the 16-set array without rendering all sixteen rows.
  const gridX = 240;
  const gridY = 100;
  const cellW = 110;
  const cellH = 30;
  const visibleTopSets = [0, 1, 2, 3];
  const ellipsisIdx = visibleTopSets.length; // row 4
  const lastSetRow = visibleTopSets.length + 1; // row 5
  const totalRows = visibleTopSets.length + 2; // 4 visible + ellipsis + last
  const gridH = cellH * totalRows;

  // The "selected" line whose per-byte mask is shown on the right. Pick
  // set 1, way 1 — visible and inside the highlighted (way-1) column so
  // the byte-enable strip naturally connects to an orchid cell.
  const selectedRowIdx = 1;
  const selectedWayIdx = 1;
  const selectedCellX = gridX + cellW * selectedWayIdx;
  const selectedCellY = gridY + cellH * selectedRowIdx;

  // Per-byte mask panel position.
  const maskPanelX = 600;
  const maskPanelY = 110;

  // Bus arbitration mask box.
  const busBoxX = 250;
  const busBoxY = 380;
  const busBoxW = 360;
  const busBoxH = 60;

  return (
    <svg
      viewBox="0 0 900 520"
      className="w-full h-auto"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="D-cache organization: 16 sets by 2 ways, with byte-enable write mask, LRU column, and bus arbitration mask"
    >
      <defs>
        <marker
          id="dc-arrow-iris"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={IRIS} />
        </marker>
        <marker
          id="dc-arrow-plum"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="7"
          markerHeight="7"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={PLUM} />
        </marker>
      </defs>

      {/* Title */}
      <text
        x="450"
        y="28"
        textAnchor="middle"
        fontSize="14"
        fontWeight="600"
        fill={INK}
      >
        D-cache: 16 sets x 2 ways, 8-byte lines (256 B)
      </text>

      {/* ---- Address decode strip (top) ---- */}
      {/* Total addr width drawn = 360 px, split tag/index/offset
          proportional to bit widths (9 / 4 / 3 = 16 bits). */}
      {(() => {
        const decX = 30;
        const decY = 55;
        const decW = 360;
        const decH = 26;
        const tagBits = 9;
        const idxBits = 4;
        const offBits = 3;
        const total = tagBits + idxBits + offBits;
        const tagW = (decW * tagBits) / total;
        const idxW = (decW * idxBits) / total;
        const offW = (decW * offBits) / total;
        return (
          <g>
            <text
              x={decX}
              y={decY - 6}
              fontSize="11"
              fill={INK}
              fontWeight="500"
            >
              Address[15:0]
            </text>
            {/* tag */}
            <rect
              x={decX}
              y={decY}
              width={tagW}
              height={decH}
              fill={SNOW}
              stroke={PLUM}
              strokeWidth="1.5"
              rx="4"
            />
            <text
              x={decX + tagW / 2}
              y={decY + decH / 2 + 4}
              textAnchor="middle"
              fontSize="11"
              fill={INK}
              fontWeight="500"
            >
              tag [15:7]
            </text>
            <text
              x={decX + tagW / 2}
              y={decY + decH + 13}
              textAnchor="middle"
              fontSize="10"
              fill={INK}
            >
              9 bits
            </text>
            {/* index */}
            <rect
              x={decX + tagW}
              y={decY}
              width={idxW}
              height={decH}
              fill="#fff"
              stroke={PLUM}
              strokeWidth="1.5"
            />
            <text
              x={decX + tagW + idxW / 2}
              y={decY + decH / 2 + 4}
              textAnchor="middle"
              fontSize="11"
              fill={INK}
              fontWeight="500"
            >
              index [6:3]
            </text>
            <text
              x={decX + tagW + idxW / 2}
              y={decY + decH + 13}
              textAnchor="middle"
              fontSize="10"
              fill={INK}
            >
              4 bits
            </text>
            {/* offset */}
            <rect
              x={decX + tagW + idxW}
              y={decY}
              width={offW}
              height={decH}
              fill={SNOW}
              stroke={PLUM}
              strokeWidth="1.5"
              rx="4"
            />
            <text
              x={decX + tagW + idxW + offW / 2}
              y={decY + decH / 2 + 4}
              textAnchor="middle"
              fontSize="11"
              fill={INK}
              fontWeight="500"
            >
              off [2:0]
            </text>
            <text
              x={decX + tagW + idxW + offW / 2}
              y={decY + decH + 13}
              textAnchor="middle"
              fontSize="10"
              fill={INK}
            >
              3 bits
            </text>

            {/* Arrow from index segment routed around the grid frame into
                the set-1 row from the left. We exit the bottom of the
                index decode box, route LEFT in the gap above the bit-width
                annotations, then DIAGONALLY into the left edge of the
                set-1 cells. The diagonal stays clear of the "set 1" label
                (which sits at row centre on the left of the grid). */}
            <polyline
              points={`${decX + tagW + idxW / 2},${decY + decH + 2} ${gridX - 22},${decY + decH + 2} ${gridX},${gridY + cellH * selectedRowIdx + cellH / 2}`}
              fill="none"
              stroke={IRIS}
              strokeWidth="1.5"
              markerEnd="url(#dc-arrow-iris)"
            />
          </g>
        );
      })()}

      {/* ---- Cache grid: 16 sets x 2 ways (rendered as 5 visible rows + ellipsis) ---- */}
      <g>
        {/* Outer frame */}
        <rect
          x={gridX - 4}
          y={gridY - 22}
          width={cellW * 2 + 8}
          height={gridH + 28}
          fill="none"
          stroke={PLUM}
          strokeWidth="1.5"
          rx="8"
        />
        <text
          x={gridX + cellW}
          y={gridY - 28}
          textAnchor="middle"
          fontSize="11"
          fill={INK}
          fontWeight="600"
        >
          dcache_data[16][2]
        </text>

        {/* Column headers */}
        <text
          x={gridX + cellW / 2}
          y={gridY - 6}
          textAnchor="middle"
          fontSize="11"
          fontWeight="500"
          fill={INK}
        >
          way 0
        </text>
        <text
          x={gridX + cellW + cellW / 2}
          y={gridY - 6}
          textAnchor="middle"
          fontSize="11"
          fontWeight="500"
          fill={ORCHID}
        >
          way 1
        </text>

        {/* Visible top rows */}
        {visibleTopSets.map((setIdx, rowIdx) => {
          const y = gridY + rowIdx * cellH;
          return (
            <g key={`set-${setIdx}`}>
              {/* set label */}
              <text
                x={gridX - 12}
                y={y + cellH / 2 + 4}
                textAnchor="end"
                fontSize="10"
                fill={INK}
              >
                set {setIdx}
              </text>
              {/* way 0 */}
              <rect
                x={gridX}
                y={y}
                width={cellW}
                height={cellH}
                fill="#fff"
                stroke={PLUM}
                strokeWidth="1"
                rx="4"
              />
              <text
                x={gridX + cellW / 2}
                y={y + cellH / 2 + 4}
                textAnchor="middle"
                fontSize="10"
                fill={INK}
              >
                tag | data | v | d
              </text>
              {/* way 1 (orchid-tinted: set-associative-specific) */}
              <rect
                x={gridX + cellW}
                y={y}
                width={cellW}
                height={cellH}
                fill={ORCHID_FILL}
                stroke={PLUM}
                strokeWidth="1"
                rx="4"
              />
              <text
                x={gridX + cellW + cellW / 2}
                y={y + cellH / 2 + 4}
                textAnchor="middle"
                fontSize="10"
                fill={INK}
              >
                tag | data | v | d
              </text>
            </g>
          );
        })}

        {/* Ellipsis row */}
        <g>
          <text
            x={gridX - 12}
            y={gridY + ellipsisIdx * cellH + cellH / 2 + 4}
            textAnchor="end"
            fontSize="10"
            fill={INK}
          >
            ...
          </text>
          <text
            x={gridX + cellW / 2}
            y={gridY + ellipsisIdx * cellH + cellH / 2 + 4}
            textAnchor="middle"
            fontSize="14"
            fill={INK}
          >
            ...
          </text>
          <text
            x={gridX + cellW + cellW / 2}
            y={gridY + ellipsisIdx * cellH + cellH / 2 + 4}
            textAnchor="middle"
            fontSize="14"
            fill={ORCHID}
          >
            ...
          </text>
        </g>

        {/* Last visible set: set 15 */}
        {(() => {
          const y = gridY + lastSetRow * cellH;
          return (
            <g>
              <text
                x={gridX - 12}
                y={y + cellH / 2 + 4}
                textAnchor="end"
                fontSize="10"
                fill={INK}
              >
                set 15
              </text>
              <rect
                x={gridX}
                y={y}
                width={cellW}
                height={cellH}
                fill="#fff"
                stroke={PLUM}
                strokeWidth="1"
                rx="4"
              />
              <text
                x={gridX + cellW / 2}
                y={y + cellH / 2 + 4}
                textAnchor="middle"
                fontSize="10"
                fill={INK}
              >
                tag | data | v | d
              </text>
              <rect
                x={gridX + cellW}
                y={y}
                width={cellW}
                height={cellH}
                fill={ORCHID_FILL}
                stroke={PLUM}
                strokeWidth="1"
                rx="4"
              />
              <text
                x={gridX + cellW + cellW / 2}
                y={y + cellH / 2 + 4}
                textAnchor="middle"
                fontSize="10"
                fill={INK}
              >
                tag | data | v | d
              </text>
            </g>
          );
        })()}

        {/* Highlight the selected line (set 1, way 1) with a thicker plum
            outline so the per-byte mask connection is unambiguous. */}
        <rect
          x={selectedCellX}
          y={selectedCellY}
          width={cellW}
          height={cellH}
          fill="none"
          stroke={PLUM}
          strokeWidth="2"
          rx="4"
        />
      </g>

      {/* ---- LRU column (one bit per set, orchid-pink: set-assoc-specific) ---- */}
      {(() => {
        const lruX = gridX + cellW * 2 + 18;
        const lruW = 28;
        return (
          <g>
            <text
              x={lruX + lruW / 2}
              y={gridY - 6}
              textAnchor="middle"
              fontSize="11"
              fontWeight="500"
              fill={ORCHID}
            >
              LRU
            </text>
            <rect
              x={lruX - 4}
              y={gridY - 22}
              width={lruW + 8}
              height={gridH + 28}
              fill="none"
              stroke={ORCHID}
              strokeWidth="1.5"
              rx="6"
            />
            {visibleTopSets.map((setIdx, rowIdx) => {
              const y = gridY + rowIdx * cellH;
              // Alternate 0/1 to make the bit-per-set idea visible.
              const bit = setIdx % 2;
              return (
                <g key={`lru-${setIdx}`}>
                  <rect
                    x={lruX}
                    y={y + 5}
                    width={lruW}
                    height={cellH - 10}
                    fill="#fff"
                    stroke={ORCHID}
                    strokeWidth="1"
                    rx="3"
                  />
                  <text
                    x={lruX + lruW / 2}
                    y={y + cellH / 2 + 4}
                    textAnchor="middle"
                    fontSize="10"
                    fill={INK}
                  >
                    {bit}
                  </text>
                </g>
              );
            })}
            {/* ellipsis */}
            <text
              x={lruX + lruW / 2}
              y={gridY + ellipsisIdx * cellH + cellH / 2 + 4}
              textAnchor="middle"
              fontSize="14"
              fill={ORCHID}
            >
              ...
            </text>
            {/* set 15 LRU */}
            {(() => {
              const y = gridY + lastSetRow * cellH;
              return (
                <g>
                  <rect
                    x={lruX}
                    y={y + 5}
                    width={lruW}
                    height={cellH - 10}
                    fill="#fff"
                    stroke={ORCHID}
                    strokeWidth="1"
                    rx="3"
                  />
                  <text
                    x={lruX + lruW / 2}
                    y={y + cellH / 2 + 4}
                    textAnchor="middle"
                    fontSize="10"
                    fill={INK}
                  >
                    1
                  </text>
                </g>
              );
            })()}
            <text
              x={lruX + lruW / 2}
              y={gridY + gridH + 20}
              textAnchor="middle"
              fontSize="9"
              fill={INK}
              fontStyle="italic"
            >
              1 bit / set
            </text>
          </g>
        );
      })()}

      {/* ---- Per-byte write byte-enable strip for the selected line ---- */}
      {/* The cache itself stores 1 valid + 1 dirty bit per LINE. The byte
          granularity lives on proc_wr_be (8 bits, one per byte). We draw
          the write-path strip here so the diagram still communicates the
          "byte-granular store merge" property the report calls out. */}
      {(() => {
        const sqW = 18;
        const sqGap = 3;
        const stripW = sqW * 8 + sqGap * 7;

        // Connector from selected cell to the strip
        return (
          <g>
            {/* Connector from the right edge of the selected (set 1, way 1)
                cell to the per-byte mask panel. Anchor x1 to the actual
                cell edge and route up-and-over the LRU column so the line
                does not cross any other box. The final segment is
                horizontal so the arrowhead lands ON the mask panel. */}
            <polyline
              points={`${selectedCellX + cellW},${selectedCellY + cellH / 2} ${gridX + cellW * 2 + 6},${selectedCellY + cellH / 2} ${gridX + cellW * 2 + 6},${gridY - 32} ${maskPanelX - 16},${gridY - 32} ${maskPanelX - 16},${maskPanelY + 14 + 9} ${maskPanelX - 4},${maskPanelY + 14 + 9}`}
              fill="none"
              stroke={IRIS}
              strokeWidth="1.5"
              markerEnd="url(#dc-arrow-iris)"
            />

            {/* Outer panel */}
            <rect
              x={maskPanelX - 12}
              y={maskPanelY - 30}
              width={stripW + 24}
              height={170}
              fill="none"
              stroke={PLUM}
              strokeWidth="1.5"
              rx="8"
            />
            <text
              x={maskPanelX + stripW / 2}
              y={maskPanelY - 14}
              textAnchor="middle"
              fontSize="11"
              fontWeight="600"
              fill={INK}
            >
              selected line: set 1, way 1
            </text>

            {/* proc_wr_be byte-enable strip (write path, 8 bits) */}
            <text
              x={maskPanelX}
              y={maskPanelY + 4}
              fontSize="11"
              fontWeight="500"
              fill={INK}
            >
              proc_wr_be[7:0]
            </text>
            {Array.from({ length: 8 }).map((_, i) => {
              // Example pattern: store the low half-word (bytes 0,1).
              const set = i < 2;
              return (
                <g key={`be-${i}`}>
                  <rect
                    x={maskPanelX + (7 - i) * (sqW + sqGap)}
                    y={maskPanelY + 14}
                    width={sqW}
                    height={sqW}
                    fill={set ? IRIS : "#fff"}
                    stroke={PLUM}
                    strokeWidth="1"
                    rx="2"
                  />
                  <text
                    x={maskPanelX + (7 - i) * (sqW + sqGap) + sqW / 2}
                    y={maskPanelY + 14 + sqW / 2 + 3}
                    textAnchor="middle"
                    fontSize="9"
                    fill={set ? "#fff" : INK}
                  >
                    {set ? "1" : "0"}
                  </text>
                  <text
                    x={maskPanelX + (7 - i) * (sqW + sqGap) + sqW / 2}
                    y={maskPanelY + 14 + sqW + 10}
                    textAnchor="middle"
                    fontSize="8"
                    fill={INK}
                  >
                    b{i}
                  </text>
                </g>
              );
            })}
            <text
              x={maskPanelX}
              y={maskPanelY + 14 + sqW + 26}
              fontSize="9"
              fill={INK}
              fontStyle="italic"
            >
              one bit per byte; selects which bytes the store overwrites
            </text>

            {/* valid bit (line-granular) */}
            <text
              x={maskPanelX}
              y={maskPanelY + 88}
              fontSize="11"
              fontWeight="500"
              fill={INK}
            >
              valid (per line)
            </text>
            <rect
              x={maskPanelX + 110}
              y={maskPanelY + 76}
              width={sqW}
              height={sqW}
              fill={IRIS}
              stroke={PLUM}
              strokeWidth="1"
              rx="2"
            />
            <text
              x={maskPanelX + 110 + sqW / 2}
              y={maskPanelY + 76 + sqW / 2 + 3}
              textAnchor="middle"
              fontSize="9"
              fill="#fff"
            >
              1
            </text>

            {/* dirty bit (line-granular) */}
            <text
              x={maskPanelX}
              y={maskPanelY + 116}
              fontSize="11"
              fontWeight="500"
              fill={INK}
            >
              dirty (per line)
            </text>
            <rect
              x={maskPanelX + 110}
              y={maskPanelY + 104}
              width={sqW}
              height={sqW}
              fill={IRIS}
              stroke={PLUM}
              strokeWidth="1"
              rx="2"
            />
            <text
              x={maskPanelX + 110 + sqW / 2}
              y={maskPanelY + 104 + sqW / 2 + 3}
              textAnchor="middle"
              fontSize="9"
              fill="#fff"
            >
              1
            </text>
          </g>
        );
      })()}

      {/* ---- Bus arbitration mask (orchid-pink stroke: shared infra) ---- */}
      <g>
        <rect
          x={busBoxX}
          y={busBoxY}
          width={busBoxW}
          height={busBoxH}
          fill={SNOW}
          stroke={ORCHID}
          strokeWidth="1.5"
          rx="8"
        />
        <text
          x={busBoxX + busBoxW / 2}
          y={busBoxY + 22}
          textAnchor="middle"
          fontSize="12"
          fontWeight="600"
          fill={INK}
        >
          bus arbitration mask
        </text>
        <text
          x={busBoxX + busBoxW / 2}
          y={busBoxY + 42}
          textAnchor="middle"
          fontSize="10"
          fill={INK}
          fontStyle="italic"
        >
          masks mem2proc_response per cache (pipeline.sv)
        </text>

        {/* arrow: cache -> bus mask. Start anchored to the bottom edge of
            the cache outer frame (gridY + gridH + 6 is the actual frame
            bottom at this x), end anchored to the top edge of the bus
            mask box. */}
        <line
          x1={gridX + cellW}
          y1={gridY + gridH + 6}
          x2={gridX + cellW}
          y2={busBoxY}
          stroke={IRIS}
          strokeWidth="1.5"
          markerEnd="url(#dc-arrow-iris)"
        />
        <text
          x={gridX + cellW + 6}
          y={gridY + gridH + 30}
          fontSize="9"
          fill={INK}
          fontStyle="italic"
        >
          fill / evict
        </text>

        {/* arrow: bus mask -> main memory (right). Start anchored to the
            right edge of the bus mask box, end anchored to the left edge
            of the main memory box. */}
        <line
          x1={busBoxX + busBoxW}
          y1={busBoxY + busBoxH / 2}
          x2={780}
          y2={busBoxY + busBoxH / 2}
          stroke={IRIS}
          strokeWidth="1.5"
          markerEnd="url(#dc-arrow-iris)"
        />
        <rect
          x={780}
          y={busBoxY + busBoxH / 2 - 22}
          width={100}
          height={44}
          fill="#fff"
          stroke={PLUM}
          strokeWidth="1.5"
          rx="8"
        />
        <text
          x={830}
          y={busBoxY + busBoxH / 2 + 4}
          textAnchor="middle"
          fontSize="11"
          fontWeight="600"
          fill={INK}
        >
          main memory
        </text>
        <text
          x={830}
          y={busBoxY + busBoxH / 2 + 18}
          textAnchor="middle"
          fontSize="9"
          fill={INK}
          fontStyle="italic"
        >
          100 ns latency
        </text>

        {/* arrow: I-cache stream buffer (left) shares the bus mask. Both
            endpoints anchored to actual box edges. */}
        <line
          x1={busBoxX}
          y1={busBoxY + busBoxH / 2}
          x2={140}
          y2={busBoxY + busBoxH / 2}
          stroke={IRIS}
          strokeWidth="1.5"
          strokeDasharray="4 3"
          markerStart="url(#dc-arrow-iris)"
        />
        <rect
          x={30}
          y={busBoxY + busBoxH / 2 - 22}
          width={110}
          height={44}
          fill="#fff"
          stroke={PLUM}
          strokeWidth="1.5"
          rx="8"
        />
        <text
          x={85}
          y={busBoxY + busBoxH / 2 + 0}
          textAnchor="middle"
          fontSize="10"
          fontWeight="600"
          fill={INK}
        >
          I-cache stream
        </text>
        <text
          x={85}
          y={busBoxY + busBoxH / 2 + 14}
          textAnchor="middle"
          fontSize="10"
          fontWeight="600"
          fill={INK}
        >
          buffer
        </text>

        <text
          x={busBoxX + busBoxW / 2}
          y={busBoxY + busBoxH + 18}
          textAnchor="middle"
          fontSize="9"
          fill={INK}
          fontStyle="italic"
        >
          fixed priority: D-cache demand &gt; I-cache demand &gt; stream buffers
        </text>
      </g>

      {/* ---- Legend (bottom) ---- */}
      <g>
        <rect
          x={30}
          y={476}
          width={14}
          height={14}
          fill={ORCHID_FILL}
          stroke={PLUM}
          strokeWidth="1"
          rx="2"
        />
        <text x={50} y={487} fontSize="10" fill={INK}>
          orchid pink = set-associative-specific (way 1, LRU, bus mask)
        </text>

        <rect
          x={420}
          y={476}
          width={14}
          height={14}
          fill={IRIS}
          stroke={PLUM}
          strokeWidth="1"
          rx="2"
        />
        <text x={440} y={487} fontSize="10" fill={INK}>
          iris blue = active bit / data path
        </text>

        <line
          x1={680}
          y1={483}
          x2={710}
          y2={483}
          stroke={IRIS}
          strokeWidth="1.5"
          strokeDasharray="4 3"
        />
        <text x={716} y={487} fontSize="10" fill={INK}>
          shared bus path
        </text>
      </g>
    </svg>
  );
}
