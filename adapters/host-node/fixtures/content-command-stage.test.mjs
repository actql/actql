import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {contentCommandStageTrace} from './content-command-stage.fixture.mjs';

test('Content child stages emit complete bounded synchronous diagnostic records', () => {
  const records = [];
  let clock = 100;
  const stage = contentCommandStageTrace('approve', {
    write: record => records.push(record), now: () => clock,
  });
  clock = 117;
  stage('host-open-begin');
  assert.equal(records.length, 1);
  assert.ok(Buffer.byteLength(records[0]) < 256);
  assert.ok(records[0].endsWith('\n'));
  assert.deepEqual(JSON.parse(records[0]), {contentCommandStage: 'host-open-begin',
    phase: 'approve', pid: process.pid, elapsedMs: 17});
  stage('host-open-done');
  assert.equal(records.length, 2, 'the observation is written before returning');
});

test('Content child stages bound total records and never stringify diagnostic substitutes', () => {
  const records = [];
  const stage = contentCommandStageTrace('capture', {write: value => records.push(value)});
  const object = {toJSON() {assert.fail('No escaped object serialization');}};
  stage(object);
  stage('key\nsecret');
  for (let index = 0; index < 1000; index++) stage('observe-begin');
  assert.equal(records.length, 62, 'rejected input also consumes diagnostic work');
  assert.ok(records.every(record => Buffer.byteLength(record) < 256));
  for (const phase of [undefined, null, {}, 'not-an-execution-phase']) {
    contentCommandStageTrace(phase, {write() {assert.fail('No invalid phase output');}})('begin');
  }
});

test('Content diagnostic sink failure cannot interrupt the original cleanup path', () => {
  let attempts = 0;
  const stage = contentCommandStageTrace('read', {
    write() {attempts++; throw new Error('Closed diagnostic sink');},
  });
  const failure = new Error('Original physical failure');
  let closed = false;
  assert.throws(() => {
    try { stage('host-open-begin'); throw failure; }
    finally { stage('host-close-begin'); closed = true; stage('host-close-done'); }
  }, error => error === failure);
  assert.equal(closed, true);
  assert.equal(attempts, 3);
});

test('Content child retains its last started stage when a bounded diagnostic times out', () => {
  const module = new URL('./content-command-stage.fixture.mjs', import.meta.url).href;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {contentCommandStageTrace} from ${JSON.stringify(module)};
     const stage = contentCommandStageTrace('approve');
     stage('host-open-begin');
     setInterval(() => {}, 1000);`],
  {encoding: 'utf8', timeout: 1000, killSignal: 'SIGTERM'});
  assert.equal(child.error?.code, 'ETIMEDOUT');
  assert.equal(child.signal, 'SIGTERM');
  assert.equal(child.stdout, '');
  const records = child.stderr.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(records.length, 1);
  assert.equal(records[0].contentCommandStage, 'host-open-begin');
  assert.equal(records[0].phase, 'approve');
  assert.equal(records[0].pid, child.pid);
});
