// Independent Host wire fixtures. They echo a request binding, but neither
// derive expected Program results nor simulate acceptance or execution owners.
export const submissionEpoch = Object.freeze({
  version: 'actql-submission-epoch/0.1',
  authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  epochNonce: 'b'.repeat(64), authenticator: 'c'.repeat(64),
  notBefore: 1800000000000, expiresAt: 1800000001000,
});
export const originalSubmission = <Nonce,>(nonce: Nonce) => ({epoch: submissionEpoch, nonce});
export const readySubmission = <Admission,>(request: Record<string, unknown>, admission: Admission) => ({kind: 'ready',
  submissionRef: request.submissionRef, intentCid: request.intentCid, admission});
export const heldSubmission = <Held,>(request: Record<string, unknown>, held: Held) => ({kind: 'held',
  submissionRef: request.submissionRef, intentCid: request.intentCid, held});
export const submissionAttempt = <Outcome,>(request: Record<string, unknown>, outcome: Outcome, kind = 'recorded') => ({
  kind, attemptRef: request.attemptRef, outcome});
export const readySubmissionAttempt = <Admission,>(request: Record<string, unknown>, admission: Admission) => submissionAttempt(request, readySubmission(request, admission));
export const heldSubmissionAttempt = <Held,>(request: Record<string, unknown>, held: Held) => submissionAttempt(request, heldSubmission(request, held));
