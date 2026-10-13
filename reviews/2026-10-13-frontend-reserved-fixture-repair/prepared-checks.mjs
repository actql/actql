import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source = process.argv[2];
assert.match(source, /^[a-f0-9]{40}$/u);
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '', 'The selected source must be clean');
const selection = JSON.parse(readFileSync(new URL('./selection.json', import.meta.url), 'utf8'));
assert.equal(selection.files.length, 80);
assert.equal(new Set(selection.files).size, selection.files.length);
assert(selection.files.every(path => /^src\/query_(?:syntax|program)\/[a-z0-9_]+_test\.mbt$/u.test(path)));
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Active ordinary-name fixtures and existing quoted/refusal controls',
      command: 'node', args: ['--input-type=module', '-e', runner, '--',
        '--target', 'js', ...selection.files]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '', 'Do not edit a running source');
