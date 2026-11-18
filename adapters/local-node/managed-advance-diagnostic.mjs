// Optional DATA on the SAME failed advance; never a new error, execution or
// cleanup owner. Only the original Core getter can select the closed reason.
import {runtimeIsError, runtimeIsBoxedSome, runtimeField, runtimeOptionalField, runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';

function originalBudget(moon, result, diagnostic) {
  try {
  const project = moon.strategyModule_local_ManagedAdvanceBudget;
  if (typeof project !== 'function') return undefined;
  // This exact compiled export returns an unboxed reference Option of a
  // tuple, independently exercised by the bridge's real JS ABI regression.
  const value = runtimeUnboxedReferenceOption(Reflect.apply(project, moon, [result]));
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const fields = Array.from({length: 5}, (_, index) => {
    const descriptor = runtimeOptionalField(descriptors, index);
    return descriptor && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
  });
  const [dimension, exact, requested, remaining, policy] = fields;
  if (dimension !== (diagnostic.kind === 'resource' ? diagnostic.dimension : diagnostic.kind) ||
      typeof exact !== 'boolean' ||
      [requested, remaining, policy].some(amount => typeof amount !== 'bigint' || amount < 0n || amount > 9223372036854775807n) ||
      requested <= remaining || remaining > policy ||
      (dimension === 'value_capture_work' ? exact || policy !== BigInt(diagnostic.workLimit)
        : !exact || !['retained_bytes', 'execution_bytes'].includes(dimension))) return undefined;
  return Object.freeze({requested: requested.toString(), remaining: remaining.toString(),
    policy: policy.toString(), requestedIsLowerBound: !exact});
  } catch { return undefined; }
}

export function checkedLocalManagedAdvance(moon, result, checked, task) {
  try {return checked(result);}
  catch (error) {
    try {
      // Only the original compiler's closed Err family reaches these getters.
      // A foreign checker exception cannot turn an Ok or malformed value into
      // a typed failure, regardless of the exception's copied code property.
      // Every LocalDispatchIssue carries an original payload. A payload-free
      // foreign enum must not be reinterpreted as this result family. This is
      // only a representation guard, never a nominal issuer or admission.
      if (!runtimeIsError(result) || runtimeField(result, 0) === null ||
          typeof runtimeField(result, 0) !== 'object') throw error;
      const resource = moon.strategyModule_local_ManagedAdvanceResourceDimension;
      if (typeof resource === 'function' && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const dimension = Reflect.apply(resource, moon, [result]);
        if (dimension === 'retained_bytes' || dimension === 'execution_bytes') {
          const data = {
            code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task, dimension,
          };
          const budget = originalBudget(moon, result, data);
          Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
            ...data, ...(budget === undefined ? {} : {budget}),
          })});
        }
      }
      const project = moon.strategyModule_local_ManagedAdvanceControlWorkLimit;
      if (!Object.hasOwn(error, 'primaryDiagnostic') && typeof project === 'function' && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const controlWorkLimit = Reflect.apply(project, moon, [result]);
        if (Number.isSafeInteger(controlWorkLimit) && controlWorkLimit >= 0 && controlWorkLimit <= 2147483647) {
          Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
            code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task, controlWorkLimit,
          })});
        }
      }
      if (!Object.hasOwn(error, 'primaryDiagnostic') && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const projectCapture = moon.strategyModule_local_ManagedAdvanceCaptureWork;
        if (typeof projectCapture === 'function') {
          const captureOption = Reflect.apply(projectCapture, moon, [result]);
          const capture = runtimeIsBoxedSome(captureOption) ? runtimeField(captureOption, 0) : undefined;
          if (Array.isArray(capture) && capture.length === 2) {
            const step = Object.getOwnPropertyDescriptor(capture, '0')?.value;
            const workLimit = Object.getOwnPropertyDescriptor(capture, '1')?.value;
            if (Number.isSafeInteger(step) && step >= 0 && step <= 2147483647 &&
                Number.isSafeInteger(workLimit) && workLimit >= 0 && workLimit <= 2147483647) {
              const data = {
                code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'value_capture_work', task, step, workLimit,
              };
              const budget = originalBudget(moon, result, data);
              Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
                ...data, ...(budget === undefined ? {} : {budget}),
              })});
            }
          }
        }
      }
      if (!Object.hasOwn(error, 'primaryDiagnostic') && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const projectLogical = moon.strategyModule_local_ManagedAdvanceLogicalWorkPolicy;
        if (typeof projectLogical === 'function') {
          const logical = runtimeUnboxedReferenceOption(Reflect.apply(projectLogical, moon, [result]));
          if (logical != null && typeof logical === 'object' && !Array.isArray(logical)) {
            const step = runtimeField(logical, 0), limit = runtimeField(logical, 1), setting = runtimeField(logical, 2);
            if (Number.isSafeInteger(step) && step >= 0 && step <= 2147483647 &&
                typeof limit === 'bigint' && limit >= 0n && limit <= 9223372036854775807n &&
                (setting === 'installation.sourceFreeMaxWork' || setting === 'unavailable')) {
              Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
                code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'logical_work',
                task, step, workLimit: limit.toString(), setting,
              })});
            }
          }
        }
        const projectCause = moon.strategyModule_local_ManagedAdvanceCause;
        const projectStep = moon.strategyModule_local_ManagedAdvanceRowStep;
        if (!Object.hasOwn(error, 'primaryDiagnostic') && typeof projectCause === 'function' && typeof projectStep === 'function') {
          const cause = Reflect.apply(projectCause, moon, [result]);
          const step = Reflect.apply(projectStep, moon, [result]);
          if (typeof cause === 'string' && cause.length <= 96 &&
              /^[a-z_]+(?:\.[a-z_]+)*$/u.test(cause) &&
              Number.isSafeInteger(step) && step >= -1 && step <= 2147483647) {
            Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze(step === -1 ? {
              code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'local_issue', task, cause,
            } : {
              code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'row_failure', task, step, cause,
            })});
          }
        }
      }
    } catch { /* Optional diagnosis cannot replace the original failure. */ }
    throw error;
  }
}
