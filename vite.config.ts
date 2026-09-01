import { defineConfig } from 'vite';

// Tauri serves the dev build over a fixed port and bundles the production
// build from dist/. Sourcemaps stay on in debug so panics in the webview map
// back to the TypeScript.
export default defineConfig({
  clearScreen: false,
  server: {
    port: 5183,
    strictPort: true,
    watch: { ignored: ['**/src-tauri/**'] },
  },
  build: {
    target: 'chrome110',
    minify: process.env.TAURI_ENV_DEBUG ? false : 'esbuild',
    sourcemap: !!process.env.TAURI_ENV_DEBUG,
    outDir: 'dist',
    emptyOutDir: true,
  },
});
