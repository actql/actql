import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const before = checkoutState(process.cwd());
assert.equal(before.clean, true); assert.equal(before.revision, process.argv[2]);
const args = ['--target', 'js', '-j', '1',
  'src/query_program/temporal_public_lowering_control_test.mbt'];
const code = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 270, graceSeconds: 5, steps: [{name: 'Original interval-left independent Program and lowering control',
    command: process.execPath, args: ['--input-type=module', '-e', code]}]});
assert.deepEqual(checkoutState(process.cwd()), before);
