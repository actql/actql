// A fresh external consumer process, with neither source-tree resolution nor
// a substitute Host. Expected rows and columns are independent literals.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, stat, writeFile} from 'node:fs/promises';
import {createRequire, registerHooks} from 'node:module';
import {resolve} from 'node:path';
import {canonicalJson} from '@actql/sdk/host-port';

const require = createRequire(import.meta.url);
const local = createRequire(require.resolve('@actql/local-node'));
for (const resolver of [require, local]) {
  for (const name of ['@duckdb/node-api', '@duckdb/node-bindings']) {
    assert.throws(() => resolver.resolve(name), {code: 'MODULE_NOT_FOUND'});
  }
}
const physicalLoads = [];
const hook = registerHooks({resolve(specifier, context, next) {
  if (specifier.includes('@duckdb/') ||
      /duckdb\/node\/(?:host|session|physical-values|physical-appender|bounded-vector)\.mjs$/u.test(specifier)) {
    physicalLoads.push(specifier);
  }
  return next(specifier, context);
}});
let networkCalls = 0;
globalThis.fetch = () => { networkCalls++; throw new Error('UnexpectedNetworkOnLocalRun'); };
const {connect, open} = await import('@actql/node');
const mode = process.argv[2];
const options = {mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('state')}};
const client = await connect(options);
let sibling;
try {
  sibling = await connect(options);
  const submissionRef = mode === 'restart'
    ? JSON.parse(await readFile('submission.json', 'utf8'))
    : client.newSubmission({nonce: 'without-duckdb'});
  if (mode !== 'restart') await writeFile('submission.json', JSON.stringify(submissionRef));
  const execution = mode === 'restart'
    ? await client.attach(JSON.parse(await readFile('run.json', 'utf8')))
    : await client.startSource(await readFile('values.json', 'utf8'),
      {format: 'json', submissionRef});
  assert.equal((await execution.wait()).status, 'succeeded');
  const result = execution.result('answer');
  assert.deepEqual((await result.describe()).columns,
    [{name: 'id', contract: {type: 'number', nullable: false}}]);
  const reader = result.rows();
  assert.deepEqual(await Array.fromAsync(reader), [{id: 1}, {id: 2}]);
  assert.equal(reader.state(), 'complete');
  const lookup = await client.lookupSubmission(submissionRef);
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual(lookup.submissionRef, submissionRef);
  assert.deepEqual(lookup.admission.ref, execution.ref);
  if (mode !== 'restart') await writeFile('run.json', JSON.stringify(execution.ref));
  const ownerPath = resolve('state/publication/owner/owner.json');
  const originalOwner = await readFile(ownerPath, 'utf8');
  const paused = result.batches({maxBatchRows: 1});
  const iterator = paused[Symbol.asyncIterator]();
  assert.deepEqual((await iterator.next()).value, [{id: 1}]);
  await client.close();
  assert.deepEqual(await iterator.next(), {done: true, value: undefined});
  assert.equal(paused.rowsYielded(), 1);
  assert.equal(await readFile(ownerPath, 'utf8'), originalOwner);
  assert.deepEqual(await (await sibling.attach(execution.ref)).result('answer').all(),
    [{id: 1}, {id: 2}]);
  await sibling.close();
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
  const reopened = await connect(options);
  try {
    assert.notEqual(await readFile(ownerPath, 'utf8'), originalOwner);
    const found = await reopened.lookupSubmission(submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.submissionRef, submissionRef);
    assert.deepEqual(found.admission.ref, execution.ref);
    assert.deepEqual(await (await reopened.attach(found.admission.ref)).result('answer').all(),
      [{id: 1}, {id: 2}]);
    const repeated = await reopened.startSource(await readFile('values.json', 'utf8'),
      {format: 'json', submissionRef});
    assert.deepEqual(repeated.ref, execution.ref);
  } finally { await reopened.close(); }
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
} finally { await client.close(); await sibling?.close(); }
// Three independently installed Sources remain inert for a source-free Run.
// Keep their durable state separate from the original no-Source lifecycle.
const sourceNames = ['unused-first', 'unused-second', 'unused-third'];
const sourceProfilePaths = await Promise.all(sourceNames
  .map(async name => {
    const schemaWire = '{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}}';
    const catalogCid = 'sha256:' + createHash('sha256')
      .update(canonicalJson({fixture: name})).digest('hex');
    const path = resolve(`${name}.json`);
    await writeFile(path, JSON.stringify({
      version: 'actql-installed-local-table-source/0.1', connectorId: name, connection: name,
      python: resolve('uninstalled-python'),
      catalog: {database: resolve(`${name}.db`), warehouse: resolve(name),
        catalogCid, limits: {bytes: 1048576, files: 16, operations: 8}},
      accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
        account_id: name, entries: [{entry_id: 'read', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['read']}, exclusions: []}]}),
      targets: [{resource: 'rows', schemaWire, selector: {
        catalog_identity_cid: catalogCid, namespace: ['unused'], table_name: 'rows',
        table_uuid: '00000000-0000-0000-0000-000000000000',
        schema_cid: 'sha256:' + createHash('sha256').update(schemaWire).digest('hex')}}],
      limits: {maxPages: 1, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16},
    }));
    return path;
  }));
let sourceSecretCalls = 0;
const installation = {sourceProfilePaths, resolveSourceSecret() {
  sourceSecretCalls++; throw new Error('UnexpectedSourceSecretOnValuesRun');
}};
const directory = resolve('inventory-state');
const inventory = await open({stateDir: directory, durability: 'durable', installation});
let inventoryRef, inventorySubmissionRef;
try {
  assert.equal(inventory.info.stateDir, directory);
  inventorySubmissionRef = mode === 'restart'
    ? JSON.parse(await readFile('inventory-submission.json', 'utf8'))
    : inventory.newSubmission({nonce: 'unused-source-inventory'});
  if (mode !== 'restart') {
    await writeFile('inventory-submission.json', JSON.stringify(inventorySubmissionRef));
  }
  const execution = mode === 'restart'
    ? await inventory.attach(JSON.parse(await readFile('inventory-run.json', 'utf8')))
    : await inventory.startSource(await readFile('values.json', 'utf8'),
      {format: 'json', submissionRef: inventorySubmissionRef});
  assert.equal((await execution.wait()).status, 'succeeded');
  assert.deepEqual((await execution.result('answer').describe()).columns,
    [{name: 'id', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(await execution.result('answer').all(), [{id: 1}, {id: 2}]);
  inventoryRef = execution.ref;
  const lookup = await inventory.lookupSubmission(inventorySubmissionRef);
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual(lookup.submissionRef, inventorySubmissionRef);
  assert.deepEqual(lookup.admission.ref, inventoryRef);
  if (mode !== 'restart') {
    await writeFile('inventory-run.json', JSON.stringify(inventoryRef));
  }
} finally { await inventory.close(); }
const reopenedInventory = await connect({mode: 'local', owner: 'local', durability: 'durable',
  installation: {...installation, directory}});
try {
  const found = await reopenedInventory.lookupSubmission(inventorySubmissionRef);
  assert.equal(found.kind, 'ready');
  assert.deepEqual(found.submissionRef, inventorySubmissionRef);
  assert.deepEqual(found.admission.ref, inventoryRef);
  const attached = await reopenedInventory.attach(found.admission.ref);
  assert.equal((await attached.status()).status, 'succeeded');
  assert.deepEqual(await attached.result('answer').all(), [{id: 1}, {id: 2}]);
} finally { await reopenedInventory.close(); }
assert.equal(sourceSecretCalls, 0, 'unused Sources must not resolve secrets');
for (const path of [resolve('uninstalled-python'), ...sourceNames.flatMap(name =>
  [resolve(`${name}.db`), resolve(name)])]) {
  await assert.rejects(stat(path), {code: 'ENOENT'});
}
assert.equal(networkCalls, 0, 'Local Values and retained Results must not use the network');
assert.deepEqual(physicalLoads, [], 'unselected DuckDB must not be resolved or loaded');
hook.deregister();

// Selecting the installed Source must fail clearly; a missing database file
// must never be opened and another execution method must not be selected.
// Reach that dependency boundary with the authored Source and the SAME
// explicitly selected Host policy, rather than an invalid Environment placeholder.
const sourceEnvironment = JSON.parse(await readFile('source-environment.json', 'utf8'));
const baseEnvironment = JSON.parse(await readFile('base-environment.json', 'utf8'));
sourceEnvironment.host_policy_profile = baseEnvironment.host_policy_profile;
delete sourceEnvironment.evidence_bundle_cid;
sourceEnvironment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
  .update(canonicalJson(sourceEnvironment)).digest('hex');
await writeFile('source-profile.json', JSON.stringify({
  version: 'actql-installed-duckdb-source/0.1',
  acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
  database: resolve('not-opened.duckdb'), schema: 'main', table: 'records',
  sourceRef: 'connector://crm/main/r#v', checkEnvironmentWire: canonicalJson(sourceEnvironment),
  accountConfigurationWire: JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'missing-duckdb',
    entries: [{entry_id: 'allow', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}}],
  }),
}));
let missingDependencyFailure;
await assert.rejects(connect({mode: 'local', owner: 'local', installation: {
  directory: resolve('missing-source-state'), sourceProfilePath: resolve('source-profile.json'),
  hostCapacityPolicy: sourceEnvironment.host_policy_profile.capacity,
}}), error => {
  assert.equal(error.code, 'InstalledHostInitializationFailed');
  assert.equal(error.primaryFailure, error.cause);
  assert.equal(error.cause.code, 'DuckDBDependencyUnavailable');
  assert.match(error.cause.message, /install @duckdb\/node-api@1\.5\.5-r\.4/u);
  assert.equal(error.cause.cause.code, 'ERR_MODULE_NOT_FOUND');
  missingDependencyFailure = error;
  return true;
});
// The failed bound initializer may still own its original partial Source.
// Retry only that public continuation; fulfillment alone is not a close ACK.
const missingDependencyCleanup = missingDependencyFailure.cleanupHandle;
if (missingDependencyCleanup.status().pending) await missingDependencyCleanup.retry();
assert.equal(missingDependencyCleanup.status().pending, false);
const contribution = new URL('./adapters/connectors/duckdb/node/strategy-bundle.mjs',
  import.meta.resolve('@actql/local-node'));
await assert.rejects(import(contribution.href), {code: 'DuckDBDependencyUnavailable'});
await assert.rejects(stat(resolve('not-opened.duckdb')), {code: 'ENOENT'});
assert.equal(networkCalls, 0, 'missing DuckDB must not use the network');
console.log('Packed dependency-free Local: Values, Result, close, attach, inert Source inventory and explicit refusal passed');
