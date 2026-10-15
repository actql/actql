import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, mode, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
assert.match(source, /^[a-f0-9]{40}$/u);
assert.ok(['deps', 'node'].includes(mode));
assert.equal(process.version, 'v22.22.0');
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert(before.clean);
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
const steps = mode === 'deps'
  ? [{name: 'Locked test-only dependencies, no lifecycle builds', command: 'npm',
    args: ['ci', '--ignore-scripts', '--no-audit', '--no-fund']}]
  : [{name: 'Normal composition admission and existing caller selection', command: process.execPath,
    args: ['--input-type=module', '-e', runner, '--', '--test', '--test-concurrency=1',
      'scripts/client-ci.test.mjs']},
  {name: 'Whitespace', command: 'git', args: ['diff', '--check']}];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps});
assert.deepEqual(checkoutState(process.cwd()), before);
