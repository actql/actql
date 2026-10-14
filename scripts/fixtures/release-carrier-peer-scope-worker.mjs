// Use the existing transport custody before loading any installed product.
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
const worker = ownTransportWorker();
try { await import('./packed-carrier-peer-scope.mjs'); }
finally { worker.release(); }
