// Real SDK/Host regressions for the independently reported #640 and #509
// failures. The saved Programs are reproduction material, not lowering oracles.
// Rows/schema below are authored independently. No Host budget is overridden.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson as canonical} from './local-account-config.mjs';

const root = new URL('../../', import.meta.url).pathname;
const hash = value => createHash('sha256').update(value).digest('hex');
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
const sourceStatus = execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'});
const provenance = {head: revision, clean: sourceStatus.length === 0, sourceStatus,
  ownerSha256: hash(await readFile(join(root, 'src/connectors/local/selected_relation_provider.mbt'))),
  testSha256: hash(await readFile(new URL(import.meta.url))),
  runtimeSha256: hash(await readFile(join(root,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')))};
const {DuckDBInstance, DuckDBConnection, DuckDBExtractedStatements,
  DuckDBPreparedStatement} = createRequire(new URL(
  '../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
const number = {type: 'number', nullable: false};
// Checked Object descriptors require the existing explicit closed-object flag
// (value_contract/encode.mbt and the checked ValueContract wire schema).
const object = {type: 'object', nullable: false, additional_properties: false,
  fields: {score: number}};
const cases = [
  {name: 'distinct-join-limit', file: 'acquired-distinct-join-limit.program.json',
    rows: [{id: 3, amount: 2}, {id: 1, amount: 2}, {id: 2, amount: 1},
      {id: 4, amount: null}, {id: 0, amount: 99}],
    expected: [{amount: -1}, {amount: -2}],
    columns: [{name: 'amount', contract: {...number, nullable: true}}]},
  {name: 'having-alias-collision', file: 'acquired-having-alias-collision.program.json',
    rows: [{id: 2, amount: 10}, {id: 1, amount: 20}, {id: 3, amount: null},
      {id: 4, amount: 40}, {id: 2, amount: 10}, {id: 0, amount: 99}],
    parameters: {p1: {score: 20}, p2: {score: 10}, p3: null, p4: {score: null},
      o1: {score: 5}, o2: {score: 30}, o3: {score: 15}, o4: {score: 25}},
    expected: [{n: 5, payload: {score: 5}, original: 'b|b|a|c'}],
    columns: [{name: 'n', contract: number}, {name: 'payload', contract: object},
      {name: 'original', contract: {type: 'string', nullable: true}}]},
];

async function fixture(t, transport, item, cancel) {
  const parent = join(root, '_build', 'acquired-chain-capacity');
  await mkdir(parent, {recursive: true});
  const directory = await mkdtemp(join(parent, `${transport}-${item.name}-`));
  console.log('Acquired-chain receipt directory:', directory);
  const database = join(directory, 'source.duckdb');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    for (const row of item.rows) await connection.run(
      'INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
  } finally { connection.closeSync(); instance.closeSync(); }
  const environment = JSON.parse(await readFile(new URL(
    './fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const base = JSON.parse(await readFile(join(root, 'spec/local-check-environment.json'), 'utf8'));
  environment.host_policy_profile = base.host_policy_profile;
  environment.connector_capabilities[0].capability_contract_cids.push(
    'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
  environment.connector_capabilities[0].capability_contract_cids.sort();
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
    .update(canonical(environment)).digest('hex');
  const account = canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'acquired-chain-capacity', entries: [{entry_id: 'read-write',
      outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []}]});
  const sourceProfilePath = join(directory, 'source-profile.json');
  const view = environment.source_views[0];
  await writeFile(sourceProfilePath, canonical({
    version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    queryAliases: [{name: 'records', sourceRef: 'connector://crm/main/r#v',
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}],
    checkEnvironmentWire: canonical(environment), accountConfigurationWire: account}));

  // Count real source read connections, including both native acquisition scans
  // within one session. The installation never injects rows into the evaluator.
  let sessions = 0, sourceReads = 0, advances = 0;
  const readSessions = new WeakSet(), sql = new WeakMap(), connections = new WeakMap();
  const prepared = new WeakMap();
  const extract = DuckDBConnection.prototype.extractStatements;
  const prepare = DuckDBExtractedStatements.prototype.prepare;
  const stream = DuckDBPreparedStatement.prototype.stream;
  DuckDBConnection.prototype.extractStatements = async function(text) {
    const value = await Reflect.apply(extract, this, [text]);
    sql.set(value, text); connections.set(value, this); return value;
  };
  DuckDBExtractedStatements.prototype.prepare = async function(index) {
    const value = await Reflect.apply(prepare, this, [index]);
    prepared.set(value, {sql: sql.get(this), connection: connections.get(this)}); return value;
  };
  DuckDBPreparedStatement.prototype.stream = function(...args) {
    const value = prepared.get(this);
    if (/\bFROM\s+(?:"main"\.)?"records"(?=\s|$)/iu.test(value?.sql ?? '')) {
      sourceReads++;
      if (!readSessions.has(value.connection)) {
        readSessions.add(value.connection); sessions++;
      }
    }
    return Reflect.apply(stream, this, args);
  };
  const barrier = Promise.withResolvers(), release = Promise.withResolvers();
  const keys = generateKeyPairSync('ed25519');
  const authorization = {accountConfiguration: account,
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    async faultInjection(step, detail) {
      if (step !== 'local_compute_advanced') return;
      advances++;
      if (cancel && detail.task === 1 && advances === 1) {
        barrier.resolve(); await release.promise;
      }
    }};
  const hostDirectory = join(directory, 'host');
  let client, host, server;
  t.after(async () => {
    release.resolve();
    await client?.close();
    if (server) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
    DuckDBConnection.prototype.extractStatements = extract;
    DuckDBExtractedStatements.prototype.prepare = prepare;
    DuckDBPreparedStatement.prototype.stream = stream;
    // Keep owned evidence, including failed attempts, for fixed-SHA review.
  });
  if (transport === 'local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: hostDirectory, sourceProfilePath, authorization}});
  } else {
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
    const cert = await readFile(join(directory, 'remote.crt'));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({directory: hostDirectory,
      sourceProfilePath, authorization,
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
    server = createServer({key: await readFile(join(directory, 'remote.key')), cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable', token: 'fixture-token',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  return {client, directory, barrier, release,
    counts: () => ({sessions, sourceReads, advances}),
    cleaned: () => readdir(join(hostDirectory, 'carrier-snapshots'))};
}

for (const transport of ['local', 'https']) {
  for (const item of cases) {
    for (const variant of ['original', 'empty', 'cancel']) {
      test(`${transport}: acquired ${item.name} ${variant} keeps capacity and cleanup`,
        {timeout: 60_000}, async t => {
          const cancel = variant === 'cancel';
          const selected = variant === 'empty' ? {...item, rows: [], expected: []} : item;
          const f = await fixture(t, transport, selected, cancel);
          const document = await readFile(new URL('./fixtures/' + item.file, import.meta.url), 'utf8');
          const options = {format: 'json', requestId: `${item.name}-${variant}`,
            ...(item.parameters === undefined ? {} : {parameters: item.parameters})};
          const run = await f.client.aql(document, options);
          if (cancel) {
            await Promise.race([f.barrier.promise, run.wait().then(state => {
              throw new Error(`Run ended before cancellation barrier: ${JSON.stringify(state)}`);
            })]);
            try {
              await run.cancel();
              const pending = await run.status();
              assert.equal(pending.control.cancellation_requested, true);
              assert.notEqual(pending.control.physical_stop, 'confirmed');
            } finally { f.release.resolve(); }
          }
          const state = await run.wait({signal: AbortSignal.timeout(30_000)});
          await writeFile(join(f.directory, 'receipt.json'), JSON.stringify({
            source: provenance,
            node: process.version, transport, case: item.name, variant,
            inputSha256: createHash('sha256').update(document).digest('hex'),
            state, ...f.counts()}, null, 2));
          assert.equal(f.counts().sessions, 1);
          assert.equal(state.status, cancel ? 'cancelled' : 'succeeded', JSON.stringify(state));
          assert.equal(state.control.physical_stop, 'confirmed');
          if (cancel) {
            assert.equal(state.result_availability.answer.state, 'unavailable');
            await assert.rejects(run.result('answer').all(), {code: 'ResultAccessDenied'});
            await assert.rejects(run.result('answer').describe(), {code: 'ResultAccessDenied'});
          } else {
            assert.deepEqual(await run.result('answer').all(), selected.expected);
            assert.deepEqual((await run.result('answer').describe()).columns, item.columns);
          }
          const counts = f.counts();
          const attached = await f.client.attach(run.ref);
          const repeated = await f.client.aql(document, options);
          assert.deepEqual(repeated.ref, run.ref);
          assert.deepEqual((await f.client.lookupRequest(options.requestId)).ref, run.ref);
          assert.equal((await attached.status()).status, state.status);
          if (!cancel) assert.deepEqual(await attached.result('answer').all(), selected.expected);
          assert.deepEqual(f.counts(), counts, 'read/attach/replay cannot reacquire or recompute');
          assert.deepEqual(await f.cleaned(), [], 'temporary input/output files are reclaimed');
        });
    }
  }
}
