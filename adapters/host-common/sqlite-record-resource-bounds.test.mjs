import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from './sqlite-format-inspection.mjs';

const sql = 'CREATE TABLE values_table(value TEXT UNIQUE)';
const limits = {maxSchemaBytes: 65536, maxSchemaEntries: 32,
  maxSchemaPages: 32, maxWalFrames: 128};
function varint(value) {
  const bytes = [value & 127];
  while ((value = Math.floor(value / 128)) !== 0) bytes.unshift((value & 127) | 128);
  return Buffer.from(bytes);
}
function claimOversizedPayload(page, type) {
  assert.equal(page[0], type);
  page.fill(0, 1);
  page.writeUInt16BE(1, 3);
  page.writeUInt16BE(128, 5);
  page.writeUInt16BE(128, 8);
  let offset = 128;
  offset += varint(32768).copy(page, offset);
  if (type === 13) page[offset++] = 1;
  // The declared record is larger than this complete disposable DB. Never
  // ask SQLite to read this row; the counter observes only pre-native order.
  page[offset++] = 4;
  varint(13 + 2 * (32768 - 4)).copy(page, offset);
}
async function fixture({wal = false} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'sqlite-record-original-', label: 'selected original record resource preflight',
  });
  let path = join(scratch.path, 'source.sqlite3');
  const db = new DatabaseSync(path);
  let roots, snapshot;
  try {
    db.exec('PRAGMA page_size = 512');
    if (wal) db.exec('PRAGMA journal_mode = WAL');
    db.exec(sql);
    db.prepare('INSERT INTO values_table VALUES (?)').run('value');
    roots = db.prepare('SELECT type,rootpage FROM sqlite_schema ORDER BY type').all();
    if (wal) snapshot = {database: readFileSync(path), wal: readFileSync(path + '-wal')};
  } finally {db.close();}
  if (snapshot !== undefined) {
    // A fresh disposable copy of this fixture's confirmed commit, not a
    // mutation underneath an open database or historical Journal recovery.
    path = join(scratch.path, 'snapshot.sqlite3');
    writeFileSync(path, snapshot.database);
    writeFileSync(path + '-wal', snapshot.wal);
  }
  return {scratch, path, roots, options: {maxSourceBytes: 4096,
    schemaReadLimits: limits, schemaSqlSupport: [sql]}};
}
function nativeOpens(body) {
  const open = DatabaseSync.prototype.open;
  let opens = 0;
  DatabaseSync.prototype.open = function () {opens++; return Reflect.apply(open, this, []);};
  try {body(); return opens;} finally {DatabaseSync.prototype.open = open;}
}
const metadataOnly = db => db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE type='table'").get().n;

for (const [kind, type] of [['table', 13], ['index', 10]]) {
  test('selected original ' + kind + ' payload extent refuses before native open', async () => {
    const f = await fixture();
    const bytes = readFileSync(f.path);
    const root = f.roots.find(row => row.type === kind).rootpage;
    claimOversizedPayload(bytes.subarray((root - 1) * 512, root * 512), type);
    writeFileSync(f.path, bytes);
    assert.equal(nativeOpens(() => assert.throws(() => inspectSqliteSnapshot(
      f.path, metadataOnly, f.options), {code: 'SqliteSchemaPreparationUnavailable'})), 0);
    assert.deepEqual(readFileSync(f.path), bytes);
    f.scratch.passed();
  });
}

test('valid selected data/automatic-index and overflow payloads retain original contents', async () => {
  const f = await fixture();
  const text = 'x'.repeat(1800);
  const db = new DatabaseSync(f.path);
  try {db.prepare('UPDATE values_table SET value = ?').run(text);} finally {db.close();}
  const before = readFileSync(f.path);
  assert.equal(nativeOpens(() => assert.equal(inspectSqliteSnapshot(f.path,
    original => original.prepare('SELECT value FROM values_table').get().value,
    {...f.options, maxSourceBytes: 16384}), text)), 1);
  assert.deepEqual(readFileSync(f.path), before);
  f.scratch.passed();
});

test('selected record walk follows both original table and index interior pages', async () => {
  const f = await fixture();
  const db = new DatabaseSync(f.path);
  try {
    db.exec('BEGIN');
    const insert = db.prepare('INSERT INTO values_table VALUES (?)');
    for (let index = 0; index < 200; index++) insert.run('row-' + index + '-' + 'x'.repeat(48));
    db.exec('COMMIT');
  } finally {db.close();}
  const before = readFileSync(f.path);
  assert.deepEqual(f.roots.map(root => before[(root.rootpage - 1) * 512]), [2, 5]);
  assert.equal(inspectSqliteSnapshot(f.path,
    original => original.prepare('SELECT count(*) AS n FROM values_table').get().n,
    {...f.options, maxSourceBytes: 1024 * 1024}), 201);
  assert.deepEqual(readFileSync(f.path), before);
  f.scratch.passed();
});

test('selected record extent uses the original committed WAL page rather than stale main bytes', async () => {
  const f = await fixture({wal: true});
  const wal = readFileSync(f.path + '-wal'), pageSize = wal.readUInt32BE(8), stride = 24 + pageSize;
  assert.equal(pageSize, 512);
  const root = f.roots.find(row => row.type === 'table').rootpage;
  let selected;
  for (let frame = 32; frame + stride <= wal.length; frame += stride) {
    if (wal.readUInt32BE(frame) === root) selected = frame;
  }
  assert.notEqual(selected, undefined);
  claimOversizedPayload(wal.subarray(selected + 24, selected + stride), 13);
  let a = wal.readUInt32BE(24), b = wal.readUInt32BE(28);
  const little = wal.readUInt32BE(0) === 0x377f0682;
  for (let frame = 32; frame + stride <= wal.length; frame += stride) {
    for (const bytes of [wal.subarray(frame, frame + 8), wal.subarray(frame + 24, frame + stride)]) {
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      for (let offset = 0; offset < bytes.length; offset += 8) {
        a = (a + view.getUint32(offset, little) + b) >>> 0;
        b = (b + view.getUint32(offset + 4, little) + a) >>> 0;
      }
    }
    wal.writeUInt32BE(a, frame + 16); wal.writeUInt32BE(b, frame + 20);
  }
  writeFileSync(f.path + '-wal', wal);
  const before = readFileSync(f.path);
  assert.equal(nativeOpens(() => assert.throws(() => inspectSqliteSnapshot(f.path,
    metadataOnly, {...f.options, maxSourceBytes: 8192}),
  {code: 'SqliteSchemaPreparationUnavailable'})), 0);
  assert.deepEqual(readFileSync(f.path), before);
  assert.deepEqual(readFileSync(f.path + '-wal'), wal);
  f.scratch.passed();
});
