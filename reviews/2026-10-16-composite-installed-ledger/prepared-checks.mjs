import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, phase] = process.argv.slice(2), root = process.cwd();
const before = checkoutState(root); assert(before.clean); assert.equal(before.revision, source);
assert(['prepare', 'counter'].includes(phase));
const file = 'src/query_integration/composite_installed_ledger_wbtest.mbt';
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root, heavy: phase === 'prepare',
  timeoutSeconds: phase === 'prepare' ? 180 : 60, graceSeconds: 5,
  ...(phase !== 'prepare' ? {} : {heavyResources: {memoryBytes: 2147483648,
    diskBytes: 1073741824, cpuThreads: 1}}),
  steps: [phase === 'prepare' ? {name: 'Affected single-package counter build, no execution',
    command: 'moon', args: ['test', '--build-only', '--target', 'js', '-j', '1', file]}
    : {name: 'Original composite installed Ledger counter', command: process.execPath,
      args: ['--input-type=module', '-e', runner, '--', '--target', 'js', '-j', '1', file]}]});
assert.deepEqual(checkoutState(root), before);
