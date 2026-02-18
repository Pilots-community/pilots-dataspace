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
      "/api/management": {
        target: "http://localhost:19193",
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api\/management/, "/management"),
      },
      "/api/public": {
        target: "http://localhost:38185",
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api\/public/, "/public"),
      },
      "/api/health/cp": {
        target: "http://localhost:18181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/dp": {
        target: "http://localhost:38181",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
      "/api/health/ih": {
        target: "http://localhost:7090",
        changeOrigin: true,
        rewrite: () => "/api/check/health",
      },
    },
  },
});
