import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Runtime import discovery counterexamples and original TypeScript controls', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', '--test-name-pattern=^(?!real stdlib)',
      'scripts/runtime-import-interface-coverage.test.mjs',
      'scripts/typescript-interface-inventory.test.mjs', 'scripts/interface-inventory.test.mjs']}]});
