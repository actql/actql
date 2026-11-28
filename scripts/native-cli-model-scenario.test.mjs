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

test('Native File and Model named Results select two different checked producer ports', () => {
  const firstTask = 'model-task:churn-risk.v1';
  const secondTask = 'model-task:churn-risk-confirm.v1';
  const one = nativeJoinedModelRun(firstTask, secondTask);
  const named = nativeJoinedModelRun(firstTask, secondTask, {includeReview: true});
  assert.deepEqual(named.program.stages, one.program.stages);
  assert.deepEqual(named.expectedRows, one.expectedRows);
  assert.deepEqual(named.program.results, {
    answer: {from: {stage: 'combined', result: 'rows'}},
    review: {from: {stage: 'first', result: 'rows'}},
  });
  assert.deepEqual(named.additionalResults, {review: [{
    id: 'joined-1', outcome: 'ok', value: {level: 'low', reason: 'independent first Model reply'},
  }]});
  assert.deepEqual(one.additionalResults, {});
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

function deliveryFixture({includeReview = false, aliasesAnswer = false} = {}) {
  const {expectedRows: rows, finalResultPolicy, additionalResults} =
    nativeJoinedModelRun('test-a', 'test-b', {includeReview});
  const runId = identity('public run');
  const definition = identity('original definition');
  const invocation = identity('original invocation');
  const policyCid = identity(finalResultPolicy);
  const artifact = seal({version: 'actql-result-artifact/0.1', invocation_cid: invocation,
    actual_completeness: 'complete', actual_row_count: 1, effective_data_policy_cid: policyCid,
    result_schema_cid: identity('joined Result schema'),
    logical_result_cid: identity('typed original row')}, 'result_artifact_cid');
  const results = {answer: artifact};
  if (includeReview) {
    results.review = aliasesAnswer ? artifact : seal({
      version: 'actql-result-artifact/0.1', invocation_cid: invocation,
      actual_completeness: 'complete', actual_row_count: 1, effective_data_policy_cid: policyCid,
      result_schema_cid: identity('first Model Result schema'),
      logical_result_cid: identity('first Model typed original row'),
    }, 'result_artifact_cid');
  }
  const names = Object.keys(results);
  const manifest = seal({version: 'actql-result-manifest/0.1', run_definition_cid: definition,
    invocation_cid: invocation, results}, 'result_manifest_cid');
  const sourceEvidence = [identity('accounts'), identity('usage')];
  const modelEvidence = [identity('first model'), identity('second model')];
  const runReceipt = seal({version: 'actql-run-receipt/0.1', invocation_cid: invocation,
    result_manifest_cid: manifest.result_manifest_cid, result_manifest: manifest, result_artifacts: manifest.results,
    source_evidence_cids: sourceEvidence,
    external_observation_evidence: [
      ...sourceEvidence.map(evidence_cid => ({kind: 'source_lookup', evidence_cid})),
      ...modelEvidence.map(evidence_cid => ({kind: 'model_invocation', evidence_cid})),
    ]}, 'receipt_identity_cid');
  const expectedResults = {answer: rows, ...additionalResults};
  const outputs = Object.fromEntries(names.map(name => [name, {
    path: `/original/${name}-outside-host.jsonl`,
    payload: Buffer.from(expectedResults[name].map(row => JSON.stringify(row) + '\n').join('')),
  }]));
  const deliveries = names.map(name => {
    const {path, payload} = outputs[name];
    const resultCid = results[name].result_artifact_cid;
    const receipt = seal({version: 'actql-result-delivery-receipt/0.1', run_definition_cid: definition,
      invocation_cid: invocation, result_artifact_cid: resultCid,
      result_manifest_cid: manifest.result_manifest_cid, result_name: name,
      delivered_byte_count: payload.length, delivered_sha256: hash(payload)}, 'result_delivery_receipt_cid');
    return {run_id: runId, status: 'delivered', receipt,
      request: {result: name, result_cid: resultCid, format: 'jsonl', path}};
  });
  const now = '2026-11-26T04:59:44.607Z';
  const report = {version: 'actql-cli-run-response/0.1', delivery_status: 'delivered',
    run: {run_id: runId, status: 'succeeded', updated_at: now, result_available: false,
      next_action: {kind: 'refresh_availability', results: names},
      result_availability: Object.fromEntries(names.map(name =>
        [name, {state: 'unknown', reason: 'verification_pending', observed_at: now}]))},
    deliveries};
  const custody = {definition, runId, observed: modelEvidence.map(evidenceCid =>
    ({evidence: [{role: 'model_invocation_evidence', evidenceCid}]}))};
  return {report, runReceipt, outputs, rows, policyCid, custody, additionalResults};
}

test('Native JOIN delivery verifies the typed file independently of the saved Run availability projection', () => {
  const fixture = deliveryFixture();
  const result = requireNativeJoinedDelivery(fixture);
  assert.equal(result.bytes, fixture.outputs.answer.payload.length);
  assert.equal(result.sha256, hash(fixture.outputs.answer.payload));
  assert.equal(result.runReceiptCid, fixture.runReceipt.receipt_identity_cid);
});

test('Native JOIN delivery requires the complete named inventory and refuses a reused Artifact', () => {
  const fixture = deliveryFixture({includeReview: true});
  const proof = requireNativeJoinedDelivery(fixture);
  assert.equal(proof.manifestCid, fixture.runReceipt.result_manifest_cid);
  assert.deepEqual(Object.keys(proof.namedDeliveries), ['answer', 'review']);
  for (const [name, {resultCid, sha256}] of Object.entries(proof.namedDeliveries)) {
    assert.equal(resultCid, fixture.runReceipt.result_manifest.results[name].result_artifact_cid);
    assert.equal(sha256, hash(fixture.outputs[name].payload));
  }
  assert.throws(() => requireNativeJoinedDelivery({...fixture, additionalResults: {}}),
    {code: 'ERR_ASSERTION'});
  assert.throws(() => requireNativeJoinedDelivery(deliveryFixture({includeReview: true, aliasesAnswer: true})),
    {code: 'ERR_ASSERTION'});
});

test('Native named JOIN delivery refuses an omitted, swapped or copied delivery', () => {
  const fixture = deliveryFixture({includeReview: true});
  const {report, outputs} = fixture;
  const [answer, review] = report.deliveries;
  for (const deliveries of [[answer], [answer, answer], [answer, {...review, receipt: answer.receipt}]]) {
    assert.throws(() => requireNativeJoinedDelivery({...fixture, report: {...report, deliveries}}),
      {code: 'ERR_ASSERTION'});
  }
  for (const altered of [
    {answer: outputs.answer},
    {answer: outputs.answer, review: {...outputs.review, path: outputs.answer.path}},
    {answer: outputs.answer, review: {...outputs.review, payload: outputs.answer.payload}},
  ]) {
    assert.throws(() => requireNativeJoinedDelivery({...fixture, outputs: altered}), {code: 'ERR_ASSERTION'});
  }
  const payload = Buffer.from(outputs.review.payload.toString('utf8').replace('"low"', '"bad"'));
  assert.equal(payload.length, outputs.review.payload.length);
  const {result_delivery_receipt_cid: previous, ...receiptBody} = review.receipt;
  const receipt = seal({...receiptBody, delivered_sha256: hash(payload)}, 'result_delivery_receipt_cid');
  assert.notEqual(receipt.result_delivery_receipt_cid, previous);
  assert.throws(() => requireNativeJoinedDelivery({
    ...fixture, outputs: {...outputs, review: {...outputs.review, payload}},
    report: {...report, deliveries: [answer, {...review, receipt}]},
  }), {code: 'ERR_ASSERTION'});
});

test('Native JOIN delivery refuses unsupported availability or unconfirmed delivery', () => {
  const fixture = deliveryFixture();
  const {report} = fixture;
  const {run, deliveries: [delivery]} = report;
  for (const observation of [
    {run: {...run, result_available: true}},
    {run: {...run, result_availability: {answer: {...run.result_availability.answer, reason: 'retention_expired'}}}},
    {run: {...run, next_action: {...run.next_action, results: ['foreign']}}},
    {delivery_status: 'pending'},
    {deliveries: [{...delivery, status: 'pending'}]},
  ]) {
    assert.throws(() => requireNativeJoinedDelivery({...fixture, report: {...report, ...observation}}),
      {code: 'ERR_ASSERTION'});
  }
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
  const {payload, path} = fixture.outputs.answer;
  const changed = Buffer.from(payload.toString('utf8').replace('joined-1', 'joined-2'));
  assert.equal(changed.length, payload.length);
  const outputs = {answer: {path, payload: changed}};
  assert.throws(() => requireNativeJoinedDelivery({...fixture, outputs}), {code: 'ERR_ASSERTION'});
  const wrongRowsReceipt = seal({...oldReceipt, delivered_sha256: hash(changed)}, 'result_delivery_receipt_cid');
  const wrongRows = {...fixture.report, deliveries: [{...delivery, receipt: wrongRowsReceipt}]};
  assert.throws(() => requireNativeJoinedDelivery({...fixture, outputs, report: wrongRows}),
    {code: 'ERR_ASSERTION'});
  assert.throws(() => requireNativeJoinedDelivery({...fixture, policyCid: identity('source-free policy')}),
    {code: 'ERR_ASSERTION'});
});
