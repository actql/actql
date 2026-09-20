import test from 'node:test';
import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {settleFailedManagedDuckDB} from '../managed-failure.mjs';
import * as portableRuntime from
  '../../../../../_build/js/release/build/connectors/duckdb/host_node/host_node.js';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));

async function runFailure(reason, {failCleanupOnce = false} = {}) {
  const base = await mkdtemp(join(tmpdir(), 'actql-managed-failure-'));
  const duckdb = join(base, 'adapters', 'connectors', 'duckdb', 'node');
  const store = join(base, 'adapters', 'store-local');
  const runtime = join(base,
    '_build/js/release/build/connectors/duckdb/host_node');
  const state = {
    calls: {open: 0, settle: 0, close: 0, refresh: 0, cleanup: 0},
    failCleanupOnce,
    cleanupFailed: false,
  };
  globalThis.__actqlManagedFailureTest = state;
  try {
    await mkdir(duckdb, {recursive: true});
    await mkdir(store, {recursive: true});
    await mkdir(runtime, {recursive: true});
    await writeFile(join(base, 'package.json'), '{"type":"module"}\n');
    await cp(join(root, 'adapters/connectors/duckdb/node/managed-strategy-compute.mjs'),
      join(duckdb, 'managed-strategy-compute.mjs'));
    await cp(join(root, 'adapters/connectors/duckdb/node/failure-envelope.mjs'),
      join(duckdb, 'failure-envelope.mjs'));
    await cp(join(root, 'adapters/connectors/duckdb/node/managed-failure.mjs'),
      join(duckdb, 'managed-failure.mjs'));
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
    if (state.failCleanupOnce && !state.cleanupFailed) {
      state.cleanupFailed = true;
      throw new Error('injected cleanup failure');
    }
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
export const managedColumnTransferEstimate=()=>({
  transferBytes:1n,
  retainedBytes:1n,
  executionBytes:1n,
});
export const encodeManagedColumnFrame=()=>{throw new Error('encoder must not run');};
export const managedColumnRowProvider=()=>{throw new Error('provider must not run');};
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
export const managedStrategyCleanupRefresh=()=>{
  state().calls.refresh++;
  return true;
};
export {
  managedStrategyFailureBegin,
  managedStrategyFailureRecordOutputCancelAttempted,
  managedStrategyFailureRecordOutputOwnersCloseAttempted,
  managedStrategyFailureRecordOutputReclaimAttempted,
  managedStrategyFailureRecordExecutionCloseAttempted,
  managedStrategyFailureRecordObservations,
  managedStrategyFailureRecordExecutionCleanupConfirmed,
  managedStrategyFailureAction,
  managedStrategyFailureRetryBegin,
  managedStrategyFailureRecordNativeRetryAttempted,
  managedStrategyFailureRecordOutputRetryAttempted,
  managedStrategyFailureRetryAction,
} from ${JSON.stringify(pathToFileURL(join(root,
  '_build/js/release/build/connectors/duckdb/host_node/host_node.js')).href)};
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
    const initialStatus = state.store.status();
    let retryStatus;
    if (failCleanupOnce) {
      retryStatus = await failure.cleanupHandle.retry();
    }
    return {
      failure,
      calls: {...state.calls},
      initialStatus,
      retryStatus,
      status: state.store.status(),
    };
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

test('frozen abort and cleanup failure preserve both causes and still retry',
  async () => {
    const reason = Object.freeze(Object.assign(new Error('frozen abort'), {
      code: 'Cancelled',
    }));
    const {
      failure,
      calls,
      initialStatus,
      retryStatus,
      status,
    } = await runFailure(reason, {failCleanupOnce: true});
    assert.equal(failure.code, 'Cancelled');
    assert.equal(failure.primaryFailure, reason);
    assert.equal(failure.cause, reason);
    assert.equal(failure.cleanupErrors.length, 1);
    assert.match(failure.cleanupErrors[0].message, /injected cleanup failure/);
    assert.equal(initialStatus.cleanupPending, true);
    assert.equal(initialStatus.reservedBytes, 1024);
    assert.equal(retryStatus.pending, false);
    assert.equal(status.cleanupPending, false);
    assert.equal(status.reservedBytes, 0);
    assert.deepEqual(calls, {
      open: 1, settle: 1, close: 1, refresh: 1, cleanup: 2,
    });
  });

test('native and output cleanup retry independently before task release',
  async () => {
    const calls = {
      cancel: 0,
      bodyClose: 0,
      storeClose: 0,
      storeCleanup: 0,
      taskClose: 0,
      settle: 0,
      refresh: 0,
      nativeRetry: 0,
    };
    const lifecycle = {
      sessionStarted: true,
      executionSettled: false,
      outputDisposed: false,
    };
    let nativePending = true;
    let outputPending = true;
    const nativeFailure = new Error('native operation still running');
    nativeFailure.cleanupPending = true;
    nativeFailure.cleanupErrors = Object.freeze([]);
    nativeFailure.cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending: nativePending, errors: []}),
      async retry() {
        calls.nativeRetry++;
        if (calls.nativeRetry === 1) throw new Error('native retry failed');
        nativePending = false;
        lifecycle.executionSettled = true;
        return Object.freeze({pending: false, errors: []});
      },
    });
    const moon = Object.freeze({
      ...portableRuntime,
      managedOutputCancel() { calls.cancel++; },
      managedStrategyClose() { calls.taskClose++; },
      managedStrategySettle() { calls.settle++; },
      managedStrategyCleanupRefresh() { calls.refresh++; return true; },
    });
    const store = Object.freeze({
      close() { calls.storeClose++; },
      status: () => Object.freeze({cleanupPending: outputPending}),
      async cleanup() {
        calls.storeCleanup++;
        if (calls.storeCleanup === 1) throw new Error('Store cleanup failed');
        outputPending = false;
        return true;
      },
    });
    const failure = await settleFailedManagedDuckDB(
      moon,
      value => value,
      {
        run: {},
        output: {},
        body: Object.freeze({close() { calls.bodyClose++; }}),
        store,
        lifecycle,
      },
      nativeFailure,
    );
    assert.equal(failure.cleanupPending, true);
    assert.equal(calls.cancel, 1);
    assert.equal(calls.bodyClose, 1);
    assert.equal(calls.storeClose, 1);
    assert.equal(calls.storeCleanup, 1);
    assert.equal(calls.taskClose, 1);
    assert.equal(calls.settle, 0);
    assert.equal(calls.refresh, 0);

    const first = await failure.cleanupHandle.retry();
    assert.equal(first.pending, true);
    assert.equal(calls.nativeRetry, 1);
    assert.equal(calls.storeCleanup, 2,
      'Store cleanup must proceed after an independent native retry failure');
    assert.equal(calls.refresh, 0);

    const second = await failure.cleanupHandle.retry();
    assert.equal(second.pending, false);
    assert.equal(calls.nativeRetry, 2);
    assert.equal(calls.storeCleanup, 2);
    assert.equal(calls.settle, 0,
      'native accounting already established settlement');
    assert.equal(calls.refresh, 1);
    assert.equal(lifecycle.outputDisposed, true);
  });

test('failure before output allocation still confirms retention disposal',
  async () => {
    const lifecycle = {
      sessionStarted: false,
      executionSettled: false,
      outputDisposed: false,
    };
    let closes = 0;
    let settlements = 0;
    let refreshes = 0;
    const moon = Object.freeze({
      ...portableRuntime,
      managedStrategyClose() { closes++; },
      managedStrategySettle() { settlements++; },
      managedStrategyCleanupRefresh() {
        refreshes++;
        return lifecycle.outputDisposed;
      },
    });
    const reason = new Error('allocation failed');
    const failure = await settleFailedManagedDuckDB(
      moon,
      value => value,
      {run: {}, lifecycle},
      reason,
    );
    assert.equal(failure.cleanupPending, false);
    assert.equal(lifecycle.outputDisposed, true);
    assert.equal(closes, 1);
    assert.equal(settlements, 1);
    assert.equal(refreshes, 1);
  });

test('failure before task creation has no synthetic cleanup responsibility',
  async () => {
    const lifecycle = {
      sessionStarted: false,
      executionSettled: false,
      outputDisposed: false,
    };
    const moon = Object.freeze({
      ...portableRuntime,
    });
    const reason = new Error('task setup failed');
    const failure = await settleFailedManagedDuckDB(
      moon,
      value => value,
      {lifecycle},
      reason,
    );
    assert.equal(failure.cleanupPending, false);
    assert.equal(failure.cleanupHandle, undefined);
    assert.equal(lifecycle.executionSettled, false,
      'the portable owner represents a missing execution without a JS write');
    assert.equal(lifecycle.outputDisposed, true);
  });
