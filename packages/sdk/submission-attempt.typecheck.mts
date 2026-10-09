import {getSubmissionAttempt, getSubmissionOutcome, type Client, type SubmissionAttempt} from './index.js';

declare const client: Client;
declare const received: unknown;
client.start({}, {attemptId: 'fresh-invocation'});
client.startSource('SELECT 1 AS n', {format: 'aql-text', attemptId: 'fresh-text-invocation'});
client.aql('SELECT 1 AS n', undefined, {attemptId: 'fresh-query-invocation'});
const attempt: SubmissionAttempt | undefined = getSubmissionAttempt(received);
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
