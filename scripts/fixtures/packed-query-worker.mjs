// Install parent-death custody before any product or authored fixture import.
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
const worker = ownTransportWorker();
try {
  if (process.argv[2] === 'restart') await import('./string-values-restart.mjs');
  else if (process.argv[2] === undefined) await import('./acceptance.mjs');
  else throw new Error('UnknownPackedQueryWorkerEntry');
} finally {
  worker.release();
}
