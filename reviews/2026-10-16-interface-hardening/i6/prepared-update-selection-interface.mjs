import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'UPDATE selection actual AST and original Owner references', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', 'scripts/update-selection-interface.test.mjs']}]});
