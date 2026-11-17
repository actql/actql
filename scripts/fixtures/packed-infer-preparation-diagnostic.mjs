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

// Reviewed labels from runtime-result/ordinary-source-managed and the public
// unpublished terminal state. A new or caller-selected label is omitted.
const effectBoundaryCodes = new Set([
  'MoonBitHostFailure', 'InvalidHostRuntimeResult', 'ForeignInstalledSourceProducer',
]);
const effectTerminalCodes = new Set(['ACTQL_E_UNPUBLISHED_RUN']);

// The original Host callback already owns this failure. Preserve only finite
// labels and enum tags before FIRST close; never inspect messages or bodies.
export function effectBoundaryFailureData(event, detail) {
  if (!['effect_start_failed', 'effect_settlement_failed',
    'effect_resume_failed', 'source_resume_failed'].includes(event)) return undefined;
  const data = {event};
  for (const key of ['code', 'primaryCode']) {
    const value = ownData(detail, key);
    if (typeof value === 'string' && effectBoundaryCodes.has(value)) data[key] = value;
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
  if (typeof code === 'string' && effectTerminalCodes.has(code)) data.terminalCode = code;
  return Object.freeze(data);
}

// Reuse the existing dispatch observer without serializing its original Error,
// Run reference, input, message or stack. Diagnostics never change execution.
export function inferDispatchFailureData(detail) {
  const own = (record, key) => {
    if (record === null || typeof record !== 'object' || nodeTypes.isProxy(record)) return undefined;
    const field = Object.getOwnPropertyDescriptor(record, key);
    return field && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  const data = {};
  for (const key of ['code', 'primaryCode']) {
    const value = own(detail, key);
    if (typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/u.test(value)) data[key] = value;
  }
  for (const key of ['issueTag', 'nestedIssueTag']) {
    const value = own(detail, key);
    if (Number.isSafeInteger(value) && value >= 0 && value <= 65535) data[key] = value;
  }
  return Object.keys(data).length === 0 ? undefined : Object.freeze(data);
}

export function inferTerminalFailureData(terminal) {
  const own = (record, key) => {
    if (record === null || typeof record !== 'object' || nodeTypes.isProxy(record)) return undefined;
    const field = Object.getOwnPropertyDescriptor(record, key);
    return field && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  const data = {};
  for (const [key, value] of [['status', own(terminal, 'status')],
    ['nextAction', own(own(terminal, 'next_action'), 'kind')],
    ['terminalCode', own(own(terminal, 'terminal_error'), 'code')]]) {
    if (typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/u.test(value)) data[key] = value;
  }
  return Object.freeze(data);
}

// Test-only command observation. No caller-supplied value becomes a Run,
// authority, currentness decision or acceptance receipt through this helper.
export function createInferFailureObserver({emit, record = () => {}, readCalls}) {
  let inferObserved = false, dispatchObserved = false;
  return (name, detail) => {
    if (name === 'dispatch_failed' && readCalls !== undefined && !dispatchObserved) {
      const data = inferDispatchFailureData(detail);
      if (data === undefined) return;
      dispatchObserved = true;
      const observed = Object.freeze({event:name,...data,calls:readCalls()});
      record(observed);emit(observed);return;
    }
    if (name !== 'infer_preparation_rejected' || inferObserved) return;
    const data = inferPreparationFailureData(detail);
    if (data === undefined) return;
    inferObserved = true;
    const observed = Object.freeze({event:name,...data});record(observed);emit(observed);
  };
}

export function withEffectFixturePreparationDiagnostic(prepare, diagnostic) {
  return facts => {
    try {return prepare(facts);}
    catch (cause) {
      try {
        const own = (value, name) => {
          if (value === null || !['object','function'].includes(typeof value) || nodeTypes.isProxy(value)) return undefined;
          const field = Object.getOwnPropertyDescriptor(value, name);
          return field && Object.hasOwn(field,'value') ? field.value : undefined;
        };
        const issue = own(cause,'cause'), tag = Number.isSafeInteger(issue) ? issue : own(issue,'$tag');
        const code = own(cause,'code');
        diagnostic(JSON.stringify({phase:'effect_definition_preparation',
          code:typeof code === 'string' && /^[A-Za-z0-9_]{1,96}$/u.test(code) ? code : undefined,
          issueTag:Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535 ? tag : undefined,
          limitsObserved:false}));
      } catch { /* Diagnostic failure cannot replace the original throw. */ }
      throw cause;
    }
  };
}

export async function waitForPackedCompositionCheckpoint(execution, waitFor, diagnostic) {
  let status;
  try {await waitFor(async () => {
    status = (await execution.status()).status;return status === 'waiting_checkpoint';
  });}
  catch (cause) {
    try {diagnostic({boundary:'pending-composition-wait',status,expectedStatus:'waiting_checkpoint'});}
    catch { /* Preserve the actual bounded wait's original failure. */ }
    throw cause;
  }
}
