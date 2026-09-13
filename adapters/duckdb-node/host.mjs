// Standard source-checkout Host entry. Neither Program inputs nor ordinary
// Connector registration can supply a replacement runtime/verifier/SQL callback.
import { randomUUID } from 'node:crypto';
import { runNativeQuery } from './native-query.mjs';
import { runBroadQuery } from './broad-query.mjs';
import { DuckDBTransportError } from './session.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/duckdb_host_node/duckdb_host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);

// The pinned MoonBit JS compiler exports typed `raise` as Result, not a JS
// throw. Keep its generated ABI here, outside semantic/provenance verification.
// These values come only from the fixed product runtime, never from a provider.
function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw new DuckDBTransportError('MoonBitHostFailure', { cause: result._0 });
  }
  throw new DuckDBTransportError('InvalidHostRuntimeResult');
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
  const moon = await loadRuntime();
  const captured = await runNativeQuery(grant, verify => {
    const run = checked(moon.nativeHostOpen(setup, randomUUID(), verify));
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
  }, limits, signal);
  return Object.freeze({
    observation: captured.observation,
    document: () => moon.nativeHostDocument(captured.observation),
    output: () => captured.bindInput(),
    close: () => captured.close(),
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
