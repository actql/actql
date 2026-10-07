import {explainSubmission} from '@actql/sdk';

declare const result: unknown;
const explanation = explainSubmission(result);
if (explanation?.observation === 'run_reference_received') {
  const operation: 'status' = explanation.next.operation;
  const runDefinitionCid: string = explanation.next.ref.runDefinitionCid;
  void operation; void runDefinitionCid;
  // @ts-expect-error A Run observation does not manufacture a submission lookup ID.
  explanation.next.requestId;
} else if (explanation) {
  const operation: 'lookupRequest' | 'lookupSubmission' = explanation.next.operation;
  if (explanation.next.operation === 'lookupRequest') {
    const requestId: string = explanation.next.requestId;
    void requestId;
  } else {
    const nonce: string = explanation.next.submissionRef.nonce;
    const authenticator: string = explanation.next.submissionRef.epoch.authenticator;
    void nonce; void authenticator;
    // @ts-expect-error The original epoch is immutable.
    explanation.next.submissionRef.epoch.notBefore = 0;
  }
  const scopeRef: string = explanation.next.lookupContext.scopeRef;
  void operation; void scopeRef;
  // @ts-expect-error An uncertain submission has no fabricated Run reference.
  explanation.next.ref;
  // @ts-expect-error The lookup target cannot be replaced with a newer request.
  explanation.next.requestId = 'edited-request';
}
// @ts-expect-error A presentation result does not expose supplied secret values.
explanation?.parameters;
