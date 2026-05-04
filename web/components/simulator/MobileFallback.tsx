export function MobileFallback() {
  return (
    <div className="lg:hidden mx-auto max-w-md px-6 py-24 text-center">
      <h1 className="text-2xl font-semibold text-plum-500">Open this on a wider screen</h1>
      <p className="mt-4 text-ink-muted">
        The pipeline visualizer needs at least a laptop-sized viewport to render legibly.
        Try opening this page on a desktop — or read the{' '}
        <a href="/deep-dive" className="text-iris-600">deep dive</a> instead.
      </p>
    </div>
  );
}
