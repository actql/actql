// How an installed source's acquisition ended when it could not return a
// capture. The adapter that did the physical work states it; the dispatch
// owner never infers it from an error:
// - `not_started`: confirmed that no provider I/O began.
// - `stopped`: provider I/O began and every transport and resource of this
//   acquisition is confirmed ended and released.
// - `unknown`: the adapter cannot confirm its end. A `recovery` owner
//   ({close, cleanup, cleanupPending}) may take over what remains.
// An error without a stated outcome is `unknown` with no recovery owner.
const outcomes = new Set(['not_started', 'stopped', 'unknown']);

export class AcquisitionOpenError extends Error {
  constructor(cause, outcome, recovery) {
    super(typeof cause?.code === 'string' ? cause.code : 'AcquisitionFailed',
      {cause});
    this.code = this.message;
    this.outcome = outcome;
    this.recovery = recovery;
  }
}

export function acquisitionFailure(cause, outcome, recovery) {
  if (!outcomes.has(outcome) ||
      (recovery !== undefined && (outcome !== 'unknown' ||
        typeof recovery?.close !== 'function' ||
        typeof recovery?.cleanup !== 'function' ||
        typeof recovery?.cleanupPending !== 'function'))) {
    throw new TypeError('InvalidAcquisitionOutcome');
  }
  // A failure already stated by an inner step keeps its statement.
  if (cause instanceof AcquisitionOpenError) return cause;
  return new AcquisitionOpenError(cause, outcome, recovery);
}

export function acquisitionOutcome(error) {
  return error instanceof AcquisitionOpenError
    ? Object.freeze({outcome: error.outcome, recovery: error.recovery})
    : Object.freeze({outcome: 'unknown', recovery: undefined});
}
