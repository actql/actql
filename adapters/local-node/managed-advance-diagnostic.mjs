// Optional DATA on the SAME failed advance; never a new error, execution or
// cleanup owner. Only the original Core getter can select the closed reason.
import {runtimeIsBoxedSome, runtimeField} from '../host-common/compiler-binding.generated.mjs';

export function checkedLocalManagedAdvance(moon, result, checked, task) {
  try {return checked(result);}
  catch (error) {
    try {
      const resource = moon.strategyModule_local_ManagedAdvanceResourceDimension;
      if (typeof resource === 'function' && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const dimension = Reflect.apply(resource, moon, [result]);
        if (dimension === 'retained_bytes' || dimension === 'execution_bytes') {
          Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
            code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task, dimension,
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
              Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
                code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'value_capture_work', task, step, workLimit,
              })});
            }
          }
        }
      }
    } catch { /* Optional diagnosis cannot replace the original failure. */ }
    throw error;
  }
}
