import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'I6 Client original-reference coverage and selected actual facade boundaries', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', '--test-name-pattern=reviewed Client facades|failed reader cleanup retains|attach refuses a first foreign Run|typed Submission refusal retains',
      'reviews/2026-10-16-interface-hardening/i6/client-owner-references.test.mjs',
      'packages/sdk/client-close.test.mjs', 'packages/sdk/response-capture.test.mjs',
      'packages/sdk/submission-attempt.test.mjs']}]});
