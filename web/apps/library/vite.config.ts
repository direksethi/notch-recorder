import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vitest/config"

// Built into the app bundle (Resources/web) and loaded from nr-app://app/.
export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "../../../Resources/web",
    emptyOutDir: true,
    target: "safari18",
    cssMinify: true,
    chunkSizeWarningLimit: 1500,
  },
  test: { environment: "node", env: { TZ: "UTC" } },
})
