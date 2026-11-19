import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import test from 'node:test';
import {runPackedCompositionChild} from './packed-composition-child.mjs';

function packedChildPorts() {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  const observed = {spawns: [], starts: [], kills: [], cleared: []};
  const timer = {};
  child.kill = signal => { observed.kills.push(signal); return observed.killResult; };
  observed.killResult = true;
  const ports = {
    spawnChild: (...args) => { observed.spawns.push(args); return child; },
    setTimer: (callback, milliseconds) => {
      observed.fire = callback;
      observed.milliseconds = milliseconds;
      return timer;
    },
    clearTimer: value => { observed.cleared.push(value); },
    report: value => { observed.starts.push(value); },
  };
  return {child, observed, ports, timer};
}

test('packed child diagnostics preserve original invocation and expected held or successful close', async () => {
  for (const expectedExit of [0, 77]) {
    const {child, observed, ports, timer} = packedChildPorts();
    const env = {PRIVATE_TEST_VALUE: 'never-in-diagnostics'};
    const args = ['rce-submit', 'private-request-marker'];
    const result = runPackedCompositionChild({script: 'effect-run.mjs', cwd: '/original',
      env, args, expectedExit, source: 'infer-graph-node', protocol: 'local'}, ports);
    assert.deepEqual(observed.spawns, [[process.execPath,
      ['effect-run.mjs', ...args], {cwd: '/original', env}]]);
    assert.equal(observed.spawns[0][2].env, env);
    assert.equal(observed.milliseconds, 120000);
    assert.deepEqual(observed.starts, ['packed child start ' + JSON.stringify({
      script: 'effect-run.mjs', source: 'infer-graph-node', protocol: 'local', phase: 'rce-submit'})]);
    child.stdout.emit('data', 'held\n');
    child.emit('close', expectedExit, null);
    assert.equal(await result, 'held\n');
    assert.deepEqual(observed.cleared, [timer]);
    assert.deepEqual(observed.kills, []);
    assert.equal(observed.spawns.length, 1);
  }
});

test('packed child diagnostics distinguish original exit or signal without claiming timer expiry', async () => {
  for (const [code, signal] of [[7, null], [null, 'SIGTERM']]) {
    const {child, observed, ports, timer} = packedChildPorts();
    const result = runPackedCompositionChild({script: 'effect-run.mjs', cwd: '/original',
      env: {}, args: ['private-phase', 'private-argument'],
      source: 'private-source', protocol: 'private-protocol'}, ports);
    child.stdout.emit('data', 'original stdout');
    child.stderr.emit('data', 'original stderr');
    child.emit('close', code, signal);
    await assert.rejects(result, error => {
      assert.ok(error.message.startsWith('effect-run.mjs failed:\noriginal stdout\noriginal stderr\n'));
      const detail = JSON.parse(error.message.split('packed child close ')[1]);
      assert.deepEqual(detail, {script: 'effect-run.mjs', source: 'unclassified',
        protocol: 'unclassified', phase: 'unclassified', code, signal,
        timerFired: false, killReturned: null});
      return true;
    });
    assert.ok(!observed.starts[0].includes('private-'));
    assert.deepEqual(observed.cleared, [timer]);
    assert.deepEqual(observed.kills, []);
    assert.equal(observed.spawns.length, 1);
  }
});

test('packed child diagnostics record timer and kill result but still await original close', async () => {
  for (const killResult of [true, false]) {
    const {child, observed, ports, timer} = packedChildPorts();
    observed.killResult = killResult;
    const result = runPackedCompositionChild({script: 'effect-run.mjs', cwd: '/original',
      env: {}, args: ['rce-resume'], source: 'infer-graph-edge', protocol: 'https'}, ports);
    let settled = false;
    result.then(() => { settled = true; }, () => { settled = true; });
    observed.fire();
    await Promise.resolve();
    assert.equal(settled, false);
    assert.deepEqual(observed.kills, ['SIGKILL']);
    assert.deepEqual(observed.cleared, []);
    child.emit('close', null, 'SIGKILL');
    await assert.rejects(result, error => {
      const detail = JSON.parse(error.message.split('packed child close ')[1]);
      assert.equal(detail.code, null);
      assert.equal(detail.signal, 'SIGKILL');
      assert.equal(detail.timerFired, true);
      assert.equal(detail.killReturned, killResult);
      return true;
    });
    assert.deepEqual(observed.cleared, [timer]);
    assert.equal(observed.spawns.length, 1);
  }
});

test('packed child diagnostics preserve original spawn error and close timer cleanup', async () => {
  const {child, observed, ports, timer} = packedChildPorts();
  const result = runPackedCompositionChild({script: 'read.mjs', cwd: '/original', env: {}}, ports);
  const original = new Error('original spawn refusal');
  child.emit('error', original);
  await assert.rejects(result, error => error === original);
  child.emit('close', -2, null);
  assert.deepEqual(observed.cleared, [timer]);
  assert.deepEqual(observed.kills, []);
  assert.equal(observed.spawns.length, 1);
});
