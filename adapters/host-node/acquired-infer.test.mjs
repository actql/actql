import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {loadPrivateEvidenceKey} from './local-continuation-evidence.mjs';
import {canonical, cid, configuration} from
  '../../scripts/fixtures/installed-infer-fixture.mjs';

// Reissue the fixture's owned source policy, references and Catalog together.
// This is installation metadata, not a provider claiming a lower classification.
function withSourceClassification(original, classification, sourceText) {
  const source = structuredClone(original);
  const policy = source.contract_registry.find(value => value.kind === 'data_policy');
  const {cid: previousPolicy, ...policyBody} = policy;
  assert.equal(cid(policyBody), previousPolicy);
  policy.body.classification = classification;
  policy.cid = cid({...policyBody, body: policy.body});
  const view = source.source_views[0];
  const {contract_cid: previousView, ...viewBody} = view;
  assert.equal(cid(viewBody), previousView);
  view.output.data_policy.cid = policy.cid;
  if (sourceText) {
    const schema = source.contract_registry.find(value => value.kind === 'carrier_schema');
    const {cid: previousSchema, ...body} = schema;
    assert.equal(cid(body), previousSchema);
    schema.body.fields.amount = {nullable: true, type: 'string'};
    schema.cid = cid({...body, body: schema.body});
    view.output.schema.cid = schema.cid;
    for (const snapshot of source.schema_snapshots) {
      snapshot.carrier_schema_contract_cid = schema.cid;
    }
  }
  view.contract_cid = cid({...viewBody, output: view.output});
  const catalog = source.connector_catalogs[0];
  catalog.contracts = source.contract_registry.map(value => structuredClone(value))
    .sort((left, right) => left.cid < right.cid ? -1 : left.cid > right.cid ? 1 : 0);
  catalog.source_views = [structuredClone(view)];
  delete catalog.catalog_cid;
  catalog.catalog_cid = cid(catalog);
  for (const capability of source.connector_capabilities) {
    capability.source_contract_cid = view.contract_cid;
    capability.source_view_contract_cid = view.contract_cid;
    if (sourceText) capability.capability_contract_cids.push(
      'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
    capability.capability_contract_cids.sort();
  }
  for (const snapshot of source.schema_snapshots) {
    snapshot.source_contract_cid = view.contract_cid;
    snapshot.source_view_contract_cid = view.contract_cid;
    snapshot.source_data_policy_cid = policy.cid;
    snapshot.data_classification = classification;
  }
  delete source.evidence_bundle_cid;
  source.evidence_bundle_cid = cid(source);
  return source;
}

async function runAcquiredInfer({authored, boundary}, t) {
  boundary ??= process.env.ACTQL_ACQUIRED_INFER_TEST_BOUNDARY;
  const mode = process.env.ACTQL_ACQUIRED_INFER_TEST_MODE;
  const replaying = mode?.startsWith('replay') === true;
  const root = process.env.ACTQL_ACQUIRED_INFER_TEST_ROOT ??
    await mkdtemp(join(tmpdir(), 'actql-acquired-infer-'));
  let client;
  let calls = 0;
  let egressIssueKind;
  let run;
  const observed = [];
  let started;
  const startedRun = new Promise(resolve => { started = resolve; });
  let cancelled = false;
  let rejectReplay;
  const replayRejected = new Promise(resolve => { rejectReplay = resolve; });
  try {
    const base = JSON.parse(await readFile(new URL(
      '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
    const source = withSourceClassification(JSON.parse(await readFile(new URL(
      './fixtures/query-amount-environment.json', import.meta.url), 'utf8')), 'public', !authored);
    source.host_policy_profile = base.host_policy_profile;
    delete source.evidence_bundle_cid;
    source.evidence_bundle_cid = cid(source);
    const database = join(root, 'records.duckdb');
    const {DuckDBInstance} = createRequire(new URL(
      '../connectors/duckdb/node/package.json', import.meta.url))(
      '@duckdb/node-api');
    const instance = await DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      if (!replaying) {
        await connection.run(`CREATE TABLE records(id DOUBLE, amount ${authored ? 'DOUBLE' : 'VARCHAR'})`);
        await connection.run(authored ? 'INSERT INTO records VALUES (1, 42)' :
          "INSERT INTO records VALUES (1, 'urgent')");
      } else if (mode === 'replay-changed') {
        await connection.run("UPDATE records SET amount = 'changed'");
      }
    } finally {
      connection.closeSync();
      instance.closeSync();
    }
    const accountConfiguration = canonical({
      version: 'actql-execution-account-config/0.1', account_id: 'infer-source',
      entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {all: true},
        exclusions: []}],
    });
    const sourceProfilePath = join(root, 'source-profile.json');
    await writeFile(sourceProfilePath, canonical({
      version: 'actql-installed-duckdb-source/0.1', database,
      schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
      acquisitionPlanning: {policy: 'priority',
        priority: ['nativeQuery', 'broadQuery']},
      checkEnvironmentWire: canonical(source),
      accountConfigurationWire: accountConfiguration,
    }));
    const {installation, taskCid} = configuration(base);
    const keys = generateKeyPairSync('ed25519');
    const keyPath = join(root, 'fixture-keys.json');
    const keyMaterial = replaying
      ? JSON.parse(await readFile(keyPath, 'utf8'))
      : {privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})};
    if (mode === 'capture') await writeFile(keyPath, JSON.stringify(keyMaterial),
      {mode: 0o600});
    const checked = value => {
      assert.equal(value.$tag, 1);
      return value._0;
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      durability: 'durable', installation: {directory: join(root, 'host'),
        sourceProfilePath, modelInstallation: installation,
        authorization: {accountConfiguration,
          observe(name, detail) {
            observed.push({name, detail});
            if (name === 'infer_replay_failed') rejectReplay(detail);
          },
          faultInjection: async name => {
            if (boundary === 'cancel' && calls === 1 && !cancelled &&
                name === 'infer_execution_advanced') {
              cancelled = true;
              await startedRun;
              await run.cancel();
            }
            if (mode === 'capture' && name === 'infer_capture_committed') {
              assert.equal(calls, 1);
              await writeFile(join(root, 'capture-calls.json'), JSON.stringify(calls));
              process.exit(0);
            }
          },
          hostKey: {keyId: 'host', privateKey: keyMaterial.privateKey},
          reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
            principalId: userInfo().username,
            publicKey: keyMaterial.publicKey}]},
        registerModelProviders: moon => {
          egressIssueKind = issue => moon.clientProgramInferEgressIssueKind(issue);
          return [{providerId: 'models/packed',
          invoke() { throw new Error('UnpreparedModelCall'); },
          validatePrompt(actual, selector, wire) {
            return actual === taskCid && selector === 'packed-risk-model' &&
              JSON.parse(wire).format === 'packed-risk/0.1';
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
                  assert.equal(moon.clientProgramModelRequestInput(request,
                    'text'), '"urgent"');
                  return moon.clientProgramModelResponse(request,
                    '{"reason":null,"risk":"high"}', 'packed-risk-model',
                    'acquired-request', 1n, boundary === 'usage' ? 1000n : 2n,
                    new Date().toISOString());
                }))}), () => true),
        }];
        },
      }});
    const program = {version: 'actql/0.1', id: 'acquired-infer',
      stages: [{id: 'main',
        inputs: {source: {connector: 'crm/main', resource: 'r'}},
        steps: [{filter: authored ? 'id > 0' : 'id = id'}, {select: ['id', 'amount']},
          {assert_rows: {unique_by: ['id']}},
          ...(authored ? [{derive: {text: {literal: 'urgent'}}}] : []),
          {infer: {contract: 'model-task:packed-risk.v1', key: 'id',
            input: {text: {field: authored ? 'text' : 'amount'}}}, as: 'captured'}],
        results: {captured: {from: 'captured',
          fields: ['id', 'outcome', 'value']}}}],
      results: {answer: {from: {stage: 'main', result: 'captured'}}}};
    if (authored) {
      await assert.rejects(client.start(program, {requestId: 'acquired-infer'}), error => {
      assert.equal(error.code, 'ClientProgramUnsupported');
      let cause = error;
      while (cause && cause.code !== 'MoonBitHostFailure') cause = cause.cause;
      assert.ok(cause, 'the common owner must provide the typed refusal');
      assert.equal(egressIssueKind(cause.cause), 'unknown_classification');
      return true;
      });
      assert.equal(calls, 0);
    } else {
      run = await client.start(program, {requestId: 'acquired-infer'}).catch(error => {
        t.diagnostic(inspect(error.cause, {depth: 12}));
        throw error;
      });
      started();
      if (mode === 'replay-changed') {
        const rejection = await replayRejected;
        assert.equal(rejection.code, 'MoonBitHostFailure');
        assert.equal((await run.wait()).status, 'needs_reconciliation');
        await assert.rejects(run.result('answer').all());
        assert.equal(calls, 0);
        return;
      }
      const terminal = await run.wait();
      if (boundary !== undefined) {
        assert.equal(terminal.status, boundary === 'cancel' ? 'cancelled' : 'failed');
        await assert.rejects(run.result('answer').all());
        assert.equal(calls, 1);
        assert.equal(cancelled, boundary === 'cancel');
        await client.close();
        client = undefined;
        await writeFile(join(root, 'stopped.json'), JSON.stringify({
          ref: run.ref, calls}));
        return;
      }
      if (terminal.status !== 'succeeded') {
        t.diagnostic(inspect(terminal, {depth: 8}));
        t.diagnostic(inspect(observed, {depth: 8}));
      }
      assert.equal(terminal.status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), [
        {id: 1, outcome: 'ok', value: {reason: null, risk: 'high'}},
      ]);
      assert.equal(calls, mode === 'replay' ? 0 : 1);
    }
  } finally {
    await client?.close();
    if (mode === undefined) await rm(root, {recursive: true, force: true});
  }
}

async function checkStoppedEvidence(root, boundary) {
        const stopped = JSON.parse(await readFile(join(root, 'stopped.json'), 'utf8'));
        assert.equal(stopped.calls, 1);
        const hostRoot = join(root, 'host');
        const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
          version: 'actql-local-store-owner/0.1', root: hostRoot,
          principalId: userInfo().username})).digest('hex')}`;
        const key = await loadPrivateEvidenceKey(join(hostRoot, 'checkpoints'));
        const store = await openLocalPublicationStore({
          directory: join(hostRoot, 'publication'), storeAuthorityCid: storeCid,
          capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 1048576,
          maxObjects: 10000, maxContractNodes: 10000, maxContractDepth: 64,
          privateEvidenceKey: key.key,
        }, createPublicationContractControlFixture());
        key.key.fill(0);
        try {
          for (const role of ['source_evidence', 'model_attempt_accounting',
            'model_attempt_outcome']) {
            const holding = cid({role, slot: 0,
              run_definition_cid: stopped.ref.runDefinitionCid,
              store_authority_cid: storeCid,
              version: 'actql-model-private-holding/0.1'});
            const record = await store.inspectPhysicalHolding(holding);
            assert.ok(record, role);
            const body = JSON.parse(new TextDecoder().decode(
              await store.readPrivateEvidence(role, record.manifest_cid, holding)));
            if (role === 'model_attempt_accounting') {
              assert.equal(body.input_tokens, 1);
              assert.equal(body.output_tokens, boundary === 'usage' ? 1000 : 2);
              assert.equal(body.cost_units, null);
              assert.ok(body.cumulative_work > 0);
            } else if (role === 'model_attempt_outcome') {
              assert.equal(body.category, boundary === 'cancel'
                ? 'cancelled' : 'contract_violation');
              assert.equal(body.failure, boundary === 'cancel'
                ? 'cancelled' : 'budget_exceeded');
            } else {
              assert.equal(body.source_ref, 'connector://crm/main/r#v');
            }
          }
        } finally { await store.close(); }
}

test('acquired INFER rejects unclassified authored contributions before dispatch',
  t => runAcquiredInfer({authored: true}, t));
test('acquired Relation reaches installed INFER and its Named Result',
  t => runAcquiredInfer({authored: false}, t));
for (const boundary of ['cancel', 'usage']) {
  test(`acquired INFER retains evidence after dispatch: ${boundary}`, async () => {
    const root = await mkdtemp(join(tmpdir(), 'actql-acquired-stopped-'));
    try {
      const environment = {...process.env, ACTQL_ACQUIRED_INFER_TEST_MODE: 'stopped',
        ACTQL_ACQUIRED_INFER_TEST_BOUNDARY: boundary, ACTQL_ACQUIRED_INFER_TEST_ROOT: root};
      delete environment.NODE_TEST_CONTEXT;
      const child = spawnSync(process.execPath, ['--test',
        '--test-name-pattern=^acquired Relation reaches', fileURLToPath(import.meta.url)], {
        encoding: 'utf8', timeout: 30000, env: environment,
      });
      assert.equal(child.status, 0, `${child.error ?? ''}\n${child.stdout}\n${child.stderr}`);
      await checkStoppedEvidence(root, boundary);
    } finally { await rm(root, {recursive: true, force: true}); }
  });
}

for (const replayMode of ['replay', 'replay-changed']) {
test(`acquired INFER uses saved evidence without another model call: ${replayMode}`, async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-acquired-replay-'));
  try {
    for (const mode of ['capture', replayMode]) {
      const environment = {...process.env, ACTQL_ACQUIRED_INFER_TEST_MODE: mode,
        ACTQL_ACQUIRED_INFER_TEST_ROOT: root};
      delete environment.NODE_TEST_CONTEXT;
      const child = spawnSync(process.execPath, ['--test',
        '--test-name-pattern=^acquired Relation reaches', fileURLToPath(import.meta.url)], {
        encoding: 'utf8', timeout: 30000,
        env: environment,
      });
      assert.equal(child.status, 0,
        `${mode}: ${child.error ?? ''}\n${child.stdout}\n${child.stderr}`);
    }
    assert.equal(JSON.parse(await readFile(join(root, 'capture-calls.json'), 'utf8')), 1);
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
}
