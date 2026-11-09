import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Live market data is fetched from the browser through this dev server (same origin)
// so there are no CORS surprises and no API keys in the bundle.
const LIVE_PROXY = {
  "/live/stooq": {
    target: "https://stooq.com",
    changeOrigin: true,
    secure: true,
    rewrite: (p) => p.replace(/^\/live\/stooq/, ""),
    headers: { Referer: "https://stooq.com/", "User-Agent": "Mozilla/5.0 (Terminal)" },
  },
  "/live/binance": {
    target: "https://api.binance.com",
    changeOrigin: true,
    secure: true,
    rewrite: (p) => p.replace(/^\/live\/binance/, ""),
  },
  "/live/kraken": {
    target: "https://api.kraken.com",
    changeOrigin: true,
    secure: true,
    rewrite: (p) => p.replace(/^\/live\/kraken/, ""),
  },
  "/live/coinbase": {
    target: "https://api.exchange.coinbase.com",
    changeOrigin: true,
    secure: true,
    rewrite: (p) => p.replace(/^\/live\/coinbase/, ""),
  },
};

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 8787,
    strictPort: true,
    allowedHosts: true,
    proxy: LIVE_PROXY,
  },
  preview: { host: "0.0.0.0", port: 8787, allowedHosts: true, proxy: LIVE_PROXY },
  build: { outDir: "dist", sourcemap: false, chunkSizeWarningLimit: 1200 },
});
