import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { closeSync, createWriteStream, fstatSync, lstatSync, openSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createGzip } from 'node:zlib';

// Retain every substituted field and byte without accumulating a full plain
// report per negative. Only the ordinary CLI needs a temporary plain file;
// in-process union negatives still validate their independent complete views.
export async function retainCapacityRegressionFixture(path, report) {
  const serialized = JSON.stringify(report) + '\n';
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
