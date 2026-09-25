import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter, once} from 'node:events';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {Worker} from 'node:worker_threads';
import {prepareExampleTaskManifestInThread, snapshotManagedExampleInput,
  snapshotTaskManifestInput} from '../examples/task-manifest.mjs';

const documents = Object.freeze({
  programText: '{}', environmentText: '{}', environmentCid: 'sha256:0', parameterText: '{}',
});

function inline(source, spawned) {
  return payload => {
    const worker = new Worker(source, {eval: true, workerData: payload});
    spawned.push(worker);
    return worker;
  };
}

// A Worker's threadId becomes -1 once the thread has fully exited.
const stopped = worker => worker.threadId === -1;

test('manifest documents are admitted by type and the existing byte limit before a thread', () => {
  assert.equal(snapshotTaskManifestInput({...documents,
    programText: 'x'.repeat(1000000)}).programText.length, 1000000);
  for (const programText of ['x'.repeat(1000001), 'é'.repeat(500001), 1, undefined]) {
    let spawned = 0;
    assert.throws(() => prepareExampleTaskManifestInThread({...documents, programText},
      undefined, {spawn: () => { spawned++; }}), {message: 'InvalidTaskManifestDocument'});
    assert.equal(spawned, 0, 'no thread is created for refused input');
  }
  assert.throws(() => snapshotTaskManifestInput(null), {message: 'InvalidTaskManifestInput'});
});

test('a completed manifest returns only after its thread has exited', async () => {
  const spawned = [];
  const tasks = await prepareExampleTaskManifestInThread(documents, undefined, {
    spawn: inline(`require('node:worker_threads').parentPort.postMessage(
      {ok: true, tasks: [{task: 1}]}); setInterval(() => {}, 1000);`, spawned)});
  assert.deepEqual(tasks, [{task: 1}]);
  assert(stopped(spawned[0]));
});

test('a checker failure is reported after its real thread has exited', async () => {
  const root = new URL('../../../../../', import.meta.url);
  await promisify(execFile)('moon', ['build', '--target', 'js', '--release',
    'src/physical_task_manifest_example'], {cwd: fileURLToPath(root)});
  const spawned = [];
  await assert.rejects(prepareExampleTaskManifestInThread(documents, undefined, {
    spawn: payload => {
      const worker = new Worker(new URL('../examples/task-manifest-thread.mjs', import.meta.url),
        {workerData: payload});
      spawned.push(worker);
      return worker;
    }}), {message: 'ControllerTaskManifestFailed'});
  assert(stopped(spawned[0]));
});

test('cancellation during derivation keeps its reason and stops the thread', async () => {
  const spawned = [];
  const controller = new AbortController();
  const pending = prepareExampleTaskManifestInThread(documents, controller.signal, {
    spawn: inline('setInterval(() => {}, 1000);', spawned)});
  await once(spawned[0], 'online');
  const reason = new Error('stop requested');
  controller.abort(reason);
  await assert.rejects(pending, error => error === reason);
  assert(stopped(spawned[0]));
  assert.throws(() => prepareExampleTaskManifestInThread(documents, controller.signal, {
    spawn: () => assert.fail('no thread after cancellation')}), error => error === reason);
});

test('a thread that exits without a response is a failure, not a manifest', async () => {
  const spawned = [];
  await assert.rejects(prepareExampleTaskManifestInThread(documents, undefined, {
    spawn: inline('process.exit(3);', spawned)}), {message: 'ControllerTaskManifestExited:3'});
  assert(stopped(spawned[0]));
});

test('racing outcomes settle and stop once, and a stop failure is not dropped', async () => {
  let terminations = 0;
  const fake = Object.assign(new EventEmitter(), {
    terminate: async () => { terminations++; throw new Error('stop failed'); },
  });
  const pending = prepareExampleTaskManifestInThread(documents, undefined, {spawn: () => fake});
  const original = new Error('checker failed');
  fake.emit('message', {ok: false, error: original});
  fake.emit('error', new Error('late error'));
  fake.emit('exit', 1);
  await assert.rejects(pending, error => error instanceof AggregateError &&
    error.message === 'ControllerTaskManifestThreadStopFailed' &&
    error.errors[0].message === 'ControllerTaskManifestFailed' &&
    error.errors[0].cause === original && error.errors[1].message === 'stop failed');
  assert.equal(terminations, 1);
});

function fakeThread(terminate) {
  const fake = new EventEmitter();
  fake.terminations = 0;
  fake.terminate = async () => { fake.terminations++; return terminate(fake); };
  return fake;
}

test('a failed stop without exit keeps thread ownership in a pending cleanup handle', async () => {
  for (const failure of [new Error('stop failed'), undefined]) {
    let failing = true;
    const fake = fakeThread(thread => {
      if (failing) return Promise.reject(failure);
      queueMicrotask(() => thread.emit('exit', 1));
    });
    const pending = prepareExampleTaskManifestInThread(documents, undefined, {spawn: () => fake});
    // Even a successful response is not returned while the thread is unstopped.
    fake.emit('message', {ok: true, tasks: [{task: 1}]});
    const error = await pending.then(() => assert.fail('resolved with an unstopped thread'),
      value => value);
    assert(error instanceof AggregateError);
    assert.equal(error.message, 'ControllerTaskManifestThreadStopFailed');
    assert.equal(error.errors.length, 1);
    assert.equal(error.errors[0], failure);
    assert.equal(error.cleanupHandle.status().pending, true);
    failing = false;
    assert.deepEqual(await error.cleanupHandle.retry(), {pending: false});
    assert.equal(error.cleanupHandle.status().pending, false);
    assert.equal(fake.terminations, 2);
  }
});

test('a late exit after a failed stop releases the pending cleanup without another stop', async () => {
  const fake = fakeThread(() => Promise.reject(new Error('stop failed')));
  const pending = prepareExampleTaskManifestInThread(documents, undefined, {spawn: () => fake});
  const original = new Error('checker failed');
  fake.emit('message', {ok: false, error: original});
  const error = await pending.then(() => assert.fail('resolved'), value => value);
  assert.equal(error.errors[0].cause, original);
  assert.equal(error.cleanupHandle.status().pending, true);
  fake.emit('exit', 0);
  assert.equal(error.cleanupHandle.status().pending, false);
  assert.deepEqual(await error.cleanupHandle.retry(), {pending: false});
  assert.equal(fake.terminations, 1);
});

test('managed input reads each supplied document once and gives parent and child the same text', () => {
  let reads = 0;
  const supplied = {environmentText: '{}', environmentCid: 'sha256:0', parameterText: '{}',
    nativeMilliseconds: '1', retainedOutput: {parentDirectory: '/tmp'}};
  Object.defineProperty(supplied, 'programText', {enumerable: true,
    get: () => (++reads === 1 ? '{}' : 'x'.repeat(1000001))});
  const {manifestInput, input} = snapshotManagedExampleInput(supplied);
  assert.equal(reads, 1);
  assert.equal(manifestInput.programText, '{}');
  assert.equal(input.programText, manifestInput.programText);
  assert.equal(input.nativeMilliseconds, '1');
  assert.deepEqual(input.retainedOutput, {parentDirectory: '/tmp'});
  assert.notEqual(input.retainedOutput, supplied.retainedOutput);
  assert.equal('dataProfile' in input, false);
  let oversizedReads = 0;
  const oversized = {...supplied};
  Object.defineProperty(oversized, 'programText', {enumerable: true,
    get: () => { oversizedReads++; return 'x'.repeat(1000001); }});
  assert.throws(() => snapshotManagedExampleInput(oversized),
    {message: 'InvalidTaskManifestDocument'});
  assert.equal(oversizedReads, 1);
});
