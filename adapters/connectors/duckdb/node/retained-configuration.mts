import { DuckDBTransportError } from './configuration.mjs';
import {processStoreContext} from '../../../store-local/process-binding.mjs';

import type {ProcessStoreBinding} from '../../../store-local/process-binding.mjs';

type RetainedConfiguration = Readonly<{parentDirectory: string; maxFrameBytes: number;
  wire: Readonly<Record<string, number>>}>;
type UncheckedConfiguration = {parentDirectory?: unknown; maxFrameBytes?: number;
  wire?: Readonly<Record<string, number | undefined>>};

const prepared = new WeakSet<object>();
const processStores = new WeakMap<object, ProcessStoreBinding>();

// Pure operator configuration: never accepts a Store, runtime or verifier.
export function retainedConfiguration(input: unknown): RetainedConfiguration {
  if (prepared.has(input as object)) return input as RetainedConfiguration;
  const keys = ['max_bytes', 'max_nodes', 'max_depth', 'max_columns', 'max_order_work'];
  const wire = Object.fromEntries(keys.map(key => [key, (input as UncheckedConfiguration | null | undefined)?.wire?.[key]]));
  const parentDirectory = (input as UncheckedConfiguration | null | undefined)?.parentDirectory;
  const maxFrameBytes = (input as UncheckedConfiguration | null | undefined)?.maxFrameBytes;
  if (typeof parentDirectory !== 'string' || !parentDirectory.length ||
      !Number.isSafeInteger(maxFrameBytes) || maxFrameBytes! < 1 || maxFrameBytes! > 16 * 1024 * 1024 ||
      Object.values(wire).some(value => !Number.isSafeInteger(value) || value! < 0 || value! > 2147483647)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  const result = Object.freeze({ parentDirectory, maxFrameBytes, wire: Object.freeze(wire) });
  prepared.add(result);
  return result as RetainedConfiguration;
}

// Installed execution-process wiring, separate from plain operator settings.
// The binding cannot be supplied through copied JSON or a caller Store factory.
export function bindRetainedProcessStore(input: unknown, binding: unknown) {
  processStoreContext(binding);
  const result = Object.freeze({...retainedConfiguration(input)});
  prepared.add(result);
  processStores.set(result, binding as ProcessStoreBinding);
  return result as RetainedConfiguration;
}

export function retainedProcessStore(input: unknown): ProcessStoreBinding | undefined { return processStores.get(input as object); }
