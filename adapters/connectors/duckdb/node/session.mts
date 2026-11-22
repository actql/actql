// Host-private native transport. SQL must come from the trusted MoonBit adapter;
// this is not a Program SQL API, semantic verifier or completion issuer.
import { realpath, stat, lstat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { DuckDBInstance, StatementType } from '@duckdb/node-api';
import type {DuckDBConnection, DuckDBAppender, DuckDBPreparedStatement} from '@duckdb/node-api';
// @ts-expect-error TS7016 Physical values are still authored in JavaScript.
import { bindPhysicalValue, exportPhysicalValue, physicalJsonScalarBytes, physicalType } from './physical-values.mjs';
// @ts-expect-error TS7016 Physical appending is still authored in JavaScript.
import {createPhysicalAppender} from './physical-appender.mjs';
import { DuckDBTransportError, validateLimits } from './configuration.mjs';
import {boundedTransport, maxNativeVectorRows} from './transport-bounds.mjs';
// @ts-expect-error TS7016 Bounded vectors are still authored in JavaScript.
import {assertBoundedVectorRuntime, boundedVectorItem} from './bounded-vector.mjs';
import environmentContract from '../environment-contract.json' with {type: 'json'};
export { DuckDBTransportError, validateLimits } from './configuration.mjs';
import {ExecutionAuthorizationError, missingAuthorizationGate} from
  '../../../host-common/authorization-gate.mjs';

import type {createAuthorizationGate} from '../../../host-common/authorization-gate.mjs';

type Authorize = ReturnType<typeof createAuthorizationGate>['authorize'];
type ReadDecision = Pick<Awaited<ReturnType<Authorize>>, 'action' | 'basis' | 'reason'>;
type Authorization = {authorize(...args: Parameters<Authorize>): ReadDecision | Promise<ReadDecision>};
type SourceAccess = Readonly<{
  authorization?: Authorization;
  connection?: string;
  resource?: string;
  subjectCid?: string;
  sourceRef?: string;
}>;
type SourceGrant = Readonly<{
  path: string;
  authorization: Authorization;
  scope: Parameters<Authorize>[1];
  subjectCid?: string;
  sourceRef?: string;
}>;
type Limits = Parameters<typeof validateLimits>[0];
type ValidatedLimits = Limits & Parameters<typeof boundedTransport>[0] & Readonly<Record<'maxRows' | 'maxCells' | 'maxTransportBytes' |
  'maxSqlBytes' | 'maxParameters' | 'maxColumns' | 'memoryBytes' | 'threads', number>>;
type Settlement = {settled(confirmed: boolean): void};
type Accounting = Settlement & {started(): void; chargeTransfer(bytes: number): void};
type CleanupStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type CleanupHandle = Readonly<{status(): CleanupStatus; retry(): Promise<CleanupStatus>}>;
type CleanupFailure = Readonly<{code?: string; cleanupErrors?: readonly unknown[];
  cleanupPending?: boolean; cleanupHandle?: CleanupHandle}>;
type TransportFailure = DuckDBTransportError & {
  primaryFailure: unknown;
  cleanupErrors: readonly unknown[];
  cleanupPending: boolean;
  cleanupHandle?: CleanupHandle;
};
type Deadline = {expired: true; failed?: never; error?: never; value?: never};
type Completion<Value> = {value: Value; expired?: never; failed?: never; error?: never} |
  {failed: true; error: unknown; expired?: never; value?: never};
type PhysicalType = Readonly<{id: string; precision?: number; scale?: number}>;
type Parameter = Readonly<{type: PhysicalType; value: unknown}>;
type Field = Readonly<{name: string; type: PhysicalType}>;
type Scalar = string | boolean | number | null;
type Frame = Readonly<{fields: readonly Field[]; rowCount: number; columns: readonly (readonly Scalar[])[]}>;
type Consume = (chunk: Frame) => unknown;
type ReceiveMetadata = (fields: readonly Field[]) => unknown;
type Command = (sql: string, parameters: readonly Parameter[], consume: Consume,
  reuseInsert?: boolean, statementMode?: 'ordinary' | 'copy-parquet',
  receiveMetadata?: ReceiveMetadata) => Promise<readonly Field[]>;
type ResidentAppender = Readonly<{
  types: readonly PhysicalType[];
  appendScalars(values: readonly Scalar[]): void;
  append(parameters: readonly Parameter[]): void;
  flush(): void;
  finish(): void;
}>;
type Usage = Readonly<{
  rows: number; cells: number; transportBytes: number; statements: number; preparations: number; chunks: number;
  appendedRows: number; commandMilliseconds: number; prepareMilliseconds: number;
  receiveCallbackMilliseconds: number; cleanupMilliseconds: number;
}>;
type Session = Readonly<{
  command: Command;
  insert(sql: string, parameters: readonly Parameter[], consume: Consume): Promise<readonly Field[]>;
  openResidentAppender(table: string, columns: number): Promise<ResidentAppender>;
  createFileView(sql: string, inputPath: string, consume: Consume): Promise<readonly Field[]>;
  copyParquet(selectSql: string, parameters: readonly Parameter[], outputPath: string):
    Promise<Readonly<{device: number; inode: number; bytes: number}>>;
  usage(): Usage;
}>;
type SessionBody<Value> = (session: Session) => Value | Promise<Value>;
type SharedDatabase = Readonly<{instance: DuckDBInstance}>;

const files = new WeakMap<object, SourceGrant>();


// Call only from explicit Host setup, never from Program/source wire decoding.
// The returned grant cannot be reconstructed by serializing its properties.
// `access` binds the Host's execution-authorization gate and the Host-declared
// connection/resource names of this source. The file grant is a technical
// admission only: every acquisition still needs a dispatch decision for this
// exact scope before any provider session opens. Without a gate the Host has
// no account configuration and acquisition is denied (configuration_missing).
export async function authorizeLocalDatabase(path: unknown, access: SourceAccess = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) throw new DuckDBTransportError('InvalidSourcePath');
  if (access === null || typeof access !== 'object') throw new DuckDBTransportError('InvalidSourceAccess');
  const authorization = access.authorization ?? missingAuthorizationGate();
  if (typeof authorization?.authorize !== 'function' ||
      (access.connection !== undefined && typeof access.connection !== 'string') ||
      (access.resource !== undefined && typeof access.resource !== 'string') ||
      (access.subjectCid !== undefined && typeof access.subjectCid !== 'string') ||
      (access.sourceRef !== undefined && (typeof access.sourceRef !== 'string' ||
        access.sourceRef.length === 0))) {
    throw new DuckDBTransportError('InvalidSourceAccess');
  }
  const resolved = await realpath(path);
  if (!(await stat(resolved)).isFile()) throw new DuckDBTransportError('SourceNotFile');
  const grant = Object.freeze({});
  files.set(grant, Object.freeze({
    path: resolved,
    authorization,
    scope: Object.freeze({
      connection: access.connection ?? 'local-database',
      resource: access.resource ?? resolved,
      operation: 'read',
    }),
    subjectCid: access.subjectCid,
    sourceRef: access.sourceRef,
  }));
  return grant;
}

// Acquisition boundary shared by every source read (native and broad,
// metadata/catalog SQL included): no provider session opens without a
// dispatch decision for this exact scope.
async function authorizeSourceAccess(source: SourceGrant, signal?: AbortSignal) {
  const decision = await source.authorization.authorize(
    'acquisition', source.scope, {subjectCid: source.subjectCid, signal},
  );
  if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
  signal?.throwIfAborted();
  return decision;
}

// A caller's cancellation deadline is not native settlement. Keep observing the
// original operation and retain its cleanup responsibility after returning early.
async function cancellationBoundary<Value>(start: (limits: Limits) => Promise<Value>, limits: Limits,
  signal?: AbortSignal, accounting?: Settlement) {
  limits = validateLimits(limits);
  if (limits.cancelWaitMs === undefined || !signal) return start(limits);
  let settled = false;
  let terminalError: CleanupFailure | null | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let resolveDeadline!: (deadline: Deadline) => void;
  const deadline = new Promise<Deadline>(resolve => { resolveDeadline = resolve; });
  const onAbort = () => {
    if (timer !== undefined || settled) return;
    timer = setTimeout(() => resolveDeadline({ expired: true }), limits.cancelWaitMs);
  };
  signal.addEventListener('abort', onAbort, { once: true });
  const operation = Promise.resolve().then(() => start(limits)).then<Completion<Value>, Completion<Value>>(
    value => { settled = true; return { value }; },
    error => { settled = true; terminalError = error as CleanupFailure | null | undefined; return { failed: true, error }; },
  );
  if (signal.aborted) onAbort();
  let outcome = await Promise.race([operation, deadline]);
  signal.removeEventListener('abort', onAbort);
  clearTimeout(timer);
  if (outcome.expired && settled) outcome = await operation;
  if (!outcome.expired) {
    if (outcome.failed) throw outcome.error;
    return outcome.value;
  }
  const status = () => Object.freeze({
    pending: !settled || (terminalError?.cleanupHandle?.status().pending ?? false),
    errors: terminalError?.cleanupHandle?.status().errors ?? terminalError?.cleanupErrors ?? Object.freeze([]),
  });
  const failure = new DuckDBTransportError('Cancelled') as TransportFailure;
  failure.primaryFailure = new DuckDBTransportError('Cancelled');
  failure.cleanupErrors = Object.freeze([]);
  failure.cleanupPending = true;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      await operation;
      if (terminalError?.cleanupHandle?.status().pending) await terminalError.cleanupHandle.retry();
      return status();
    },
  });
  accounting?.settled(false);
  throw failure;
}

async function usingSession<Value>(path: string, readonly: boolean, suppliedLimits: Limits, body: SessionBody<Value>,
  signal?: AbortSignal, accounting?: Accounting, shared?: SharedDatabase, inputFiles: readonly string[] = []) {
  const limits = validateLimits(suppliedLimits) as ValidatedLimits;
  const bounded = boundedTransport(limits);
  if (bounded) assertBoundedVectorRuntime();
  accounting?.started();
  let cancelled = signal?.aborted ?? false;
  let active = true;
  let busy = false;
  let pending = false;
  let instance: DuckDBInstance | undefined;
  let connection: DuckDBConnection | undefined;
  let transaction = false;
  let commandFailure: unknown;
  let commandFailed = false;
  // At most one prepared INSERT, owned by this exact session. It replaces, not
  // supplements, the ordinary per-command statement allocation.
  let cachedInsert: {sql: string; prepared: DuckDBPreparedStatement} | undefined;
  let activeAppender: DuckDBAppender | undefined;
  let appenderFailure: unknown;
  let appenderFailed = false;
  const inFlight = new Set<Promise<unknown>>();
  const recordAppenderFailure = (error: unknown) => {
    if (!appenderFailed) appenderFailure = error;
    appenderFailed = true;
  };
  const recordCommandFailure = (error: unknown) => {
    if (!commandFailed) commandFailure = error;
    commandFailed = true;
  };
  const trackFlight = <Result,>(promise: Promise<Result>, recordFailure: (error: unknown) => void) => {
    inFlight.add(promise);
    promise.then(
      () => inFlight.delete(promise),
      error => {
        recordFailure(error);
        inFlight.delete(promise);
      },
    );
    return promise;
  };
  const usage = { rows: 0, cells: 0, transportBytes: 0, statements: 0, preparations: 0, chunks: 0,
    appendedRows: 0,
    commandMilliseconds: 0, prepareMilliseconds: 0, receiveCallbackMilliseconds: 0, cleanupMilliseconds: 0 };
  const destroyCachedInsert = () => {
    cachedInsert?.prepared.destroySync();
    cachedInsert = undefined;
  };
  const assertLive = () => {
    if (cancelled) throw new DuckDBTransportError('Cancelled');
    if (!active) throw new DuckDBTransportError('SessionClosed');
  };
  const onAbort = () => {
    cancelled = true;
    // Do not interrupt a subsequent rollback/cleanup operation.
    if (pending) connection?.interrupt();
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  const chargeBytes = (n: number) => {
    if (n > limits.maxTransportBytes - usage.transportBytes) throw new DuckDBTransportError('TransportBytes');
    accounting?.chargeTransfer(n);
    usage.transportBytes += n;
  };
  const startResidentAppender = async (table: string, columns: number): Promise<ResidentAppender> => {
    assertLive();
    if (busy || readonly || !shared || activeAppender ||
        typeof table !== 'string' || !/^resident_(0|[1-9][0-9]{0,9})$/.test(table) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > limits.maxColumns) {
      throw new DuckDBTransportError('InvalidResidentAppender');
    }
    busy = true;
    try {
      pending = true;
      activeAppender = await connection!.createAppender(table, 'main');
      pending = false;
      assertLive();
      const physical = createPhysicalAppender(activeAppender, columns, {
        rows: Math.min(limits.maxChunkRows ?? 64, 64),
        bytes: Math.min(limits.maxChunkBytes ?? limits.maxTransportBytes, 1024 * 1024),
      });
      let live = true;
      const ensure = () => {
        assertLive();
        if (!live) throw new DuckDBTransportError('AppenderUnavailable');
      };
      return Object.freeze({
        types: physical.types,
        appendScalars(values) {
          try {
            ensure();
            pending = true;
            try {
              physical.appendScalars(values, (bytes: number) => {
                if (bytes > (limits.maxChunkBytes ?? limits.maxTransportBytes)) {
                  throw new DuckDBTransportError('ChunkBytes');
                }
                chargeBytes(bytes);
              });
            } finally { pending = false; }
            usage.appendedRows++;
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
        append(parameters) {
          try {
            ensure();
            if (!Array.isArray(parameters) || parameters.length !== columns) {
              throw new DuckDBTransportError('ImportColumns');
            }
            pending = true;
            try {
              // Stage every typed value before charging or writing a native row.
              // The same bounded pass measures the physical transport charge.
              physical.append(parameters, (bytes: number) => {
                if (bytes > (limits.maxChunkBytes ?? limits.maxTransportBytes)) {
                  throw new DuckDBTransportError('ChunkBytes');
                }
                chargeBytes(bytes);
              });
            }
            finally { pending = false; }
            usage.appendedRows++;
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
        flush() {
          try {
            ensure();
            pending = true;
            try {
              physical.flush();
              activeAppender!.flushSync();
            }
            finally { pending = false; }
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
        finish() {
          try {
            ensure();
            pending = true;
            try {
              physical.flush();
              activeAppender!.closeSync();
              activeAppender = undefined;
              live = false;
              busy = false;
            } finally { pending = false; }
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
      });
    } catch (error) {
      recordAppenderFailure(error);
      busy = false;
      pending = false;
      throw error;
    }
  };
  const openResidentAppender = (...args: Parameters<typeof startResidentAppender>) =>
    trackFlight(startResidentAppender(...args), recordAppenderFailure);
  const runCommand: Command = async (sql, parameters, consume, reuseInsert = false,
    statementMode = 'ordinary', receiveMetadata) => {
    assertLive();
    if (busy) throw new DuckDBTransportError('ConcurrentCommand');
    if (receiveMetadata !== undefined && typeof receiveMetadata !== 'function') throw new DuckDBTransportError('InvalidMetadataReceiver');
    if (typeof sql !== 'string' || Buffer.byteLength(sql, 'utf8') > limits.maxSqlBytes) {
      throw new DuckDBTransportError('SqlBytes');
    }
    if (!Array.isArray(parameters) || parameters.length > limits.maxParameters) {
      throw new DuckDBTransportError('Parameters');
    }
    // Snapshot plain transport parameters before the first await. No Neo object
    // or caller-owned mutable array may change a bound command during execution.
    const bound = parameters.map(({ type, value }) => {
      if (bounded) {
        if (typeof value === 'string' && Buffer.byteLength(value, 'utf8') > limits.maxChunkBytes) {
          throw new DuckDBTransportError('ChunkBytes');
        }
        if ((value !== null && typeof value !== 'string' && typeof value !== 'boolean') ||
            !type || typeof type.id !== 'string' || type.id.length > 32 ||
            Object.keys(type).some(key => !['id', 'precision', 'scale'].includes(key)) ||
            ['precision', 'scale'].some(key => type[key as keyof PhysicalType] !== undefined && !Number.isSafeInteger(type[key as keyof PhysicalType]))) {
          throw new DuckDBTransportError('Parameters');
        }
      }
      return {type: {...type}, value};
    });
    let parameterBytes = Buffer.byteLength('{"parameters":[]}\n', 'utf8');
    if (bounded && parameterBytes > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
    chargeBytes(parameterBytes);
    for (let i = 0; i < bound.length; i++) {
      const bytes = Buffer.byteLength(JSON.stringify(bound[i]), 'utf8') + (i === 0 ? 0 : 1);
      if (bounded && bytes > limits.maxChunkBytes - parameterBytes) throw new DuckDBTransportError('ChunkBytes');
      chargeBytes(bytes);
      parameterBytes += bytes;
    }
    busy = true;
    const commandStarted = performance.now();
    let prepared: DuckDBPreparedStatement | undefined;
    let succeeded = false;
    try {
      if (reuseInsert && cachedInsert?.sql === sql) {
        prepared = cachedInsert.prepared;
      } else {
        destroyCachedInsert();
        const prepareStarted = performance.now();
        try {
          pending = true;
          const extracted = await connection!.extractStatements(sql);
          pending = false;
          assertLive();
          if (extracted.count !== 1) throw new DuckDBTransportError('StatementCount');
          pending = true;
          prepared = await extracted.prepare(0);
          usage.preparations++;
          pending = false;
          assertLive();
        } finally { usage.prepareMilliseconds += performance.now() - prepareStarted; }
      }
      if (reuseInsert && (readonly || prepared.statementType !== StatementType.INSERT)) {
        throw new DuckDBTransportError('StatementKind');
      }
      const allowed = statementMode === 'copy-parquet'
        ? [StatementType.COPY]
        : readonly ? [StatementType.SELECT]
        : [StatementType.SELECT, StatementType.CREATE, StatementType.INSERT,
          ...(shared ? [StatementType.DROP] : [])];
      if (!allowed.includes(prepared.statementType)) throw new DuckDBTransportError('StatementKind');
      if (prepared.parameterCount !== bound.length) throw new DuckDBTransportError('ParameterCount');
      for (let i = 0; i < bound.length; i++) bindPhysicalValue(prepared, i + 1, bound[i]);
      usage.statements++;
      pending = true;
      const result = await prepared.stream();
      pending = false;
      assertLive();
      if (result.columnCount > limits.maxColumns) throw new DuckDBTransportError('Columns');
      const fieldItems: Field[] = [];
      let fieldBytes = Buffer.byteLength('{"fields":[]}\n', 'utf8');
      for (let i = 0; i < result.columnCount; i++) {
        const name = result.columnName(i);
        if (bounded && Buffer.byteLength(name, 'utf8') > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
        const field = Object.freeze({name, type: physicalType(result.columnType(i))});
        const bytes = Buffer.byteLength(JSON.stringify(field), 'utf8') + (i === 0 ? 0 : 1);
        if (bounded && bytes > limits.maxChunkBytes - fieldBytes) throw new DuckDBTransportError('ChunkBytes');
        fieldBytes += bytes;
        fieldItems.push(field);
      }
      const fields = Object.freeze(fieldItems);
      // Charge even an empty result's metadata; rows alone do not bound schema.
      const metadataBytes = Buffer.byteLength(JSON.stringify({ fields }) + '\n', 'utf8');
      if (bounded && metadataBytes > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
      chargeBytes(metadataBytes);
      // The same cursor's typed metadata also exists for an empty result.
      if (receiveMetadata !== undefined) {await receiveMetadata(fields);assertLive();}
      for (;;) {
        pending = true;
        const chunk = await result.fetchChunk();
        pending = false;
        assertLive();
        if (!chunk || chunk.rowCount === 0) break;
        if (bounded && chunk.rowCount > maxNativeVectorRows) throw new DuckDBTransportError('NativeChunkRows');
        if (chunk.rowCount > limits.maxRows - usage.rows) throw new DuckDBTransportError('Rows');
        if (fields.length !== 0 && chunk.rowCount > Math.floor((limits.maxCells - usage.cells) / fields.length)) {
          throw new DuckDBTransportError('Cells');
        }
        usage.rows += chunk.rowCount;
        usage.cells += chunk.rowCount * fields.length;
        const rowsPerBatch = limits.maxChunkRows ?? chunk.rowCount;
        const frameLimit = limits.maxChunkBytes ?? limits.maxTransportBytes;
        for (let start = 0; start < chunk.rowCount;) {
          const maximumRows = Math.min(rowsPerBatch, chunk.rowCount - start);
          const columns = fields.map((): Scalar[] => []);
          const emptyFrameBytes = Buffer.byteLength(JSON.stringify({
            rowCount: 0, columns,
          }) + '\n', 'utf8');
          if (emptyFrameBytes > frameLimit) throw new DuckDBTransportError('ChunkBytes');
          // Variable-width SDK vectors cache decoded values. Use a fresh view
          // for each delivered batch, including a batch split by byte size.
          const vectors = fields.map((_, i) => chunk.getColumnVector(i).slice(start, maximumRows));
          let rowCount = 0;
          let batchBytes = emptyFrameBytes;
          const candidate: Scalar[] = [];
          while (rowCount < maximumRows) {
            candidate.length = 0;
            let nextBytes = batchBytes + String(rowCount + 1).length - String(rowCount).length;
            for (let i = 0; i < fields.length; i++) {
              const item = bounded
                ? boundedVectorItem(vectors[i], rowCount, fields[i].type, frameLimit)
                : vectors[i].getItem(rowCount);
              const cell = exportPhysicalValue(item, fields[i].type);
              nextBytes += physicalJsonScalarBytes(cell) + (rowCount === 0 ? 0 : 1);
              if (nextBytes > frameLimit) break;
              candidate.push(cell);
            }
            if (candidate.length !== fields.length) {
              if (rowCount === 0) throw new DuckDBTransportError('ChunkBytes');
              break;
            }
            for (let i = 0; i < fields.length; i++) columns[i].push(candidate[i]);
            batchBytes = nextBytes;
            rowCount++;
          }
          chargeBytes(batchBytes);
          usage.chunks++;
          const receiveStarted = performance.now();
          try {
            await consume(Object.freeze({ fields, rowCount,
              columns: Object.freeze(columns.map(column => Object.freeze(column))) }));
          } finally { usage.receiveCallbackMilliseconds += performance.now() - receiveStarted; }
          assertLive();
          start += rowCount;
        }
      }
      succeeded = true;
      return fields;
    } finally {
      pending = false;
      try {
        if (prepared && reuseInsert) {
          // Keep ownership until explicit destruction succeeds, including on a
          // failed command. Cleanup must not forget a native statement.
          cachedInsert = {sql, prepared};
          if (succeeded) prepared.clearBindings();
          else destroyCachedInsert();
        } else prepared?.destroySync();
      } finally {
        usage.commandMilliseconds += performance.now() - commandStarted;
        busy = false;
      }
    }
  };
  const command = (...args: Parameters<Command>) => {
    const promise = runCommand(...args);
    // Observe failures even if trusted orchestration accidentally catches or
    // forgets to await a command. Such an attempt must never return success.
    return trackFlight(promise, recordCommandFailure);
  };
  const createFileView = (sql: string, inputPath: string, consume: Consume) => {
    if (typeof sql !== 'string' || typeof inputPath !== 'string' ||
        typeof consume !== 'function' || !inputFiles.includes(inputPath) ||
        !sql.startsWith('CREATE TEMP VIEW ') ||
        sql.indexOf('?') < 0 || sql.indexOf('?') !== sql.lastIndexOf('?')) {
      throw new DuckDBTransportError('InvalidFileView');
    }
    // DuckDB does not allow prepared parameters in CREATE VIEW. Only this
    // installed Host operation may substitute one exact session-authorized
    // path into an adapter-compiled template. General external access remains
    // disabled and the resulting complete SQL is checked by runCommand.
    const quoted = `'${inputPath.replaceAll("'", "''")}'`;
    const pathBytes = Buffer.byteLength(JSON.stringify({
      type: {id: 'VARCHAR'}, value: inputPath,
    }), 'utf8');
    chargeBytes(pathBytes);
    return command(sql.replace('?', quoted), [], consume);
  };
  const runCopyParquet = async (selectSql: string, parameters: readonly Parameter[], outputPath: string) => {
    if (typeof selectSql !== 'string' || !inputFiles.includes(outputPath)) {
      throw new DuckDBTransportError('UnauthorizedOutputPath');
    }
    const quoted = `'${outputPath.replaceAll("'", "''")}'`;
    await command(`COPY (${selectSql}) TO ${quoted} (FORMAT PARQUET)`,
      parameters, () => {}, false, 'copy-parquet');
    assertLive();
    const state = await lstat(outputPath);
    if (!state.isFile() || !Number.isSafeInteger(state.dev) ||
        !Number.isSafeInteger(state.ino) || !Number.isSafeInteger(state.size) ||
        state.size < 0) throw new DuckDBTransportError('InvalidNativeOutput');
    return Object.freeze({device: state.dev, inode: state.ino,
      bytes: state.size});
  };
  const copyParquet = (...args: Parameters<typeof runCopyParquet>) =>
    trackFlight(runCopyParquet(...args), recordCommandFailure);
  let result!: Awaited<Value>;
  let failure: unknown;
  let failed = false;
  const cleanupErrors: unknown[] = [];
  let cleaning = false;
  const cleanupStatus = () => Object.freeze({
    pending: activeAppender !== undefined || cachedInsert !== undefined ||
      connection !== undefined || instance !== undefined,
    errors: Object.freeze([...cleanupErrors]),
  });
  const cleanOwnedResources = async () => {
    if (cleaning) throw new DuckDBTransportError('CleanupInProgress');
    cleaning = true;
    const cleanupStarted = performance.now();
    try {
      try { activeAppender?.closeSync(); activeAppender = undefined; }
      catch (error) { cleanupErrors.push(error); }
      try { destroyCachedInsert(); }
      catch (error) { cleanupErrors.push(error); }
      try {
        if (transaction && connection) await connection.run('ROLLBACK');
        transaction = false;
      } catch (error) { cleanupErrors.push(error); }
      try {
        if (!activeAppender && !cachedInsert) {
          connection?.closeSync();
          connection = undefined;
          transaction = false; // closing the owned connection ends its transaction
        }
      } catch (error) { cleanupErrors.push(error); }
      // Retain the instance while its connection still needs cleanup.
      if (!connection && !shared) {
        try { instance?.closeSync(); instance = undefined; }
        catch (error) { cleanupErrors.push(error); }
      }
      // This task borrows the DB. Its transaction/connection has settled, but
      // the environment owner continues reserving the shared instance capacity.
      if (!connection && shared) instance = undefined;
      const status = cleanupStatus();
      accounting?.settled(!status.pending);
      return status;
    } finally {
      usage.cleanupMilliseconds += performance.now() - cleanupStarted;
      cleaning = false;
    }
  };
  try {
    assertLive();
    instance = shared?.instance ?? await createInstance(path, readonly, limits, inputFiles);
    assertLive();
    connection = await instance.connect();
    assertLive();
    if (inputFiles.length) {
      // List settings are not accepted by the pinned C configuration setter.
      // Configure before exposing the private connection to any task SQL, then
      // irreversibly disable general external access for this instance.
      await connection.run(`SET allowed_paths = [${inputFiles.map(path => `'${path.replaceAll("'", "''")}'`).join(',')}]`);
      assertLive();
      await connection.run('SET enable_external_access = false');
      assertLive();
    }
    await connection.run('BEGIN TRANSACTION');
    transaction = true;
    assertLive();
    // Callback is trusted Host code. Its chunks are provisional, not a public
    // success channel. Only this function's resolution denotes clean completion.
    result = await body(Object.freeze({
      command,
      insert: (sql, parameters, consume) => command(sql, parameters, consume, true),
      openResidentAppender,
      createFileView,
      // Installed Host operation only. The output path must be one of the exact
      // paths admitted when this private session was created; callers cannot
      // choose a format, option, glob or arbitrary destination.
      copyParquet,
      usage: () => Object.freeze({ ...usage }),
    }));
    assertLive();
    if (inFlight.size !== 0) throw new DuckDBTransportError('UnawaitedCommand');
    if (commandFailed) throw commandFailure;
    if (appenderFailed) throw appenderFailure;
    if (activeAppender) throw new DuckDBTransportError('UnclosedAppender');
    if (shared) {
      // The trusted body must finish provisional-output validation before
      // returning. Only successful transactions may publish resident tables.
      await connection.run('COMMIT');
      transaction = false;
      assertLive();
    }
  } catch (error) {
    failed = true;
    failure = cancelled ? new DuckDBTransportError('Cancelled', { cause: error }) : error;
  } finally {
    active = false;
    signal?.removeEventListener('abort', onAbort);
    if (pending) connection?.interrupt();
    // Await actual native settlement before rollback/disconnect. No racing
    // cleanup or success while an ignored command is still accessing the DB.
    await Promise.allSettled([...inFlight]);
    // Source is read-only and Compute ephemeral. Roll back owned temporary
    // resources in both cases. No pool or source handle survives this attempt.
    await cleanOwnedResources();
  }
  if (cleanupErrors.length) {
    const combined = new DuckDBTransportError((failure as CleanupFailure | null | undefined)?.code ?? 'CleanupFailed', {
      cause: failed ? failure : cleanupErrors[0],
    }) as TransportFailure;
    combined.primaryFailure = failure;
    combined.cleanupErrors = Object.freeze([...cleanupErrors]);
    combined.cleanupPending = cleanupStatus().pending;
    if (combined.cleanupPending) combined.cleanupHandle = Object.freeze({
      status: cleanupStatus, retry: cleanOwnedResources,
    });
    throw combined;
  }
  if (signal?.aborted && !failed) {
    failed = true;
    failure = new DuckDBTransportError('Cancelled');
  }
  if (failed) throw failure;
  return Object.freeze({ value: result, usage: Object.freeze({ ...usage }) });
}

function createInstance(path: string, readonly: boolean, limits: Limits, inputFiles: readonly string[] = []) {
  return DuckDBInstance.create(path, {
    ...environmentContract.settings,
    access_mode: readonly ? 'READ_ONLY' : 'READ_WRITE',
    threads: String(limits.threads), memory_limit: `${limits.memoryBytes}B`,
    enable_external_access: inputFiles.length ? 'true' : 'false',
  });
}

// Trusted resource-provider operation, not candidate enumeration. The caller
// must reserve the DB capacity before calling. Each task has its own connection,
// transaction, cancellation scope, transfer budget and scratch accounting.
// No source grant or arbitrary existing instance can be attached here.
export async function provisionComputeDatabase(suppliedLimits: Limits, accounting: Settlement & {started(): void}) {
  const limits = validateLimits(suppliedLimits) as ValidatedLimits;
  accounting.started();
  let instance: DuckDBInstance | undefined;
  try {
    instance = await createInstance(':memory:', false, limits);
  } catch (error) {
    accounting.settled(true);
    throw error;
  }
  let closing = false;
  let busy = false;
  let pendingCleanup: CleanupHandle | undefined;
  const status = () => Object.freeze({
    live: instance !== undefined && !closing,
    pending: instance !== undefined,
    busy,
  });
  const close = async () => {
    closing = true;
    if (busy) {
      accounting.settled(false);
      throw new DuckDBTransportError('CleanupInProgress');
    }
    try {
      if (pendingCleanup) {
        const state = await pendingCleanup.retry();
        if (state.pending) {
          accounting.settled(false);
          return status();
        }
        pendingCleanup = undefined;
      }
      instance?.closeSync();
      instance = undefined;
      accounting.settled(true);
      return status();
    } catch (error) {
      accounting.settled(false);
      throw error;
    }
  };
  return Object.freeze({
    status,
    close,
    memoryBytes: limits.memoryBytes,
    threads: limits.threads,
    async run<Value>(taskLimits: Limits, body: SessionBody<Value>, signal?: AbortSignal, taskAccounting?: Accounting) {
      taskLimits = validateLimits(taskLimits);
      if (!instance || closing || pendingCleanup) throw new DuckDBTransportError('SessionClosed');
      if (busy) throw new DuckDBTransportError('ConcurrentCommand');
      if (taskLimits.memoryBytes !== limits.memoryBytes || taskLimits.threads !== limits.threads) {
        throw new DuckDBTransportError('EnvironmentMismatch');
      }
      busy = true;
      // busy tracks actual native settlement, not the cancellation deadline.
      return cancellationBoundary(async fixedLimits => {
        try {
          return await usingSession(':memory:', false, fixedLimits, body, signal,
            taskAccounting, { instance } as SharedDatabase);
        } catch (error) {
          if ((error as CleanupFailure | null | undefined)?.cleanupPending) {
            pendingCleanup = (error as CleanupFailure).cleanupHandle;
            closing = true;
          }
          throw error;
        } finally {
          busy = false;
        }
      }, taskLimits, signal, taskAccounting);
    },
  });
}

export async function withSourceDatabase<Value>(grant: object, limits: Limits, body: SessionBody<Value>,
  signal?: AbortSignal, accounting?: Accounting) {
  const source = files.get(grant);
  if (!source) throw new DuckDBTransportError('UnauthorizedSource');
  await authorizeSourceAccess(source, signal);
  return cancellationBoundary(fixedLimits => usingSession(source.path, true, fixedLimits, body, signal, accounting), limits, signal, accounting);
}

export async function withComputeDatabase<Value>(limits: Limits, body: SessionBody<Value>, signal?: AbortSignal,
  accounting?: Accounting, suppliedFiles: readonly string[] = []) {
  // Trusted transport wiring, never a Program path. Freeze before any await;
  // admit exact files only, not directories, globs, URLs or external access.
  if (!Array.isArray(suppliedFiles) || suppliedFiles.length > 2 || suppliedFiles.some(path =>
    typeof path !== 'string' || !isAbsolute(path) || /[\u0000*?\[\]]/.test(path) ||
    Buffer.byteLength(path, 'utf8') > limits.maxSqlBytes!)) throw new DuckDBTransportError('InvalidInputFileGrant');
  const inputFiles = Object.freeze([...new Set(suppliedFiles)]);
  return cancellationBoundary(fixedLimits => usingSession(':memory:', false, fixedLimits, body, signal, accounting,
    undefined, inputFiles), limits, signal, accounting);
}

// Explicit Host revocation affects both future reads and evidence issuance.
// It does not report a currently executing native operation as stopped.
export function revokeLocalDatabase(grant: object) {
  return files.delete(grant);
}

// Issuance uses the same opaque file grant and exact configured logical source
// as acquisition. Recheck after the async authority decision to cover revocation
// while delegate policy is answering. The body runs synchronously after admission.
export async function withCurrentSourceEvidenceRead<Value>(grant: object, sourceRef: string, body: () => Value,
  signal?: AbortSignal) {
  const source = files.get(grant);
  if (!source || source.sourceRef !== sourceRef) {
    throw new DuckDBTransportError('UnauthorizedSourceEvidence');
  }
  await authorizeSourceAccess(source, signal);
  if (files.get(grant) !== source) {
    throw new DuckDBTransportError('RevokedSourceEvidenceGrant');
  }
  return body();
}
