import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
// The installed connector table runs with the installation tests.
import './installed-connectors.test.mjs';
// The neutral row source's Site boundary runs with the installation tests.
import './installed-row-source.test.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from
  './embedded-local.mjs';
import {installedEffectIdentity} from './installed-effect.mjs';
import {installedSourceIdentity, loadInstalledSource} from './installed-source.mjs';
import {prepareCapturedDuckDBSource, openCapturedDuckDBSource} from
  './captured-duckdb-source.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';

function retainedAuthorization(accountId, observe) {
  const keys = generateKeyPairSync('ed25519');
  return {
    accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: accountId, entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    observe,
  };
}

test('installed HTTP status denies an unregistered Run with a public code',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-status-denied-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const principalId = userInfo().username;
    const host = await openInstalledRemoteHttpHost({directory,
      authenticate: () => principalId});
    t.after(async () => { await host.close(); });
    const server = createServer(host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise(resolve => server.close(resolve)));
    const authorityScopeCid = `sha256:${createHash('sha256')
      .update(JSON.stringify({version: 'actql-local-owner-scope/0.1',
        root: directory, principalId})).digest('hex')}`;
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/actql/client/0.1/status`,
      {method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
          runners: [], consentRefs: []}, ref: {namespaceId: 'local',
          authorityScopeCid,
          runDefinitionCid: `sha256:${'a'.repeat(64)}`}})},
    );
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), {code: 'RunStateAccessDenied'});
  });

test('source alias profiles own immutable metadata without widening provider input', () => {
  const entry = {name: 'records', sourceRef: 'connector://crm/r#v',
    sourceViewContractCid: `sha256:${'1'.repeat(64)}`,
    schemaContractCid: `sha256:${'2'.repeat(64)}`};
  const profile = {version: 'test', queryAliases: [entry]};
  const owned = splitSourceAliasProfile(profile);
  entry.name = 'changed';
  assert.equal(owned.queryAliases[0].name, 'records');
  assert.deepEqual(owned.providerProfile, {version: 'test'});
  assert.equal(Object.isFrozen(owned.queryAliases[0]), true);
  assert.throws(() => splitSourceAliasProfile({...profile,
    queryAliases: [{...entry, schema: {id: 'untrusted'}}]}),
  {message: 'InvalidPublicSourcePublication'});
});

test('public Host entrypoints reject an old root before modifying it',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-prior-host-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const prior = Buffer.from('retained prior request state');
    await writeFile(join(directory, 'requests'), prior);
    const entries = await readdir(directory);
    await assert.rejects(openInstalledRemoteHttpHost({directory,
      authenticate: async () => ({principalId: 'caller'})}),
    {code: 'LegacyHostRootFormat'});
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory}}), {code: 'LegacyHostRootFormat'});
    assert.deepEqual(await readdir(directory), entries);
    assert.deepEqual(await readFile(join(directory, 'requests')), prior);
  });

test('embedded Host reuses equivalent installation options, not object identity',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-embedded-owner-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const first = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory}});
    const second = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory}});
    assert.equal(first.profile.version, second.profile.version);
    await first.close();
    await second.close();

    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true}}),
    {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: 'enabled'}}),
    {name: 'TypeError', message: 'InvalidLocalRetainedOutputConfiguration'});

    const foreign = join(directory, 'different-source.json');
    await writeFile(foreign,
      '{"version":"actql-installed-duckdb-source/0.1","database":"/other.duckdb","schema":"main","table":"records"}');
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, sourceProfilePath: foreign}}),
    {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
  });

test('public source-free Program uses installed retained Relation output',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-retained-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let outputRepresentations;
    const authorization = retainedAuthorization('retained-source-free', (name, detail) => {
      if (name === 'computed') outputRepresentations = detail.outputRepresentations;
    });
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true,
        authorization}}).catch(error => {
      assert.fail(error.primaryFailure?.stack ?? error.stack);
    });
    t.after(() => client.close());
    const program = {version: 'actql/0.1', id: 'public-retained-values',
      stages: [{id: 'source', inputs: {}, steps: [{values: {
        schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 2}, {id: 1}]}, as: 'seed'},
      {from: 'seed', sort: [{id: 'asc'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['id']}}}],
      results: {rows: {from: {stage: 'source', result: 'rows'}}}};
    const execution = await client.aql(JSON.stringify(program), {format: 'json',
      requestId: 'public-retained-values'});
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await execution.result('rows').all(), [{id: 1}, {id: 2}]);
    assert.ok(outputRepresentations?.some(value =>
      value.representation === 'retained-file'));
  });

test('public Events Bridge retains producer and two consumer Results', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-retained-events-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  let outputRepresentations;
  const authorization = retainedAuthorization('retained-events', (name, detail) => {
    if (name === 'computed') outputRepresentations = detail.outputRepresentations;
  });
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, retainedRelationOutput: true, authorization}});
  t.after(() => client.close());
  const program = {version: 'actql/0.1', id: 'public-retained-events', stages: [{
    id: 'values', inputs: {}, steps: [{values: {schema: {
      event_id: {type: 'number', nullable: false},
      occurred_at: {type: 'number', nullable: false},
      payload: {type: 'string', nullable: false},
    }, rows: [
      {event_id: 1, occurred_at: 5, payload: 'first'},
      {event_id: 2, occurred_at: 15, payload: 'second'},
    ]}, as: 'out'}],
    results: {r: {from: 'out', fields: ['event_id', 'occurred_at', 'payload']}},
  }, {
    id: 'events', inputs: {rows: {result: {stage: 'values', result: 'r'}}},
    steps: [{from: 'rows', to_events: {id: 'event_id', time: 'occurred_at'},
      as: 'source'},
    {from: 'source', watermark_events: {watermark_ms: 10, policy: 'mark'},
      as: 'marked'},
    {from: 'marked', events: true, as: 'out'}],
    results: {r: {from: 'out', fields: ['event_id', 'occurred_at', 'payload',
      'watermark_ms', 'late', 'watermark_decision']}},
  }, {
    id: 'consumer_a', inputs: {x: {result: {stage: 'events', result: 'r'}}},
    steps: [{select: ['event_id', 'late'], as: 'out'}],
    results: {r: {from: 'out', fields: ['event_id', 'late']}},
  }, {
    id: 'consumer_b', inputs: {x: {result: {stage: 'events', result: 'r'}}},
    steps: [{select: ['watermark_decision', 'event_id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['watermark_decision', 'event_id']}},
  }], results: {
    published: {from: {stage: 'events', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
  const execution = await client.aql(JSON.stringify(program), {format: 'json',
    requestId: 'public-retained-events'});
  const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  assert.deepEqual(await execution.result('published').all(), [
    {event_id: 1, occurred_at: 5, payload: 'first', watermark_ms: 10,
      late: true, watermark_decision: 'mark'},
    {event_id: 2, occurred_at: 15, payload: 'second', watermark_ms: 10,
      late: false, watermark_decision: 'keep'},
  ]);
  assert.deepEqual(await execution.result('consumed_a').all(), [
    {event_id: 1, late: true}, {event_id: 2, late: false},
  ]);
  assert.deepEqual(await execution.result('consumed_b').all(), [
    {watermark_decision: 'mark', event_id: 1},
    {watermark_decision: 'keep', event_id: 2},
  ]);
  assert.ok(outputRepresentations?.some(value =>
    value.representation === 'retained-file'));
});

test('public Vectors Bridge retains producer and two consumer Results', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-retained-vectors-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  let outputRepresentations;
  const authorization = retainedAuthorization('retained-vectors', (name, detail) => {
    if (name === 'computed') outputRepresentations = detail.outputRepresentations;
  });
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, retainedRelationOutput: true, authorization}});
  t.after(() => client.close());
  const program = {version: 'actql/0.1', id: 'public-retained-vectors', stages: [{
    id: 'values', inputs: {}, steps: [{values: {schema: {
      id: {type: 'number', nullable: false},
      embedding: {type: 'vector', dimensions: 2, nullable: false},
    }, rows: [
      {id: 1, embedding: [3, 4]}, {id: 2, embedding: [0, 2]},
    ]}, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'embedding']}},
  }, {
    id: 'vectors', inputs: {rows: {result: {stage: 'values', result: 'r'}}},
    steps: [{from: 'rows', to_vectors: {id: 'id', vector: 'embedding'},
      as: 'source'},
    {from: 'source', normalize_vectors: true, as: 'normalized'},
    {from: 'normalized', vectors: true, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'embedding']}},
  }, {
    id: 'consumer_a', inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
    steps: [{select: ['id', 'embedding'], as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'embedding']}},
  }, {
    id: 'consumer_b', inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
    steps: [{select: ['embedding', 'id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['embedding', 'id']}},
  }], results: {
    published: {from: {stage: 'vectors', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
  const execution = await client.aql(JSON.stringify(program), {format: 'json',
    requestId: 'public-retained-vectors'});
  const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [{id: 1, embedding: [0.6000000238418579, 0.800000011920929]},
    {id: 2, embedding: [0, 1]}];
  assert.deepEqual(await execution.result('published').all(), expected);
  assert.deepEqual(await execution.result('consumed_a').all(), expected);
  assert.deepEqual(await execution.result('consumed_b').all(), expected.map(row => ({
    embedding: row.embedding, id: row.id})));
  assert.ok(outputRepresentations?.some(value =>
    value.representation === 'retained-file'));
});

test('installed Host admits only an exact Result policy original', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-policy-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const wire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  const original = {kind: 'data_policy',
    cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`, wire};
  await assert.rejects(openInstalledRemoteHttpHost({directory,
    authenticate: () => userInfo().username,
    resultDataPolicy: {...original, cid: `sha256:${'a'.repeat(64)}`}}),
  {code: 'MoonBitHostFailure'});
  const host = await openInstalledRemoteHttpHost({directory,
    authenticate: () => userInfo().username, resultDataPolicy: original});
  t.after(async () => host.close());
  assert.equal(typeof host.handler, 'function');
});

test('installed Effect identity compares declarations and generation semantics',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-effect-identity-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const siteProfilePath = join(directory, 'site.json');
    const publicationPath = join(directory, 'publication.json');
    const profilePath = join(directory, 'effect.json');
    await writeFile(siteProfilePath, '{"siteGeneration":1,"siteKey":"site-a"}');
    await writeFile(publicationPath, '{"generation":"a"}');
    await writeFile(profilePath, JSON.stringify({
      version: 'actql-installed-salesforce-effect/0.1', siteProfilePath,
      publicationPath, connectorId: 'crm-main',
      accountConfigurationWire: '{"account_id":"a"}',
      writes: [{resource: 'Test_Record__c', kind: 'update',
        fields: ['Name']}],
    }));
    const first = await installedEffectIdentity(profilePath);
    await writeFile(siteProfilePath,
      '{\n  "siteKey": "site-a", "siteGeneration": 1\n}');
    assert.equal(await installedEffectIdentity(profilePath), first);
    await writeFile(siteProfilePath,
      '{"siteKey":"site-a","siteGeneration":2}');
    assert.notEqual(await installedEffectIdentity(profilePath), first);
    await writeFile(siteProfilePath,
      '{"siteKey":"site-a","siteGeneration":1}');
    await writeFile(publicationPath, '{"generation":"b"}');
    assert.notEqual(await installedEffectIdentity(profilePath), first);
  });

test('installed source identity includes the published generation',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-source-identity-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const siteProfilePath = join(directory, 'site.json');
    const publicationPath = join(directory, 'publication.json');
    const profilePath = join(directory, 'source.json');
    await writeFile(siteProfilePath, '{"siteGeneration":1}');
    await writeFile(publicationPath, '{"generation":"a"}');
    await writeFile(profilePath, JSON.stringify({
      version: 'actql-installed-salesforce-source/0.1', siteProfilePath,
      publicationPath, connectorId: 'crm-main',
      accountConfigurationWire: '{"account_id":"a"}',
      resources: ['Test_Record__c'],
    }));
    const first = await installedSourceIdentity(profilePath);
    const profile = JSON.parse(await readFile(profilePath, 'utf8'));
    await writeFile(profilePath, JSON.stringify({...profile, queryAliases: []}));
    assert.equal(await installedSourceIdentity(profilePath), first);
    await writeFile(profilePath, JSON.stringify({...profile, queryAliases: [{
      name: 'records', sourceRef: 'connector://crm-main/Test_Record__c#records',
      sourceViewContractCid: `sha256:${'1'.repeat(64)}`,
      schemaContractCid: `sha256:${'2'.repeat(64)}`,
    }]}));
    assert.notEqual(await installedSourceIdentity(profilePath), first);
    await writeFile(profilePath, JSON.stringify(profile));
    await writeFile(publicationPath, '{\n "generation": "a"\n}');
    assert.equal(await installedSourceIdentity(profilePath), first);
    await writeFile(publicationPath, '{"generation":"b"}');
    assert.notEqual(await installedSourceIdentity(profilePath), first);
  });

// Independent preimages: logical text is NFC; the physical-name hex is authored
// separately so the expected identity cannot inherit the implementation's loss.
const identityCanonical = value => Array.isArray(value)
  ? '[' + value.map(identityCanonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
      identityCanonical(value[key])).join(',') + '}'
    : JSON.stringify(typeof value === 'string' ? value.normalize('NFC') : value);
const identityDigest = value => 'sha256:' + createHash('sha256')
  .update(identityCanonical(value)).digest('hex');
const targetNames = [
  {text: 'caf\u00e9', hex: '636166c3a9'},
  {text: 'cafe\u0301', hex: '63616665cc81'},
];
function identityProfile(field, name) {
  return {version: 'actql-installed-duckdb-source/0.1',
    database: '/unopened.duckdb', schema: 'main', table: 'records',
    sourceRef: 'connector://crm/main/r#v',
    checkEnvironmentWire: '{"connector_catalogs":[{"connector_id":"crm"}]}',
    accountConfigurationWire: identityCanonical({version: 'actql-execution-account-config/0.1',
      account_id: 'target-identity', entries: [{entry_id: 'read', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    [field]: field === 'database' ? '/' + name.text : name.text};
}
function expectedTarget(profile, field, name) {
  return {version: 'actql-installed-duckdb-target/0.1',
    database: profile.database, schema: profile.schema, table: profile.table,
    utf8_hex: {database: '2f756e6f70656e65642e6475636b6462', schema: '6d61696e',
      table: '7265636f726473', [field]: (field === 'database' ? '2f' : '') + name.hex}};
}
function expectedInstallation(profile, target) {
  const hash = createHash('sha256');
  for (const part of [profile, target]) {
    const text = identityCanonical(part);
    hash.update(String(Buffer.byteLength(text)) + '\0' + text);
  }
  return 'sha256:' + hash.digest('hex');
}
for (const field of ['database', 'schema', 'table']) {
  test(`installed source identity preserves physical ${field} UTF-8 bytes`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-exact-target-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const path = join(directory, 'source.json');
    const controls = [];
    for (const name of targetNames) {
      await writeFile(path, JSON.stringify(identityProfile(field, name)));
      controls.push(await installedSourceIdentity(path));
    }
    assert.notEqual(controls[0], controls[1]);
    const ids = [];
    for (const name of targetNames) {
      const profile = identityProfile(field, name);
      await writeFile(path, JSON.stringify(profile));
      const identity = await installedSourceIdentity(path);
      assert.equal(identity, expectedInstallation(profile,
        expectedTarget(profile, field, name)));
      ids.push(identity);
      // A different serialization and fresh object still select the same target.
      await writeFile(path, JSON.stringify(Object.fromEntries(
        Object.entries(profile).reverse()), null, 2) + '\n');
      assert.equal(await installedSourceIdentity(path), identity);
      await writeFile(path, JSON.stringify({...profile, queryAliases: []}));
      assert.equal(await installedSourceIdentity(path), identity);
    }
    assert.notEqual(ids[0], ids[1]);
  });

  test(`installed connector identity preserves physical ${field} UTF-8 bytes`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-exact-connector-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const path = join(directory, 'source.json');
    const ids = [];
    for (const name of targetNames) {
      const profile = identityProfile(field, name);
      await writeFile(path, JSON.stringify(profile));
      // Installation binds the connector without opening the nonexistent database.
      const adapter = await loadInstalledSource(path, {root: directory,
        principalId: 'target-identity', moon: {}});
      try {
        const binding = adapter.connectorBindings[0];
        assert.deepEqual(binding, {connectorId: 'crm', bindingCid: identityDigest({
          version: 'actql-installed-duckdb-source-binding/0.1',
          root: directory, principalId: 'target-identity',
          physicalBinding: expectedTarget(profile, field, name),
          sourceRef: profile.sourceRef})});
        ids.push(binding.bindingCid);
      } finally { await adapter.close(); }
    }
    assert.notEqual(ids[0], ids[1]);
  });
}

test('approval and pre-acquisition checks preserve the same exact physical target', async () => {
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientProgramPrepareQueryAcquisition: () => ok({}),
    clientProgramPrepareLocalQueryRequirement: () => ok({}),
    clientProgramQueryRequirementSourceEvidenceFacts: () => ok([
      'connector://crm/main/r#v', 'source', 'schema', 'policy', 'classification', 'view']),
    clientProgramQueryRequirementCid: () => 'requirement',
    clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
    clientProgramPrepareDuckDBSourceEvidenceContext: () => ok({}),
    clientProgramAcquisitionCount: () => 1,
  };
  let decisions = 0;
  const options = {moon, preparedProgram: {}, registry: '{}', values: '{}',
    fragment: '{}', ordered: '{}',
    sourceAccess: {sourceRef: 'connector://crm/main/r#v', authorization: {
      async authorize() { decisions++; return {action: 'deny', basis: 'account',
        reason: 'explicit'}; },
    }}, transportLimits: {maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
      maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
      memoryBytes: 128 * 1024 * 1024, threads: 1}};
  for (const field of ['database', 'schema', 'table']) {
    const profile = identityProfile(field, targetNames[0]);
    const access = {...options.sourceAccess, authorization: {
      async authorize() { return {action: 'waiting'}; },
    }};
    const input = {...options, ...{database: profile.database, schema: profile.schema,
      table: profile.table}, sourceAccess: access};
    const preparedSource = await prepareCapturedDuckDBSource(input);
    assert.deepEqual(preparedSource.physicalBinding,
      expectedTarget(profile, field, targetNames[0]));
    assert.ok(Object.isFrozen(preparedSource.physicalBinding.utf8_hex));
    access.authorization = options.sourceAccess.authorization;
    let ended;
    await assert.rejects(openCapturedDuckDBSource({...input, preparedSource,
      [field]: (field === 'database' ? '/' : '') + targetNames[1].text,
      reportAcquisitionFailure: failure => { ended = failure; }}),
    {message: 'InstalledSourcePreparationMismatch'});
    assert.equal(ended.outcome, 'not_started');
    assert.equal(decisions, 0);
    // Exact unchanged target reaches the existing gate, which still refuses I/O.
    await assert.rejects(openCapturedDuckDBSource({...input, preparedSource}),
      {code: 'ExecutionAuthorizationDenied'});
    assert.equal(decisions, 1);
    decisions = 0;
  }
});

test('DuckDB confirms distinct physical Unicode tables and schemas before identity comparison', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-provider-target-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const {DuckDBInstance} = createRequire(new URL(
    '../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
  const database = join(directory, 'source.duckdb');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    for (const [field, expected] of [
      ['table', [{id: 101, amount: 11}, {id: 202, amount: 22}]],
      ['schema', [{id: 303, amount: 33}, {id: 404, amount: 44}]],
    ]) {
      const ids = [];
      for (const [index, name] of targetNames.entries()) {
        const profile = {...identityProfile(field, name), database};
        if (field === 'schema') await connection.run(`CREATE SCHEMA "${profile.schema}"`);
        const table = `"${profile.schema}"."${profile.table}"`;
        await connection.run(`CREATE TABLE ${table}(id DOUBLE, amount DOUBLE)`);
        await connection.run(`INSERT INTO ${table} VALUES (?, ?)`,
          [expected[index].id, expected[index].amount]);
        const rows = await connection.runAndReadAll(`SELECT id, amount FROM ${table}`);
        assert.deepEqual(rows.getRowObjectsJS(), [expected[index]]);
        const path = join(directory, 'source.json');
        await writeFile(path, JSON.stringify(profile));
        ids.push(await installedSourceIdentity(path));
      }
      assert.notEqual(ids[0], ids[1]);
    }
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
});
