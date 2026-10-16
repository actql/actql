import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const invoke = args => ({command: process.execPath, args: ['--input-type=module', '-e',
  'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
  '--', '--test-concurrency=1', ...args]});
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Original installed member correspondence and trusted source evidence',
    ...invoke(['scripts/installed-interface-correspondence.test.mjs'])},
  {name: 'Actual member-derived dormant source and copied qualification refusal',
    ...invoke(['--test-name-pattern=^actual member-derived', 'scripts/required-interface-check.test.mjs'])}]});
