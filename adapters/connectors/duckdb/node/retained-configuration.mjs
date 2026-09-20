import { DuckDBTransportError } from './configuration.mjs';
import {processStoreContext} from '../../../store-local/process-binding.mjs';

const prepared = new WeakSet();
const processStores = new WeakMap();

// Pure operator configuration: never accepts a Store, runtime or verifier.
export function retainedConfiguration(input) {
  if (prepared.has(input)) return input;
  const keys = ['max_bytes', 'max_nodes', 'max_depth', 'max_columns', 'max_order_work'];
  const wire = Object.fromEntries(keys.map(key => [key, input?.wire?.[key]]));
  const parentDirectory = input?.parentDirectory;
  const maxFrameBytes = input?.maxFrameBytes;
  if (typeof parentDirectory !== 'string' || !parentDirectory.length ||
      !Number.isSafeInteger(maxFrameBytes) || maxFrameBytes < 1 || maxFrameBytes > 16 * 1024 * 1024 ||
      Object.values(wire).some(value => !Number.isSafeInteger(value) || value < 0 || value > 2147483647)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  const result = Object.freeze({ parentDirectory, maxFrameBytes, wire: Object.freeze(wire) });
  prepared.add(result);
  return result;
}

// Installed execution-process wiring, separate from plain operator settings.
// The binding cannot be supplied through copied JSON or a caller Store factory.
export function bindRetainedProcessStore(input, binding) {
  processStoreContext(binding);
  const result = Object.freeze({...retainedConfiguration(input)});
  prepared.add(result);
  processStores.set(result, binding);
  return result;
}

export function retainedProcessStore(input) { return processStores.get(input); }
