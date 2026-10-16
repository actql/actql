import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
assert.equal(process.version, 'v22.22.0');
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert(before.clean);
const run = 'import{runFocusedTests}from"./scripts/test-execution.mjs";' +
  'process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Original installed Effect binding, legacy scope and existing ordinary controls',
      command: process.execPath, args: ['--input-type=module', '-e', run, '--',
        'adapters/host-node/acquired-effect-source-binding.test.mjs',
        'adapters/host-node/acquired-effect-computation.test.mjs',
        'adapters/host-node/ordinary-source-binding.test.mjs']},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);
