// Independent benchmark settlement: attempt every owned cleanup action and
// preserve both execution failure and unconfirmed cleanup. Not product Host code.
export async function settleObligationRun(primary, actions) {
  const failures = [];
  for (const [phase, action] of actions) {
    try { await action(); }
    catch (cause) { failures.push(new Error(`ObligationCleanupFailed:${phase}`, {cause})); }
  }
  if (failures.length) {
    throw new AggregateError(primary === undefined ? failures : [primary, ...failures],
      'ObligationRunCleanupUnconfirmed');
  }
  if (primary !== undefined) throw primary;
}
