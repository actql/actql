import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';

function fail(code: string, cause?: unknown): never {
  throw Object.assign(new Error(code, {cause}), {code});
}

// The caller supplies a member of the admitted Project connector JSON.
// Selection of a table never infers a path or a schema from a Program.
type CsvLimits = Readonly<{maxPathBytes: number; maxDepth: number; maxFileBytes: number;
  maxPageBytes: number; maxFiles: number; maxPageRows: number}>;
type CsvDefinition = Readonly<{path?: unknown; columns?: unknown; key?: unknown}>;
export type PreparedLocalCsvTable = ReturnType<typeof prepareLocalCsvTable>;

export function prepareLocalCsvTable(resource: string, table: CsvDefinition, limits: CsvLimits) {
  const path = table?.path;
  if (typeof path !== 'string' || !path.isWellFormed() ||
    Buffer.byteLength(path) > limits.maxPathBytes) fail('InvalidLocalCsvPath');
  const components = path.split('/');
  if (components.length - 1 > limits.maxDepth || components.some(name =>
    name === '' || name === '.' || name === '..' || name.includes('\0'))) fail('InvalidLocalCsvPath');
  const selectedColumns = table.columns;
  if (selectedColumns === null || typeof selectedColumns !== 'object' || Array.isArray(selectedColumns)) fail('InvalidLocalCsvColumns');
  const columns = selectedColumns as Readonly<Record<string, unknown>>;
  const names = Object.keys(columns);
  if (names.length === 0 || names.some(name => name === '' || !name.isWellFormed() || name.includes('\0') ||
    (columns[name] !== 'int64' && columns[name] !== 'string'))) fail('InvalidLocalCsvColumns');
  const key = Object.hasOwn(table, 'key') ? table.key : [];
  if (!Array.isArray(key) || (Object.hasOwn(table, 'key') && key.length === 0) ||
    new Set(key).size !== key.length || key.some(name => typeof name !== 'string' || !Object.hasOwn(columns, name))) {
    fail('InvalidLocalCsvKey');
  }
  // Initially one complete page. Both the raw file and its typed projection
  // must fit the existing Source page ceiling. Hold the raw response and its
  // native read block, decoded cells, key index, JSON text and RowRun wire at
  // the same time. Bound key index growth by the same row and input limits.
  const maxBytes = Math.min(limits.maxFileBytes, limits.maxPageBytes);
  const maxRows = Math.min(limits.maxFiles, limits.maxPageRows);
  const transport = Object.freeze({transferBytes: BigInt(maxBytes),
    executionBytes: 65536n + 32n * BigInt(maxBytes) + 8n * BigInt(limits.maxPageBytes) +
      256n * BigInt(maxRows) + 256n * BigInt(names.length)});
  return Object.freeze({resource, path, columnTypes: Object.freeze({...columns}) as Readonly<Record<string, 'int64' | 'string'>>, key: Object.freeze([...key]),
    maxBytes, maxRows, maxFieldBytes: maxBytes, transport});
}

export type LocalCsvDeclarationRuntime = Readonly<{
  clientProgramLocalCsvRelationView(resource: string, names: readonly string[],
    integerColumns: readonly boolean[], keys: readonly string[]): unknown;
}>;
export function projectLocalCsvRelationView(moon: Partial<LocalCsvDeclarationRuntime>, table: PreparedLocalCsvTable) {
  if (typeof moon.clientProgramLocalCsvRelationView !== 'function') fail('LocalCsvRuntimeUnavailable');
  const names = Object.keys(table.columnTypes);
  const projected = checked(moon.clientProgramLocalCsvRelationView(table.resource, names,
    names.map(name => table.columnTypes[name] === 'int64'), table.key));
  const schema_wire = runtimeField(projected, 0), schema_cid = runtimeField(projected, 1),
    facts_wire = runtimeField(projected, 2);
  if (typeof schema_wire !== 'string' || typeof schema_cid !== 'string' ||
    typeof facts_wire !== 'string') fail('InvalidLocalCsvColumns');
  return {resource:table.resource, resource_kind:'record', schema_wire, schema_cid, facts_wire};
}

export type LocalCsvRuntime = Readonly<{
  clientProgramLocalCsvPage(bytes: Uint8Array, names: readonly string[], integerColumns: readonly boolean[],
    keys: readonly string[], maxBytes: number, maxFieldBytes: number, maxRows: number, maxPageBytes: number): unknown;
}>;

export function encodeLocalCsvPage(moon: LocalCsvRuntime, bytes: Buffer, table: PreparedLocalCsvTable, maxPageBytes: number) {
  if (!Buffer.isBuffer(bytes) || ![table.maxBytes, table.maxRows, table.maxFieldBytes].every(value =>
    Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) fail('InvalidLocalCsvLimits');
  if (typeof moon.clientProgramLocalCsvPage !== 'function') fail('LocalCsvRuntimeUnavailable');
  const names = Object.keys(table.columnTypes);
  let page;
  try {
    page = checked(moon.clientProgramLocalCsvPage(bytes, names, names.map(name => table.columnTypes[name] === 'int64'),
      table.key, table.maxBytes, table.maxFieldBytes, table.maxRows, maxPageBytes));
  } catch (cause) {
    if (cause instanceof Error && (cause as Error & {code?: string}).code === 'MoonBitHostFailure' &&
        typeof cause.cause === 'string') fail(cause.cause, cause);
    throw cause;
  }
  if (typeof page !== 'string') fail('InvalidLocalCsvPage');
  return page;
}
