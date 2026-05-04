import type { NextConfig } from 'next';
import path from 'node:path';

const config: NextConfig = {
  output: 'export',
  images: { unoptimized: true },
  trailingSlash: true,
  // Pin the workspace root to this directory so Next.js does not walk up the
  // tree and pick up an unrelated lockfile (e.g. one in $HOME).
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default config;
