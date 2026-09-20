// Pure, lightweight Connector configuration. Importing this module never loads
// the SDK, reads a database, or grants access to a source or runtime verifier.
import {retainedConfiguration} from './retained-configuration.mjs';
export class DuckDBTransportError extends Error {
  constructor(code, options) { super(code, options); this.name = 'DuckDBTransportError'; this.code = code; }
}

export function validateLimits(limits) {
  limits = { ...limits };
  if (limits.cancelWaitMs !== undefined &&
      (!Number.isSafeInteger(limits.cancelWaitMs) || limits.cancelWaitMs < 0 || limits.cancelWaitMs > 2147483647)) {
    throw new DuckDBTransportError('InvalidLimits');
  }
  for (const name of ['maxRows', 'maxCells', 'maxTransportBytes', 'maxSqlBytes', 'maxParameters', 'maxColumns', 'memoryBytes', 'threads']) {
    if (!Number.isSafeInteger(limits[name]) || limits[name] < (['memoryBytes', 'threads'].includes(name) ? 1 : 0)) {
      throw new DuckDBTransportError('InvalidLimits');
    }
  }
  for (const name of ['maxChunkRows', 'maxChunkBytes']) {
    if (limits[name] !== undefined && (!Number.isSafeInteger(limits[name]) || limits[name] < 1)) {
      throw new DuckDBTransportError('InvalidLimits');
    }
  }
  return Object.freeze(limits);
}

const configurations = new WeakMap();

export function prepareDuckDBStrategyConfiguration({
  transportLimits, importLimits, retainedOutput, managedOutput,
}) {
  const validated = validateLimits(transportLimits);
  const transport = Object.freeze(Object.fromEntries([
    'maxRows', 'maxCells', 'maxTransportBytes', 'maxSqlBytes', 'maxParameters',
    'maxColumns', 'memoryBytes', 'threads', 'cancelWaitMs', 'maxChunkRows', 'maxChunkBytes',
  ].map(key => [key, validated[key]])));
  const imports = Object.freeze({maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells});
  for (const value of Object.values(imports)) {
    if (!Number.isSafeInteger(value) || value < 0) throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedOutput === undefined ? undefined : retainedConfiguration(retainedOutput);
  const managed = managedOutput === undefined ? undefined : retainedConfiguration(managedOutput);
  if (retained && managed) throw new DuckDBTransportError('ConflictingOutputProfiles');
  if (retained && (retained.wire.max_bytes < 1 || retained.maxFrameBytes > transport.maxTransportBytes)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  if (managed && (managed.wire.max_bytes < 1 || managed.maxFrameBytes > transport.maxTransportBytes)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  const handle = Object.freeze({});
  configurations.set(handle, Object.freeze({
    transportLimits: transport,
    importLimits: imports,
    retainedOutput: retained,
    managedOutput: managed,
  }));
  return handle;
}

// Connector-internal interpretation, never a generic Host configuration reader.
export function preparedStrategyConfiguration(handle) {
  const configuration = configurations.get(handle);
  if (!configuration) throw new DuckDBTransportError('UnpreparedStrategyConfiguration');
  return configuration;
}
