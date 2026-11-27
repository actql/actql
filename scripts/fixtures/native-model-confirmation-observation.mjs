// Both opted-in Native records borrow closed evidence. The receipt is tied
// to the same physical response and encrypted holdings in the fixture.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const accountingMarker = 'ACTQL_NATIVE_MODEL_ACCOUNTING ';
const rawMarker = 'ACTQL_NATIVE_MODEL_RAW_RECEIPT ';
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const amount = value => Number.isSafeInteger(value) && value >= 0;
const optionalAmount = value => value === null || amount(value);
const accountingFields = ['attempt_cid', 'cost_units', 'cumulative_work', 'duration_ms',
  'input_tokens', 'output_tokens', 'reservation', 'self_cid', 'slot_cid', 'uncertain_wire_bytes', 'version'];
const rawFields = ['attempt', 'attempt_cid', 'byte_count', 'content_cid', 'effective_data_policy_cid',
  'http_status', 'observed_at', 'phase', 'raw_capture_policy_cid', 'response_profile_cid', 'run_definition_cid',
  'scope_cid', 'self_cid', 'slot_cid', 'store_authority_cid', 'transport_eof', 'version'];

function parseAccounting(original) {
  const fields = Object.hasOwn(original, 'reservation') ? accountingFields : accountingFields.filter(key => key !== 'reservation');
  assert.deepEqual(Object.keys(original), fields);
  assert.equal(original.version, 'actql-model-attempt-accounting/0.1');
  assert(amount(original.cumulative_work) && amount(original.uncertain_wire_bytes));
  assert([original.cost_units, original.duration_ms, original.input_tokens, original.output_tokens].every(optionalAmount));
  if (Object.hasOwn(original, 'reservation')) {
    assert.deepEqual(Object.keys(original.reservation), ['cost_units', 'duration_ms', 'tokens']);
    assert(Object.values(original.reservation).every(amount));
  }
  return {identity: original.self_cid, attempt: original.attempt_cid, slot: original.slot_cid,
    input_tokens: original.input_tokens, output_tokens: original.output_tokens};
}

function parseRaw(original) {
  assert.deepEqual(Object.keys(original), rawFields);
  assert.equal(original.version, 'actql-model-raw-response/0.1');
  assert.equal(original.attempt, 1);
  assert.equal(original.phase, 'entered');
  assert(amount(original.byte_count) && original.byte_count <= 65536);
  assert(amount(original.http_status) && original.http_status >= 100 && original.http_status <= 599);
  assert(typeof original.transport_eof === 'boolean');
  assert.match(original.observed_at, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/u);
  return {
    identity: original.self_cid, attempt: original.attempt_cid, slot: original.slot_cid,
    scope: original.scope_cid, definition: original.run_definition_cid, authority: original.store_authority_cid,
    effectivePolicy: original.effective_data_policy_cid, capturePolicy: original.raw_capture_policy_cid,
    profile: original.response_profile_cid, content: original.content_cid, bytes: original.byte_count,
    status: original.http_status, eof: original.transport_eof,
  };
}

export function splitNativeModelConfirmations(stderr, pid) {
  assert(stderr.endsWith('\n'), 'Truncated Native observation stream');
  const accounting = [];
  const raw = [];
  const timingLines = [];
  for (const line of stderr.split('\n')) {
    const marker = line.startsWith(accountingMarker) ? accountingMarker : line.startsWith(rawMarker) ? rawMarker : null;
    if (marker === null) {
      timingLines.push(line);
      continue;
    }
    const recorded = marker === accountingMarker ? accounting : raw;
    assert(recorded.length < 2 && line.length < 1200, 'Native Model confirmation limit');
    const body = line.slice(marker.length);
    const record = JSON.parse(body);
    assert.deepEqual(Object.keys(record), ['pid', 'evidence']);
    assert.equal(record.pid, pid, 'Foreign Native confirmation process');
    assert.equal(JSON.stringify(record), body, 'Noncanonical or duplicate Native confirmation fields');
    const row = marker === accountingMarker ? parseAccounting(record.evidence) : parseRaw(record.evidence);
    const {self_cid: identity, ...preimage} = record.evidence;
    for (const [key, value] of Object.entries(record.evidence))
      if (key.endsWith('_cid')) assert.match(value, cidPattern);
    assert.equal(identity, 'sha256:' + createHash('sha256').update(JSON.stringify(preimage)).digest('hex'),
      'Changed Native Model evidence');
    recorded.push(row);
  }
  return {timing: timingLines.join('\n'), accounting, raw};
}

export function requireNativeModelAccounting(observed, custody, expectedByTask) {
  assert.equal(observed.length, custody.observed.length);
  const byAttempt = new Map(observed.map(row => [row.attempt, row]));
  assert.equal(byAttempt.size, observed.length, 'Repeated Native Model accounting observation');
  return custody.observed.map(({attempt, task, slot, evidence}) => {
    const {evidenceCid} = evidence.find(({role}) => role === 'model_attempt_accounting');
    const row = byAttempt.get(attempt);
    assert(row, 'Missing Native Model accounting for the original attempt');
    assert.equal(row.slot, slot);
    assert.equal(row.identity, evidenceCid);
    const usage = {input_tokens: row.input_tokens, output_tokens: row.output_tokens};
    assert.deepEqual(usage, expectedByTask.get(task));
    return {task, attempt, evidenceCid, ...usage};
  });
}

export function requireNativeRawReceipts(observed, custody, selectedByTask) {
  assert.equal(observed.length, custody.observed.length);
  const byAttempt = new Map(observed.map(row => [row.attempt, row]));
  assert.equal(byAttempt.size, observed.length, 'Repeated Native Raw receipt');
  assert.equal(new Set(observed.map(row => row.capturePolicy)).size, observed.length, 'Repeated Native Raw capture policy');
  return custody.observed.map(({attempt, task, slot, scope, rawHolding, evidence}) => {
    const row = byAttempt.get(attempt);
    assert(row, 'Missing Native Raw receipt for the original attempt');
    assert.equal(row.slot, slot);
    assert.equal(row.scope, scope);
    assert.equal(row.definition, custody.definition);
    assert.equal(row.authority, custody.authority);
    assert.equal(row.effectivePolicy, custody.policy.policyCid);
    const descriptor = evidence.find(({role}) => role === 'model_raw_response');
    if (custody.terminalRun) assert(descriptor, 'Missing committed terminal Raw descriptor');
    if (descriptor) assert.equal(row.identity, descriptor.evidenceCid);
    const response = {profile: row.profile, content: row.content, bytes: row.bytes, status: row.status, eof: row.eof};
    assert.deepEqual(response, selectedByTask.get(task));
    return {attempt, task, evidenceCid: row.identity, holding: rawHolding, ...response};
  });
}
