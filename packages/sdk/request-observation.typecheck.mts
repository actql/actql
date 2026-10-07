import {explainRequestLookup, explainSubmission, formatRequestLookup,
  type RequestLookup, type RequestLookupExplanation} from '@actql/sdk';
declare const lookup: RequestLookup;
const explanation: RequestLookupExplanation | undefined = explainRequestLookup(lookup);
if (explanation) {
  // @ts-expect-error An observation grants no execution permission.
  const accepted: boolean = explanation.accepted;
  // @ts-expect-error Original lookup references are immutable.
  explanation.next.operation = 'submit';
  if (explanation.observation === 'request_held') {
    const state: 'waiting_checkpoint' | 'resuming' | 'ended' = explanation.preparationState;
    const durability: 'durable' = explanation.durability;
    void [state, durability];
    // @ts-expect-error Held preparation has no Run status fact.
    const status: string = explanation.runStatus;
  }
  if (explanation.observation === 'run_reference_received') {
    const operation: 'status' = explanation.next.operation;
    const definition: string = explanation.next.ref.runDefinitionCid;
    void [operation, definition];
  }
  if (explanation.observation === 'lookup_unresolved') {
    // @ts-expect-error Absence supplies no preparation facts.
    const state: string = explanation.preparationState;
  }
}
const submission = explainSubmission(lookup);
if (submission?.observation === 'request_held') {
  const preparation: string = submission.prepareAttemptId;
  void preparation;
}
if (submission?.observation === 'not_accepted' || submission?.observation === 'preparation_failed') {
  const classification: 'invalid_input' | 'requirements' | 'implementation_limit' |
    'authorization' | 'operation_failed' = submission.problem.classification;
  const operation: 'lookupSubmission' = submission.next.operation;
  const nonce: string = submission.next.submissionRef.nonce;
  void [classification, operation, nonce];
  // @ts-expect-error Retained terminal facts cannot be rewritten by presentation.
  submission.problem.classification = 'operation_failed';
  // @ts-expect-error A preparation outcome supplies no Run reference.
  const run: string = submission.next.ref.runDefinitionCid;
}
if (submission?.observation === 'history_unresolvable' || submission?.observation === 'not_sent' ||
    submission?.observation === 'lookup_unavailable' || submission?.observation === 'lookup_uninterpretable') {
  const operation: 'lookupSubmission' = submission.next.operation;
  void operation;
  // @ts-expect-error These observations establish no Owner rejection problem.
  const problem: string = submission.problem.classification;
}
const text: string | undefined = formatRequestLookup(lookup, {format: 'json'});
void text;

import {explainRequestCancellation, formatRequestCancellation,
  type RequestCancellationExplanation} from '@actql/sdk';
const cancellation: RequestCancellationExplanation | undefined = explainRequestCancellation(lookup);
if (cancellation) {
  // @ts-expect-error No physical-stop certificate is exposed.
  const stopped: boolean = cancellation.stopped;
  // @ts-expect-error The original request reference is immutable.
  cancellation.requestId = 'another';
  if (cancellation.observation === 'outcome_unknown') {
    const problem: 'exchange_failed' | 'response_uninterpretable' = cancellation.problem;
    const operation: 'lookupRequest' | 'lookupSubmission' = cancellation.next.operation;
    void [problem, operation];
    if (cancellation.next.operation === 'lookupSubmission') {
      const nonce: string = cancellation.next.submissionRef.nonce;
      void nonce;
    } else {
      const requestId: string = cancellation.next.requestId;
      void requestId;
    }
    // @ts-expect-error A failed observation has no Run revision.
    const revision: number = cancellation.revision;
  }
  // @ts-expect-error Existing request IDs are not cancellation-operation identities.
  const cancelRef: string = cancellation.cancelRef;
}
const cancellationText: string | undefined = formatRequestCancellation(lookup, {format: 'html', locale: 'ja'});
void cancellationText;
