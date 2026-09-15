// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
export function localStrategyContribution(moon, setup, checked) {
  return Object.freeze({
    registration: moon.strategyModule_local_Registration(setup),
    async run(task) {
      checked(moon.strategyModule_local_Dispatch(setup, task));
      return { diagnostic: { realization: 'local' } };
    },
  });
}
