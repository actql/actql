// How an installed source's acquisition ended when it could not return a
// capture. The adapter that did the physical work states it; the dispatch
// owner never infers it from an error:
// - `not_started`: confirmed that no provider I/O began.
// - `stopped`: provider I/O began and every transport and resource of this
//   acquisition is confirmed ended and released.
// - `unknown`: the adapter cannot confirm its end. A `recovery` owner
//   ({close, cleanup, cleanupPending}) may take over what remains.
// An error without a stated outcome is `unknown` with no recovery owner.
type UncheckedFailure = {readonly code?: unknown; readonly message?: unknown};
type UncheckedRecovery = {readonly close?: unknown; readonly cleanup?: unknown; readonly cleanupPending?: unknown};
const outcomes = new Set<unknown>(['not_started', 'stopped', 'unknown']);

export class AcquisitionOpenError extends Error {
  declare readonly code: string;
  declare readonly outcome: unknown;
  declare readonly recovery: unknown;
  declare readonly classificationFailure?: unknown;
  declare readonly identityInspectionFailure?: unknown;

  constructor(cause: unknown, outcome: unknown, recovery?: unknown) {
    // The cause's own code, or its message, stays the failure's identity.
    // Classification must not replace an arbitrary rejection reason. Read
    // each property once: getters may change their result or throw any value.
    let label = 'AcquisitionFailed', classificationFailed = false, classificationFailure;
    try {
      const code = (cause as UncheckedFailure | null | undefined)?.code;
      if (typeof code === 'string') label = code;
      else {
        const message = (cause as UncheckedFailure | null | undefined)?.message;
        if (typeof message === 'string' && message !== '') label = message;
      }
    } catch (error) {
      classificationFailed = true;
      classificationFailure = error;
    }
    super(label, {cause});
    this.code = this.message;
    this.outcome = outcome;
    this.recovery = recovery;
    if (classificationFailed) Object.defineProperty(this, 'classificationFailure',
      {value: classificationFailure});
  }
}

export function acquisitionFailure(cause: unknown, outcome: unknown, recovery?: unknown) {
  if (!outcomes.has(outcome) ||
      (recovery !== undefined && (outcome !== 'unknown' ||
        typeof (recovery as UncheckedRecovery | null | undefined)?.close !== 'function' ||
        typeof (recovery as UncheckedRecovery | null | undefined)?.cleanup !== 'function' ||
        typeof (recovery as UncheckedRecovery | null | undefined)?.cleanupPending !== 'function'))) {
    throw new TypeError('InvalidAcquisitionOutcome');
  }
  // A failure already stated by an inner step keeps its statement.
  let original = false, identityInspectionFailed = false, identityInspectionFailure;
  try { original = cause instanceof AcquisitionOpenError; }
  catch (error) {
    identityInspectionFailed = true;
    identityInspectionFailure = error;
  }
  if (original) return cause as AcquisitionOpenError;
  const error = new AcquisitionOpenError(cause, outcome, recovery);
  if (identityInspectionFailed) Object.defineProperty(error, 'identityInspectionFailure',
    {value: identityInspectionFailure});
  return error;
}

export function acquisitionOutcome(error: unknown) {
  return error instanceof AcquisitionOpenError
    ? Object.freeze({outcome: error.outcome, recovery: error.recovery})
    : Object.freeze({outcome: 'unknown', recovery: undefined});
}

// An installed adapter transfers its end observation before another boundary
// can wrap the thrown error. The receiving Run owner retains this statement
// separately from the exception chain; a missing statement remains unknown.
export function acquisitionEndHandoff() {
  let failure: AcquisitionOpenError | undefined;
  return Object.freeze({
    retain(error: unknown) {
      if (!(error instanceof AcquisitionOpenError) ||
          !outcomes.has(error.outcome) ||
          (error.recovery !== undefined && (error.outcome !== 'unknown' ||
            typeof (error.recovery as UncheckedRecovery | null | undefined)?.close !== 'function' ||
            typeof (error.recovery as UncheckedRecovery | null | undefined)?.cleanup !== 'function' ||
            typeof (error.recovery as UncheckedRecovery | null | undefined)?.cleanupPending !== 'function')) ||
          (failure !== undefined && failure !== error)) {
        throw new TypeError('InvalidAcquisitionEndHandoff');
      }
      failure = error;
      return error;
    },
    outcome(error?: unknown) {
      return acquisitionOutcome(failure ?? error);
    },
  });
}
