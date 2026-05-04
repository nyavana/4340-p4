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
