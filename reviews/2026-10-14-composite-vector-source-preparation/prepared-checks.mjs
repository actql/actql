import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, selection, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
assert.match(source, /^[a-f0-9]{40}$/u);
assert.ok(['snapshots', 'preparation'].includes(selection));
const before = checkoutState(process.cwd());
assert.equal(before.revision, source); assert.equal(before.clean, true);
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";' +
  'process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd(),timeout:30000});';
const args = selection === 'snapshots'
  ? ['node', '--test', 'scripts/composite-vector-source-preparation.test.mjs']
  : ['moon', '--target', 'js', '-j', '1',
    'src/query_integration/composite_vector_source_preparation_wbtest.mbt'];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: `Original composite Vector Source ${selection}`, command: 'node',
      args: ['--input-type=module', '-e', runner, '--', ...args]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.deepEqual(checkoutState(process.cwd()), before);
