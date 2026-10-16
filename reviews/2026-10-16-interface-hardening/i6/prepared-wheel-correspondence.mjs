import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Actual stdlib RECORD and source correspondence controls, no wheel producer', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', '--test-name-pattern=^real stdlib wheel', 'scripts/interface-inventory.test.mjs']},
  {name: 'Read-only retained SDK-only wheel exact member/source correspondence, not a normal cohort',
    command: 'python3', args: ['-B', 'reviews/2026-10-16-interface-hardening/i6/retained-sdk-wheel-correspondence.py']}]});
