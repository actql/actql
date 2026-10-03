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
  '@actql/local-node/http-host';
import {exercisePublicQueryInput, querySuccesses, queryRefusals, inferRefusals, sourceRows, sourceFreeSuccesses, sourceFreeRefusals, queryCompositionSuccesses, queryCompositionRefusals, pipeResultSuccesses, pipeResultRefusals, pipeResultExecutionFailures}
  from './public-query-input.mjs';

if (process.env.ACTQL_TEST_TWO_SOURCE_ONLY === '1') {
  await import('./packed-two-source-public-query.mjs');
} else {
const sourceFreeOnly = process.env.ACTQL_TEST_SOURCE_FREE_ONLY === '1';
const inferOnly = process.env.ACTQL_TEST_INFER_REFUSAL_ONLY === '1';
const joinOnly = process.env.ACTQL_TEST_JOIN_ORDER_ONLY === '1';
const compositionOnly = process.env.ACTQL_TEST_QUERY_COMPOSITION_ONLY === '1';
const resultOnly = process.env.ACTQL_TEST_PIPE_RESULT_ONLY === '1';
const dataSetStrategyOnly = process.env.ACTQL_TEST_DATA_SET_STRATEGY_ONLY === '1';
const scopeOnly = process.env.ACTQL_TEST_PIPE_SCOPE_ONLY === '1' || inferOnly || joinOnly || sourceFreeOnly || compositionOnly || resultOnly || dataSetStrategyOnly;
const joinOrder = JSON.parse(await readFile('join-order-cases.json', 'utf8'));
const scope = JSON.parse(await readFile('pipe-scope-cases.json', 'utf8'));
assert.deepEqual(scope.source_rows, sourceRows);
const dataSetStrategyInputs = {
  // Independent machine input bypasses the frontend. Values are deliberately
  // opposite to the required order; the internal sort slot must not escape.
  successes: [{name: 'independent-ordered-data-set', format: 'json',
    text: await readFile('data-set-strategy-program.json', 'utf8'),
    sourceReadCount: 0,
    results: {nodes: {rows: [{id: 1}], columns: [
      {name: 'id', contract: {type: 'number', nullable: false}},
    ]}}}],
  refusals: [],
};
const scopeInputs = dataSetStrategyOnly ? dataSetStrategyInputs
  : sourceFreeOnly ? {successes: sourceFreeSuccesses, refusals: sourceFreeRefusals}
  : resultOnly ? {successes: pipeResultSuccesses, refusals: pipeResultRefusals,
    executionFailures: pipeResultExecutionFailures}
  : compositionOnly ? {successes: queryCompositionSuccesses, refusals: queryCompositionRefusals}
  : inferOnly ? {successes: [querySuccesses[0]], refusals: inferRefusals}
  : joinOnly ? joinOrder : scopeOnly ? {successes: scope.successes,
  refusals: scope.refusals} : {successes: [...dataSetStrategyInputs.successes, ...querySuccesses, ...sourceFreeSuccesses, ...queryCompositionSuccesses, ...pipeResultSuccesses, ...scope.successes, ...joinOrder.successes],
  refusals: [...queryRefusals, ...sourceFreeRefusals, ...queryCompositionRefusals, ...pipeResultRefusals, ...scope.refusals, ...inferRefusals, ...joinOrder.refusals],
  executionFailures: pipeResultExecutionFailures};
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
  for (const suffix of ['named.aql', 'expected-program.json', 'expected-results.json']) {
    await writeFile(resolve(sgaFixtureDirectory, `${name}.${suffix}`),
      await readFile(resolve('sga-source-fixtures', `${name}.${suffix}`)));
  }
}
const sgaFailures = [];
async function exerciseSga(mode, extraEnv) {
  if (scopeOnly) return;
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
await exerciseSga('local', {ACTQL_LOCAL_STATE_DIR: resolve('sga-local-state'),
  ACTQL_TEST_LOCAL_SOURCE_PROFILE: sourceProfilePath});
if (!scopeOnly) assert.equal(observe('sga-local-state')().acceptedRuns, expectedSgaRuns);
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
  const beforeSga = observe('remote-state')();
  await exerciseSga('remote', {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${server.address().port}/`,
    ACTQL_TEST_REMOTE_TOKEN: 'fixture-token',
  });
  const afterSga = observe('remote-state')();
  assert.equal(afterSga.acceptedRuns - beforeSga.acceptedRuns,
    scopeOnly ? 0 : expectedSgaRuns);
  assert.equal(afterSga.sourceIo, beforeSga.sourceIo);
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
  DuckDBConnection.prototype.extractStatements = extract;
  DuckDBExtractedStatements.prototype.prepare = prepare;
}
// Exercise both transports before rejecting the acceptance run. A failed
// case remains a failure; the other transport provides independent evidence.
assert.deepEqual(sgaFailures, [], 'Packed SGA acceptance failures');

if (retainedStrings.local && retainedStrings.remote) {
  await writeFile('retained-string-results.json', JSON.stringify(retainedStrings));

}
if (!scopeOnly) await import('./packed-two-source-public-query.mjs');
}
