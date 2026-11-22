import {canonicalJson} from '../../packages/sdk/host-port.mjs';

// Read approvals the Host's Checkpoint owner admitted for one dispatch. The
// Checkpoint records the exact approved read (tuple, physical binding,
// checked source and requesting principal) with the decision it returns; a
// source adapter reads these facts to verify that the approval covers the
// read it is about to perform. A copied or constructed decision has none.
const approvals = new WeakMap();
const encode = value => canonicalJson(value, {dataKeys: true});

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

// Select the original object held by the Checkpoint. The Site still admits
// the pair; an expected binding supplied by a codec is never a grant.
export function admitCheckpointPhysicalRead(decision, expected, operation, admit, foreignCode) {
  const matched = checkpointApprovalFacts(decision)?.physicalBindings?.find(value =>
    Object.entries(expected).every(([key, item]) => encode(value[key]) === encode(item)));
  if (!matched) throw Object.assign(new Error(foreignCode), {code: foreignCode});
  return admit(decision, matched, operation);
}
