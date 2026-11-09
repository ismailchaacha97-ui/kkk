import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 8787,
    allowedHosts: true,
    strictPort: true,
  },
  preview: { host: "0.0.0.0", port: 8787, allowedHosts: true },
  build: { outDir: "dist", sourcemap: false },
});
