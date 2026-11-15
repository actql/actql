import {types as nodeTypes} from 'node:util';

function ownData(record, key) {
  if (record === null || typeof record !== 'object' || nodeTypes.isProxy(record)) return undefined;
  const field = Object.getOwnPropertyDescriptor(record, key);
  return field && Object.hasOwn(field, 'value') ? field.value : undefined;
}

// Preserve one existing Host admission event in the command's existing stderr
// evidence. These labels/tags are DATA, not an acceptance or failure verdict.
// Never serialize errors, opaque compiled values, getters or business inputs.
export function inferPreparationFailureData(detail) {
  const boundary = ownData(detail, 'boundary');
  if (!['original_model_compilation', 'model_execution', 'model_dependencies',
    'model_provider', 'model_dispatch', 'model_admission', 'task_compilation',
    'model_admission.original_startup', 'model_admission.compute_suffix',
    'model_admission.egress', 'model_admission.account', 'model_admission.plan_graph',
    'model_admission.provider_binding'].includes(boundary)) return undefined;
  const data = {boundary};
  for (const key of ['code', 'typedCause']) {
    const value = ownData(detail, key);
    if (typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/u.test(value)) data[key] = value;
  }
  const tag = ownData(ownData(detail, 'cause'), '$tag');
  if (Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535) data.issueTag = tag;
  return Object.freeze(data);
}

// The original Host callback already owns this failure. Preserve only finite
// labels and enum tags before FIRST close; never inspect messages or bodies.
export function effectBoundaryFailureData(event, detail) {
  if (!['effect_start_failed', 'effect_settlement_failed',
    'effect_resume_failed', 'source_resume_failed'].includes(event)) return undefined;
  const data = {event};
  for (const key of ['code', 'primaryCode']) {
    const value = ownData(detail, key);
    if (typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(value)) data[key] = value;
  }
  for (const key of ['issueTag', 'nestedIssueTag']) {
    const value = ownData(detail, key);
    if (Number.isSafeInteger(value) && value >= 0 && value <= 65535) data[key] = value;
  }
  const tags = [];
  let cause = ownData(detail, 'cause');
  for (let depth = 0; depth < 8 && cause !== undefined; depth++) {
    const tag = ownData(cause, '$tag');
    if (Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535) tags.push(tag);
    const next = ownData(cause, 'cause') ?? ownData(cause, '_0');
    if (next === cause) break;
    cause = next;
  }
  if (tags.length) data.causeTags = Object.freeze(tags);
  return Object.freeze(data);
}

// A terminal capture cannot become the delegated Checkpoint this same call
// expects. Keep its public status, without exporting the Run or private data.
export function effectCheckpointTerminalData(state) {
  const status = ownData(state, 'status');
  if (!['failed', 'cancelled', 'needs_reconciliation', 'succeeded'].includes(status)) return undefined;
  const data = {status};
  const code = ownData(ownData(state, 'terminal_error'), 'code');
  if (typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(code)) data.terminalCode = code;
  return Object.freeze(data);
}
