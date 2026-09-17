import test from 'node:test';
import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));

async function runFailure(reason) {
  const base = await mkdtemp(join(tmpdir(), 'actql-managed-failure-'));
  const duckdb = join(base, 'adapters', 'duckdb-node');
  const store = join(base, 'adapters', 'store-local');
  const runtime = join(base,
    '_build/js/release/build/connectors/duckdb/host_node');
  const state = {calls: {open: 0, settle: 0, close: 0, refresh: 0, cleanup: 0}};
  globalThis.__actqlManagedFailureTest = state;
  try {
    await mkdir(duckdb, {recursive: true});
    await mkdir(store, {recursive: true});
    await mkdir(runtime, {recursive: true});
    await writeFile(join(base, 'package.json'), '{"type":"module"}\n');
    await cp(join(root, 'adapters/duckdb-node/managed-strategy-compute.mjs'),
      join(duckdb, 'managed-strategy-compute.mjs'));
    await cp(join(root, 'adapters/duckdb-node/failure-envelope.mjs'),
      join(duckdb, 'failure-envelope.mjs'));
    await writeFile(join(duckdb, 'configuration.mjs'), `
export class DuckDBTransportError extends Error {
  constructor(code, options) { super(code, options); this.code = code; }
}
`);
    await writeFile(join(store, 'files.mjs'), `
import {createLocalRetainedStore as actual} from ${JSON.stringify(
      pathToFileURL(join(root, 'adapters/store-local/files.mjs')).href)};
export async function createLocalRetainedStore(options) {
  const state = globalThis.__actqlManagedFailureTest;
  state.store = await actual(options);
  state.controller.abort(state.reason);
  return {...state.store, cleanup: async () => {
    state.calls.cleanup++;
    return state.store.cleanup();
  }};
}
`);
    for (const name of ['managed-representations.mjs',
      'managed-physical-representation.mjs']) {
      await writeFile(join(store, name), `export * from ${JSON.stringify(
        pathToFileURL(join(root, 'adapters/store-local', name)).href)};\n`);
    }
    await writeFile(join(duckdb, 'physical-capacity.mjs'),
      'export const computePhysicalCapacity=()=>({transferBytes:1n,executionBytes:1n});\n');
    await writeFile(join(duckdb, 'session.mjs'), `
export {DuckDBTransportError} from './configuration.mjs';
export const validateLimits=value=>Object.freeze({...value});
export const withComputeDatabase=()=>{throw new Error('native must not start');};
`);
    await writeFile(join(duckdb, 'runtime-result.mjs'),
      'export const checked=value=>value;\n');
    await writeFile(join(duckdb, 'managed-column-codec.mjs'), `
export const managedColumnCodecContractCid='column';
export const encodeManagedColumnFrame=()=>{throw new Error('encoder must not run');};
`);
    await writeFile(join(duckdb, 'managed-parquet-codec.mjs'),
      "export const managedParquetCodecContractCid='parquet';\n");
    await writeFile(join(runtime, 'host_node.js'), `
const state=()=>globalThis.__actqlManagedFailureTest;
export const managedStrategyRetentionCapacity=()=>0;
export const managedStrategyScratchCapacity=()=>0;
export const managedStrategyHostOpen=()=>{state().calls.open++;return {};};
export const managedStrategyOutputFileCapacity=()=>1024n;
export const managedStrategyInputCount=()=>1;
export const managedStrategyInputAt=()=>({});
export const managedStrategyCreateSql=()=>'';
export const managedStrategyInputFileSqlAt=()=>'';
export const managedStrategyInputFileViewSqlAt=()=>'';
export const managedStrategyInputParquetViewSqlAt=()=>'';
export const managedStrategyOccurrenceSql=()=>undefined;
export const managedStrategySql=()=>'';
export const managedStrategyParameterCount=()=>0;
export const managedStrategySettle=()=>{state().calls.settle++;};
export const managedStrategyClose=()=>{state().calls.close++;};
export const managedStrategyRefreshRetention=()=>{state().calls.refresh++;};
`);
    state.controller = new AbortController();
    state.reason = reason;
    const module = await import(pathToFileURL(
      join(duckdb, 'managed-strategy-compute.mjs')).href);
    let failure;
    try {
      await module.runManagedColumnStrategyHostCompute(
        {}, {}, 'column', {maxSqlBytes: 10000},
        {parentDirectory: base, maxFrameBytes: 1024},
        state.controller.signal,
      );
    } catch (error) { failure = error; }
    return {failure, calls: {...state.calls}, status: state.store.status()};
  } finally {
    state.store?.close();
    await state.store?.cleanup();
    delete globalThis.__actqlManagedFailureTest;
    await rm(base, {recursive: true, force: true});
  }
}

test('managed Host cleans up after null and primitive abort reasons', async () => {
  for (const reason of [null, false, 0, '']) {
    const {failure, calls, status} = await runFailure(reason);
    assert.equal(failure.code, 'ManagedStrategyFailed');
    assert.equal(failure.primaryFailure, reason);
    assert.equal(failure.cause, reason);
    assert.deepEqual(calls, {
      open: 1, settle: 1, close: 1, refresh: 1, cleanup: 1,
    });
    assert.equal(status.reservedBytes, 0);
    assert.equal(status.cleanupPending, false);
  }
});

test('managed Host does not mutate a frozen abort Error', async () => {
  const reason = Object.freeze(Object.assign(new Error('frozen abort'), {
    code: 'Cancelled',
  }));
  const {failure, calls, status} = await runFailure(reason);
  assert.equal(failure.code, 'Cancelled');
  assert.equal(failure.primaryFailure, reason);
  assert.equal(failure.cause, reason);
  assert.equal(calls.settle, 1);
  assert.equal(calls.close, 1);
  assert.equal(calls.cleanup, 1);
  assert.equal(status.reservedBytes, 0);
});
