// Use the existing transport custody before loading any installed product.
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
const worker = ownTransportWorker();
try { await import('./packed-window-group-source.mjs'); }
finally { worker.release(); }
