#!/usr/bin/env python3
"""
capture_trace.py — runs on the EECS 4340 lab PC. Generates JSON traces for the
demo-website pipeline visualizer.

Usage:
  python3 web/tools/capture_trace.py <program-name>

Workflow per program:
  1. Run `make <program>.out` to generate output/<program>.{ppln,out,wb}.
  2. Parse .ppln for per-cycle pipeline state. If absent or malformed, fall back
     to .out/.wb (commit-stream-only).
  3. Parse .wb for committed writebacks.
  4. Detect events (mispredict, ETB wakeup, flush) by diffing snapshot deltas.
  5. Write web/public/traces/<program>.json (downsample if > 5MB).

------------------------------------------------------------------------------
Source-of-truth notes for the lab-PC trip
------------------------------------------------------------------------------
The Makefile recipe is (Makefile:558):
    ./simv +MEMORY=$< +WRITEBACK=$(@D)/$*.wb +PIPELINE=$(@D)/$*.ppln > $@

So three files land in `output/` per program:
  output/<prog>.out   — captured stdout: banner, halt reason, branch_accuracy,
                        watchdog ring, "@@@ Passed", "@@  N cycles / M instrs ...".
                        Does NOT contain WB lines.
  output/<prog>.wb    — committed writebacks, one per architectural commit, in
                        the format (test/pipeline_test.sv:413):
                            PC=<hex>, REG[<dec>]=<hex>
                        or (no register write that cycle):
                            PC=<hex>, ---
  output/<prog>.ppln  — per-cycle pipeline dump.

  IMPORTANT: as of this commit the DPI-C `print_*` calls in
  test/pipeline_test.sv (lines 18-29 and 396-408) are commented out. That
  means `+PIPELINE=output/<prog>.ppln` will produce an EMPTY .ppln file on the
  lab PC unless the testbench is updated. The fallback path
  (`fallback_from_out` over .wb) is therefore the realistic v1 path. The
  best-effort `parse_ppln` here uses a generic "Cycle: N\n  ROB: {...}\n  ..."
  format that is what we'd want a future ppln dumper to emit; until that
  dumper is wired up, the ppln branch is essentially unused on the lab PC.

  parse_out() in this module is intentionally permissive: it accepts the
  real .wb format `PC=..., REG[i]=v` AND the simpler `WB rN = 0xV` style
  used in the unit-test fixture. This keeps the same code path useful for
  whichever file the lab-PC trip ends up feeding it.
"""
from __future__ import annotations
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
TRACES_DIR = REPO_ROOT / 'web' / 'public' / 'traces'
MAX_TRACE_BYTES = 5 * 1024 * 1024

CycleSnapshot = dict[str, Any]


def run_make(program: str) -> tuple[Path, Path | None, Path | None]:
    """Run `make <program>.out` and return (out_path, wb_path_or_None, ppln_path_or_None)."""
    out_path = REPO_ROOT / 'output' / f'{program}.out'
    wb_path = REPO_ROOT / 'output' / f'{program}.wb'
    ppln_path = REPO_ROOT / 'output' / f'{program}.ppln'
    print(f'[capture] running: make {program}.out')
    res = subprocess.run(
        ['make', f'{program}.out'], cwd=REPO_ROOT, capture_output=True, text=True
    )
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr, file=sys.stderr)
        raise RuntimeError(f'make {program}.out failed')
    if not out_path.exists():
        raise RuntimeError(f'expected {out_path} but it was not produced')
    return (
        out_path,
        wb_path if wb_path.exists() else None,
        ppln_path if (ppln_path.exists() and ppln_path.stat().st_size > 0) else None,
    )


CYCLE_RE = re.compile(r'^\s*(?:Cycle|cycle)\s*[:=]?\s*(\d+)', re.IGNORECASE)


def _parse_kv_entry(entry_text: str) -> dict[str, str]:
    """Parse `k1=v1,k2=v2,...` into a dict, coercing simple bool-ish ints."""
    out: dict[str, Any] = {}
    for piece in entry_text.split(','):
        if '=' not in piece:
            continue
        k, v = piece.split('=', 1)
        k = k.strip()
        v = v.strip()
        # try integer coercion (decimal or hex)
        try:
            if v.startswith(('0x', '0X')):
                out[k] = int(v, 16)
            else:
                out[k] = int(v)
        except ValueError:
            out[k] = v
    # canonicalize busy → bool when present as 0/1
    if 'busy' in out and out['busy'] in (0, 1):
        out['busy'] = bool(out['busy'])
    return out


def parse_ppln(path: Path) -> list[CycleSnapshot]:
    """Parse the per-cycle pipeline dump.

    Recognized line shapes (after stripping leading whitespace):
        Cycle: <N>
        PC=<hex>
        ROB: {k=v,k=v,...} {k=v,...}
        RS:  {k=v,...} ...
        LSQ: {k=v,...} ...
        CDB: {k=v,...}
        COMMIT: {k=v,...}
    Anything else is ignored.
    """
    text = path.read_text(errors='replace')
    snapshots: list[CycleSnapshot] = []
    current: CycleSnapshot | None = None
    for line in text.splitlines():
        m = CYCLE_RE.match(line)
        if m:
            if current is not None:
                snapshots.append(current)
            current = {
                'cycle': int(m.group(1)),
                'pc': 0,
                'fetch': [],
                'decode': [],
                'rob': [],
                'rs': [],
                'lsq': [],
                'exec': {},
                'cdb': [],
                'commit': [],
                'events': [],
            }
            continue
        if current is None:
            continue
        if 'PC=' in line:
            mpc = re.search(r'PC=(\w+)', line)
            if mpc:
                try:
                    current['pc'] = int(mpc.group(1), 0)
                except ValueError:
                    pass
        stripped = line.strip()
        for prefix, key in (
            ('ROB:', 'rob'),
            ('RS:', 'rs'),
            ('LSQ:', 'lsq'),
            ('CDB:', 'cdb'),
            ('COMMIT:', 'commit'),
        ):
            if stripped.startswith(prefix):
                for entry in re.finditer(r'\{([^}]+)\}', stripped):
                    current[key].append(_parse_kv_entry(entry.group(1)))
                break
    if current is not None:
        snapshots.append(current)
    return snapshots


# Match either `PC=<hex>, REG[<dec>]=<hex>` (real .wb format) OR `WB rN = 0xV`
# (test-fixture / friendlier .out format).
WB_REAL_RE = re.compile(
    r'^\s*PC=(\w+)\s*,\s*REG\[\s*(\d+)\s*\]\s*=\s*(\w+)', re.IGNORECASE
)
WB_FRIENDLY_RE = re.compile(
    r'^\s*(?:WB|writeback)\s+r?(\d+)\s*[=:]\s*(\w+)', re.IGNORECASE
)


def _coerce_int(s: str) -> int:
    """Parse a hex (`0x...` or bare hex) or decimal int; return 0 on failure."""
    s = s.strip()
    try:
        if s.lower().startswith('0x'):
            return int(s, 16)
        # bare hex (REG values in .wb are unprefixed hex)
        if any(c in s.lower() for c in 'abcdef'):
            return int(s, 16)
        return int(s)
    except ValueError:
        try:
            return int(s, 16)
        except ValueError:
            return 0


def parse_out(path: Path) -> list[dict[str, Any]]:
    """Parse a writeback or .out file for committed writebacks.

    Tolerates both the real .wb format and the friendlier WB-style format.
    Lines like `PC=..., ---` (no write that cycle) are ignored.
    """
    wbs: list[dict[str, Any]] = []
    cycle: int | None = None
    for line in path.read_text(errors='replace').splitlines():
        cm = CYCLE_RE.match(line)
        if cm:
            cycle = int(cm.group(1))
            continue
        m = WB_REAL_RE.match(line)
        if m:
            wbs.append(
                {
                    'cycle': cycle,
                    'pc': _coerce_int(m.group(1)),
                    'reg': int(m.group(2)),
                    'value': _coerce_int(m.group(3)),
                }
            )
            continue
        m = WB_FRIENDLY_RE.match(line)
        if m:
            wbs.append(
                {
                    'cycle': cycle,
                    'reg': int(m.group(1)),
                    'value': _coerce_int(m.group(2)),
                }
            )
    return wbs


def fallback_from_out(path: Path) -> list[CycleSnapshot]:
    """Build commit-stream-only snapshots from a .out/.wb file.

    Used when no .ppln is available (the realistic case until pipeline_test.sv
    re-enables its DPI dumping). Each writeback becomes one cycle snapshot
    with only the `commit` lane populated.
    """
    wbs = parse_out(path)
    snapshots: list[CycleSnapshot] = []
    for i, w in enumerate(wbs):
        commit_entry: dict[str, Any] = {'reg': w['reg'], 'value': w['value']}
        if 'pc' in w:
            commit_entry['pc'] = w['pc']
        snapshots.append(
            {
                'cycle': w.get('cycle') if w.get('cycle') is not None else i,
                'pc': w.get('pc', 0),
                'fetch': [],
                'decode': [],
                'rob': [],
                'rs': [],
                'lsq': [],
                'exec': {},
                'cdb': [],
                'commit': [commit_entry],
                'events': [],
            }
        )
    return snapshots


def _busy_tag_set(rob_entries: list[dict[str, Any]]) -> set[Any]:
    """Collect the tags of `busy` ROB entries, tolerating bool/int/str busy."""
    out: set[Any] = set()
    for e in rob_entries:
        b = e.get('busy')
        if b is True or b == 1 or b == '1':
            out.add(e.get('tag'))
    return out


def detect_events(snapshots: list[CycleSnapshot]) -> list[CycleSnapshot]:
    """Annotate snapshots with simple event tags.

    Heuristics (cheap, snapshot-diff based):
      - "mispredict" + "flush" when 2+ ROB entries go from busy→not-busy in a
        single cycle (i.e. a bulk squash).
    More precise events (ETB wakeup, exact flush boundary) require richer
    .ppln content than the fallback path can give us.
    """
    for i in range(1, len(snapshots)):
        prev, cur = snapshots[i - 1], snapshots[i]
        prev_busy = _busy_tag_set(prev.get('rob', []))
        cur_busy = _busy_tag_set(cur.get('rob', []))
        flushed = prev_busy - cur_busy
        if len(flushed) >= 2:
            cur.setdefault('events', [])
            cur['events'].append('mispredict')
            cur['events'].append('flush')
    return snapshots


def downsample(snapshots: list[CycleSnapshot], target_bytes: int) -> list[CycleSnapshot]:
    """Reduce the snapshot list size to fit under `target_bytes` when serialized.

    Always keeps event-flagged snapshots, plus every `factor`-th snapshot.
    """
    raw = json.dumps(snapshots).encode()
    if len(raw) <= target_bytes:
        return snapshots
    factor = max(2, len(raw) // target_bytes + 1)
    print(f'[capture] downsampling 1:{factor} (was {len(raw):,} bytes)')
    kept: list[CycleSnapshot] = []
    for i, s in enumerate(snapshots):
        if i % factor == 0 or s.get('events'):
            kept.append(s)
    return kept


def main() -> None:
    if len(sys.argv) != 2:
        print('usage: python3 capture_trace.py <program>', file=sys.stderr)
        sys.exit(1)
    program = sys.argv[1]
    out_path, wb_path, ppln_path = run_make(program)
    if ppln_path is not None:
        print(f'[capture] parsing {ppln_path}')
        snapshots = parse_ppln(ppln_path)
        if not snapshots:
            print('[capture] WARNING: .ppln parse returned empty — falling back to .wb/.out')
            snapshots = fallback_from_out(wb_path or out_path)
    else:
        print('[capture] no .ppln present — using .wb/.out fallback')
        snapshots = fallback_from_out(wb_path or out_path)
    snapshots = detect_events(snapshots)
    snapshots = downsample(snapshots, MAX_TRACE_BYTES)
    TRACES_DIR.mkdir(parents=True, exist_ok=True)
    json_path = TRACES_DIR / f'{program}.json'
    json_path.write_text(json.dumps({'program': program, 'snapshots': snapshots}, indent=None))
    print(
        f'[capture] wrote {json_path} ({json_path.stat().st_size:,} bytes, '
        f'{len(snapshots)} snapshots)'
    )


if __name__ == '__main__':
    main()
