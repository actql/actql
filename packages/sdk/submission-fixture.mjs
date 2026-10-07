// Independent Host wire fixtures. They echo a request binding, but neither
// derive expected Program results nor simulate acceptance or execution owners.
export const submissionEpoch = Object.freeze({
  version: 'actql-submission-epoch/0.1',
  authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  epochNonce: 'b'.repeat(64), authenticator: 'c'.repeat(64),
  notBefore: 1800000000000, expiresAt: 1800000001000,
});
export const originalSubmission = nonce => ({epoch: submissionEpoch, nonce});
export const readySubmission = (request, admission) => ({kind: 'ready',
  submissionRef: request.submissionRef, intentCid: request.intentCid, admission});
export const heldSubmission = (request, held) => ({kind: 'held',
  submissionRef: request.submissionRef, intentCid: request.intentCid, held});
