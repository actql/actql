// The common Host owns task selection, settlement, completion, and output life.
export function externalNumericContribution(moon, setup, checked) {
  return Object.freeze({
    registration: moon.strategyModule_external_numeric_Registration(setup),
    async run(task, _signal, completionPermit) {
      checked(moon.strategyModule_external_numeric_Dispatch(
        setup,
        task,
        () => completionPermit?.isAvailable?.() !== false,
      ));
      return {diagnostic: {realization: 'external-numeric'}};
    },
  });
}
