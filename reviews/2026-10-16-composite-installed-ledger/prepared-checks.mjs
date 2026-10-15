import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, phase] = process.argv.slice(2), root = process.cwd();
const before = checkoutState(root); assert(before.clean); assert.equal(before.revision, source);
assert(['prepare', 'counter', 'prepare-comparison', 'comparison', 'api'].includes(phase));
const file = 'src/query_integration/composite_installed_ledger_wbtest.mbt';
const comparisons = ['src/execution_relation/positional_identity_order_wbtest.mbt',
  'src/execution_relation/stable_order_wbtest.mbt',
  'src/execution_relation/bounded_distinct_tree_wbtest.mbt'];
const preparing = phase.startsWith('prepare');
const selected = phase.includes('comparison') ? comparisons : [file];
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root, heavy: preparing,
  timeoutSeconds: preparing ? 180 : 60, graceSeconds: 5,
  ...(!preparing ? {} : {heavyResources: {memoryBytes: 2147483648,
    diskBytes: 1073741824, cpuThreads: 1}}),
  steps: [phase === 'api' ? {name: 'Affected public API generation', command: 'moon',
    args: ['info', '--target', 'js', 'src/pipeline_typing', 'src/lowering_relation']}
    : preparing ? {name: 'Affected single-package counter build, no execution',
    command: 'moon', args: ['test', '--build-only', '--target', 'js', '-j', '1', ...selected]}
    : {name: 'Original composite installed Ledger counter', command: process.execPath,
      args: ['--input-type=module', '-e', runner, '--', '--target', 'js', '-j', '1', ...selected]}]});
if (phase === 'api') assert.equal(checkoutState(root).revision, before.revision);
else
assert.deepEqual(checkoutState(root), before);
