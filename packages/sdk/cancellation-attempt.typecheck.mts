import type {Execution} from './index.js';

declare const run: Execution;
const outcome = await run.cancel({cancelId: 'original', expectedRevision: 7,
  attemptId: 'this-invocation'});
const operation: 'cancel' = outcome.attemptRef.operation;
const invocation: string = outcome.attemptRef.attemptId;
if (outcome.kind === 'refused') {
  const guarantee: 'attempt_uncommitted_unconsumed' = outcome.guarantee;
  const reason: 'authorization' | 'admission_capacity' = outcome.reason;
  // A refused invocation does not carry an accepted durable cancellation.
  // @ts-expect-error
  outcome.cancellation;
  void [guarantee, reason];
} else if (outcome.kind === 'conflict') {
  const revision: number = outcome.cancelRef.expectedRevision;
  const reason: 'intent' | 'control_revision' = outcome.reason;
  void [revision, reason];
} else {
  const revision: number = outcome.cancellation.revision;
  const runIdentity: string = outcome.cancellation.ref.runDefinitionCid;
  // Cancellation receipt is not a physical-stop or cleanup receipt.
  // @ts-expect-error
  outcome.cancellation.physicalStopConfirmed;
  void [revision, runIdentity];
}
void [operation, invocation];
