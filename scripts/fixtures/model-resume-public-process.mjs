// Real installed Host acceptance process. Only provider I/O is a deterministic
// local fixture; authorization, Model/Core issuance, journal and Store are real.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
const options = JSON.parse(readFileSync(0, 'utf8'));
// Source and packed acceptance supply ordinary public entry points explicitly.
// A missing installation is an error, never a fallback to checkout internals.
const {runtime} = options;
assert.ok(runtime && typeof runtime.client === 'string' &&
  typeof runtime.httpHost === 'string' && typeof runtime.environment === 'string');
// The real request Journal retains its physical exec original when opening.
// Install this fixture fault before that capture, then arm only the selected
// final cancellation transaction without replacing a live connection method.
const originalSqliteExec = DatabaseSync.prototype.exec;
let cancellationCommitFault;
if (options.commitLoss !== undefined) DatabaseSync.prototype.exec = function(sql) {
  return (cancellationCommitFault ?? originalSqliteExec).call(this, sql);
};
const {connect, RequestHeld} = await import(runtime.client);
const {openInstalledRemoteHttpHost} = await import(runtime.httpHost);
const {canonical, cid, configuration} = await import(runtime.inferFixture);
const {providerBindingOriginals} = await import(runtime.providerFixture);
const {root, phase, transport = 'local', count = 1, acquired = false,
  checkpointTtlMs = 120_000, providerRevision = 'public-model-fixture-1'} = options;
const historicalSource = acquired && options.sourceDelegate && options.historicalSource === true;
const owner = userInfo().username;
const path = name => join(root, name);
mkdirSync(root, {recursive: true});
const read = name => JSON.parse(readFileSync(path(name), 'utf8'));
const save = (name, value) => writeFileSync(path(name), JSON.stringify(value));
const calls = () => existsSync(path('provider-calls.jsonl'))
  ? readFileSync(path('provider-calls.jsonl'), 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
const log = (name, value) => appendFileSync(path(name), `${JSON.stringify(value)}\n`);
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
if (!existsSync(path('keys.json'))) {
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  writeFileSync(path('keys.json'), JSON.stringify({reviewerPrivate: pem(reviewer.privateKey),
    reviewerPublic: pem(reviewer.publicKey), hostPrivate: pem(host.privateKey)}), {mode: 0o600});
}
const keys = read('keys.json');
const signer = {keyId: 'model-reviewer-key', reviewerId: 'model-reviewer',
  sign: bytes => sign(null, bytes, keys.reviewerPrivate)};
const base = JSON.parse(readFileSync(runtime.environment, 'utf8'));
const configured = configuration(base);
const environment = JSON.parse(configured.installation.environmentWire);
const {contract_cid: ignoredTask, ...task} = environment.model_task_contracts[0];
void ignoredTask;
task.max_items = count;
const taskCid = cid(task);
environment.model_task_contracts = [{...task, contract_cid: taskCid}];
delete environment.evidence_bundle_cid;
const {self_cid: ignoredExecution, ...execution} = JSON.parse(configured.installation.executionContracts[0].bodyWire);
void ignoredExecution;
Object.assign(execution, {model_task_contract_cid: taskCid, max_total_attempts: count,
  max_total_duration_ms: 500 * count, max_total_wire_bytes: 66536 * count,
  max_total_token_reservation: 33 * count});
const modelInstallation = Object.freeze({...configured.installation,
  environmentWire: canonical({...environment, evidence_bundle_cid: cid(environment)}),
  executionContracts: Object.freeze([Object.freeze({modelTaskCid: taskCid, cid: cid(execution),
    bodyWire: canonical({...execution, self_cid: cid(execution)})})])});
const fixtureInputs = options.inputTexts ?? ['alpha', 'bravo', 'charlie'].slice(0, count);
assert.equal(fixtureInputs.length, count);
assert.equal(new Set(fixtureInputs).size, count);
const fixtureRisk = new Map(fixtureInputs.map((text, index) =>
  [text, ['high', 'low', 'medium'][index]]));
const program = {version: 'actql/0.1', id: 'public-model-resume', stages: [{id: 'main',
  inputs: acquired ? {source: {connector: 'crm/main', resource: 'r'}} : {},
  steps: [
    ...(acquired ? [{filter: 'id = id'}, {select: ['id', 'amount']}] : [
      {values: {schema: {id: {type: 'string', nullable: false}, text: {type: 'string', nullable: true}},
        rows: fixtureInputs.map((text, index) => ({id: String(index + 1), text}))}, as: 'input'}]),
    {assert_rows: {unique_by: ['id']}},
    {infer: {contract: 'model-task:packed-risk.v1', key: 'id',
      input: {text: {field: acquired ? 'amount' : 'text'}},
      on_non_success: options.onNonSuccess ?? 'outcomes'}, as: 'captured'},
  ], results: {captured: {from: 'captured', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}}};
const entry = (id, operation, outcome) => ({entry_id: id, outcome,
  principal: {all: true}, connection: {all: true}, resource: {all: true},
  operation: {any_of: [operation]}, exclusions: []});
const accountConfiguration = canonical({version: 'actql-execution-account-config/0.1',
  account_id: 'public-model-owner', entries: [entry('run', 'write', 'allow'),
    entry('model', 'infer', options.denyInfer ? 'deny' : options.immediate ? 'allow' : 'delegate'),
    entry('effect', 'effect', 'delegate'),
    {entry_id: 'read-original', outcome: 'allow', principal: {any_of: [owner]},
      connection: {all: true}, resource: {any_of: ['result/answer', 'run']},
      operation: {any_of: ['read']}, exclusions: []}].sort((left, right) =>
      left.entry_id < right.entry_id ? -1 : left.entry_id > right.entry_id ? 1 : 0)});

// This database contains only the independently authored fixture rows. Reissue
// its policy/schema declaration graph, never relabel captured provider bytes.
let sourceProfilePath;
let sourceObservation;
if (acquired) {
  const {observeTwoSourceProvider} = await import(runtime.sourceObserver);
  const source = JSON.parse(readFileSync(runtime.sourceEnvironment, 'utf8'));
  const policy = source.contract_registry.find(value => value.kind === 'data_policy');
  const {cid: oldPolicy, ...policyBody} = policy;
  assert.equal(cid(policyBody), oldPolicy);
  policy.body.classification = 'public';
  policy.cid = cid(policyBody);
  const schema = source.contract_registry.find(value => value.kind === 'carrier_schema');
  const {cid: oldSchema, ...schemaBody} = schema;
  assert.equal(cid(schemaBody), oldSchema);
  schema.body.fields.amount = {nullable: true, type: 'string'};
  schema.cid = cid(schemaBody);
  const view = source.source_views[0];
  const {contract_cid: oldView, ...viewBody} = view;
  assert.equal(cid(viewBody), oldView);
  view.output.data_policy.cid = policy.cid;
  view.output.schema.cid = schema.cid;
  view.contract_cid = cid(viewBody);
  const catalog = source.connector_catalogs[0];
  catalog.contracts = source.contract_registry.map(value => structuredClone(value))
    .sort((left, right) => left.cid < right.cid ? -1 : left.cid > right.cid ? 1 : 0);
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = cid(catalog);
  for (const capability of source.connector_capabilities) {
    capability.source_contract_cid = view.contract_cid;
    capability.source_view_contract_cid = view.contract_cid;
    capability.capability_contract_cids.push('sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d');
    capability.capability_contract_cids.sort();
  }
  for (const snapshot of source.schema_snapshots) Object.assign(snapshot, {
    carrier_schema_contract_cid: schema.cid, source_contract_cid: view.contract_cid,
    source_view_contract_cid: view.contract_cid, source_data_policy_cid: policy.cid,
    data_classification: 'public'});
  source.host_policy_profile = base.host_policy_profile;
  delete source.evidence_bundle_cid;
  source.evidence_bundle_cid = cid(source);
  const database = path('records.duckdb');
  const initialize = !existsSync(database);
  const duckdb = createRequire(runtime.duckdbPackage)('@duckdb/node-api');
  const {DuckDBInstance} = duckdb;
  if (initialize || options.changeSource) {
    const instance = await DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      if (initialize) {
        await connection.run('CREATE TABLE records(id DOUBLE, amount VARCHAR)');
        for (const [index, text] of fixtureInputs.entries()) await connection.run(
          `INSERT INTO records VALUES (${index + 1}, '${text}')`);
      } else await connection.run("UPDATE records SET amount = 'changed-after-model-wait'");
    } finally { connection.closeSync(); instance.closeSync(); }
  }
  sourceObservation = observeTwoSourceProvider(duckdb, {source: database});
  sourceProfilePath = path('source-profile.json');
  writeFileSync(sourceProfilePath, canonical({version: 'actql-installed-duckdb-source/0.1',
    database, schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    checkEnvironmentWire: canonical(source), accountConfigurationWire: canonical({
      version: 'actql-execution-account-config/0.1', account_id: 'public-model-source',
      entries: [entry('read-source', 'read', options.sourceDelegate ? 'delegate' : 'allow')]}),
  }));
}

let run;
let client;
let host;
let server;
const observations = [];
const output = value => save(`${phase}-result.json`, {...value, calls: calls().length,
  observations, source: sourceObservation?.snapshot(), ref: run?.ref ?? (existsSync(path('run.json')) ? read('run.json') : undefined)});
const crash = (boundary, detail) => {
  output({boundary, detail});
  process.exit(77);
};
const authorization = {accountConfiguration, checkpointTtlMs, leaseMs: 1000,
  ...(options.permitModel ? {decide: view => ({decision: 'permit', subject: view.subject,
    authority: 'model-reviewer', claims: [...view.requiredClaims]})} : {}),
  hostKey: {keyId: 'model-host-key', privateKey: keys.hostPrivate},
  reviewers: [{keyId: signer.keyId, reviewerId: signer.reviewerId,
    principalId: owner, publicKey: keys.reviewerPublic},
    {keyId: 'metadata-reviewer-key', reviewerId: 'metadata-reviewer',
      principalId: 'fixture-metadata-only', publicKey: keys.reviewerPublic}],
  reviewReaders: [owner],
  observe(name, detail) {
    observations.push({name, detail});
  },
  async faultInjection(name, detail) {
    if (phase === 'cancel-before-stop' && name === 'infer_waiting_checkpoint') {
      while (run === undefined) await new Promise(resolve => setImmediate(resolve));
      await run.cancel();
      await run.cancel();
      save('cancel-before-stop-observation.json', await run.status());
    }
    if (phase === 'cancel-before-stop-commit-loss' && name === 'infer_waiting_checkpoint') {
      while (run === undefined) await new Promise(resolve => setImmediate(resolve));
      const recovery = await cancelWithCommitReplyLoss();
      // The real driver remains inside its waiting hook. Acceptance and exact
      // operation lookup cannot substitute for its later physical stop receipt.
      save('cancel-before-stop-observation.json', {state: await run.status(), recovery});
    }
    if ((phase === 'approve-crash-saved' || phase === 'immediate-crash-saved') &&
        name === 'infer_model_settlement_committed' && detail.slot === 0) crash(name, detail);
    if (phase === 'approve-crash-response' &&
        name === 'infer_model_response_stored' && detail.slot === 0) crash(name, detail);
    if (['approve-cancel-saved', 'immediate-cancel-saved'].includes(phase) && name === 'infer_model_settlement_committed' &&
        detail.slot === 0) await run.cancel();
  }};
let diagnosticMoon;
const checked = value => { assert.equal(value?.$tag, 1); return value._0; };
const installation = {directory: path('host'), modelInstallation, authorization,
  hostCapacityPolicy: base.host_policy_profile.capacity,
  ...(sourceProfilePath === undefined ? {} : {sourceProfilePath}),
  registerModelProviders: moon => {
    diagnosticMoon = moon;
    return [{providerId: 'models/packed',
    bindingOriginals: providerBindingOriginals('models/packed', {
      revision: providerRevision, selector: 'packed-risk-model'}),
    invoke() { throw new Error('UnpreparedPublicModelCall'); },
    validatePrompt(actual, selector, wire) {
      return actual === taskCid && selector === 'packed-risk-model' &&
        JSON.parse(wire).format === 'packed-risk/0.1';
    },
    quantityCapacity: {limits: {tokens: BigInt(33 * count), costUnits: 0n, durationMs: BigInt(500 * count)},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: options.denyEgress ? 'unknown' : 'public', _1: 'fixture-region', _2: false, _3: false}),
    physicalPreflight: request => moon.clientProgramModelRequestPreflight(
      () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
        request, 1000n, 33n, 0n, 500n, () => {
          const text = JSON.parse(moon.clientProgramModelRequestInput(request, 'text'));
          assert.ok(fixtureInputs.includes(text), `The fixed input changed: ${text}`);
          assert.ok(!calls().some(value => value.text === text), `Duplicate physical send: ${text}`);
          log('provider-calls.jsonl', {text, providerRevision, phase});
          if (options.providerReplyLoss === 'crash') crash('provider_response_lost', {text});
          if (['approve-crash-unknown', 'immediate-crash-unknown'].includes(phase) &&
              text === 'bravo') crash('provider_response_lost', {text});
          return moon.clientProgramModelResponse(request, JSON.stringify({reason: null, risk: fixtureRisk.get(text)}),
            'packed-risk-model', options.inputTexts === undefined ? `public-request-${text}` :
              `public-request-${fixtureInputs.indexOf(text)}`, 1n, options.usageOverflow ? 1000n : 2n, new Date().toISOString());
        }))}), () => true),
  }];
  }};
// Optional observation acceptance reuses this real public lifecycle. It does
// not replace the Model/Checkpoint fixtures or manufacture any Owner facts.
let telemetry, telemetryContext;
if (options.observation !== undefined) {
  const {createNodeHostObservability} = await import(runtime.observation);
  telemetry = createNodeHostObservability({endpoint: options.observation.endpoint,
    logs: {endpoint: `${options.observation.endpoint}/v1/logs`}});
  installation.observation = telemetry.connection;
  const {context, trace, ROOT_CONTEXT} = await import(runtime.contextApi);
  const {AsyncLocalStorageContextManager} = await import(runtime.contextManager);
  const manager = new AsyncLocalStorageContextManager().enable();
  assert.equal(context.setGlobalContextManager(manager), true);
  // This is application-owned ingress context, not an authorization claim.
  telemetryContext = {context, manager, parent: trace.setSpanContext(ROOT_CONTEXT,
    options.observation.parent)};
}
async function assertSeparateReviewDisclosure(summary) {
  if (transport !== 'https') return;
  const metadata = await connect({mode: 'remote', durability: 'durable',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-metadata-only'});
  try {
    const page = await metadata.checkpoints();
    for (const item of page.items) {
      assert.equal(item.reviewWire, undefined);
      assert.equal(item.slotWires, undefined);
      assert.equal(item.inputArtifactWire, undefined);
    }
    await assert.rejects(metadata.reviewCheckpoint(summary), {code: 'CheckpointReviewDenied'});
  } finally { await metadata.close(); }
}
const deadline = Date.now() + 20_000;
async function until(check) {
  do {
    const value = await check();
    if (value) return value;
    if ((await run?.status())?.status === 'failed') throw new Error(`Unexpected failed Run: ${JSON.stringify(observations)}`);
    await new Promise(resolve => setTimeout(resolve, 20));
  } while (Date.now() < deadline);
  throw new Error(`PublicModelBoundaryTimeout: ${JSON.stringify(observations.slice(-12))}`);
}
async function unknownRunRetained() {
  const state = await run.status();
  const database = new DatabaseSync(path('host/checkpoints/journal/checkpoint-journal.sqlite3'),
    {readOnly: true});
  try {
    const retained = database.prepare('SELECT status FROM runs WHERE run_id = ?').get(state.run_id);
    return state.status === 'needs_reconciliation' && retained?.status === 'needs_reconciliation'
      ? state : undefined;
  } finally { database.close(); }
}
async function cancelWithCommitReplyLoss() {
  const before = await run.status();
  const cancelRef = {...run.ref, cancelId: 'model-commit-original-cancel',
    expectedRevision: before.control.revision};
  save('cancel-ref.json', cancelRef);
  let lost = false;
  cancellationCommitFault = function(sql) {
    const outcome = sql === 'COMMIT' && !lost && this.prepare(
      "SELECT name FROM sqlite_master WHERE name = 'client_cancellation_operations'").get() !== undefined
      ? this.prepare('SELECT outcome_wire FROM client_cancellation_operations WHERE cancel_id = ?')
        .get(cancelRef.cancelId)?.outcome_wire : undefined;
    // Fault the final request-journal transaction, not the earlier pending
    // identity or the independent Model fence transaction.
    if (outcome != null) {
      lost = true;
      if (options.commitLoss === 'after') originalSqliteExec.call(this, sql);
      throw new Error('FixtureCancelCommitReplyLost');
    }
    return originalSqliteExec.call(this, sql);
  };
  try {
    await assert.rejects(run.cancel({cancelId: cancelRef.cancelId,
      expectedRevision: cancelRef.expectedRevision}), error => {
      assert.equal(error.code, 'CancellationUnknown');
      assert.deepEqual(error.cancelRef, cancelRef);
      return true;
    });
    assert.equal(lost, true, 'the final original cancellation COMMIT was observed');
  } finally { cancellationCommitFault = undefined; }
  const first = await run.lookupCancellation(cancelRef);
  const second = await run.lookupCancellation(cancelRef);
  assert.deepEqual(second, first);
  return {cancelRef, first, second, unknownCode: 'CancellationUnknown'};
}
const execute = async () => { try {
  const open = async () => {
  if (transport === 'https') {
    setDefaultCACertificates([...getCACertificates('default'), readFileSync(path('host.crt'), 'utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer fixture-owner' ? owner :
        header === 'Bearer fixture-metadata-only' ? 'fixture-metadata-only' : undefined});
    server = createServer({key: readFileSync(path('host.key')), cert: readFileSync(path('host.crt'))}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-owner',
      ...(telemetry === undefined ? {} : {traceContext: () => options.observation.parent})});
  } else client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  };
  if (telemetryContext === undefined) await open();
  else await telemetryContext.context.with(telemetryContext.parent, open);
  try {
    if (historicalSource) {
      if (phase === 'wait-source') {
        // Author only an unresolved historical-format Source original while
        // all public Host owners are closed. This is current recovery
        // coverage, not a claim of earlier public-Host acceptance.
        assert.equal(existsSync(path('historical-source.json')), false);
        await client.close(); client = undefined;
        if (server) {
          server.closeAllConnections();
          await new Promise(resolve => server.close(resolve)); server = undefined;
        }
        await host?.close(); host = undefined;
        assert.equal(typeof runtime.root, 'string');
        const {writeSyntheticHistoricalHeldQuery} = await import('./synthetic-historical-held-query.mjs');
        const original = await writeSyntheticHistoricalHeldQuery({directory: installation.directory,
          document: JSON.stringify(program), requestId: 'historical-public-model-resume', authorization,
          sourceProfile: JSON.parse(readFileSync(sourceProfilePath, 'utf8')),
          runtimeRootUrl: new URL(runtime.root), mode: transport === 'https' ? 'remote' : 'local',
          modelEnvironmentWire: modelInstallation.environmentWire});
        save('historical-source.json', original);
        await open();
      }
      const original = read('historical-source.json');
      assert.equal(original.kind, 'synthetic_historical_format');
      const found = await client.lookupRequest(original.requestId);
      if (found.kind === 'found') run = await client.attach(found.ref);
      else {
        assert.equal(found.kind, 'held');
        assert.ok(['wait-source', 'approve-source'].includes(phase));
        assert.equal(found.checkpoint.checkpointCid, original.checkpointCid);
      }
      if (run !== undefined) {
        if (existsSync(path('run.json'))) assert.deepEqual(run.ref, read('run.json'));
        else save('run.json', run.ref);
      }
    } else {
      const lookupOnly = phase === 'lookup-cancel-fence-loss' || phase === 'lookup-cancel-commit-loss';
      if (!existsSync(path('submission-ref.json'))) {
        assert.equal(lookupOnly, false, 'original cancellation lookup must retain submission custody');
        save('submission-ref.json', client.newSubmission({nonce: 'public-model-resume'}));
      }
      const submissionRef = read('submission-ref.json');
      run = phase === 'lookup-cancel-fence-loss' || phase === 'lookup-cancel-commit-loss'
        ? await client.attach(read('run.json'))
        : await client.start(program, {submissionRef});
      if (existsSync(path('run.json'))) {
        const original = read('run.json');
        assert.deepEqual(run.ref, original);
      } else save('run.json', run.ref);
    }
  } catch (error) {
    if (!(error instanceof RequestHeld)) {
      // Failure-only diagnostic through the real Core reader. Public check()
      // accepts text/SQL, so it cannot diagnose this JSON Program directly.
      // This never substitutes for public submission or establishes a pass.
      if (!acquired && diagnosticMoon !== undefined) {
        try {
          const wire = modelInstallation.environmentWire;
          const environment = diagnosticMoon.clientProgramCheckEnvironment(wire,
            JSON.parse(wire).evidence_bundle_cid,
            false, false, true, false, false, false, false);
          assert.ok(environment, 'DiagnosticModelEnvironmentRejected');
          const outcome = diagnosticMoon.clientProgramPrepareEffectFreeWithParameters(
            JSON.stringify(program), 'json', environment, undefined);
          observations.push({name: 'core_json_preparation_diagnostic', detail: {
            code: diagnosticMoon.clientProgramPreparationIssueCode(outcome),
            issue: inspect(diagnosticMoon.clientProgramPreparationIssue(outcome), {depth: 10}),
          }});
        } catch (checkError) {
          observations.push({name: 'core_json_preparation_diagnostic_failed',
            detail: {code: checkError.code, message: checkError.message}});
        }
      }
      throw error;
    }
    assert.equal(acquired && options.sourceDelegate, true);
  }
  if (phase === 'wait' || phase === 'wait-source') {
    const expectedKind = phase === 'wait-source' ? 'read_access' : 'model_invocation';
    const summary = await until(async () => (await client.checkpoints()).items.find(item => item.kind === expectedKind));
    const reviewWire = new TextDecoder().decode((await client.reviewCheckpoint(summary)).bytes);
    if (historicalSource && expectedKind === 'read_access') {
      assert.equal(reviewWire, read('historical-source.json').reviewWire);
    }
    const review = JSON.parse(reviewWire);
    save(`${expectedKind}-summary.json`, summary);
    await assertSeparateReviewDisclosure(summary);
    assert.equal(calls().length, options.expectedPriorCalls ?? 0);
    if (expectedKind === 'model_invocation') {
      assert.equal(typeof summary.subject.runId, 'string');
      assert.ok(summary.subject.runId.length > 0);
      assert.equal(summary.subject.runDefinitionCid, run.ref.runDefinitionCid);
      assert.equal(summary.requiredArtifact.type, 'model_invocation_scope');
      assert.deepEqual(summary.requirements, ['invocation_scope_approved']);
      assert.equal(review.displayed_scope.model_invocation_scope_cid, summary.requiredArtifact.cid);
      assert.equal(review.displayed_scope.model_call_slot_cids.length, count);
    }
    if (expectedKind === 'model_invocation' && options.assertModelInputReleased) {
      await until(() => observations.filter(value => value.name === 'model_input_custody_changed')
        .at(-1)?.detail.retainedInputs === 0);
    }
    const state = run === undefined ? undefined : await run.status();
    if (state !== undefined) assert.equal(state.run_id, summary.subject.runId);
    output({summary, review, runId: state?.run_id, status: state?.status ?? 'held',
      ...(historicalSource ? {originalKind: read('historical-source.json').kind} : {})});
  } else {
    let resolution;
    let cancellationRecovery;
    if (phase.startsWith('approve') || phase === 'reject') {
      const kind = phase === 'approve-source' ? 'read_access' : 'model_invocation';
      const summary = read(`${kind}-summary.json`);
      resolution = await client.resolveCheckpoints([{checkpoint: summary,
        decision: phase === 'reject' ? 'rejected' : 'approved'}], {signer});
      save(`${kind}-signed.json`, resolution.signed);
      assert.equal(resolution.results[0].status, 'committed');
    } else if (phase === 'duplicate') {
      resolution = await client.resolveCheckpoints(read('model_invocation-signed.json'));
    } else if (phase === 'cancel' || phase === 'cancel-unknown') await run.cancel();
    else if (phase === 'cancel-fence-loss') {
      const before = await run.status();
      const cancelRef = {...run.ref, cancelId: 'model-fence-original-cancel',
        expectedRevision: before.control.revision};
      save('cancel-ref.json', cancelRef);
      // Lose only the actual Model fence COMMIT acknowledgement. The separate
      // request journal has already retained the pending operation identity.
      const originalExec = DatabaseSync.prototype.exec;
      let lost = false;
      DatabaseSync.prototype.exec = function(sql) {
        const fence = sql === 'COMMIT' && !lost && this.prepare(
          "SELECT name FROM sqlite_master WHERE name = 'run_cancellation_fences'").get() !== undefined
          ? this.prepare('SELECT run_id FROM run_cancellation_fences WHERE run_id = ?')
            .get(before.run_id) : undefined;
        const result = originalExec.call(this, sql);
        if (fence !== undefined) {
          lost = true;
          throw new Error('FixtureModelFenceCommitReplyLost');
        }
        return result;
      };
      try {
        await assert.rejects(run.cancel({cancelId: cancelRef.cancelId,
          expectedRevision: cancelRef.expectedRevision}), error => {
          assert.equal(error.code, 'CancellationUnknown');
          assert.deepEqual(error.cancelRef, cancelRef);
          cancellationRecovery = {cancelRef, unknownCode: error.code};
          return true;
        });
        assert.equal(lost, true, 'the real Model fence commit was observed');
      } finally { DatabaseSync.prototype.exec = originalExec; }
    } else if (phase === 'cancel-commit-loss' || phase === 'cancel-before-stop-commit-loss') {
      cancellationRecovery = phase === 'cancel-commit-loss' ? await cancelWithCommitReplyLoss()
        : (await until(() => existsSync(path('cancel-before-stop-observation.json'))
          ? read('cancel-before-stop-observation.json') : undefined)).recovery;
      if (options.providerReplyLoss) await until(unknownRunRetained);
      else if (options.commitLoss === 'after') await until(async () => {
        const state = await run.status();
        return state.status === 'cancelled' ? state : undefined;
      });
    } else if (phase === 'lookup-cancel-commit-loss') {
      const cancelRef = read('cancel-ref.json');
      const first = await run.lookupCancellation(cancelRef);
      const second = await run.lookupCancellation(cancelRef);
      assert.deepEqual(second, first);
      cancellationRecovery = {cancelRef, first, second};
      if (options.expectedModelUnknown) await until(unknownRunRetained);
    } else if (phase === 'lookup-cancel-fence-loss') {
      const cancelRef = read('cancel-ref.json');
      const first = await run.lookupCancellation(cancelRef);
      const second = await run.lookupCancellation(cancelRef);
      assert.deepEqual(first, {kind: 'unknown', cancelRef});
      assert.deepEqual(second, first);
      cancellationRecovery = {cancelRef, first, second};
    }
    if (cancellationRecovery !== undefined) {
      const state = await run.status();
      output({runId: state.run_id, status: state.status, control: state.control, cancellationRecovery});
    } else if (phase === 'approve-source') {
      const found = await until(async () => {
        const lookup = historicalSource
          ? await client.lookupRequest(read('historical-source.json').requestId)
          : await client.lookupSubmission(read('submission-ref.json'));
        return lookup.kind === (historicalSource ? 'found' : 'ready') ? lookup : undefined;
      });
      run = await client.attach(historicalSource ? found.ref : found.admission.ref);
      save('run.json', run.ref);
      const summary = await until(async () => (await client.checkpoints()).items.find(item => item.kind === 'model_invocation'));
      save('model_invocation-summary.json', summary);
      assert.equal(calls().length, 0, 'Source approval cannot authorize Model I/O');
      const state = await run.status();
      assert.equal(state.run_id, summary.subject.runId);
      output({summary, runId: state.run_id, status: state.status, resolution});
    } else if (phase === 'cancel-unknown') {
      const state = await until(async () => {
        const current = await run.status();
        return current.status === 'needs_reconciliation' ? current : undefined;
      });
      if (options.assertModelInputReleased) {
        await until(() => observations.filter(value => value.name === 'model_input_custody_changed')
          .at(-1)?.detail.retainedInputs === 0);
      }
      output({runId: state.run_id, status: state.status});
    } else if (phase === 'probe' || phase.endsWith('-probe')) {
      await new Promise(resolve => setTimeout(resolve, 250));
      const state = await run.status();
      output({runId: state.run_id, status: state.status});
    } else {
      const terminal = await until(async () => {
        const state = await run.wait({until: 'terminal', signal: AbortSignal.timeout(20_000)});
        return ['running', 'resuming', 'waiting_checkpoint'].includes(state.status) ||
          (phase.includes('cancel') || options.usageOverflow) && state.status === 'needs_reconciliation' ? undefined : state;
      });
      let rows;
      if (terminal.status === 'succeeded') rows = await run.result('answer').all();
      else await assert.rejects(run.result('answer').all());
      if (existsSync(path('model_invocation-summary.json')))
        await assertSeparateReviewDisclosure(read('model_invocation-summary.json'));
      output({runId: terminal.run_id, status: terminal.status, rows, resolution});
    }
  }
} catch (error) {
  output({state: await run?.status(), error: {name: error.name, code: error.code, message: error.message,
    cause: String(error.cause?.message ?? error.cause ?? '')}});
  throw error;
} finally {
  await client?.close();
  if (server !== undefined) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
  if (options.commitLoss !== undefined) DatabaseSync.prototype.exec = originalSqliteExec;
  if (telemetry !== undefined) {
    save(`${phase}-telemetry.json`, telemetry.status());
    await telemetry.close();
    telemetryContext.context.disable();
    telemetryContext.manager.disable();
  }
  sourceObservation?.restore();
} };
if (telemetryContext === undefined) await execute();
else await telemetryContext.context.with(telemetryContext.parent, execute);
