import {setImmediate as yieldToHost} from 'node:timers/promises';
import {runtimeField, runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {createMoonBitRetainedRowFrames} from '../../../store-local/moonbit-row-frames.mjs';
import {retainedStorageBody, retainedStorageContract} from '../../../store-local/representations.mjs';
import {DuckDBTransportError, provisionComputeDatabase, validateLimits} from './session.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';
import {boundedTransport} from './transport-bounds.mjs';
import {createImportBatch} from './import-batch.mjs';
import {checked} from './runtime-result.mjs';

import type {MoonBitRetainedFrameBindings} from '../../../store-local/moonbit-row-frames.mjs';
import type {PhysicalParameter} from './physical-values.mjs';
import type {retainedConfiguration} from './retained-configuration.mjs';

type Limits = Parameters<typeof validateLimits>[0];
type Database = Awaited<ReturnType<typeof provisionComputeDatabase>>;
type MappingLimits = Readonly<{maxEntries: number; maxNameBytes: number}>;
type RetainedReceipt = Readonly<{cid: string; bytes: number}>;
type RetainedBody = ReturnType<typeof retainedStorageBody> & RetainedReceipt;
type RetainedContract = Pick<ReturnType<typeof retainedConfiguration>, 'wire' | 'maxFrameBytes'>;
type CleanupFailure = Error & {
  cleanupPending?: boolean;
  cleanupErrors?: readonly unknown[];
  cleanupHandle?: {status(): {pending: boolean}; retry(): unknown};
};
export type OwnedResidentEnvironment = Readonly<{graph: unknown; env: unknown; database: Database; limits: Limits}>;

export type ResidentRuntime = MoonBitRetainedFrameBindings & Readonly<{
  residentBegin(graph: unknown, task: number, bytes: bigint): unknown;
  residentClose(graph: unknown, environment: unknown, confirmed: boolean): unknown;
  residentConfirm(graph: unknown, environment: unknown, bytes: bigint): unknown;
  residentTableAt(graph: unknown, environment: unknown, producer: number): unknown;
  residentHasTable(graph: unknown, environment: unknown, producer: number): boolean;
  residentTablePrepare(graph: unknown, environment: unknown, producer: number,
    bytes: bigint, entries: number, names: number, sql: number): unknown;
  residentTableCancel(graph: unknown, table: unknown): unknown;
  residentImportBatch(table: unknown, rows: number, maxParameters: number, maxSqlBytes: number): unknown;
  residentImportCount(table: unknown, columns: boolean): unknown;
  residentTransferBegin(graph: unknown, table: unknown, transferBytes: bigint, scratchBytes: bigint): unknown;
  residentImportSql(table: unknown, insert: boolean): unknown;
  residentImportMaterial(table: unknown): unknown;
  residentImportScalarNames(table: unknown): unknown;
  residentImportCanonicalCopyMatches(table: unknown, cid: string, bytes: number, rows: number): boolean;
  residentImportTableName(table: unknown): unknown;
  residentImportStreamBegin(table: unknown, rows: number,
    values: Readonly<{max_nodes: number; max_text_bytes: number; max_work: number}>,
    wire: RetainedContract['wire'], maxFrameBytes: number): unknown;
  residentImportStreamAppend(stream: unknown, row: string,
    limits: Readonly<{max_bytes: number; max_nodes: number; max_depth: number; max_text_bytes: number}>): unknown;
  residentImportStreamFinish(stream: unknown): unknown;
  residentImportStreamCancel(stream: unknown): void;
  residentImportParameter(table: unknown, row: number, column: number, bytes: number, nodes: number): unknown;
  residentTransferCharge(graph: unknown, transfer: unknown, bytes: bigint): unknown;
  residentTransferSettle(graph: unknown, transfer: unknown, confirmed: boolean): unknown;
  residentTransferComplete(graph: unknown, transfer: unknown): unknown;
  residentTransferAbort(graph: unknown, transfer: unknown): unknown;
}>;

export function residentStrategyEnvironment(
  loadRuntime: () => Promise<ResidentRuntime>, residentEnvironments: WeakMap<object, OwnedResidentEnvironment>,
  rows: (value: unknown) => number,
) {
  // Supply a run-owned local environment only after MoonBit has reserved the
  // selected capacity. No existing file or source connection can be attached.
  async function openResidentStrategyEnvironment(graph: unknown, task: number, limits: Limits) {
    const moon = await loadRuntime();
    limits = validateLimits(limits);
    const capacity = computePhysicalCapacity(limits);
    const env = checked(moon.residentBegin(graph, task, capacity.databaseBytes));
    let database: Database | undefined;
    let started = false;
    let released = false;
    const cleanupStatus = () => Object.freeze({ pending: !released });
    const cleanup = async () => {
      if (!released) {
        checked(moon.residentClose(graph, env, false));
        if (database) await database.close();
        else if (!started) {
          // No provider work was sent. An absent returned handle alone is not
          // sufficient: started-but-unknown provision must keep its reservation.
          checked(moon.residentClose(graph, env, true));
          released = true;
        }
      }
      return cleanupStatus();
    };
    const cleanupHandle = Object.freeze({ status: cleanupStatus, retry: cleanup });
    try {
      database = await provisionComputeDatabase(limits, Object.freeze({
        started() { started = true; },
        settled(confirmed: boolean) {
          if (released) return;
          checked(moon.residentClose(graph, env, confirmed));
          if (confirmed) released = true;
        },
      }));
      checked(moon.residentConfirm(graph, env, BigInt(database.memoryBytes)));
    } catch (error) {
      try { await cleanup(); }
      catch (cleanupError) { (error as CleanupFailure).cleanupErrors = Object.freeze([cleanupError]); }
      if (!released) {
        (error as CleanupFailure).cleanupPending = true;
        (error as CleanupFailure).cleanupHandle = cleanupHandle;
      }
      throw error;
    }
    const handle = Object.freeze({
      status: () => Object.freeze({ ...database!.status(), pending: !released }),
      table(producer: number) { return checked(moon.residentTableAt(graph, env, producer)); },
      hasTable(producer: number) { return moon.residentHasTable(graph, env, producer); },
      async close() {
        if (released) return;
        try {
          await cleanup();
          if (!released) throw new DuckDBTransportError('CleanupInProgress');
        } catch (error) {
          (error as CleanupFailure).cleanupPending = !released;
          if (!released) (error as CleanupFailure).cleanupHandle = cleanupHandle;
          throw error;
        }
        residentEnvironments.delete(handle);
      },
    });
    residentEnvironments.set(handle, { graph, env, database, limits });
    return handle;
  }

  async function importResidentStrategyInput(environment: object, producer: number, tableBytes: bigint | number,
    limits: Limits, mappingLimits: MappingLimits, signal?: AbortSignal) {
    const owned = residentEnvironments.get(environment);
    if (!owned || !owned.database.status().live) throw new DuckDBTransportError('SessionClosed');
    const moon = await loadRuntime();
    limits = validateLimits(limits);
    if (limits.memoryBytes !== owned.database.memoryBytes || limits.threads !== owned.database.threads) {
      throw new DuckDBTransportError('EnvironmentMismatch');
    }
    const capacity = computePhysicalCapacity(limits);
    const table = checked(moon.residentTablePrepare(owned.graph, owned.env, producer,
      BigInt(tableBytes), mappingLimits.maxEntries, mappingLimits.maxNameBytes, limits.maxSqlBytes!));
    let count, columns, transfer, batchRows = 1;
    const compileBatch = (requested: number) => {
      let compilerTuple1 = checked(moon.residentImportBatch(table, requested,
        limits.maxParameters!, limits.maxSqlBytes!));
      const rows = runtimeField(compilerTuple1, 0) as number,
        sql = runtimeField(compilerTuple1, 1) as string;
      compilerTuple1 = undefined;
      return {rows, sql};
    };
    try {
      count = rows(checked(moon.residentImportCount(table, false)));
      columns = rows(checked(moon.residentImportCount(table, true)));
      if (count > limits.maxRows! || columns > limits.maxColumns! || columns > limits.maxParameters! ||
          columns === 0 || count > Math.floor(limits.maxCells! / columns)) {
        throw new DuckDBTransportError('InvalidImportLimits');
      }
      if (boundedTransport(limits) && count > 1) {
        batchRows = compileBatch(Math.min(count, limits.maxChunkRows,
          Math.floor(limits.maxParameters! / columns))).rows;
      }
      transfer = checked(moon.residentTransferBegin(owned.graph, table,
        capacity.transferBytes, capacity.scratchBytes));
    } catch (error) {
      // Synchronous preparation only: no import attempt or native work exists.
      checked(moon.residentTableCancel(owned.graph, table));
      throw error;
    }
    let started = false;
    let storageReadBytes = 0, storageReadUnconfirmed = false;
    let nativeScalarStaging = false;
    try {
      const result = await owned.database.run(limits, async session => {
        const discard = () => {};
        await session.command(checked(moon.residentImportSql(table, false)) as string, [], discard);
        const sql = checked(moon.residentImportSql(table, true)) as string;
        const material = checked(moon.residentImportMaterial(table)) as object | undefined;
        const body = material == null ? undefined : retainedStorageBody(material) as RetainedBody;
        const scalarNames = material != null && boundedTransport(limits) && limits.threads === 1
          ? runtimeOptionalField(moon.residentImportScalarNames(table), 0) as readonly string[] | undefined : undefined;
        const scalarStaging = scalarNames?.length === columns &&
          moon.residentImportCanonicalCopyMatches(table, body!.cid, body!.bytes, count);
        nativeScalarStaging = scalarStaging;
        const appender = material != null && limits.threads === 1
          ? await session.openResidentAppender(checked(moon.residentImportTableName(table)) as string, columns)
          : undefined;
        const batch = !appender && batchRows > 1 ? createImportBatch(columns, batchRows, limits as Parameters<typeof createImportBatch>[2],
          compileBatch, (sql, parameters) => session.insert(sql, parameters, discard), signal) : undefined;
        let appendedSinceFlush = 0;
        const append = (parameters: readonly PhysicalParameter[]) => {
          if (!appender) return batch ? batch.append(parameters) : session.insert(sql, parameters, discard);
          appender.append(parameters);
          if (++appendedSinceFlush === (limits.maxChunkRows ?? 128)) {
            appender.flush();
            appendedSinceFlush = 0;
            return yieldToHost().then(() => signal?.throwIfAborted());
          }
        };
        if (material != null) {
          const {wire, maxFrameBytes} = retainedStorageContract(material) as RetainedContract;
          if (maxFrameBytes > (limits.maxChunkBytes ?? limits.maxTransportBytes!)) {
            throw new DuckDBTransportError('RetainedFrameLimit');
          }
          const decode = {max_bytes: maxFrameBytes,
            max_nodes: Math.min(wire.max_nodes, maxFrameBytes),
            max_depth: Math.min(64, wire.max_depth), max_text_bytes: maxFrameBytes};
          const stream = scalarStaging ? undefined : checked(moon.residentImportStreamBegin(table, count,
            {max_nodes: wire.max_nodes, max_text_bytes: wire.max_bytes, max_work: wire.max_order_work},
            wire, maxFrameBytes));
          const scalarTypes = scalarStaging && appender?.types;
          if (scalarStaging && (!scalarTypes || scalarTypes.length !== columns ||
              scalarTypes.some(type => !['DOUBLE', 'BOOLEAN', 'VARCHAR'].includes(type.id)))) {
            throw new DuckDBTransportError('InvalidScalarImportType');
          }
          const frameLimits = {maxBytes: wire.max_bytes, maxRows: count,
            maxRowBytes: maxFrameBytes, maxFrameBytes, maxDepth: decode.max_depth};
          // Scalar staging takes every row framed from one bounded Store chunk at
          // once: one standard JSON parse of those exact row texts, then one flush
          // and cancellation point per chunk. The appender's own row/byte batch
          // bound still limits buffered data; the typed copy check below and the
          // MoonBit receipt comparison remain the acceptance boundary.
          const frames = scalarStaging
            ? createMoonBitRetainedRowFrames(moon, frameLimits, rowTexts => {
              const sources = JSON.parse(`[${rowTexts.join(',')}]`);
              if (sources.length !== rowTexts.length) {
                throw new DuckDBTransportError('InvalidScalarImportRow');
              }
              for (const source of sources) {
                if (source === null || Array.isArray(source) || typeof source !== 'object' ||
                    Object.keys(source).length !== columns) {
                  throw new DuckDBTransportError('InvalidScalarImportRow');
                }
                appender!.appendScalars(scalarNames!.map(name => {
                  if (!Object.hasOwn(source, name)) {
                    throw new DuckDBTransportError('InvalidScalarImportRow');
                  }
                  return source[name];
                }));
              }
              appender!.flush();
              return yieldToHost().then(() => signal?.throwIfAborted());
            }, {batch: true})
            : createMoonBitRetainedRowFrames(moon, frameLimits, row => {
              const parameters = JSON.parse(checked(moon.residentImportStreamAppend(stream, row, decode)) as string);
              return append(parameters);
            });
          try {
            storageReadUnconfirmed = true;
            const verified = await body!.consume(async chunk => {
              checked(moon.residentTransferCharge(owned.graph, transfer, BigInt(chunk.byteLength)));
              storageReadBytes += chunk.byteLength;
              await frames.feed(chunk, signal);
            }, signal) as RetainedReceipt | undefined;
            storageReadUnconfirmed = false;
            const framed = frames.finish();
            signal?.throwIfAborted();
            await batch?.finish();
            appender?.finish();
            if (scalarStaging) {
              if ((verified !== undefined &&
                    (verified.cid !== body!.cid || verified.bytes !== body!.bytes)) ||
                  framed.bytes !== body!.bytes || storageReadBytes !== body!.bytes ||
                  !moon.residentImportCanonicalCopyMatches(table,
                    body!.cid, body!.bytes, framed.rows)) {
                throw new DuckDBTransportError('RetainedCopyMismatch');
              }
            } else checked(moon.residentImportStreamFinish(stream));
          } finally {
            frames.cancel();
            if (stream) moon.residentImportStreamCancel(stream);
          }
          return;
        }
        for (let row = 0; row < count; row++) {
          signal?.throwIfAborted();
          const parameters: PhysicalParameter[] = [];
          for (let column = 0; column < columns; column++) {
            parameters.push(JSON.parse(checked(moon.residentImportParameter(table, row, column,
              limits.maxTransportBytes!, mappingLimits.maxEntries)) as string));
          }
          // The shared environment outlives this import, but the reusable INSERT
          // belongs only to its task connection and is explicitly destroyed at
          // settlement. Reuse does not bypass per-row transfer/parameter checks.
          await append(parameters);
        }
        await batch?.finish();
      }, signal, Object.freeze({
        started() { started = true; },
        chargeTransfer(bytes: number) { checked(moon.residentTransferCharge(owned.graph, transfer, BigInt(bytes))); },
        settled(confirmed: boolean) {
          checked(moon.residentTransferSettle(owned.graph, transfer, confirmed && !storageReadUnconfirmed));
        },
      }));
      checked(moon.residentTransferComplete(owned.graph, transfer));
      return Object.freeze({ table, importedRows: count, importedCells: count * columns, batchRows,
        nativeScalarStaging,
        usage: Object.freeze({...result.usage, storageReadBytes,
          transportBytes: result.usage.transportBytes + storageReadBytes}) });
    } catch (error) {
      checked(moon.residentTransferAbort(owned.graph, transfer));
      if (!started) checked(moon.residentTransferSettle(owned.graph, transfer, true));
      if (storageReadUnconfirmed) {
        const failure = new DuckDBTransportError('ResidentStorageReadUnconfirmed', {cause: error}) as CleanupFailure;
        failure.cleanupPending = true;
        // No file-close acknowledgement is available after a failed Store read.
        // Do not retry the import or claim that closing the DB closed this file.
        failure.cleanupHandle = Object.freeze({
          status: () => ({pending: true}),
          async retry() { await (error as CleanupFailure | undefined)?.cleanupHandle?.retry(); return {pending: true}; },
        });
        throw failure;
      }
      throw error;
    }
  }

  return {openResidentStrategyEnvironment, importResidentStrategyInput};
}
