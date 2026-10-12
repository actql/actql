import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import {fileURLToPath} from 'node:url';
export default defineConfig({root: fileURLToPath(new URL('.', import.meta.url)),
  envPrefix: 'ACTQL_EXPLORER_PUBLIC_', plugins: [react(), tailwindcss()],
  build: {outDir: 'dist', emptyOutDir: true, sourcemap: false,
    lib: {entry: fileURLToPath(new URL('./plan-explorer.tsx', import.meta.url)),
      formats: ['es'], fileName: 'plan-explorer'},
    rollupOptions: {external: [/^react(?:\/|$)/, /^react-dom(?:\/|$)/,
      /^@xyflow\/react(?:\/|$)/, /^@base-ui\/react(?:\/|$)/, 'lucide-react']},
    cssCodeSplit: false, minify: false},
});
