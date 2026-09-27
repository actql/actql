import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {withFixtureConnector} from '../adapters/host-common/connector-manifest.fixture.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'packed-local-assets-'));
const environment = {...process.env,
  npm_config_cache: join(build, 'npm-cache')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: command === 'npm' && args[0] === 'pack' ? 180000 : 30000});
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
  'checkpoint_runtime_node/checkpoint_runtime_node.js',
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
delete sourceEnvironment.evidence_bundle_cid;
sourceEnvironment.evidence_bundle_cid = machineCid(sourceEnvironment);
await writeFile(join(root, 'source.environment.json'),
  canonicalText(sourceEnvironment));
await writeFile(join(root, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
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
  delete copy[name];
  return 'sha256:' + createHash('sha256')
    .update(JSON.stringify(copy)).digest('hex');
};
const fixtureCid = digit => 'sha256:' + digit.repeat(64);
const targetSchema = {additional_properties: false, fields: {
  Id: {nullable: false, type: 'string'},
  Name: {nullable: true, type: 'number'},
}, nullable: false, type: 'object'};
const mapping = {
  connector_manifest_cid: fixtureCid('a'), conversions: [],
  mapping_contract_cid: '', mapping_ref: 'mapping:crm.account.v1',
  minimum_approval: 'none',
  permission_rules: [{effect_kind: 'create', permissions: ['scope:create'],
    selector_class: 'none', write_fields: ['Name']}],
  primary_identity: 'Id', required_fields: [], required_permissions: [],
  resource_identity_cid: fixtureCid('b'),
  row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
  schema: 'actql.mapping_contract/0.1',
  target_ref: 'connector://crm/account', target_schema: targetSchema,
  target_schema_identity: 'sha256:' + createHash('sha256')
    .update(JSON.stringify(targetSchema)).digest('hex'),
  version: 'salesforce-v1', writable_fields: ['Name'],
};
const effectEnvironmentBody = JSON.parse(wire);
mapping.connector_manifest_cid = withFixtureConnector(effectEnvironmentBody,
  mapping.target_ref);
mapping.mapping_contract_cid = machineCid(Object.fromEntries(
  Object.entries(mapping).filter(([key]) => key !== 'mapping_contract_cid')));
effectEnvironmentBody.mapping_contracts = [mapping];
delete effectEnvironmentBody.evidence_bundle_cid;
effectEnvironmentBody.evidence_bundle_cid = machineCid(effectEnvironmentBody);
const effectEnvironmentWire = canonicalText(effectEnvironmentBody);
const effectEnvironment = owner.clientProgramCheckEnvironment(
  effectEnvironmentWire, effectEnvironmentBody.evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert(effectEnvironment);
const effectDocument = JSON.parse(readFileSync('values.json', 'utf8'));
effectDocument.stages[0].effects = {save: {create: {
  target: mapping.target_ref, mapping: mapping.mapping_ref,
  from: {result: 'rows'},
}}};
const effectOutcome = owner.clientProgramPrepareEffectComputationWithParameters(
  JSON.stringify(effectDocument), 'json', effectEnvironment, undefined, []);
const effectPrepared = owner.clientProgramEffectPreparationReady(effectOutcome);
assert(effectPrepared, owner.clientProgramEffectPreparationIssueCode(effectOutcome));
let effectStarts = 0;
let clock = '2026-09-26T00:00:01.000Z';
let effectExpiry = '2026-09-26T00:00:03.000Z';
const openEffect = journal => effectHost.installNodeClientEffectRun({
  moon: owner, journal, now: () => clock,
  authorizeRequest: async () => ({executionContextCid: fixtureCid('a'),
    hostPolicyCid: fixtureCid('b'),
    createdAt: '2026-09-26T00:00:00.000Z', expiresAt: effectExpiry}),
  authorizeRunStart: async () => true,
  execute: async ({owner: effectRun}) => {
    effectStarts++;
    const effectSetup = owner.clientProgramOpenSourceFreeLocalEffectHost(
      effectRun, registry, values, 1n, 0n, 0n, 0n);
    assert(effectSetup);
    const capture = await host.runCapturedEffectComputation(effectSetup);
    try { assert.equal(capture.status, 'host-tasks-completed'); }
    finally { await capture.close(); }
    return 'captured';
  },
});
const effectRequest = requestId => ({prepared: effectPrepared,
  authorityScopeCid: fixtureCid('a'), requestId,
  tenantId: 'packed-local', principalId: 'packed-user',
  connection: {owner: 'local'},
  lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
let effectJournal = effectHost.openClientRequestJournal('./effect-journal');
let effectRuns = openEffect(effectJournal);
const effectAccepted = await effectRuns.accept(effectRequest('packed-effect'));
assert.equal(effectStarts, 0);
assert.equal((await effectRuns.start(effectAccepted)).kind, 'started');
assert.equal(effectStarts, 1);
effectJournal.close();
effectJournal = effectHost.openClientRequestJournal('./effect-journal');
effectRuns = openEffect(effectJournal);
const effectResent = await effectRuns.accept(effectRequest('packed-effect'));
assert.deepEqual(effectResent.ref, effectAccepted.ref);
assert.equal((await effectRuns.start(effectResent)).kind, 'reconcile');
assert.equal(effectStarts, 1);
const expiring = await effectRuns.accept(effectRequest('packed-expiring'));
clock = effectExpiry;
await assert.rejects(effectRuns.start(expiring),
  {code: 'ClientEffectRunExpired'});
assert.equal(effectStarts, 1);
await assert.rejects(effectRuns.accept(effectRequest('packed-expired-new')),
  {code: 'ClientEffectRunExpired'});
effectJournal.close();
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
    resource: databasePath, sourceRef: 'connector://crm/main/r#v'},
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
