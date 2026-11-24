// Install parent-death custody before any product or authored fixture import.
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
const worker = ownTransportWorker();
try {
  // These runtime entries are prepared beside the worker in the external fixture.
  if (process.argv[2] === 'restart') await import('./string-values-restart.mjs' as string);
  else if (process.argv[2] === undefined && process.env.ACTQL_TEST_VECTOR_SCALAR_ONLY === '1')
    await import('./packed-vector-scalar-source.mjs' as string);
  else if (process.argv[2] === undefined) await import('./acceptance.mjs' as string);
  else throw new Error('UnknownPackedQueryWorkerEntry');
} finally {
  worker.release();
}
