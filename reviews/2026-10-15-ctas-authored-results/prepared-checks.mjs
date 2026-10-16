import assert from 'node:assert/strict';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, phase, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0);
assert.match(source, /^[a-f0-9]{40}$/u);
assert(['prepare', 'test'].includes(phase));
assert.equal(process.version, 'v22.22.0');
const before = checkoutState(process.cwd());
assert.equal(before.revision, source);
assert(before.clean);
const runner = 'import{runFocusedTests}from"./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
const focused = (name, path, filter) => ({name, command: process.execPath,
  args: ['--input-type=module', '-e', runner, '--', '--target', 'js', '-j', '1',
    path, ...(filter === undefined ? [] : ['--filter', filter])]});
process.exitCode = await runLocalCheck({root: process.cwd(),
  heavy: phase === 'prepare',
  ...(phase === 'prepare' ? {heavyResources: {
    memoryBytes: 2147483648, diskBytes: 2147483648, cpuThreads: 1}} : {}),
  timeoutSeconds: phase === 'prepare' ? 300 : 60, graceSeconds: 5,
  steps: phase === 'prepare' ? [{
    name: 'Cold query_program JS test compilation only; no test execution',
    command: 'moon', args: ['test', '--build-only', '--target', 'js', '-j', '1',
      'src/query_program'],
  }] : [
    focused('Terminal Table authored Result and existing save-only controls',
      'src/query_program/table_effect_program_test.mbt'),
    focused('Ordinary retained Result semantics remain unchanged',
      'src/query_program/pipe_result_test.mbt'),
    focused('Existing UPDATE nonterminal Result retains its primary tail',
      'src/query_program/update_capture_test.mbt',
      'explicit earlier UPDATE expressions do not bind a renamed filtered tail'),
    {name: 'Document metadata freshness', command: process.execPath,
      args: ['scripts/update-document-metadata.mjs']},
    {name: 'Normative requirements freshness', command: process.execPath,
      args: ['scripts/check-actql-spec-family.mjs']},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ],
});
assert.deepEqual(checkoutState(process.cwd()), before);
