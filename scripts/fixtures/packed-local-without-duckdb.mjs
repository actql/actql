// A fresh external consumer process, with neither source-tree resolution nor
// a substitute Host. Expected rows and columns are independent literals.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire, registerHooks} from 'node:module';
import {resolve} from 'node:path';

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
globalThis.fetch = () => { throw new Error('UnexpectedNetworkOnLocalRun'); };
const {connect} = await import('@actql/node');
const options = {mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('state')}};
const client = await connect(options);
let sibling;
try {
  sibling = await connect(options);
  const mode = process.argv[2];
  const execution = mode === 'restart'
    ? await client.attach(JSON.parse(await readFile('run.json', 'utf8')))
    : await client.startSource(await readFile('values.json', 'utf8'),
      {format: 'json', requestId: 'without-duckdb'});
  assert.equal((await execution.wait()).status, 'succeeded');
  const result = execution.result('answer');
  assert.deepEqual((await result.describe()).columns,
    [{name: 'id', contract: {type: 'number', nullable: false}}]);
  const reader = result.rows();
  assert.deepEqual(await Array.fromAsync(reader), [{id: 1}, {id: 2}]);
  assert.equal(reader.state(), 'complete');
  const lookup = await client.lookupRequest('without-duckdb');
  assert.deepEqual(lookup.ref, execution.ref);
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
    const found = await reopened.lookupRequest('without-duckdb');
    assert.deepEqual(found.ref, execution.ref);
    assert.deepEqual(await (await reopened.attach(found.ref)).result('answer').all(),
      [{id: 1}, {id: 2}]);
    const repeated = await reopened.startSource(await readFile('values.json', 'utf8'),
      {format: 'json', requestId: 'without-duckdb'});
    assert.deepEqual(repeated.ref, execution.ref);
  } finally { await reopened.close(); }
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
} finally { await client.close(); await sibling?.close(); }
assert.deepEqual(physicalLoads, [], 'unselected DuckDB must not be resolved or loaded');
hook.deregister();

// Selecting the installed Source must fail clearly; a missing database file
// must never be opened and another execution method must not be selected.
await writeFile('source-profile.json', JSON.stringify({
  version: 'actql-installed-duckdb-source/0.1',
  acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
  database: resolve('not-opened.duckdb'), schema: 'main', table: 'records',
  sourceRef: 'connector://crm/main/r#v', checkEnvironmentWire: '{}',
  accountConfigurationWire: JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'missing-duckdb',
    entries: [{entry_id: 'allow', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}}],
  }),
}));
await assert.rejects(connect({mode: 'local', owner: 'local', installation: {
  directory: resolve('missing-source-state'), sourceProfilePath: resolve('source-profile.json'),
}}), error => {
  assert.equal(error.code, 'DuckDBDependencyUnavailable');
  assert.match(error.message, /install @duckdb\/node-api@1\.5\.5-r\.4/u);
  return true;
});
const contribution = new URL('./adapters/connectors/duckdb/node/strategy-bundle.mjs',
  import.meta.resolve('@actql/local-node'));
await assert.rejects(import(contribution.href), {code: 'DuckDBDependencyUnavailable'});
console.log('Packed dependency-free Local: Values, Result, close, attach and explicit refusal passed');
