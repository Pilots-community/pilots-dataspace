import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    port: 3000,
    proxy: {
      "/api/provider": {
        target: "http://localhost:19193",
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api\/provider/, "/management"),
      },
      "/api/consumer": {
        target: "http://localhost:29193",
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api\/consumer/, "/management"),
      },
      "/api/health/provider-cp": {
        target: "http://localhost:18181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/consumer-cp": {
        target: "http://localhost:28181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/provider-dp": {
        target: "http://localhost:38181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/consumer-dp": {
        target: "http://localhost:48181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/provider-ih": {
        target: "http://localhost:7090",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/consumer-ih": {
        target: "http://localhost:7080",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
    },
  },
});
