import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// During development Vite proxies /api to the Julia backend.
// For the local production demo, Julia serves frontend/dist and /api itself.
const backend = process.env.NEXTLAB_BACKEND ?? 'http://127.0.0.1:8080'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': backend,
    },
  },
})
