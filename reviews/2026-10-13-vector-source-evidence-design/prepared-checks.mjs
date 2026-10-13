import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, selection] = process.argv.slice(2);
assert.match(source, /^[a-f0-9]{40}$/u);
const selections = {
  declaration: [
    'src/check_environment/relation_keys_test.mbt',
    'src/query_program/vector_source_order_boundary_test.mbt',
    'src/query_program/vector_scalar_source_test.mbt',
  ],
  acquisition: ['src/query_integration/source_relation_keys_wbtest.mbt'],
  keycursor: [
    'src/execution_relation/input_keys_wbtest.mbt',
    'src/execution_relation/supplied_key_validation_wbtest.mbt',
  ],
};
assert.ok(Object.hasOwn(selections, selection), 'Select one allocated focused boundary');
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({
  root: process.cwd(), heavy: false, timeoutSeconds: 60, graceSeconds: 5,
  steps: [
    {name: `SourceView keys: ${selection}`, command: 'node',
      args: ['--input-type=module', '-e', runner, 'moon', '--target', 'js', '-j', '2', ...selections[selection]]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ],
});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
