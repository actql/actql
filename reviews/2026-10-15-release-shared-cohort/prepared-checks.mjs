import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.match(source, /^[a-f0-9]{40}$/u);
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert.equal(before.clean, true);
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";' +
  'process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Normal6-to-exact4 shared prepack counterexample', command: process.execPath,
      args: ['--input-type=module', '-e', runner, '--', '--test', 'scripts/package-release-shared-cohort.test.mjs']},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);
