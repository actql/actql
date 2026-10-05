// Sequence the existing inference owner and authorization gate. Waiting exits
// the driver; it never polls a zero-work owner or acquires completed output.
import {authorizationDispatchFacts, ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';

export async function driveNodeInferOperation(operation, {dispatch, signal} = {}) {
  signal?.throwIfAborted();
  const result = await operation.run();
  if (result?.kind !== 'waiting') return result;
  const prepared = operation.preparedCallSet();
  if (prepared === undefined || prepared !== result.callSet ||
      typeof dispatch?.authorize !== 'function' ||
      typeof dispatch?.resume !== 'function') {
    throw new Error('InstalledInferModelApprovalNotConnected');
  }
  // The installing Host persists the exact retained input/call originals and
  // uses its existing authorization gate. This call receives the opaque owner
  // and receipt, not a detached reconstruction of the call inventory.
  const decision = await dispatch.authorize({operation, prepared, signal});
  signal?.throwIfAborted();
  if (decision?.boundary !== 'activation' ||
      decision.tuple?.operation !== 'infer' ||
      decision.tuple.connection !== prepared.binding.providerId ||
      decision.tuple.resource !== prepared.binding.taskCid) {
    throw new Error('InstalledInferForeignDispatchDecision');
  }
  if (decision?.action === 'waiting') {
    if (typeof decision.checkpoint?.checkpointCid !== 'string') {
      throw new Error('InstalledInferCheckpointNotRetained');
    }
    // client-dispatch-owner checks this against the committed journal again
    // before accepting the wait and settling the physical preparation owner.
    return Object.freeze({status: 'waiting_checkpoint',
      checkpointCid: decision.checkpoint.checkpointCid});
  }
  if (decision?.action !== 'dispatch') {
    throw new ExecutionAuthorizationError(decision);
  }
  const facts = authorizationDispatchFacts(decision);
  if (facts === undefined || facts.principal !== decision.tuple.principal) {
    throw new Error('InstalledInferForeignDispatchDecision');
  }
  // Resume binds current dispatch authority and the journal-read grant through
  // A's owner. Neither the decision nor its serialized copy is a send permit.
  await dispatch.resume({operation, prepared, decision, signal});
  signal?.throwIfAborted();
  if (operation.preparedCallSet() !== undefined) {
    throw new Error('InstalledInferModelResumeIncomplete');
  }
  const resumed = await operation.run();
  if (resumed?.kind === 'waiting') {
    throw new Error('InstalledInferModelResumeIncomplete');
  }
  return resumed;
}
