import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, phase] = process.argv.slice(2);
const root = process.cwd(), before = checkoutState(root);
assert(before.clean); assert.equal(before.revision, source);
assert(['counter', 'regression'].includes(phase));
const focused = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd(),timeout:30000});`;
const args = phase === 'counter'
  ? ['--test-name-pattern=^portable dependency payload custody retains Table and Result roots', 'adapters/host-common/publication-contract-control.test.mjs']
  : ['adapters/host-common/completed-effect-capture-retirement.test.mjs'];
process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [{name: 'Exact physical dependency custody metadata boundary', command: process.execPath,
    args: ['--input-type=module','-e',focused,'--',...args]}]});
assert.deepEqual(checkoutState(root), before);
