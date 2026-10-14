import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, selection = 'pure'] = process.argv.slice(2);
assert.equal(process.version, 'v22.22.0');
assert.match(source, /^[a-f0-9]{40}$/u);
assert.ok(['pure', 'retained'].includes(selection));
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";' +
  'process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
const tests = selection === 'pure' ? ['adapters/host-node/ordinary-source-binding.test.mjs']
  : ['--test-name-pattern=ordinary bound|ordinary row binding',
    'adapters/host-node/client-request-journal.test.mjs',
    'adapters/host-node/installed-row-source.test.mjs'];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: `Ordinary installed Source binding ${selection} controls`, command: process.execPath,
      args: ['--input-type=module', '-e', runner, '--', '--test', ...tests]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
