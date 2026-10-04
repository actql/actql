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
  '@actql/local-node/http-host';
import {exercisePublicQueryInput, querySuccesses, queryRefusals, inferRefusals, sourceRows, sourceFreeSuccesses, sourceFreeRefusals, queryCompositionSuccesses, queryCompositionRefusals, pipeResultSuccesses, pipeResultRefusals, pipeResultExecutionFailures, relationDataSuccesses, relationDataRefusals}
  from './public-query-input.mjs';

import {propertyGraphSourceSuccesses, propertyGraphSourceExecutionFailures, propertyGraphSourceRefusals}
  from "./property-graph-source-input.mjs";
import {uniquePublicQueryCases} from './public-query-cases.mjs';
import {acquiredDataSuccesses, acquiredGraphSourceSuccesses, acquiredDataRefusals}
  from './acquired-data-source-input.mjs';

if (process.env.ACTQL_TEST_TWO_SOURCE_ONLY === '1') {
  await import('./packed-two-source-public-query.mjs');
} else {
const propertyGraphOnly = process.env.ACTQL_TEST_PROPERTY_GRAPH_SOURCE_ONLY === "1";
const scopedOrderOnly = process.env.ACTQL_TEST_SCOPED_ORDER_ONLY === '1';
const sourceFreeOnly = process.env.ACTQL_TEST_SOURCE_FREE_ONLY === '1';
const inferOnly = process.env.ACTQL_TEST_INFER_REFUSAL_ONLY === '1';
const joinOnly = process.env.ACTQL_TEST_JOIN_ORDER_ONLY === '1';
const groupOnly = process.env.ACTQL_TEST_GROUP_SCOPE_ONLY === '1';
const compositionOnly = process.env.ACTQL_TEST_QUERY_COMPOSITION_ONLY === '1';
const resultOnly = process.env.ACTQL_TEST_PIPE_RESULT_ONLY === '1';
const dataOnly = process.env.ACTQL_TEST_RELATION_DATA_ONLY === '1';
const acquiredDataOnly = process.env.ACTQL_TEST_ACQUIRED_DATA_ONLY === '1';
const dataSetStrategyOnly = process.env.ACTQL_TEST_DATA_SET_STRATEGY_ONLY === '1';
const scopeOnly = process.env.ACTQL_TEST_PIPE_SCOPE_ONLY === '1' || scopedOrderOnly || inferOnly || joinOnly || groupOnly || sourceFreeOnly || compositionOnly || resultOnly || dataOnly || acquiredDataOnly || dataSetStrategyOnly || propertyGraphOnly;
const joinOrder = JSON.parse(await readFile('join-order-cases.json', 'utf8'));
const joinChain = JSON.parse(await readFile('join-chain-cases.json', 'utf8'));
const groupScope = JSON.parse(await readFile('group-scope-cases.json', 'utf8'));
const scope = JSON.parse(await readFile('pipe-scope-cases.json', 'utf8'));
assert.deepEqual(scope.source_rows, sourceRows);
const dataSetStrategyInputs = {
  // Retain main's independent JSON control once. The DATA source group shares
  // this input rather than duplicating the same machine Program and run.
  successes: [{name: 'independent-ordered-data-set', format: 'json',
    text: await readFile('data-set-strategy-program.json', 'utf8'),
    sourceReadCount: 0,
    results: {nodes: {rows: [{id: 1}], columns: [
      {name: 'id', contract: {type: 'number', nullable: false}},
    ]}}}],
  refusals: [],
};
const scopeInputs = scopedOrderOnly ? {
  successes: scope.successes.filter(item => item.name.startsWith('scoped-order-')),
  refusals: scope.refusals.filter(item => item.name.startsWith('scoped-order-')),
} : propertyGraphOnly ? {successes: propertyGraphSourceSuccesses,
  executionFailures: propertyGraphSourceExecutionFailures, refusals: propertyGraphSourceRefusals}
  : acquiredDataOnly ? {successes: [...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses],
    refusals: acquiredDataRefusals}
  : dataOnly ? {successes: [...relationDataSuccesses,
  ...dataSetStrategyInputs.successes], refusals: relationDataRefusals}
  : dataSetStrategyOnly ? dataSetStrategyInputs
  : sourceFreeOnly ? {successes: sourceFreeSuccesses, refusals: sourceFreeRefusals}
  : resultOnly ? {successes: pipeResultSuccesses, refusals: pipeResultRefusals,
    executionFailures: pipeResultExecutionFailures}
  : compositionOnly ? {successes: queryCompositionSuccesses, refusals: queryCompositionRefusals}
  : inferOnly ? {successes: [querySuccesses[0]], refusals: inferRefusals}
  : groupOnly ? groupScope : joinOnly ? joinOrder : scopeOnly ? {successes: scope.successes,
  refusals: scope.refusals} : {successes: [...dataSetStrategyInputs.successes, ...querySuccesses, ...sourceFreeSuccesses, ...queryCompositionSuccesses, ...pipeResultSuccesses, ...relationDataSuccesses, ...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses, ...propertyGraphSourceSuccesses, ...scope.successes, ...joinOrder.successes],
  refusals: [...queryRefusals, ...sourceFreeRefusals, ...queryCompositionRefusals, ...pipeResultRefusals, ...relationDataRefusals, ...acquiredDataRefusals, ...propertyGraphSourceRefusals, ...scope.refusals, ...inferRefusals, ...joinOrder.refusals],
  executionFailures: [...pipeResultExecutionFailures, ...propertyGraphSourceExecutionFailures]};
if (!scopeOnly) {
  scopeInputs.successes.push(...joinChain.successes);
  scopeInputs.refusals.push(...joinChain.refusals);
  scopeInputs.successes.push(...groupScope.successes);
  scopeInputs.refusals.push(...groupScope.refusals);
}
scopeInputs.successes = uniquePublicQueryCases(scopeInputs.successes);
if (scopedOrderOnly) {
  assert.equal(scopeInputs.successes.length, 4);
  assert.equal(scopeInputs.refusals.length, 1);
}
const expectedQueryRuns = scopeInputs.successes.length + (scopeInputs.executionFailures?.length ?? 0);
const expectedSourceReads = [...scopeInputs.successes, ...(scopeInputs.executionFailures ?? [])]
  .reduce((count, item) => count + (item.sourceReadCount ?? item.sourceReadSessionCount ?? 1), 0);

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
const {DuckDBInstance, DuckDBPreparedStatement, DuckDBConnection,
  DuckDBExtractedStatements} = createRequire(
  new URL('./node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
// Provider-confirmed independent rows for canonically equivalent physical names.
const exactTargetPairs = [
  {field: 'table', targets: [
    {schema: 'main', table: 'caf\u00e9', rows: [{id: 101, amount: 11}]},
    {schema: 'main', table: 'cafe\u0301', rows: [{id: 202, amount: 22}]},
  ]},
  {field: 'schema', targets: [
    {schema: 'caf\u00e9', table: 'records', rows: [{id: 303, amount: 33}]},
    {schema: 'cafe\u0301', table: 'records', rows: [{id: 404, amount: 44}]},
  ]},
];
const physicalSqlName = target => `"${target.schema}"."${target.table}"`;
const instance = await DuckDBInstance.create(database);
const connection = await instance.connect();
try {
  await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  for (const row of sourceRows) {
    await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
  }
  for (const {targets} of scopeOnly ? [] : exactTargetPairs) {
    for (const target of targets) {
      if (target.schema !== 'main') await connection.run(`CREATE SCHEMA "${target.schema}"`);
      await connection.run(`CREATE TABLE ${physicalSqlName(target)}(id DOUBLE, amount DOUBLE)`);
      for (const row of target.rows) await connection.run(
        `INSERT INTO ${physicalSqlName(target)} VALUES (?, ?)`, [row.id, row.amount]);
      const observed = await connection.runAndReadAll(
        `SELECT id, amount FROM ${physicalSqlName(target)} ORDER BY id`);
      assert.deepEqual(observed.getRowObjectsJS(), target.rows);
    }
  }
} finally {
  connection.closeSync();
  instance.closeSync();
}
// Install hand-authored rows in the real DuckDB source before each case.
// Source identity/schema stay fixed; the ordinary acquisition captures the
// current contents. No rows are injected into the Client or frontend.
let installedRows = sourceRows;
async function prepareCase(rows = sourceRows) {
  if (JSON.stringify(rows) === JSON.stringify(installedRows)) return;
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('DELETE FROM records');
    for (const row of rows) {
      await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
    }
    installedRows = rows;
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
}
const view = environment.source_views[0];
const sourceProfilePath = resolve('source-profile.json');
await writeFile(sourceProfilePath, canonical({
  acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
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
let sourceIo = 0, sourceReads = 0, sourceReadSessions = 0;
const sourceReadCommands = [];
const extractedSql = new WeakMap(), preparedSql = new WeakMap();
const extractedConnection = new WeakMap(), preparedConnection = new WeakMap();
const readSessions = new WeakMap();
const extract = DuckDBConnection.prototype.extractStatements;
const prepare = DuckDBExtractedStatements.prototype.prepare;
DuckDBConnection.prototype.extractStatements = async function(sql) {
  const statements = await Reflect.apply(extract, this, [sql]);
  extractedSql.set(statements, sql);
  extractedConnection.set(statements, this);
  return statements;
};
DuckDBExtractedStatements.prototype.prepare = async function(index) {
  const statement = await Reflect.apply(prepare, this, [index]);
  preparedSql.set(statement, extractedSql.get(this));
  preparedConnection.set(statement, extractedConnection.get(this));
  return statement;
};
const stream = DuckDBPreparedStatement.prototype.stream;
DuckDBPreparedStatement.prototype.stream = function(...args) {
  sourceIo++;
  // Distinguish the real source-table acquisition from identity/metadata I/O
  // and Local resident computation. This observes emitted physical SQL only.
  if (/\bFROM\s+(?:"main"\.)?"records"(?=\s|$)/iu.test(preparedSql.get(this) ?? '')) {
    sourceReads++;
    // withSourceAcquisition opens one private connection/read view per owner.
    // Native acquisition intentionally uses two row receipts in that same
    // connection (validation_scan and native_result); count those transfers
    // separately from repeated acquisition sessions.
    const connection = preparedConnection.get(this);
    assert.ok(connection, 'source statement retains its actual native connection');
    if (!readSessions.has(connection)) readSessions.set(connection, ++sourceReadSessions);
    sourceReadCommands.push({session: readSessions.get(connection), sql: preparedSql.get(this),
      columns: Array.from({length: this.columnCount}, (_, index) => this.columnName(index))});
  }
  return Reflect.apply(stream, this, args);
};
const observe = directory => () => {
  const journal = new DatabaseSync(resolve(directory, 'requests',
    'client-requests.sqlite3'), {readOnly: true});
  try {
    return {sourceIo, sourceReads, sourceReadSessions, sourceReadCommands, acceptedRuns: journal.prepare(
      'SELECT COUNT(*) AS count FROM client_requests').get().count};
  } finally { journal.close(); }
};
// Current Graph acceptance runs in the driver's shared public Host regression:
// constructor/MATCH/TRAIL, physical snapshot roundtrip and inventory-derived
// pre-admission refusals. Retired SGA fixtures are not execution coverage.
// Public check must also work from installed tarballs, without repository imports.
async function exercisePublicCheck(options) {
  const client = await connect(options);
  const first = await client.check('SELECT 1 AS n', {format: 'sql'});
  assert.equal(first.report.verdict, 'verified');
  assert.deepEqual(await client.check('SELECT 1 AS n', {format: 'sql'}), first);
  const invalid = await client.check('SELECT missing AS n', {format: 'sql'});
  assert.equal(invalid.report.verdict, 'invalid');
  assert.notEqual(invalid.report.context_ref, first.report.context_ref);
  for (const pair of [['e\u0301', 'é'], ['\r', '\n']]) {
    const refs = [];
    for (const x of pair) {
      const result = await client.check('SELECT @x AS n', {format: 'sql',
        parameterDeclarations: {x: {type: 'string'}}, parameters: {x}});
      assert.equal(result.report.verdict, 'verified');
      refs.push(result.report.context_ref);
    }
    assert.notEqual(refs[0], refs[1]);
  }
  const budget = await client.check('SELECT id FROM never_configured', {
    format: 'sql', parameterDeclarations: {x: {type: 'array', items: {type: 'number'}}},
    parameters: {x: Array(9000).fill(1)}});
  assert.equal(budget.report.verdict, 'undetermined');
  assert.deepEqual(budget.report.reasons, []);
  assert.deepEqual(budget.report.coverage, {
    limits: [{code: 'analysis_budget_exhausted'}],
    unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
  console.log(`packed public check ${options.mode} passed`);
}
await exercisePublicCheck({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('local-state'), sourceProfilePath}});
// Extend the same public harness; no second lifecycle/fault matrix. Each
// physical spelling has independently authored rows and its own explicit Host.
async function exerciseExactPhysicalTargets() {
  const baseProfile = JSON.parse(await readFile(sourceProfilePath, 'utf8'));
  for (const {field, targets} of exactTargetPairs) {
    const path = resolve(`exact-${field}-source.json`);
    const firstDirectory = resolve(`exact-${field}-local-0`);
    const firstOptions = {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: firstDirectory, sourceProfilePath: path}};
    for (const [index, target] of targets.entries()) {
      const profile = {...baseProfile, schema: target.schema, table: target.table};
      await writeFile(path, JSON.stringify(profile));
      if (index === 1) {
        const before = observe(firstDirectory)();
        await assert.rejects(connect(firstOptions),
          {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
        assert.deepEqual(observe(firstDirectory)(), before,
          'changing only the physical target must refuse without provider I/O');
      }
      const directory = resolve(`exact-${field}-local-${index}`);
      const options = {...firstOptions, installation: {directory, sourceProfilePath: path}};
      const fixture = {name: `exact-${field}-${index}`, format: 'sql',
        text: 'SELECT id, amount FROM records ORDER BY id',
        expected: target.rows, columns: [
          {name: 'id', contract: {type: 'number', nullable: false}},
          {name: 'amount', contract: {type: 'number', nullable: true}},
        ]};
      await exercisePublicQueryInput(connect, options, {
        requestPrefix: 'exact-local', observe: observe(directory),
        successes: [fixture], refusals: []});
      const before = observe(directory)();
      await writeFile(path, JSON.stringify(Object.fromEntries(
        Object.entries(profile).reverse()), null, 2) + '\n');
      const unchanged = await connect(options);
      unchanged.close();
      assert.deepEqual(observe(directory)(), before,
        'unchanged target with reordered JSON must reuse without provider I/O');
      const remoteDirectory = resolve(`exact-${field}-remote-${index}`);
      const remoteHost = await openInstalledRemoteHttpHost({directory: remoteDirectory,
        sourceProfilePath: path, authenticate: header => header === 'Bearer fixture-token'
          ? userInfo().username : undefined});
      const remoteServer = createServer({key: await readFile('remote.key'),
        cert: await readFile('remote.crt')}, remoteHost.handler);
      try {
        await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
        await exercisePublicQueryInput(connect, {mode: 'remote',
          endpoint: `https://127.0.0.1:${remoteServer.address().port}/`,
          token: 'fixture-token', durability: 'durable'}, {
          requestPrefix: 'exact-http', observe: observe(remoteDirectory),
          successes: [fixture], refusals: []});
      } finally {
        remoteServer.closeAllConnections();
        await new Promise(resolve => remoteServer.close(resolve));
        await remoteHost.close();
      }
    }
  }
}
const retainedStrings = {};
const recordString = mode => item => {
  if (item.name === 'exact-string-values') retainedStrings[mode] = item;
};
await exercisePublicQueryInput(connect, {mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: resolve('local-state'),
    sourceProfilePath}}, {requestPrefix: 'packed-local',
  observe: observe('local-state'), prepareCase, completedCase: recordString('local'), ...scopeInputs});
assert.equal(observe('local-state')().acceptedRuns, expectedQueryRuns);
assert.ok(sourceIo >= expectedSourceReads);
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
  await exercisePublicCheck({mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'});
  await exercisePublicQueryInput(connect, {mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-token', durability: 'durable'},
  {requestPrefix: 'packed-http', observe: observe('remote-state'), prepareCase, completedCase: recordString('remote'), ...scopeInputs});
  assert.equal(observe('remote-state')().acceptedRuns, expectedQueryRuns);
  assert.ok(sourceIo >= beforeRemote + expectedSourceReads);
  console.log('packed raw SQL/Pipe HTTP acceptance passed');
  if (!scopeOnly) await exerciseExactPhysicalTargets();
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
  DuckDBConnection.prototype.extractStatements = extract;
  DuckDBExtractedStatements.prototype.prepare = prepare;
}
if (retainedStrings.local && retainedStrings.remote) {
  await writeFile('retained-string-results.json', JSON.stringify(retainedStrings));

}
if (!scopeOnly) await import('./packed-two-source-public-query.mjs');
}
