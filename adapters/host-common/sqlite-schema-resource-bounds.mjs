// Resource-only preflight for the same isolated SQLite copy. This reads the
// schema table's declared payload lengths, not SQL meaning, row authority or
// the Journal format. SQLite remains the semantic decoder. No admission is
// issued here, and unselected inspection does not use this extra boundary.
import {readSync} from 'node:fs';
import {Buffer} from 'node:buffer';
import {types} from 'node:util';

const readOriginal = readSync, apply = Reflect.apply, freeze = Object.freeze;
const descriptor = Object.getOwnPropertyDescriptor, own = Object.hasOwn;
const keys = Reflect.ownKeys, integer = Number.isSafeInteger;
const alloc = Buffer.alloc, u16 = Buffer.prototype.readUInt16BE;
const u32 = Buffer.prototype.readUInt32BE, le32 = Buffer.prototype.readUInt32LE;
const copy = Buffer.prototype.copy, character = String.prototype.charCodeAt;
const unavailable = () => {
  throw Object.assign(new Error('SqliteSchemaPreparationUnavailable'),
    {code: 'SqliteSchemaPreparationUnavailable'});
};

export function snapshotSqliteSchemaReadLimits(value) {
  if (value === undefined) return undefined;
  const names = ['maxSchemaBytes', 'maxSchemaEntries', 'maxSchemaPages', 'maxWalFrames'];
  if (value === null || typeof value !== 'object' || types.isProxy(value)) unavailable();
  const selected = keys(value);
  if (selected.length !== names.length || selected.some(name => !names.includes(name))) unavailable();
  const result = {};
  for (const name of names) {
    const field = descriptor(value, name);
    if (field === undefined || !own(field, 'value') || !integer(field.value) || field.value < 1) unavailable();
    result[name] = field.value;
  }
  return freeze(result);
}

// A selected resource recipe may name a finite set of its own ASCII DDL
// byte strings. This is not SQL interpretation, format admission or authority.
// Unknown/equivalent spellings remain an unsupported backend recipe; SQLite
// still checks actual schema meaning after this support boundary.
export function snapshotSqliteSchemaSqlSupport(value, limits) {
  if (value === undefined) return undefined;
  if (limits === undefined || value === null || typeof value !== 'object' ||
      types.isProxy(value) || !Array.isArray(value)) unavailable();
  const length = descriptor(value, 'length')?.value;
  if (!integer(length) || length < 1 || length > limits.maxSchemaEntries) unavailable();
  const result = [];
  let total = 0;
  for (let index = 0; index < length; index++) {
    const property = descriptor(value, String(index));
    if (property === undefined || !own(property, 'value') ||
        typeof property.value !== 'string' || property.value.length === 0 ||
        property.value.length > limits.maxSchemaBytes - total) unavailable();
    const text = property.value;
    for (let offset = 0; offset < text.length; offset++) {
      const byte = apply(character, text, [offset]);
      if (byte === 0 || byte > 127) unavailable();
    }
    total += text.length;
    result.push(text);
  }
  return freeze(result);
}

function at(fd, target, position, bytes = target.length) {
  let offset = 0;
  while (offset < bytes) {
    const count = apply(readOriginal, undefined, [fd, target, offset, bytes - offset, position + offset]);
    if (!integer(count) || count < 1 || count > bytes - offset) unavailable();
    offset += count;
  }
}
const be = (bytes, offset) => apply(u32, bytes, [offset]);
const half = (bytes, offset) => apply(u16, bytes, [offset]);

function checksum(bytes, length, little, previous) {
  let [a, b] = previous;
  const read = little ? le32 : u32;
  for (let offset = 0; offset < length; offset += 8) {
    a = (a + apply(read, bytes, [offset]) + b) >>> 0;
    b = (b + apply(read, bytes, [offset + 4]) + a) >>> 0;
  }
  return [a, b];
}

function committedWal(wal, pageSize, page, limits, maxPages) {
  const latest = new Map();
  if (wal === undefined || wal.bytes === 0) return {latest, frames: 0};
  if (wal.bytes < 32) unavailable();
  const header = apply(alloc, Buffer, [32]);
  at(wal.fd, header, 0);
  const magic = be(header, 0);
  if ((magic !== 0x377f0682 && magic !== 0x377f0683) ||
      be(header, 4) !== 3007000 || be(header, 8) !== pageSize) unavailable();
  const little = magic === 0x377f0682;
  let sum = checksum(header, 24, little, [0, 0]);
  if (sum[0] !== be(header, 24) || sum[1] !== be(header, 28)) unavailable();
  const salt1 = be(header, 16), salt2 = be(header, 20);
  const count = Math.floor((wal.bytes - 32) / (24 + pageSize));
  if (count > limits.maxWalFrames) unavailable();
  const frame = apply(alloc, Buffer, [24]);
  let committed = 0;
  // A single streaming checksum pass finds the same last valid commit prefix.
  // Invalid/uncommitted tails cannot hide an earlier larger schema. Do not
  // copy the growing page map on every commit: build it in one second pass.
  for (let index = 0; index < count; index++) {
    const offset = 32 + index * (24 + pageSize);
    at(wal.fd, frame, offset);
    const number = be(frame, 0), size = be(frame, 4);
    if (number === 0 || be(frame, 8) !== salt1 || be(frame, 12) !== salt2) break;
    at(wal.fd, page, offset + 24);
    sum = checksum(frame, 8, little, sum);
    sum = checksum(page, pageSize, little, sum);
    if (sum[0] !== be(frame, 16) || sum[1] !== be(frame, 20)) break;
    if (number > maxPages || size > maxPages) unavailable();
    if (size !== 0) committed = index + 1;
  }
  for (let index = 0; index < committed; index++) {
    const offset = 32 + index * (24 + pageSize);
    at(wal.fd, frame, offset);
    latest.set(be(frame, 0), offset + 24);
  }
  return {latest, frames: committed};
}

function varint(page, offset, limit, decode) {
  let value = 0;
  for (let count = 0; count < 9; count++) {
    if (offset >= limit) unavailable();
    const byte = page[offset++];
    if (decode) {
      value = value * (count === 8 ? 256 : 128) +
        (count === 8 ? byte : byte & 127);
      if (!integer(value)) unavailable();
    }
    if (count === 8 || (byte & 128) === 0) return {value, offset};
  }
  unavailable();
}

function serialBytes(type) {
  if (type === 0 || type === 8 || type === 9) return 0;
  if (type >= 1 && type <= 4) return type;
  if (type === 5) return 6;
  if (type === 6 || type === 7) return 8;
  if (type >= 12) return Math.floor((type - 12) / 2);
  unavailable();
}

function supportsSchemaRecord(payload, support) {
  const header = varint(payload, 0, payload.length, true);
  if (header.value > payload.length || header.value < header.offset) unavailable();
  let cursor = header.offset, body = header.value, typeName, sql;
  for (let index = 0; index < 5; index++) {
    const type = varint(payload, cursor, header.value, true);
    cursor = type.offset;
    const bytes = serialBytes(type.value);
    if (bytes > payload.length - body) unavailable();
    if (index === 0) typeName = {type: type.value, offset: body, bytes};
    if (index === 4) sql = {type: type.value, offset: body, bytes};
    body += bytes;
  }
  if (cursor !== header.value || body !== payload.length) unavailable();
  if (sql.type === 0) {
    // Only a native automatic-index entry has no SQL program. Its identity
    // and semantic validity are still SQLite/Journal responsibilities.
    const name = 'index';
    if (typeName.type < 13 || typeName.type % 2 !== 1 || typeName.bytes !== name.length) unavailable();
    for (let offset = 0; offset < name.length; offset++) {
      if (payload[typeName.offset + offset] !== apply(character, name, [offset])) unavailable();
    }
    return;
  }
  if (sql.type < 13 || sql.type % 2 !== 1) unavailable();
  for (const candidate of support) {
    if (candidate.length !== sql.bytes) continue;
    let equal = true;
    for (let index = 0; index < candidate.length; index++) {
      if (payload[sql.offset + index] !== apply(character, candidate, [index])) { equal = false; break; }
    }
    if (equal) return;
  }
  unavailable();
}

export function inspectBoundedSqliteSchema(database, wal, limits, maxSourceBytes, schemaSqlSupport) {
  if (!integer(maxSourceBytes) || maxSourceBytes < 512 || database.bytes < 100) unavailable();
  const header = apply(alloc, Buffer, [100]);
  at(database.fd, header, 0);
  const signature = [83,81,76,105,116,101,32,102,111,114,109,97,116,32,51,0];
  for (let index = 0; index < signature.length; index++) {
    if (header[index] !== signature[index]) unavailable();
  }
  const declaredSize = half(header, 16);
  const pageSize = declaredSize === 1 ? 65536 : declaredSize;
  if (pageSize < 512 || pageSize > 65536 || (pageSize & (pageSize - 1)) !== 0) unavailable();
  const maxPages = Math.floor(maxSourceBytes / pageSize);
  if (be(header, 28) > maxPages) unavailable();
  const page = apply(alloc, Buffer, [pageSize]);
  const overlay = committedWal(wal, pageSize, page, limits, maxPages);
  const pending = [1], visited = new Set();
  // Support inspection reads original record bytes only. One overflow buffer
  // is reused; all allocated payload backings together are bounded by the
  // existing aggregate schema payload ceiling, not by GC between iterations.
  if (schemaSqlSupport !== undefined && be(header, 56) !== 1) unavailable();
  const overflow = schemaSqlSupport === undefined ? undefined : apply(alloc, Buffer, [pageSize]);
  const payloadPages = new Set();
  const usable = pageSize - header[20];
  if (usable < 480) unavailable();
  const readPage = (number, target) => {
    if (number < 1 || number > maxPages) unavailable();
    const offset = overlay.latest.get(number);
    if (offset === undefined) {
      if (number * pageSize > database.bytes) unavailable();
      at(database.fd, target, (number - 1) * pageSize);
    } else at(wal.fd, target, offset);
  };
  const readPayload = (offset, bytes) => {
    const maximumLocal = usable - 35;
    const minimumLocal = Math.floor((usable - 12) * 32 / 255) - 23;
    let local = bytes;
    if (bytes > maximumLocal) {
      local = minimumLocal + (bytes - minimumLocal) % (usable - 4);
      if (local > maximumLocal) local = minimumLocal;
    }
    if (offset + local + (local < bytes ? 4 : 0) > usable) unavailable();
    const payload = apply(alloc, Buffer, [bytes]);
    apply(copy, page, [payload, 0, offset, offset + local]);
    let copied = local, number = local < bytes ? be(page, offset + local) : 0;
    while (copied < bytes) {
      if (number === 0 || visited.has(number) || payloadPages.has(number) ||
          visited.size + pending.length + payloadPages.size >= limits.maxSchemaPages) unavailable();
      payloadPages.add(number);
      readPage(number, overflow);
      const count = Math.min(bytes - copied, usable - 4);
      apply(copy, overflow, [payload, copied, 4, 4 + count]);
      copied += count;
      number = be(overflow, 0);
    }
    if (number !== 0) unavailable();
    return payload;
  };
  let entries = 0, payloadBytes = 0;
  const enqueue = number => {
    if (number < 1 || number > maxPages || visited.has(number) || payloadPages.has(number) ||
        visited.size + pending.length + payloadPages.size >= limits.maxSchemaPages) unavailable();
    pending.push(number);
  };
  while (pending.length !== 0) {
    const number = pending.pop();
    if (visited.has(number) || payloadPages.has(number) ||
        visited.size + payloadPages.size === limits.maxSchemaPages) unavailable();
    visited.add(number);
    const offset = overlay.latest.get(number);
    if (offset === undefined) {
      if (number * pageSize > database.bytes) unavailable();
      at(database.fd, page, (number - 1) * pageSize);
    } else at(wal.fd, page, offset);
    if (number === 1) {
      for (let index = 0; index < signature.length; index++) {
        if (page[index] !== signature[index]) unavailable();
      }
      const observedSize = half(page, 16);
      if ((observedSize === 1 ? 65536 : observedSize) !== pageSize) unavailable();
    }
    const start = number === 1 ? 100 : 0;
    const type = page[start];
    if (type !== 5 && type !== 13) unavailable();
    const cells = half(page, start + 3), bytes = type === 5 ? 12 : 8;
    if (cells > limits.maxSchemaEntries || start + bytes + cells * 2 > pageSize) unavailable();
    if (type === 5) enqueue(be(page, start + 8));
    for (let index = 0; index < cells; index++) {
      let cell = half(page, start + bytes + 2 * index);
      if (cell < start + bytes + cells * 2 || cell >= pageSize) unavailable();
      if (type === 5) {
        if (cell + 4 > pageSize) unavailable();
        enqueue(be(page, cell));
        varint(page, cell + 4, pageSize, false);
      } else {
        const payload = varint(page, cell, pageSize, true);
        const rowid = varint(page, payload.offset, usable, false);
        if (entries === limits.maxSchemaEntries ||
            payload.value > limits.maxSchemaBytes - payloadBytes) unavailable();
        entries++;
        payloadBytes += payload.value;
        if (schemaSqlSupport !== undefined) supportsSchemaRecord(
          readPayload(rowid.offset, payload.value), schemaSqlSupport);
      }
    }
  }
  return freeze({pageSize, schemaEntries: entries, schemaPayloadBytes: payloadBytes,
    schemaPages: visited.size + payloadPages.size, committedWalFrames: overlay.frames});
}
