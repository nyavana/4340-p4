export function Footer() {
  return (
    <footer className="mt-32 border-t border-snow-600 bg-snow-500/60">
      <div className="mx-auto max-w-7xl px-6 py-10 text-sm text-ink-muted">
        <p>EECS 4340 — Spring 2026 — Columbia University</p>
        <p className="mt-2">
          Chenhao Yang · Xuepeng Han · Gavin Zou · Pingchuan Dong · Hins Lyu · Xueer Qian
        </p>
        <div className="mt-4 flex flex-wrap gap-4">
          <a
            href="https://github.com/CSEE4340-26/p4.GaPiChiXuXu"
            className="hover:text-plum-500"
          >
            GitHub
          </a>
          <a href="/4340-final-report.pdf" className="hover:text-plum-500">
            Report (PDF)
          </a>
          <a
            href="https://drive.google.com/drive/folders/1Cx6foIeGxm7YQhFhJAD3ntioi5XnTrun"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-plum-500"
          >
            More resources (Google Drive)
          </a>
        </div>
      </div>
    </footer>
  );
}
