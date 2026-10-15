import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
export default defineConfig({root: fileURLToPath(new URL('.', import.meta.url)),
  envPrefix: 'ACTQL_EXPLORER_PUBLIC_', plugins: [react(), tailwindcss(), {
    // Keep the literal Worker URL in a small external module so the embedding
    // application's bundler emits its own same-origin Worker asset. A library
    // build must not bake a release-specific Worker URL into the shared UI.
    name: 'actql-layout-worker-sources', generateBundle() {
      for (const fileName of ['flow-layout.mjs', 'flow-layout-engine.mjs',
        'flow-layout-worker.mjs', 'presentation-limits.mjs']) {
        this.emitFile({type: 'asset', fileName, source: readFileSync(new URL(fileName, import.meta.url))});
      }
    },
  }],
  build: {outDir: 'dist', emptyOutDir: true, sourcemap: false,
    lib: {entry: fileURLToPath(new URL('./plan-explorer.tsx', import.meta.url)),
      formats: ['es'], fileName: 'plan-explorer'},
    rollupOptions: {external: [/^react(?:\/|$)/, /^react-dom(?:\/|$)/,
      /^@xyflow\/react(?:\/|$)/, /^@base-ui\/react(?:\/|$)/, 'lucide-react', './flow-layout.mjs']},
    cssCodeSplit: false, minify: false},
});
