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
                pathname === l.href
                  ? 'text-iris-600 font-medium'
                  : 'text-ink-muted hover:text-plum-500',
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
