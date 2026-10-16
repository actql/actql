import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Native CLI actual source/copy and existing artifact reader controls, no Native execution', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', 'scripts/native-cli-interface-check.test.mjs', 'scripts/native-cli-release.test.mjs']},
  {name: 'Actual ordinary Native CLI source interface command', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {execFileSync} from "node:child_process";execFileSync("npm",["run","check:interfaces","--","--manifest","packages/native-cli/package.json"],{stdio:"inherit",timeout:30000});']}]});
