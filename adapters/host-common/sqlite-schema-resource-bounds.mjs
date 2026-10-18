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

export function inspectBoundedSqliteSchema(database, wal, limits, maxSourceBytes) {
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
  let entries = 0, payloadBytes = 0;
  const enqueue = number => {
    if (number < 1 || number > maxPages || visited.has(number) ||
        visited.size + pending.length >= limits.maxSchemaPages) unavailable();
    pending.push(number);
  };
  while (pending.length !== 0) {
    const number = pending.pop();
    if (visited.has(number) || visited.size === limits.maxSchemaPages) unavailable();
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
        varint(page, payload.offset, pageSize, false);
        if (entries === limits.maxSchemaEntries ||
            payload.value > limits.maxSchemaBytes - payloadBytes) unavailable();
        entries++;
        payloadBytes += payload.value;
      }
    }
  }
  return freeze({pageSize, schemaEntries: entries, schemaPayloadBytes: payloadBytes,
    schemaPages: visited.size, committedWalFrames: overlay.frames});
}
