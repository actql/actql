import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, selection] = process.argv.slice(2);
assert.match(source, /^[a-f0-9]{40}$/u);
const selections = {
  admission: ['src/check_environment/relation_scores_test.mbt',
    'src/vector_typing/ranking_scores_test.mbt',
    'src/vector_typing/ranking_merge_test.mbt'],
  cursor: ['src/execution_relation/input_scores_wbtest.mbt'],
  acquisition: ['src/query_integration/source_relation_scores_wbtest.mbt',
    'src/query_integration/source_relation_keys_wbtest.mbt'],
};
assert.ok(Object.hasOwn(selections, selection));
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: `SourceView score ${selection}`, command: 'node', args:
      ['--input-type=module', '-e', runner, 'moon', '--target', 'js', '-j', '2', ...selections[selection]]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
