// Diagnostic selection never changes the registered matrix or its fixtures.
// An explicit case is not a substitute for completing the full readiness gate.
export function selectReadinessCases(cases, id) {
  if (id === undefined) return {cases, scope: 'full-matrix'};
  if (typeof id !== 'string' || id.length === 0) throw new Error('Invalid retained diagnostic case');
  const selected = cases.filter(value => value.id === id);
  if (selected.length !== 1) throw new Error(`Unknown or ambiguous retained diagnostic case: ${id}`);
  return {cases: selected, scope: 'single-case-diagnostic'};
}
