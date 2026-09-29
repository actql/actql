// Copied unchanged into the external tarball installation by the driver.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';
import {exercisePublicQueryInput, sourceRows} from './public-query-input.mjs';

assert.equal(spawnSync('moon', ['version']).error?.code, 'ENOENT');
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const environment = JSON.parse(await readFile('source-environment.json', 'utf8'));
const base = JSON.parse(await readFile('base-environment.json', 'utf8'));
environment.host_policy_profile = base.host_policy_profile;
environment.connector_capabilities[0].capability_contract_cids.push(
  'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
environment.connector_capabilities[0].capability_contract_cids.sort();
delete environment.evidence_bundle_cid;
environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
  .update(canonical(environment)).digest('hex');
const database = resolve('records.duckdb');
const {DuckDBInstance, DuckDBPreparedStatement} = createRequire(
  new URL('./node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
const instance = await DuckDBInstance.create(database);
const connection = await instance.connect();
try {
  await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  for (const row of sourceRows) {
    await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
  }
} finally {
  connection.closeSync();
  instance.closeSync();
}
const view = environment.source_views[0];
const sourceProfilePath = resolve('source-profile.json');
await writeFile(sourceProfilePath, canonical({
  version: 'actql-installed-duckdb-source/0.1', database,
  schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
  queryAliases: [{name: 'records', sourceRef: 'connector://crm/main/r#v',
    sourceViewContractCid: view.contract_cid,
    schemaContractCid: view.output.schema.cid}],
  checkEnvironmentWire: canonical(environment),
  accountConfigurationWire: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-query',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}]}),
}));
// Observe actual native execution, never a diagnostic notification.
let sourceIo = 0;
const stream = DuckDBPreparedStatement.prototype.stream;
DuckDBPreparedStatement.prototype.stream = function(...args) {
  sourceIo++;
  return Reflect.apply(stream, this, args);
};
const observe = directory => () => {
  const journal = new DatabaseSync(resolve(directory, 'requests',
    'client-requests.sqlite3'), {readOnly: true});
  try {
    return {sourceIo, acceptedRuns: journal.prepare(
      'SELECT COUNT(*) AS count FROM client_requests').get().count};
  } finally { journal.close(); }
};
await exercisePublicQueryInput(connect, {mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: resolve('local-state'),
    sourceProfilePath}}, {requestPrefix: 'packed-local',
  observe: observe('local-state')});
assert.equal(observe('local-state')().acceptedRuns, 5);
assert.ok(sourceIo >= 5);
console.log('packed raw SQL/Pipe Embedded Local acceptance passed');
const beforeRemote = sourceIo;
const host = await openInstalledRemoteHttpHost({
  directory: resolve('remote-state'), sourceProfilePath,
  authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined,
});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await exercisePublicQueryInput(connect, {mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-token', durability: 'durable'},
  {requestPrefix: 'packed-http', observe: observe('remote-state')});
  assert.equal(observe('remote-state')().acceptedRuns, 5);
  assert.ok(sourceIo >= beforeRemote + 5);
  console.log('packed raw SQL/Pipe HTTP acceptance passed');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
}
