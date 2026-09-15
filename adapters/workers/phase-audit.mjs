// Conformance spy, not execution authority. Actual permission and reservation
// are still enforced by the product Core and the Connector's owned attempt.
export function phaseAudit() {
  let phase = 'idle';
  const calls = [], violations = [];
  return Object.freeze({
    calls, violations,
    during(next, operation) {
      const previous = phase;
      phase = next;
      try {
        const value = operation();
        if (value && typeof value.then === 'function') {
          return value.finally(() => { phase = previous; });
        }
        phase = previous;
        return value;
      } catch (error) { phase = previous; throw error; }
    },
    perform(kind, admitted, operation) {
      const permitted = kind === 'cleanup' ? phase === 'cleanup' : phase === 'execution';
      if (!permitted || !admitted) {
        violations.push({phase,kind,admitted});
        throw new Error('UnpermittedPhaseIO');
      }
      calls.push({phase,kind});
      return operation();
    },
  });
}
