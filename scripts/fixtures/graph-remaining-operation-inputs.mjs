import {graphGraftSourceSuccesses, graphGraftSourceRefusals,
  graphGraftSourceExecutionFailures} from './graph-graft-source-input.mjs';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './graph-reach-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './graph-shortest-source-input.mjs';
import {graphMeanSourceOracles, graphMeanSourceRefusals}
  from './graph-mean-source-input.mjs';

// Select existing authored oracles without changing them or registering a
// second copy in the normal corpus. One installation exercises all four
// families before its existing fresh-process retained Result reader.
export const graphRemainingOperationInputs = {
  successes: [...graphGraftSourceSuccesses, ...graphReachSourceSuccesses,
    ...graphShortestSourceSuccesses, ...graphMeanSourceOracles],
  refusals: [...graphGraftSourceRefusals, ...graphReachSourceRefusals,
    ...graphShortestSourceRefusals, ...graphMeanSourceRefusals],
  executionFailures: graphGraftSourceExecutionFailures,
};
