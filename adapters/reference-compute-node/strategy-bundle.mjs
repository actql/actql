// In-process independent Compute implementation. No DB, transport settings or
// attempt settlement in application code; the connector-owned entry completes it.
export function numericStrategyContribution(moon, setup, checked) {
  return Object.freeze({
    registration: moon.strategyModule_reference_compute_Registration(setup),
    async run(task) {
      checked(moon.strategyModule_reference_compute_Dispatch(setup, task));
      return {diagnostic: {realization: 'reference-numeric'}};
    },
  });
}
