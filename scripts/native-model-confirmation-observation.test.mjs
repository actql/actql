import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {requireNativeModelAccounting, requireNativeRawReceipts, splitNativeModelConfirmations}
  from './fixtures/native-model-confirmation-observation.mjs';

const cid = body => 'sha256:' + createHash('sha256').update(body).digest('hex');
const pid = 123;
const first = {attempt: cid('first'), slot: cid('first slot'), task: cid('first task')};
const second = {attempt: cid('second'), slot: cid('second slot'), task: cid('second task')};

function accountingWire({attempt, slot}, input, output) {
  const body = {attempt_cid: attempt, cost_units: null, cumulative_work: 23, duration_ms: null,
    input_tokens: input, output_tokens: output, reservation: {cost_units: 0, duration_ms: 3000, tokens: 36},
    slot_cid: slot, uncertain_wire_bytes: 66536, version: 'actql-model-attempt-accounting/0.1'};
  const identity = cid(JSON.stringify(body));
  return Object.fromEntries(Object.entries({...body, self_cid: identity}).sort(([a], [b]) => a.localeCompare(b)));
}

const firstWire = accountingWire(first, 0, 8);
const secondWire = accountingWire(second, 15, null);
const line = (accounting, process = pid) => 'ACTQL_NATIVE_MODEL_ACCOUNTING ' + JSON.stringify({pid: process, evidence: accounting}) + '\n';
const firstLine = line(firstWire);
const secondLine = line(secondWire);
const usage = new Map([[first.task, {input_tokens: 0, output_tokens: 8}],
  [second.task, {input_tokens: 15, output_tokens: null}]]);
const custody = {observed: [[first, firstWire], [second, secondWire]].map(([scope, wire]) =>
  ({...scope, evidence: [{role: 'model_attempt_accounting', evidenceCid: wire.self_cid}]}))};

test('Native Model accounting matches retained evidence by attempt and preserves zero and missing usage', () => {
  const timing = 'ACTQL_NATIVE_TIMINGS {"pid":123}\n';
  const split = splitNativeModelConfirmations(secondLine + firstLine + timing, pid);
  assert.equal(split.timing, timing);
  assert.deepEqual(requireNativeModelAccounting(split.accounting, custody, usage),
    [[first, firstWire], [second, secondWire]].map(([scope, wire]) => ({task: scope.task, attempt: scope.attempt,
      evidenceCid: wire.self_cid, ...usage.get(scope.task)})));
});

test('Native Model accounting refuses changed, duplicate, foreign and unconfirmed diagnostics', () => {
  assert.throws(() => splitNativeModelConfirmations(line(firstWire, pid + 1), pid), /Foreign Native confirmation process/u);
  assert.throws(() => splitNativeModelConfirmations(firstLine.slice(0, -1), pid), {message: 'Truncated Native observation stream'});
  assert.throws(() => splitNativeModelConfirmations(line({...firstWire, input_tokens: 1}), pid),
    /Changed Native Model evidence/u);
  const missing = splitNativeModelConfirmations(firstLine, pid).accounting;
  assert.throws(() => requireNativeModelAccounting(missing, custody, usage), {code: 'ERR_ASSERTION'});
  const repeated = splitNativeModelConfirmations(firstLine.repeat(2), pid).accounting;
  assert.throws(() => requireNativeModelAccounting(repeated, custody, usage),
    /Repeated Native Model accounting observation/u);
  const other = splitNativeModelConfirmations(line(accountingWire(first, 1, 8)) + secondLine, pid).accounting;
  assert.throws(() => requireNativeModelAccounting(other, custody, usage), {code: 'ERR_ASSERTION'});
});

const runDefinition = cid('original run');
const storeAuthority = cid('original store');
const rawByTask = new Map();
const rawScopes = [first, second].map(item => ({
  ...item, scope: cid(item.task + ' scope'), rawHolding: cid(item.attempt + ' entered holding'),
}));

function rawDescriptor(item) {
  const sent = {profile: cid(item.task + ' profile'), content: cid(item.task + ' exact provider response'),
    bytes: 157, status: 200, eof: true};
  rawByTask.set(item.task, sent);
  return {
    attempt: 1, attempt_cid: item.attempt, byte_count: sent.bytes, content_cid: sent.content,
    effective_data_policy_cid: cid('effective data policy'), http_status: sent.status, observed_at: '2026-11-25T00:00:00.000Z',
    phase: 'entered', raw_capture_policy_cid: cid(item.task + ' capture policy'), response_profile_cid: sent.profile,
    run_definition_cid: runDefinition, scope_cid: item.scope, slot_cid: item.slot,
    store_authority_cid: storeAuthority, transport_eof: sent.eof, version: 'actql-model-raw-response/0.1',
  };
}

const descriptors = rawScopes.map(rawDescriptor);
const rawCustody = {definition: runDefinition, authority: storeAuthority,
  policy: {policyCid: cid('effective data policy')}, observed: rawScopes.map((scope, index) => ({
    ...scope,
    evidence: index === 0 ? [{role: 'model_raw_response', evidenceCid: cid(JSON.stringify(descriptors[index]))}] : [],
  }))};
function rawLine(body) {
  const evidence = Object.fromEntries(Object.entries({...body, self_cid: cid(JSON.stringify(body))})
    .sort(([a], [b]) => a.localeCompare(b)));
  return 'ACTQL_NATIVE_MODEL_RAW_RECEIPT ' + JSON.stringify({pid, evidence}) + '\n';
}

test('Native Raw receipts bind exact bytes and profile to each original retained attempt', () => {
  const [firstRaw, secondRaw] = descriptors.map(rawLine);
  const split = splitNativeModelConfirmations(secondRaw + secondLine + firstRaw + firstLine, pid);
  assert.equal(split.accounting.length, 2);
  const confirmed = requireNativeRawReceipts(split.raw, rawCustody, rawByTask);
  assert.deepEqual(confirmed.map(({task, content, holding}) => ({task, content, holding})),
    rawCustody.observed.map(({task, rawHolding}) => ({task, content: rawByTask.get(task).content, holding: rawHolding})));
});

test('Native Raw receipt refuses re-sealed substituted bytes, wrong profile and foreign invocation', () => {
  const [original, secondRaw] = descriptors;
  for (const changed of [
    {content_cid: secondRaw.content_cid}, {response_profile_cid: secondRaw.response_profile_cid},
    {scope_cid: secondRaw.scope_cid}, {transport_eof: false}, {byte_count: original.byte_count + 1},
    {effective_data_policy_cid: cid('other effective policy')}, {raw_capture_policy_cid: secondRaw.raw_capture_policy_cid},
  ]) {
    const split = splitNativeModelConfirmations(rawLine({...original, ...changed}) + rawLine(secondRaw), pid);
    assert.throws(() => requireNativeRawReceipts(split.raw, rawCustody, rawByTask), {code: 'ERR_ASSERTION'});
  }
});

test('Native Raw receipts refuse a different settled descriptor for the same original attempt', () => {
  const split = splitNativeModelConfirmations(descriptors.map(rawLine).join(''), pid);
  const [producer, sibling] = rawCustody.observed;
  const foreign = {...producer, evidence: [{role: 'model_raw_response', evidenceCid: split.raw[1].identity}]};
  assert.throws(() => requireNativeRawReceipts(split.raw, {...rawCustody, observed: [foreign, sibling]}, rawByTask),
    {code: 'ERR_ASSERTION'});
});
