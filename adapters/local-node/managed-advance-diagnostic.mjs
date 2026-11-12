// Optional DATA on the SAME failed advance; never a new error, execution or
// cleanup owner. Only the original Core getter can select the closed reason.
export function checkedLocalManagedAdvance(moon, result, checked, task) {
  try {return checked(result);}
  catch (error) {
    try {
      const project = moon.strategyModule_local_ManagedAdvanceControlWorkLimit;
      if (typeof project === 'function' && Number.isSafeInteger(task) && task >= 0 && task <= 2147483647 &&
          Object.getOwnPropertyDescriptor(error, 'code')?.value === 'MoonBitHostFailure') {
        const controlWorkLimit = Reflect.apply(project, moon, [result]);
        if (Number.isSafeInteger(controlWorkLimit) && controlWorkLimit >= 0 && controlWorkLimit <= 2147483647) {
          Object.defineProperty(error, 'primaryDiagnostic', {value: Object.freeze({
            code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task, controlWorkLimit,
          })});
        }
      }
    } catch { /* Optional diagnosis cannot replace the original failure. */ }
    throw error;
  }
}
