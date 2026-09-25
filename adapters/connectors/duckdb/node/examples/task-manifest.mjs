import {Worker} from 'node:worker_threads';
import {checked} from '../runtime-result.mjs';
import {snapshotDataProfile} from './data-profile.mjs';

// The controller's independent manifest links only the control-side checker
// projection, not the runnable application with its connectors and compute.
const root = new URL('../../../../../', import.meta.url);
const manifestUrl = new URL(
  '_build/js/release/build/physical_task_manifest_example/physical_task_manifest_example.js', root);

export async function prepareExampleTaskManifest({programText, environmentText,
  environmentCid, parameterText, dataProfile}) {
  const data = snapshotDataProfile(dataProfile);
  const app = await import(manifestUrl);
  const args = [programText, environmentText, environmentCid, parameterText];
  return checked(data ? app.applicationTaskManifest(...args, data)
    : app.applicationTaskManifestDefault(...args));
}

// Derivation is synchronous checker work. A thread keeps the controller's event
// loop free to start and drive the child while the manifest is derived. Only
// the plain task identities cross back; the caller still validates them.
export function prepareExampleTaskManifestInThread(input, signal) {
  const {programText, environmentText, environmentCid, parameterText, dataProfile} = input;
  const payload = {programText, environmentText, environmentCid, parameterText,
    dataProfile: snapshotDataProfile(dataProfile)};
  return new Promise((resolve, reject) => {
    signal?.throwIfAborted();
    const worker = new Worker(new URL('./task-manifest-thread.mjs', import.meta.url),
      {workerData: payload});
    let settled = false;
    const finish = (settle, value) => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener('abort', abort);
      void worker.terminate();
      settle(value);
    };
    const abort = () => finish(reject, signal.reason);
    signal?.addEventListener('abort', abort, {once: true});
    worker.once('message', message => message?.ok === true
      ? finish(resolve, message.tasks)
      : finish(reject, new Error('ControllerTaskManifestFailed', {cause: message?.error})));
    worker.once('error', error => finish(reject, error));
    worker.once('exit', code => finish(reject, new Error(`ControllerTaskManifestExited:${code}`)));
  });
}
