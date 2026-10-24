import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// During development Vite proxies /api to the Julia backend.
// For the local production demo, Julia serves frontend/dist and /api itself.
const backend = process.env.NEXTLAB_BACKEND ?? 'http://127.0.0.1:8080'

export default defineConfig({
  plugins: [react()],
  // The Plotly basic bundle is a deliberate ~1.2 MB vendor chunk, loaded separately from the app.
  build: { chunkSizeWarningLimit: 1300 },
  server: {
    proxy: {
      '/api': backend,
    },
  },
})
