import {getSubmissionAttempt, getSubmissionOutcome, explainSubmission,
  type Client, type SubmissionAttempt} from './index.js';

declare const client: Client;
declare const received: unknown;
client.start({}, {attemptId: 'fresh-invocation'});
client.startSource('SELECT 1 AS n', {format: 'aql-text', attemptId: 'fresh-text-invocation'});
client.startSource('SELECT 1 AS n', {format: 'sql', requestId: 'same-scoped-original'});
client.sql('SELECT 1 AS n', undefined, {requestId: 'same-query-original'});
client.aql('SELECT 1 AS n', undefined, {attemptId: 'fresh-query-invocation'});
const attempt: SubmissionAttempt | undefined = getSubmissionAttempt(received);
if (attempt?.kind === 'observed') {
  const name: string = attempt.requestName;
  const original: string = attempt.outcome.submissionRef.nonce;
  void [name, original];
  // @ts-expect-error A named observation is not a nonacceptance certificate.
  attempt.guarantee;
}
if (attempt?.kind === 'refused') {
  const guarantee: 'attempt_uncommitted_unconsumed' = attempt.guarantee;
  void guarantee;
  // @ts-expect-error An initial refusal is not a durable original receipt.
  attempt.outcome;
}
if (attempt?.kind === 'recorded' || attempt?.kind === 'already_satisfied') {
  const operation: 'submit' = attempt.attemptRef.operation;
  void operation;
  if (attempt.outcome.kind === 'ready') attempt.outcome.admission.ref.runDefinitionCid;
  // @ts-expect-error Receipt existence is not a nonexecution guarantee.
  attempt.guarantee;
}
const original = getSubmissionOutcome(received);
// @ts-expect-error The durable outcome has no per-invocation identity.
original?.attemptRef;
const explanation = explainSubmission(received);
if (explanation?.observation === 'refused' || explanation?.observation === 'conflict') {
  const operation: 'submit' = explanation.attemptRef.operation;
  const lookup: 'lookupSubmission' = explanation.next.operation;
  const authority: string = explanation.submissionRef.epoch.authorityScopeCid;
  void [operation, lookup, authority];
  // @ts-expect-error Invocation advice is not a durable original receipt.
  explanation.problem;
  // @ts-expect-error Invocation advice cannot become a resubmission.
  explanation.next.operation = 'start';
  if (explanation.observation === 'refused') {
    const guarantee: 'attempt_uncommitted_unconsumed' = explanation.guarantee;
    void guarantee;
  } else {
    // @ts-expect-error A conflict does not certify unconsumed original custody.
    explanation.guarantee;
  }
}
