import {explainCancellation} from '@actql/sdk';

declare const result: unknown;
const explanation = explainCancellation(result);
if (explanation) {
  const operation: 'status' = explanation.next.operation;
  const runDefinitionCid: string = explanation.next.ref.runDefinitionCid;
  void operation; void runDefinitionCid;
  // @ts-expect-error Observation advice is immutable and cannot become a write.
  explanation.next.operation = 'cancel';
  // @ts-expect-error A Run reference is not a cancellation-operation identity.
  explanation.next.cancelRef;
  // @ts-expect-error The explanation is not a physical-stop or release receipt.
  explanation.physical_stop;
  // @ts-expect-error This operation exposes no original submit lookup identity.
  explanation.next.requestId;
}
if (explanation?.observation === 'outcome_unknown') {
  // @ts-expect-error An unestablished outcome has no fabricated recorded revision.
  explanation.revision;
} else if (explanation) {
  const revision: number = explanation.revision;
  void revision;
}
