import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Actual installed dependency resolver delta', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', '--test-name-pattern=^(actual installed resolver|resolved runtime targets)',
      'scripts/installed-interface-correspondence.test.mjs']},
  {name: 'Ordinary Explorer library build after retaining the stale own output', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {execFileSync} from "node:child_process";execFileSync("npm",["run","build","--prefix","packages/explorer-ui"],{stdio:"inherit",timeout:30000});']} ]});
