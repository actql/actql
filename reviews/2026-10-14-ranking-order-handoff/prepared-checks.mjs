import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source] = process.argv.slice(2);
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.match(source, /^[a-f0-9]{40}$/u);
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",["--target","js","-j","1","src/lowering_relation/ranking_order_handoff_test.mbt"],{cwd:process.cwd(),timeout:30000});';
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [
    {name: 'Checked ranking to ORDER handoff', command: process.execPath,
      args: ['--input-type=module', '-e', runner]},
    {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
  ]});
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
