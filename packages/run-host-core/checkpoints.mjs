// Exact existing Owner calls. Strings cross the portable ABI; this package
// does not manufacture a Checkpoint, confirm a Store write or authorize resume.
export {checkpointAdmit, checkpointWaitingState} from
  './dist/checkpoint_runtime_node.js';
