import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {createServer, request} from 'node:http';
import {canonicalText} from './check-canonical-json.mjs';
import {nativeFileModelEffect, requireNativeFileModelEffectTrace} from './fixtures/native-file-model-effect.mjs';
import {requireNativeFileModelDeletePreview} from './native-cli-model-scenario.mjs';
import {nativeJoinedModelRun, requireModelAttempts, requireNativeJoinedDelivery} from './fixtures/native-joined-model-run.mjs';
import {dropNativeDependentModelReply, nativeDependentModelDocument, nativeDependentModelInput, nativeDependentModelOutputPolicy,
  nativeDependentModelRun, nativeModelBindingIdentity} from './fixtures/native-dependent-model-run.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = value => 'sha256:' + hash(canonicalText(value));
const seal = (body, name) => ({...body, [name]: identity(body)});

test('Native File Model Effect inputs retain the File source and an independent original DELETE oracle', () => {
  const fixture = nativeFileModelEffect('model-task:churn-risk.v1');
  const {files, document, before, after} = fixture;
  const project = JSON.parse(files['actql.config.json']);
  assert.equal(project.state_dir, './host');
  assert.deepEqual(project.mock.answers, {});
  assert.deepEqual(JSON.parse(files['model-tasks.json']).tasks, {});
  assert.deepEqual(JSON.parse(files['model-tasks.json']).providers, {});
  const catalog = JSON.parse(files['mock/catalog.json']);
  const {views, query_aliases, data} = catalog.connections.drive;
  assert.equal(views.length, 1);
  assert.deepEqual([views[0].resource, views[0].resource_kind, views[0].data_classification],
    ['files', 'record', 'internal']);
  assert.deepEqual(views[0].facts.relation_keys.candidate_keys, [['id']]);
  assert.deepEqual(views[0].schema, {
    id: {type: 'string', nullable: false}, notes: {type: 'string', nullable: false},
    active_users: {type: 'int64', nullable: false}, trend: {type: 'string', nullable: false},
  });
  assert.deepEqual(query_aliases, [{name: 'drive.files', resource: 'files'}]);
  assert.deepEqual(data, [{resource: 'files', items_path: ['drive', 'files', 'rows'],
    key_path: ['drive', 'files', 'key'], primary_identity: 'id'}]);
  assert.deepEqual(catalog.connections.salesforce.writes.map(({resource, operation, approval}) =>
    [resource, operation, approval]), [['Opportunity', 'delete', 'required']]);
  const rows = JSON.parse(before);
  assert.deepEqual(rows.drive.files, {key: ['id'], rows: [{id: '006Acme', ...fixture.input}]});
  assert.deepEqual(fixture.input, {notes: 'Acme Corp - Renewal', active_users: '17', trend: 'declining'});
  assert.equal(files[document].split('\n|> INFER ')[0],
    'SELECT f.id, f.notes, f.active_users, f.trend\nFROM drive.files AS f\n|> ASSERT UNIQUE BY (id)');
  rows.salesforce.Opportunity.rows.shift();
  assert.deepEqual(JSON.parse(after), rows);
  assert.equal(before, files['mock/data.json']);
  assert.match(files[document], /FROM drive\.files AS f[\s\S]*INFER .+ AS advice[\s\S]*advice\.value\.level = 'high'[\s\S]*EFFECT DELETE salesforce\.Opportunity ID id;/u);
  assert.deepEqual(fixture.rows, [{id: '006Acme', outcome: 'ok', value: fixture.reply}]);
});

test('Native File Model Effect Preview displays the original full DELETE and rejects foreign rows', () => {
  const fixture = nativeFileModelEffect('model-task:churn-risk.v1');
  const expected = {run_id: identity('run'), status: 'waiting_checkpoint',
    checkpoint: {checkpoint_id: 'checkpoint', checkpoint_cid: identity('checkpoint')}};
  const before = {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null};
  const stdout = [
    `Run: ${JSON.stringify(expected.run_id)}`, 'State: "waiting_checkpoint"', 'Checkpoint: "checkpoint"',
    `  Original CID: ${JSON.stringify(expected.checkpoint.checkpoint_cid)}`,
    'Stored Effect Preview (read-only; not approval):',
    '  Effect: "delete"  Target: "connector://salesforce/Opportunity"',
    '  Items: 1', '  Preview strength: "full_diff"', '  Changes:', '    Row: "006Acme"',
    `      Before: ${JSON.stringify({state: 'present', value: before})}`,
    '      After: {"state":"absent"}', '',
  ].join('\n');
  assert.deepEqual(requireNativeFileModelDeletePreview(stdout, fixture), expected);
  assert.throws(() => requireNativeFileModelDeletePreview(stdout.replace('006Acme', '006Globex'), fixture));
  assert.throws(() => requireNativeFileModelDeletePreview(stdout.replace('state":"absent', 'state":"present'), fixture));
});

test('Native File Model Effect acceptance compares approval, cold output and peer counters independently', () => {
  const fixture = nativeFileModelEffect('model-task:churn-risk.v1');
  const run_id = identity('run');
  const checkpoint = {checkpoint_id: 'checkpoint', checkpoint_cid: identity('checkpoint')};
  const waiting = {status: 'waiting_checkpoint', run_id, checkpoint};
  const names = ['adopt', 'check', 'run', 'waiting-status', 'approve', 'saved-status', 'saved-result'];
  const before = {bytes: fixture.before, sha256: hash(fixture.before), inode: '100'};
  const applied = {bytes: fixture.after, sha256: hash(fixture.after), inode: '101'};
  const observations = {
    run: [0, 1, 2].map(tag => attempt(tag, 'a')),
    approve: [attempt(5, 'b'), {tag: 6, ordinal: -1, identity: ''},
      {tag: 7, ordinal: -1, identity: ''}, attempt(8, 'b'), attempt(9, 'c'),
      attempt(10, 'd'), attempt(11, 'e')],
  };
  const baseline = {
    fixture, waiting, input: {notes: 'Acme Corp - Renewal', active_users: '17', trend: 'declining'},
    preview: structuredClone(waiting), completed: {status: 'succeeded', run_id},
    savedRows: [{id: '006Acme', outcome: 'ok', value: {level: 'high', reason: 'controlled File decision'}}],
    before, pending: {...before}, applied, afterSaved: {...applied},
    phases: names.map((phase, index) => {
      const sends = index < 2 ? 0 : 1;
      return {phase, pid: index + 10, firstClose: true, physicalRequests: sends,
        connections: {tcp: sends, tls: sends}, events: observations[phase] ?? []};
    }),
  };
  assert.equal(requireNativeFileModelEffectTrace(baseline).runId, run_id);
  for (const change of [
    state => {state.pending = applied;},
    state => {state.applied = before;},
    state => {state.afterSaved.inode = '102';},
    state => {state.input.notes = 'wrong Source';},
    state => {state.phases[4].physicalRequests = 2;},
    state => {state.phases[6].connections.tls = 2;},
    state => {state.phases[6].pid = state.phases[2].pid;},
    state => {state.phases[4].firstClose = false;},
    state => {state.phases[4].events.pop();},
    state => {state.preview.checkpoint.checkpoint_cid = identity('foreign');},
    state => {state.completed.run_id = identity('saved foreign');},
    state => {state.savedRows[0].value = {level: 'low', reason: 'different answer'};},
  ]) {
    const candidate = structuredClone(baseline);
    change(candidate);
    assert.throws(() => requireNativeFileModelEffectTrace(candidate), {code: 'ERR_ASSERTION'});
  }
});

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

test('Native dependent fixture passes the actual typed producer body through the exact receiving port', async () => {
  const source = JSON.parse(await readFile(new URL('./fixtures/public-model-task-signed64.json', import.meta.url)));
  const input = nativeDependentModelInput(source.output_schema);
  assert.deepEqual(input.fields.prior, {...source.output_schema, nullable: true});
  assert(!source.output_schema.nullable);
  const document = nativeDependentModelDocument(source.document, input);
  const {additional_properties, ...authored} = input.fields.prior;
  assert.equal(additional_properties, false);
  assert(document.includes('input:\n  prior: ' + canonicalText(authored) + '\ninstructions:'));
  const scenario = nativeDependentModelRun('fixture-a', 'fixture-b');
  const [, producer, receiver, finalUnit] = scenario.program.stages;
  assert.equal(producer.steps[1].infer.on_non_success, 'fail');
  assert.deepEqual(receiver.inputs, {rows: {result: {stage: 'first', result: 'rows'}}});
  assert.deepEqual(receiver.steps[1].infer.input, {prior: {field: 'value'}});
  assert.deepEqual(scenario.expectedReceiverInput, {prior: scenario.answers[0]});
  assert.deepEqual(Object.values(finalUnit.inputs).map(({result}) => result.stage), ['first', 'second']);
  scenario.answers[0].reason = 'unexpected reply';
  assert.equal(scenario.expectedReceiverInput.prior.reason, 'typed output of the first controlled Model');
  assert.equal(scenario.expectedRows[0].first_value.reason, 'typed output of the first controlled Model');
});

test('Native dependent policy binds the produced Schema and both exact original Model bindings', () => {
  const vendor = {installationRevision: {cid: identity('revision')}, configurationContract: {cid: identity('contract')}};
  const firstConfig = {model_defaults: {default_model: 'a'}, credential_ref: 'file:a.key'};
  const secondConfig = {model_defaults: {default_model: 'b'}, credential_ref: 'file:b.key'};
  const configuration_cid = identity(firstConfig);
  const first = {task: identity('Task A'), profile: identity('Profile A'), outputSchema: identity('Schema A'),
    binding: nativeModelBindingIdentity('models/http', vendor, firstConfig)};
  const second = {task: identity('Task B'), profile: identity('Profile B'), outputSchema: identity('Schema B'),
    binding: nativeModelBindingIdentity('models/http', vendor, secondConfig)};
  assert.equal(first.binding, identity({configuration_cid, provider_id: 'models/http',
    installation_revision_cid: vendor.installationRevision.cid, configuration_contract_cid: vendor.configurationContract.cid,
    version: 'actql-model-provider-binding/0.1'}));
  assert.deepEqual(nativeDependentModelOutputPolicy(first, second), {
    version: 'actql-local-model-output-policy/0.1', receiving_profile_cid: second.profile,
    receiving_task_cid: second.task, inputs: [{input_index: 0, producer_stage: 1, producer_step: 1,
      producer_task_cid: first.task, producer_binding_cid: first.binding, producer_schema_cid: first.outputSchema,
      producer_profile_cid: first.profile, receiving_binding_cid: second.binding, classification: 'internal'}],
  });
  assert.throws(() => nativeDependentModelOutputPolicy(first, {...second, binding: first.binding}), {code: 'ERR_ASSERTION'});
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

function deliveryFixture({receiverRateLimited = false, includeReview = false, aliasesAnswer = false} = {}) {
  const fixture = receiverRateLimited ? nativeDependentModelRun('test-a', 'test-b', {receiverRateLimited}) :
    nativeJoinedModelRun('test-a', 'test-b', {includeReview});
  const {expectedRows: rows, finalResultPolicy, additionalResults = {}} = fixture;
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
  const observedModels = receiverRateLimited ? modelEvidence.slice(0, 1) : modelEvidence;
  const runReceipt = seal({version: 'actql-run-receipt/0.1', invocation_cid: invocation,
    result_manifest_cid: manifest.result_manifest_cid, result_manifest: manifest, result_artifacts: manifest.results,
    source_evidence_cids: sourceEvidence,
    external_observation_evidence: [
      ...sourceEvidence.map(evidence_cid => ({kind: 'source_lookup', evidence_cid})),
      ...observedModels.map(evidence_cid => ({kind: 'model_invocation', evidence_cid})),
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
  const custody = {definition, runId, observed: modelEvidence.map((evidenceCid, index) => ({
    task: index === 0 ? 'test-a' : 'test-b',
    evidence: receiverRateLimited && index === 1 ?
      [{role: 'model_raw_response', evidenceCid: identity('receiver rejected Raw')}] :
      [{role: 'model_invocation_evidence', evidenceCid}],
  }))};
  return {report, runReceipt, outputs, rows, policyCid, custody, additionalResults,
    failedModelTask: receiverRateLimited ? 'test-b' : null};
}

test('Native JOIN delivery verifies the typed file independently of the saved Run availability projection', () => {
  const fixture = deliveryFixture();
  const result = requireNativeJoinedDelivery(fixture);
  assert.equal(result.bytes, fixture.outputs.answer.payload.length);
  assert.equal(result.sha256, hash(fixture.outputs.answer.payload));
  assert.equal(result.runReceiptCid, fixture.runReceipt.receipt_identity_cid);
});

test('dependent JOIN delivery proves B RateLimit in the typed Result without a successful B invocation', () => {
  const fixture = deliveryFixture({receiverRateLimited: true});
  const {program, expectedReceiverInput} = nativeDependentModelRun('test-a', 'test-b', {receiverRateLimited: true});
  const [, producer, receiver] = program.stages;
  assert.equal(producer.steps[1].infer.on_non_success, 'fail');
  assert.equal(receiver.steps[1].infer.on_non_success, 'outcomes');
  assert.deepEqual(receiver.steps[1].infer.input, {prior: {field: 'value'}});
  const [row] = fixture.rows;
  assert.deepEqual(expectedReceiverInput, {prior: row.first_value});
  assert.deepEqual([row.first_outcome, row.second_outcome, row.second_value], ['ok', 'failed:rate_limit', null]);
  assert.equal(requireNativeJoinedDelivery(fixture).bytes, fixture.outputs.answer.payload.length);
  const [first, second] = fixture.custody.observed;
  const inventedSuccess = {role: 'model_invocation_evidence', evidenceCid: identity('foreign B')};
  for (const evidence of [[], [...second.evidence, inventedSuccess]]) {
    const custody = {...fixture.custody, observed: [first, {...second, evidence}]};
    assert.throws(() => requireNativeJoinedDelivery({...fixture, custody}), {code: 'ERR_ASSERTION'});
  }
  const {receipt_identity_cid, ...body} = fixture.runReceipt;
  assert(receipt_identity_cid);
  const runReceipt = seal({...body, external_observation_evidence: [
    ...body.external_observation_evidence, {kind: 'model_invocation', evidence_cid: identity('invented B')},
  ]}, 'receipt_identity_cid');
  assert.throws(() => requireNativeJoinedDelivery({...fixture, runReceipt}), {code: 'ERR_ASSERTION'});
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

async function controlledModelReply(t, inspect) {
  const observed = Promise.withResolvers();
  const server = createServer(async (incoming, reply) => {
    try {
      const chunks = [];
      for await (const chunk of incoming) chunks.push(chunk);
      assert.equal(Buffer.concat(chunks).toString('utf8'), 'original Model input');
      const custody = await dropNativeDependentModelReply(incoming, reply, () => inspect(incoming.socket, reply));
      observed.resolve({custody});
    } catch (error) {
      observed.resolve({error});
      reply.destroy();
    }
  });
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  const listening = once(server, 'listening');
  server.listen({host: '127.0.0.1', port: 0});
  await listening;
  const client = request({host: '127.0.0.1', port: server.address().port, method: 'POST'});
  const clientOutcome = new Promise(resolve => {
    client.once('error', error => resolve({error}));
    client.once('response', received => {received.resume(); resolve({status: received.statusCode});});
  });
  client.end('original Model input');
  return {client, clientOutcome, observed: observed.promise};
}

test('the controlled Model reply drop owns the still-open original socket and emits no response headers',
  {timeout: 5000}, async t => {
    const custody = {aSettlement: identity('original committed A'), bEntry: identity('original entered B')};
    const actor = await controlledModelReply(t, (socket, reply) => {
      assert.strictEqual(reply.socket, socket);
      assert.equal(reply.headersSent, false);
      assert.equal(socket.destroyed, false);
      return custody;
    });
    assert.strictEqual((await actor.observed).custody, custody);
    assert.equal((await actor.clientOutcome).error?.code, 'ECONNRESET');
  });

test('a Model peer disconnect during the custody read cannot count as the controlled reply drop',
  {timeout: 5000}, async t => {
    const started = Promise.withResolvers();
    const actor = await controlledModelReply(t, async socket => {
      const closed = once(socket, 'close');
      started.resolve();
      await closed;
      return {aSettlement: identity('already completed A')};
    });
    await started.promise;
    actor.client.destroy();
    const {error} = await actor.observed;
    assert.match(error.message, /disconnected or started a reply before the controlled drop/u);
    assert.equal((await actor.clientOutcome).error?.code, 'ECONNRESET');
  });

test('a Model reply which already started cannot count as the controlled reply drop', {timeout: 5000}, async t => {
  const actor = await controlledModelReply(t, (_socket, reply) => {
    reply.writeHead(200);
    reply.flushHeaders();
    return {aSettlement: identity('already completed A')};
  });
  const {error} = await actor.observed;
  assert.match(error.message, /disconnected or started a reply before the controlled drop/u);
  await actor.clientOutcome;
});

test('the controlled Model reply drop preserves the original custody failure', {timeout: 5000}, async t => {
  const original = new Error('original scoped custody refusal');
  const actor = await controlledModelReply(t, async () => {throw original;});
  assert.strictEqual((await actor.observed).error, original);
  await actor.clientOutcome;
});
