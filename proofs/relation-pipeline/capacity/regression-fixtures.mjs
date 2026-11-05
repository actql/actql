import assert from 'node:assert/strict';
import { closeSync, fstatSync, lstatSync, openSync, unlinkSync, writeFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

// Retain every substituted field and byte without accumulating a full plain
// report per negative. Only the ordinary CLI needs a temporary plain file;
// in-process union negatives still validate their independent complete views.
export function retainCapacityRegressionFixture(path, report) {
  const bytes = Buffer.from(JSON.stringify(report) + '\n');
  const compressed = gzipSync(bytes);
  const archivePath = `${path}.gz`;
  writeFileSync(archivePath, compressed, { flag: 'wx' });
  return Object.freeze({
    archivePath, bytes: bytes.length, compressedBytes: compressed.length,
    withUncompressed(consume) {
      const fd = openSync(path, 'wx', 0o600);
      const original = fstatSync(fd);
      try {
        try { writeFileSync(fd, bytes); }
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
