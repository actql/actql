// Read approvals the Host's Checkpoint owner admitted for one dispatch. The
// Checkpoint records the exact approved read (tuple, physical binding,
// checked source and requesting principal) with the decision it returns; a
// source adapter reads these facts to verify that the approval covers the
// read it is about to perform. A copied or constructed decision has none.
const approvals = new WeakMap();

export function recordCheckpointApproval(decision, facts) {
  if (decision === null || typeof decision !== 'object' ||
      !Object.isFrozen(decision) || approvals.has(decision)) {
    throw new TypeError('InvalidCheckpointApproval');
  }
  approvals.set(decision, Object.freeze({...facts}));
  return decision;
}

export function checkpointApprovalFacts(decision) {
  return decision !== null && typeof decision === 'object'
    ? approvals.get(decision) : undefined;
}
