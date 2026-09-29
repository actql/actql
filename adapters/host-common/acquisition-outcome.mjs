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
    // The cause's own code, or its message, stays the failure's identity.
    super(typeof cause?.code === 'string' ? cause.code
      : typeof cause?.message === 'string' && cause.message !== ''
        ? cause.message : 'AcquisitionFailed', {cause});
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

// An installed adapter transfers its end observation before another boundary
// can wrap the thrown error. The receiving Run owner retains this statement
// separately from the exception chain; a missing statement remains unknown.
export function acquisitionEndHandoff() {
  let failure;
  return Object.freeze({
    retain(error) {
      if (!(error instanceof AcquisitionOpenError) ||
          !outcomes.has(error.outcome) ||
          (error.recovery !== undefined && (error.outcome !== 'unknown' ||
            typeof error.recovery?.close !== 'function' ||
            typeof error.recovery?.cleanup !== 'function' ||
            typeof error.recovery?.cleanupPending !== 'function')) ||
          (failure !== undefined && failure !== error)) {
        throw new TypeError('InvalidAcquisitionEndHandoff');
      }
      failure = error;
      return error;
    },
    outcome(error) {
      return acquisitionOutcome(failure ?? error);
    },
  });
}
