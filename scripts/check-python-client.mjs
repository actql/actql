import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 120, graceSeconds: 5,
  steps: [
    {name: 'Python contract generation', command: process.execPath, args: ['scripts/generate-python-client-wire.mjs', '--check']},
    {name: 'Python client boundary tests', command: process.env.ACTQL_PYTHON ?? 'python3', args: ['packages/python-sdk/tests/run.py']},
  ]});
