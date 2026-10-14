import ELK from 'elkjs/lib/elk.bundled.js';
import {elkGraph, layoutPositions} from './flow-layout-engine.mjs';

// One request is placed in this disposable Worker. Its parent enforces the
// deadline and terminates the Worker on completion, failure or scope change.
const elk = new ELK();
self.onmessage = async ({data}) => {
  const requestId = data?.requestId;
  try {
    if (!Number.isSafeInteger(requestId) || requestId < 1) throw new Error();
    const graph = elkGraph(data.input);
    const placed = await elk.layout(graph);
    self.postMessage({requestId, kind: 'layout', positions: layoutPositions(data.input, placed)});
  } catch {
    // Never echo source/graph data or an upstream exception/stack to the UI.
    self.postMessage({requestId, kind: 'unavailable'});
  }
};
