// The upstream module is unchecked at this static boundary. Its only consumed
// operation returns unknown DATA, accepted solely by layoutPositions below.
type LayoutConstructor = new (options:{algorithms:string[];workerFactory:()=>Worker})=>{
  layout(input:unknown):Promise<unknown>;
};
type LayoutInput = Parameters<typeof layoutInput>[0];
type Positions = ReturnType<typeof layoutPositions>;
import ELK from 'elkjs/lib/elk-api.js';
import {ExplorerReadError} from './presentation-limits.mjs';
import {layoutInput, elkGraph, layoutPositions, flowLayoutDeadlineMs} from './flow-layout-engine.mjs';
export {layoutInput, flowNodeWidth, flowNodeHeight, flowLayoutDeadlineMs} from './flow-layout-engine.mjs';

const browserWorker = () => new Worker(new URL('./flow-layout-worker.mjs', import.meta.url), {type: 'module'});

/** One disposable Worker per layout. Leaving a scope/Plan or the Flow view
 * aborts this request and terminates its Worker; old replies never publish. */
export function requestFlowLayout(flow:LayoutInput, {signal, createWorker = browserWorker}:{signal?:AbortSignal;createWorker?:()=>Worker} = {}):Promise<Positions> {
  const input = layoutInput(flow);
  if (signal?.aborted) return Promise.reject(new ExplorerReadError('ExplorerLayoutAborted'));
  if (input.nodes.length === 0) return Promise.resolve([]);
  return new Promise<Positions>((resolve, reject) => {
    let worker:Worker|undefined, timer:ReturnType<typeof setTimeout>|undefined, settled = false;
    const finish = (error?:Error, positions?:Positions) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (worker) { worker.onmessage = null; worker.onerror = null; worker.terminate(); }
      if (error) reject(error); else resolve(positions!);
    };
    const abort = () => finish(new ExplorerReadError('ExplorerLayoutAborted'));
    signal?.addEventListener('abort', abort, {once: true});
    try {
      worker = createWorker();
      // A factory may deliver the scope abort before returning its Worker.
      if (settled) { worker.terminate(); return; }
      // Use the upstream API/Worker pair. elk.bundled's in-process fake Worker
      // is intended for Window/Node, not for construction inside a Worker.
      const elk = new (ELK as LayoutConstructor)({algorithms: ['layered'], workerFactory: () => worker!});
      worker.onerror = () => finish(new ExplorerReadError('ExplorerLayoutUnavailable'));
      timer = setTimeout(() => finish(new ExplorerReadError('ExplorerLayoutUnavailable')), flowLayoutDeadlineMs);
      if (signal?.aborted) { abort(); return; }
      elk.layout(elkGraph(input)).then(result => {
        if (settled) return;
        try { finish(undefined, layoutPositions(input, result)); }
        catch { finish(new ExplorerReadError('ExplorerInvalidLayout')); }
      }, () => finish(new ExplorerReadError('ExplorerLayoutUnavailable')));
    } catch { finish(new ExplorerReadError('ExplorerLayoutUnavailable')); }
  });
}
