import { join } from 'node:path';
import { isMainThread, parentPort, workerData } from 'node:worker_threads';
import { unionCapacityParts } from './parts.mjs';
import { validate } from './audit.mjs';
import { readCapacityRegressionText } from './regression-fixtures.mjs';
import { pipelineEvidenceReader } from '../evidence-reader.mjs';
import { hash } from '../inventory.mjs';

export function capacityRegressionReader(root, overrides) {
  const { read: original } = pipelineEvidenceReader(join(root, '.artifacts/relation-pipeline'), root);
  const read = path => overrides.get(path) ?? original(path);
  // An independent mutation/virtual original is always fully read and hashed.
  Object.defineProperty(read, 'artifactDigest', { value: path => overrides.has(path)
    ? hash(read(path)) : original.artifactDigest(path) });
  Object.defineProperty(read, 'artifactDigestWork', { value: original.artifactDigestWork });
  return read;
}

export function auditCapacityRegressionCase({ root, parts, current }) {
  const timings = {};
  try {
    let started = performance.now();
    const overrides = new Map(parts.map(({ path, archive }) => [path, readCapacityRegressionText(archive)]));
    const originals = parts.map(({ path }) => ({ path, report: JSON.parse(overrides.get(path)) }));
    timings.loadPartsMs = performance.now() - started;
    const read = capacityRegressionReader(root, overrides);
    started = performance.now();
    const union = unionCapacityParts(originals, read);
    timings.unionMs = performance.now() - started;
    started = performance.now();
    try { validate(union, current, ['js', 'wasm', 'native'], read); }
    finally {
      timings.validateMs = performance.now() - started;
      timings.artifactDigests = read.artifactDigestWork();
    }
    return { status: 0, stdout: '', stderr: '', timings };
  } catch (error) {
    return { status: 1, stdout: '', stderr: error.stack, timings };
  }
}

if (!isMainThread) {
  parentPort.postMessage({ slot: workerData.slot, result: auditCapacityRegressionCase(workerData) });
}
