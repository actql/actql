import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source = process.argv[2];
assert.match(source, /^[0-9a-f]{40}$/u);
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert.equal(before.clean, true);
const args = ['--target', 'js', '-j', '1', 'src/query_syntax',
  '--file', 'temporal_public_identifier_fixture_test.mbt'];
const code = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 270, graceSeconds: 5, steps: [{
    name: 'Original temporal reserved alias refusals and unchanged quoted semantics',
    command: process.execPath, args: ['--input-type=module', '-e', code],
  }]});
assert.deepEqual(checkoutState(process.cwd()), before);
