import {explainCancellation, formatCancellation, type Execution, type CancellationReference} from '@actql/sdk';

declare const result: unknown;
declare const execution: Execution;
declare const reference: CancellationReference;
const lookup = await execution.lookupCancellation(reference);
const recovered = explainCancellation(lookup);
const rendered: string | undefined = formatCancellation(lookup, {format: 'json'});
void recovered; void rendered;
const explanation = explainCancellation(result);
if (explanation) {
  // @ts-expect-error Observation advice is immutable and cannot become a write.
  explanation.next.operation = 'cancel';
  // @ts-expect-error The explanation is not a physical-stop or release receipt.
  explanation.physical_stop;
  // @ts-expect-error This operation exposes no original submit lookup identity.
  explanation.next.requestId;
}
if (explanation?.observation === 'outcome_unknown') {
  const operation: 'lookupCancellation' = explanation.next.operation;
  const cancelId: string = explanation.next.cancelRef.cancelId;
  const expectedRevision: number = explanation.next.cancelRef.expectedRevision;
  void operation; void cancelId; void expectedRevision;
  // @ts-expect-error Original operation identity is immutable.
  explanation.next.cancelRef.cancelId = 'replacement';
  // @ts-expect-error An unknown operation cannot be resolved from current Run state alone.
  explanation.next.ref;
  // @ts-expect-error An unestablished outcome has no fabricated recorded revision.
  explanation.revision;
} else if (explanation) {
  const operation: 'status' = explanation.next.operation;
  const runDefinitionCid: string = explanation.next.ref.runDefinitionCid;
  void operation; void runDefinitionCid;
  // @ts-expect-error Recorded acceptance is followed by separate Run observations.
  explanation.next.cancelRef;
  const revision: number = explanation.revision;
  void revision;
}
