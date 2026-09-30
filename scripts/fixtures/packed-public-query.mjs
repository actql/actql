// Copied unchanged into the external tarball installation by the driver.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
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
const sgaCases = ['normalize-rows', 'mean-graphs', 'traverse-paths',
  'shortest-path',
  'reach-selector', 'reach-selector-duplicates', 'reach-selector-empty',
  'reach-selector-nullable',
  'union-graphs', 'graft-graphs', 'subtract-graphs', 'degree-rows',
  'components', 'graph-bounds', 'match-projections', 'reach-subgraph',
  'graphs-equal', 'diff-apply'];
const selectedSgaCases = process.env.ACTQL_TEST_SGA_CASES === undefined
  ? sgaCases : process.env.ACTQL_TEST_SGA_CASES.split(',');
if (selectedSgaCases.length === 0 ||
    new Set(selectedSgaCases).size !== selectedSgaCases.length ||
    selectedSgaCases.some(name => !sgaCases.includes(name))) {
  throw new Error('Invalid selected SGA acceptance cases');
}
// Nullable selector acceptance also starts two well-typed failing Runs.
// Its schema-type refusal must not add a third Run.
const expectedSgaRuns = selectedSgaCases.length +
  (selectedSgaCases.includes('reach-selector-nullable') ? 2 : 0) +
  (selectedSgaCases.includes('reach-selector') ? 2 : 0);
if (selectedSgaCases.includes('reach-selector')) {
  assert.equal(environment.host_policy_profile.capacity.max_graph_output_rows,
    1000, 'Reach capacity acceptance requires the actual 1,000-row Host ceiling');
}
const sgaFixtureDirectory = resolve('sga-fixtures');
await mkdir(sgaFixtureDirectory);
for (const name of sgaCases) {
  for (const suffix of ['named.aql', 'expected-results.json']) {
    await writeFile(resolve(sgaFixtureDirectory, `${name}.${suffix}`),
      await readFile(resolve('sga-source-fixtures', `${name}.${suffix}`)));
  }
}
const sgaFailures = [];
async function exerciseSga(mode, extraEnv) {
  for (const name of selectedSgaCases) {
    const child = spawn(process.execPath,
      ['accept-sga-public-source.mjs', resolve('.'), sgaFixtureDirectory,
        mode, name],
      {env: {...process.env, ...extraEnv}, stdio: ['ignore', 'pipe', 'pipe']});
    const output = [];
    for (const stream of [child.stdout, child.stderr]) {
      stream.on('data', chunk => output.push(chunk));
    }
    const code = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', resolve);
    });
    const diagnostic = Buffer.concat(output).toString();
    if (code !== 0) {
      sgaFailures.push({mode, name, code});
      console.error(`packed SGA ${mode}/${name} failed (${code}): ${diagnostic}`);
    } else {
      console.log(diagnostic.trimEnd());
    }
  }
}
await exercisePublicQueryInput(connect, {mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: resolve('local-state'),
    sourceProfilePath}}, {requestPrefix: 'packed-local',
  observe: observe('local-state')});
assert.equal(observe('local-state')().acceptedRuns, 5);
assert.ok(sourceIo >= 5);
console.log('packed raw SQL/Pipe Embedded Local acceptance passed');
await exerciseSga('local', {ACTQL_LOCAL_STATE_DIR: resolve('sga-local-state'),
  ACTQL_TEST_LOCAL_SOURCE_PROFILE: sourceProfilePath});
assert.equal(observe('sga-local-state')().acceptedRuns, expectedSgaRuns);
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
  const beforeSga = observe('remote-state')();
  await exerciseSga('remote', {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${server.address().port}/`,
    ACTQL_TEST_REMOTE_TOKEN: 'fixture-token',
  });
  const afterSga = observe('remote-state')();
  assert.equal(afterSga.acceptedRuns - beforeSga.acceptedRuns,
    expectedSgaRuns);
  assert.equal(afterSga.sourceIo, beforeSga.sourceIo);
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
}
// Exercise both transports before rejecting the acceptance run. A failed
// case remains a failure; the other transport provides independent evidence.
assert.deepEqual(sgaFailures, [], 'Packed SGA acceptance failures');
