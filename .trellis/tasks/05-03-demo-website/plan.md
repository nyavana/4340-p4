# Interactive Demo Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Vercel-deployed Next.js website with a landing page (interactive architecture diagram + headline numbers + chart), a `/simulator` page (cycle-by-cycle pipeline visualizer playing back captured RTL traces), and a `/deep-dive` page (long-form report content with native React SVG figures and Recharts charts).

**Architecture:** Static-export Next.js 15 + React 19 + TypeScript + Tailwind v4. No backend. All chart data lives in typed `lib/*.ts` const arrays; trace data lives as JSON in `public/traces/`. Five report figures are redrawn from RTL ground truth as native React SVG components — no TikZ imports.

**Tech Stack:** Next.js 15 (App Router), React 19, TypeScript (strict), Tailwind v4, Recharts, Framer Motion, ESLint + Prettier, npm, Vercel CLI.

**Spec:** [.trellis/tasks/05-03-demo-website/prd.md](./prd.md)

**Implementation discipline:** Per user request:
- Dispatch each task to a subagent (Agent tool with `implement` or `general-purpose` subagent_type). Dispatch independent tasks in parallel via a single message with multiple Agent calls. The main thread reviews each subagent's output before proceeding.
- Use the `playwright-cli` skill for browser-level verification at integration checkpoints (after each "page assembly" task and during the final QA pass). Specifically: navigate the page, click the headline CTAs, click an architecture-diagram module to confirm the side panel opens, scrub the simulator, and verify console is free of errors. This replaces the unit-test layer the spec opted out of for UI code.

---

## File Structure (created by this plan)

```
web/
├── app/
│   ├── layout.tsx              ← Task 2
│   ├── page.tsx                ← Task 14
│   ├── simulator/page.tsx      ← Task 26
│   ├── deep-dive/page.tsx      ← Task 23
│   └── globals.css             ← Task 2
├── components/
│   ├── nav/Nav.tsx                                 ← Task 2
│   ├── nav/Footer.tsx                              ← Task 2
│   ├── landing/Hero.tsx                            ← Task 9
│   ├── landing/HeadlineNumbers.tsx                 ← Task 9
│   ├── landing/FeaturePills.tsx                    ← Task 13
│   ├── architecture/ArchDiagram.tsx                ← Task 10
│   ├── architecture/ModulePanel.tsx                ← Task 11
│   ├── architecture/AdvancedFeatureToggle.tsx     ← Task 12
│   ├── diagrams/PipelineOverviewDiagram.tsx        ← Task 17
│   ├── diagrams/BranchPredictorDiagram.tsx         ← Task 18
│   ├── diagrams/DCacheDiagram.tsx                  ← Task 19
│   ├── diagrams/STLFDiagram.tsx                    ← Task 20
│   ├── diagrams/ETBDiagram.tsx                     ← Task 21
│   ├── charts/PerProgramSpeedupChart.tsx           ← Task 15
│   ├── charts/AblationChart.tsx                    ← Task 22a
│   ├── charts/BranchAccLiftChart.tsx               ← Task 22b
│   ├── charts/CpiHistogram.tsx                     ← Task 22c
│   ├── simulator/PipelineLanes.tsx                 ← Task 27
│   ├── simulator/RobTable.tsx                      ← Task 28
│   ├── simulator/RsTable.tsx                       ← Task 28
│   ├── simulator/LsqTable.tsx                      ← Task 28
│   ├── simulator/Scrubber.tsx                      ← Task 29
│   ├── simulator/EventCaption.tsx                  ← Task 29
│   ├── simulator/MobileFallback.tsx                ← Task 30
│   └── ui/{Button,Card,SidePanel}.tsx              ← Task 2
├── lib/
│   ├── architecture.ts         ← Task 6
│   ├── results.ts              ← Task 7
│   ├── features.ts             ← Task 8
│   └── trace.ts                ← Task 25
├── public/
│   ├── traces/                 ← Task 5 (USER ACTION)
│   └── 4340-final-report.pdf   ← Task 31
├── tools/
│   ├── capture_trace.py        ← Task 4
│   └── tests/test_capture.py   ← Task 3
├── package.json                ← Task 1
├── tsconfig.json               ← Task 1
├── tailwind.config.ts          ← Task 1
├── next.config.ts              ← Task 1
├── vercel.json                 ← Task 32
└── README.md                   ← Task 33
```

---

## Phase 1 — Foundation (mostly serial)

### Task 1: Scaffold Next.js + dependencies

**Files:**
- Create: `web/package.json`, `web/tsconfig.json`, `web/next.config.ts`, `web/tailwind.config.ts`, `web/postcss.config.mjs`, `web/.eslintrc.json`, `web/.prettierrc`, `web/.gitignore`

- [ ] **Step 1.1: Create `web/` directory and initialize Next.js**

Run from repo root:
```sh
mkdir -p web && cd web
npx create-next-app@latest . \
  --typescript --tailwind --eslint --app --src-dir=false \
  --import-alias "@/*" --no-turbopack --use-npm
```

If the wizard asks anything else, accept defaults. Expected: `web/package.json`, `web/app/`, `web/tailwind.config.ts`, `web/tsconfig.json` all created.

- [ ] **Step 1.2: Add runtime dependencies**

```sh
cd web && npm install recharts framer-motion clsx
npm install --save-dev prettier prettier-plugin-tailwindcss
```

- [ ] **Step 1.3: Configure Tailwind palette**

Edit `web/tailwind.config.ts` so the `theme.extend.colors` block contains the palette tokens from `doc/web/color/color_palette_guidance.md` §11. Concretely:

```ts
import type { Config } from 'tailwindcss';

export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        plum:   { 50: '#F1EAEF', 100: '#DDCAD6', 500: '#77295D', 600: '#591F46', 800: '#3B142F' },
        orchid: { 50: '#F9EDF6', 100: '#F0D3E8', 500: '#C34FA2', 600: '#923B7A', 800: '#612851' },
        snow:   { 50: '#FDFEFF', 100: '#FAFCFE', 500: '#EDF1FD', 600: '#D8DDF2', 700: '#B2B5BE' },
        sky:    { 50: '#F1F8FE', 100: '#DDEDFB', 500: '#77B7F0', 600: '#5989B4', 800: '#33506A' },
        iris:   { 50: '#EEF0F9', 100: '#D4D8EF', 500: '#5364C0', 600: '#3E4B90', 800: '#293260' },
        ink:    { DEFAULT: '#241B2A', muted: '#5F657A', subtle: '#8A8FA3' },
      },
      boxShadow: {
        soft:   '0 18px 48px rgba(83, 100, 192, 0.12)',
        strong: '0 24px 64px rgba(83, 100, 192, 0.18)',
      },
      borderRadius: { soft: '1.5rem' },
      fontFamily: { sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 1.4: Configure `next.config.ts` for static export**

Edit `web/next.config.ts`:
```ts
import type { NextConfig } from 'next';

const config: NextConfig = {
  output: 'export',
  images: { unoptimized: true },
  trailingSlash: true,
};

export default config;
```

- [ ] **Step 1.5: Set up Prettier**

Create `web/.prettierrc`:
```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

- [ ] **Step 1.6: Verify the dev server boots**

```sh
cd web && npm run dev
```
Expected: server starts on http://localhost:3000 with the Next.js placeholder page. Stop it with Ctrl-C.

- [ ] **Step 1.7: Commit**

```sh
git add web/
git commit -m "chore(web): scaffold Next.js 15 + Tailwind v4 + TypeScript"
```

---

### Task 2: Base layout, nav, footer, design-token CSS

**Files:**
- Modify: `web/app/layout.tsx`, `web/app/globals.css`
- Create: `web/components/nav/Nav.tsx`, `web/components/nav/Footer.tsx`, `web/components/ui/Button.tsx`, `web/components/ui/Card.tsx`, `web/components/ui/SidePanel.tsx`

- [ ] **Step 2.1: Globals CSS with palette CSS vars + Inter font**

Replace `web/app/globals.css` with:
```css
@import 'tailwindcss';

@font-face {
  font-family: 'Inter';
  src: url('https://rsms.me/inter/inter.css');
}

:root {
  --color-bg: #EDF1FD;
  --color-surface: #FFFFFF;
  --color-text: #241B2A;
  --color-text-muted: #5F657A;
  --color-primary: #77295D;
  --color-secondary: #5364C0;
  --color-accent: #C34FA2;
  --color-info: #77B7F0;
  --color-border: #D8DDF2;
}

body {
  background:
    radial-gradient(circle at 12% 10%, rgba(195, 79, 162, 0.10), transparent 30%),
    radial-gradient(circle at 90% 4%, rgba(119, 183, 240, 0.18), transparent 30%),
    var(--color-bg);
  color: var(--color-text);
  font-family: 'Inter', ui-sans-serif, system-ui, sans-serif;
  min-height: 100vh;
}

::selection { background: #F0D3E8; color: #77295D; }
```

- [ ] **Step 2.2: Top nav component**

Create `web/components/nav/Nav.tsx`:
```tsx
'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import clsx from 'clsx';

const links = [
  { href: '/', label: 'Overview' },
  { href: '/simulator', label: 'Simulator' },
  { href: '/deep-dive', label: 'Deep Dive' },
];

export function Nav() {
  const pathname = usePathname();
  return (
    <nav className="sticky top-0 z-40 backdrop-blur-md bg-snow-500/80 border-b border-snow-600">
      <div className="mx-auto max-w-7xl px-6 py-4 flex items-center justify-between">
        <Link href="/" className="font-semibold text-plum-500 tracking-tight">
          OoO RV32IM
        </Link>
        <div className="flex items-center gap-6">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={clsx(
                'text-sm transition-colors',
                pathname === l.href ? 'text-iris-600 font-medium' : 'text-ink-muted hover:text-plum-500',
              )}
            >
              {l.label}
            </Link>
          ))}
          <a
            href="https://github.com/CSEE4340-26/p4.GaPiChiXuXu"
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm text-ink-muted hover:text-plum-500"
          >
            GitHub
          </a>
        </div>
      </div>
    </nav>
  );
}
```

- [ ] **Step 2.3: Footer component**

Create `web/components/nav/Footer.tsx`:
```tsx
export function Footer() {
  return (
    <footer className="mt-32 border-t border-snow-600 bg-snow-500/60">
      <div className="mx-auto max-w-7xl px-6 py-10 text-sm text-ink-muted">
        <p>EECS 4340 — Spring 2026 — Columbia University</p>
        <p className="mt-2">
          Chenhao Yang · Xuepeng Han · Gavin Zou · Pingchuan Dong · Hins Lyu · Xueer Qian
        </p>
        <div className="mt-4 flex gap-4">
          <a href="https://github.com/CSEE4340-26/p4.GaPiChiXuXu" className="hover:text-plum-500">GitHub</a>
          <a href="/4340-final-report.pdf" className="hover:text-plum-500">Report (PDF)</a>
        </div>
      </div>
    </footer>
  );
}
```

- [ ] **Step 2.4: Wrap app in layout**

Replace `web/app/layout.tsx`:
```tsx
import type { Metadata } from 'next';
import './globals.css';
import { Nav } from '@/components/nav/Nav';
import { Footer } from '@/components/nav/Footer';

export const metadata: Metadata = {
  title: 'OoO RV32IM Processor — EECS 4340',
  description:
    'A synthesizable 2-way superscalar P6-style out-of-order RISC-V processor in SystemVerilog.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Nav />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
```

- [ ] **Step 2.5: Three small UI primitives**

Create `web/components/ui/Button.tsx`:
```tsx
import clsx from 'clsx';
import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary' | 'soft';

export function Button({
  variant = 'primary',
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  const styles: Record<Variant, string> = {
    primary: 'bg-plum-500 text-white hover:bg-plum-600',
    secondary: 'bg-iris-500 text-white hover:bg-iris-600',
    soft: 'bg-sky-50 text-iris-800 border border-iris-100 hover:bg-sky-100',
  };
  return (
    <button
      {...rest}
      className={clsx(
        'rounded-soft px-5 py-2.5 text-sm font-medium transition-colors',
        styles[variant],
        className,
      )}
    />
  );
}
```

Create `web/components/ui/Card.tsx`:
```tsx
import clsx from 'clsx';
import type { HTMLAttributes } from 'react';

export function Card({ className, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      {...rest}
      className={clsx(
        'rounded-soft bg-white border border-snow-600 shadow-soft p-6',
        className,
      )}
    />
  );
}
```

Create `web/components/ui/SidePanel.tsx`:
```tsx
'use client';
import { motion, AnimatePresence } from 'framer-motion';
import type { ReactNode } from 'react';

export function SidePanel({
  open,
  onClose,
  children,
}: {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            className="fixed inset-0 z-40 bg-plum-800/20"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />
          <motion.aside
            className="fixed right-0 top-0 z-50 h-full w-full max-w-lg bg-white shadow-strong p-8 overflow-y-auto"
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ type: 'spring', damping: 26, stiffness: 240 }}
          >
            {children}
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}
```

- [ ] **Step 2.6: Verify dev build still works**

```sh
cd web && npm run dev
```
Visit http://localhost:3000 — should see the placeholder page now wrapped in nav + footer (no errors). Stop with Ctrl-C.

- [ ] **Step 2.7: Commit**

```sh
git add web/
git commit -m "feat(web): base layout, nav, footer, UI primitives"
```

---

## Phase 2 — Trace capture (independent — runs in parallel with Phase 3+)

### Task 3: Discover the `.ppln` format and write tests for the parser

**Files:**
- Create: `web/tools/tests/test_capture.py`, `web/tools/tests/fixtures/sample.ppln`, `web/tools/tests/fixtures/sample.out`

- [ ] **Step 3.1: Read pipeline.sv to learn the ppln format**

```sh
grep -n '\$display\|\$write\|\$fdisplay\|\$fwrite' verilog/pipeline.sv | head -50
grep -rn '\$fopen\|\$fclose\|\.ppln\|ppln_fileno' test/ verilog/ | head -20
```
Document findings (per-cycle line format, columns) at the top of `web/tools/capture_trace.py` as a doc-comment. If the format is non-trivial, sample `output/no_hazard.ppln` from a previous run if available, or note that you'll have to make a best-effort parser and let the lab-PC trip validate it.

- [ ] **Step 3.2: Create a tiny synthetic `.ppln` fixture**

Hand-author `web/tools/tests/fixtures/sample.ppln` with 3-5 cycles of plausible content matching whatever format you discovered in 3.1. If you couldn't determine the format, hand-author a minimal version of the *expected* output format (the simpler "commit-stream" fallback) for use by the fallback-path test. Keep this file under 30 lines.

- [ ] **Step 3.3: Create a synthetic `.out` fixture**

Hand-author `web/tools/tests/fixtures/sample.out` with a few lines that look like a real `.out` file: some simulator banner, a couple of `WB` lines, a halt line. ~10 lines.

- [ ] **Step 3.4: Write failing test for `parse_ppln`**

Create `web/tools/tests/test_capture.py`:
```python
"""Tests for capture_trace.py. Run with: cd web && python3 -m pytest tools/tests/ -v"""
import json
from pathlib import Path
import sys

# allow `import capture_trace` from the parent dir
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import capture_trace as ct

FIXTURES = Path(__file__).parent / 'fixtures'

def test_parse_ppln_returns_list_of_cycle_snapshots():
    snapshots = ct.parse_ppln(FIXTURES / 'sample.ppln')
    assert isinstance(snapshots, list)
    assert all('cycle' in s for s in snapshots)
    assert snapshots[0]['cycle'] < snapshots[-1]['cycle']

def test_parse_out_extracts_committed_writebacks():
    wbs = ct.parse_out(FIXTURES / 'sample.out')
    assert isinstance(wbs, list)
    # Each writeback at minimum has a register index and a value
    for w in wbs:
        assert 'reg' in w
        assert 'value' in w

def test_fallback_trace_from_out_only_produces_valid_snapshots():
    snapshots = ct.fallback_from_out(FIXTURES / 'sample.out')
    assert all('commit' in s for s in snapshots)
    assert all('cycle' in s for s in snapshots)

def test_detect_events_finds_mispredict():
    # synthetic snapshots with a flush event between cycles
    snaps = [
        {'cycle': 1, 'rob': [{'tag': 0, 'busy': True}], 'events': []},
        {'cycle': 2, 'rob': [{'tag': 0, 'busy': False}], 'events': []},  # flushed
    ]
    out = ct.detect_events(snaps)
    assert any('mispredict' in e or 'flush' in e for e in out[1]['events'])
```

- [ ] **Step 3.5: Run the test to confirm it fails**

```sh
cd web && python3 -m pytest tools/tests/ -v
```
Expected: ImportError or 4 failures (capture_trace.py doesn't exist yet).

- [ ] **Step 3.6: Commit fixtures + tests**

```sh
git add web/tools/
git commit -m "test(web): trace capture parser fixtures and failing tests"
```

---

### Task 4: Write `capture_trace.py`

**Files:**
- Create: `web/tools/capture_trace.py`

- [ ] **Step 4.1: Implement the script**

Create `web/tools/capture_trace.py`:
```python
#!/usr/bin/env python3
"""
capture_trace.py — runs on the EECS 4340 lab PC. Generates JSON traces for the
demo-website pipeline visualizer.

Usage:
  python3 web/tools/capture_trace.py <program-name>
  e.g. python3 web/tools/capture_trace.py parallel

Workflow per program:
  1. Run `make <program>.out` to generate output/<program>.{ppln,out,wb}.
  2. Parse .ppln for per-cycle pipeline state. If absent or malformed, fall back
     to .out (commit-stream-only).
  3. Parse .wb for committed writebacks (architectural register file deltas).
  4. Detect events (mispredict, ETB wakeup, flush) by diffing snapshot deltas.
  5. Write web/public/traces/<program>.json (downsample if > 5MB).

Reverse-engineered .ppln format (TODO: confirm against verilog/pipeline.sv):
  Header line(s): banner / column legend.
  Per-cycle line(s): cycle number, then per-stage state.
  This script accepts either format and falls back to .out if .ppln is unparseable.
"""
from __future__ import annotations
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]   # web/tools/capture_trace.py → repo root
TRACES_DIR = REPO_ROOT / 'web' / 'public' / 'traces'
MAX_TRACE_BYTES = 5 * 1024 * 1024  # 5 MB

CycleSnapshot = dict[str, Any]


def run_make(program: str) -> tuple[Path, Path | None]:
    """Run `make <program>.out` and return (out_path, ppln_path_or_None)."""
    out_path = REPO_ROOT / 'output' / f'{program}.out'
    ppln_path = REPO_ROOT / 'output' / f'{program}.ppln'
    print(f'[capture] running: make {program}.out')
    res = subprocess.run(
        ['make', f'{program}.out'],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr, file=sys.stderr)
        raise RuntimeError(f'make {program}.out failed')
    if not out_path.exists():
        raise RuntimeError(f'expected {out_path} but it was not produced')
    return out_path, (ppln_path if ppln_path.exists() else None)


# .ppln parser — best-effort. The exact line format depends on the testbench's
# $display calls in verilog/pipeline.sv. The implementing engineer should
# confirm the format from grep output (Step 3.1) and adjust the regex below.
CYCLE_RE = re.compile(r'^\s*(?:Cycle|cycle)\s*[:=]?\s*(\d+)', re.IGNORECASE)


def parse_ppln(path: Path) -> list[CycleSnapshot]:
    """Parse the per-cycle pipeline dump. Returns one snapshot per cycle.

    Snapshot fields (best-effort, may be empty for fallback traces):
      cycle, pc, fetch, decode, rob, rs, lsq, exec, cdb, commit, events
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
                'fetch': [], 'decode': [],
                'rob': [], 'rs': [], 'lsq': [],
                'exec': {}, 'cdb': [], 'commit': [],
                'events': [],
            }
            continue
        if current is None:
            continue
        # Heuristic per-line parse. Adjust to match the actual $display format.
        if 'PC=' in line:
            mpc = re.search(r'PC=(\w+)', line)
            if mpc:
                current['pc'] = int(mpc.group(1), 0)
        if line.strip().startswith('ROB:'):
            # parse "ROB: [tag=0,pc=0x4,busy=1,ready=0,...]" entries
            for entry in re.finditer(r'\{([^}]+)\}', line):
                kv = dict(p.split('=') for p in entry.group(1).split(',') if '=' in p)
                current['rob'].append(kv)
        if line.strip().startswith('RS:'):
            for entry in re.finditer(r'\{([^}]+)\}', line):
                kv = dict(p.split('=') for p in entry.group(1).split(',') if '=' in p)
                current['rs'].append(kv)
        if line.strip().startswith('LSQ:'):
            for entry in re.finditer(r'\{([^}]+)\}', line):
                kv = dict(p.split('=') for p in entry.group(1).split(',') if '=' in p)
                current['lsq'].append(kv)
        if line.strip().startswith('CDB:'):
            for entry in re.finditer(r'\{([^}]+)\}', line):
                kv = dict(p.split('=') for p in entry.group(1).split(',') if '=' in p)
                current['cdb'].append(kv)
        if line.strip().startswith('COMMIT:'):
            for entry in re.finditer(r'\{([^}]+)\}', line):
                kv = dict(p.split('=') for p in entry.group(1).split(',') if '=' in p)
                current['commit'].append(kv)
    if current is not None:
        snapshots.append(current)
    return snapshots


WB_RE = re.compile(r'^\s*(?:WB|writeback)\s+r?(\d+)\s*[=:]\s*(\w+)', re.IGNORECASE)


def parse_out(path: Path) -> list[dict[str, Any]]:
    """Parse the .out file for committed writebacks.

    Returns: [{'cycle': int|None, 'reg': int, 'value': int}, ...]
    """
    wbs: list[dict[str, Any]] = []
    cycle: int | None = None
    for line in path.read_text(errors='replace').splitlines():
        cm = CYCLE_RE.match(line)
        if cm:
            cycle = int(cm.group(1))
            continue
        m = WB_RE.match(line)
        if m:
            wbs.append({
                'cycle': cycle,
                'reg': int(m.group(1)),
                'value': int(m.group(2), 0),
            })
    return wbs


def fallback_from_out(path: Path) -> list[CycleSnapshot]:
    """When .ppln is unavailable, build a commit-stream-only trace from .out."""
    wbs = parse_out(path)
    snapshots: list[CycleSnapshot] = []
    for i, w in enumerate(wbs):
        snapshots.append({
            'cycle': w.get('cycle') or i,
            'pc': 0,
            'fetch': [], 'decode': [],
            'rob': [], 'rs': [], 'lsq': [],
            'exec': {}, 'cdb': [],
            'commit': [{'reg': w['reg'], 'value': w['value']}],
            'events': [],
        })
    return snapshots


def detect_events(snapshots: list[CycleSnapshot]) -> list[CycleSnapshot]:
    """Tag each snapshot's 'events' field by diffing against the previous snapshot."""
    for i in range(1, len(snapshots)):
        prev, cur = snapshots[i - 1], snapshots[i]
        prev_busy = {e.get('tag') for e in prev.get('rob', []) if e.get('busy') in (True, '1', 1)}
        cur_busy = {e.get('tag') for e in cur.get('rob', []) if e.get('busy') in (True, '1', 1)}
        # If two or more ROB entries went from busy → not-busy in one cycle, that's a flush.
        flushed = prev_busy - cur_busy
        if len(flushed) >= 2:
            cur['events'].append('mispredict')
            cur['events'].append('flush')
    return snapshots


def downsample(snapshots: list[CycleSnapshot], target_bytes: int) -> list[CycleSnapshot]:
    """If the trace is too large, keep every Nth snapshot (preserving event-flagged ones)."""
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
    out_path, ppln_path = run_make(program)
    if ppln_path is not None:
        print(f'[capture] parsing {ppln_path}')
        snapshots = parse_ppln(ppln_path)
        if not snapshots:
            print(f'[capture] WARNING: .ppln parse returned empty — falling back to .out')
            snapshots = fallback_from_out(out_path)
    else:
        print(f'[capture] no .ppln present — using .out fallback')
        snapshots = fallback_from_out(out_path)
    snapshots = detect_events(snapshots)
    snapshots = downsample(snapshots, MAX_TRACE_BYTES)
    TRACES_DIR.mkdir(parents=True, exist_ok=True)
    json_path = TRACES_DIR / f'{program}.json'
    json_path.write_text(json.dumps({'program': program, 'snapshots': snapshots}, indent=None))
    print(f'[capture] wrote {json_path} ({json_path.stat().st_size:,} bytes, {len(snapshots)} snapshots)')


if __name__ == '__main__':
    main()
```

- [ ] **Step 4.2: Run tests; iterate until they pass**

```sh
cd web && python3 -m pytest tools/tests/ -v
```
Expected: 4 passing. If a test fails, fix the parser to match the fixture (or fix the fixture if the format expectation changed). Iterate until all 4 are green.

- [ ] **Step 4.3: Commit**

```sh
git add web/tools/capture_trace.py
git commit -m "feat(web): trace capture script with .ppln parser + .out fallback"
```

---

### Task 5: Lab-PC trace capture (USER ACTION)

**This is a manual step. The user runs it on the lab PC.**

- [ ] **Step 5.1: Hand the user this copy-paste block**

```sh
# On the lab PC, in the repo root:
module load vcs verdi synopsys-synth
python3 web/tools/capture_trace.py parallel
python3 web/tools/capture_trace.py mult_no_lsq
python3 web/tools/capture_trace.py fib_rec
ls -lh web/public/traces/
```

- [ ] **Step 5.2: Receive trace JSON files from the user**

User pastes back the contents (or uploads a tarball). Save each file at `web/public/traces/<program>.json`.

- [ ] **Step 5.3: Sanity check the traces**

```sh
cd web && python3 -c "
import json, sys
for p in ['parallel','mult_no_lsq','fib_rec']:
    d = json.load(open(f'public/traces/{p}.json'))
    print(p, 'snapshots=', len(d['snapshots']), 'first cycle=', d['snapshots'][0]['cycle'], 'last=', d['snapshots'][-1]['cycle'])
"
```
Expected output: three lines, each showing a non-zero snapshot count and a sensible cycle range (last > first).

- [ ] **Step 5.4: Commit the traces**

```sh
git add web/public/traces/
git commit -m "chore(web): add captured RTL traces for parallel, mult_no_lsq, fib_rec"
```

---

## Phase 3 — Data layer (parallelizable — Tasks 6/7/8 can dispatch in one Agent batch)

### Task 6: `lib/architecture.ts` — module metadata for the landing diagram

**Files:**
- Create: `web/lib/architecture.ts`

- [ ] **Step 6.1: Type-checked module list**

Create `web/lib/architecture.ts`:
```ts
/** A box on the landing-page architecture diagram. */
export interface PipelineModule {
  id: string;                     // unique stable id; used in URLs and as React key
  name: string;                   // display name in the box
  category: 'frontend' | 'backend' | 'memory' | 'control';
  description: string;            // 1-paragraph summary in the side panel
  parameters: { key: string; value: string }[];
  files: { path: string; githubUrl: string }[];
  advancedFeatures: string[];     // ids from features.ts
}

const REPO = 'https://github.com/CSEE4340-26/p4.GaPiChiXuXu';
const blob = (path: string) => `${REPO}/blob/release/${path}`;

export const MODULES: PipelineModule[] = [
  {
    id: 'fetch',
    name: 'Fetch (2-wide)',
    category: 'frontend',
    description:
      'Two-wide instruction fetch reading the I-cache. The PC drives both the cache and the branch predictor in parallel; on a predicted-taken hit, fetch redirects on the same cycle.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'icache',
    name: 'I-Cache',
    category: 'memory',
    description:
      '256-byte instruction cache returning an 8-byte line per hit (carries two instructions). Paired with a one-line stream-buffer prefetcher.',
    parameters: [{ key: 'capacity', value: '256 B' }, { key: 'line size', value: '8 B' }],
    files: [
      { path: 'verilog/icache.sv', githubUrl: blob('verilog/icache.sv') },
      { path: 'verilog/stream_buffer.sv', githubUrl: blob('verilog/stream_buffer.sv') },
    ],
    advancedFeatures: ['prefetch'],
  },
  {
    id: 'branch-predictor',
    name: 'Branch Predictor',
    category: 'frontend',
    description:
      'Combinational lookup at fetch: a 32-entry direct-mapped BTB, a 64-entry gshare direction predictor, and a 16-entry RAS for returns. Updates fire once per committing branch.',
    parameters: [
      { key: 'BTB entries', value: '32' },
      { key: 'BHT entries', value: '64' },
      { key: 'RAS depth', value: '16' },
    ],
    files: [{ path: 'verilog/branch_predictor.sv', githubUrl: blob('verilog/branch_predictor.sv') }],
    advancedFeatures: ['gshare', 'ras'],
  },
  {
    id: 'decode',
    name: 'Decode (2-wide)',
    category: 'frontend',
    description:
      'Two parallel decoders working on the two halves of a fetched line. Reused largely unchanged from the in-order Project 3 pipeline.',
    parameters: [],
    files: [{ path: 'verilog/decoder.sv', githubUrl: blob('verilog/decoder.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'rob',
    name: 'ROB + RAT',
    category: 'control',
    description:
      'Reorder Buffer doubles as the physical register file and embeds the 32-entry RAT inside it. Allocates and commits two slots per cycle. The stale-clear protection at commit prevents a younger producer from being erased.',
    parameters: [{ key: 'ROB_SZ', value: '16' }],
    files: [{ path: 'verilog/rob.sv', githubUrl: blob('verilog/rob.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'rs',
    name: 'Reservation Station',
    category: 'control',
    description:
      'Holds dispatched instructions until their two source operands are ready, then issues to a functional unit. The selector reads registered ready bits only — a combinational read created a feedback loop that froze the simulator on tight loops.',
    parameters: [{ key: 'RS_SZ', value: '16' }],
    files: [{ path: 'verilog/rs.sv', githubUrl: blob('verilog/rs.sv') }],
    advancedFeatures: ['superscalar', 'etb'],
  },
  {
    id: 'lsq',
    name: 'Load-Store Queue',
    category: 'memory',
    description:
      'FIFO of 8 entries. Memory ops bypass the RS at dispatch and allocate directly. Only the head talks to the cache. Stores hold (addr, data, mem_size) until commit; loads check older stores for STLF before going to cache.',
    parameters: [{ key: 'LSQ_SZ', value: '8' }],
    files: [{ path: 'verilog/lsq.sv', githubUrl: blob('verilog/lsq.sv') }],
    advancedFeatures: ['stlf'],
  },
  {
    id: 'alu',
    name: 'ALU × 2',
    category: 'backend',
    description:
      'Two 1-cycle integer ALUs, lets two independent integer ops finish per cycle.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'mult',
    name: 'Multiplier',
    category: 'backend',
    description:
      'Pipelined multiplier from Project 2, 5 stages. Drives the early-tag-broadcast sideband one cycle before the final result lands on the CDB.',
    parameters: [{ key: 'MULT_STAGES', value: '5' }],
    files: [
      { path: 'verilog/mult.sv', githubUrl: blob('verilog/mult.sv') },
      { path: 'verilog/mult_stage.sv', githubUrl: blob('verilog/mult_stage.sv') },
    ],
    advancedFeatures: ['etb'],
  },
  {
    id: 'branch-resolver',
    name: 'Branch Resolver',
    category: 'backend',
    description:
      'Inline unit that resolves conditional branches and produces JAL/JALR targets. Resolution travels on the CDB; PC redirect happens at commit, not at execute.',
    parameters: [],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: [],
  },
  {
    id: 'dcache',
    name: 'D-Cache',
    category: 'memory',
    description:
      '256-byte 2-way set-associative, write-back, write-allocate D-cache with byte-granular valid/dirty masks for sub-word stores. One LRU bit per set. Paired with a one-line stream-buffer prefetcher on the data side.',
    parameters: [
      { key: 'capacity', value: '256 B' },
      { key: 'sets', value: '16' },
      { key: 'ways', value: '2' },
      { key: 'line size', value: '8 B' },
    ],
    files: [{ path: 'verilog/dcache.sv', githubUrl: blob('verilog/dcache.sv') }],
    advancedFeatures: ['set-associative', 'prefetch'],
  },
  {
    id: 'cdb',
    name: 'CDB (2 slots)',
    category: 'control',
    description:
      'Two-slot Common Data Bus. Per-slot priority is MULT > LD > ALU. Stores never use the CDB; they signal completion via a sideband to the ROB.',
    parameters: [{ key: 'slots', value: '2' }],
    files: [{ path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') }],
    advancedFeatures: ['superscalar'],
  },
  {
    id: 'commit',
    name: 'Commit (2-wide) + Arch RegFile',
    category: 'control',
    description:
      'Retires up to 2 ROB entries per cycle in program order. Writes the architectural register file. Runs the mispredict check; on disagreement, raises a one-cycle redirect that flushes RS, LSQ, and in-flight MULT.',
    parameters: [],
    files: [
      { path: 'verilog/pipeline.sv', githubUrl: blob('verilog/pipeline.sv') },
      { path: 'verilog/regfile.sv', githubUrl: blob('verilog/regfile.sv') },
    ],
    advancedFeatures: ['superscalar'],
  },
];
```

- [ ] **Step 6.2: Commit**

```sh
git add web/lib/architecture.ts
git commit -m "feat(web): module metadata for landing-page architecture diagram"
```

---

### Task 7: `lib/results.ts` — Tables II & III, branch-acc, CPI data

**Files:**
- Create: `web/lib/results.ts`

- [ ] **Step 7.1: Type-checked results**

Create `web/lib/results.ts` (numbers transcribed verbatim from Tables II & III in `doc/final-report/4340-final-report.md`):
```ts
export interface ProgramResult {
  program: string;
  cyclesOoOBase: number;        // OoO base (all 5 ablate-able features off)
  cyclesAllOn: number;          // all 7 features on
  deltaPct: number;             // (allOn - base) / base * 100, signed
  cpiAllOn: number;
  branchAccAllOn: number | null; // null if program has no conditional branches
}

export interface AblationRow {
  feature: string;
  geomeanDeltaPctWhenDisabled: number;
  worstCaseProgram: string;
  worstCaseDeltaPct: number;
  source: 'ablation' | 'analytical';
}

export const PROGRAM_RESULTS: ProgramResult[] = [
  { program: 'alexnet',         cyclesOoOBase: 9_186_436, cyclesAllOn: 4_730_247, deltaPct: -48.51, cpiAllOn: 22.63, branchAccAllOn: 84.74 },
  { program: 'backtrack',       cyclesOoOBase:   250_581, cyclesAllOn:   146_853, deltaPct: -41.40, cpiAllOn: 20.39, branchAccAllOn: 83.74 },
  { program: 'basic_malloc',    cyclesOoOBase:    49_284, cyclesAllOn:    27_798, deltaPct: -43.60, cpiAllOn: 29.45, branchAccAllOn: 56.39 },
  { program: 'bfs',             cyclesOoOBase:   111_376, cyclesAllOn:    66_438, deltaPct: -40.35, cpiAllOn: 19.07, branchAccAllOn: 64.31 },
  { program: 'btest1',          cyclesOoOBase:    17_087, cyclesAllOn:    10_357, deltaPct: -39.39, cpiAllOn: 44.84, branchAccAllOn: 60.00 },
  { program: 'btest2',          cyclesOoOBase:    27_207, cyclesAllOn:    14_013, deltaPct: -48.50, cpiAllOn: 30.66, branchAccAllOn: 33.33 },
  { program: 'copy',            cyclesOoOBase:     3_686, cyclesAllOn:     3_472, deltaPct:  -5.81, cpiAllOn: 26.30, branchAccAllOn: 87.50 },
  { program: 'copy_long',       cyclesOoOBase:     5_773, cyclesAllOn:     5_264, deltaPct:  -8.82, cpiAllOn:  8.89, branchAccAllOn: 88.23 },
  { program: 'dft',             cyclesOoOBase: 1_685_731, cyclesAllOn: 1_008_057, deltaPct: -40.20, cpiAllOn: 17.42, branchAccAllOn: 82.48 },
  { program: 'evens',           cyclesOoOBase:     1_166, cyclesAllOn:     1_170, deltaPct:  +0.34, cpiAllOn: 11.82, branchAccAllOn: 76.74 },
  { program: 'evens_long',      cyclesOoOBase:     2_934, cyclesAllOn:     2_563, deltaPct: -12.65, cpiAllOn:  7.63, branchAccAllOn: 76.74 },
  { program: 'fc_forward',      cyclesOoOBase:    51_721, cyclesAllOn:    33_419, deltaPct: -35.39, cpiAllOn:  4.97, branchAccAllOn: 82.88 },
  { program: 'fib',             cyclesOoOBase:     2_371, cyclesAllOn:     2_048, deltaPct: -13.62, cpiAllOn: 13.65, branchAccAllOn: 86.66 },
  { program: 'fib_long',        cyclesOoOBase:     6_240, cyclesAllOn:     4_940, deltaPct: -20.83, cpiAllOn:  7.74, branchAccAllOn: 85.71 },
  { program: 'fib_rec',         cyclesOoOBase:    32_018, cyclesAllOn:    29_132, deltaPct:  -9.01, cpiAllOn:  2.44, branchAccAllOn: 65.56 },
  { program: 'graph',           cyclesOoOBase:   450_656, cyclesAllOn:   259_337, deltaPct: -42.45, cpiAllOn: 23.31, branchAccAllOn: 59.83 },
  { program: 'haha',            cyclesOoOBase:       935, cyclesAllOn:       528, deltaPct: -43.53, cpiAllOn: 29.33, branchAccAllOn: null  },
  { program: 'halt',            cyclesOoOBase:       106, cyclesAllOn:       106, deltaPct:   0.00, cpiAllOn: 106.0, branchAccAllOn: null  },
  { program: 'insertion',       cyclesOoOBase:     3_093, cyclesAllOn:     3_159, deltaPct:  +2.13, cpiAllOn:  5.27, branchAccAllOn: 87.27 },
  { program: 'insertionsort',   cyclesOoOBase:   750_097, cyclesAllOn:   554_803, deltaPct: -26.04, cpiAllOn:  3.88, branchAccAllOn: 88.46 },
  { program: 'matrix_mult_rec', cyclesOoOBase:   712_425, cyclesAllOn:   662_478, deltaPct:  -7.01, cpiAllOn: 30.56, branchAccAllOn: 94.37 },
  { program: 'mergesort',       cyclesOoOBase:   294_331, cyclesAllOn:   200_073, deltaPct: -32.02, cpiAllOn: 21.10, branchAccAllOn: 75.38 },
  { program: 'mult',            cyclesOoOBase:     7_565, cyclesAllOn:     7_430, deltaPct:  -1.78, cpiAllOn: 22.79, branchAccAllOn: 83.33 },
  { program: 'mult_no_lsq',     cyclesOoOBase:     2_920, cyclesAllOn:     2_251, deltaPct: -22.91, cpiAllOn:  7.95, branchAccAllOn: 88.23 },
  { program: 'no_hazard',       cyclesOoOBase:       725, cyclesAllOn:       422, deltaPct: -41.79, cpiAllOn: 30.14, branchAccAllOn: null  },
  { program: 'omegalul',        cyclesOoOBase:     3_944, cyclesAllOn:     2_220, deltaPct: -43.71, cpiAllOn: 30.00, branchAccAllOn: 33.33 },
  { program: 'outer_product',   cyclesOoOBase: 3_983_006, cyclesAllOn: 3_166_519, deltaPct: -20.50, cpiAllOn:  4.24, branchAccAllOn: 85.18 },
  { program: 'parallel',        cyclesOoOBase:     2_328, cyclesAllOn:     2_135, deltaPct:  -8.29, cpiAllOn: 10.68, branchAccAllOn: 87.50 },
  { program: 'priority_queue',  cyclesOoOBase:    77_416, cyclesAllOn:    43_389, deltaPct: -43.95, cpiAllOn: 29.82, branchAccAllOn: 56.47 },
  { program: 'quicksort',       cyclesOoOBase:   871_758, cyclesAllOn:   568_772, deltaPct: -34.76, cpiAllOn:  5.96, branchAccAllOn: 84.28 },
  { program: 'sampler',         cyclesOoOBase:     6_220, cyclesAllOn:     3_378, deltaPct: -45.69, cpiAllOn: 30.71, branchAccAllOn: 74.35 },
  { program: 'saxpy',           cyclesOoOBase:     4_515, cyclesAllOn:     4_230, deltaPct:  -6.31, cpiAllOn: 22.62, branchAccAllOn: 85.00 },
  { program: 'sort_search',     cyclesOoOBase:   718_427, cyclesAllOn:   600_637, deltaPct: -16.40, cpiAllOn:  3.30, branchAccAllOn: 85.81 },
];

export const SUITE_SUMMARY = {
  programCount: 33,
  geomeanDeltaPct: -27.46,
  arithMeanDeltaPct: -25.54,
  geomeanCpi: 14.87,
  arithMeanCpi: 20.77,
  geomeanBranchAcc: 74.03,
  arithMeanBranchAcc: 76.13,
  branchAccLiftOverBimodalPp: 8.87,
  bimodalArithMeanBranchAcc: 67.25,
};

export const ABLATION: AblationRow[] = [
  { feature: 'Next-line prefetch',     geomeanDeltaPctWhenDisabled: 37.14, worstCaseProgram: 'alexnet',       worstCaseDeltaPct: 94.22, source: 'ablation' },
  { feature: 'STLF',                   geomeanDeltaPctWhenDisabled:  0.20, worstCaseProgram: 'insertionsort', worstCaseDeltaPct:  1.64, source: 'ablation' },
  { feature: 'gshare',                 geomeanDeltaPctWhenDisabled:  0.19, worstCaseProgram: 'fib_rec',       worstCaseDeltaPct:  9.65, source: 'ablation' },
  { feature: 'ETB',                    geomeanDeltaPctWhenDisabled:  0.10, worstCaseProgram: 'outer_product', worstCaseDeltaPct:  1.07, source: 'ablation' },
  { feature: 'RAS',                    geomeanDeltaPctWhenDisabled:  0.10, worstCaseProgram: 'basic_malloc',  worstCaseDeltaPct:  0.52, source: 'ablation' },
  { feature: '2-way superscalar',      geomeanDeltaPctWhenDisabled:   NaN, worstCaseProgram: '—',             worstCaseDeltaPct:   NaN, source: 'analytical' },
  { feature: '2-way set-assoc D-cache', geomeanDeltaPctWhenDisabled:  NaN, worstCaseProgram: '—',             worstCaseDeltaPct:   NaN, source: 'analytical' },
  { feature: 'all 5 disabled',         geomeanDeltaPctWhenDisabled: 37.86, worstCaseProgram: 'alexnet',       worstCaseDeltaPct: 94.21, source: 'ablation' },
];

export const TIMING = {
  clockTargetPs: 1000,
  worstSlackPs: -797.58,
  criticalPath: 'lsq_0/head_reg[2] → rob_0/entries_reg[2][take_branch]',
  secondWorstSlackPs: -797.55,
  moduleTbsAllPass: true,
};
```

- [ ] **Step 7.2: Spot-check that the data adds up**

```sh
cd web && npx tsx -e "
import { PROGRAM_RESULTS, SUITE_SUMMARY } from './lib/results';
const passing = PROGRAM_RESULTS.length;
const speedups = PROGRAM_RESULTS.filter(p => p.deltaPct < 0).length;
const regressions = PROGRAM_RESULTS.filter(p => p.deltaPct > 0).length;
console.log({ passing, speedups, regressions, ...SUITE_SUMMARY });
"
```
Expected: `passing: 33, speedups: 30, regressions: 2`. (`halt` is the third — it's exactly 0.) If `npx tsx` is not available, install it first: `npm install --save-dev tsx`.

- [ ] **Step 7.3: Commit**

```sh
git add web/lib/results.ts
git commit -m "feat(web): per-program results, ablation, suite summary, timing"
```

---

### Task 8: `lib/features.ts` — 7 advanced features metadata

**Files:**
- Create: `web/lib/features.ts`

- [ ] **Step 8.1: Type-checked feature list**

Create `web/lib/features.ts`:
```ts
export type FeatureTier = 'difficult' | 'simpler';

export interface AdvancedFeature {
  id: string;                       // 'superscalar', 'etb', 'gshare', 'ras', 'stlf', 'prefetch', 'set-associative'
  name: string;
  tier: FeatureTier;
  oneLiner: string;                 // <= 90 chars; for landing-page pill
  hostModuleIds: string[];          // architecture.ts module ids the feature lives in
  marginalDeltaPctWhenDisabled: number | null;  // null for analytical (structural)
  worstCaseProgram: string | null;
  worstCaseDeltaPct: number | null;
  deepDiveAnchor: string;           // '#superscalar' etc., used for /deep-dive#anchor links
}

export const FEATURES: AdvancedFeature[] = [
  {
    id: 'superscalar',
    name: '2-way Superscalar',
    tier: 'difficult',
    oneLiner: 'Two-wide fetch, decode, dispatch, and commit. Doubles the IPC ceiling.',
    hostModuleIds: ['fetch', 'decode', 'rob', 'rs', 'cdb', 'commit'],
    marginalDeltaPctWhenDisabled: null,
    worstCaseProgram: null,
    worstCaseDeltaPct: null,
    deepDiveAnchor: '#superscalar',
  },
  {
    id: 'etb',
    name: 'Early Tag Broadcast',
    tier: 'difficult',
    oneLiner: 'MULT wakes its dependents one cycle before the result lands on the CDB.',
    hostModuleIds: ['mult', 'rs'],
    marginalDeltaPctWhenDisabled: 0.10,
    worstCaseProgram: 'outer_product',
    worstCaseDeltaPct: 1.07,
    deepDiveAnchor: '#etb',
  },
  {
    id: 'gshare',
    name: 'gshare Predictor',
    tier: 'simpler',
    oneLiner: 'XOR-folded global history with PC bits to specialize on hot branches.',
    hostModuleIds: ['branch-predictor'],
    marginalDeltaPctWhenDisabled: 0.19,
    worstCaseProgram: 'fib_rec',
    worstCaseDeltaPct: 9.65,
    deepDiveAnchor: '#gshare',
  },
  {
    id: 'ras',
    name: 'Return Address Stack',
    tier: 'simpler',
    oneLiner: '16-entry hardware stack. Returns predicted by where they were called.',
    hostModuleIds: ['branch-predictor'],
    marginalDeltaPctWhenDisabled: 0.10,
    worstCaseProgram: 'basic_malloc',
    worstCaseDeltaPct: 0.52,
    deepDiveAnchor: '#ras',
  },
  {
    id: 'stlf',
    name: 'Store-to-Load Forwarding',
    tier: 'simpler',
    oneLiner: 'A load behind a fully-covering older store completes from the LSQ.',
    hostModuleIds: ['lsq'],
    marginalDeltaPctWhenDisabled: 0.20,
    worstCaseProgram: 'insertionsort',
    worstCaseDeltaPct: 1.64,
    deepDiveAnchor: '#stlf',
  },
  {
    id: 'prefetch',
    name: 'Next-line Prefetch',
    tier: 'simpler',
    oneLiner: 'One-line stream buffer fetches line N+1 in parallel on a miss for line N.',
    hostModuleIds: ['icache', 'dcache'],
    marginalDeltaPctWhenDisabled: 37.14,
    worstCaseProgram: 'alexnet',
    worstCaseDeltaPct: 94.22,
    deepDiveAnchor: '#prefetch',
  },
  {
    id: 'set-associative',
    name: '2-way Set-Associative D-Cache',
    tier: 'simpler',
    oneLiner: '16 sets × 2 ways with 1-bit LRU. Resolves direct-mapped conflict misses.',
    hostModuleIds: ['dcache'],
    marginalDeltaPctWhenDisabled: null,
    worstCaseProgram: null,
    worstCaseDeltaPct: null,
    deepDiveAnchor: '#set-associative',
  },
];
```

- [ ] **Step 8.2: Commit**

```sh
git add web/lib/features.ts
git commit -m "feat(web): advanced features metadata"
```

---

## Phase 4 — Landing page (Tasks 9–15; 9, 13, 15 can dispatch in parallel after 6/7/8 land; 10/11/12 sequential within architecture cluster)

### Task 9: Hero + headline numbers

**Files:**
- Create: `web/components/landing/Hero.tsx`, `web/components/landing/HeadlineNumbers.tsx`

- [ ] **Step 9.1: Hero**

Create `web/components/landing/Hero.tsx`:
```tsx
import Link from 'next/link';
import { Button } from '@/components/ui/Button';
import { HeadlineNumbers } from './HeadlineNumbers';

export function Hero() {
  return (
    <section className="mx-auto max-w-7xl px-6 pt-16 pb-24">
      <p className="text-sm uppercase tracking-widest text-iris-600 mb-4">
        EECS 4340 · Spring 2026 · Columbia University
      </p>
      <h1 className="text-5xl md:text-6xl font-semibold text-plum-500 leading-tight tracking-tight">
        Out-of-Order RV32IM Processor
      </h1>
      <p className="mt-6 max-w-3xl text-lg text-ink-muted">
        A synthesizable, P6-style 2-way superscalar out-of-order RISC-V processor in
        SystemVerilog. Built on top of the Project 3 in-order pipeline, with seven
        advanced features layered on the base machine.
      </p>
      <div className="mt-10 flex flex-wrap gap-4">
        <Link href="/simulator">
          <Button variant="primary">Open the simulator →</Button>
        </Link>
        <Link href="/deep-dive">
          <Button variant="soft">Read the deep dive</Button>
        </Link>
      </div>
      <HeadlineNumbers />
    </section>
  );
}
```

- [ ] **Step 9.2: Headline numbers**

Create `web/components/landing/HeadlineNumbers.tsx`:
```tsx
import { Card } from '@/components/ui/Card';
import { SUITE_SUMMARY, TIMING } from '@/lib/results';

interface Stat { label: string; value: string; sub?: string; }

const STATS: Stat[] = [
  { label: 'Programs passing', value: '33 / 33', sub: 'RTL + synthesized netlist' },
  { label: 'Geomean cycle reduction', value: `${SUITE_SUMMARY.geomeanDeltaPct.toFixed(2)}%`, sub: 'OoO base → all-on' },
  { label: 'Geomean branch accuracy', value: `${SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%`, sub: `+${SUITE_SUMMARY.branchAccLiftOverBimodalPp.toFixed(2)} pp over bimodal` },
  { label: 'Worst slack at 1000 ps', value: `${TIMING.worstSlackPs} ps`, sub: 'functionally bit-equivalent' },
];

export function HeadlineNumbers() {
  return (
    <div className="mt-16 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
      {STATS.map((s) => (
        <Card key={s.label}>
          <p className="text-xs uppercase tracking-widest text-ink-subtle">{s.label}</p>
          <p className="mt-3 text-3xl font-semibold text-plum-500">{s.value}</p>
          {s.sub && <p className="mt-2 text-sm text-ink-muted">{s.sub}</p>}
        </Card>
      ))}
    </div>
  );
}
```

- [ ] **Step 9.3: Commit**

```sh
git add web/components/landing/
git commit -m "feat(web): hero + headline numbers"
```

---

### Task 10: Interactive architecture diagram (the big one)

**Files:**
- Create: `web/components/architecture/ArchDiagram.tsx`

This is the most complex component. Approach: hand-built SVG with absolute positioning, React state for selected module, Framer Motion for hover/click polish.

- [ ] **Step 10.1: Implement ArchDiagram**

Create `web/components/architecture/ArchDiagram.tsx`. The implementing subagent should:

1. Lay out 13 module boxes in the topology described in `prd.md` §6.2. Use a 1200×640 viewBox.
2. For each module from `MODULES` in `lib/architecture.ts`, render an SVG `<g>` containing a `<rect>` (rounded, plum stroke, white fill) and a `<text>` (module name).
3. Connect boxes with `<path>` arrows. Use `marker-end` for arrowheads. Iris blue stroke (`#5364C0`).
4. On hover, the box's stroke widens (Framer Motion or pure CSS); shadow appears.
5. On click, set state `selectedId` and call a prop callback `onSelect(moduleId: string)`.
6. Below the SVG, render a small legend (Frontend / Backend / Memory / Control color dots).

Component signature:
```tsx
'use client';
import { useState } from 'react';
import { motion } from 'framer-motion';
import { MODULES, type PipelineModule } from '@/lib/architecture';

interface Props {
  highlightedFeatureIds?: string[];   // when set, modules whose advancedFeatures intersect
                                      // are highlighted with an orchid pink overlay
  onSelect: (moduleId: string) => void;
}

export function ArchDiagram({ highlightedFeatureIds = [], onSelect }: Props) { ... }
```

Use this layout grid (x, y in viewBox units, all boxes 180w × 56h):
```
Fetch                (510, 30)
I-Cache              (210, 30)
Branch Predictor     (810, 30)
Decode               (510, 130)
ROB + RAT            (510, 230)
RS                   (310, 350)   LSQ                (710, 350)
ALU × 2              (110, 470)   D-Cache            (910, 470)
MULT                 (310, 470)
Branch Resolver      (510, 470)
CDB (2 slots)        (510, 580)
Commit               (510, 660 — overflow allowed; viewBox = "0 0 1200 720")
```
Adjust if the layout looks crowded — the implementing subagent has visual judgment.

Arrows to draw (curved, with arrowheads):
- I-Cache → Fetch
- Branch Predictor → Fetch
- Fetch → Decode
- Decode → ROB+RAT
- ROB+RAT → RS
- ROB+RAT → LSQ
- RS → {ALU, MULT, Branch Resolver}
- LSQ → D-Cache
- {ALU, MULT, Branch Resolver, D-Cache} → CDB (multi-source convergence)
- CDB → Commit
- CDB → ROB+RAT (writeback)

The "advanced features" overlay (controlled by `highlightedFeatureIds`): when any feature id is in this set, every module whose `advancedFeatures` intersects gets an orchid-pink translucent rect underlay (`fill="rgba(195,79,162,0.15)"`).

- [ ] **Step 10.2: Visual smoke test**

Temporarily import `<ArchDiagram onSelect={() => {}} />` into a test route or directly into `app/page.tsx` and run `npm run dev`. Confirm: all 13 boxes render, arrows connect them, hover/click work, no console errors.

- [ ] **Step 10.3: Commit**

```sh
git add web/components/architecture/ArchDiagram.tsx
git commit -m "feat(web): interactive architecture diagram"
```

---

### Task 11: Module side panel

**Files:**
- Create: `web/components/architecture/ModulePanel.tsx`

- [ ] **Step 11.1: Implement ModulePanel**

Create `web/components/architecture/ModulePanel.tsx`:
```tsx
'use client';
import { SidePanel } from '@/components/ui/SidePanel';
import { MODULES } from '@/lib/architecture';
import { FEATURES } from '@/lib/features';

interface Props {
  moduleId: string | null;
  onClose: () => void;
}

export function ModulePanel({ moduleId, onClose }: Props) {
  const m = MODULES.find((x) => x.id === moduleId);
  return (
    <SidePanel open={!!m} onClose={onClose}>
      {m && (
        <div>
          <p className="text-xs uppercase tracking-widest text-iris-600">{m.category}</p>
          <h2 className="mt-2 text-3xl font-semibold text-plum-500">{m.name}</h2>
          <p className="mt-4 text-ink leading-relaxed">{m.description}</p>

          {m.parameters.length > 0 && (
            <>
              <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
                Parameters
              </h3>
              <dl className="mt-3 grid grid-cols-2 gap-y-2 text-sm">
                {m.parameters.map((p) => (
                  <div key={p.key} className="contents">
                    <dt className="text-ink-muted">{p.key}</dt>
                    <dd className="text-ink font-mono">{p.value}</dd>
                  </div>
                ))}
              </dl>
            </>
          )}

          <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
            Source
          </h3>
          <ul className="mt-3 space-y-1 text-sm">
            {m.files.map((f) => (
              <li key={f.path}>
                <a href={f.githubUrl} target="_blank" rel="noopener noreferrer"
                   className="text-iris-600 hover:text-plum-500 font-mono">
                  {f.path}
                </a>
              </li>
            ))}
          </ul>

          {m.advancedFeatures.length > 0 && (
            <>
              <h3 className="mt-8 text-sm font-semibold uppercase tracking-widest text-ink-subtle">
                Advanced features hosted here
              </h3>
              <ul className="mt-3 flex flex-wrap gap-2">
                {m.advancedFeatures.map((fid) => {
                  const f = FEATURES.find((x) => x.id === fid);
                  if (!f) return null;
                  return (
                    <li key={fid}>
                      <a href={`/deep-dive${f.deepDiveAnchor}`}
                         className="inline-flex items-center rounded-full bg-orchid-50 text-plum-500 px-3 py-1 text-xs">
                        {f.name}
                      </a>
                    </li>
                  );
                })}
              </ul>
            </>
          )}
        </div>
      )}
    </SidePanel>
  );
}
```

- [ ] **Step 11.2: Commit**

```sh
git add web/components/architecture/ModulePanel.tsx
git commit -m "feat(web): module side panel"
```

---

### Task 12: Advanced feature toggle

**Files:**
- Create: `web/components/architecture/AdvancedFeatureToggle.tsx`

- [ ] **Step 12.1: Implement toggle**

Create `web/components/architecture/AdvancedFeatureToggle.tsx`:
```tsx
'use client';
import { FEATURES } from '@/lib/features';
import clsx from 'clsx';

interface Props {
  selectedFeatureIds: string[];
  onChange: (ids: string[]) => void;
}

export function AdvancedFeatureToggle({ selectedFeatureIds, onChange }: Props) {
  const allOn = selectedFeatureIds.length === FEATURES.length;
  return (
    <div className="mb-6 flex flex-wrap items-center gap-3">
      <button
        onClick={() => onChange(allOn ? [] : FEATURES.map((f) => f.id))}
        className={clsx(
          'rounded-full px-4 py-1.5 text-sm transition-colors',
          allOn ? 'bg-plum-500 text-white' : 'bg-snow-500 text-ink-muted border border-snow-600',
        )}
      >
        {allOn ? 'Hide advanced features' : 'Show all advanced features'}
      </button>
      {FEATURES.map((f) => {
        const on = selectedFeatureIds.includes(f.id);
        return (
          <button
            key={f.id}
            onClick={() =>
              onChange(on ? selectedFeatureIds.filter((id) => id !== f.id) : [...selectedFeatureIds, f.id])
            }
            className={clsx(
              'rounded-full px-3 py-1 text-xs transition-colors',
              on ? 'bg-orchid-500 text-white' : 'bg-orchid-50 text-plum-500 hover:bg-orchid-100',
            )}
          >
            {f.name}
          </button>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 12.2: Commit**

```sh
git add web/components/architecture/AdvancedFeatureToggle.tsx
git commit -m "feat(web): advanced feature toggle"
```

---

### Task 13: Feature pills section

**Files:**
- Create: `web/components/landing/FeaturePills.tsx`

- [ ] **Step 13.1: Implement**

Create `web/components/landing/FeaturePills.tsx`:
```tsx
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { FEATURES } from '@/lib/features';

export function FeaturePills() {
  return (
    <section className="mx-auto max-w-7xl px-6 py-24">
      <h2 className="text-3xl font-semibold text-plum-500 mb-3">Seven advanced features</h2>
      <p className="text-ink-muted max-w-2xl mb-12">
        Two from the difficult tier and five from the simpler tier, layered on top of the
        base out-of-order pipeline.
      </p>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {FEATURES.map((f) => (
          <Link key={f.id} href={`/deep-dive${f.deepDiveAnchor}`}>
            <Card className="h-full hover:shadow-strong transition-shadow cursor-pointer">
              <div className="flex items-start justify-between">
                <h3 className="text-lg font-semibold text-plum-500">{f.name}</h3>
                <span className="text-xs uppercase tracking-widest text-iris-600">
                  {f.tier}
                </span>
              </div>
              <p className="mt-3 text-sm text-ink-muted">{f.oneLiner}</p>
              {f.marginalDeltaPctWhenDisabled !== null ? (
                <p className="mt-4 text-xs text-ink-subtle">
                  Disabling raises geomean cycles by{' '}
                  <span className="text-orchid-600 font-mono">
                    +{f.marginalDeltaPctWhenDisabled.toFixed(2)}%
                  </span>
                </p>
              ) : (
                <p className="mt-4 text-xs text-ink-subtle">Structural — see deep dive</p>
              )}
            </Card>
          </Link>
        ))}
      </div>
    </section>
  );
}
```

- [ ] **Step 13.2: Commit**

```sh
git add web/components/landing/FeaturePills.tsx
git commit -m "feat(web): advanced-feature pill cards"
```

---

### Task 14: Landing page assembly

**Files:**
- Modify: `web/app/page.tsx`

- [ ] **Step 14.1: Compose the landing page**

Replace `web/app/page.tsx`:
```tsx
'use client';
import { useState } from 'react';
import { Hero } from '@/components/landing/Hero';
import { ArchDiagram } from '@/components/architecture/ArchDiagram';
import { ModulePanel } from '@/components/architecture/ModulePanel';
import { AdvancedFeatureToggle } from '@/components/architecture/AdvancedFeatureToggle';
import { PerProgramSpeedupChart } from '@/components/charts/PerProgramSpeedupChart';
import { FeaturePills } from '@/components/landing/FeaturePills';

export default function HomePage() {
  const [selectedModuleId, setSelectedModuleId] = useState<string | null>(null);
  const [highlightedFeatureIds, setHighlightedFeatureIds] = useState<string[]>([]);

  return (
    <>
      <Hero />

      <section className="mx-auto max-w-7xl px-6 py-16">
        <h2 className="text-3xl font-semibold text-plum-500 mb-2">Architecture</h2>
        <p className="text-ink-muted max-w-2xl mb-8">
          Click any module to read what it does. Toggle the pills to highlight the advanced
          features in their host modules.
        </p>
        <AdvancedFeatureToggle
          selectedFeatureIds={highlightedFeatureIds}
          onChange={setHighlightedFeatureIds}
        />
        <ArchDiagram
          highlightedFeatureIds={highlightedFeatureIds}
          onSelect={setSelectedModuleId}
        />
      </section>

      <section className="mx-auto max-w-7xl px-6 py-16">
        <h2 className="text-3xl font-semibold text-plum-500 mb-2">Per-program results</h2>
        <p className="text-ink-muted max-w-2xl mb-8">
          Cycle-count change from disabling all five ablate-able advanced features
          (OoO base) to running all seven (all-on). Hover any bar for details.
        </p>
        <PerProgramSpeedupChart />
      </section>

      <FeaturePills />

      <ModulePanel moduleId={selectedModuleId} onClose={() => setSelectedModuleId(null)} />
    </>
  );
}
```

- [ ] **Step 14.2: Visual QA via playwright-cli**

```sh
cd web && npm run dev   # leave running in background
```
Invoke the `playwright-cli` skill: navigate to http://localhost:3000, take a screenshot,
click an architecture-diagram module box and confirm the side panel opens, toggle the
"Show all advanced features" pill and confirm modules highlight, click the hero CTA and
confirm navigation. Console must be clean of React warnings or errors.

- [ ] **Step 14.3: Commit**

```sh
git add web/app/page.tsx
git commit -m "feat(web): assemble landing page"
```

---

### Task 15: Per-program speedup chart

**Files:**
- Create: `web/components/charts/PerProgramSpeedupChart.tsx`

- [ ] **Step 15.1: Implement chart**

Create `web/components/charts/PerProgramSpeedupChart.tsx`:
```tsx
'use client';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Cell, Tooltip, ReferenceLine } from 'recharts';
import { PROGRAM_RESULTS } from '@/lib/results';

const sorted = [...PROGRAM_RESULTS].sort((a, b) => a.deltaPct - b.deltaPct);

export function PerProgramSpeedupChart() {
  return (
    <div className="h-[640px] w-full">
      <ResponsiveContainer>
        <BarChart data={sorted} layout="vertical" margin={{ top: 8, right: 60, left: 60, bottom: 8 }}>
          <XAxis type="number" domain={[-50, 5]} unit="%" stroke="#5F657A" />
          <YAxis type="category" dataKey="program" width={120} stroke="#5F657A" tick={{ fontSize: 11 }} />
          <ReferenceLine x={0} stroke="#D8DDF2" />
          <Tooltip
            contentStyle={{ background: 'white', border: '1px solid #D8DDF2', borderRadius: 12 }}
            formatter={(v: number, _name, item) => {
              const r = item.payload;
              return [
                `${v.toFixed(2)}% (${r.cyclesOoOBase.toLocaleString()} → ${r.cyclesAllOn.toLocaleString()} cycles, CPI ${r.cpiAllOn.toFixed(2)}${r.branchAccAllOn !== null ? `, branch acc ${r.branchAccAllOn.toFixed(2)}%` : ''})`,
                'Δ%',
              ];
            }}
          />
          <Bar dataKey="deltaPct">
            {sorted.map((r) => (
              <Cell key={r.program} fill={r.deltaPct > 0 ? '#C34FA2' : '#5364C0'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

- [ ] **Step 15.2: Commit**

```sh
git add web/components/charts/PerProgramSpeedupChart.tsx
git commit -m "feat(web): per-program speedup chart"
```

---

## Phase 5 — Five native React SVG figures (Tasks 17–21 dispatch fully in parallel)

Each task in this phase is self-contained: read one RTL file, draw one SVG component matching the report's prose. Subagents should be dispatched in a single batch.

### Task 17: PipelineOverviewDiagram

**Files:**
- Create: `web/components/diagrams/PipelineOverviewDiagram.tsx`
- Read for ground truth: `verilog/pipeline.sv`, plus `doc/final-report/4340-final-report.md` §III

- [ ] **Step 17.1: Implement**

Same topology as the landing-page `ArchDiagram` but simpler: no interaction, no module-panel, no feature toggle. ~600 wide. The implementing subagent should:
- Draw the same 13 boxes + arrows from Task 10's grid.
- Add a small label on the CDB arrow ("MULT > LD > ALU per slot, 2 slots").
- Plum strokes, iris arrows, white fills, snow background.

Component signature: `export function PipelineOverviewDiagram() { return <svg viewBox="0 0 800 480">...</svg>; }`

If RTL and report disagree on topology (e.g., port count, CDB priority), favor RTL and add an HTML comment in the file noting the disagreement.

- [ ] **Step 17.2: Commit**

```sh
git add web/components/diagrams/PipelineOverviewDiagram.tsx
git commit -m "feat(web): pipeline overview diagram (Fig 1 native)"
```

---

### Task 18: BranchPredictorDiagram

**Files:**
- Create: `web/components/diagrams/BranchPredictorDiagram.tsx`
- Read for ground truth: `verilog/branch_predictor.sv`, report §V.C

- [ ] **Step 18.1: Implement**

Diagram shows: fetch PC fan-out → 32-entry BTB lookup, 64-entry gshare BHT (XOR with GHR), 16-entry RAS. Output mux selecting `pred_target` from {RAS, BTB target}. Update side: shift register for GHR.

Concrete elements:
- Box "Fetch PC" (top-left)
- Box "BTB (32 entries)" — labeled "PC[6:2] index, PC[31:7] tag"
- Box "BHT (64 entries, 2-bit counters)" with input arrow labeled "PC[7:2] XOR GHR"
- Box "GHR (shift register)" feeding into the XOR
- Box "RAS (16 entries)" with stack-shaped icon
- Output mux selecting prediction

Same color discipline as Task 17. Highlight the gshare XOR in orchid pink (it's the gshare-specific element). Highlight the RAS's override path in orchid pink.

Note: RAS depth is 16, BTB is 32 entries (per report §III paragraph on RAS/BTB). Confirm in `verilog/branch_predictor.sv` and adjust if RTL differs.

- [ ] **Step 18.2: Commit**

```sh
git add web/components/diagrams/BranchPredictorDiagram.tsx
git commit -m "feat(web): gshare + RAS branch predictor diagram (Fig 2 native)"
```

---

### Task 19: DCacheDiagram

**Files:**
- Create: `web/components/diagrams/DCacheDiagram.tsx`
- Read for ground truth: `verilog/dcache.sv`, report §V.D

- [ ] **Step 19.1: Implement**

Diagram shows: 16 sets × 2 ways geometry, byte-valid + dirty masks, LRU bit per set, bus arbitration mask between D-cache and I-cache stream buffers.

Layout: a 16×2 grid representing the cache (8 visible rows × 2 columns of cache lines, with "..." for the rest). Each cell labeled "way 0 / way 1". A column on the right shows the per-byte valid (8 bits) and dirty (8 bits) masks for one selected line. Beneath, the LRU column (1 bit per set).

To the left: address decode showing which bits go to tag / index / offset.

To the right: arrows to/from main memory through the bus arbitration mask.

Highlight the second way and the LRU bit in orchid pink (the set-associative-specific elements). Highlight the bus arbitration mask in orchid pink (the prefetch-related infrastructure).

- [ ] **Step 19.2: Commit**

```sh
git add web/components/diagrams/DCacheDiagram.tsx
git commit -m "feat(web): D-cache diagram (Fig 3 native)"
```

---

### Task 20: STLFDiagram

**Files:**
- Create: `web/components/diagrams/STLFDiagram.tsx`
- Read for ground truth: `verilog/lsq.sv`, report §V.E

- [ ] **Step 20.1: Implement**

Diagram shows: LSQ FIFO with 8 entries, the address comparator that compares the load-at-head's address against every older un-committed store, the mux selecting between the forwarded store data and the cache return.

Layout: a horizontal LSQ row (8 boxes, head on the left) with the head box highlighted. Comparator block below the head, with arrows from each store entry feeding into it. A 2-input mux on the right selecting between (1) forwarded value from a matching older store and (2) D-cache return path.

Annotate the conditions that block forwarding: "older store with unresolved addr", "store data not yet arrived", "partial overlap" — each as a small label with a red ✗.

Highlight the comparator and forwarding mux in orchid pink.

- [ ] **Step 20.2: Commit**

```sh
git add web/components/diagrams/STLFDiagram.tsx
git commit -m "feat(web): STLF diagram (Fig 4 native)"
```

---

### Task 21: ETBDiagram

**Files:**
- Create: `web/components/diagrams/ETBDiagram.tsx`
- Read for ground truth: `verilog/mult.sv`, `verilog/pipeline.sv`, report §V.B

- [ ] **Step 21.1: Implement**

Diagram shows: 5-stage MULT pipeline with the early-tag tap point at stage N-1. The early-tag wire flips a registered ready bit in the RS one cycle before the value lands on the CDB. A small timing-cycle table at the bottom shows: cycle N (early tag fires, RS ready bit flips), cycle N+1 (CDB broadcasts value, dependent issues).

Layout: top half shows the MULT pipeline (5 boxes labeled stage 0 through stage 4), with an extra wire branching off stage 3 ("early_done") routed to a labeled box "RS wakeup logic". A separate, slower wire from stage 4 ("done") goes to the CDB.

Bottom half: a 4×5 grid showing 5 cycles × 4 events (multiply enters stage 4, early tag fires, RS ready flips, CDB broadcasts). Use orchid pink for the early-tag path and the early-tag column in the timing chart.

- [ ] **Step 21.2: Commit**

```sh
git add web/components/diagrams/ETBDiagram.tsx
git commit -m "feat(web): ETB timing diagram (Fig 5 native)"
```

---

## Phase 6 — Deep dive page (Tasks 22 & 23 sequential after diagrams + data)

### Task 22: Three more charts (a, b, c — parallelizable)

**Files:**
- Create: `web/components/charts/AblationChart.tsx`, `BranchAccLiftChart.tsx`, `CpiHistogram.tsx`

- [ ] **Step 22a: AblationChart**

Create `web/components/charts/AblationChart.tsx`:
```tsx
'use client';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Cell, Tooltip, ReferenceLine } from 'recharts';
import { ABLATION } from '@/lib/results';

const ablationOnly = ABLATION.filter((r) => r.source === 'ablation');

export function AblationChart() {
  return (
    <div className="h-[360px] w-full">
      <ResponsiveContainer>
        <BarChart data={ablationOnly} layout="vertical" margin={{ left: 60, right: 60, top: 8, bottom: 8 }}>
          <XAxis type="number" unit="%" domain={[0, 'auto']} stroke="#5F657A" />
          <YAxis type="category" dataKey="feature" width={150} stroke="#5F657A" tick={{ fontSize: 12 }} />
          <ReferenceLine x={0} stroke="#D8DDF2" />
          <Tooltip
            contentStyle={{ background: 'white', border: '1px solid #D8DDF2', borderRadius: 12 }}
            formatter={(v: number, _n, item) => [
              `+${v.toFixed(2)}% geomean (worst: ${item.payload.worstCaseProgram} +${item.payload.worstCaseDeltaPct.toFixed(2)}%)`,
              'Δ% when disabled',
            ]}
          />
          <Bar dataKey="geomeanDeltaPctWhenDisabled">
            {ablationOnly.map((r) => (
              <Cell key={r.feature} fill={r.feature === 'all 5 disabled' ? '#77295D' : '#5364C0'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

Commit:
```sh
git add web/components/charts/AblationChart.tsx
git commit -m "feat(web): ablation chart"
```

- [ ] **Step 22b: BranchAccLiftChart**

Create `web/components/charts/BranchAccLiftChart.tsx`. The branch accuracy data is in `PROGRAM_RESULTS[i].branchAccAllOn`; the bimodal baseline per program isn't in `lib/results.ts` directly, so this chart shows only the all-on accuracy (the lift over bimodal is +8.87 pp arith. mean — annotate that as a label rather than per-program). Use a horizontal bar chart of `branchAccAllOn` filtered to non-null entries, sorted descending. Same color discipline as `PerProgramSpeedupChart`.

```tsx
'use client';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, ReferenceLine } from 'recharts';
import { PROGRAM_RESULTS, SUITE_SUMMARY } from '@/lib/results';

const data = PROGRAM_RESULTS
  .filter((r) => r.branchAccAllOn !== null)
  .map((r) => ({ program: r.program, branchAccAllOn: r.branchAccAllOn as number }))
  .sort((a, b) => b.branchAccAllOn - a.branchAccAllOn);

export function BranchAccLiftChart() {
  return (
    <div className="h-[640px] w-full">
      <ResponsiveContainer>
        <BarChart data={data} layout="vertical" margin={{ left: 60, right: 60, top: 8, bottom: 8 }}>
          <XAxis type="number" unit="%" domain={[0, 100]} stroke="#5F657A" />
          <YAxis type="category" dataKey="program" width={120} stroke="#5F657A" tick={{ fontSize: 11 }} />
          <ReferenceLine x={SUITE_SUMMARY.geomeanBranchAcc} stroke="#C34FA2" strokeDasharray="4 4"
                         label={{ value: `geomean ${SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%`, fill: '#C34FA2', fontSize: 11, position: 'top' }} />
          <Tooltip contentStyle={{ background: 'white', border: '1px solid #D8DDF2', borderRadius: 12 }} />
          <Bar dataKey="branchAccAllOn" fill="#5364C0" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

Commit:
```sh
git add web/components/charts/BranchAccLiftChart.tsx
git commit -m "feat(web): branch-accuracy chart"
```

- [ ] **Step 22c: CpiHistogram**

Create `web/components/charts/CpiHistogram.tsx`. Bin all-on CPI into 10 buckets and draw a bar chart, with vertical reference lines at the geomean (14.87) and arith mean (20.77).

```tsx
'use client';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, ReferenceLine } from 'recharts';
import { PROGRAM_RESULTS, SUITE_SUMMARY } from '@/lib/results';

const BIN_COUNT = 10;
const BIN_MAX = 110;
const BIN_WIDTH = BIN_MAX / BIN_COUNT;

function bin() {
  const buckets = Array.from({ length: BIN_COUNT }, (_, i) => ({
    range: `${(i * BIN_WIDTH).toFixed(0)}–${((i + 1) * BIN_WIDTH).toFixed(0)}`,
    count: 0,
  }));
  for (const r of PROGRAM_RESULTS) {
    const idx = Math.min(BIN_COUNT - 1, Math.floor(r.cpiAllOn / BIN_WIDTH));
    buckets[idx].count += 1;
  }
  return buckets;
}

export function CpiHistogram() {
  return (
    <div className="h-[360px] w-full">
      <ResponsiveContainer>
        <BarChart data={bin()} margin={{ left: 20, right: 20, top: 8, bottom: 8 }}>
          <XAxis dataKey="range" stroke="#5F657A" tick={{ fontSize: 11 }} label={{ value: 'CPI bucket', position: 'insideBottom', offset: -4, fontSize: 12 }} />
          <YAxis allowDecimals={false} stroke="#5F657A" />
          <Tooltip contentStyle={{ background: 'white', border: '1px solid #D8DDF2', borderRadius: 12 }} />
          <Bar dataKey="count" fill="#5364C0" />
          <ReferenceLine x={`${Math.floor(SUITE_SUMMARY.geomeanCpi / BIN_WIDTH) * BIN_WIDTH}–${(Math.floor(SUITE_SUMMARY.geomeanCpi / BIN_WIDTH) + 1) * BIN_WIDTH}`}
                         stroke="#C34FA2" strokeDasharray="4 4"
                         label={{ value: `geomean ${SUITE_SUMMARY.geomeanCpi.toFixed(2)}`, fill: '#C34FA2', fontSize: 11, position: 'top' }} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

Commit:
```sh
git add web/components/charts/CpiHistogram.tsx
git commit -m "feat(web): CPI histogram"
```

---

### Task 23: Deep-dive page assembly

**Files:**
- Create: `web/app/deep-dive/page.tsx`

- [ ] **Step 23.1: Implement page**

Create `web/app/deep-dive/page.tsx`:
```tsx
import { HeadlineNumbers } from '@/components/landing/HeadlineNumbers';
import { AblationChart } from '@/components/charts/AblationChart';
import { PerProgramSpeedupChart } from '@/components/charts/PerProgramSpeedupChart';
import { BranchAccLiftChart } from '@/components/charts/BranchAccLiftChart';
import { CpiHistogram } from '@/components/charts/CpiHistogram';
import { PipelineOverviewDiagram } from '@/components/diagrams/PipelineOverviewDiagram';
import { BranchPredictorDiagram } from '@/components/diagrams/BranchPredictorDiagram';
import { DCacheDiagram } from '@/components/diagrams/DCacheDiagram';
import { STLFDiagram } from '@/components/diagrams/STLFDiagram';
import { ETBDiagram } from '@/components/diagrams/ETBDiagram';
import { TIMING, SUITE_SUMMARY } from '@/lib/results';

const TOC = [
  { id: 'numbers',         label: 'Headline numbers' },
  { id: 'ablation',        label: 'Per-feature ablation' },
  { id: 'architecture',    label: 'Architecture overview' },
  { id: 'superscalar',     label: '2-way Superscalar' },
  { id: 'etb',             label: 'Early Tag Broadcast' },
  { id: 'gshare',          label: 'gshare' },
  { id: 'ras',             label: 'Return Address Stack' },
  { id: 'stlf',            label: 'Store-to-Load Forwarding' },
  { id: 'prefetch',        label: 'Next-line Prefetch' },
  { id: 'set-associative', label: '2-way Set-Assoc D-Cache' },
  { id: 'speedup',         label: 'Per-program speedup' },
  { id: 'branch-acc',      label: 'Branch accuracy' },
  { id: 'cpi',             label: 'CPI distribution' },
  { id: 'timing',          label: 'Synthesis & timing' },
  { id: 'verification',    label: 'Verification' },
  { id: 'limitations',     label: 'Limitations & future work' },
  { id: 'refs',            label: 'References & team' },
];

export default function DeepDivePage() {
  return (
    <div className="mx-auto max-w-7xl px-6 py-12 grid grid-cols-1 lg:grid-cols-[200px_1fr] gap-12">
      <aside className="hidden lg:block sticky top-24 self-start">
        <p className="text-xs uppercase tracking-widest text-ink-subtle mb-4">Contents</p>
        <ol className="space-y-2 text-sm">
          {TOC.map((t) => (
            <li key={t.id}>
              <a href={`#${t.id}`} className="text-ink-muted hover:text-plum-500">
                {t.label}
              </a>
            </li>
          ))}
        </ol>
      </aside>
      <article className="space-y-24">
        <section id="numbers">
          <h1 className="text-4xl font-semibold text-plum-500">Deep dive</h1>
          <p className="mt-4 text-ink-muted max-w-2xl">
            Every number on this page comes from the same RTL source you can see on GitHub.
          </p>
          <div className="mt-8">
            <HeadlineNumbers />
          </div>
        </section>

        <section id="ablation">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Per-feature ablation</h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            Marginal value of each ablate-able feature at the all-on operating point. Disable
            one feature, hold the other four on, and measure the geomean cycle-count regression.
            Prefetch dominates: disabling it alone accounts for nearly the entire all-five-off gap.
          </p>
          <AblationChart />
        </section>

        <section id="architecture">
          <h2 className="text-3xl font-semibold text-plum-500 mb-6">Architecture overview</h2>
          <PipelineOverviewDiagram />
          <p className="mt-6 text-ink-muted max-w-3xl">
            P6-style: in-order fetch and decode, register renaming through a RAT embedded in
            the ROB, out-of-order issue and execute, broadcast on a 2-slot Common Data Bus,
            and in-order commit. The ROB doubles as the physical register file.
          </p>
        </section>

        {/* The implementing subagent should add ~12 paragraphs total
            for the 7 advanced features, drawing from report §V.A through §V.E.
            Pattern per feature:
              <section id={feature.deepDiveAnchor.slice(1)}>
                <h2 className="text-3xl ...">{feature.name}</h2>
                <p>problem statement</p>
                {DiagramComponent && <DiagramComponent />}
                <p>design summary</p>
                <p>measured number + worst-case</p>
              </section>
            Use the prose from report §V verbatim where possible (it's already the right length and tone). */}

        <section id="speedup">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Per-program speedup</h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            All 33 programs sorted by Δ% from OoO base to all-on. Two regress: <code>insertion</code>{' '}
            (+2.13%) and <code>evens</code> (+0.34%).
          </p>
          <PerProgramSpeedupChart />
        </section>

        <section id="branch-acc">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Branch prediction accuracy</h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            All-on accuracy across the {SUITE_SUMMARY.programCount - 3} programs that execute
            at least one conditional branch. Geomean {SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%,
            an arith. mean lift of {SUITE_SUMMARY.branchAccLiftOverBimodalPp.toFixed(2)} pp over
            the bimodal baseline.
          </p>
          <BranchAccLiftChart />
        </section>

        <section id="cpi">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">CPI distribution</h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            All-on CPI bucketed into 10 ranges. Most of the suite sits in the 3–30 band; the
            tail above 100 is the toy halt-only program.
          </p>
          <CpiHistogram />
        </section>

        <section id="timing">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Synthesis &amp; timing</h2>
          <p className="text-ink-muted max-w-3xl">
            All seven module-level testbenches meet timing at {TIMING.clockTargetPs} ps. The
            full pipeline netlist misses by {TIMING.worstSlackPs} ps on the path{' '}
            <code className="text-iris-600">{TIMING.criticalPath}</code>: a single 32-bit
            ripple-carry adder with high fanout sits in the middle of a long combinational
            chain. Closing it would mean either registering the LSQ broadcast (one extra cycle
            on every completing load) or splitting the ALU adder into two pipeline stages (one
            extra cycle on every ALU op). Both pay performance on the common case to fix the
            static-timing residual, so this pass stops short.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            The netlist is functionally bit-equivalent to the RTL on every program: the
            <code> .syn.wb </code> writeback trace is byte-identical to <code>.wb</code> on all
            33 programs (pre-multiplier-operand-register baseline; the subsequent flop insertion
            should preserve this property and is pending re-verification).
          </p>
        </section>

        <section id="verification">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Verification methodology</h2>
          <p className="text-ink-muted max-w-3xl">
            Three layers, each catching a different class of bug. Module-level SystemVerilog
            testbenches catch local regressions (mult, rob, rs, lsq, dcache, icache,
            branch_predictor — all green in sim and synth). Full-pipeline regression catches
            integration bugs across all 33 RV32IM programs end-to-end. The same regression run
            against the synthesized netlist catches RTL-vs-netlist divergence.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            Two byte-equivalence checks anchor correctness: (1) every <code>.syn.wb</code> is
            byte-identical to its <code>.wb</code> on all 33 programs, and (2) every <code>.wb</code>
            on the post-merge build is byte-identical to the trace produced by the same commit
            built with <code>+define+SERIALIZE_BRANCHES</code>. Out-of-order issue and speculation
            do the same architectural work as a serialized reference, just with cycles arranged
            differently.
          </p>
        </section>

        <section id="limitations">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">Limitations &amp; future work</h2>
          <p className="text-ink-muted max-w-3xl">
            Single-port LSQ caps memory bandwidth on the wider pipeline — two adjacent loads
            still serialize at the cache. A second multiplier would help multiply-heavy code
            but is hard to justify at the marginal cycles ETB ablation suggests are available.
            Past 2-way, the embedded-RAT-in-ROB rename approach starts to fall off; a unified
            R10K-style physical register pool would make more sense at 4-wide. The −797.58 ps
            timing miss is the one thing we'd close with more time.
          </p>
        </section>

        <section id="refs">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">References &amp; team</h2>
          <p className="text-ink-muted">
            Chenhao Yang, Xuepeng Han, Gavin Zou, Pingchuan Dong, Hins Lyu, Xueer Qian.
          </p>
          <p className="mt-4 text-ink-muted">
            <a href="/4340-final-report.pdf" className="text-iris-600 hover:text-plum-500">Read the full report (PDF)</a>
          </p>
        </section>
      </article>
    </div>
  );
}
```

For the `{/* The implementing subagent should add ~12 paragraphs ... */}` comment block: the implementing subagent should expand this into seven `<section>` blocks (one per feature), embedding the appropriate diagram component (`<ETBDiagram />`, `<BranchPredictorDiagram />`, `<DCacheDiagram />`, `<STLFDiagram />` — superscalar, gshare/RAS, prefetch, set-assoc don't all have unique diagrams; share where appropriate). Use prose from report §V verbatim where feasible.

- [ ] **Step 23.2: Visual QA via playwright-cli**

Invoke the `playwright-cli` skill: navigate to http://localhost:3000/deep-dive, take a
screenshot of the full page (scroll-to-bottom screenshot if the skill supports it), click
each TOC entry and confirm the anchor scroll happens, scroll past every chart and confirm
none rendered as an empty SVG. Console must be clean.

- [ ] **Step 23.3: Commit**

```sh
git add web/app/deep-dive/page.tsx
git commit -m "feat(web): deep-dive page assembly"
```

---

## Phase 7 — Simulator (Tasks 24–30)

### Task 24: Trace types + loader

**Files:**
- Create: `web/lib/trace.ts`

- [ ] **Step 24.1: Implement**

Create `web/lib/trace.ts`:
```ts
export interface InstrRef {
  rob_tag?: number;
  pc?: number;
  instr_text?: string;
}

export interface RobEntry { tag: number; pc?: number; instr_text?: string; busy?: boolean; ready?: boolean; value?: number; }
export interface RsEntry { tag: number; op?: string; src1_tag?: number; src1_ready?: boolean; src2_tag?: number; src2_ready?: boolean; }
export interface LsqEntry { tag: number; op?: string; addr?: number; data?: number; state?: string; }
export interface CdbSlot { tag: number; value?: number; }
export interface ExecState {
  alu0?: InstrRef;
  alu1?: InstrRef;
  mult_stage_n?: number;
  branch?: InstrRef;
  lsq_head?: InstrRef;
}

export interface CycleSnapshot {
  cycle: number;
  pc: number;
  fetch: InstrRef[];
  decode: InstrRef[];
  rob: RobEntry[];
  rs: RsEntry[];
  lsq: LsqEntry[];
  exec: ExecState;
  cdb: CdbSlot[];
  commit: InstrRef[];
  events: string[];
}

export interface Trace {
  program: string;
  snapshots: CycleSnapshot[];
}

export const TRACE_PROGRAMS = [
  { id: 'parallel',    label: 'parallel.s — ILP demo' },
  { id: 'mult_no_lsq', label: 'mult_no_lsq.s — multiplier + ETB' },
  { id: 'fib_rec',     label: 'fib_rec.s — recursion + RAS' },
] as const;

export type TraceProgramId = typeof TRACE_PROGRAMS[number]['id'];

export async function loadTrace(id: TraceProgramId): Promise<Trace> {
  const res = await fetch(`/traces/${id}.json`);
  if (!res.ok) throw new Error(`failed to load trace ${id}: ${res.status}`);
  return res.json();
}

export function findFirstEventCycle(snapshots: CycleSnapshot[]): number {
  const idx = snapshots.findIndex((s) => s.events.length > 0);
  return idx >= 0 ? snapshots[idx].cycle : snapshots[0]?.cycle ?? 0;
}
```

- [ ] **Step 24.2: Commit**

```sh
git add web/lib/trace.ts
git commit -m "feat(web): trace types and loader"
```

---

### Task 25: Pipeline lanes (the visualizer top half)

**Files:**
- Create: `web/components/simulator/PipelineLanes.tsx`

- [ ] **Step 25.1: Implement**

Create `web/components/simulator/PipelineLanes.tsx`. Layout: six labeled vertical lanes left-to-right (Fetch / Decode / RS-LSQ / Exec / CDB / Commit). For each in-flight instruction in the current snapshot, render a small pill in its lane. Pills are colored by ROB tag (use a deterministic palette function `colorForTag(tag)` cycling through plum/iris/sky/orchid). Animate pill positions with Framer Motion's `layout` prop so they smoothly transition between snapshots.

```tsx
'use client';
import { motion, AnimatePresence } from 'framer-motion';
import type { CycleSnapshot } from '@/lib/trace';

const LANES = ['Fetch', 'Decode', 'RS / LSQ', 'Exec', 'CDB', 'Commit'] as const;

const TAG_COLORS = ['#77295D', '#5364C0', '#77B7F0', '#C34FA2', '#3B142F', '#293260', '#33506A', '#612851'];
function colorForTag(tag: number) { return TAG_COLORS[tag % TAG_COLORS.length]; }

interface Pill { tag: number; lane: number; label: string; }

function pillsFromSnapshot(s: CycleSnapshot): Pill[] {
  const pills: Pill[] = [];
  s.fetch.forEach((i) => i.rob_tag !== undefined && pills.push({ tag: i.rob_tag, lane: 0, label: i.instr_text ?? `pc=${(i.pc ?? 0).toString(16)}` }));
  s.decode.forEach((i) => i.rob_tag !== undefined && pills.push({ tag: i.rob_tag, lane: 1, label: i.instr_text ?? '' }));
  s.rs.forEach((e) => pills.push({ tag: e.tag, lane: 2, label: e.op ?? `t${e.tag}` }));
  s.lsq.forEach((e) => pills.push({ tag: e.tag, lane: 2, label: `LSQ ${e.op ?? ''}` }));
  if (s.exec.alu0?.rob_tag !== undefined) pills.push({ tag: s.exec.alu0.rob_tag, lane: 3, label: 'ALU0' });
  if (s.exec.alu1?.rob_tag !== undefined) pills.push({ tag: s.exec.alu1.rob_tag, lane: 3, label: 'ALU1' });
  if (s.exec.mult_stage_n !== undefined) pills.push({ tag: -1, lane: 3, label: `MULT s${s.exec.mult_stage_n}` });
  s.cdb.forEach((c) => pills.push({ tag: c.tag, lane: 4, label: `CDB t${c.tag}` }));
  s.commit.forEach((i) => i.rob_tag !== undefined && pills.push({ tag: i.rob_tag, lane: 5, label: i.instr_text ?? `t${i.rob_tag}` }));
  return pills;
}

export function PipelineLanes({ snapshot }: { snapshot: CycleSnapshot | null }) {
  const pills = snapshot ? pillsFromSnapshot(snapshot) : [];
  const grouped: Pill[][] = LANES.map((_, lane) => pills.filter((p) => p.lane === lane));
  return (
    <div className="grid grid-cols-6 gap-2 h-[480px]">
      {LANES.map((laneLabel, idx) => (
        <div key={laneLabel} className="flex flex-col bg-white rounded-soft border border-snow-600 p-3">
          <p className="text-xs uppercase tracking-widest text-ink-subtle mb-3">{laneLabel}</p>
          <div className="flex-1 overflow-y-auto space-y-2">
            <AnimatePresence>
              {grouped[idx].map((p, i) => (
                <motion.div
                  key={`${p.tag}-${i}`}
                  layout
                  initial={{ opacity: 0, y: -6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 6 }}
                  className="rounded-md px-2 py-1 text-xs text-white font-mono"
                  style={{ background: p.tag >= 0 ? colorForTag(p.tag) : '#5F657A' }}
                >
                  {p.label}
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 25.2: Commit**

```sh
git add web/components/simulator/PipelineLanes.tsx
git commit -m "feat(web): pipeline lanes visualization"
```

---

### Task 26: Simulator page assembly + scrubber + controls + tables + caption

**Files:**
- Create: `web/app/simulator/page.tsx`, `web/components/simulator/RobTable.tsx`, `RsTable.tsx`, `LsqTable.tsx`, `Scrubber.tsx`, `EventCaption.tsx`, `MobileFallback.tsx`

This is the largest single task. The implementing subagent should build all these pieces together so the page works end-to-end on first run.

- [ ] **Step 26.1: Three live tables**

Create `web/components/simulator/RobTable.tsx`:
```tsx
'use client';
import type { RobEntry } from '@/lib/trace';
export function RobTable({ rob, committingTags }: { rob: RobEntry[]; committingTags: number[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">ROB</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle">
          <tr>
            <th className="text-left">tag</th><th className="text-left">pc</th><th>busy</th><th>ready</th>
          </tr>
        </thead>
        <tbody>
          {rob.map((e) => (
            <tr key={e.tag} className={committingTags.includes(e.tag) ? 'bg-plum-50' : ''}>
              <td>{e.tag}</td>
              <td>{e.pc !== undefined ? `0x${e.pc.toString(16)}` : '—'}</td>
              <td className="text-center">{e.busy ? '●' : '·'}</td>
              <td className="text-center">{e.ready ? '✓' : '·'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

Create `web/components/simulator/RsTable.tsx`:
```tsx
'use client';
import type { RsEntry } from '@/lib/trace';
export function RsTable({ rs }: { rs: RsEntry[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">RS</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle"><tr><th className="text-left">tag</th><th className="text-left">op</th><th>s1</th><th>s2</th></tr></thead>
        <tbody>
          {rs.map((e) => (
            <tr key={e.tag}>
              <td>{e.tag}</td>
              <td>{e.op ?? '—'}</td>
              <td className="text-center">{e.src1_ready ? '✓' : `t${e.src1_tag ?? '?'}`}</td>
              <td className="text-center">{e.src2_ready ? '✓' : `t${e.src2_tag ?? '?'}`}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

Create `web/components/simulator/LsqTable.tsx`:
```tsx
'use client';
import type { LsqEntry } from '@/lib/trace';
export function LsqTable({ lsq }: { lsq: LsqEntry[] }) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-3">
      <p className="text-xs uppercase tracking-widest text-ink-subtle mb-2">LSQ</p>
      <table className="w-full text-xs font-mono">
        <thead className="text-ink-subtle"><tr><th className="text-left">tag</th><th className="text-left">op</th><th className="text-left">addr</th><th>state</th></tr></thead>
        <tbody>
          {lsq.map((e) => (
            <tr key={e.tag}>
              <td>{e.tag}</td>
              <td>{e.op ?? '—'}</td>
              <td>{e.addr !== undefined ? `0x${e.addr.toString(16)}` : '—'}</td>
              <td className="text-center">{e.state ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 26.2: Scrubber + controls**

Create `web/components/simulator/Scrubber.tsx`:
```tsx
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
  cycle, minCycle, maxCycle, isPlaying, speed,
  onCycleChange, onPlayPause, onStep, onJumpNextEvent, onSpeedChange,
}: Props) {
  return (
    <div className="bg-white rounded-soft border border-snow-600 p-4 flex flex-wrap items-center gap-4">
      <button onClick={() => onStep(-1)} className="px-2 py-1 text-iris-600 hover:text-plum-500" aria-label="step back">⏮</button>
      <button onClick={onPlayPause} className="rounded-full bg-plum-500 text-white w-10 h-10 flex items-center justify-center hover:bg-plum-600">
        {isPlaying ? '⏸' : '▶'}
      </button>
      <button onClick={() => onStep(1)} className="px-2 py-1 text-iris-600 hover:text-plum-500" aria-label="step forward">⏭</button>
      <button onClick={onJumpNextEvent} className="px-3 py-1 rounded-full bg-orchid-50 text-plum-500 text-xs hover:bg-orchid-100">
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
```

- [ ] **Step 26.3: Event caption**

Create `web/components/simulator/EventCaption.tsx`:
```tsx
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
```

- [ ] **Step 26.4: Mobile fallback**

Create `web/components/simulator/MobileFallback.tsx`:
```tsx
export function MobileFallback() {
  return (
    <div className="lg:hidden mx-auto max-w-md px-6 py-24 text-center">
      <h1 className="text-2xl font-semibold text-plum-500">Open this on a wider screen</h1>
      <p className="mt-4 text-ink-muted">
        The pipeline visualizer needs at least a laptop-sized viewport to render legibly.
        Try opening this page on a desktop — or read the <a href="/deep-dive" className="text-iris-600">deep dive</a> instead.
      </p>
    </div>
  );
}
```

- [ ] **Step 26.5: Page assembly**

Create `web/app/simulator/page.tsx`:
```tsx
'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { loadTrace, TRACE_PROGRAMS, findFirstEventCycle, type Trace, type TraceProgramId, type CycleSnapshot } from '@/lib/trace';
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
  const tickRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadTrace(programId).then((t) => {
      if (cancelled) return;
      setTrace(t);
      setCycle(findFirstEventCycle(t.snapshots));
      setIsPlaying(false);
    });
    return () => { cancelled = true; };
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
    return () => { if (tickRef.current) clearInterval(tickRef.current); };
  }, [isPlaying, speed, trace]);

  const snapshot: CycleSnapshot | null = useMemo(() => {
    if (!trace) return null;
    let lo = 0, hi = trace.snapshots.length - 1, ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (trace.snapshots[mid].cycle <= cycle) { ans = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    return trace.snapshots[ans];
  }, [trace, cycle]);

  const jumpNextEvent = () => {
    if (!trace) return;
    const idx = trace.snapshots.findIndex((s) => s.cycle > cycle && s.events.length > 0);
    if (idx >= 0) setCycle(trace.snapshots[idx].cycle);
  };

  if (!trace) return <p className="mx-auto max-w-7xl px-6 py-16 text-ink-muted">Loading trace…</p>;

  const minCycle = trace.snapshots[0].cycle;
  const maxCycle = trace.snapshots[trace.snapshots.length - 1].cycle;
  const committingTags = (snapshot?.commit ?? []).map((c) => c.rob_tag).filter((t): t is number => t !== undefined);

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
            {TRACE_PROGRAMS.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
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
```

- [ ] **Step 26.6: Visual QA via playwright-cli**

Invoke the `playwright-cli` skill: navigate to http://localhost:3000/simulator, take a
screenshot, click ▶ and confirm the cycle counter increments, click ⏸ and confirm it
stops, drag the scrubber to a specific cycle and confirm the snapshot updates, switch the
program dropdown to `mult_no_lsq` and confirm a new trace loads, click "Jump to next event"
and confirm the cycle jumps. Console must be clean. If a trace has empty `rob`/`rs`/`lsq`
(fallback path), the lanes will still show the commit stream — that's expected.

- [ ] **Step 26.7: Commit**

```sh
git add web/components/simulator/ web/app/simulator/page.tsx
git commit -m "feat(web): pipeline visualizer (simulator page)"
```

---

## Phase 8 — Final assets, QA, deploy

### Task 27: Render the report PDF

**Files:**
- Create: `web/public/4340-final-report.pdf`

- [ ] **Step 27.1: Render the existing IEEE LaTeX source**

The IEEE source is already zipped at `doc/final-report/4340-final-report-ieee-revised-source.zip`, and the working main.tex is at `doc/final-report/main.tex`. Try the latex flow first:

```sh
cd doc/final-report
pdflatex -interaction=nonstopmode main.tex && pdflatex -interaction=nonstopmode main.tex
```
If pdflatex isn't installed, fall back to pandoc on the markdown:
```sh
pandoc doc/final-report/4340-final-report.md -o doc/final-report/main.pdf --pdf-engine=xelatex
```
If neither tool is available locally, ask the user to render on the lab PC (where they'll have a LaTeX install) and paste back, similar to the trace capture flow.

- [ ] **Step 27.2: Copy to public/**

```sh
cp doc/final-report/main.pdf web/public/4340-final-report.pdf
```

- [ ] **Step 27.3: Commit**

```sh
git add web/public/4340-final-report.pdf
git commit -m "chore(web): bundle final report PDF"
```

---

### Task 28: README for the website

**Files:**
- Create: `web/README.md`

- [ ] **Step 28.1: Implement**

Create `web/README.md`:
```markdown
# Demo Website — EECS 4340 OoO RV32IM

Vercel-hosted Next.js site demoing the project. Three routes: `/` landing, `/simulator`
pipeline visualizer, `/deep-dive` long-form report.

## Develop

```sh
cd web
npm install
npm run dev
# http://localhost:3000
```

## Deploy

```sh
npm install -g vercel
vercel login
vercel link        # one-time
vercel deploy --prod
```

## Update RTL traces

The pipeline visualizer plays back JSON traces captured from the RTL simulator. To
add or refresh a trace, run on the lab PC:

```sh
module load vcs verdi synopsys-synth
python3 web/tools/capture_trace.py <program-name>
```

The script writes to `web/public/traces/<program-name>.json`. Check the file in.

## Structure

See `.trellis/tasks/05-03-demo-website/prd.md` for the design spec.
```

- [ ] **Step 28.2: Commit**

```sh
git add web/README.md
git commit -m "docs(web): README"
```

---

### Task 29: Lighthouse audit + fixes

**Files:**
- Modify whatever is needed to hit the score targets

- [ ] **Step 29.1: Build static export**

```sh
cd web && npm run build
# Inspect the output for warnings; fix any.
```
Expected: `out/` directory created, no errors.

- [ ] **Step 29.2: Serve and audit**

```sh
cd web && npx serve out
# In another terminal, run Lighthouse against http://localhost:3000
npx lighthouse http://localhost:3000 --view --preset=desktop
```
Targets: Performance ≥ 90, Accessibility ≥ 95, SEO ≥ 90.

If any target misses, fix in priority order:
- A11y misses: missing `alt` text on images, missing `aria-label` on icon-only buttons, color contrast failures (use the palette guide's contrast table at §4).
- Perf misses: oversized images, blocking JS. (Charts are client-side — that's expected. Watch the FCP.)
- SEO misses: missing meta description, missing `<title>` per route.
- Commit fixes incrementally — one targeted commit per fix class.

- [ ] **Step 29.3: Repeat for `/simulator` and `/deep-dive`**

```sh
npx lighthouse http://localhost:3000/simulator --preset=desktop
npx lighthouse http://localhost:3000/deep-dive --preset=desktop
```

- [ ] **Step 29.4: Browser smoke test via playwright-cli skill**

Invoke the `playwright-cli` skill to run an interactive smoke test against the local dev
server (or the served `out/` build). The skill drives a headless browser; the agent should
verify, on http://localhost:3000:

1. `/` loads with no console errors. The hero CTA "Open the simulator" navigates to `/simulator`.
2. On `/`, clicking any architecture-diagram module box opens the side panel; clicking the
   backdrop closes it. Toggling the "Show all advanced features" pill highlights modules.
3. `/simulator` loads with the program selector defaulting to `parallel`. Clicking ▶ starts
   playback; the cycle counter advances. Clicking ⏸ stops it. Switching the dropdown to
   `mult_no_lsq` reloads with cycle 0 (or first event). The scrubber slider moves freely.
4. `/deep-dive` loads. Sticky TOC links jump to anchors. All charts render (no empty SVG).

Capture screenshots of each route at 1280×800 for the record. Any failure → fix and re-run.

- [ ] **Step 29.5: Commit any fixes**

```sh
git add web/
git commit -m "fix(web): lighthouse audit cleanups"
```

---

### Task 30: vercel.json + deploy

**Files:**
- Create: `web/vercel.json`

- [ ] **Step 30.1: Minimal vercel.json**

Create `web/vercel.json`:
```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "framework": "nextjs"
}
```

- [ ] **Step 30.2: Deploy preview**

Run from `web/`:
```sh
npm install -g vercel
vercel login
vercel link
vercel deploy
```
Expected: a preview URL printed. Visit it; confirm all three routes work.

- [ ] **Step 30.3: Deploy production**

```sh
vercel deploy --prod
```
Expected: a production URL printed. Verify all three routes one more time. Verify the report PDF link works. Verify the GitHub link in the nav goes to the right repo.

- [ ] **Step 30.4: Commit vercel.json + record the URL in README**

```sh
git add web/vercel.json web/README.md
git commit -m "feat(web): production deploy config"
```

---

## Self-review (run after writing the plan, before handing off)

**Spec coverage check:**
- ✅ §3 site map: `/` (Tasks 9, 10–14), `/simulator` (Tasks 24–26), `/deep-dive` (Tasks 17–23)
- ✅ §4 tech stack: Task 1 (Next.js + Tailwind + Recharts + Framer)
- ✅ §5 folder structure: built incrementally across all tasks; matches §5 exactly
- ✅ §6 landing page: Tasks 9 (hero + numbers), 10–12 (architecture diagram + panel + toggle), 13 (feature pills), 14 (assembly), 15 (per-program chart)
- ✅ §7 simulator: Tasks 24 (types/loader), 25 (lanes), 26 (everything else)
- ✅ §8 deep-dive: Tasks 17–21 (5 native SVG diagrams), 22a/b/c (charts), 23 (assembly)
- ✅ §9 color/style: Task 1.3 sets up the palette tokens; all components reference those tokens
- ✅ §10 lab-PC capture: Tasks 3–5
- ✅ §11 deployment: Task 30
- ✅ §12 acceptance criteria: covered by the per-task QA + Lighthouse (Task 29)
- ✅ §13 implementation discipline: documented in plan header; each task is dispatchable to a subagent

**Placeholder scan:** No "TBD" or "implement later" remaining. Two areas use phrases like "the implementing subagent should": (1) Task 10 step 10.1 leaves visual layout judgment to the subagent (with a specific grid suggestion), (2) Task 23 step 23.1 leaves the seven feature subsections as a comment with explicit guidance ("expand into seven `<section>` blocks"). These are intentional — the engineer needs visual/prose judgment there, not more rigid scripting. Code in every code step is complete.

**Type consistency:** `CycleSnapshot` is defined identically in `lib/trace.ts` (Task 24) and the Python parser's docstring (Task 4). `MODULES`, `FEATURES`, `PROGRAM_RESULTS`, `ABLATION`, `SUITE_SUMMARY`, `TIMING` are referenced by name in later tasks and defined exactly once in `lib/`. All component prop interfaces are written out in their creating task. No drift.

**Parallelism notes for the dispatcher:**
- Tasks 6 / 7 / 8 are independent — dispatch in one Agent batch.
- Tasks 17 / 18 / 19 / 20 / 21 (the 5 SVG diagrams) are independent — dispatch in one Agent batch after Task 6 lands.
- Tasks 9 / 13 / 15 / 22a / 22b / 22c are leaf components with no cross-deps — dispatch in one Agent batch after data layer (6/7/8) lands.
- Tasks 10 / 11 / 12 must be sequential within the architecture cluster (they all touch the same conceptual subsystem; reviewing diff-by-diff is easier).
- Tasks 14 (landing assembly), 23 (deep-dive assembly), 26 (simulator assembly) are integration tasks — sequential after their dependencies, dispatched as single subagent each.
- Phase 2 (Tasks 3–5) runs in parallel with everything in Phases 3–6.
