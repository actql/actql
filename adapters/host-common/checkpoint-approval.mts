import {canonicalJson} from '../../packages/sdk/host-port.mjs';

// Read approvals the Host's Checkpoint owner admitted for one dispatch. The
// Checkpoint records the exact approved read (tuple, physical binding,
// checked source and requesting principal) with the decision it returns; a
// source adapter reads these facts to verify that the approval covers the
// read it is about to perform. A copied or constructed decision has none.
const approvals = new WeakMap<object, Readonly<Record<PropertyKey, unknown>>>();
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});

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

// Select the original object held by the Checkpoint. The Site still admits
// the pair; an expected binding supplied by a codec is never a grant.
type PhysicalBinding = Readonly<Record<string, unknown>>;

export function admitCheckpointPhysicalRead<Decision, Operation, Result>(
  decision: Decision, expected: PhysicalBinding, operation: Operation,
  admit: (decision: Decision, binding: PhysicalBinding, operation: Operation) => Result, foreignCode: string,
): Result {
  const matched = (checkpointApprovalFacts(decision)?.physicalBindings as
    readonly PhysicalBinding[] | undefined)?.find(value =>
    Object.entries(expected).every(([key, item]) => encode(value[key]) === encode(item)));
  if (!matched) throw Object.assign(new Error(foreignCode), {code: foreignCode});
  return admit(decision, matched, operation);
}
