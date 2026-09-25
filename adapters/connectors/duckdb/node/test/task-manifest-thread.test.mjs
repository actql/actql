import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter, once} from 'node:events';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {Worker} from 'node:worker_threads';
import {prepareExampleTaskManifestInThread, snapshotTaskManifestInput} from
  '../examples/task-manifest.mjs';

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
