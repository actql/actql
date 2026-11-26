import {checked} from '../../../host-common/runtime-result.mjs';

function fail(code: string, cause?: unknown): never {
  throw Object.assign(new Error(code, {cause}), {code});
}

type CsvLimits = Readonly<{maxPathBytes: number; maxDepth: number; maxFileBytes: number;
  maxPageBytes: number; maxFiles: number; maxPageRows: number}>;
export type LocalCsvRelationView = Readonly<{resource: string; resource_kind: 'record';
  schema_wire: string; schema_cid: string; facts_wire: string}>;
type CsvTableProjection = Readonly<{path: string; column_names: string[];
  integer_columns: boolean[]; key: string[]; view: LocalCsvRelationView}>;
type LocalFileProjection = Readonly<{root: string; content_version: boolean; csv_tables: CsvTableProjection[]}>;

function prepareLocalCsvTransport(table: CsvTableProjection, limits: CsvLimits) {
  // Initially one complete page. Both the raw file and its typed projection
  // must fit the existing Source page ceiling. Hold the raw response and its
  // native read block, decoded cells, key index, JSON text and RowRun wire at
  // the same time. Bound key index growth by the same row and input limits.
  const maxBytes = Math.min(limits.maxFileBytes, limits.maxPageBytes);
  const maxRows = Math.min(limits.maxFiles, limits.maxPageRows);
  const transport = Object.freeze({transferBytes: BigInt(maxBytes),
    executionBytes: 65536n + 32n * BigInt(maxBytes) + 8n * BigInt(limits.maxPageBytes) +
      256n * BigInt(maxRows) + 256n * BigInt(table.column_names.length)});
  return Object.freeze({resource: table.view.resource, path: table.path,
    columnNames: Object.freeze(table.column_names), integerColumns: Object.freeze(table.integer_columns),
    key: Object.freeze(table.key), view: Object.freeze(table.view),
    maxBytes, maxRows, maxFieldBytes: maxBytes, transport});
}
export type PreparedLocalCsvTable = ReturnType<typeof prepareLocalCsvTransport>;

export type LocalCsvProjectRuntime = Readonly<{
  clientProjectConnectionsLocalFileEntry(connections: unknown, index: number,
    maxPathBytes: number, maxDepth: number): unknown;
}>;

export function prepareLocalCsvProjectEntry(moon: Partial<LocalCsvProjectRuntime>, connections: unknown,
  index: number, limits: CsvLimits) {
  if (typeof moon.clientProjectConnectionsLocalFileEntry !== 'function') fail('LocalCsvRuntimeUnavailable');
  let wire: unknown;
  try {
    wire = checked(moon.clientProjectConnectionsLocalFileEntry(
      connections, index, limits.maxPathBytes, limits.maxDepth));
  } catch (cause) {
    if (cause instanceof Error && (cause as Error & {code?: string}).code === 'MoonBitHostFailure' &&
        typeof cause.cause === 'string') fail(cause.cause, cause);
    throw cause;
  }
  if (typeof wire !== 'string') fail('InvalidLocalFilesConnection');
  const entry = JSON.parse(wire) as LocalFileProjection;
  return Object.freeze({root: entry.root, contentVersion: entry.content_version,
    tables: Object.freeze(entry.csv_tables.map(table => prepareLocalCsvTransport(table, limits)))});
}

export type LocalCsvRuntime = Readonly<{
  clientProgramLocalCsvPage(bytes: Uint8Array, names: readonly string[], integerColumns: readonly boolean[],
    keys: readonly string[], maxBytes: number, maxFieldBytes: number, maxRows: number, maxPageBytes: number): unknown;
}>;

export function encodeLocalCsvPage(moon: LocalCsvRuntime, bytes: Buffer, table: PreparedLocalCsvTable, maxPageBytes: number) {
  if (!Buffer.isBuffer(bytes) || ![table.maxBytes, table.maxRows, table.maxFieldBytes].every(value =>
    Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) fail('InvalidLocalCsvLimits');
  if (typeof moon.clientProgramLocalCsvPage !== 'function') fail('LocalCsvRuntimeUnavailable');
  let page;
  try {
    page = checked(moon.clientProgramLocalCsvPage(bytes, table.columnNames, table.integerColumns,
      table.key, table.maxBytes, table.maxFieldBytes, table.maxRows, maxPageBytes));
  } catch (cause) {
    if (cause instanceof Error && (cause as Error & {code?: string}).code === 'MoonBitHostFailure' &&
        typeof cause.cause === 'string') fail(cause.cause, cause);
    throw cause;
  }
  if (typeof page !== 'string') fail('InvalidLocalCsvPage');
  return page;
}
