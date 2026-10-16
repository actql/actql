import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'I6 final immutable owner projections and computed representation controls', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-name-pattern=immutable syntax projection|closed literal and dynamic compiler field|syntax parser distinguishes|compiler internals require',
      'reviews/2026-10-16-interface-hardening/i6/owner-final-source-projections.test.mjs',
      'scripts/interface-inventory.test.mjs']}]});
