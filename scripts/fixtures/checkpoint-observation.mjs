// Pure fixture observation DATA; no Client/Host/runtime is imported here.
import assert from 'node:assert/strict';
import {types as nodeTypes} from 'node:util';

// Fixture observation covers two configured ordinary retry intervals. It
// never schedules a product retry or changes the unchanged 120s child guard.
export function checkpointObservationSchedule(leaseMs) {
  assert(Number.isSafeInteger(leaseMs) && leaseMs >= 1000);
  const pollMs = 25, retryMs = leaseMs + 100;
  const polls = Math.ceil(2 * retryMs / pollMs);
  assert(3 * polls * pollMs < 120000,
    'Three observation phases must fit the existing child budget');
  return Object.freeze({pollMs, retryMs, polls});
}

// Keep only the public failure's own scalar DATA; no getter, cause traversal
// or compiled value inspection is needed to preserve the original throw.
export function checkpointFailureData(error) {
  const data = {name: null, code: null};
  if (error === null || typeof error !== 'object' || nodeTypes.isProxy(error)) return data;
  for (const key of ['name', 'code']) {
    const field = Object.getOwnPropertyDescriptor(error, key);
    if (field && Object.hasOwn(field, 'value') && typeof field.value === 'string') data[key] = field.value;
  }
  return data;
}

// The existing Host event may put an error message in `code`. Retain only
// fixed authored dispatch labels from that field, never arbitrary messages.
// An emitted label remains DATA, not proof of its origin or nonacceptance.
export function checkpointDispatchFailureData(detail) {
  if (detail === null || typeof detail !== 'object' || nodeTypes.isProxy(detail)) return undefined;
  const data = {};
  const code = Object.getOwnPropertyDescriptor(detail, 'primaryCode');
  if (code && Object.hasOwn(code, 'value') && typeof code.value === 'string' &&
      /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/u.test(code.value)) data.primaryCode = code.value;
  const emittedCodes = ['InstalledManagedComputeRunUnavailable', 'PreparationHostCustodyUnavailable',
    'DuplicatePreparationHostBorrow', 'ForeignPreparationHostCustody', 'InstalledManagedComputeHostUnavailable',
    'ClientProgramNeedsInputs', 'PreparationPublicationUnavailable', 'ClientDispatchCleanupOwnerAlreadyRetained',
    'ClientDispatchCleanupOwnerInvalid', 'CapturedRunPublicationFailed', 'CapturedRunExecutionFailed',
    'ClientRunStopObservationChanged', 'ClientDispatchCleanupPending'];
  const emitted = Object.getOwnPropertyDescriptor(detail, 'code');
  if (emitted && Object.hasOwn(emitted, 'value') && typeof emitted.value === 'string' &&
      emittedCodes.includes(emitted.value)) data.emittedCode = emitted.value;
  for (const key of ['issueTag', 'nestedIssueTag']) {
    const field = Object.getOwnPropertyDescriptor(detail, key);
    if (field && Object.hasOwn(field, 'value') && Number.isSafeInteger(field.value) &&
        field.value >= 0 && field.value <= 65535) data[key] = field.value;
  }
  return Object.freeze(data);
}

export function checkpointObservationRecord(records, kind, data) {
  if (records.some(record => record.kind === kind)) return undefined;
  const record = Object.freeze({kind, data: Object.freeze({...data})});
  records.push(record);
  return record;
}

export function createCheckpointDispatchObserver(record) {
  return (name, detail) => {
    if (name !== 'dispatch_failed') return;
    const data = checkpointDispatchFailureData(detail);
    if (data !== undefined) record('diagnostic:dispatch_failed', data);
  };
}

export function createCheckpointFaultObserver(records, record, appendEvent) {
  return (name, detail) => {
    appendEvent(name);
    if (name === 'dispatch_reserved' || name === 'physical_start_reserved') {
      record(`first-${name}`, {});
    } else if (name === 'resume_failed' || name === 'sweep_failed') {
      record('first-resume-failure', {event:name,code:detail?.code??null});
    } else if (name === 'resume_claimed') {
      record('first-resume-claim', {generation:detail.generation});
      if (records.some(value=>value.kind==='first-resume-failure')) {
        record('resume-claim-after-failure', {generation:detail.generation});
      }
    } else if (name === 'run_observed' && records.some(value=>value.kind==='first-resume-failure')) {
      record('run-observed-after-failure', {});
    }
  };
}

// Borrow the caller's existing client and first-attempt WeakSet. This helper
// does not create a client, suppress a close, or acknowledge physical stop.
export async function closeCheckpointClient(selected, closedClients, record, label) {
  const first = !closedClients.has(selected);
  closedClients.add(selected);
  record(`close-attempt:${label}`, {first});
  try {
    const value = await selected.close();
    record(`close-returned:${label}`, {first});
    return value;
  } catch (error) {
    record(`close-failed:${label}`, {first,...checkpointFailureData(error)});
    throw error;
  }
}
