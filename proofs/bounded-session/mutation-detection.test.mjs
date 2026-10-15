import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {requireMutationDetection} from './mutation-command.mjs';

const output = 'Total tests: 3, passed: 2, failed: 1.\n';
const terminal = {status: 1, signal: null};

test('completed nonzero child with executing assertions retains its failure count', () => {
  assert.equal(requireMutationDetection(terminal, output), 1);
  assert.equal(requireMutationDetection({...terminal, status: 2},
    'Total tests: 4, passed: 2, failed: 2.\n'), 2);
});

for (const [name, result] of [
  ['parent interruption after a nonzero child', {...terminal, interrupted: 'SIGTERM'}],
  ['child signal after assertion-shaped output', {status: null, signal: 'SIGTERM'}],
  ['missing terminal status', {signal: null}],
  ['null terminal status', {status: null, signal: null}],
  ['fractional exit', {...terminal, status: 1.5}],
  ['successful process', {...terminal, status: 0}],
  ['spawn error', {...terminal, error: new Error('SpawnFailed')}],
]) test(`assertion text cannot admit ${name}`, () => {
  assert.throws(() => requireMutationDetection(result, output));
});

for (const [name, text] of [
  ['compile error before assertion text', 'Error: [3001] invalid source\n' + output],
  ['no test summary', 'assertion text without execution totals'],
  ['zero failing assertions', 'Total tests: 3, passed: 3, failed: 0.\n'],
  ['unsafe failure count', 'Total tests: 9007199254740992, passed: 0, failed: 9007199254740992.\n'],
]) test(`completed child still refuses ${name}`, () => {
  assert.throws(() => requireMutationDetection(terminal, text));
});

test('real self-signaled local child cannot turn printed assertions into detection',
  {skip: process.platform === 'win32'}, () => {
    const result = spawnSync(process.execPath, ['-e',
      "console.log('Total tests: 1, passed: 0, failed: 1.');process.kill(process.pid,'SIGTERM');"],
    {encoding: 'utf8', timeout: 3000, maxBuffer: 4096});
    assert.ifError(result.error);
    assert.equal(result.status, null);
    assert.equal(result.signal, 'SIGTERM');
    assert.match(result.stdout, /Total tests: 1, passed: 0, failed: 1/);
    assert.throws(() => requireMutationDetection(result, result.stdout), /Process failure/);
  });
