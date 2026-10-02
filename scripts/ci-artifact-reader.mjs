// Bounded, read-only ZIP access. Nothing is extracted, imported or executed.
import {constants, createReadStream} from 'node:fs';
import {open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {createInflateRaw} from 'node:zlib';

const MiB = 1024 * 1024;
export const DEFAULT_ARTIFACT_LIMITS = Object.freeze({
  maxCompressedBytes: 512 * MiB,
  maxMemberBytes: 256 * MiB,
  maxTotalBytes: 8 * 1024 * MiB,
  maxEntries: 20_000,
  maxCompressionRatio: 2_000,
  maxJsonBytes: 160 * MiB,
});
const chunkBytes = 64 * 1024;
const utf8 = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const fail = message => { throw new Error(`Invalid artifact ZIP: ${message}`); };
const crcTable = Uint32Array.from({length: 256}, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  return value >>> 0;
});
function crcUpdate(value, data) {
  for (const byte of data) value = crcTable[(value ^ byte) & 255] ^ (value >>> 8);
  return value;
}

function boundedLimits(overrides = {}) {
  if (!overrides || typeof overrides !== 'object' || Array.isArray(overrides)) fail('invalid limits');
  const limits = {...DEFAULT_ARTIFACT_LIMITS};
  for (const [key, value] of Object.entries(overrides)) {
    if (!Object.hasOwn(limits, key) || !Number.isSafeInteger(value) || value <= 0 || value > limits[key]) {
      fail(`limit ${key} must be a positive integer no larger than its default`);
    }
    limits[key] = value;
  }
  return limits;
}

async function readAt(handle, size, position, end) {
  if (!Number.isSafeInteger(size) || !Number.isSafeInteger(position) || size < 0 ||
      position < 0 || position + size > end) fail('record extends outside its permitted range');
  const data = Buffer.allocUnsafe(size);
  for (let offset = 0; offset < size;) {
    const {bytesRead} = await handle.read(data, offset, size - offset, position + offset);
    if (!bytesRead) fail('truncated archive');
    offset += bytesRead;
  }
  return data;
}

function checkExtra(extra) {
  for (let offset = 0; offset < extra.length;) {
    if (offset + 4 > extra.length) fail('truncated extra field');
    const id = extra.readUInt16LE(offset);
    const size = extra.readUInt16LE(offset + 2);
    if (id === 0x0001) fail('ZIP64 is unsupported');
    offset += 4 + size;
    if (offset > extra.length) fail('truncated extra field payload');
  }
}

function safeName(raw, flags) {
  if (!raw.length) fail('empty member name');
  // Legacy code pages are intentionally unsupported rather than decoded ambiguously.
  if (!(flags & 0x0800) && raw.some(byte => byte >= 128)) fail('non-UTF-8 member name is unsupported');
  let name;
  try { name = utf8.decode(raw); } catch { fail('invalid UTF-8 member name'); }
  if (/^[\/]/u.test(name) || /[\\:\u0000-\u001f\u007f]/u.test(name)) fail('unsafe member path');
  const directory = name.endsWith('/');
  const parts = (directory ? name.slice(0, -1) : name).split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) fail('unsafe member path');
  // NFC aliases have one identity, including for duplicate/file-directory checks.
  return {path: parts.join('/').normalize('NFC'), directory};
}

function checkType(attributes, directory) {
  const kind = (attributes >>> 16) & 0xf000;
  if (kind !== 0 && kind !== 0x8000 && kind !== 0x4000) fail('symlink or special member is unsupported');
  if ((attributes & 8) || (directory && kind === 0x8000) ||
      (!directory && (kind === 0x4000 || (attributes & 16)))) fail('inconsistent member type');
}

function streamRange(handle, position, bytes) {
  return bytes === 0 ? Readable.from([]) : createReadStream(null, {
    fd: handle.fd, start: position, end: position + bytes - 1, autoClose: false, highWaterMark: chunkBytes,
  });
}

function fingerprint(stat) {
  return [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs].join(':');
}

async function centralEntries(handle, archiveBytes, limits) {
  const tailStart = Math.max(0, archiveBytes - 65_557);
  const tail = await readAt(handle, archiveBytes - tailStart, tailStart, archiveBytes);
  let endIndex = -1;
  for (let index = tail.length - 22; index >= 0; index--) {
    if (tail.readUInt32LE(index) === 0x06054b50 &&
        index + 22 + tail.readUInt16LE(index + 20) === tail.length) {
      endIndex = index;
      break;
    }
  }
  if (endIndex < 0) fail('missing end-of-central-directory record or trailing bytes');
  const endOffset = tailStart + endIndex;
  const end = tail.subarray(endIndex);
  const count = end.readUInt16LE(10);
  const centralSize = end.readUInt32LE(12);
  const centralOffset = end.readUInt32LE(16);
  if (count === 0xffff || centralSize === 0xffffffff || centralOffset === 0xffffffff ||
      (endIndex >= 20 && tail.readUInt32LE(endIndex - 20) === 0x07064b50)) fail('ZIP64 is unsupported');
  if (end.readUInt16LE(4) || end.readUInt16LE(6) || end.readUInt16LE(8) !== count) {
    fail('multi-disk archives are unsupported');
  }
  if (count > limits.maxEntries) fail('member count exceeds limit');
  if (centralOffset + centralSize !== endOffset) fail('invalid central-directory extent');
  const entries = [];
  const names = new Map();
  let offset = centralOffset;
  let totalBytes = 0;
  for (let index = 0; index < count; index++) {
    const header = await readAt(handle, 46, offset, endOffset);
    if (header.readUInt32LE(0) !== 0x02014b50) fail('invalid central-directory member');
    const needed = header.readUInt16LE(6);
    const flags = header.readUInt16LE(8);
    const method = header.readUInt16LE(10);
    const crc = header.readUInt32LE(16);
    const compressedBytes = header.readUInt32LE(20);
    const bytes = header.readUInt32LE(24);
    const nameBytes = header.readUInt16LE(28);
    const extraBytes = header.readUInt16LE(30);
    const commentBytes = header.readUInt16LE(32);
    const localOffset = header.readUInt32LE(42);
    if ([compressedBytes, bytes, localOffset].includes(0xffffffff) || needed >= 45) fail('ZIP64 or newer ZIP feature is unsupported');
    if (needed > 20) fail('ZIP version is unsupported');
    if (header.readUInt16LE(34)) fail('multi-disk member is unsupported');
    if (flags & 0x2041) fail('encrypted members are unsupported');
    if (flags & ~0x080e) fail('ZIP member flags are unsupported');
    if (method !== 0 && method !== 8) fail('compression method is unsupported');
    if (method === 0 && (flags & 6)) fail('invalid stored-member flags');
    if (bytes > limits.maxMemberBytes) fail('member logical bytes exceed limit');
    if (bytes > compressedBytes * limits.maxCompressionRatio) fail('member compression ratio exceeds limit');
    if (method === 0 && bytes !== compressedBytes) fail('stored-member sizes disagree');
    totalBytes += bytes;
    if (totalBytes > limits.maxTotalBytes) fail('total logical bytes exceed limit');
    const variable = await readAt(handle, nameBytes + extraBytes + commentBytes, offset + 46, endOffset);
    const rawName = Buffer.from(variable.subarray(0, nameBytes));
    const name = safeName(rawName, flags);
    checkExtra(variable.subarray(nameBytes, nameBytes + extraBytes));
    checkType(header.readUInt32LE(38), name.directory);
    if (name.directory && (bytes !== 0 || crc !== 0)) fail('directory has a payload');
    if (names.has(name.path)) fail('duplicate normalized member path');
    const entry = {...name, rawName, needed, flags, method, crc, compressedBytes, bytes, localOffset,
      modified: header.readUInt32LE(12)};
    names.set(name.path, entry);
    entries.push(entry);
    offset += 46 + variable.length;
  }
  if (offset !== endOffset) fail('central-directory member count or size disagrees');
  for (const entry of entries) {
    for (let slash = entry.path.indexOf('/'); slash >= 0; slash = entry.path.indexOf('/', slash + 1)) {
      const ancestor = names.get(entry.path.slice(0, slash));
      if (ancestor && !ancestor.directory) fail('file is an ancestor of another member');
    }
  }
  return {entries, centralOffset};
}

async function validateLocalEntries(handle, entries, centralOffset) {
  for (const entry of entries) {
    const local = await readAt(handle, 30, entry.localOffset, centralOffset);
    if (local.readUInt32LE(0) !== 0x04034b50) fail('invalid local member header');
    if (local.readUInt16LE(4) !== entry.needed || local.readUInt16LE(6) !== entry.flags ||
        local.readUInt16LE(8) !== entry.method || local.readUInt32LE(10) !== entry.modified) {
      fail('local and central member headers disagree');
    }
    const nameBytes = local.readUInt16LE(26);
    const extraBytes = local.readUInt16LE(28);
    const variable = await readAt(handle, nameBytes + extraBytes, entry.localOffset + 30, centralOffset);
    if (!variable.subarray(0, nameBytes).equals(entry.rawName)) fail('local and central member names disagree');
    checkExtra(variable.subarray(nameBytes));
    const descriptor = Boolean(entry.flags & 8);
    for (const [position, value] of [[14, entry.crc], [18, entry.compressedBytes], [22, entry.bytes]]) {
      const localValue = local.readUInt32LE(position);
      if (localValue !== value && !(descriptor && localValue === 0)) fail('local and central member sizes or CRC disagree');
    }
    entry.dataOffset = entry.localOffset + 30 + nameBytes + extraBytes;
    entry.endOffset = entry.dataOffset + entry.compressedBytes;
    if (entry.endOffset > centralOffset) fail('member payload overlaps central directory');
    if (descriptor) {
      const data = await readAt(handle, Math.min(16, centralOffset - entry.endOffset), entry.endOffset, centralOffset);
      const matches = position => data.length >= position + 12 &&
        data.readUInt32LE(position) === entry.crc &&
        data.readUInt32LE(position + 4) === entry.compressedBytes &&
        data.readUInt32LE(position + 8) === entry.bytes;
      if (data.length >= 16 && data.readUInt32LE(0) === 0x08074b50 && matches(4)) entry.endOffset += 16;
      else if (matches(0)) entry.endOffset += 12;
      else fail('missing or inconsistent data descriptor');
    }
    delete entry.rawName;
  }
  const ranges = [...entries].sort((left, right) => left.localOffset - right.localOffset);
  for (let index = 1; index < ranges.length; index++) {
    if (ranges[index].localOffset < ranges[index - 1].endOffset) fail('overlapping local members');
  }
}

/**
 * Open an immutable local ZIP without extraction. Only stored/deflated ZIP32
 * members are supported. Optional limits may tighten, never raise, defaults.
 * Opening checks structure and hashes every compressed byte. read/json/digest
 * stream and verify the selected member's length, CRC and deflate completion.
 * entries lists files only; directory records still count toward safety limits.
 * Callers must consume/digest every member used as evidence; unused payloads
 * are not inflated during open. Returned read buffers belong to the caller.
 */
export async function openArtifactZip(filename, {expectedSha256, limits: overrides} = {}) {
  const limits = boundedLimits(overrides);
  if (expectedSha256 !== undefined && (typeof expectedSha256 !== 'string' ||
      !/^(?:sha256:)?[a-f0-9]{64}$/iu.test(expectedSha256))) fail('invalid expected SHA-256');
  const expected = expectedSha256?.replace(/^sha256:/iu, '').toLowerCase();
  const handle = await open(filename, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0));
  try {
    const stat = await handle.stat({bigint: true});
    if (!stat.isFile()) fail('input is not a regular file');
    if (stat.size > BigInt(limits.maxCompressedBytes)) fail('compressed archive bytes exceed limit');
    const compressedBytes = Number(stat.size);
    if (compressedBytes < 22) fail('truncated archive');
    const original = fingerprint(stat);
    const unchanged = async () => {
      if (fingerprint(await handle.stat({bigint: true})) !== original) fail('archive changed while open');
    };
    const hash = createHash('sha256');
    let hashedBytes = 0;
    for await (const chunk of streamRange(handle, 0, compressedBytes)) {
      hashedBytes += chunk.length;
      hash.update(chunk);
    }
    if (hashedBytes !== compressedBytes) fail('compressed archive byte count changed');
    const sha256 = hash.digest('hex');
    if (expected !== undefined && expected !== sha256) fail('SHA-256 mismatch');
    const {entries: internalEntries, centralOffset} = await centralEntries(handle, compressedBytes, limits);
    await validateLocalEntries(handle, internalEntries, centralOffset);
    await unchanged();
    const files = internalEntries.filter(entry => !entry.directory);
    const byPath = new Map(files.map(entry => [entry.path, entry]));
    const entries = Object.freeze(files.map(({path, bytes, compressedBytes: size}) =>
      Object.freeze({path, bytes, compressedBytes: size})));
    let closed = false;
    let queue = Promise.resolve();
    let closePromise;

    const consume = async (entry, retain) => {
      await unchanged();
      const chunks = retain ? [] : undefined;
      const digest = retain ? undefined : createHash('sha256');
      let bytes = 0;
      let crc = 0xffffffff;
      const input = streamRange(handle, entry.dataOffset, entry.compressedBytes);
      const inflater = entry.method === 8 ? createInflateRaw({chunkSize: chunkBytes}) : undefined;
      const sink = async output => {
        for await (const chunk of output) {
          bytes += chunk.length;
          // Check before retaining anything: declarations cannot bypass the bound.
          if (bytes > entry.bytes || bytes > limits.maxMemberBytes) fail('inflated member exceeds declared size or limit');
          crc = crcUpdate(crc, chunk);
          if (retain) chunks.push(chunk);
          else digest.update(chunk);
        }
      };
      if (inflater) await pipeline(input, inflater, sink);
      else await pipeline(input, sink);
      if (bytes !== entry.bytes) fail('member logical byte count mismatch');
      if (((crc ^ 0xffffffff) >>> 0) !== entry.crc) fail('member CRC mismatch');
      if (inflater && inflater.bytesWritten !== entry.compressedBytes) fail('trailing bytes in deflated member');
      await unchanged();
      return retain ? Buffer.concat(chunks, bytes) : digest.digest('hex');
    };
    // Serialize I/O so concurrent calls cannot multiply decompression buffers.
    const run = (path, kind) => {
      if (closed) return Promise.reject(new Error('Artifact ZIP is closed'));
      const entry = byPath.get(path);
      if (!entry) return Promise.reject(new Error('Artifact ZIP member not found'));
      if (kind === 'json' && entry.bytes > limits.maxJsonBytes) {
        return Promise.reject(new Error('Artifact ZIP JSON bytes exceed limit'));
      }
      const operation = queue.then(async () => {
        const value = await consume(entry, kind !== 'digest');
        if (kind !== 'json') return value;
        let text;
        try { text = utf8.decode(value); } catch { fail('JSON member has invalid UTF-8'); }
        try { return JSON.parse(text); } catch { fail('JSON member has invalid JSON'); }
      });
      queue = operation.catch(() => {});
      return operation;
    };
    return Object.freeze({
      entries, compressedBytes, sha256,
      read: path => run(path, 'read'),
      json: path => run(path, 'json'),
      digest: path => run(path, 'digest'),
      close() {
        if (!closePromise) {
          closed = true;
          closePromise = queue.then(() => handle.close());
        }
        return closePromise;
      },
    });
  } catch (error) {
    await handle.close();
    throw error;
  }
}
