import {prepareClientHostRequest, validNamedSubmissionAttempt, validSubmissionName,
  type WireConnection, type WireSubmissionRef, type WireOperationAttemptRef,
  type WireNamedSubmissionAttempt, type WireSubmissionName} from './index.mjs';

declare const value: unknown;
declare const name: unknown;
declare const connection: WireConnection;
declare const candidate: WireSubmissionRef;
declare const attempt: WireOperationAttemptRef;
if (validSubmissionName(name)) {
  const originalName: WireSubmissionName = name;
  const packet = prepareClientHostRequest('submit-named-intent', {requestName: originalName});
  void packet;
  if (validNamedSubmissionAttempt(value, connection, originalName, candidate, 'sha256:original', attempt)) {
    const retained: WireNamedSubmissionAttempt = value;
    if (retained.kind === 'observed') {
      const original: WireSubmissionRef = retained.outcome.submissionRef;
      void original;
      // @ts-expect-error Observing the original does not issue an unused-attempt guarantee.
      retained.guarantee;
      if (retained.outcome.kind === 'unresolvable') {
        // @ts-expect-error Missing original custody is not Run admission.
        retained.outcome.admission;
      }
    } else if (retained.kind === 'refused') {
      const proof: 'attempt_uncommitted_unconsumed' = retained.guarantee;
      void proof;
      // @ts-expect-error A refusal does not fabricate an original outcome.
      retained.outcome;
    } else {
      const reason: 'intent' = retained.reason;
      void reason;
      // @ts-expect-error A conflict does not certify no prior execution.
      retained.guarantee;
    }
  }
}
