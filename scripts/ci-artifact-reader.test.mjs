import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, writeFile, rm, appendFile, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {deflateRawSync} from 'node:zlib';
import {DEFAULT_ARTIFACT_LIMITS, openArtifactZip} from './ci-artifact-reader.mjs';

// Independent, deliberately simple fixture CRC; no product ZIP construction.
function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
const sha256 = data => createHash('sha256').update(data).digest('hex');

// ZIP records are authored here rather than using an archive package. Each
// optional override exists to construct a particular malformed test record.
function zip(specs, {comment = Buffer.alloc(0), endPatch} = {}) {
  const locals = [];
  const centrals = [];
  const layout = [];
  let offset = 0;
  for (const spec of specs) {
    const name = Buffer.isBuffer(spec.name) ? spec.name : Buffer.from(spec.name);
    const localName = spec.localName ? Buffer.from(spec.localName) : name;
    const data = Buffer.isBuffer(spec.data) ? spec.data : Buffer.from(spec.data ?? '123456789');
    const method = spec.method ?? 0;
    const packed = spec.packed ?? (method === 8 ? deflateRawSync(data) : data);
    const crc = spec.crc ?? crc32(data);
    const bytes = spec.bytes ?? data.length;
    const compressedBytes = spec.compressedBytes ?? packed.length;
    const flags = spec.flags ?? 0x0800;
    const needed = spec.needed ?? 20;
    const extra = spec.extra ?? Buffer.alloc(0);
    const localExtra = spec.localExtra ?? extra;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(needed, 4);
    local.writeUInt16LE(flags, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(flags & 8 ? 0 : crc, 14);
    local.writeUInt32LE(flags & 8 ? 0 : compressedBytes, 18);
    local.writeUInt32LE(flags & 8 ? 0 : bytes, 22);
    local.writeUInt16LE(localName.length, 26);
    local.writeUInt16LE(localExtra.length, 28);
    spec.localPatch?.(local);
    let descriptor = Buffer.alloc(0);
    if (flags & 8) {
      const start = spec.unsignedDescriptor ? 0 : 4;
      descriptor = Buffer.alloc(start + 12);
      if (start) descriptor.writeUInt32LE(0x08074b50, 0);
      descriptor.writeUInt32LE(crc, start);
      descriptor.writeUInt32LE(compressedBytes, start + 4);
      descriptor.writeUInt32LE(bytes, start + 8);
      spec.descriptorPatch?.(descriptor);
    }
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt16LE(needed, 6);
    central.writeUInt16LE(flags, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(compressedBytes, 20);
    central.writeUInt32LE(bytes, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(extra.length, 30);
    central.writeUInt32LE((spec.attributes ?? (0o100644 << 16)) >>> 0, 38);
    central.writeUInt32LE(spec.localOffset ?? offset, 42);
    spec.centralPatch?.(central);
    const localRecord = Buffer.concat([local, localName, localExtra, packed, descriptor]);
    locals.push(localRecord);
    centrals.push(Buffer.concat([central, name, extra]));
    layout.push({localOffset: offset, dataOffset: offset + 30 + localName.length + localExtra.length,
      recordBytes: localRecord.length});
    offset += localRecord.length;
  }
  const centralBytes = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(specs.length, 8);
  end.writeUInt16LE(specs.length, 10);
  end.writeUInt32LE(centralBytes.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(comment.length, 20);
  endPatch?.(end);
  return {bytes: Buffer.concat([...locals, centralBytes, end, comment]), layout, centralOffset: offset};
}

async function fixture(t, bytes, options) {
  const directory = await mkdtemp(join(tmpdir(), 'ci-artifact-reader-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'artifact.zip');
  await writeFile(path, bytes);
  const reader = await openArtifactZip(path, options);
  t.after(() => reader.close());
  return {reader, path, directory};
}

async function rejected(t, archive, pattern, options) {
  const directory = await mkdtemp(join(tmpdir(), 'ci-artifact-invalid-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'artifact.zip');
  await writeFile(path, archive.bytes ?? archive);
  await assert.rejects(openArtifactZip(path, options), pattern);
}

test('reads stored/deflated files and both descriptor layouts without extraction', async t => {
  const specs = [
    {name: 'reports/', data: '', attributes: (0o40755 << 16) | 16},
    {name: 'reports/plain.txt'},
    {name: 'reports/data.json', data: '{"ok":true,"samples":[1,2]}', method: 8, flags: 0x0808},
    {name: 'reports/unsigned.txt', data: 'unsigned', method: 8, flags: 0x0808, unsignedDescriptor: true},
    {name: 'empty', data: ''},
    {name: 'empty-deflated', data: '', method: 8},
    {name: 'cafe\u0301.json', data: '{}'},
  ];
  const archive = zip(specs, {comment: Buffer.from('comment PK\u0005\u0006 is not an EOCD')});
  const {reader, directory} = await fixture(t, archive.bytes, {expectedSha256: `sha256:${sha256(archive.bytes)}`});
  assert.equal(reader.sha256, sha256(archive.bytes));
  assert.equal(reader.compressedBytes, archive.bytes.length);
  assert.deepEqual(reader.entries[0], {path: 'reports/plain.txt', bytes: 9, compressedBytes: 9});
  assert.equal(reader.entries.length, 6);
  assert.equal((await reader.read('reports/plain.txt')).toString(), '123456789');
  assert.equal(await reader.digest('reports/plain.txt'), '15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225');
  assert.deepEqual(await reader.json('reports/data.json'), {ok: true, samples: [1, 2]});
  assert.equal((await reader.read('reports/unsigned.txt')).toString(), 'unsigned');
  assert.equal((await reader.read('empty')).length, 0);
  assert.equal((await reader.read('empty-deflated')).length, 0);
  assert.deepEqual(await reader.json('café.json'), {});
  const {readdir} = await import('node:fs/promises');
  assert.deepEqual(await readdir(directory), ['artifact.zip']);
  assert.ok(Object.isFrozen(reader) && Object.isFrozen(reader.entries) && Object.isFrozen(reader.entries[0]));
});

test('empty ZIP and ASCII names without UTF-8 flag are supported', async t => {
  const {reader} = await fixture(t, zip([]).bytes);
  assert.deepEqual(reader.entries, []);
  const {reader: ascii} = await fixture(t, zip([{name: 'ascii', flags: 0}]).bytes);
  assert.equal((await ascii.read('ascii')).toString(), '123456789');
});

test('rejects unsafe and ambiguous paths', async t => {
  for (const name of ['../escape', '/absolute', '//server/share', 'C:/drive', 'C:drive', 'a\\b',
    'a/../b', './a', 'a/./b', 'a//b', 'a///', '', '/', 'a\0b', 'a\nb']) {
    await t.test(JSON.stringify(name), inner => rejected(inner, zip([{name}]), /unsafe member path|empty member name/u));
  }
});

test('rejects invalid/legacy filenames and normalized duplicates', async t => {
  await rejected(t, zip([{name: Buffer.from([0xff])}]), /invalid UTF-8/u);
  await rejected(t, zip([{name: 'café', flags: 0}]), /non-UTF-8/u);
  for (const names of [['same', 'same'], ['café', 'cafe\u0301'], ['a', 'a/']]) {
    const specs = names.map(name => ({name, data: '', attributes: 0}));
    await rejected(t, zip(specs), /duplicate normalized/u);
  }
  await rejected(t, zip([{name: 'a'}, {name: 'a/b'}]), /ancestor/u);
});

test('rejects symlinks, special files and inconsistent directory metadata', async t => {
  for (const kind of [0o120777, 0o20600, 0o60600, 0o10600, 0o140600]) {
    await rejected(t, zip([{name: 'link', attributes: kind << 16}]), /symlink or special/u);
  }
  await rejected(t, zip([{name: 'dir', data: '', attributes: (0o40755 << 16) | 16}]), /inconsistent member type/u);
  await rejected(t, zip([{name: 'dir/', data: '', attributes: 0o100644 << 16}]), /inconsistent member type/u);
  await rejected(t, zip([{name: 'dir/', data: 'payload', attributes: 0o40755 << 16}]), /directory has a payload/u);
  await rejected(t, zip([{name: 'volume', attributes: 8}]), /inconsistent member type/u);
});

test('rejects encryption, unsupported flags/methods/versions, multi-disk and ZIP64', async t => {
  for (const flags of [1, 0x40, 0x2000]) {
    await rejected(t, zip([{name: 'a', flags}]), /encrypted/u);
  }
  await rejected(t, zip([{name: 'a', flags: 0x10}]), /flags are unsupported/u);
  await rejected(t, zip([{name: 'a', flags: 2}]), /invalid stored-member flags/u);
  await rejected(t, zip([{name: 'a', method: 12}]), /compression method/u);
  await rejected(t, zip([{name: 'a', needed: 21}]), /ZIP version/u);
  await rejected(t, zip([{name: 'a', needed: 45}]), /ZIP64/u);
  await rejected(t, zip([{name: 'a', extra: Buffer.from([1, 0, 0, 0])}]), /ZIP64/u);
  await rejected(t, zip([{name: 'a', bytes: 0xffffffff}]), /ZIP64/u);
  await rejected(t, zip([{name: 'a', centralPatch: h => h.writeUInt16LE(1, 34)}]), /multi-disk/u);
  await rejected(t, zip([{name: 'a'}], {endPatch: h => h.writeUInt16LE(1, 4)}), /multi-disk/u);
  await rejected(t, zip([{name: 'a'}], {endPatch: h => h.writeUInt16LE(0xffff, 10)}), /ZIP64/u);
});

test('enforces compressed/member/total/count/ratio/JSON bounds and limit validation', async t => {
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxCompressedBytes, 512 * 1024 * 1024);
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxMemberBytes, 256 * 1024 * 1024);
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxTotalBytes, 8 * 1024 ** 3);
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxEntries, 20_000);
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxCompressionRatio, 2_000);
  assert.equal(DEFAULT_ARTIFACT_LIMITS.maxJsonBytes, 160 * 1024 * 1024);
  const archive = zip([{name: 'a'}, {name: 'b'}]);
  await rejected(t, archive, /compressed archive bytes exceed/u, {limits: {maxCompressedBytes: 30}});
  await rejected(t, archive, /member logical bytes exceed/u, {limits: {maxMemberBytes: 8}});
  await rejected(t, archive, /total logical bytes exceed/u, {limits: {maxTotalBytes: 17}});
  await rejected(t, archive, /member count exceeds/u, {limits: {maxEntries: 1}});
  await rejected(t, zip([{name: 'ratio', data: 'x'.repeat(4096), method: 8}]), /compression ratio/u,
    {limits: {maxCompressionRatio: 2}});
  for (const limits of [{maxEntries: 20_001}, {maxEntries: 0}, {maxEntries: 1.5}, {unknown: 1}, null, []]) {
    await rejected(t, archive, /limit/u, {limits});
  }
  const {reader} = await fixture(t, zip([{name: 'a.json', data: '{"x":1}'}]).bytes, {limits: {maxJsonBytes: 6}});
  await assert.rejects(reader.json('a.json'), /JSON bytes exceed limit/u);
  assert.equal((await reader.read('a.json')).length, 7);
});

test('requires expected digest to match the complete archive', async t => {
  const archive = zip([{name: 'a'}]);
  await rejected(t, archive, /SHA-256 mismatch/u, {expectedSha256: '0'.repeat(64)});
  for (const expectedSha256 of ['', 'abc', null, 1]) {
    await rejected(t, archive, /invalid expected SHA-256/u, {expectedSha256});
  }
  const modified = Buffer.from(archive.bytes);
  modified[archive.layout[0].dataOffset] ^= 1;
  await rejected(t, modified, /SHA-256 mismatch/u, {expectedSha256: sha256(archive.bytes)});
});

test('rejects malformed records, truncation, trailing data and bad directory extents', async t => {
  const archive = zip([{name: 'a'}]);
  await rejected(t, Buffer.alloc(2), /truncated/u);
  await rejected(t, archive.bytes.subarray(0, -1), /end-of-central-directory/u);
  await rejected(t, Buffer.concat([archive.bytes, Buffer.from('extra')]), /end-of-central-directory/u);
  await rejected(t, zip([{name: 'a'}], {endPatch: h => h.writeUInt32LE(1, 16)}), /extent/u);
  await rejected(t, zip([{name: 'a'}], {endPatch: h => { h.writeUInt16LE(2, 8); h.writeUInt16LE(2, 10); }}), /range/u);
  await rejected(t, zip([{name: 'a', extra: Buffer.from([3, 0, 5, 0])}]), /truncated extra field payload/u);
  await rejected(t, zip([{name: 'a', extra: Buffer.from([3, 0])}]), /truncated extra field/u);
  await rejected(t, zip([{name: 'a', localExtra: Buffer.from([3, 0])}]), /truncated extra field/u);
  await rejected(t, zip([{name: 'a', centralPatch: h => h.writeUInt32LE(0, 0)}]), /central-directory member/u);
  await rejected(t, zip([{name: 'a', localPatch: h => h.writeUInt32LE(0, 0)}]), /local member header/u);
});

test('rejects local/central disagreement, invalid descriptors and overlapping records', async t => {
  await rejected(t, zip([{name: 'central', localName: 'changed'}]), /names disagree/u);
  for (const localPatch of [h => h.writeUInt16LE(8, 8), h => h.writeUInt16LE(10, 4),
    h => h.writeUInt16LE(0, 6), h => h.writeUInt32LE(1, 10)]) {
    await rejected(t, zip([{name: 'a', localPatch}]), /headers disagree/u);
  }
  for (const position of [14, 18, 22]) {
    await rejected(t, zip([{name: 'a', localPatch: h => h.writeUInt32LE(1, position)}]), /sizes or CRC disagree/u);
  }
  await rejected(t, zip([{name: 'a', flags: 0x0808, descriptorPatch: h => h.writeUInt32LE(123, 4)}]), /data descriptor/u);
  await rejected(t, zip([{name: 'a', flags: 0x0808, localPatch: h => h.writeUInt32LE(123, 18)}]), /sizes or CRC disagree/u);
  const inner = zip([{name: 'inner'}]);
  const innerRecord = inner.bytes.subarray(0, inner.centralOffset);
  await rejected(t, zip([{name: 'outer', data: innerRecord}, {name: 'inner', localOffset: 35}]), /overlapping/u);
  await rejected(t, zip([{name: 'a', method: 8, compressedBytes: 10_000}]), /payload overlaps/u);
  await rejected(t, zip([{name: 'a', bytes: 8}]), /stored-member sizes disagree/u);
});

test('validates actual CRC/length and bounds dishonest or invalid deflate payloads', async t => {
  const {reader} = await fixture(t, zip([
    {name: 'crc', crc: 0},
    {name: 'short', method: 8, bytes: 10},
    {name: 'bomb', method: 8, data: 'x'.repeat(1024 * 1024), bytes: 32},
    {name: 'invalid', method: 8, packed: Buffer.from('invalid deflate')},
    {name: 'truncated', method: 8, packed: deflateRawSync(Buffer.from('123456789')).subarray(0, -1)},
    {name: 'trailing', method: 8, packed: Buffer.concat([deflateRawSync(Buffer.from('123456789')), Buffer.from('extra')])},
    {name: 'good'},
  ]).bytes);
  await assert.rejects(reader.read('crc'), /CRC mismatch/u);
  await assert.rejects(reader.digest('crc'), /CRC mismatch/u);
  await assert.rejects(reader.read('short'), /logical byte count mismatch/u);
  await assert.rejects(reader.read('bomb'), /inflated member exceeds/u);
  await assert.rejects(reader.read('invalid'));
  await assert.rejects(reader.read('truncated'));
  await assert.rejects(reader.read('trailing'), /trailing bytes in deflated/u);
  assert.equal((await reader.read('good')).toString(), '123456789');
});

test('JSON is parsed as data with strict UTF-8 and errors do not poison subsequent reads', async t => {
  const {reader} = await fixture(t, zip([
    {name: 'invalid.json', data: '{'},
    {name: 'encoding.json', data: Buffer.from([34, 0xff, 34])},
    {name: 'data.json', data: '{"__proto__":{"polluted":true},"script":"throw Error()"}'},
  ]).bytes);
  await assert.rejects(reader.json('invalid.json'), /invalid JSON/u);
  await assert.rejects(reader.json('encoding.json'), /invalid UTF-8/u);
  const data = await reader.json('data.json');
  assert.equal(data.script, 'throw Error()');
  assert.equal(Object.hasOwn(data, '__proto__'), true);
  assert.equal({}.polluted, undefined);
  await assert.rejects(reader.read('../missing'), /not found/u);
});

test('large digest streams through bounded chunks and concurrent operations serialize', async t => {
  const data = Buffer.alloc(2 * 1024 * 1024, 0x61);
  const {reader} = await fixture(t, zip([{name: 'large', data, method: 8}, {name: 'small'}]).bytes);
  const [digest, small] = await Promise.all([reader.digest('large'), reader.read('small')]);
  assert.equal(digest, sha256(data));
  assert.equal(small.toString(), '123456789');
});

test('detects mutation, refuses symlink inputs, and closes idempotently after queued work', async t => {
  const {reader, path, directory} = await fixture(t, zip([{name: 'a'}]).bytes);
  const pending = reader.read('a');
  const closing = reader.close();
  assert.equal(reader.close(), closing);
  assert.equal((await pending).toString(), '123456789');
  await closing;
  await assert.rejects(reader.read('a'), /closed/u);
  const link = join(directory, 'link.zip');
  await symlink(path, link);
  await assert.rejects(openArtifactZip(link), /ELOOP/u);
  const {reader: changing, path: changingPath} = await fixture(t, zip([{name: 'a'}]).bytes);
  await appendFile(changingPath, 'x');
  await assert.rejects(changing.read('a'), /archive changed/u);
});


test('repeated streaming reads do not retain FileHandle close listeners', async t => {
  const {reader} = await fixture(t, zip([{name: 'many', method: 8}]).bytes);
  const warnings = []; const capture = warning => warnings.push(warning);
  process.on('warning', capture); t.after(() => process.off('warning', capture));
  for (let i = 0; i < 32; i++) assert.equal(await reader.digest('many'), sha256(Buffer.from('123456789')));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(warnings.filter(w => w.name === 'MaxListenersExceededWarning').length, 0);
});
test('FIFO archive input is rejected without waiting for a writer', {skip: process.platform === 'win32'}, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'ci-artifact-fifo-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'input.zip');
  const result = spawnSync('mkfifo', [path]);
  assert.equal(result.status, 0);
  await assert.rejects(openArtifactZip(path), /regular file/);
});
