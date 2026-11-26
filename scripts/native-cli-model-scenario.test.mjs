import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {canonicalText} from './check-canonical-json.mjs';
import {nativeJoinedModelRun, requireModelAttempts, requireNativeJoinedDelivery} from './fixtures/native-joined-model-run.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = value => 'sha256:' + hash(canonicalText(value));
const seal = (body, name) => ({...body, [name]: identity(body)});

test('Native joined Model fixture names two File sources and joins two distinct Model results', () => {
  const firstTask = 'model-task:churn-risk.v1';
  const secondTask = 'model-task:churn-risk-confirm.v1';
  const scenario = nativeJoinedModelRun(firstTask, secondTask);
  const {connection, catalog, payload, program} = scenario;
  assert.notEqual(scenario.finalResultPolicy, scenario.modelRawDataPolicy);
  assert.notEqual(scenario.finalResultPolicy.source_response_policy_cids,
    scenario.modelRawDataPolicy.source_response_policy_cids);
  assert.equal(scenario.finalResultPolicy.classification, 'unknown');
  assert.equal(scenario.finalResultPolicy.source_response_policy_cids.length, 2);
  const [source, first, second, combined] = program.stages;
  assert.deepEqual(Object.values(source.inputs).map(({resource}) => resource), ['accounts', 'usage']);
  for (const {resource, items_path} of catalog.connections[connection].data) {
    const [row] = items_path.reduce((value, part) => value[part], payload);
    assert.equal(row.id, 'joined-1');
    assert.equal(catalog.connections[connection].views.find(view => view.resource === resource).data_classification,
      'internal');
  }
  assert.deepEqual(source.steps[0].join.select, {
    id: 'left.id', notes: 'left.notes', active_users: 'right.active_users', trend: 'right.trend',
  });
  for (const [stage, contract] of [[first, firstTask], [second, secondTask]]) {
    assert.equal(stage.inputs.rows.result.stage, 'source');
    assert.equal(stage.steps[1].infer.contract, contract);
  }
  assert.deepEqual(Object.values(combined.inputs).map(({result}) => result.stage), ['first', 'second']);
  assert.deepEqual(combined.steps[0].join.select, {
    id: 'left.id', first_outcome: 'left.outcome', first_value: 'left.value',
    second_outcome: 'right.outcome', second_value: 'right.value',
  });
  assert.deepEqual(program.results, {answer: {from: {stage: 'combined', result: 'rows'}}});
  const [row] = scenario.expectedRows;
  assert.notEqual(row.first_value.level, row.second_value.level);
  scenario.answers[0].reason = 'wrong reply';
  assert.equal(row.first_value.reason, 'independent first Model reply');
});

const attempt = (tag, digit, ordinal = 0) => ({tag, identity: 'sha256:' + digit.repeat(64), ordinal});

test('Native Model observations preserve individual attempt order under interleaving', () => {
  assert.deepEqual(requireModelAttempts([
    attempt(0, 'a'), attempt(0, 'b'), attempt(1, 'a'), attempt(1, 'b'), attempt(2, 'b'), attempt(2, 'a'),
  ], 2), ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)]);
});

test('Native Model observations refuse a second send, a foreign row and an incomplete attempt', () => {
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a'), attempt(1, 'a'), attempt(2, 'a'),
  ], 1), {name: 'AssertionError'});
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a', 1), attempt(2, 'a'),
  ], 1), {name: 'AssertionError'});
  assert.throws(() => requireModelAttempts([
    attempt(0, 'a'), attempt(1, 'a'), attempt(2, 'a'), attempt(0, 'b'), attempt(1, 'b'),
  ], 2), {name: 'AssertionError'});
});

function deliveryFixture() {
  const {expectedRows: rows, finalResultPolicy} = nativeJoinedModelRun('test-a', 'test-b');
  const runId = identity('public run');
  const definition = identity('original definition');
  const invocation = identity('original invocation');
  const policyCid = identity(finalResultPolicy);
  const path = '/original/results-outside-host.jsonl';
  const payload = Buffer.from(rows.map(row => JSON.stringify(row) + '\n').join(''));
  const artifact = seal({version: 'actql-result-artifact/0.1', invocation_cid: invocation,
    actual_completeness: 'complete', actual_row_count: 1, effective_data_policy_cid: policyCid,
    logical_result_cid: identity('typed original row')}, 'result_artifact_cid');
  const manifest = seal({version: 'actql-result-manifest/0.1', run_definition_cid: definition,
    invocation_cid: invocation, results: {answer: artifact}}, 'result_manifest_cid');
  const sourceEvidence = [identity('accounts'), identity('usage')];
  const modelEvidence = [identity('first model'), identity('second model')];
  const runReceipt = seal({version: 'actql-run-receipt/0.1', invocation_cid: invocation,
    result_manifest_cid: manifest.result_manifest_cid, result_manifest: manifest, result_artifacts: manifest.results,
    source_evidence_cids: sourceEvidence,
    external_observation_evidence: [
      ...sourceEvidence.map(evidence_cid => ({kind: 'source_lookup', evidence_cid})),
      ...modelEvidence.map(evidence_cid => ({kind: 'model_invocation', evidence_cid})),
    ]}, 'receipt_identity_cid');
  const receipt = seal({version: 'actql-result-delivery-receipt/0.1', run_definition_cid: definition,
    invocation_cid: invocation, result_artifact_cid: artifact.result_artifact_cid,
    result_manifest_cid: manifest.result_manifest_cid, result_name: 'answer',
    delivered_byte_count: payload.length, delivered_sha256: hash(payload)}, 'result_delivery_receipt_cid');
  const report = {version: 'actql-cli-run-response/0.1', delivery_status: 'delivered',
    run: {run_id: runId, result_availability: {answer: {state: 'available'}}},
    deliveries: [{run_id: runId, status: 'delivered', receipt,
      request: {result: 'answer', result_cid: artifact.result_artifact_cid, format: 'jsonl', path}}]};
  const custody = {definition, runId, observed: modelEvidence.map(evidenceCid =>
    ({evidence: [{role: 'model_invocation_evidence', evidenceCid}]}))};
  return {report, runReceipt, payload, path, rows, policyCid, custody};
}

test('Native JOIN delivery matches the original Run receipt, actual file and typed rows', () => {
  const fixture = deliveryFixture();
  const result = requireNativeJoinedDelivery(fixture);
  assert.equal(result.bytes, fixture.payload.length);
  assert.equal(result.sha256, hash(fixture.payload));
  assert.equal(result.runReceiptCid, fixture.runReceipt.receipt_identity_cid);
});

test('Native JOIN delivery refuses foreign originals and matching-size changes', () => {
  const fixture = deliveryFixture();
  const [delivery] = fixture.report.deliveries;
  const {result_delivery_receipt_cid: prior, ...oldReceipt} = delivery.receipt;
  assert(prior);
  const foreignReceipt = seal({...oldReceipt, result_artifact_cid: identity('same rows, different artifact')},
    'result_delivery_receipt_cid');
  const foreign = {...fixture.report, deliveries: [{...delivery, receipt: foreignReceipt}]};
  assert.throws(() => requireNativeJoinedDelivery({...fixture, report: foreign}), {code: 'ERR_ASSERTION'});
  const changed = Buffer.from(fixture.payload.toString('utf8').replace('joined-1', 'joined-2'));
  assert.equal(changed.length, fixture.payload.length);
  assert.throws(() => requireNativeJoinedDelivery({...fixture, payload: changed}), {code: 'ERR_ASSERTION'});
  const wrongRowsReceipt = seal({...oldReceipt, delivered_sha256: hash(changed)}, 'result_delivery_receipt_cid');
  const wrongRows = {...fixture.report, deliveries: [{...delivery, receipt: wrongRowsReceipt}]};
  assert.throws(() => requireNativeJoinedDelivery({...fixture, payload: changed, report: wrongRows}),
    {code: 'ERR_ASSERTION'});
  assert.throws(() => requireNativeJoinedDelivery({...fixture, policyCid: identity('source-free policy')}),
    {code: 'ERR_ASSERTION'});
});
