// Standard source-checkout Host entry. Neither Program inputs nor ordinary
// Connector registration can supply a replacement runtime/verifier/SQL callback.
import { randomUUID } from 'node:crypto';
import { runNativeQuery } from './native-query.mjs';
import { runBroadQuery } from './broad-query.mjs';
import { runFixedCompute, matchesFixedCompute, releaseFixedCompute } from './fixed-compute.mjs';
import { DuckDBTransportError } from './session.mjs';
import { computePhysicalCapacity } from './physical-capacity.mjs';
import { checked } from './runtime-result.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/duckdb_host_node/duckdb_host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);

// No source grant or connection enters Compute. The fixed product runtime
// supplies the selected SQL and exact owned input; verifier wiring stays here.
export async function runFixedHostCompute(setup, limits, importLimits, signal) {
  return runHostCompute(setup, limits, importLimits, signal, false);
}

// Same trusted transport wiring, with completion owned by the checked DAG.
export async function runStrategyHostCompute(setup, limits, importLimits, signal) {
  return runHostCompute(setup, limits, importLimits, signal, true);
}

async function runHostCompute(setup, limits, importLimits, signal, strategy) {
  const moon = await loadRuntime();
  // Freeze the same values used by both reservation and actual transport. A
  // caller mutating its limits during an await cannot enlarge the execution.
  limits = Object.freeze({ ...limits });
  const capacity = strategy ? Object.freeze({
    ...computePhysicalCapacity(limits),
    retentionBytes: checked(moon.computeStrategyRetentionCapacity(setup)),
    receiverScratchBytes: checked(moon.computeStrategyScratchCapacity(setup)),
  }) : undefined;
  let result, port, consume, attempt;
  const verify = current => current === attempt && matchesFixedCompute(result, port, consume);
  let run = checked(strategy
    ? moon.computeStrategyHostOpen(setup, verify, capacity.transferBytes, capacity.executionBytes)
    : moon.computeHostOpen(setup, verify));
  attempt = moon.computeHostAttempt(run);
  let sessionStarted = false;
  const accounting = strategy ? Object.freeze({
    started() { sessionStarted = true; },
    chargeTransfer(bytes) { checked(moon.computeHostPhysicalCharge(run, BigInt(bytes))); },
    settled(confirmed) { checked(moon.computeHostPhysicalSettle(run, confirmed)); },
  }) : undefined;
  let began = false;
  const begin = fields => {
    if (!began) {
      checked(moon.computeHostBegin(run, fieldsFrame(fields)));
      began = true;
    }
  };
  port = Object.freeze({
    rowCount: () => rows(moon.computeHostCount(run, false)),
    columnCount: () => rows(moon.computeHostCount(run, true)),
    createSql: () => checked(moon.computeHostSql(run, 0)),
    insertSql: () => checked(moon.computeHostSql(run, 1)),
    parameter: (row, column) => JSON.parse(checked(moon.computeHostParameter(run, row, column, false))),
    querySql: () => checked(moon.computeHostSql(run, 2)),
    queryParameters: () => [JSON.parse(checked(moon.computeHostParameter(run, 0, 0, true)))],
  });
  consume = chunk => {
    begin(chunk.fields);
    checked(moon.computeHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
  };
  try {
    result = await runFixedCompute(port, limits, importLimits, consume, signal, accounting);
    if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
    begin(result.value.fields); // empty input still has checked output metadata
    checked(moon.computeHostFinish(run));
    let output = checked(moon.computeHostComplete(run));
    let closed = false;
    return Object.freeze({
      usage: result.usage,
      physicalCapacity: capacity === undefined ? undefined : Object.freeze({
        ...capacity, executionBytes: capacity.executionBytes + capacity.receiverScratchBytes,
      }),
      importedRows: result.value.importedRows,
      importedCells: result.value.importedCells,
      output() {
        if (closed) throw new DuckDBTransportError('ReleasedCompute');
        return output;
      },
      close() {
        if (closed) return;
        closed = true;
        moon.computeHostClose(run);
        releaseFixedCompute(result);
        // This successful session is already settled. Do not keep otherwise
        // unused completion/input buffers alive through a retained closed handle.
        output = undefined;
        run = undefined;
        result = undefined;
        attempt = undefined;
        port = undefined;
        consume = undefined;
      },
    });
  } catch (error) {
    if (strategy && !sessionStarted) checked(moon.computeHostPhysicalSettle(run, true));
    moon.computeHostAbort(run);
    moon.computeHostClose(run);
    if (result !== undefined) releaseFixedCompute(result);
    throw error;
  }
}

function fieldsFrame(fields) {
  // Structural transport only: physical type interpretation remains MoonBit's
  // shared descriptor decoder. Names are not NFC/LF-normalized here.
  return JSON.stringify(fields.map(({ name, type }) => [
    name, type.id, type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale),
  ]));
}

function rows(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) {
    throw new DuckDBTransportError('InvalidHostRowCount');
  }
  return value;
}

// setup is an opaque NativeHostConfiguration from trusted MoonBit application
// preparation, not serialized Program JSON and not a source-file authorization.
export async function runNativeHostQuery(grant, setup, limits, signal) {
  return runHostNativeQuery(grant, setup, limits, signal);
}

// The same owned ledger will receive the capture root and every later task.
// No caller-supplied verifier or accounting callback enters this standard API.
export async function runStrategyNativeHostQuery(grant, setup, ledger, limits, signal) {
  return runHostNativeQuery(grant, setup, limits, signal, ledger);
}

async function runHostNativeQuery(grant, setup, limits, signal, ledger) {
  const moon = await loadRuntime();
  limits = Object.freeze({ ...limits });
  const capacity = ledger === undefined ? undefined : Object.freeze({
    ...computePhysicalCapacity(limits),
    retentionBytes: checked(moon.nativeHostCapacity(setup, true)),
    receiverScratchBytes: checked(moon.nativeHostCapacity(setup, false)),
  });
  let capturedRun;
  let sessionStarted = false;
  const accounting = capacity === undefined ? undefined : Object.freeze({
    started() { sessionStarted = true; },
    chargeTransfer(bytes) { checked(moon.nativeHostPhysicalCharge(capturedRun, BigInt(bytes))); },
    settled(confirmed) { checked(moon.nativeHostPhysicalSettle(capturedRun, confirmed)); },
  });
  const captured = await runNativeQuery(grant, verify => {
    const run = checked(capacity === undefined
      ? moon.nativeHostOpen(setup, randomUUID(), verify)
      : moon.nativeStrategyHostOpen(setup, ledger, randomUUID(), verify,
        capacity.transferBytes, capacity.executionBytes));
    capturedRun = run;
    const attempt = moon.nativeHostAttempt(run);
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      if (current !== view) throw new DuckDBTransportError('ForeignReadView');
    };
    const port = Object.freeze({
      metadataSql: () => checked(moon.nativeHostSql(run, 0)),
      metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.nativeHostParameter(run, index)))),
      acceptMetadata(chunk, current) {
        owns(current);
        checked(moon.nativeHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
      },
      finishMetadata(_fields, current) { owns(current); },
      validationSql: () => checked(moon.nativeHostSql(run, 1)),
      nativeSql: () => checked(moon.nativeHostSql(run, 2)),
      nativeParameters: () => [JSON.parse(checked(moon.nativeHostParameter(run, 2)))],
      beginReceipt(role, fields, current) {
        owns(current);
        checked(moon.nativeHostBegin(run, role === 'native_result', fieldsFrame(fields)));
      },
      acceptChunk(_role, chunk, current) {
        owns(current);
        checked(moon.nativeHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
      },
      finishReceipt(_role, current) {
        owns(current);
        checked(moon.nativeHostFinish(run));
        return attempt;
      },
      abort() { moon.nativeHostAbort(run); },
    });
    return Object.freeze({
      attempt, port,
      complete: () => checked(moon.nativeHostComplete(run)),
      bindInput: observation => checked(moon.nativeHostOutput(run, observation)),
      abort() { moon.nativeHostAbort(run); },
      close() { moon.nativeHostClose(run); },
    });
  }, limits, signal, accounting).catch(error => {
    if (capacity !== undefined && capturedRun !== undefined && !sessionStarted) {
      checked(moon.nativeHostPhysicalSettle(capturedRun, true));
    }
    throw error;
  });
  let closed = false;
  const liveRun = () => {
    if (closed) throw new DuckDBTransportError('IssuerClosed');
    return capturedRun;
  };
  return Object.freeze({
    observation: captured.observation,
    usage: captured.usage,
    physicalCapacity: capacity === undefined ? undefined : Object.freeze({
      ...capacity, executionBytes: capacity.executionBytes + capacity.receiverScratchBytes,
    }),
    document: () => moon.nativeHostDocument(captured.observation),
    ...(capacity === undefined ? {
      output: () => captured.bindInput(),
      source: () => checked(moon.nativeHostCapturedSource(liveRun(), captured.observation)),
    } : {
      openDAG: graph => checked(moon.nativeHostOpenDAG(liveRun(), graph, captured.observation)),
    }),
    close() {
      if (closed) return;
      closed = true;
      try { captured.close(); }
      finally { capturedRun = undefined; }
    },
  });
}

// The broad result binds directly to an owned consumer through the existing
// captured-input API. No caller-supplied expected producer or success proof.
export async function runBroadHostQuery(grant, setup, limits, signal) {
  const moon = await loadRuntime();
  const captured = await runBroadQuery(grant, verify => {
    const run = checked(moon.broadHostOpen(setup, randomUUID(), verify));
    const attempt = moon.broadHostAttempt(run);
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      if (view !== current) throw new DuckDBTransportError('ForeignReadView');
    };
    const port = Object.freeze({
      metadataSql: () => moon.broadHostSql(run, true),
      metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.broadHostParameter(run, index)))),
      acceptMetadata(chunk, current) {
        owns(current);
        checked(moon.broadHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
      },
      finishMetadata(_fields, current) { owns(current); },
      scanSql: () => moon.broadHostSql(run, false),
      beginReceipt(fields, current) {
        owns(current);
        checked(moon.broadHostBegin(run, fieldsFrame(fields)));
      },
      acceptChunk(chunk, current) {
        owns(current);
        checked(moon.broadHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
      },
      finishReceipt(current) {
        owns(current);
        checked(moon.broadHostFinish(run));
        return attempt;
      },
      abort() { moon.broadHostAbort(run); },
    });
    return Object.freeze({
      attempt, port,
      complete: () => checked(moon.broadHostComplete(run)),
      bindInput: (observation, receiver, inputIndex) => checked(moon.broadHostBind(run, observation, receiver, rows(inputIndex))),
      abort() { moon.broadHostAbort(run); },
      close() { moon.broadHostClose(run); },
    });
  }, limits, signal);
  return Object.freeze({
    observation: captured.observation,
    document: () => moon.broadHostDocument(captured.observation),
    bindInput: (receiver, inputIndex) => captured.bindInput(receiver, inputIndex),
    close: () => captured.close(),
  });
}
