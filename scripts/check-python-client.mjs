import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const python = process.env.ACTQL_PYTHON ?? 'python3';
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 180, graceSeconds: 5,
  steps: [
    {name: 'Python contract generation', command: process.execPath, args: ['scripts/generate-python-client-wire.mjs', '--check']},
    {name: 'Python client boundary tests', command: python, args: ['packages/python-sdk/tests/run.py']},
    {name: 'Python public API type checks', command: python, args: ['-m', 'mypy', '--config-file', 'packages/python-sdk/pyproject.toml', 'scripts/fixtures/python-client-types.py']},
  ]});
