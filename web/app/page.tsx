export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col items-center justify-center gap-6 px-6 py-24 text-center">
      <h1 className="text-4xl font-semibold tracking-tight text-plum-500 sm:text-5xl">
        Out-of-Order RV32IM Processor
      </h1>
      <p className="max-w-xl text-lg text-ink-muted">
        EECS 4340 — Spring 2026. A synthesizable 2-way superscalar P6-style out-of-order RISC-V
        processor in SystemVerilog. Interactive demo coming soon.
      </p>
    </main>
  );
}
