import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    proxy: {
      '/api': { target: 'http://127.0.0.1:5000', changeOrigin: true },
      // Permanent action endpoints that live outside /api/ (not pages, so
      // never becoming Vue routes) - the "sync now"/"clear database" buttons
      // fetch these directly.
      '/cron': { target: 'http://127.0.0.1:5000', changeOrigin: true },
      '/clear-cache': { target: 'http://127.0.0.1:5000', changeOrigin: true },
      // Static images hand-maintained in the backend's public/, referenced
      // directly by Vue components (AppNav/AppFooter) - without this, the
      // dev server can't find them and silently serves the SPA shell
      // instead (200 OK, but text/html), so they render as broken images
      // in dev only. Add new backend-served images here as they come up.
      '/scout-navigator-badge.png': { target: 'http://127.0.0.1:5000', changeOrigin: true },
      '/favicon.svg': { target: 'http://127.0.0.1:5000', changeOrigin: true },
    },
  },
  build: {
    outDir: '../FellScout/public',
    emptyOutDir: false,
  },
})
