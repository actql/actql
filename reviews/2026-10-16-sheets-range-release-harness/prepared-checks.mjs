import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source] = process.argv.slice(2);
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(process.version, 'v22.22.0');
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const focused = 'import{runFocusedTests}from"./scripts/test-execution.mjs";' +
  'process.exitCode=runFocusedTests("node",process.argv.slice(1),' +
  '{cwd:process.cwd(),timeout:30000});';
const scripts = ['scripts/test-packed-sheets.mjs', 'scripts/sheets-packed-cases.mjs',
  'scripts/sheets-packed-cases.test.mjs', 'scripts/packed-query-evidence.test.mjs'];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Four preparation controls through the existing packed-query CI entry',
      command: process.execPath, args: ['--input-type=module', '-e', focused, '--',
        '--test-name-pattern=^Sheets release', 'scripts/packed-query-evidence.test.mjs']},
    {name: 'Existing real normal-cohort admission and foreign/dirty/tampered negative controls',
      command: process.execPath, args: ['--input-type=module', '-e', focused, '--',
        'scripts/composition-release-input.test.mjs']},
    ...scripts.map(path => ({name: `Syntax ${path}`, command: process.execPath,
      args: ['--check', path]})),
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
