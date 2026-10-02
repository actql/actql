// Independent application run from an installed package directory.
import assert from 'node:assert/strict';
import {appendFileSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {createDecipheriv, createHash, generateKeyPairSync} from 'node:crypto';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {connect} from '@actql/node';
import {canonical, cid, configuration, expected} from
  './installed-acquired-infer-fixture.mjs';

const mode = process.argv[2];
assert.ok(['success', 'cancel', 'capture', 'replay'].includes(mode));
const root = resolve(mode === 'replay' ? 'capture' : mode);
mkdirSync(root, {recursive: true});
const base = JSON.parse(readFileSync('base-environment.json', 'utf8'));
const environment = JSON.parse(readFileSync('source-environment.json', 'utf8'));
const policy = environment.contract_registry.find(item => item.kind === 'data_policy');
const {cid: oldPolicy, ...policyBody} = policy;
assert.equal(cid(policyBody), oldPolicy);
policy.body.classification = 'public';
policy.cid = cid({...policyBody, body: policy.body});
const schema = environment.contract_registry.find(item => item.kind === 'carrier_schema');
const {cid: oldSchema, ...schemaBody} = schema;
assert.equal(cid(schemaBody), oldSchema);
schema.body.fields.amount = {nullable: true, type: 'string'};
schema.cid = cid({...schemaBody, body: schema.body});
const view = environment.source_views[0];
const {contract_cid: oldView, ...viewBody} = view;
assert.equal(cid(viewBody), oldView);
view.output.data_policy.cid = policy.cid;
view.output.schema.cid = schema.cid;
view.contract_cid = cid({...viewBody, output: view.output});
const catalog = environment.connector_catalogs[0];
catalog.contracts = environment.contract_registry.map(item => structuredClone(item))
  .sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
catalog.source_views = [structuredClone(view)];
delete catalog.catalog_cid;
catalog.catalog_cid = cid(catalog);
for (const capability of environment.connector_capabilities) {
  capability.source_contract_cid = view.contract_cid;
  capability.source_view_contract_cid = view.contract_cid;
  capability.capability_contract_cids.push(
    'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
  capability.capability_contract_cids.sort();
}
for (const snapshot of environment.schema_snapshots) {
  snapshot.carrier_schema_contract_cid = schema.cid;
  snapshot.source_contract_cid = view.contract_cid;
  snapshot.source_view_contract_cid = view.contract_cid;
  snapshot.source_data_policy_cid = policy.cid;
  snapshot.data_classification = 'public';
}
environment.host_policy_profile = base.host_policy_profile;
delete environment.evidence_bundle_cid;
environment.evidence_bundle_cid = cid(environment);
const database = join(root, 'records.duckdb');
const {DuckDBInstance} = createRequire(new URL(
  './node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
const instance = await DuckDBInstance.create(database);
const connection = await instance.connect();
try {
  if (mode !== 'replay') {
    await connection.run('CREATE TABLE records(id DOUBLE, amount VARCHAR)');
    await connection.run("INSERT INTO records VALUES (1, 'urgent')");
  }
} finally {
  connection.closeSync();
  instance.closeSync();
}
const accountConfiguration = canonical({
  version: 'actql-execution-account-config/0.1', account_id: 'packed-infer-source',
  entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
    connection: {all: true}, resource: {all: true}, operation: {all: true},
    exclusions: []}],
});
writeFileSync(join(root, 'source-profile.json'), canonical({
  version: 'actql-installed-duckdb-source/0.1', database,
  schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
  checkEnvironmentWire: canonical(environment),
  accountConfigurationWire: accountConfiguration,
}));
const {installation, taskCid} = configuration(base);
const keyPath = join(root, 'fixture-keys.json');
const keys = mode === 'replay' ? JSON.parse(readFileSync(keyPath, 'utf8')) :
  (() => {
    const pair = generateKeyPairSync('ed25519');
    return {privateKey: pair.privateKey.export({type: 'pkcs8', format: 'pem'}),
      publicKey: pair.publicKey.export({type: 'spki', format: 'pem'})};
  })();
if (mode === 'capture') writeFileSync(keyPath, JSON.stringify(keys), {mode: 0o600});
let calls = 0;
let cancelled = false;
let run;
let started;
const startedRun = new Promise(resolve => { started = resolve; });
const authorization = {
  accountConfiguration,
  hostKey: {keyId: 'host', privateKey: keys.privateKey},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
    principalId: userInfo().username, publicKey: keys.publicKey}],
  async faultInjection(name) {
    if (mode === 'cancel' && calls === 1 && !cancelled &&
        name === 'infer_execution_advanced') {
      cancelled = true;
      await startedRun;
      await run.cancel();
    }
    if (mode === 'capture' && name === 'infer_capture_committed') {
      assert.equal(calls, 1);
      writeFileSync('capture-boundary.json', JSON.stringify({calls, name}));
      process.exit(0);
    }
  },
};
const checked = value => {
  assert.equal(value.$tag, 1);
  return value._0;
};
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: join(root, 'host'),
    sourceProfilePath: join(root, 'source-profile.json'),
    modelInstallation: installation, authorization,
    registerModelProviders: moon => [{providerId: 'models/packed',
      invoke() { throw new Error('UnpreparedModelCall'); },
      validatePrompt(actual, selector, wire) {
        return actual === taskCid &&
          selector === 'packed-acquired-risk-model' &&
          JSON.parse(wire).format === 'packed-acquired-risk/0.1';
      },
      quantityCapacity: {
        limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
        perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
      observeEgress: () => ({_0: 'public', _1: 'fixture-region',
        _2: false, _3: false}),
      physicalPreflight: request => moon.clientProgramModelRequestPreflight(
        () => ({_0: true,
          _1: checked(moon.clientProgramModelPhysicalRequestPlan(
            request, 1000n, 33n, 0n, 500n, () => {
              calls++;
              appendFileSync('provider-calls.jsonl', JSON.stringify({mode}) + '\n');
              assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
                '"urgent"');
              return moon.clientProgramModelResponse(request,
                '{"reason":null,"risk":"high"}', 'packed-acquired-risk-model',
                'packed-acquired-request', 1n, 2n, new Date().toISOString());
            }))}), () => true),
    }],
  }});
const program = {version: 'actql/0.1', id: 'packed-acquired-infer',
  stages: [{id: 'main', inputs: {source: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id = id'}, {select: ['id', 'amount']},
      {assert_rows: {unique_by: ['id']}},
      {infer: {contract: 'model-task:packed-acquired-risk.v1', key: 'id',
        input: {text: {field: 'amount'}}}, as: 'captured'}],
    results: {captured: {from: 'captured',
      fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}}};
try {
  run = await client.start(program, {requestId: 'packed-acquired-infer'});
  started();
  const terminal = await run.wait();
  assert.equal(terminal.status, mode === 'cancel' ? 'cancelled' : 'succeeded');
  if (mode === 'cancel') await assert.rejects(run.result('answer').all());
  else assert.deepEqual(await run.result('answer').all(), expected);
  assert.equal(calls, mode === 'replay' ? 0 : 1);
  const hostRoot = join(root, 'host');
  const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root: hostRoot,
    principalId: userInfo().username})).digest('hex')}`;
  for (const role of ['source_evidence', 'model_attempt_accounting',
    'model_attempt_outcome', 'model_dispatch_authority']) {
    const holding = cid({role, slot: 0,
      run_definition_cid: run.ref.runDefinitionCid,
      store_authority_cid: storeCid,
      version: 'actql-model-private-holding/0.1'});
    const record = JSON.parse(readFileSync(join(hostRoot, 'publication',
      'physical-holdings', `${holding.slice(7)}.json`), 'utf8'));
    assert.equal(record.holding_cid, holding);
    assert.equal(record.namespace, 'publication-private');
    assert.equal(record.objects.length, 1);
    const object = record.objects[0];
    const bytes = readFileSync(join(hostRoot, 'publication', 'objects',
      object.cid.slice(7)));
    assert.equal(bytes.byteLength, object.byte_count);
    assert.equal(`sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      object.cid);
    const envelope = JSON.parse(bytes);
    assert.equal(envelope.version, 'actql-private-publication-evidence/0.1');
    const key = readFileSync(join(hostRoot, 'checkpoints', 'private-evidence.key'));
    let evidence;
    try {
      const decipher = createDecipheriv('aes-256-gcm', key,
        Buffer.from(envelope.nonce, 'base64'));
      decipher.setAAD(Buffer.from(
        `actql-private-publication-evidence/0.1\0${role}\0${record.manifest_cid}`));
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      evidence = JSON.parse(Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
        decipher.final()]));
    } finally { key.fill(0); }
    if (role === 'source_evidence') {
      assert.equal(evidence.source_ref, 'connector://crm/main/r#v');
    } else if (role === 'model_attempt_accounting') {
      assert.equal(evidence.input_tokens, 1);
      assert.equal(evidence.output_tokens, 2);
      assert.equal(evidence.cost_units, null);
      assert.ok(evidence.cumulative_work > 0);
    } else if (role === 'model_attempt_outcome' && mode === 'cancel') {
      assert.equal(evidence.category, 'cancelled');
      assert.equal(evidence.failure, 'cancelled');
    }
  }
  console.log(JSON.stringify({mode, status: terminal.status, calls,
    evidenceHoldings: 4}));
} finally { await client.close(); }
