# Demo Website — EECS 4340 OoO RV32IM

Vercel-hosted Next.js site demoing the project. Three routes: `/` (landing), `/simulator`
(pipeline visualizer), `/deep-dive` (long-form report).

Spec: [.trellis/tasks/05-03-demo-website/prd.md](../.trellis/tasks/05-03-demo-website/prd.md)
Plan: [.trellis/tasks/05-03-demo-website/plan.md](../.trellis/tasks/05-03-demo-website/plan.md)

## Develop

```sh
cd web
npm install
npm run dev
# http://localhost:3000
```

Tech stack: Next.js 16 (App Router) + React 19 + TypeScript + Tailwind v4 + Recharts +
Framer Motion. Static export. No backend.

## Build

```sh
cd web
npm run build
# Static output in web/out/
```

## Deploy (Vercel)

```sh
npm install -g vercel
vercel login
vercel link        # one-time, links this folder to a Vercel project
vercel deploy --prod
```

## Update RTL traces

The pipeline visualizer plays back JSON traces captured from the RTL simulator. To
add or refresh a trace, run on the lab PC (which has Synopsys VCS):

```sh
module load vcs verdi synopsys-synth
python3 web/tools/capture_trace.py <program-name>
```

The script writes to `web/public/traces/<program-name>.json`. Check the file in.

The current build expects three traces:
- `parallel.json` — short ILP demo
- `mult_no_lsq.json` — multiplier + ETB
- `fib_rec.json` — recursion + RAS + branch mispredict

Until traces are captured, the simulator page renders with "Loading trace…" forever
(by design — the page works as soon as the JSON arrives).

## Notes

- Tailwind v4 uses CSS-first configuration. Palette tokens live in `app/globals.css`
  inside an `@theme` block, not in a `tailwind.config.ts`.
- The landing page architecture diagram and the five report figures are native React
  SVG components, not imported PNGs. They're regenerated from RTL ground truth, not
  ported from the report's TikZ source.
- The Recharts `width(-1) and height(-1)` warning during `npm run build` is benign:
  Recharts' ResponsiveContainer can't measure dimensions during static prerender. The
  charts hydrate correctly client-side.
