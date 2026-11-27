import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {verifyIdentity} from '../check-canonical-json.mjs';

// Two adopted File relations, two independently selected Model Tasks, one Result.
export function nativeJoinedModelRun(firstTask, secondTask) {
  const connection = 'files/native-fixture';
  const field = type => ({type, nullable: false});
  const views = [
    {resource: 'accounts', schema: {id: field('string'), notes: field('string')}},
    {resource: 'usage', schema: {id: field('string'), active_users: field('int64'), trend: field('string')}},
  ].map(view => ({...view, resource_kind: 'record', data_classification: 'internal',
    facts: {relation_keys: {candidate_keys: [['id']]}}}));
  const connections = {version: 'actql-connectors/0.1', connections: {[connection]: {connector: connection}}};
  const catalog = {connections: {[connection]: {views, query_aliases: views.map(({resource}) => ({
    name: resource, resource,
  })), data: views.map(({resource}) => ({resource, items_path: [connection, resource, 'rows'],
    key_path: [connection, resource, 'key'], primary_identity: 'id'}))}}};
  const payload = {[connection]: {
    accounts: {key: ['id'], rows: [{id: 'joined-1', notes: 'account notes from the declared File'}]},
    usage: {key: ['id'], rows: [{id: 'joined-1', active_users: '17', trend: 'declining usage from the declared File'}]},
  }};
  const expectedInput = {
    active_users: '17', notes: 'account notes from the declared File',
    trend: 'declining usage from the declared File',
  };
  // Both File Views contribute to each policy. The Model response adds
  // unknown provenance. The Raw and final Result proofs compare their own
  // originals to separate copies of this independently authored expectation.
  const joinedPolicy = () => ({
    classification: 'unknown',
    source_data_policy_cids: [
      'sha256:530c120715b6538c2b5afa3431f0eaee463b593ce24d5323d48332b72bf4af70',
      'sha256:780d5be079a2364b02d5c51448101bfed3220aa3f176f6300a8e6d25eef196a8',
    ],
    source_response_policy_cids: [
      'sha256:03d4a4c3e6d268665495515859a5e87ee33a737469c9b642db6433f557ef3599',
      'sha256:e30171f43cd510506568f1ee10f0e0baa013bba5723cb69967f9b18d9154dd21',
    ],
    unknown_provenance: true,
    version: 'actql-effective-data-policy/0.1',
  });
  const modelRawResponseViews = new Map([
    ['sha256:e30171f43cd510506568f1ee10f0e0baa013bba5723cb69967f9b18d9154dd21',
      'sha256:53523f86c2abd066cb72f721f5d7bd9e2ea6249c9387c8757827b63fb6e24b13'],
    ['sha256:03d4a4c3e6d268665495515859a5e87ee33a737469c9b642db6433f557ef3599',
      'sha256:3f300c394be6861870871a168e2f9e5a56185a73993ca8c81bbd6ae35e219afb'],
  ]);
  const answers = [{level: 'low', reason: 'independent first Model reply'},
    {level: 'high', reason: 'independent second Model reply'}];
  const result = stage => ({result: {stage, result: 'rows'}});
  const on = [{left: 'id', right: 'id'}];
  const infer = (id, contract) => ({
    id, inputs: {rows: result('source')}, steps: [
      {from: 'rows', assert_rows: {unique_by: ['id']}},
      {infer: {contract, key: 'id', input: {notes: {field: 'notes'}, active_users: {field: 'active_users'},
        trend: {field: 'trend'}}}, as: 'inferred'},
    ], results: {rows: {from: 'inferred', fields: ['id', 'outcome', 'value']}},
  });
  const program = {version: 'actql/0.1', id: 'native-file-two-model-join', stages: [
    {id: 'source', inputs: {account: {connector: connection, resource: 'accounts', view: 'records'},
      usage: {connector: connection, resource: 'usage', view: 'records'}}, steps: [{
      from: 'account', join: {with: 'usage', kind: 'inner', on, select: {
        id: 'left.id', notes: 'left.notes', active_users: 'right.active_users', trend: 'right.trend',
      }}, as: 'joined',
    }], results: {rows: {from: 'joined', fields: ['id', 'notes', 'active_users', 'trend']}}},
    infer('first', firstTask),
    infer('second', secondTask),
    {id: 'combined', inputs: {first: result('first'), second: result('second')}, steps: [{
      from: 'first', join: {with: 'second', kind: 'inner', on, select: {
        id: 'left.id', first_outcome: 'left.outcome', first_value: 'left.value',
        second_outcome: 'right.outcome', second_value: 'right.value',
      }}, as: 'joined',
    }], results: {rows: {from: 'joined',
      fields: ['id', 'first_outcome', 'first_value', 'second_outcome', 'second_value']}}},
  ], results: {answer: {from: {stage: 'combined', result: 'rows'}}}};
  return {connection, resources: views.map(({resource}) => resource), connections, catalog, payload, expectedInput,
    answers, program, modelRawDataPolicy: joinedPolicy(), finalResultPolicy: joinedPolicy(), modelRawResponseViews, expectedRows: [{
      id: 'joined-1',
      first_outcome: 'ok', first_value: {level: 'low', reason: 'independent first Model reply'},
      second_outcome: 'ok', second_value: {level: 'high', reason: 'independent second Model reply'},
    }]};
}

// Every individual Task has one input row and one admitted attempt. Events
// from independent Tasks can interleave, so compare progression per attempt.
export function requireModelAttempts(events, count) {
  const attempts = new Map();
  for (const {identity, tag, ordinal} of events) {
    assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(ordinal, 0);
    if (!attempts.has(identity)) attempts.set(identity, []);
    attempts.get(identity).push(tag);
  }
  assert.equal(attempts.size, count);
  for (const tags of attempts.values()) assert.deepEqual(tags, [0, 1, 2]);
  return [...attempts.keys()];
}

function requireSealedContract(value, version, identity) {
  const {[identity]: cid, ...body} = value;
  assert.equal(body.version, version);
  verifyIdentity(body, cid);
  return cid;
}

export function requireNativeJoinedDelivery({
  report, runReceipt, payload, path, rows, policyCid, custody, failedModelTask = null,
}) {
  assert.equal(report.version, 'actql-cli-run-response/0.1');
  assert.equal(report.run.run_id, custody.runId);
  assert.equal(report.run.status, 'succeeded');
  // The RunRead projection re-observes the stored Run after delivery. It
  // has no fresh availability observation for answer. Prove this delivery
  // separately using the original receipts and the actual bytes below.
  assert.equal(report.run.result_available, false);
  assert.equal(typeof report.run.updated_at, 'string');
  assert.deepEqual(report.run.result_availability, {answer: {
    state: 'unknown', reason: 'verification_pending', observed_at: report.run.updated_at,
  }});
  assert.deepEqual(report.run.next_action, {kind: 'refresh_availability', results: ['answer']});
  assert.equal(report.delivery_status, 'delivered');
  assert.equal(report.deliveries.length, 1);
  const [delivery] = report.deliveries;
  assert.equal(delivery.run_id, custody.runId);
  assert.equal(delivery.status, 'delivered');

  const runReceiptCid = requireSealedContract(runReceipt, 'actql-run-receipt/0.1', 'receipt_identity_cid');
  const manifest = runReceipt.result_manifest;
  const manifestCid = requireSealedContract(manifest, 'actql-result-manifest/0.1', 'result_manifest_cid');
  assert.equal(runReceipt.result_manifest_cid, manifestCid);
  assert.equal(manifest.run_definition_cid, custody.definition);
  assert.equal(manifest.invocation_cid, runReceipt.invocation_cid);
  assert.deepEqual(runReceipt.result_artifacts, manifest.results);
  assert.deepEqual(Object.keys(manifest.results), ['answer']);
  const artifact = manifest.results.answer;
  const resultCid = requireSealedContract(artifact, 'actql-result-artifact/0.1', 'result_artifact_cid');
  assert.equal(artifact.invocation_cid, manifest.invocation_cid);
  assert.equal(artifact.effective_data_policy_cid, policyCid);
  assert.equal(artifact.actual_row_count, rows.length);
  assert.equal(artifact.actual_completeness, 'complete');

  if (failedModelTask !== null) assert.equal(custody.observed.filter(call => call.task === failedModelTask).length, 1);
  const expectedModels = custody.observed.flatMap(call => {
    const evidence = call.evidence.filter(value => value.role === 'model_invocation_evidence');
    if (call.task === failedModelTask) {
      assert.equal(evidence.length, 0, 'A failed Model cannot contribute successful invocation evidence');
      assert.equal(call.evidence.filter(value => value.role === 'model_raw_response').length, 1);
      return [];
    }
    assert.equal(evidence.length, 1);
    return [evidence[0].evidenceCid];
  });
  const models = runReceipt.external_observation_evidence.filter(value => value.kind === 'model_invocation');
  assert.deepEqual(models.map(value => value.evidence_cid).sort(), expectedModels.sort());
  const sources = runReceipt.external_observation_evidence.filter(value => value.kind === 'source_lookup');
  assert.equal(new Set(runReceipt.source_evidence_cids).size, 2);
  assert.deepEqual(sources.map(value => value.evidence_cid), runReceipt.source_evidence_cids);

  const {receipt} = delivery;
  const deliveryReceiptCid = requireSealedContract(receipt, 'actql-result-delivery-receipt/0.1',
    'result_delivery_receipt_cid');
  assert.deepEqual(delivery.request, {result: 'answer', result_cid: resultCid, format: 'jsonl', path});
  assert.equal(receipt.result_name, 'answer');
  assert.equal(receipt.run_definition_cid, custody.definition);
  assert.equal(receipt.invocation_cid, manifest.invocation_cid);
  assert.equal(receipt.result_manifest_cid, manifestCid);
  assert.equal(receipt.result_artifact_cid, resultCid);

  const sha256 = createHash('sha256').update(payload).digest('hex');
  assert.equal(receipt.delivered_byte_count, payload.length);
  assert.equal(receipt.delivered_sha256, sha256);
  const text = new TextDecoder('utf-8', {fatal: true}).decode(payload);
  const lines = text.split('\n');
  assert.equal(lines.pop(), '');
  assert.deepEqual(lines.map(line => JSON.parse(line)), rows);
  return {runReceiptCid, manifestCid, resultCid, deliveryReceiptCid, bytes: payload.length, sha256};
}
