import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({
  variable: '--font-inter',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'Out-of-Order RV32IM Processor — EECS 4340 Spring 2026',
  description:
    'Interactive demo of a synthesizable 2-way superscalar P6-style out-of-order RISC-V processor in SystemVerilog.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col bg-snow-50 text-ink">{children}</body>
    </html>
  );
}
