import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { closeSync, createWriteStream, fstatSync, lstatSync, openSync, readFileSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createGzip, gunzipSync } from 'node:zlib';
import { maxCapacityReportBytes } from '../ci-artifacts.mjs';

// Retain every substituted field and byte without accumulating a full plain
// report per negative. Only the ordinary CLI needs a temporary plain file;
// union negatives still validate their independent complete views.
export async function retainCapacityRegressionFixture(path, report) {
  return retainCapacityRegressionText(path, JSON.stringify(report) + '\n');
}

// Producer overrides retain their original pretty JSON wire, including the
// final newline, because the union hashes those actual independent bytes.
export async function retainCapacityRegressionText(path, serialized) {
  const archivePath = `${path}.gz`;
  const hash = createHash('sha256');
  // Bound encoding/compression chunks instead of adding another whole-report
  // UTF-8 Buffer and compressed Buffer beside the already serialized report.
  function* chunks() {
    for (let start = 0; start < serialized.length;) {
      let end = Math.min(start + 65536, serialized.length);
      const last = serialized.charCodeAt(end - 1);
      if (end < serialized.length && last >= 0xD800 && last <= 0xDBFF) end--;
      const chunk = serialized.slice(start, end);
      hash.update(chunk);
      yield chunk;
      start = end;
    }
  }
  await pipeline(Readable.from(chunks(), { objectMode: false }), createGzip(),
    createWriteStream(archivePath, { flags: 'wx' }));
  return Object.freeze({
    archivePath, sha256: hash.digest('hex'), bytes: Buffer.byteLength(serialized),
    compressedBytes: statSync(archivePath).size,
    withUncompressed(consume) {
      const fd = openSync(path, 'wx', 0o600);
      const original = fstatSync(fd);
      try {
        try { writeFileSync(fd, serialized); }
        finally { closeSync(fd); }
        return consume(path);
      } finally {
        const current = lstatSync(path);
        assert(current.isFile() && current.dev === original.dev && current.ino === original.ino,
          'Capacity regression temporary fixture changed ownership');
        unlinkSync(path);
      }
    },
  });
}

// Retain only this DATA between preparation and validation. In particular, do
// not retain withUncompressed's closure over an entire serialized report.
export function capacityRegressionDescriptor({ archivePath, sha256, bytes, compressedBytes }) {
  return Object.freeze({ archivePath, sha256, bytes, compressedBytes });
}

export function readCapacityRegressionText(descriptor) {
  assert(Number.isSafeInteger(descriptor.bytes) && descriptor.bytes > 0 &&
    descriptor.bytes <= maxCapacityReportBytes, 'Invalid capacity regression extent');
  const compressed = readFileSync(descriptor.archivePath);
  assert.equal(compressed.length, descriptor.compressedBytes, 'Capacity regression archive extent changed');
  const bytes = gunzipSync(compressed, { maxOutputLength: descriptor.bytes });
  assert.equal(bytes.length, descriptor.bytes, 'Capacity regression fixture extent changed');
  assert.equal(createHash('sha256').update(bytes).digest('hex'), descriptor.sha256,
    'Capacity regression fixture digest changed');
  return bytes.toString('utf8');
}
