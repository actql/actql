import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Read-only Vite output context comparison', command: process.execPath,
    args: ['reviews/2026-10-16-interface-hardening/i6/vite-output-context-diagnostic.mjs'], timeoutSeconds: 30}]});
