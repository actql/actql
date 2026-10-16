import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Original provider argument provenance controls', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', 'scripts/provider-runtime-interface.test.mjs']},
  {name: 'Actual ordinary local-node interface command positive', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {execFileSync} from "node:child_process";execFileSync("npm",["run","check:interfaces","--","--manifest","packages/local-node/package.json"],{stdio:"inherit",timeout:30000});']}]});
