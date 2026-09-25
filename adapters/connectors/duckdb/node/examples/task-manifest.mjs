import {Worker} from 'node:worker_threads';
import {checked} from '../runtime-result.mjs';
import {snapshotDataProfile} from './data-profile.mjs';

// The controller's independent manifest links only the control-side checker
// projection, not the runnable application with its connectors and compute.
const root = new URL('../../../../../', import.meta.url);
const manifestUrl = new URL(
  '_build/js/release/build/physical_task_manifest_example/physical_task_manifest_example.js', root);
const threadUrl = new URL('./task-manifest-thread.mjs', import.meta.url);

// The example's existing per-document acceptance limit (file reads and the
// MoonBit source parser use the same bound). Not a new policy value.
const maxDocumentBytes = 1000000;

function boundedDocument(value) {
  // UTF-8 never has fewer bytes than UTF-16 code units, so the length check
  // rejects oversized text before any byte scan or copy.
  if (typeof value !== 'string' || value.length > maxDocumentBytes ||
      Buffer.byteLength(value, 'utf8') > maxDocumentBytes) {
    throw new TypeError('InvalidTaskManifestDocument');
  }
  return value;
}

// Type and size admission for the manifest documents. Callers run this before
// cloning the supplied input or starting a thread; the returned strings are the
// only document values used afterwards.
export function snapshotTaskManifestInput(input) {
  if (input === null || typeof input !== 'object') throw new TypeError('InvalidTaskManifestInput');
  const {programText, environmentText, environmentCid, parameterText, dataProfile} = input;
  return Object.freeze({
    programText: boundedDocument(programText),
    environmentText: boundedDocument(environmentText),
    environmentCid: boundedDocument(environmentCid),
    parameterText: boundedDocument(parameterText),
    dataProfile: snapshotDataProfile(dataProfile),
  });
}

export async function prepareExampleTaskManifest(input) {
  const {programText, environmentText, environmentCid, parameterText, dataProfile} =
    snapshotTaskManifestInput(input);
  const app = await import(manifestUrl);
  const args = [programText, environmentText, environmentCid, parameterText];
  return checked(dataProfile ? app.applicationTaskManifest(...args, dataProfile)
    : app.applicationTaskManifestDefault(...args));
}

const manifestKeys = Object.freeze(
  ['programText', 'environmentText', 'environmentCid', 'parameterText', 'dataProfile']);

const spawnThread = payload => new Worker(threadUrl, {workerData: payload});

// Every supplied property is read exactly once. The manifest documents are
// admitted before anything is cloned, and the same admitted strings are used by
// both the controller's manifest and the child's input.
export function snapshotManagedExampleInput(supplied) {
  if (supplied === null || typeof supplied !== 'object') throw new TypeError('InvalidTaskManifestInput');
  // One explicit read per own enumerable property (the properties a structured
  // clone copies). Object rest destructuring can re-read excluded getters.
  const values = {};
  for (const key of Object.keys(supplied)) values[key] = supplied[key];
  const manifestInput = snapshotTaskManifestInput(values);
  for (const key of manifestKeys) delete values[key];
  const input = structuredClone(values);
  for (const key of ['programText', 'environmentText', 'environmentCid', 'parameterText']) {
    input[key] = manifestInput[key];
  }
  if (manifestInput.dataProfile !== undefined) input.dataProfile = manifestInput.dataProfile;
  return {manifestInput, input};
}

// Derivation is synchronous checker work. A short-lived thread keeps the
// controller's event loop free to start and drive the child meanwhile. The
// returned promise settles exactly once, with the first outcome among message,
// error, exit and abort, after a stop request. When the thread is confirmed
// stopped the outcome is returned as is. When the stop request fails, the
// outcome is rejected together with that failure and a cleanup handle that
// keeps ownership of the thread until its exit is observed.
export function prepareExampleTaskManifestInThread(input, signal, {spawn = spawnThread} = {}) {
  const payload = snapshotTaskManifestInput(input);
  signal?.throwIfAborted();
  const worker = spawn(payload);
  let exitObserved = false;
  const exited = new Promise(done => worker.once('exit', () => {
    exitObserved = true;
    done();
  }));
  const cleanupHandle = Object.freeze({
    status: () => ({pending: !exitObserved}),
    async retry() {
      if (!exitObserved) {
        await worker.terminate();
        await exited;
      }
      return {pending: !exitObserved};
    },
  });
  return new Promise((resolve, reject) => {
    let settling = false;
    const abort = () => finish({error: signal.reason});
    const finish = async outcome => {
      if (settling) return;
      settling = true;
      signal?.removeEventListener('abort', abort);
      let stopFailed = false;
      let stopFailure;
      try {
        await worker.terminate();
      } catch (error) {
        stopFailed = true;
        stopFailure = error;
      }
      if (stopFailed) {
        reject(Object.assign(new AggregateError(
          'error' in outcome ? [outcome.error, stopFailure] : [stopFailure],
          'ControllerTaskManifestThreadStopFailed'), {cleanupHandle}));
        return;
      }
      // A fulfilled stop request is followed by the thread's exit event.
      await exited;
      if ('error' in outcome) reject(outcome.error);
      else resolve(outcome.value);
    };
    signal?.addEventListener('abort', abort, {once: true});
    worker.once('message', message => finish(message?.ok === true
      ? {value: message.tasks}
      : {error: new Error('ControllerTaskManifestFailed', {cause: message?.error})}));
    worker.once('error', error => finish({error}));
    worker.once('exit', code => finish({error: new Error(`ControllerTaskManifestExited:${code}`)}));
  });
}
