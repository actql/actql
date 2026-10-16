import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'I6 Explorer original-reference coverage and selected real wrapper boundaries', command: process.execPath,
    args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});',
      '--', '--test-concurrency=1', '--test-name-pattern=reviewed Explorer references|both Join roles retain exact|scope abort retires its Worker|lost or malformed cancellation replies',
      'reviews/2026-10-16-interface-hardening/i6/explorer-owner-references.test.mjs',
      'packages/explorer-ui/read-model.test.mjs', 'packages/explorer-ui/flow-layout.test.mjs',
      'packages/explorer/cancellation.test.mjs']}]});
