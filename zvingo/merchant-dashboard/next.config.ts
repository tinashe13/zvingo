import type { NextConfig } from "next";

// Backend gateway that same-origin '/api/*' requests are proxied to.
// Rewrites are resolved at BUILD time, so set API_PROXY_URL when running
// `next build` (or as a Docker build arg). Defaults to the local dev Nginx.
const API_PROXY_URL = process.env.API_PROXY_URL || 'http://localhost:80';

const nextConfig: NextConfig = {
  // Emit a self-contained server bundle for the production Docker image.
  output: 'standalone',
  // Pin the workspace root to this app so stray lockfiles in parent
  // directories can't change the standalone output layout.
  turbopack: {
    root: __dirname,
  },
  outputFileTracingRoot: __dirname,
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${API_PROXY_URL}/api/:path*`, // Proxy to Nginx (which proxies to Backend)
      },
    ]
  },
};

export default nextConfig;
