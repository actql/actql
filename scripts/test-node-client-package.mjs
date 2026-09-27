import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'node-client-package-'));
const cache = join(root, 'npm-cache');
const environment = {...process.env, npm_config_cache: cache,
  ACTQL_LOCAL_STATE_DIR: join(root, 'local-state')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: command === 'npm' && args[0] === 'pack' ? 180000 : 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

function runAsync(command, args, cwd, extraEnvironment = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd,
      env: {...environment, ...extraEnvironment}});
    let output = '';
    child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(output) :
      reject(new Error(`${command} ${args.join(' ')} failed:\n${output}`)));
  });
}

// PR-2 uses a test-only source adapter; the installed Client and Host retain
// their ordinary JSON admission and execution path. Raw-text SDK routing is
// intentionally a separate delivery unit.
run('moon', ['build', '--target', 'js', 'src/aql_text_test_bridge'], repository);
run('node', ['--test', 'scripts/aql-text.test.mjs'], repository);
run('moon', ['build', '--target', 'js', 'src/query_program_test_bridge'],
  repository);
run('node', ['--test', 'scripts/query-program.test.mjs'], repository);
const frontend = await import(pathToFileURL(join(repository,
  '_build/js/debug/build/aql_text_test_bridge/aql_text_test_bridge.js')));
const structuralValues = frontend.structuralToJson(await readFile(join(repository,
  'spec/frontend/fixtures/client-values.structural.aql'), 'utf8'));
assert.deepEqual(JSON.parse(structuralValues), JSON.parse(await readFile(
  join(repository, 'packages/sdk/fixtures/values.json'), 'utf8')));

for (const name of ['client-wire', 'sdk', 'local-node',
  'node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
}
const sdk = join(root, 'actql-sdk-0.0.0-development.tgz');
const node = join(root, 'actql-node-0.0.0-development.tgz');
const wire = join(root, 'actql-client-wire-0.0.0-development.tgz');
const local = join(root, 'actql-local-node-0.0.0-development.tgz');
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save',
  wire, sdk, local, node],
  root);
assert.deepEqual((await readdir(join(root, 'node_modules', '@actql'))).sort(),
  ['client-wire', 'local-node', 'node', 'sdk']);
for (const name of ['client-host.generated.js',
  'client-host.generated.d.ts']) {
  assert((await readFile(join(root, 'node_modules', '@actql',
    'client-wire', name), 'utf8')).length > 0);
}
for (const name of ['host-port.mjs', 'host-port.d.ts']) {
  assert((await readFile(join(root, 'node_modules', '@actql',
    'sdk', name), 'utf8')).length > 0);
}
await writeFile(join(root, 'values.json'), structuralValues);
const sourceProgram = await readFile(join(repository,
  'adapters/connectors/duckdb/node/examples/program.json'), 'utf8');
const sourceRoundtrip = frontend.structuralToJson(
  frontend.jsonToStructural(sourceProgram));
assert.deepEqual(JSON.parse(sourceRoundtrip), JSON.parse(sourceProgram));
await writeFile(join(root, 'source-program.json'), sourceRoundtrip);
const queryFrontend = await import(pathToFileURL(join(repository,
  '_build/js/debug/build/query_program_test_bridge/query_program_test_bridge.js')));
const valuesStep = JSON.parse(structuralValues).stages[0].steps[0];
const valuesQuery = queryFrontend.compileValuesQueryJson(
  'SELECT * FROM rows', 'rows', 'selected', JSON.stringify(valuesStep),
  JSON.stringify(['id']), 'fixture.values_query');
assert.notEqual(valuesQuery, '');
await writeFile(join(root, 'query-values.json'), valuesQuery);
const computedValuesQuery = queryFrontend.compileValuesQueryJson(
  'SELECT id FROM rows WHERE id > 1', 'rows', 'selected',
  JSON.stringify(valuesStep), JSON.stringify(['id']),
  'fixture.computed_values_query');
assert.notEqual(computedValuesQuery, '');
await writeFile(join(root, 'query-computed-values.json'),
  computedValuesQuery);
const aliasRows = {values: {schema: {
  x: {type: 'number', nullable: false},
  y: {type: 'number', nullable: false}},
rows: [{x: 2, y: 1}, {x: 1, y: 2}]}, as: 'rows'};
for (const [name, sql] of [
  ['alias-order', 'SELECT x AS y FROM rows ORDER BY y'],
  ['hidden-order', 'SELECT x FROM rows ORDER BY y'],
]) {
  const query = queryFrontend.compileValuesQueryJson(sql, 'rows', 'rows',
    JSON.stringify(aliasRows), JSON.stringify(['x', 'y']),
    `fixture.${name}`);
  assert.notEqual(query, '', name);
  await writeFile(join(root, `${name}.json`), query);
}
const concatQuery = queryFrontend.compileValuesQueryJson(
  "SELECT CONCAT('a', NULL) AS strict, ACTQL.CONCAT('a', NULL) "
    + 'AS legacy FROM rows',
  'rows', 'rows', JSON.stringify(aliasRows), JSON.stringify(['x', 'y']),
  'fixture.concat_null');
assert.notEqual(concatQuery, '');
await writeFile(join(root, 'concat-query.json'), concatQuery);
const valuesCteQuery = queryFrontend.compileValuesQueryJson(
  'WITH chosen AS (SELECT x, y FROM rows WHERE x > 0) '
    + 'SELECT x FROM chosen',
  'rows', 'rows', JSON.stringify(aliasRows), JSON.stringify(['x', 'y']),
  'fixture.values_cte');
assert.notEqual(valuesCteQuery, '');
await writeFile(join(root, 'values-cte-query.json'), valuesCteQuery);
const setLeft = {values: {schema: {
  a: {type: 'number', nullable: true},
  b: {type: 'string', nullable: false}},
rows: [{a: 1, b: 'x'}, {a: 1, b: 'x'}, {a: 2, b: 'y'},
  {a: null, b: 'n'}]}, as: 'set_left'};
const setRight = {values: {schema: {
  c: {type: 'number', nullable: true},
  d: {type: 'string', nullable: false}},
rows: [{c: 1, d: 'x'}, {c: 3, d: 'z'}, {c: null, d: 'n'}]},
as: 'set_right'};
const setQuery = queryFrontend.compileTwoValuesSetQueryJson(
  'SELECT a, b FROM set_left UNION ALL SELECT c, d FROM set_right',
  'set_left', JSON.stringify(setLeft), JSON.stringify(['a', 'b']),
  'set_right', JSON.stringify(setRight), JSON.stringify(['c', 'd']),
  'fixture.set_query');
assert.notEqual(setQuery, '');
await writeFile(join(root, 'set-query.json'), setQuery);
const pipeUnionQuery = queryFrontend.compileTwoValuesSetQueryJson(
  'FROM set_left |> SELECT a, b |> UNION ALL '
    + '(SELECT c, d FROM set_right)',
  'set_left', JSON.stringify(setLeft), JSON.stringify(['a', 'b']),
  'set_right', JSON.stringify(setRight), JSON.stringify(['c', 'd']),
  'fixture.set_query');
assert.deepEqual(JSON.parse(pipeUnionQuery), JSON.parse(setQuery));
await writeFile(join(root, 'pipe-union-query.json'), pipeUnionQuery);
const setQueries = [
  ['union-distinct', 'UNION DISTINCT'],
  ['intersect-distinct', 'INTERSECT DISTINCT'],
  ['except-distinct', 'EXCEPT DISTINCT'],
];
for (const [name, operator] of setQueries) {
  const query = queryFrontend.compileTwoValuesSetQueryJson(
    `SELECT a, b FROM set_left ${operator} SELECT c, d FROM set_right`,
    'set_left', JSON.stringify(setLeft), JSON.stringify(['a', 'b']),
    'set_right', JSON.stringify(setRight), JSON.stringify(['c', 'd']),
    `fixture.${name}`);
  assert.notEqual(query, '', name);
  await writeFile(join(root, `${name}.json`), query);
}
const joinCases = [
  ['inner', [{a: 1, d: 'x'}, {a: 1, d: 'x'}]],
  ['left', [{a: 1, d: 'x'}, {a: 1, d: 'x'},
    {a: 2, d: null}, {a: null, d: null}]],
  ['cross', [
    {a: 1, d: 'x'}, {a: 1, d: 'z'}, {a: 1, d: 'n'},
    {a: 1, d: 'x'}, {a: 1, d: 'z'}, {a: 1, d: 'n'},
    {a: 2, d: 'x'}, {a: 2, d: 'z'}, {a: 2, d: 'n'},
    {a: null, d: 'x'}, {a: null, d: 'z'}, {a: null, d: 'n'},
  ]],
];
for (const [kind] of joinCases) {
  const clause = kind === 'cross'
    ? 'CROSS JOIN set_right AS r'
    : `${kind.toUpperCase()} JOIN set_right AS r ON l.a = r.c`;
  const query = queryFrontend.compileTwoValuesSetQueryJson(
    `SELECT l.a AS a, r.d AS d FROM set_left AS l ${clause}`,
    'set_left', JSON.stringify(setLeft), JSON.stringify(['a', 'b']),
    'set_right', JSON.stringify(setRight), JSON.stringify(['c', 'd']),
    `fixture.join_${kind}`);
  assert.notEqual(query, '', kind);
  await writeFile(join(root, `join-${kind}.json`), query);
}
const pipeJoinQuery = queryFrontend.compileTwoValuesSetQueryJson(
  'FROM set_left AS l |> INNER JOIN set_right AS r ON l.a = r.c '
    + '|> SELECT l.a AS a, r.d AS d',
  'set_left', JSON.stringify(setLeft), JSON.stringify(['a', 'b']),
  'set_right', JSON.stringify(setRight), JSON.stringify(['c', 'd']),
  'fixture.join_inner');
assert.deepEqual(JSON.parse(pipeJoinQuery),
  JSON.parse(await readFile(join(root, 'join-inner.json'), 'utf8')));
await writeFile(join(root, 'join-pipe.json'), pipeJoinQuery);
await writeFile(join(root, 'join-cases.json'), JSON.stringify(joinCases));
const capturedQuery = queryFrontend.compileCapturedQueryJson(
  'SELECT id FROM records WHERE id > 1', 'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.captured_query');
assert.notEqual(capturedQuery, '');
await writeFile(join(root, 'captured-query.json'), capturedQuery);
const capturedCteQuery = queryFrontend.compileCapturedQueryJson(
  'WITH chosen AS (SELECT id, amount FROM records WHERE id > 1) '
    + 'SELECT id FROM chosen',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.captured_cte');
assert.notEqual(capturedCteQuery, '');
await writeFile(join(root, 'captured-cte-query.json'), capturedCteQuery);
const reusedCteQuery = queryFrontend.compileCapturedQueryJson(
  'WITH chosen AS (SELECT id, amount FROM records WHERE id > 1) '
    + 'SELECT l.id AS left_id, r.id AS right_id '
    + 'FROM chosen AS l JOIN chosen AS r ON l.id = r.id',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.reused_cte');
assert.notEqual(reusedCteQuery, '');
await writeFile(join(root, 'reused-cte-query.json'), reusedCteQuery);
const usingCteQuery = queryFrontend.compileCapturedQueryJson(
  'WITH chosen AS (SELECT id, amount FROM records WHERE id > 1) '
    + 'SELECT id FROM chosen AS l JOIN chosen AS r USING (id)',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.using_cte');
assert.notEqual(usingCteQuery, '');
await writeFile(join(root, 'using-cte-query.json'), usingCteQuery);
const chainedCteQuery = queryFrontend.compileCapturedQueryJson(
  'WITH first AS (SELECT id, amount FROM records WHERE id > 1), '
    + 'second AS (SELECT id FROM first WHERE amount >= 20) '
    + 'SELECT id FROM second',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.chained_cte');
assert.notEqual(chainedCteQuery, '');
await writeFile(join(root, 'chained-cte-query.json'), chainedCteQuery);
const distinctQuery = queryFrontend.compileCapturedQueryJson(
  'SELECT DISTINCT id FROM records WHERE id > 1 ORDER BY id',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.distinct_query');
assert.notEqual(distinctQuery, '');
await writeFile(join(root, 'distinct-query.json'), distinctQuery);
const distinctExpressionQuery = queryFrontend.compileCapturedQueryJson(
  'SELECT DISTINCT id + 1 AS next FROM records WHERE id > 0 '
    + 'ORDER BY id + 1',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.distinct_expression');
assert.notEqual(distinctExpressionQuery, '');
await writeFile(join(root, 'distinct-expression-query.json'),
  distinctExpressionQuery);
const groupedQuery = queryFrontend.compileCapturedQueryJson(
  'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id HAVING n > 1 ORDER BY id',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.grouped_query');
assert.notEqual(groupedQuery, '');
const pipeGroupedQuery = queryFrontend.compileCapturedQueryJson(
  'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n GROUP BY id |> WHERE n > 1 |> SELECT id, n |> ORDER BY id',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.grouped_query');
assert.deepEqual(JSON.parse(pipeGroupedQuery), JSON.parse(groupedQuery));
await writeFile(join(root, 'grouped-query.json'), groupedQuery);
const analyticQuery = queryFrontend.compileCapturedQueryJson(
  'SELECT id, RANK() OVER (ORDER BY id) AS ranking FROM records WHERE id > 0',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.analytic_query');
assert.notEqual(analyticQuery, '');
await writeFile(join(root, 'analytic-query.json'), analyticQuery);
const analyticCases = [
  ['row-number',
    'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS pos '
      + 'FROM records WHERE id < 3',
    [{id: 1, pos: 1}, {id: 2, pos: 2}]],
  ['lag',
    'SELECT id, LAG(id) OVER (ORDER BY id) AS previous '
      + 'FROM records WHERE id < 3',
    [{id: 1, previous: null}, {id: 2, previous: 1}]],
  ['frame-count',
    'SELECT id, COUNT(id) OVER (ORDER BY id '
      + 'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running '
      + 'FROM records WHERE id < 3',
    [{id: 1, running: 1}, {id: 2, running: 2}]],
  ['over-alias-scope',
    'SELECT amount AS id, ROW_NUMBER() OVER (ORDER BY id) AS pos '
      + 'FROM records WHERE id < 3 ORDER BY id DESC',
    [{id: 20, pos: 2}, {id: null, pos: 1}]],
];
for (const [name, sql] of analyticCases) {
  const query = queryFrontend.compileCapturedQueryJson(sql,
    'records', 'remote',
    JSON.stringify({connector: 'crm/main', resource: 'r'}),
    JSON.stringify(['id', 'amount']), `fixture.analytic_${name}`);
  assert.notEqual(query, '', name);
  await writeFile(join(root, `analytic-${name}.json`), query);
}
const pipeRowNumber = queryFrontend.compileCapturedQueryJson(
  'FROM records |> WHERE id < 3 '
    + '|> SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS pos',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.analytic_row-number');
assert.deepEqual(JSON.parse(pipeRowNumber),
  JSON.parse(await readFile(join(root, 'analytic-row-number.json'), 'utf8')));
await writeFile(join(root, 'analytic-pipe-row-number.json'), pipeRowNumber);
analyticCases.push(['pipe-row-number', '', [{id: 1, pos: 1}, {id: 2, pos: 2}]]);
await writeFile(join(root, 'analytic-cases.json'),
  JSON.stringify(analyticCases.map(([name, , expected]) => [name, expected])));
const extendedQuery = queryFrontend.compileCapturedQueryJson(
  'FROM records |> WHERE id > 0 |> EXTEND amount + 1 AS adjusted |> SELECT id, adjusted',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.extended_query');
assert.notEqual(extendedQuery, '');
await writeFile(join(root, 'extended-query.json'), extendedQuery);
const pipeSetQuery = queryFrontend.compileCapturedQueryJson(
  'FROM records AS before |> WHERE id > 0 '
    + '|> SET id = amount, amount = id '
    + '|> SELECT before.id AS old_id, before.amount AS old_amount, id, amount',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.pipe_set_query');
assert.notEqual(pipeSetQuery, '');
await writeFile(join(root, 'pipe-set-query.json'), pipeSetQuery);
const pipeSetGroupedQuery = queryFrontend.compileCapturedQueryJson(
  'FROM records |> WHERE amount > 0 |> SET id = amount '
    + '|> AGGREGATE COUNT(*) AS n GROUP BY id |> SELECT id, n '
    + '|> ORDER BY id',
  'records', 'remote',
  JSON.stringify({connector: 'crm/main', resource: 'r'}),
  JSON.stringify(['id', 'amount']), 'fixture.pipe_set_grouped_query');
assert.notEqual(pipeSetGroupedQuery, '');
await writeFile(join(root, 'pipe-set-grouped-query.json'),
  pipeSetGroupedQuery);
const sourceCatalog = await readFile(join(repository,
  'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
const catalog = sourceCatalog.slice(sourceCatalog.indexOf(
  'fn query_amount_nullable_catalog')).match(
  /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/u);
assert.ok(catalog);
const sourceEnvironment = JSON.parse(JSON.parse(catalog[1]));
const sourceSelector = {source_ref: 'connector://crm/main/r#v',
  source_contract_cid:
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
  source_view_contract_cid:
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
  read_mode: 'snapshot'};
sourceEnvironment.schema_snapshots = [{...sourceSelector,
  output_carrier: 'relation',
  carrier_schema_contract_cid:
    'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4',
  source_data_policy_cid:
    'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf',
  data_classification: 'unknown'}];
sourceEnvironment.connector_capabilities = [{...sourceSelector,
  capability_contract_cids: [
    'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8'],
}];
Object.assign(sourceEnvironment.host_policy_profile.capacity, {
  max_analytic_frame_memberships: 10000,
  max_analytic_input_wire_bytes: 10000,
  max_analytic_output_wire_bytes: 10000,
  max_analytic_partition_wire_bytes: 10000,
});
delete sourceEnvironment.evidence_bundle_cid;
sourceEnvironment.evidence_bundle_cid = machineCid(sourceEnvironment);
const databasePath = join(root, 'records.duckdb');
const {DuckDBInstance} = createRequire(join(root, 'node_modules', '@actql',
  'local-node', 'package.json'))('@duckdb/node-api');
const sourceDatabase = await DuckDBInstance.create(databasePath);
const sourceConnection = await sourceDatabase.connect();
try {
  await sourceConnection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  await sourceConnection.run('INSERT INTO records VALUES (3,30),(1,NULL),'
    + '(2,20),(3,30)');
} finally {
  sourceConnection.closeSync();
  sourceDatabase.closeSync();
}
const sourceProfilePath = join(root, 'source-profile.json');
await writeFile(sourceProfilePath, JSON.stringify({
  version: 'actql-installed-duckdb-source/0.1',
  database: databasePath, schema: 'main', table: 'records',
  sourceRef: sourceSelector.source_ref,
  checkEnvironmentWire: canonicalText(sourceEnvironment),
  accountConfigurationWire: JSON.stringify({
    version: 'actql-execution-account-config/0.1',
    account_id: 'packed-source-account', entries: [{
      entry_id: 'packed-source-allow', outcome: 'allow',
      principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}, exclusions: [],
    }],
  }),
}));
environment.ACTQL_LOCAL_SOURCE_PROFILE = sourceProfilePath;

await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {connect, ClientError} from '@actql/node';
import {connectInProcess} from '@actql/sdk/host-port';

const calls = [];
const originalFetch = globalThis.fetch;
globalThis.fetch = async (_url, init) => {
  const body = JSON.parse(init.body);
  calls.push(body.connection);
  return Response.json({version: 'actql-client-host/0.1',
    mode: body.connection.mode, owner: body.connection.owner,
    durability: 'volatile', scopeRef: 'scope-a', capabilities: [],
    limits: {maxReadWireBytes: 1024, maxRowWireBytes: 512,
      maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
      maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 1024}});
};
const connected = [
  {mode: 'remote', endpoint: 'https://remote.example/', token: 'token'},
  {mode: 'local', owner: 'local', endpoint: 'https://local.example/',
    token: 'token'},
  {mode: 'hybrid', owner: 'cloud', endpoint: 'https://cloud.example/',
    token: 'token', runners: ['runner-a'], movementPolicyRef: 'movement-a'},
  {mode: 'hybrid', owner: 'local', endpoint: 'https://local.example/',
    token: 'token', cloudConnectionRef: 'registered-cloud-a',
    movementPolicyRef: 'movement-a'},
];
for (const selected of connected) {
  const client = await connect(selected);
  assert.equal(client.profile.mode, selected.mode);
  assert.equal(client.profile.owner, selected.owner ?? 'remote');
  client.close();
}
const document = readFileSync('values.json', 'utf8');
const valuesQueryDocument = readFileSync('query-values.json', 'utf8');
const computedValuesQueryDocument = readFileSync('query-computed-values.json',
  'utf8');
async function checkOrderScopes(client, suffix) {
  for (const [name, expected] of [
    ['alias-order', [{y: 1}, {y: 2}]],
    ['hidden-order', [{x: 2}, {x: 1}]],
  ]) {
    const execution = await client.aql(readFileSync(name + '.json', 'utf8'),
      {format: 'json', requestId: 'packed-' + name + '-' + suffix});
    const status = await execution.wait();
    assert.equal(status.status, 'succeeded', JSON.stringify(status));
    assert.deepEqual(await execution.result('answer').all(), expected);
  }
}
async function checkConcat(client, suffix) {
  await assert.rejects(client.aql(readFileSync('concat-query.json', 'utf8'),
    {format: 'json', requestId: 'packed-concat-' + suffix}),
  {code: 'RunHostCompilationRejected'});
}
async function checkValuesCte(client, suffix) {
  const execution = await client.aql(
    readFileSync('values-cte-query.json', 'utf8'),
    {format: 'json', requestId: 'packed-values-cte-' + suffix});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.deepEqual(await execution.result('answer').all(),
    [{x: 2}, {x: 1}]);
}
const setQueryDocument = readFileSync('set-query.json', 'utf8');
const pipeUnionQueryDocument = readFileSync('pipe-union-query.json', 'utf8');
const expectedUnionRows = [{a: 1, b: 'x'}, {a: 1, b: 'x'},
  {a: 2, b: 'y'}, {a: null, b: 'n'}, {a: 1, b: 'x'},
  {a: 3, b: 'z'}, {a: null, b: 'n'}];
const setExpectations = [
  ['union-distinct', [{a: 1, b: 'x'}, {a: 2, b: 'y'},
    {a: null, b: 'n'}, {a: 3, b: 'z'}]],
  ['intersect-distinct', [{a: 1, b: 'x'}, {a: null, b: 'n'}]],
  ['except-distinct', [{a: 2, b: 'y'}]],
];
const sortedRows = rows => rows.map(row => JSON.stringify(row)).sort();
async function checkJoinCases(client, suffix) {
  const cases = JSON.parse(readFileSync('join-cases.json', 'utf8'));
  for (const [kind, expected] of cases) {
    const execution = await client.aql(
      readFileSync('join-' + kind + '.json', 'utf8'),
      {format: 'json', requestId: 'packed-join-' + kind + '-' + suffix});
    const status = await execution.wait();
    assert.equal(status.status, 'succeeded', JSON.stringify(status));
    assert.deepEqual(sortedRows(await execution.result('answer').all()),
      sortedRows(expected));
  }
  const execution = await client.aql(readFileSync('join-pipe.json', 'utf8'),
    {format: 'json', requestId: 'packed-join-pipe-' + suffix});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.deepEqual(sortedRows(await execution.result('answer').all()),
    sortedRows(cases[0][1]));
}
async function checkSetQueries(client, suffix) {
  for (const [name, expected] of setExpectations) {
    const execution = await client.aql(readFileSync(name + '.json', 'utf8'),
      {format: 'json', requestId: 'packed-' + name + '-' + suffix});
    const status = await execution.wait();
    assert.equal(status.status, 'succeeded', JSON.stringify(status));
    assert.deepEqual(sortedRows(await execution.result('answer').all()),
      sortedRows(expected));
  }
}
const acquiredDocument = readFileSync('source-program.json', 'utf8');
const capturedQueryDocument = readFileSync('captured-query.json', 'utf8');
const capturedCteDocument = readFileSync('captured-cte-query.json', 'utf8');
const reusedCteDocument = readFileSync('reused-cte-query.json', 'utf8');
const usingCteDocument = readFileSync('using-cte-query.json', 'utf8');
const chainedCteDocument = readFileSync('chained-cte-query.json', 'utf8');
async function checkCapturedCte(client, suffix) {
  const execution = await client.aql(capturedCteDocument,
    {format: 'json', requestId: 'packed-captured-cte-' + suffix});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.deepEqual(await execution.result('answer').all(),
    [{id: 3}, {id: 2}, {id: 3}]);
  const reused = await client.aql(reusedCteDocument,
    {format: 'json', requestId: 'packed-reused-cte-' + suffix});
  assert.equal((await reused.wait()).status, 'succeeded');
  assert.deepEqual(sortedRows(await reused.result('answer').all()),
    sortedRows([
      {left_id: 3, right_id: 3}, {left_id: 3, right_id: 3},
      {left_id: 2, right_id: 2}, {left_id: 3, right_id: 3},
      {left_id: 3, right_id: 3},
    ]));
  const using = await client.aql(usingCteDocument,
    {format: 'json', requestId: 'packed-using-cte-' + suffix});
  assert.equal((await using.wait()).status, 'succeeded');
  assert.deepEqual(sortedRows(await using.result('answer').all()),
    sortedRows([{id: 3}, {id: 3}, {id: 2}, {id: 3}, {id: 3}]));
  const chained = await client.aql(chainedCteDocument,
    {format: 'json', requestId: 'packed-chained-cte-' + suffix});
  assert.equal((await chained.wait()).status, 'succeeded');
  assert.deepEqual(await chained.result('answer').all(),
    [{id: 3}, {id: 2}, {id: 3}]);
}
const distinctQueryDocument = readFileSync('distinct-query.json', 'utf8');
const distinctExpressionDocument = readFileSync(
  'distinct-expression-query.json', 'utf8');
async function checkDistinctExpression(client, suffix) {
  const execution = await client.aql(distinctExpressionDocument,
    {format: 'json', requestId: 'packed-distinct-expression-' + suffix});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.deepEqual(await execution.result('answer').all(),
    [{next: 2}, {next: 3}, {next: 4}]);
}
const groupedQueryDocument = readFileSync('grouped-query.json', 'utf8');
const analyticQueryDocument = readFileSync('analytic-query.json', 'utf8');
async function checkAnalyticCases(client, suffix) {
  const cases = JSON.parse(readFileSync('analytic-cases.json', 'utf8'));
  for (const [name, expected] of cases) {
    const execution = await client.aql(
      readFileSync('analytic-' + name + '.json', 'utf8'),
      {format: 'json', requestId: 'packed-analytic-' + name + '-' + suffix});
    const status = await execution.wait();
    assert.equal(status.status, 'succeeded', JSON.stringify(status));
    assert.deepEqual(await execution.result('answer').all(), expected);
  }
}
const extendedQueryDocument = readFileSync('extended-query.json', 'utf8');
const pipeSetQueryDocument = readFileSync('pipe-set-query.json', 'utf8');
const pipeSetGroupedDocument = readFileSync('pipe-set-grouped-query.json',
  'utf8');
async function runApplication(options, requestId) {
  const client = await connect(options);
  const execution = await client.aql(document, {format: 'json', requestId});
  const settled = await execution.wait();
  assert.equal(settled.status, 'succeeded');
  const rows = await execution.result('answer').all();
  return {client, execution, rows};
}
async function runAcquiredApplication(options, requestId) {
  const client = await connect(options);
  const execution = await client.aql(acquiredDocument, {format: 'json',
    requestId, parameters: {minimum: 1}});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.equal((await execution.status()).control.physical_stop, 'confirmed');
  const resultB = execution.result('b');
  const b = await resultB.all();
  const c = await execution.result('c').all();
  assert.deepEqual(b.map(row => row.id).sort(), [2, 3, 3]);
  assert.deepEqual(c.map(row => row.id).sort(), [3, 3]);
  await assert.rejects(resultB.all({maxRows: 1}),
    {code: 'ResultRetainedLimit'});
  const reader = resultB.rows();
  assert.deepEqual(await Array.fromAsync(reader), b);
  assert.equal(reader.state(), 'complete');
  assert.equal((await resultB.deliveryAttempt(reader.attemptId)).kind,
    'found');
  assert.deepEqual((await client.lookupRequest(requestId)).ref,
    execution.ref);
  assert.deepEqual((await client.aql(acquiredDocument, {format: 'json',
    requestId, parameters: {minimum: 1}})).ref, execution.ref);
  await assert.rejects(client.aql(acquiredDocument, {format: 'json',
    requestId, parameters: {minimum: 2}}),
  {code: 'ClientRequestIntentConflict'});
  return {client, execution, b, c};
}
const {client: installedLocal, execution, rows} = await runApplication(
  {mode: 'local', owner: 'local', durability: 'durable'},
  'packed-standard-values');
assert.equal(execution.profile.durability, 'durable');
assert.equal((await execution.status()).status, 'succeeded');
assert.deepEqual(rows, [{id: 1}, {id: 2}]);
assert.equal((await execution.cancel()).kind, 'already_terminal');
assert.equal((await execution.status()).control.physical_stop, 'confirmed');
await assert.rejects(execution.result('answer').all({maxRows: 1}),
  {code: 'ResultRetainedLimit'});
const reader = execution.result('answer').rows();
assert.deepEqual(await Array.fromAsync(reader), [{id: 1}, {id: 2}]);
assert.equal(reader.state(), 'complete');
assert.equal((await execution.result('answer')
  .deliveryAttempt(reader.attemptId)).kind, 'found');
assert.deepEqual((await installedLocal.lookupRequest(
  'packed-standard-values')).ref, execution.ref);
assert.deepEqual((await installedLocal.attach(execution.ref)).ref,
  execution.ref);
const valuesQueryLocal = await installedLocal.aql(valuesQueryDocument,
  {format: 'json', requestId: 'packed-query-values-local'});
assert.equal((await valuesQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await valuesQueryLocal.result('answer').all(),
  [{id: 1}, {id: 2}]);
const computedValuesQueryLocal = await installedLocal.aql(
  computedValuesQueryDocument,
  {format: 'json', requestId: 'packed-query-computed-values-local'});
assert.equal((await computedValuesQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await computedValuesQueryLocal.result('answer').all(),
  [{id: 2}]);
await checkOrderScopes(installedLocal, 'local');
await checkValuesCte(installedLocal, 'local');
await checkConcat(installedLocal, 'local');
const setQueryLocal = await installedLocal.aql(setQueryDocument,
  {format: 'json', requestId: 'packed-set-query-local'});
const setQueryLocalStatus = await setQueryLocal.wait();
assert.equal(setQueryLocalStatus.status, 'succeeded',
  JSON.stringify(setQueryLocalStatus));
assert.deepEqual(await setQueryLocal.result('answer').all(), expectedUnionRows);
await checkSetQueries(installedLocal, 'local');
await checkJoinCases(installedLocal, 'local');
const pipeUnionLocal = await installedLocal.aql(pipeUnionQueryDocument,
  {format: 'json', requestId: 'packed-pipe-union-local'});
assert.equal((await pipeUnionLocal.wait()).status, 'succeeded');
assert.deepEqual(await pipeUnionLocal.result('answer').all(), expectedUnionRows);
const acquiredLocal = await runAcquiredApplication(
  {mode: 'local', owner: 'local', durability: 'durable'},
  'packed-acquired-local');
const capturedQueryLocal = await acquiredLocal.client.aql(capturedQueryDocument,
  {format: 'json', requestId: 'packed-captured-query-local'});
assert.equal((await capturedQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await capturedQueryLocal.result('answer').all(),
  [{id: 3}, {id: 2}, {id: 3}]);
await checkAnalyticCases(acquiredLocal.client, 'local');
await checkCapturedCte(acquiredLocal.client, 'local');
const distinctQueryLocal = await acquiredLocal.client.aql(distinctQueryDocument,
  {format: 'json', requestId: 'packed-distinct-query-local'});
assert.equal((await distinctQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await distinctQueryLocal.result('answer').all(),
  [{id: 2}, {id: 3}]);
await checkDistinctExpression(acquiredLocal.client, 'local');
const groupedQueryLocal = await acquiredLocal.client.aql(groupedQueryDocument,
  {format: 'json', requestId: 'packed-grouped-query-local'});
assert.equal((await groupedQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await groupedQueryLocal.result('answer').all(),
  [{id: 3, n: 2}]);
const analyticQueryLocal = await acquiredLocal.client.aql(analyticQueryDocument,
  {format: 'json', requestId: 'packed-analytic-query-local'});
assert.equal((await analyticQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await analyticQueryLocal.result('answer').all(),
  [{id: 3, ranking: 3}, {id: 1, ranking: 1},
    {id: 2, ranking: 2}, {id: 3, ranking: 3}]);
const extendedQueryLocal = await acquiredLocal.client.aql(extendedQueryDocument,
  {format: 'json', requestId: 'packed-extended-query-local'});
assert.equal((await extendedQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await extendedQueryLocal.result('answer').all(),
  [{id: 3, adjusted: 31}, {id: 1, adjusted: null},
    {id: 2, adjusted: 21}, {id: 3, adjusted: 31}]);
const pipeSetQueryLocal = await acquiredLocal.client.aql(pipeSetQueryDocument,
  {format: 'json', requestId: 'packed-pipe-set-query-local'});
assert.equal((await pipeSetQueryLocal.wait()).status, 'succeeded');
assert.deepEqual(await pipeSetQueryLocal.result('answer').all(),
  [{old_id: 3, old_amount: 30, id: 30, amount: 3},
    {old_id: 1, old_amount: null, id: null, amount: 1},
    {old_id: 2, old_amount: 20, id: 20, amount: 2},
    {old_id: 3, old_amount: 30, id: 30, amount: 3}]);
const pipeSetGroupedLocal = await acquiredLocal.client.aql(
  pipeSetGroupedDocument,
  {format: 'json', requestId: 'packed-pipe-set-grouped-local'});
assert.equal((await pipeSetGroupedLocal.wait()).status, 'succeeded');
assert.deepEqual(await pipeSetGroupedLocal.result('answer').all(),
  [{id: 20, n: 1}, {id: 30, n: 2}]);
assert.deepEqual((await acquiredLocal.client.attach(
  acquiredLocal.execution.ref)).ref, acquiredLocal.execution.ref);
const acquiredStarted = await acquiredLocal.client.start(
  JSON.parse(acquiredDocument), {requestId: 'packed-acquired-start',
    parameters: {minimum: 1}});
assert.equal((await acquiredStarted.wait()).status, 'succeeded');
assert.deepEqual(await acquiredStarted.result('b').all(), acquiredLocal.b);
assert.equal((await acquiredStarted.cancel()).kind, 'already_terminal');
writeFileSync('acquired-local-ref.json',
  JSON.stringify(acquiredLocal.execution.ref));
acquiredLocal.client.close();
writeFileSync('run-ref.json', JSON.stringify(execution.ref));
const nullable = JSON.parse(document);
nullable.id = 'client-nullable-values';
nullable.stages[0].steps[0].values.schema.id.nullable = true;
nullable.stages[0].steps[0].values.rows = [{id: null}, {id: 3}];
const nullableRun = await installedLocal.aql(JSON.stringify(nullable),
  {format: 'json', requestId: 'packed-nullable-values'});
assert.equal((await nullableRun.wait()).status, 'succeeded');
assert.deepEqual(await nullableRun.result('answer').all(),
  [{id: null}, {id: 3}]);
const empty = JSON.parse(document);
empty.id = 'client-empty-values';
empty.stages[0].steps[0].values.rows = [];
const emptyRun = await installedLocal.aql(JSON.stringify(empty),
  {format: 'json', requestId: 'packed-empty-values'});
assert.equal((await emptyRun.wait()).status, 'succeeded');
assert.deepEqual(await emptyRun.result('answer').all(), []);
const computed = JSON.parse(document);
computed.id = 'client-values-filtered';
computed.stages[0].steps.push({filter: 'id > 1', as: 'filtered'});
computed.stages[0].results.rows.from = 'filtered';
const computedDocument = JSON.stringify(computed);
const computedLocal = await installedLocal.aql(computedDocument,
  {format: 'json', requestId: 'packed-computed-local'});
const computedLocalState = await computedLocal.wait();
assert.equal(computedLocalState.status, 'succeeded',
  JSON.stringify(computedLocalState));
assert.deepEqual(await computedLocal.result('answer').all(), [{id: 2}]);
assert.deepEqual((await installedLocal.aql(document, {format: 'json',
  requestId: 'packed-standard-values'})).ref, execution.ref);
const conflictingProgram = JSON.parse(document);
assert.equal(conflictingProgram.stages[0].steps[0].values.rows[1].id, 2);
conflictingProgram.stages[0].steps[0].values.rows[1].id = 3;
await assert.rejects(installedLocal.aql(JSON.stringify(conflictingProgram),
  {format: 'json', requestId: 'packed-standard-values'}),
  {code: 'ClientRequestIntentConflict'});
installedLocal.close();
assert.equal(calls.length, connected.length);
globalThis.fetch = originalFetch;
const remoteOptions = {mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT, token: 'packed-test-token',
  durability: 'durable'};
const timingClient = await connect(remoteOptions);
let acceptanceTimer;
const timingRun = await Promise.race([
  timingClient.aql(document, {format: 'json',
    requestId: 'packed-acceptance-before-dispatch'}),
  new Promise((_, reject) => {
    acceptanceTimer = setTimeout(() => reject(
      new Error('SubmitWaitedForPhysicalDispatch')), 5000);
  }),
]).finally(() => clearTimeout(acceptanceTimer));
const pendingState = await timingRun.status();
assert.equal(pendingState.status, 'running');
assert.equal(pendingState.result_availability.answer.reason,
  'not_published');
const abortedWait = new AbortController();
const waitAttempt = timingRun.wait({signal: abortedWait.signal});
abortedWait.abort();
await assert.rejects(waitAttempt);
assert.equal((await timingRun.status()).status, 'running');
const cancelledRun = await timingClient.aql(document, {format: 'json',
  requestId: 'packed-cancel-before-dispatch'});
assert.equal((await cancelledRun.cancel()).kind, 'accepted');
const cancelledState = await cancelledRun.status();
assert.equal(cancelledState.status, 'cancelled');
assert.equal(cancelledState.control.cancellation_requested, true);
assert.equal(cancelledState.control.physical_stop, 'confirmed');
assert.equal((await cancelledRun.cancel()).kind, 'already_requested');
assert.equal((await cancelledRun.wait()).status, 'cancelled');
const cancelledAcquired = await timingClient.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-cancel-before-dispatch',
    parameters: {minimum: 1}});
assert.equal((await cancelledAcquired.cancel()).kind, 'accepted');
assert.equal((await cancelledAcquired.wait()).status, 'cancelled');
assert.equal((await cancelledAcquired.status()).control.physical_stop,
  'confirmed');
const release = await originalFetch(new URL('/__test/release-dispatch',
  remoteOptions.endpoint), {method: 'POST'});
assert.equal(release.status, 200);
assert.equal((await timingRun.wait()).status, 'succeeded');
assert.deepEqual(await timingRun.result('answer').all(), rows);
const cancelledResend = await timingClient.aql(document, {format: 'json',
  requestId: 'packed-cancel-before-dispatch'});
assert.deepEqual(cancelledResend.ref, cancelledRun.ref);
assert.equal((await cancelledResend.wait()).status, 'cancelled');
await assert.rejects(cancelledResend.result('answer').all());
const cancelledAcquiredResend = await timingClient.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-cancel-before-dispatch',
    parameters: {minimum: 1}});
assert.deepEqual(cancelledAcquiredResend.ref, cancelledAcquired.ref);
assert.equal((await cancelledAcquiredResend.wait()).status, 'cancelled');
await assert.rejects(cancelledAcquiredResend.result('b').all());
timingClient.close();
const {client: installedRemote, execution: remoteExecution,
  rows: remoteRows} = await runApplication(remoteOptions,
  'packed-remote-values');
assert.deepEqual(remoteRows, rows);
const valuesQueryRemote = await installedRemote.aql(valuesQueryDocument,
  {format: 'json', requestId: 'packed-query-values-remote'});
assert.equal((await valuesQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await valuesQueryRemote.result('answer').all(),
  [{id: 1}, {id: 2}]);
const computedValuesQueryRemote = await installedRemote.aql(
  computedValuesQueryDocument,
  {format: 'json', requestId: 'packed-query-computed-values-remote'});
assert.equal((await computedValuesQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await computedValuesQueryRemote.result('answer').all(),
  [{id: 2}]);
await checkOrderScopes(installedRemote, 'remote');
await checkValuesCte(installedRemote, 'remote');
const setQueryRemote = await installedRemote.aql(setQueryDocument,
  {format: 'json', requestId: 'packed-set-query-remote'});
assert.equal((await setQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await setQueryRemote.result('answer').all(), expectedUnionRows);
await checkSetQueries(installedRemote, 'remote');
await checkJoinCases(installedRemote, 'remote');
const pipeUnionRemote = await installedRemote.aql(pipeUnionQueryDocument,
  {format: 'json', requestId: 'packed-pipe-union-remote'});
assert.equal((await pipeUnionRemote.wait()).status, 'succeeded');
assert.deepEqual(await pipeUnionRemote.result('answer').all(), expectedUnionRows);
const acquiredRemote = await runAcquiredApplication(remoteOptions,
  'packed-acquired-remote');
const capturedQueryRemote = await acquiredRemote.client.aql(
  capturedQueryDocument,
  {format: 'json', requestId: 'packed-captured-query-remote'});
assert.equal((await capturedQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await capturedQueryRemote.result('answer').all(),
  [{id: 3}, {id: 2}, {id: 3}]);
await checkAnalyticCases(acquiredRemote.client, 'remote');
await checkCapturedCte(acquiredRemote.client, 'remote');
const distinctQueryRemote = await acquiredRemote.client.aql(
  distinctQueryDocument,
  {format: 'json', requestId: 'packed-distinct-query-remote'});
assert.equal((await distinctQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await distinctQueryRemote.result('answer').all(),
  [{id: 2}, {id: 3}]);
await checkDistinctExpression(acquiredRemote.client, 'remote');
const groupedQueryRemote = await acquiredRemote.client.aql(
  groupedQueryDocument,
  {format: 'json', requestId: 'packed-grouped-query-remote'});
assert.equal((await groupedQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await groupedQueryRemote.result('answer').all(),
  [{id: 3, n: 2}]);
const analyticQueryRemote = await acquiredRemote.client.aql(
  analyticQueryDocument,
  {format: 'json', requestId: 'packed-analytic-query-remote'});
assert.equal((await analyticQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await analyticQueryRemote.result('answer').all(),
  [{id: 3, ranking: 3}, {id: 1, ranking: 1},
    {id: 2, ranking: 2}, {id: 3, ranking: 3}]);
const extendedQueryRemote = await acquiredRemote.client.aql(
  extendedQueryDocument,
  {format: 'json', requestId: 'packed-extended-query-remote'});
assert.equal((await extendedQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await extendedQueryRemote.result('answer').all(),
  [{id: 3, adjusted: 31}, {id: 1, adjusted: null},
    {id: 2, adjusted: 21}, {id: 3, adjusted: 31}]);
const pipeSetQueryRemote = await acquiredRemote.client.aql(
  pipeSetQueryDocument,
  {format: 'json', requestId: 'packed-pipe-set-query-remote'});
assert.equal((await pipeSetQueryRemote.wait()).status, 'succeeded');
assert.deepEqual(await pipeSetQueryRemote.result('answer').all(),
  [{old_id: 3, old_amount: 30, id: 30, amount: 3},
    {old_id: 1, old_amount: null, id: null, amount: 1},
    {old_id: 2, old_amount: 20, id: 20, amount: 2},
    {old_id: 3, old_amount: 30, id: 30, amount: 3}]);
const pipeSetGroupedRemote = await acquiredRemote.client.aql(
  pipeSetGroupedDocument,
  {format: 'json', requestId: 'packed-pipe-set-grouped-remote'});
assert.equal((await pipeSetGroupedRemote.wait()).status, 'succeeded');
assert.deepEqual(await pipeSetGroupedRemote.result('answer').all(),
  [{id: 20, n: 1}, {id: 30, n: 2}]);
assert.deepEqual(acquiredRemote.b, acquiredLocal.b);
assert.deepEqual(acquiredRemote.c, acquiredLocal.c);
assert.deepEqual((await acquiredRemote.client.attach(
  acquiredRemote.execution.ref)).ref, acquiredRemote.execution.ref);
const acquiredRemoteStarted = await acquiredRemote.client.start(
  JSON.parse(acquiredDocument), {requestId: 'packed-acquired-remote-start',
    parameters: {minimum: 1}});
assert.equal((await acquiredRemoteStarted.wait()).status, 'succeeded');
assert.deepEqual(await acquiredRemoteStarted.result('b').all(),
  acquiredLocal.b);
acquiredRemote.client.close();
const orderedAcquired = JSON.parse(acquiredDocument);
orderedAcquired.id = 'physical-example-ordered';
orderedAcquired.stages[2].steps.push({from: 'out',
  sort: [{id: 'desc'}], as: 'sorted'});
orderedAcquired.stages[2].results.r.from = 'sorted';
const orderedDocument = JSON.stringify(orderedAcquired);
const variantLocal = await connect({mode: 'local', owner: 'local',
  durability: 'durable'});
const orderedLocal = await variantLocal.aql(orderedDocument,
  {format: 'json', requestId: 'packed-acquired-ordered-local',
    parameters: {minimum: 1}});
assert.equal((await orderedLocal.wait()).status, 'succeeded');
assert.deepEqual((await orderedLocal.result('b').all()).map(row => row.id),
  [3, 3, 2]);
const orderedRemote = await installedRemote.aql(orderedDocument,
  {format: 'json', requestId: 'packed-acquired-ordered-remote',
    parameters: {minimum: 1}});
assert.equal((await orderedRemote.wait()).status, 'succeeded');
assert.deepEqual((await orderedRemote.result('b').all()).map(row => row.id),
  [3, 3, 2]);
const emptyLocal = await variantLocal.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-empty-local',
    parameters: {minimum: 9}});
assert.equal((await emptyLocal.wait()).status, 'succeeded');
assert.deepEqual(await emptyLocal.result('b').all(), []);
const emptyRemote = await installedRemote.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-empty-remote',
    parameters: {minimum: 9}});
assert.equal((await emptyRemote.wait()).status, 'succeeded');
assert.deepEqual(await emptyRemote.result('b').all(), []);
const nullableAcquired = JSON.parse(acquiredDocument);
nullableAcquired.id = 'physical-example-nullable';
nullableAcquired.stages[0].steps[1].select = ['id', 'amount'];
nullableAcquired.stages[0].results.r.fields = ['id', 'amount'];
nullableAcquired.stages[2].steps[1].select = ['amount', 'id'];
nullableAcquired.stages[2].results.r.fields = ['amount', 'id'];
const nullableDocument = JSON.stringify(nullableAcquired);
const expectedNullable = [{id: 1, amount: null}, {id: 2, amount: 20},
  {id: 3, amount: 30}, {id: 3, amount: 30}];
const nullableLocal = await variantLocal.aql(nullableDocument,
  {format: 'json', requestId: 'packed-acquired-nullable-local',
    parameters: {minimum: 0}});
assert.equal((await nullableLocal.wait()).status, 'succeeded');
assert.deepEqual((await nullableLocal.result('b').all())
  .sort((left, right) => left.id - right.id), expectedNullable);
const nullableRemote = await installedRemote.aql(nullableDocument,
  {format: 'json', requestId: 'packed-acquired-nullable-remote',
    parameters: {minimum: 0}});
assert.equal((await nullableRemote.wait()).status, 'succeeded');
assert.deepEqual((await nullableRemote.result('b').all())
  .sort((left, right) => left.id - right.id), expectedNullable);
variantLocal.close();
const computedRemote = await installedRemote.aql(computedDocument,
  {format: 'json', requestId: 'packed-computed-remote'});
assert.equal((await computedRemote.wait()).status, 'succeeded');
assert.deepEqual(await computedRemote.result('answer').all(), [{id: 2}]);
assert.equal((await remoteExecution.status()).status, 'succeeded');
assert.deepEqual((await installedRemote.attach(remoteExecution.ref)).ref,
  remoteExecution.ref);
assert.deepEqual((await installedRemote.lookupRequest(
  'packed-remote-values')).ref, remoteExecution.ref);
await assert.rejects(remoteExecution.result('answer').all({maxRows: 1}),
  {code: 'ResultRetainedLimit'});
let remoteReplyLost = false;
globalThis.fetch = async (url, options) => {
  const reply = await originalFetch(url, options);
  if (!remoteReplyLost && new URL(url).pathname.endsWith('/submit')) {
    remoteReplyLost = true;
    await reply.arrayBuffer();
    throw new Error('RemoteAcceptanceReplyLost');
  }
  return reply;
};
try {
  await assert.rejects(installedRemote.aql(document, {format: 'json',
    requestId: 'packed-remote-lost-ack'}), error =>
    error.code === 'SubmissionUnknown' &&
    error.requestId === 'packed-remote-lost-ack');
} finally { globalThis.fetch = originalFetch; }
assert.equal(remoteReplyLost, true);
const recoveredRemote = await installedRemote.lookupRequest(
  'packed-remote-lost-ack');
assert.equal(recoveredRemote.kind, 'found');
const resumedRemote = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-lost-ack'});
assert.deepEqual(resumedRemote.ref, recoveredRemote.ref);
assert.equal((await resumedRemote.wait()).status, 'succeeded');
assert.deepEqual(await resumedRemote.result('answer').all(), rows);
let acquiredReplyLost = false;
globalThis.fetch = async (url, options) => {
  const reply = await originalFetch(url, options);
  if (!acquiredReplyLost && new URL(url).pathname.endsWith('/submit')) {
    acquiredReplyLost = true;
    await reply.arrayBuffer();
    throw new Error('AcquiredAcceptanceReplyLost');
  }
  return reply;
};
try {
  await assert.rejects(installedRemote.aql(acquiredDocument,
    {format: 'json', requestId: 'packed-acquired-lost-ack',
      parameters: {minimum: 1}}), error =>
    error.code === 'SubmissionUnknown' &&
    error.requestId === 'packed-acquired-lost-ack');
} finally { globalThis.fetch = originalFetch; }
assert.equal(acquiredReplyLost, true);
const foundAcquired = await installedRemote.lookupRequest(
  'packed-acquired-lost-ack');
assert.equal(foundAcquired.kind, 'found');
const recoveredAcquired = await installedRemote.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-lost-ack',
    parameters: {minimum: 1}});
assert.deepEqual(recoveredAcquired.ref, foundAcquired.ref);
assert.equal((await recoveredAcquired.wait()).status, 'succeeded');
assert.deepEqual(await recoveredAcquired.result('b').all(),
  acquiredLocal.b);
const failDispatch = await originalFetch(new URL(
  '/__test/fail-next-dispatch', remoteOptions.endpoint), {method: 'POST'});
assert.equal(failDispatch.status, 200);
const failedRemote = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-dispatch-failure'});
const failedState = await failedRemote.wait();
assert.equal(failedState.status, 'failed');
assert.equal(failedState.terminal_error.code,
  'ACTQL_E_UNPUBLISHED_RUN');
const repeatedFailure = await installedRemote.aql(document, {format: 'json',
  requestId: 'packed-remote-dispatch-failure'});
assert.deepEqual(repeatedFailure.ref, failedRemote.ref);
assert.equal((await repeatedFailure.status()).status, 'failed');
installedRemote.close();
const local = await connectInProcess({mode: 'local', owner: 'local'}, {
  async perform(operation) {
    assert.equal(operation, 'connect');
    return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'embedded-scope',
      capabilities: [], limits: {maxReadWireBytes: 1024,
        maxRowWireBytes: 512, maxRowRetainedValueBytes: 512,
        maxRetainedValueBytes: 1024, maxRows: 10, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 1024}};
  },
});
assert.equal(local.profile.owner, 'local');
assert.equal(calls.length, connected.length);
local.close();
`);
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], root);
const remoteModule = pathToFileURL(join(root, 'node_modules', '@actql',
  'local-node', 'adapters', 'host-node', 'embedded-local.mjs')).href;
const {openInstalledRemoteHttpHost} = await import(remoteModule);
let releaseDispatch;
const heldDispatch = new Promise(resolve => { releaseDispatch = resolve; });
let failNextDispatch = false;
const remoteHost = await openInstalledRemoteHttpHost({
  directory: join(root, 'remote-state'),
  sourceProfilePath,
  authenticate: header => header === 'Bearer packed-test-token'
    ? userInfo().username : undefined,
  beforeDispatch: async () => {
    if (failNextDispatch) {
      failNextDispatch = false;
      throw new Error('TestPhysicalDispatchFailure');
    }
    await heldDispatch;
  },
});
const remoteServer = createServer({
  key: await readFile(join(root, 'remote.key')),
  cert: await readFile(join(root, 'remote.crt')),
}, (request, response) => {
  if (request.method === 'POST' &&
      request.url === '/__test/release-dispatch') {
    releaseDispatch();
    response.writeHead(200);
    response.end();
    return;
  }
  if (request.method === 'POST' &&
      request.url === '/__test/fail-next-dispatch') {
    failNextDispatch = true;
    response.writeHead(200);
    response.end();
    return;
  }
  return remoteHost.handler(request, response);
});
await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
try {
  const endpoint = `https://127.0.0.1:${remoteServer.address().port}/`;
  await runAsync(process.execPath, ['smoke.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: endpoint,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally {
  releaseDispatch();
  await new Promise(resolve => remoteServer.close(resolve));
}
const acquiredRecoveryRequest = {requestId: 'packed-acquired-remote',
  principalId: userInfo().username,
  connection: {mode: 'remote', owner: 'remote'}};
assert.equal((await remoteHost.inspectAcquisition(
  acquiredRecoveryRequest)).state, 'completed_retained');
assert.equal((await remoteHost.inspectAcquisition({
  ...acquiredRecoveryRequest, requestId: 'never-submitted'})).state,
  'not_started');
await assert.rejects(remoteHost.inspectAcquisition({
  ...acquiredRecoveryRequest, principalId: 'other-principal'}),
{message: 'AcquisitionInspectionDenied'});
await remoteHost.close();
await writeFile(join(root, 'restart-remote-host.mjs'), `
import {readFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';
const host = await openInstalledRemoteHttpHost({
  directory: join(process.cwd(), 'restart-remote-state'),
  authenticate: header => header === 'Bearer packed-test-token'
    ? userInfo().username : undefined,
  beforeDispatch: process.env.ACTQL_HOLD_DISPATCH === '1'
    ? async () => new Promise(() => {}) : undefined,
});
const recovery = await host.inspectAcquisition({
  requestId: 'packed-acquired-restart-before-start',
  principalId: userInfo().username,
  connection: {mode: 'remote', owner: 'remote'},
});
console.log('RECOVERY:' + recovery.state);
const server = createServer({key: readFileSync('remote.key'),
  cert: readFileSync('remote.crt')}, host.handler);
server.listen(0, '127.0.0.1', () => {
  console.log('READY:' + server.address().port);
});
`);
await writeFile(join(root, 'reserve-remote.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {connect} from '@actql/node';
const client = await connect({mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT,
  token: 'packed-test-token', durability: 'durable'});
const document = readFileSync('values.json', 'utf8');
const acquiredDocument = readFileSync('source-program.json', 'utf8');
const execution = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
for (let attempt = 0; attempt < 100; attempt++) {
  if ((await execution.status()).status === 'running') break;
  await new Promise(resolve => setTimeout(resolve, 20));
}
assert.equal((await execution.status()).status, 'running');
writeFileSync('restart-remote-ref.json', JSON.stringify(execution.ref));
const acquired = await client.aql(acquiredDocument, {format: 'json',
  requestId: 'packed-acquired-restart-before-start',
  parameters: {minimum: 1}});
assert.equal((await acquired.status()).status, 'running');
writeFileSync('restart-acquired-ref.json', JSON.stringify(acquired.ref));
const cancelled = await client.aql(document, {format: 'json',
  requestId: 'packed-cancel-before-restart'});
assert.equal((await cancelled.cancel()).kind, 'accepted');
writeFileSync('cancelled-remote-ref.json', JSON.stringify(cancelled.ref));
client.close();
`);
await writeFile(join(root, 'resume-remote.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/node';
const client = await connect({mode: 'remote',
  endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT,
  token: 'packed-test-token', durability: 'durable'});
const document = readFileSync('values.json', 'utf8');
const acquiredDocument = readFileSync('source-program.json', 'utf8');
const ref = JSON.parse(readFileSync('restart-remote-ref.json', 'utf8'));
const attached = await client.attach(ref);
assert.equal((await attached.status()).status, 'running');
const cancelledRef = JSON.parse(readFileSync('cancelled-remote-ref.json', 'utf8'));
const cancelled = await client.attach(cancelledRef);
assert.equal((await cancelled.status()).status, 'cancelled');
const cancelledResend = await client.aql(document, {format: 'json',
  requestId: 'packed-cancel-before-restart'});
assert.deepEqual(cancelledResend.ref, cancelledRef);
assert.equal((await cancelledResend.wait()).status, 'cancelled');
assert.equal((await cancelledResend.status()).control.physical_stop, 'confirmed');
await assert.rejects(cancelledResend.result('answer').all());
const execution = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
assert.deepEqual(execution.ref, ref);
assert.equal((await execution.wait()).status, 'succeeded');
assert.deepEqual(await execution.result('answer').all(),
  [{id: 1}, {id: 2}]);
const repeated = await client.aql(document, {format: 'json',
  requestId: 'packed-restart-before-physical-start'});
assert.deepEqual(repeated.ref, ref);
assert.equal((await repeated.status()).status, 'succeeded');
assert.deepEqual((await client.lookupRequest(
  'packed-restart-before-physical-start')).ref, ref);
const acquiredRef = JSON.parse(readFileSync('restart-acquired-ref.json',
  'utf8'));
const acquiredAttached = await client.attach(acquiredRef);
assert.equal((await acquiredAttached.status()).status, 'running');
const acquiredResumed = await client.aql(acquiredDocument,
  {format: 'json', requestId: 'packed-acquired-restart-before-start',
    parameters: {minimum: 1}});
assert.deepEqual(acquiredResumed.ref, acquiredRef);
assert.equal((await acquiredResumed.wait()).status, 'succeeded');
assert.deepEqual((await acquiredResumed.result('b').all())
  .map(row => row.id).sort(), [2, 3, 3]);
assert.deepEqual((await client.lookupRequest(
  'packed-acquired-restart-before-start')).ref, acquiredRef);
client.close();
`);
async function startRestartHost(hold) {
  const child = spawn(process.execPath, ['restart-remote-host.mjs'], {
    cwd: root, env: {...environment, ACTQL_HOLD_DISPATCH: hold ? '1' : '0'},
  });
  let output = '';
  return new Promise((resolve, reject) => {
    child.stdout.setEncoding('utf8').on('data', chunk => {
      output += chunk;
      const ready = output.match(/READY:(\d+)/u);
      if (ready) resolve({child, port: Number(ready[1]),
        recovery: output.match(/RECOVERY:([a-z_]+)/u)?.[1]});
    });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('exit', code => reject(new Error(
      `Packed restart Host exited before ready (${code}): ${output}`)));
  });
}
async function stopRestartHost(host) {
  if (host.child.exitCode !== null) return;
  const stopped = once(host.child, 'exit');
  host.child.kill('SIGTERM');
  await stopped;
}
const heldHost = await startRestartHost(true);
assert.equal(heldHost.recovery, 'not_started');
try {
  await runAsync(process.execPath, ['reserve-remote.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${heldHost.port}/`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally { await stopRestartHost(heldHost); }
const resumedHost = await startRestartHost(false);
try {
  await runAsync(process.execPath, ['resume-remote.mjs'], root, {
    ACTQL_TEST_REMOTE_ENDPOINT: `https://127.0.0.1:${resumedHost.port}/`,
    NODE_EXTRA_CA_CERTS: join(root, 'remote.crt'),
  });
} finally { await stopRestartHost(resumedHost); }
const recoveredHost = await startRestartHost(false);
try {
  assert.equal(recoveredHost.recovery, 'completed_retained');
} finally { await stopRestartHost(recoveredHost); }
await writeFile(join(root, 'restart.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/node';
globalThis.fetch = () => { throw new Error('NetworkOnLocalRestart'); };
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable'});
const ref = JSON.parse(readFileSync('run-ref.json', 'utf8'));
const attached = await client.attach(ref);
assert.equal((await attached.status()).status, 'succeeded');
assert.deepEqual(await attached.result('answer').all(),
  [{id: 1}, {id: 2}]);
assert.deepEqual((await client.lookupRequest('packed-standard-values')).ref,
  ref);
const repeated = await client.aql(readFileSync('values.json', 'utf8'),
  {format: 'json', requestId: 'packed-standard-values'});
assert.deepEqual(repeated.ref, ref);
const acquiredRef = JSON.parse(readFileSync('acquired-local-ref.json',
  'utf8'));
const acquiredAttached = await client.attach(acquiredRef);
assert.equal((await acquiredAttached.status()).status, 'succeeded');
assert.deepEqual((await acquiredAttached.result('b').all())
  .map(row => row.id).sort(), [2, 3, 3]);
assert.deepEqual((await client.lookupRequest('packed-acquired-local')).ref,
  acquiredRef);
client.close();
`);
run(process.execPath, ['restart.mjs'], root);
const browser = join(root, 'actql-sdk-browser.mjs');
const browserMetadata = join(root, 'actql-sdk-browser-meta.json');
run(join(repository, 'node_modules/.bin/esbuild'), [
  join(root, 'node_modules/@actql/sdk/index.mjs'),
  '--bundle', '--platform=browser', '--format=esm', '--target=es2022',
  `--outfile=${browser}`, `--metafile=${browserMetadata}`,
], root);
const metadata = JSON.parse(await readFile(browserMetadata, 'utf8'));
assert.deepEqual(Object.keys(metadata.inputs).sort(), [
  'node_modules/@actql/client-wire/client-host.generated.js',
  'node_modules/@actql/client-wire/index.mjs',
  'node_modules/@actql/client-wire/publication.generated.js',
  'node_modules/@actql/sdk/checkpoints.mjs',
  'node_modules/@actql/sdk/index.mjs',
]);
assert(Object.values(metadata.outputs).every(output =>
  output.imports.length === 0));
await writeFile(join(root, 'browser-smoke.mjs'), `
import assert from 'node:assert/strict';
globalThis.fetch = async () => { throw new Error('NetworkOnImport'); };
const {connect} = await import('./actql-sdk-browser.mjs');
let calls = 0;
globalThis.fetch = async () => {
  calls++;
  return Response.json({version: 'actql-client-host/0.1', mode: 'remote',
    owner: 'remote', durability: 'volatile', scopeRef: 'browser-scope',
    capabilities: [], limits: {maxReadWireBytes: 1024,
      maxRowWireBytes: 512, maxRowRetainedValueBytes: 512,
      maxRetainedValueBytes: 1024, maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 1024}});
};
const client = await connect({mode: 'remote',
  endpoint: 'https://remote.example/', token: 'fixture-token'});
assert.equal(client.profile.mode, 'remote');
assert.equal(calls, 1);
client.close();
`);
run(process.execPath, ['browser-smoke.mjs'], root);
console.log('packed Node and browser Client smoke passed');
