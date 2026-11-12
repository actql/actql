import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isMainThread, parentPort, workerData } from 'node:worker_threads';
import { unionCapacityParts } from './parts.mjs';
import { validate } from './audit.mjs';
import { readCapacityRegressionText } from './regression-fixtures.mjs';

export function auditCapacityRegressionCase({ root, parts, current }) {
  const timings = {};
  try {
    let started = performance.now();
    const overrides = new Map(parts.map(({ path, archive }) => [path, readCapacityRegressionText(archive)]));
    const originals = parts.map(({ path }) => ({ path, report: JSON.parse(overrides.get(path)) }));
    timings.loadPartsMs = performance.now() - started;
    const read = path => overrides.get(path) ?? readFileSync(join(root, path));
    started = performance.now();
    const union = unionCapacityParts(originals, read);
    timings.unionMs = performance.now() - started;
    started = performance.now();
    try { validate(union, current, ['js', 'wasm', 'native'], read); }
    finally { timings.validateMs = performance.now() - started; }
    return { status: 0, stdout: '', stderr: '', timings };
  } catch (error) {
    return { status: 1, stdout: '', stderr: error.stack, timings };
  }
}

if (!isMainThread) {
  parentPort.postMessage({ slot: workerData.slot, result: auditCapacityRegressionCase(workerData) });
}
