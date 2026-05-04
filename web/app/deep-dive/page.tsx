// /deep-dive — long-form companion to the IEEE-format final report.
//
// Server Component (no `'use client'`). The chart components imported below
// each carry their own `'use client'` directive, so they hydrate
// independently while the surrounding prose stays server-rendered.
//
// Anchors must match `lib/features.ts` `deepDiveAnchor` values so the
// landing-page feature pills link directly into the right subsection.
//
// Numerical claims are pulled from `lib/results.ts` so this page can never
// drift from the chart data on the same site.

import type { Metadata } from 'next';

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
import { ABLATION, SUITE_SUMMARY, TIMING } from '@/lib/results';

export const metadata: Metadata = {
  title: 'Deep Dive — OoO RV32IM Processor',
  description:
    'Long-form walk through the seven advanced features, performance results, '
    + 'synthesis timing, and verification methodology of the EECS 4340 OoO RV32IM '
    + 'processor.',
};

const TOC = [
  { id: 'numbers', label: 'Headline numbers' },
  { id: 'ablation', label: 'Per-feature ablation' },
  { id: 'architecture', label: 'Architecture overview' },
  { id: 'superscalar', label: '2-way Superscalar' },
  { id: 'etb', label: 'Early Tag Broadcast' },
  { id: 'gshare', label: 'gshare' },
  { id: 'ras', label: 'Return Address Stack' },
  { id: 'stlf', label: 'Store-to-Load Forwarding' },
  { id: 'prefetch', label: 'Next-line Prefetch' },
  { id: 'set-associative', label: '2-way Set-Assoc D-Cache' },
  { id: 'speedup', label: 'Per-program speedup' },
  { id: 'branch-acc', label: 'Branch accuracy' },
  { id: 'cpi', label: 'CPI distribution' },
  { id: 'timing', label: 'Synthesis & timing' },
  { id: 'verification', label: 'Verification' },
  { id: 'limitations', label: 'Limitations & future work' },
  { id: 'refs', label: 'References & team' },
];

const TEAM = [
  'Chenhao Yang',
  'Xuepeng Han',
  'Gavin Zou',
  'Pingchuan Dong',
  'Hins Lyu',
  'Xueer Qian',
];

const REFERENCES = [
  'Hennessy & Patterson, Computer Architecture: A Quantitative Approach, 6th ed., Morgan Kaufmann, 2017.',
  'McFarling, "Combining Branch Predictors", DEC WRL Technical Note TN-36, 1993.',
  'EECS 4340 starter codebase (VeriSimpleV in-order pipeline), Columbia University, Spring 2026.',
  'RISC-V Instruction Set Manual, Volume I: Unprivileged ISA, Document Version 20191213.',
  'Yeh & Patt, "Two-level adaptive training branch prediction", MICRO-24, 1991.',
];

// Look up a feature ablation row by name. Returns null for the structural
// (non-ablate-able) features so prose can branch on it.
function findAblation(name: string) {
  const row = ABLATION.find((r) => r.feature === name);
  if (!row || Number.isNaN(row.geomeanDeltaPctWhenDisabled)) return null;
  return row;
}

const ETB_ROW = findAblation('ETB');
const GSHARE_ROW = findAblation('gshare');
const RAS_ROW = findAblation('RAS');
const STLF_ROW = findAblation('STLF');
const PREFETCH_ROW = findAblation('Next-line prefetch');
const ALL_FIVE_ROW = findAblation('all 5 disabled');

export default function DeepDivePage() {
  return (
    <div className="mx-auto max-w-7xl px-6 py-12 grid grid-cols-1 lg:grid-cols-[200px_1fr] gap-12">
      <aside className="hidden lg:block sticky top-24 self-start">
        <p className="text-xs uppercase tracking-widest text-ink-subtle mb-4">
          Contents
        </p>
        <ol className="space-y-2 text-sm">
          {TOC.map((t) => (
            <li key={t.id}>
              <a
                href={`#${t.id}`}
                className="text-ink-muted hover:text-plum-500 transition-colors"
              >
                {t.label}
              </a>
            </li>
          ))}
        </ol>
      </aside>

      <article className="space-y-24 min-w-0">
        <header>
          <p className="text-sm uppercase tracking-widest text-iris-600 mb-3">
            EECS 4340 · Spring 2026 · Columbia University
          </p>
          <h1 className="text-4xl md:text-5xl font-semibold text-plum-500 leading-tight tracking-tight">
            Deep Dive
          </h1>
          <p className="mt-4 max-w-3xl text-lg text-ink-muted">
            A long-form walkthrough of the design: the seven advanced features
            layered on the base out-of-order machine, what each one buys, the
            performance numbers across 33 programs, and where the synthesis
            timing actually lands.
          </p>
        </header>

        {/* §1 Headline numbers */}
        <section id="numbers" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Headline numbers
          </h2>
          <p className="text-ink-muted max-w-3xl">
            Every number on this page is sourced from the same const arrays in{' '}
            <code className="text-iris-600">lib/results.ts</code> that drive the
            charts. The four cards below are the geomean over the full
            33-program suite at the &ldquo;all-on&rdquo; operating point.
          </p>
          <HeadlineNumbers />
        </section>

        {/* §2 Per-feature ablation */}
        <section id="ablation" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Per-feature ablation
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            Marginal value at the operating point: disable one feature at a
            time, leave the other four ablate-able features on, measure the
            cycle-count regression. The two structural features (2-way
            superscalar, 2-way set-associative D-cache) cannot be rolled back
            with a <code className="text-iris-600">+define</code> and are
            discussed in their own subsections below.
          </p>
          <AblationChart />
          <p className="text-ink-muted max-w-3xl mt-6">
            Disabling all five ablate-able features together raises geomean
            cycle count by{' '}
            {ALL_FIVE_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%. Next-line
            prefetch alone accounts for{' '}
            {PREFETCH_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)} pp of that;
            the other four contribute about 0.7 pp combined. Read that not as
            &ldquo;the smaller features are broken&rdquo; but as &ldquo;the
            prefetcher already absorbs most of the cycles those features could
            have saved on their own.&rdquo;
          </p>
        </section>

        {/* §3 Architecture overview */}
        <section id="architecture" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Architecture overview
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            P6-style out-of-order RV32IM core. 2-way superscalar in fetch,
            decode, dispatch, ALU, CDB, and commit; the LSQ, multiplier, and
            both caches stay 1-wide. The RAT lives inside the ROB &mdash; ROB
            entries double as physical registers, so there is no separate
            rename file.
          </p>
          <PipelineOverviewDiagram />
          <p className="text-ink-muted max-w-3xl mt-6">
            The fetch unit pulls 8-byte aligned lines from the I-cache. Decode
            cracks each line into two parallel decoders. Dispatch allocates two
            ROB slots per cycle and either two RS slots or one RS + one LSQ
            slot per cycle, in lockstep so the structures never disagree about
            what is in flight. The CDB has 2 slots with priority MULT &gt; LD
            &gt; ALU per slot.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The LSQ is a FIFO and only the head can issue to the cache, which
            keeps memory ordering simple at the cost of some throughput on
            adjacent loads. Branch resolution happens inside the two ALUs
            alongside <code className="text-iris-600">alu_result</code>; the
            diagram draws a dedicated &ldquo;Branch resolver&rdquo; box for
            pedagogical clarity.
          </p>
        </section>

        {/* §V.A — 2-way superscalar (no dedicated diagram) */}
        <section id="superscalar" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            2-way Superscalar
          </h2>
          <p className="text-ink-muted max-w-3xl">
            A one-instruction-wide pipeline retires at most one instruction per
            cycle. Real programs often have two unrelated instructions sitting
            ready in the RS, both waiting for an issue slot that will only ever
            serve one of them. Going from one issue per cycle to two roughly
            doubles the IPC ceiling.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The widening runs from fetch through commit. Two parallel decoders
            on the 8-byte fetch line, two ROB allocations per cycle, two RS
            picks (or one RS + one LSQ if one of the pair is a memory op), two
            ALUs at the end of issue, two CDB slots, and two commit slots in
            program order. A few units stayed single: there is still one MULT
            unit (multiply is rare on the suite, the queue of consumers sits
            ahead of it) and a single-port LSQ (a second LSQ port and a second
            cache port would have been a much larger surgery than the rest of
            the widening combined).
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            This is one of the two structural features. It is wired into port
            widths, RS issue logic, ROB allocate-and-commit, and the CDB count;
            no single <code className="text-iris-600">+define</code> rolls it
            back. Its contribution shows up indirectly: several ILP-rich
            programs reach all-on CPI well below the structural ceiling of a
            strictly one-wide machine (
            <code className="text-iris-600">fib_rec</code> 2.44,{' '}
            <code className="text-iris-600">sort_search</code> 3.30,{' '}
            <code className="text-iris-600">insertionsort</code> 3.88), so the
            widening is doing real work.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The single-port LSQ is the most visible IPC limit that remains.
            Tight memory-stream inner loops still see one of their two issue
            slots sit idle because two adjacent loads serialize at the cache.
          </p>
        </section>

        {/* §V.B — Early Tag Broadcast */}
        <section id="etb" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Early Tag Broadcast
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            A consumer that depends on a multiply normally waits for the
            multiplier&rsquo;s value to land on the CDB before it can issue.
            But the multiplier&rsquo;s latency is fixed and known the moment
            the multiply enters the unit, so a dependent could in principle
            wake up earlier and be ready to issue on the cycle the value
            actually arrives.
          </p>
          <ETBDiagram />
          <p className="mt-6 text-ink-muted max-w-3xl">
            The mechanism is one extra wire. When a multiply enters the
            multiplier&rsquo;s first stage, the unit drives the destination tag
            onto a dedicated early-tag sideband that runs alongside the CDB but
            is not part of it. RS entries watch that wire the same way they
            watch the CDB tag; a match flips the source&rsquo;s registered
            ready bit one cycle early. The value itself still rides the CDB at
            the original cycle &mdash; ETB is purely an issue-eligibility
            wakeup, not a value bypass. The MULT pipeline in the actual RTL is
            8 stages (
            <code className="text-iris-600">MULT_STAGES = 8</code> in{' '}
            <code className="text-iris-600">sys_defs.svh</code>); the diagram
            draws 5 schematic stages for legibility.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            Disabling ETB raises geomean cycle count by{' '}
            {ETB_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%; the worst case
            is <code className="text-iris-600">{ETB_ROW?.worstCaseProgram}</code>{' '}
            at +{ETB_ROW?.worstCaseDeltaPct.toFixed(2)}%. That program runs a
            tight back-to-back multiply loop and is the workload most directly
            aligned with what ETB optimizes. Elsewhere the multiplier is not
            on the critical path of the program, so an earlier wakeup does not
            change much. The single-CDB-broadcast rule from the base design
            also gates the win: a non-MULT consumer woken by the early tag
            still has to wait its turn on the bus when the MULT broadcast
            lands the same cycle.
          </p>
        </section>

        {/* §V.C.1 — gshare */}
        <section id="gshare" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            gshare Predictor
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            The bimodal baseline indexed the 64-entry BHT with PC bits alone.
            Two unrelated branches whose PCs landed on the same six-bit slice
            shared a counter, so a loop-control branch and a data-dependent
            branch sitting next to each other in the binary trained the same
            counter and polluted each other&rsquo;s prediction. Loop-control
            and data-dependent branches tend to sit near each other in
            compiled code, so this collision was common rather than rare.
          </p>
          <BranchPredictorDiagram />
          <p className="mt-6 text-ink-muted max-w-3xl">
            The gshare design indexes the BHT by{' '}
            <code className="text-iris-600">PC[7:2] XOR GHR</code>, where the
            6-bit Global History Register holds the taken/not-taken outcomes
            of recent committed conditional branches. The GHR width matches
            the BHT index width so every history bit affects the index. A
            single hot branch with a TNTNTNT&hellip; pattern now lands on six
            different counters depending on which history led into it, instead
            of fighting itself on one.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            Disabling gshare raises geomean cycle count by{' '}
            {GSHARE_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%; the worst
            case is{' '}
            <code className="text-iris-600">{GSHARE_ROW?.worstCaseProgram}</code>{' '}
            at +{GSHARE_ROW?.worstCaseDeltaPct.toFixed(2)}% &mdash; the
            workload pattern gshare was built for, where the same call site
            sees a short, regular taken/not-taken history that the XOR fold
            can specialize on but the bimodal table cannot. Branch accuracy
            across the suite lifts by{' '}
            {SUITE_SUMMARY.branchAccLiftOverBimodalPp.toFixed(2)} pp arithmetic
            mean over the bimodal baseline (
            {SUITE_SUMMARY.bimodalArithMeanBranchAcc.toFixed(2)}%) on the same
            30 programs that execute at least one conditional branch.
          </p>
        </section>

        {/* §V.C.2 — RAS (shares the diagram with gshare) */}
        <section id="ras" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Return Address Stack
          </h2>
          <p className="text-ink-muted max-w-3xl">
            Function returns are nearly 100% predictable in principle, because
            the right target is always &ldquo;go back to the call site that
            wrote the return address into the link register.&rdquo; The BTB
            cannot exploit that &mdash; it caches one target per branch, so a
            recursive function whose return sees a different call site on
            every frame leaves the BTB constantly relearning the wrong target.
            Every switch between frames mispredicts.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The RAS is a 16-entry hardware stack alongside the gshare BHT (see
            the diagram above). When the front end sees a JAL that writes the
            link register, the next-PC is pushed. When the front end sees a
            return-shaped JALR (
            <code className="text-iris-600">x0, ra, 0</code>), the top of the
            stack supplies the predicted target and the entry is popped. On
            returns, the RAS overrides the BTB. When the stack is empty, the
            override does not fire and the predictor falls back to the BTB, so
            cold-start behavior matches the pre-RAS design.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Disabling the RAS raises geomean cycle count by{' '}
            {RAS_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%; the worst case
            is{' '}
            <code className="text-iris-600">{RAS_ROW?.worstCaseProgram}</code>{' '}
            at +{RAS_ROW?.worstCaseDeltaPct.toFixed(2)}%. The benchmark suite
            does not have enough deep recursion in its hot paths to make the
            RAS dominant at the geomean level. Where it does help, it replaces
            a steady stream of BTB mispredicts with a stack lookup that gets
            the target right on every call frame.
          </p>
        </section>

        {/* §V.E — STLF */}
        <section id="stlf" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Store-to-Load Forwarding
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            A load that asks for an address an older store has just written
            should not have to wait for the cache. In a write-back design, the
            store sits in the LSQ until commit, then waits for a cache port,
            then marks the line dirty. A dependent load behind it pays every
            one of those cycles for what is logically a register-to-register
            move.
          </p>
          <STLFDiagram />
          <p className="mt-6 text-ink-muted max-w-3xl">
            When a load reaches the head of the LSQ, the queue compares its
            address against every older un-committed store on the same 8-byte
            line. If the most recent matching store fully covers the
            load&rsquo;s byte range and its data is already known, the load
            completes in one cycle out of the LSQ and the cache never sees the
            request. Anything that breaks the chain blocks the forward: an
            older store with an unresolved address, an older store whose data
            has not arrived yet, or a partial overlap where the load needs
            bytes the store did not write. Partial overlap is intentionally
            not merged; the regression set does not contain programs where it
            would fire often enough to matter, and the correctness corners are
            easier to reason about when partial overlap simply waits.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            Disabling STLF raises geomean cycle count by{' '}
            {STLF_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%; the worst
            case is{' '}
            <code className="text-iris-600">{STLF_ROW?.worstCaseProgram}</code>{' '}
            at +{STLF_ROW?.worstCaseDeltaPct.toFixed(2)}%. The canonical
            pattern is an inner loop that writes an array element and reads it
            back on the next iteration. A late timing-cleanup pass deferred
            the forward by one cycle (forwarded loads broadcast via the
            existing STLF latch), so each forwarded load now lands one cycle
            later than it would have. That cost only hits the small set of
            loads that actually forward.
          </p>
        </section>

        {/* §V.D.2 — Next-line prefetch (no dedicated diagram) */}
        <section id="prefetch" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Next-line Prefetch
          </h2>
          <p className="text-ink-muted max-w-3xl">
            Programs spend a lot of their time walking through memory in
            order: instruction fetch through straight-line code, array sweeps
            in matrix kernels, struct-field reads in image processing. Every
            cold line in that walk costs the full 100 ns memory latency, and
            the cache cannot start the fetch until the program asks for the
            line. A small prefetcher can fetch the next line in the background
            while the program is still using the current one.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The mechanism is a one-line stream buffer. On a miss fill for some
            line N, the buffer queues a request for line N+1 and issues it
            once the bus is free. If the program later misses on N+1 while the
            buffer is holding it, the line transfers into the cache without a
            fresh round trip to memory. The I-cache uses the shared{' '}
            <code className="text-iris-600">stream_buffer.sv</code> module;
            the D-cache has its own internal next-line prefetch logic in{' '}
            <code className="text-iris-600">dcache.sv</code>. Both are real,
            and bus arbitration in <code className="text-iris-600">pipeline.sv</code>{' '}
            makes sure speculative prefetch requests yield to demand fetches
            from either cache.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Disabling prefetch raises geomean cycle count by{' '}
            {PREFETCH_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%; the worst
            case is{' '}
            <code className="text-iris-600">{PREFETCH_ROW?.worstCaseProgram}</code>{' '}
            at +{PREFETCH_ROW?.worstCaseDeltaPct.toFixed(2)}%. For comparison,
            removing all five ablate-able features together raises geomean by{' '}
            {ALL_FIVE_ROW?.geomeanDeltaPctWhenDisabled.toFixed(2)}%, so the
            prefetcher alone accounts for nearly the entire gap. The worst-
            regressing programs under <code className="text-iris-600">no_prefetch</code>{' '}
            (alexnet, btest2, sampler) are the ones whose cycle count is most
            sensitive to instruction-fetch latency, which is why we read this
            as evidence that the I-cache side is the dominant beneficiary.
          </p>
        </section>

        {/* §V.D.1 — 2-way set-assoc D-cache */}
        <section id="set-associative" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            2-way Set-Associative D-Cache
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            A direct-mapped 256-byte D-cache with 8-byte lines has 32 slots,
            and any two addresses whose index bits collide have to share one
            slot. If a program walks two arrays whose strides happen to fold
            onto the same slot, every reference evicts the other one even
            though the rest of the cache is sitting empty. Sort-style inner
            loops do this regularly: an array element, a loop counter, and a
            comparison key all touching memory in the same iteration.
          </p>
          <DCacheDiagram />
          <p className="mt-6 text-ink-muted max-w-3xl">
            The 2-way layout splits the same 256 bytes into 16 sets of 2 lines
            each. An address now picks a set, and either of the two ways
            inside that set can hold the line. Each set carries a single LRU
            bit that tracks which way was touched more recently &mdash; at
            2-way, one bit of state is exact LRU rather than an approximation.
            On a miss into a set whose ways are both valid, the eviction picks
            the LRU way.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            Worth being precise about cache state: each line carries{' '}
            <strong>one</strong> valid bit and{' '}
            <strong>one</strong> dirty bit, not byte-granular masks. Byte
            granularity exists only on the write path: the LSQ supplies an
            8-bit <code className="text-iris-600">proc_wr_be</code> byte-
            enable that selects which bytes of a line get rewritten on a
            hit/store, and which bytes of a fill response are overridden on a
            miss-and-store. Sub-word stores work; the cache itself just
            doesn&rsquo;t track per-byte status.
          </p>
          <p className="mt-4 text-ink-muted max-w-3xl">
            This is the second structural feature. The 2-way geometry is
            wired into the array dimensions of <code className="text-iris-600">dcache.sv</code>{' '}
            and into the address decode; there is no{' '}
            <code className="text-iris-600">+define</code> that turns it back
            into a direct-mapped cache without a substantial RTL rebuild. Its
            contribution is best read as the residual on programs whose inner
            loops walk two stride-aligned arrays (sort and search kernels,
            plus <code className="text-iris-600">bfs</code> and{' '}
            <code className="text-iris-600">graph</code>): those post the
            largest reductions from OoO base to all-on, and the prefetch
            ablation alone does not account for the full size of those cuts.
          </p>
        </section>

        {/* §VII — Per-program speedup chart */}
        <section id="speedup" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Per-program speedup
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            Δ% per program from OoO base to all-on, sorted by largest speedup
            first. Negative is faster. The two regressions (
            <code className="text-iris-600">evens</code> +0.34% and{' '}
            <code className="text-iris-600">insertion</code> +2.13%) are
            shown in orchid; both come down to gshare BHT aliasing on the
            programs&rsquo; specific branch pairs.
          </p>
          <PerProgramSpeedupChart />
          <p className="mt-6 text-ink-muted max-w-3xl">
            Geomean speedup over the suite is{' '}
            {SUITE_SUMMARY.geomeanDeltaPct.toFixed(2)}% (arithmetic mean{' '}
            {SUITE_SUMMARY.arithMeanDeltaPct.toFixed(2)}%). The biggest
            speedups land on ALU-bound code with predictable branches
            (<code className="text-iris-600">alexnet</code>,{' '}
            <code className="text-iris-600">btest2</code>,{' '}
            <code className="text-iris-600">sampler</code>); the smallest land
            on programs whose inner loops are dominated by the single-port LSQ
            or by serial dependences the OoO machine cannot break.
          </p>
        </section>

        {/* Branch accuracy chart */}
        <section id="branch-acc" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Branch accuracy
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            Conditional-branch prediction accuracy at the all-on operating
            point, per program, sorted high to low. The dashed line is the
            geomean ({SUITE_SUMMARY.geomeanBranchAcc.toFixed(2)}%) over the 30
            programs that execute at least one conditional branch. Three
            programs (<code className="text-iris-600">haha</code>,{' '}
            <code className="text-iris-600">halt</code>,{' '}
            <code className="text-iris-600">no_hazard</code>) execute zero
            conditional branches and are excluded.
          </p>
          <BranchAccLiftChart />
          <p className="mt-6 text-ink-muted max-w-3xl">
            Arithmetic mean is{' '}
            {SUITE_SUMMARY.arithMeanBranchAcc.toFixed(2)}%, a lift of{' '}
            {SUITE_SUMMARY.branchAccLiftOverBimodalPp.toFixed(2)} pp over the
            bimodal baseline ({SUITE_SUMMARY.bimodalArithMeanBranchAcc.toFixed(2)}%).
            The largest lifts land on programs whose branch behavior the
            bimodal table could not specialize on (<code className="text-iris-600">omegalul</code>,{' '}
            <code className="text-iris-600">btest1</code>,{' '}
            <code className="text-iris-600">priority_queue</code>,{' '}
            <code className="text-iris-600">bfs</code>,{' '}
            <code className="text-iris-600">basic_malloc</code>); programs
            whose branches are mostly counted loop tests already sit near
            85&ndash;88% accuracy under bimodal and gain fractions of a
            percentage point or none at all.
          </p>
        </section>

        {/* CPI distribution */}
        <section id="cpi" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            CPI distribution
          </h2>
          <p className="text-ink-muted max-w-3xl mb-6">
            All-on cycles-per-instruction across the 33-program suite, binned.
            Geomean CPI is {SUITE_SUMMARY.geomeanCpi.toFixed(2)}; arithmetic
            mean is {SUITE_SUMMARY.arithMeanCpi.toFixed(2)}, pulled up by a
            handful of toy programs that pay full memory latency on a few
            fetches (<code className="text-iris-600">halt</code> at CPI 106 is
            the extreme). The kernel-style workloads that are representative
            of real use sit between 3 and 30 CPI.
          </p>
          <CpiHistogram />
        </section>

        {/* §VII / §VIII — Synthesis & timing */}
        <section id="timing" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Synthesis &amp; timing
          </h2>
          <p className="text-ink-muted max-w-3xl">
            All seven module-level testbenches (
            <code className="text-iris-600">mult</code>,{' '}
            <code className="text-iris-600">rob</code>,{' '}
            <code className="text-iris-600">rs</code>,{' '}
            <code className="text-iris-600">lsq</code>,{' '}
            <code className="text-iris-600">dcache</code>,{' '}
            <code className="text-iris-600">icache</code>,{' '}
            <code className="text-iris-600">branch_predictor</code>) meet
            timing at the {TIMING.clockTargetPs} ps target.{' '}
            <code className="text-iris-600">mult</code> and{' '}
            <code className="text-iris-600">lsq</code> are the tightest at
            +0.23 ps and +0.05 ps; the other five clear by hundreds of
            picoseconds.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The full-pipeline netlist (
            <code className="text-iris-600">synth/pipeline.vg</code>) does not
            meet timing at {TIMING.clockTargetPs} ps. Worst slack is{' '}
            <strong>{TIMING.worstSlackPs} ps</strong> on the path{' '}
            <code className="text-iris-600">{TIMING.criticalPath}</code>, with
            a companion endpoint at {TIMING.secondWorstSlackPs} ps on the same
            cone. Every other endpoint in the design meets at the same clock.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            The cone runs LSQ broadcast → RS operand mux → ALU 32-bit adder →
            {' '}
            <code className="text-iris-600">{'{ROB take_branch, LSQ addr}'}</code>:
            a single 32-bit ripple-carry adder with high fanout sits in the
            middle of a long combinational chain. Closing it would mean either
            registering <code className="text-iris-600">load_complete_value</code>{' '}
            and <code className="text-iris-600">load_complete_tag</code>{' '}
            between the LSQ broadcast arbiter and the CDB (one extra cycle on
            every completing load) or splitting the ALU&rsquo;s 32-bit adder
            into two pipeline stages (one extra cycle on every ALU op). Both
            pay perf on the common case to fix the static-timing residual, so
            this pass ships as-is.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Functional correctness and static-timing closure are different
            things. Every <code className="text-iris-600">.syn.wb</code>{' '}
            writeback trace produced by the gate-level netlist is byte-
            identical to the corresponding RTL{' '}
            <code className="text-iris-600">.wb</code> across all 33 programs
            on the pre-multiplier-operand-register baseline. The synthesized
            machine commits the same architectural register-write stream as
            the RTL on every program, modulo the standard one-cycle reset
            offset.
          </p>
        </section>

        {/* §VI — Verification methodology */}
        <section id="verification" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Verification methodology
          </h2>
          <p className="text-ink-muted max-w-3xl">
            Three layers, each catching a different class of bug. At the
            bottom, every nontrivial module has its own SystemVerilog
            testbench. A test passes only if the run prints{' '}
            <code className="text-iris-600">@@@ Passed</code>. The RTL unit
            suite covers <code className="text-iris-600">mult</code>,{' '}
            <code className="text-iris-600">rob</code>,{' '}
            <code className="text-iris-600">rs</code>,{' '}
            <code className="text-iris-600">lsq</code>,{' '}
            <code className="text-iris-600">dcache</code>,{' '}
            <code className="text-iris-600">icache</code>, and{' '}
            <code className="text-iris-600">branch_predictor</code>.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Above that, the full pipeline runs all{' '}
            {SUITE_SUMMARY.programCount} RV32IM programs end to end, checked
            for a clean halt on{' '}
            <code className="text-iris-600">@@@ System halted on WFI instruction</code>{' '}
            and a correct register-write trace. On top of both layers, the
            same tests run a second time against the gate-level netlist that
            Synopsys DC produces. A small wrapper per module (
            <code className="text-iris-600">synth/&lt;m&gt;_svsim.sv</code>)
            sits between the testbench and the netlist and uses the
            SystemVerilog stream operator{' '}
            <code className="text-iris-600">{`{>>{ }}`}</code> to repack DC&rsquo;s
            flattened ports into the shape the testbench expects.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Two byte-equivalence checks back up the regression. First, every{' '}
            <code className="text-iris-600">.syn.wb</code> trace is byte-
            identical to its <code className="text-iris-600">.wb</code> on the
            pre-multiplier-operand-register baseline. Second, every{' '}
            <code className="text-iris-600">.wb</code> on the post-merge build
            is byte-identical to the trace produced by rebuilding the same
            commit under{' '}
            <code className="text-iris-600">+define+SERIALIZE_BRANCHES</code>,
            which forces the front end to serialize on every conditional
            branch. If out-of-order issue plus speculation drifted from what
            a serialized front end would have done on the same program, this
            check would fail. It does not.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            Five compile-time disable knobs (
            <code className="text-iris-600">DISABLE_EARLY_TAG</code>,{' '}
            <code className="text-iris-600">DISABLE_GSHARE</code>,{' '}
            <code className="text-iris-600">DISABLE_RAS</code>,{' '}
            <code className="text-iris-600">DISABLE_STLF</code>,{' '}
            <code className="text-iris-600">DISABLE_PREFETCH</code>) drive the
            ablation sweep. Each compiles cleanly and produces a working
            binary that halts every program. The two structural features
            cannot be rolled back with a{' '}
            <code className="text-iris-600">+define</code>.
          </p>
        </section>

        {/* §VIII — Limitations */}
        <section id="limitations" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            Limitations &amp; future work
          </h2>
          <p className="text-ink-muted max-w-3xl">
            <strong>Pipeline timing residual.</strong> The {TIMING.worstSlackPs} ps
            slack on the LSQ → RS → ALU adder cone is the one limitation we
            would close first. Both fixes (registering the LSQ broadcast or
            splitting the ALU adder) cost a cycle on the common case to
            recover ~800 ps of static-timing slack, which we judged the wrong
            trade at this point in the project.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            <strong>Single-port LSQ on a 2-way machine.</strong> Two adjacent
            loads still serialize at the cache, so the front-end widening is
            not always matched by back-end memory bandwidth. The natural next
            step on a wider machine is a dual-ported LSQ paired with a dual-
            ported or banked D-cache.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            <strong>Single multiplier.</strong> Multiply-heavy code caps out
            at one issue per cycle through the multiplier. ETB recovers a
            cycle by waking dependent consumers ahead of the CDB broadcast,
            but a second multiplier would do better. We did not add one
            because doubling area for a single functional class was hard to
            justify against an ablation that suggested the marginal cycles
            available were small.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            <strong>Rename style at wider issue.</strong> If we were widening
            past 2-way, we would revisit the embedded-RAT-in-ROB rename
            approach. A unified physical register pool in the R10K style
            would make more sense at four-wide, where the simplicity payoff
            of treating ROB entries as physical registers starts to fall off.
          </p>
          <p className="text-ink-muted max-w-3xl mt-4">
            <strong>An ablation lesson worth naming.</strong> Once the
            prefetcher is in place, the simpler features stacked on top of an
            already-tuned base contribute less on geomean than they would in
            isolation, because the prefetcher has already taken the cycles
            they would have saved. The bottleneck on this suite at this clock
            is memory latency. That is not a failure of the smaller features;
            it is a description of the workload.
          </p>
        </section>

        {/* References & team */}
        <section id="refs" className="scroll-mt-24">
          <h2 className="text-3xl font-semibold text-plum-500 mb-3">
            References &amp; team
          </h2>
          <h3 className="text-lg font-semibold text-iris-600 mt-6 mb-3">
            Team
          </h3>
          <p className="text-ink-muted max-w-3xl">{TEAM.join(' · ')}</p>

          <h3 className="text-lg font-semibold text-iris-600 mt-8 mb-3">
            References
          </h3>
          <ol className="list-decimal list-inside space-y-2 text-ink-muted max-w-3xl">
            {REFERENCES.map((ref, i) => (
              <li key={i}>{ref}</li>
            ))}
          </ol>

          <p className="text-ink-muted max-w-3xl mt-8">
            The full IEEE-format paper is available as a PDF:{' '}
            <a
              href="/4340-final-report.pdf"
              className="text-plum-500 hover:text-plum-600 underline"
            >
              4340-final-report.pdf
            </a>
            . The complete source is on{' '}
            <a
              href="https://github.com/CSEE4340-26/p4.GaPiChiXuXu"
              target="_blank"
              rel="noopener noreferrer"
              className="text-plum-500 hover:text-plum-600 underline"
            >
              GitHub
            </a>
            .
          </p>
        </section>
      </article>
    </div>
  );
}
