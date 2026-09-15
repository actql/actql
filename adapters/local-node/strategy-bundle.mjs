// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
export function localStrategyContribution(moon, setup, checked) {
  return Object.freeze({
    registration: moon.strategyHostLocalRegistration(setup),
    async run(task) {
      checked(moon.strategyHostExecuteLocal(task));
      return { diagnostic: { realization: 'local' } };
    },
  });
}
