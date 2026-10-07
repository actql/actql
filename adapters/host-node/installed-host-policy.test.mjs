import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, access} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {writeFile} from 'node:fs/promises';
import {analyticFrameParameterCapacity, analyticFrameParameterSuccesses}
  from '../../scripts/fixtures/analytic-frame-parameter-source-input.mjs';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {DatabaseSync} from 'node:sqlite';
import test, {after} from 'node:test';
import {connect as connectRemote} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
const connect = options => options.mode === 'local'
  ? connectEmbeddedLocal(options) : connectRemote(options);
import {snapshotHostCapacityPolicy, selectInstalledHostEnvironment} from './installed-host-policy.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const base = JSON.parse(baseWire), policy = base.host_policy_profile.capacity;
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const expectedScope = (directory, selected) => hash(JSON.stringify({
  version: 'actql-local-owner-scope/0.1', root: directory, principalId: userInfo().username,
  ...(selected === undefined ? {} : {hostCapacityPolicyCid: hash(canonical({max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000, ...selected}))}),
}));
const scratch = new URL('../../_build/installed-host-policy/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tls = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'key.pem', '-out', 'cert.pem', '-days', '1', '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=IP:127.0.0.1'], {cwd: tls, stdio: 'ignore'});
const key = await readFile(join(tls, 'key.pem')), cert = await readFile(join(tls, 'cert.pem'));
const originalCertificates = getCACertificates('default');
setDefaultCACertificates([...originalCertificates, cert.toString('utf8')]);
after(async () => {setDefaultCACertificates(originalCertificates); await rm(tls, {recursive: true, force: true});});

const invalidPolicies = () => [null, [], {}, {...policy, version: 'future'},
  {...policy, unknown_capacity: 1}, {...policy, max_effect_items: undefined},
  ...[0, -1, -0, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, new Number(1)]
    .map(value => ({...policy, max_effect_items: value})),
  {...policy, get max_effect_items() {throw new Error('private getter');}},
];
test('Host capacity selection snapshots the complete registered contract once', () => {
  let reads = 0;
  const source = {...policy, get max_effect_items() {reads++; return 1234;}};
  const snapshot = snapshotHostCapacityPolicy(source);
  assert.deepEqual(snapshot, {...policy, max_effect_items: 1234});
  assert.equal(reads, 1);
  assert.ok(Object.isFrozen(snapshot));
  assert.equal(snapshotHostCapacityPolicy(snapshot), snapshot);
  for (const value of invalidPolicies()) assert.throws(() => snapshotHostCapacityPolicy(value),
    {code: 'InvalidInstalledHostCapacityPolicy'});
  const inherited = Object.create(policy);
  assert.throws(() => snapshotHostCapacityPolicy(inherited), {code: 'InvalidInstalledHostCapacityPolicy'});
  const explicit = {...policy, max_graph_construction_nodes: 23,
    max_analytic_input_wire_bytes: 1048576, max_analytic_output_wire_bytes: 1048576,
    max_analytic_partition_wire_bytes: 1048576, max_analytic_frame_memberships: 10000};
  const selected = selectInstalledHostEnvironment(moon, baseWire, explicit);
  assert.deepEqual(JSON.parse(selected).host_policy_profile.capacity, explicit);
  assert.equal(selectInstalledHostEnvironment(moon, baseWire, undefined), baseWire);
  assert.equal(composeInstalledCheckEnvironment(moon, selected, selected, undefined), selected);
  assert.throws(() => composeInstalledCheckEnvironment(moon, baseWire, selected, undefined),
    {code: 'InstalledCheckEnvironmentConflict'});
});

for (const entrance of ['local', 'https']) {
  test(`${entrance}: invalid explicit Host capacity is refused before creating a Host root`, async () => {
    for (const [index, selected] of invalidPolicies().entries()) {
      const directory = join(scratch, `${entrance}-invalid-${index}`);
      const promise = entrance === 'local' ? connect({mode: 'local', owner: 'local',
        installation: {directory, hostCapacityPolicy: selected}})
        : openInstalledRemoteHttpHost({directory, hostCapacityPolicy: selected,
          authenticate: () => userInfo().username});
      await assert.rejects(promise, {code: 'InvalidInstalledHostCapacityPolicy'});
      await assert.rejects(access(directory), {code: 'ENOENT'});
    }
  });
}

async function submit(client, requestId = 'policy-request') {
  const run = await client.aql('SELECT 1 AS n', {format: 'sql', requestId});
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
  return run;
}
async function remote(t, directory, selected, mutate, extra = {}) {
  const opening = openInstalledRemoteHttpHost({directory, hostCapacityPolicy: selected, ...extra,
    authenticate: header => header === 'Bearer policy-token' ? userInfo().username : undefined});
  mutate?.();
  const host = await opening;
  const server = createServer({key, cert}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await host.close();
  };
  t.after(close);
  return {client: await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'policy-token'}), close};
}

test('public Embedded Local binds a pre-await policy snapshot and refuses a changed installation', async t => {
  const directory = await mkdtemp(join(scratch, 'local-'));
  const selected = {...policy, max_effect_items: 1234};
  let reads = 0;
  const original = {...policy};
  Object.defineProperty(original, 'max_effect_items', {enumerable: true, configurable: true,
    get() {reads++; return 1234;}});
  const opening = connect({mode: 'local', owner: 'local', installation: {directory, hostCapacityPolicy: original}});
  assert.equal(reads, 1, '[host-policy:host-pre-await]');
  Object.defineProperty(original, 'max_effect_items', {value: 4321});
  const client = await opening;
  t.after(() => client.close());
  assert.equal(client.profile.scopeRef, expectedScope(directory, selected));
  const run = await submit(client);
  assert.equal(run.ref.authorityScopeCid, expectedScope(directory, selected), '[host-policy:scope-binding]');
  const equivalent = Object.fromEntries(Object.entries(selected).reverse());
  const same = await connect({mode: 'local', owner: 'local', installation: {directory, hostCapacityPolicy: equivalent}});
  t.after(() => same.close());
  assert.deepEqual((await submit(same)).ref, run.ref);
  await assert.rejects(connect({mode: 'local', owner: 'local',
    installation: {directory, hostCapacityPolicy: {...selected, max_effect_items: 4321}}}),
  {message: 'InstalledHostConfigurationMismatch'});
  assert.equal(reads, 1);
});

test('public HTTPS restart keeps selected request identity and separates changed or default policy scopes', async t => {
  const directory = await mkdtemp(join(scratch, 'https-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const selected = {...policy, max_effect_items: 1234, max_graph_construction_nodes: 23};
  const supplied = {...selected};
  const first = await remote(t, directory, supplied, () => {supplied.max_effect_items = 4321;});
  const original = await submit(first.client);
  assert.equal(original.ref.authorityScopeCid, expectedScope(directory, selected));
  await first.close();
  const resumed = await remote(t, directory, {...selected});
  assert.deepEqual((await submit(resumed.client)).ref, original.ref,
    '[host-policy:same-request-restart]');
  await resumed.close();
  const changed = {...selected, max_effect_items: 4321};
  const different = await remote(t, directory, changed);
  assert.equal((await different.client.lookupRequest('policy-request')).kind, 'not_found');
  await assert.rejects(different.client.attach(original.ref), {code: 'ClientConnectionDenied'});
  const next = await submit(different.client);
  assert.equal(next.ref.authorityScopeCid, expectedScope(directory, changed));
  assert.notEqual(next.ref.authorityScopeCid, original.ref.authorityScopeCid);
  await different.close();
  const defaults = await remote(t, directory, undefined);
  assert.equal((await defaults.client.lookupRequest('policy-request')).kind, 'not_found');
  assert.equal(defaults.client.profile.scopeRef, userInfo().username);
  const historical = await submit(defaults.client);
  assert.equal(historical.ref.authorityScopeCid, expectedScope(directory, undefined),
    '[host-policy:historical-default-scope]');
  await defaults.close();
  const explicitDefault = await remote(t, directory, {...policy});
  const selectedDefault = await submit(explicitDefault.client);
  assert.equal(selectedDefault.ref.authorityScopeCid, expectedScope(directory, policy));
  assert.notEqual(selectedDefault.ref.authorityScopeCid, historical.ref.authorityScopeCid,
    '[host-policy:explicit-default-is-selected]');
  const journal = new DatabaseSync(join(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  try {
    const rows = journal.prepare('SELECT authority_scope_cid, caller_request_id FROM client_requests').all();
    assert.equal(rows.length, 4);
    assert.deepEqual(new Set(rows.map(row => row.authority_scope_cid)), new Set([
      expectedScope(directory, selected), expectedScope(directory, changed), expectedScope(directory, undefined),
      expectedScope(directory, policy)]));
    assert.ok(rows.every(row => row.caller_request_id === 'policy-request'));
  } finally {journal.close();}
  await explicitDefault.close();
});


for (const entrance of ['local', 'https']) {
  test(`${entrance}: public installed analytic profile keeps its original explicit capacities and rows`, async t => {
    const root = await mkdtemp(join(scratch, `analytic-${entrance}-`));
    const directory = join(root, 'state'), database = join(root, 'records.duckdb');
    const selected = {...policy, ...analyticFrameParameterCapacity};
    assert.deepEqual(analyticFrameParameterCapacity, {
      max_analytic_input_wire_bytes: 10000, max_analytic_output_wire_bytes: 10000,
      max_analytic_partition_wire_bytes: 10000, max_analytic_frame_memberships: 10000});
    const item = analyticFrameParameterSuccesses.find(item =>
      item.name === 'analytic-frame-parameter-sql-distinct-widths');
    const {DuckDBInstance} = createRequire(new URL('../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
    const instance = await DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      for (const row of item.sourceRows) await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
    } finally {connection.closeSync(); instance.closeSync();}
    const environment = JSON.parse(await readFile(new URL('./fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
    environment.host_policy_profile = {...base.host_policy_profile, capacity: selected};
    delete environment.evidence_bundle_cid;
    environment.evidence_bundle_cid = hash(canonical(environment));
    const view = environment.source_views[0];
    const sourceProfilePath = join(root, 'source.json');
    await writeFile(sourceProfilePath, JSON.stringify({
      version: 'actql-installed-duckdb-source/0.1', database, schema: 'main', table: 'records',
      sourceRef: 'connector://crm/main/r#v',
      acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
      queryAliases: [{name: 'records', sourceRef: 'connector://crm/main/r#v',
        sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}],
      checkEnvironmentWire: canonical(environment),
      accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
        account_id: 'explicit-host-policy', entries: [{entry_id: 'read', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['read']}, exclusions: []}]}),
    }));
    const host = entrance === 'https' ? await remote(t, directory, selected, undefined, {sourceProfilePath}) : undefined;
    const client = host?.client ?? await connect({mode: 'local', owner: 'local',
      installation: {directory, sourceProfilePath, hostCapacityPolicy: selected}});
    t.after(() => client.close());
    const run = await client.aql(item.text, {format: item.format, requestId: 'analytic-original-profile',
      parameters: item.parameters, parameterDeclarations: item.parameterDeclarations});
    assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), item.expected);
    assert.deepEqual((await run.result('answer').describe()).columns, item.columns);
    assert.equal(run.ref.authorityScopeCid, expectedScope(directory, selected));
    await host?.close();
  });
}
