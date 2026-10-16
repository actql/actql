import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Source references and actual Cloud binding regression; product/cohort/all-I6 unadmitted',
    command: process.execPath, args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', 'scripts/typescript-interface-inventory.test.mjs',
      'scripts/interface-owner-coverage.test.mjs',
      'reviews/2026-10-16-interface-hardening/i6/cloud-binding-export-regression.test.mjs',
      'reviews/2026-10-16-interface-hardening/i6/normal-owner-intake.test.mjs']}]});
