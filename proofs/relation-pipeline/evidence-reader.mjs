import assert from 'node:assert/strict';
import { lstatSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonicalJson, fileDigest, maxCapacityReportBytes, noLinks, safePath } from './ci-artifacts.mjs';
import { hash } from './inventory.mjs';
import {capacityPartIds} from './proof-parts.mjs';
const prefix = '.artifacts/relation-pipeline/';
export function pipelineEvidenceReader(directory, sourceRoot = fileURLToPath(new URL('../../', import.meta.url))) {
  const local = path => {
    assert(path.startsWith(prefix), 'Non-local evidence reference');
    return join(directory, safePath(path.slice(prefix.length)));
  };
  const read = path => readFileSync(path.startsWith(prefix) ? local(path) : join(sourceRoot,safePath(path)));
  // Native inspection tools need the SAME verified physical input that this
  // reader opens, including before relocated parts have been joined.
  Object.defineProperty(read,'resolveArtifact',{value:local});
  const digests = new Map(), work = { requests: 0, fullHashes: 0, hashedBytes: 0, reused: 0 };
  const identity = stat => Object.fromEntries(['dev', 'ino', 'mode', 'size', 'mtimeNs', 'ctimeNs', 'nlink']
    .map(key => [key, stat[key]]));
  const fullDigest = path => {
    const bytes = read(path), digest = hash(bytes);
    work.fullHashes++; work.hashedBytes += Buffer.byteLength(bytes);
    return digest;
  };
  Object.defineProperty(read, 'artifactDigest', { value(path) {
    work.requests++;
    const file = local(path);
    // Only the original content-addressed capacity binaries use this scope.
    // Writable/virtual inputs keep their ordinary complete read/hash path.
    if (!/^\.artifacts\/relation-pipeline\/capacity\/binaries\/(js|wasm|native)\/[0-9a-f]{64}$/u.test(path)) return fullDigest(path);
    const before = lstatSync(file, { bigint: true }), prior = digests.get(path);
    if (prior) {
      noLinks(file);
      assert.deepEqual(identity(before), prior.identity, 'Immutable capacity artifact identity changed');
      work.reused++;
      return prior.digest;
    }
    if (!before.isFile() || before.nlink !== 1n || (before.mode & 0o222n) !== 0n) return fullDigest(path);
    try { noLinks(file); } catch { return fullDigest(path); }
    const digest = fileDigest(file);
    assert.deepEqual(identity(lstatSync(file, { bigint: true })), identity(before),
      'Capacity artifact identity changed while hashing');
    work.fullHashes++; work.hashedBytes += Number(before.size);
    // Keep digest/stat DATA only, never artifact bytes or a validation result.
    digests.set(path, { digest, identity: identity(before) });
    return digest;
  } });
  Object.defineProperty(read, 'artifactDigestWork', { value: () => Object.freeze({ ...work }) });
  const report = path => canonicalJson(join(directory, safePath(path)),
    capacityPartIds.some(id => path === `capacity/parts/${id}.json`) ? maxCapacityReportBytes : 32 * 1024 ** 2);
  return {local, read, report};
}
