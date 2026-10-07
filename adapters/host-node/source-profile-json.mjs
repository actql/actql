// Bound installed Source configuration and identity metadata before buffering.
// This does not make separate identity and installation reads one snapshot.
import {open} from 'node:fs/promises';

const profileByteLimit = 8 * 1024 * 1024;
const chunkBytes = 64 * 1024;

export async function readSourceProfileJson(path,
  {maxBytes = profileByteLimit, openFile = open} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0 ||
      maxBytes > profileByteLimit) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  const file = await openFile(path, 'r');
  let failure;
  try {
    const chunks = [];
    let bytes = 0;
    let used = 0;
    let buffer = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes + 1));
    for (;;) {
      // One lookahead byte distinguishes exact-limit EOF from an oversized
      // file, including one that grows after it is opened. Never readFile.
      const {bytesRead} = await file.read(buffer, used,
        buffer.length - used, null);
      if (bytesRead === 0) {
        chunks.push(buffer.subarray(0, used));
        return JSON.parse(Buffer.concat(chunks, bytes).toString('utf8'));
      }
      bytes += bytesRead;
      used += bytesRead;
      if (bytes > maxBytes) {
        throw new TypeError('InvalidInstalledSourceProfile');
      }
      if (used === buffer.length) {
        chunks.push(buffer);
        buffer = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes - bytes + 1));
        used = 0;
      }
    }
  } catch (cause) {
    failure = cause;
    throw cause;
  } finally {
    try { await file.close(); }
    catch (cause) {
      if (failure === undefined) throw cause;
      throw new AggregateError([failure, cause], failure.message,
        {cause: failure});
    }
  }
}
