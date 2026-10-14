import {ExplorerReadError} from './read-model.mjs';
import {layoutInput, layoutPositions, flowLayoutDeadlineMs} from './flow-layout-engine.mjs';
export {flowNodeWidth, flowNodeHeight, flowLayoutDeadlineMs} from './flow-layout-engine.mjs';

let nextRequest = 0;
const browserWorker = () => new Worker(new URL('./flow-layout-worker.mjs', import.meta.url), {type: 'module'});

/** One disposable Worker per layout. Leaving a scope/Plan or the Flow view
 * aborts this request and terminates its Worker; old replies never publish. */
export function requestFlowLayout(flow, {signal, createWorker = browserWorker} = {}) {
  const input = layoutInput(flow);
  if (signal?.aborted) return Promise.reject(new ExplorerReadError('ExplorerLayoutAborted'));
  if (input.nodes.length === 0) return Promise.resolve([]);
  if (nextRequest >= Number.MAX_SAFE_INTEGER) refuse();
  const requestId = ++nextRequest;
  return new Promise((resolve, reject) => {
    let worker, timer, settled = false;
    const finish = (error, positions) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (worker) { worker.onmessage = null; worker.onerror = null; worker.terminate(); }
      if (error) reject(error); else resolve(positions);
    };
    const abort = () => finish(new ExplorerReadError('ExplorerLayoutAborted'));
    signal?.addEventListener('abort', abort, {once: true});
    try {
      worker = createWorker();
      worker.onmessage = event => {
        if (event.data?.requestId !== requestId) return;
        if (event.data?.kind !== 'layout') {
          finish(new ExplorerReadError('ExplorerLayoutUnavailable')); return;
        }
        try {
          const positions = event.data.positions;
          // The same complete original node set is required on both sides.
          const checked = layoutPositions(input, {children: Array.isArray(positions)
            ? positions.map(point => ({...point, id: `node:${point.id}`})) : undefined});
          finish(undefined, checked);
        } catch { finish(new ExplorerReadError('ExplorerInvalidLayout')); }
      };
      worker.onerror = () => finish(new ExplorerReadError('ExplorerLayoutUnavailable'));
      timer = setTimeout(() => finish(new ExplorerReadError('ExplorerLayoutUnavailable')), flowLayoutDeadlineMs);
      if (signal?.aborted) { abort(); return; }
      worker.postMessage({requestId, input});
    } catch { finish(new ExplorerReadError('ExplorerLayoutUnavailable')); }
  });
}
