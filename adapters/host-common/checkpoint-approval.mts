// Read approvals the Host's Checkpoint owner admitted for one dispatch. The
// Checkpoint records the exact approved read (tuple, physical binding,
// checked source and requesting principal) with the decision it returns; a
// source adapter reads these facts to verify that the approval covers the
// read it is about to perform. A copied or constructed decision has none.
const approvals = new WeakMap<object, Readonly<Record<PropertyKey, unknown>>>();

export function recordCheckpointApproval<T>(decision: T, facts: unknown): T {
  if (decision === null || typeof decision !== 'object' ||
      !Object.isFrozen(decision) || approvals.has(decision)) {
    throw new TypeError('InvalidCheckpointApproval');
  }
  approvals.set(decision, Object.freeze({...(facts as object)}));
  return decision;
}

export function checkpointApprovalFacts(decision: unknown) {
  return decision !== null && typeof decision === 'object'
    ? approvals.get(decision) : undefined;
}
