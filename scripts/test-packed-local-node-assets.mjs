import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'packed-local-assets-'));
const environment = {...process.env,
  npm_config_cache: join(build, 'npm-cache')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

const artifacts = [];
for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node']) {
  const packed = run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
  const metadata = JSON.parse(packed);
  artifacts.push(join(root, metadata[0]?.filename ??
    metadata[`@actql/${name}`]?.filename));
}
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...artifacts], root);
const moduleRoot = join(root, 'node_modules/@actql/local-node');
for (const name of [
  'connectors_builtin_node/connectors_builtin_node.js',
  'connectors/duckdb/host_node/host_node.js',
  'retained_host_bridge/retained_host_bridge.js',
  'process_host_bridge/process_host_bridge.js',
]) {
  assert((await readFile(join(moduleRoot, '_build/js/release/build',
    name))).byteLength > 0);
}
for (const name of ['values.json', 'values.environment.json']) {
  await writeFile(join(root, name), await readFile(join(repository,
    'packages/sdk/fixtures', name)));
}
for (const name of ['program.json', 'parameters.json']) {
  await writeFile(join(root, name), await readFile(join(repository,
    'adapters/connectors/duckdb/node/examples', name)));
}
const catalogSource = await readFile(join(repository,
  'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
const catalog = catalogSource.slice(catalogSource.indexOf(
  'fn query_amount_nullable_catalog')).match(
  /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/u);
assert(catalog);
await writeFile(join(root, 'source.environment.json'),
  JSON.parse(catalog[1]));
await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
globalThis.fetch = () => { throw new Error('NetworkOnPackedLocalRun'); };
const effectHost = await import('@actql/local-node/effect-run');
assert.equal(typeof effectHost.installNodeClientEffectRun, 'function');
assert.equal(typeof effectHost.openClientRequestJournal, 'function');
const owner = await import('@actql/local-node/runtime');
assert.equal(typeof owner.clientProgramPrepareEffectFree, 'function');
assert.equal(typeof owner.clientProgramOpenSourceFreeLocalHost, 'function');
const host = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/entry.mjs');
assert.equal(typeof host.runPublishedCapturedStrategy, 'function');
const ingress = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/in-process-client.mjs');
assert.equal(typeof ingress.createNodeInProcessClientHost, 'function');
const prefix = './node_modules/@actql/local-node/';
const wire = readFileSync('values.environment.json', 'utf8').trimEnd();
const environment = owner.clientProgramCheckEnvironment(wire,
  JSON.parse(wire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert(environment);
const prepared = owner.clientProgramPrepareEffectFree(
  readFileSync('values.json', 'utf8'), 'json', environment);
assert(prepared);
const registry = readFileSync(prefix +
  'spec/dependencies/aoa-pipeline-registry.json', 'utf8');
const contract = JSON.parse(readFileSync(prefix +
  'spec/contracts/actql-aoa.json', 'utf8'));
const values = JSON.stringify(contract.execution_contracts['REL.values']);
const setup = owner.clientProgramOpenSourceFreeLocalHost(
  prepared, registry, values, 1n, 0n, 0n, 0n);
assert(setup);
const executed = await host.runCapturedStrategy(setup);
try {
  assert.equal(executed.status, 'host-tasks-completed');
  assert.deepEqual(executed.resultInventory.map(value => value.name),
    ['answer']);
  assert.equal(executed.completed[0].outputRows, 2);
} finally { await executed.close(); }
const {DuckDBInstance} = createRequire(new URL(
  './node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
const database = await DuckDBInstance.create('./source.duckdb');
const connection = await database.connect();
try {
  await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),'
    + '(2,20),(3,30)');
} finally {
  connection.closeSync();
  database.closeSync();
}
const sourceWire = readFileSync('source.environment.json', 'utf8');
const sourceEnvironment = owner.clientProgramCheckEnvironment(sourceWire,
  JSON.parse(sourceWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert(sourceEnvironment);
const preparedSource = owner.clientProgramPreparationReady(
  owner.clientProgramPrepareEffectFreeWithParameters(
    readFileSync('program.json', 'utf8'), 'json', sourceEnvironment,
    readFileSync('parameters.json', 'utf8')));
assert(preparedSource);
const physical = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/captured-duckdb-source.mjs');
const account = await import('./node_modules/@actql/local-node/adapters/' +
  'host-node/local-account-config.mjs');
const databasePath = new URL('./source.duckdb', import.meta.url).pathname;
const authorization = await account.createLocalAuthorizationGate({
  accountConfiguration: account.sourceReadAccountConfiguration({
    connection: 'local-database', resource: databasePath,
  }),
  principal: 'local-user',
});
const captured = await physical.openCapturedDuckDBSource({
  moon: owner, preparedProgram: preparedSource, registry, values,
  fragment: JSON.stringify(contract.execution_contracts[
    'ACTQL.expression_fragment/0.1']),
  ordered: JSON.stringify(contract.execution_contracts[
    'REL.derive.ordered']),
  database: databasePath,
  sourceAccess: {authorization, connection: 'local-database',
    resource: databasePath},
  schema: 'main', table: 'records',
  transportLimits: {maxRows: 100, maxCells: 1000,
    maxTransportBytes: 100000, maxSqlBytes: 10000,
    maxParameters: 10, maxColumns: 10,
    memoryBytes: 128 * 1024 * 1024, threads: 1},
});
try {
  assert.equal(captured.checkedSource.sourceRef,
    'connector://crm/main/r#v');
  assert.equal(captured.checkedSource.sourceContractCid,
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3');
  assert.match(captured.checkedSource.requirementCid,
    /^sha256:[0-9a-f]{64}$/u);
  assert.equal(owner.clientProgramCapturedSourceRowCount(
    captured.identity), 3);
  const sourceExecution = await host.runCapturedStrategy(captured.setup);
  try {
    assert.equal(sourceExecution.status, 'host-tasks-completed');
    assert.deepEqual(sourceExecution.resultInventory.map(value =>
      value.name), ['b', 'c']);
    assert.deepEqual(sourceExecution.completed.map(value => value.task),
      [1, 2, 3]);
  } finally { await sourceExecution.close(); }
} finally { captured.close(); }
`);
run(process.execPath, ['smoke.mjs'], root);
console.log('packed Local Host source-free and acquired computation passed');
