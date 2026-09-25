import {parentPort, workerData} from 'node:worker_threads';
import {prepareExampleTaskManifest} from './task-manifest.mjs';

try {
  parentPort.postMessage({ok: true, tasks: await prepareExampleTaskManifest(workerData)});
} catch (error) {
  parentPort.postMessage({ok: false, error});
}
