import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import {fileURLToPath} from 'node:url';
export default defineConfig({root: fileURLToPath(new URL('./app/', import.meta.url)),
  envPrefix: 'ACTQL_EXPLORER_PUBLIC_', plugins: [react()],
  build: {outDir: fileURLToPath(new URL('./dist/', import.meta.url)),
    emptyOutDir: true, sourcemap: false, assetsInlineLimit: 0},
});
