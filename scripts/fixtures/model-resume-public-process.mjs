// Real installed Host acceptance process. Only provider I/O is a deterministic
// local fixture; authorization, Model/Core issuance, journal and Store are real.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect, RequestHeld} from '../../packages/node/index.mjs';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';
import {canonical, cid, configuration} from './installed-infer-fixture.mjs';
import {providerBindingOriginals} from './model-provider-binding-fixture.mjs';
import {observeTwoSourceProvider} from './two-source-public-query.mjs';

const options = JSON.parse(readFileSync(0, 'utf8'));
const {root, phase, transport = 'local', count = 1, acquired = false,
  checkpointTtlMs = 120_000, providerRevision = 'public-model-fixture-1'} = options;
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
const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
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
const modelInstallation = {...configured.installation,
  environmentWire: canonical({...environment, evidence_bundle_cid: cid(environment)}),
  executionContracts: [{modelTaskCid: taskCid, cid: cid(execution),
    bodyWire: canonical({...execution, self_cid: cid(execution)})}]};
const fixtureInputs = ['alpha', 'bravo', 'charlie'].slice(0, count);
const fixtureRisk = {alpha: 'high', bravo: 'low', charlie: 'medium'};
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
    entry('effect', 'effect', 'delegate')].sort((left, right) =>
      left.entry_id < right.entry_id ? -1 : left.entry_id > right.entry_id ? 1 : 0)});

// This database contains only the independently authored fixture rows. Reissue
// its policy/schema declaration graph, never relabel captured provider bytes.
let sourceProfilePath;
let sourceObservation;
if (acquired) {
  const source = JSON.parse(readFileSync(new URL('../../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
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
    capability.capability_contract_cids.push('sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
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
  const duckdb = createRequire(new URL('../../adapters/connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
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
          if (phase === 'approve-crash-unknown' && text === 'bravo') crash('provider_response_lost', {text});
          return moon.clientProgramModelResponse(request, JSON.stringify({reason: null, risk: fixtureRisk[text]}),
            'packed-risk-model', `public-request-${text}`, 1n, options.usageOverflow ? 1000n : 2n, new Date().toISOString());
        }))}), () => true),
  }];
  }};
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
try {
  if (transport === 'https') {
    setDefaultCACertificates([...getCACertificates('default'), readFileSync(path('host.crt'), 'utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer fixture-owner' ? owner :
        header === 'Bearer fixture-metadata-only' ? 'fixture-metadata-only' : undefined});
    server = createServer({key: readFileSync(path('host.key')), cert: readFileSync(path('host.crt'))}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-owner'});
  } else client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  try {
    run = await client.start(program, {requestId: 'public-model-resume'});
    if (existsSync(path('run.json'))) {
      const original = read('run.json');
      assert.deepEqual(run.ref, original);
    } else save('run.json', run.ref);
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
    const review = JSON.parse(new TextDecoder().decode((await client.reviewCheckpoint(summary)).bytes));
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
    const state = run === undefined ? undefined : await run.status();
    if (state !== undefined) assert.equal(state.run_id, summary.subject.runId);
    output({summary, review, runId: state?.run_id, status: state?.status ?? 'held'});
  } else {
    let resolution;
    if (phase.startsWith('approve') || phase === 'reject') {
      const kind = phase === 'approve-source' ? 'read_access' : 'model_invocation';
      const summary = read(`${kind}-summary.json`);
      resolution = await client.resolveCheckpoints([{checkpoint: summary,
        decision: phase === 'reject' ? 'rejected' : 'approved'}], {signer});
      save(`${kind}-signed.json`, resolution.signed);
      assert.equal(resolution.results[0].status, 'committed');
    } else if (phase === 'duplicate') {
      resolution = await client.resolveCheckpoints(read('model_invocation-signed.json'));
    } else if (phase === 'cancel') await run.cancel();
    if (phase === 'approve-source') {
      const found = await until(async () => {
        const lookup = await client.lookupRequest('public-model-resume');
        return lookup.kind === 'found' ? lookup : undefined;
      });
      run = await client.attach(found.ref);
      save('run.json', run.ref);
      const summary = await until(async () => (await client.checkpoints()).items.find(item => item.kind === 'model_invocation'));
      save('model_invocation-summary.json', summary);
      assert.equal(calls().length, 0, 'Source approval cannot authorize Model I/O');
      const state = await run.status();
      assert.equal(state.run_id, summary.subject.runId);
      output({summary, runId: state.run_id, status: state.status, resolution});
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
  sourceObservation?.restore();
}
