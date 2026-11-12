import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { chmodSync, existsSync, linkSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  realpathSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { pipelineEvidenceReader } from '../evidence-reader.mjs';
import { auditCapacityArtifact } from './audit.mjs';
import { materializeVerifiedMember } from '../ci-parts.mjs';
import { capacityRegressionReader } from './regression-worker.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-capacity-digests-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const directory = join(root, '.artifacts/relation-pipeline');
  const bytes = Buffer.alloc(2 * 1024 ** 2, 0xa5);
  const digest = crypto.createHash('sha256').update(bytes).digest('hex');
  const path = `.artifacts/relation-pipeline/capacity/binaries/js/${digest}`;
  const full = join(root, path);
  mkdirSync(dirname(full), { recursive: true }); writeFileSync(full, bytes); chmodSync(full, 0o444);
  return { root, directory, bytes, digest, path, full };
}

// Count actual SHA-256 objects and real bytes passed to them, without replacing
// their digest operation or supplying a virtual artifact reader.
function hashWork(t) {
  const work = { calls: 0, bytes: 0 }, createHash = crypto.createHash;
  t.mock.method(crypto, 'createHash', function (...args) {
    const hash = Reflect.apply(createHash, this, args), update = hash.update;
    work.calls++;
    hash.update = function (bytes, ...rest) {
      work.bytes += Buffer.byteLength(bytes);
      return Reflect.apply(update, this, [bytes, ...rest]);
    };
    return hash;
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  return work;
}

test('repeated original receipt checks hash a read-only physical artifact once per reader', t => {
  const f = fixture(t), { read } = pipelineEvidenceReader(f.directory, f.root), work = hashWork(t);
  for (let receipt = 0; receipt < 4; receipt++) auditCapacityArtifact(f.path, f.digest, read);
  console.log(`Actual capacity artifact hash work: ${JSON.stringify(work)}`);
  assert.equal(work.calls, 1);
  assert.equal(work.bytes, f.bytes.length);
});

test('actual joined hardlink transfer ends single-linked and its same reader hashes four receipts once', t => {
  const f = fixture(t), from = join(f.root, 'original-extraction');
  renameSync(f.full, from);
  materializeVerifiedMember(from, f.full, f.digest);
  assert.equal(existsSync(from), false);
  const actual = lstatSync(f.full, { bigint: true });
  assert.equal(actual.nlink, 1n); assert.equal(actual.mode & 0o777n, 0o444n);
  const { read } = pipelineEvidenceReader(f.directory, f.root), work = hashWork(t);
  for (let receipt = 0; receipt < 4; receipt++) auditCapacityArtifact(f.path, f.digest, read);
  assert.deepEqual(work, { calls: 1, bytes: f.bytes.length });
  assert.deepEqual(read.artifactDigestWork(), { requests: 4, fullHashes: 1, hashedBytes: f.bytes.length, reused: 3 });
  assert.equal(read.resolveArtifact(f.path), f.full);
});

test('every receipt still compares its independent expected digest, even after a mismatch', t => {
  const f = fixture(t), { read } = pipelineEvidenceReader(f.directory, f.root), work = hashWork(t);
  assert.throws(() => auditCapacityArtifact(f.path, 'foreign', read), /Executed capacity artifact changed/);
  auditCapacityArtifact(f.path, f.digest, read);
  assert.throws(() => auditCapacityArtifact(f.path, 'different receipt digest', read), /Executed capacity artifact changed/);
  auditCapacityArtifact(f.path, f.digest, read);
  assert.deepEqual(work, { calls: 1, bytes: f.bytes.length });
  assert.throws(() => read.artifactDigest('.artifacts/relation-pipeline/../elsewhere'), /Unsafe evidence path/);
  assert.throws(() => read.artifactDigest('/outside'), /Non-local evidence/);
});

for (const mutation of ['bytes', 'replacement', 'mode', 'hardlink', 'symlink', 'missing']) {
  test(`a previously read immutable artifact refuses ${mutation} instead of reusing its old digest`, t => {
    const f = fixture(t), { read } = pipelineEvidenceReader(f.directory, f.root);
    auditCapacityArtifact(f.path, f.digest, read);
    if (mutation === 'bytes') { chmodSync(f.full, 0o644); writeFileSync(f.full, Buffer.alloc(f.bytes.length, 0x42)); chmodSync(f.full, 0o444); }
    if (mutation === 'replacement') { renameSync(f.full, `${f.full}.original`); writeFileSync(f.full, f.bytes); chmodSync(f.full, 0o444); }
    if (mutation === 'mode') chmodSync(f.full, 0o440);
    if (mutation === 'hardlink') linkSync(f.full, `${f.full}.alias`);
    if (mutation === 'symlink') { renameSync(f.full, `${f.full}.original`); symlinkSync(`${f.full}.original`, f.full); }
    if (mutation === 'missing') unlinkSync(f.full);
    assert.throws(() => auditCapacityArtifact(f.path, f.digest, read), /identity changed|Linked evidence path|ENOENT/);
    assert.equal(read.artifactDigestWork().reused, 0);
  });
}

test('writable and multiply linked files keep complete reads; changed content still refuses', t => {
  const f = fixture(t), { read } = pipelineEvidenceReader(f.directory, f.root), work = hashWork(t);
  chmodSync(f.full, 0o644);
  for (let receipt = 0; receipt < 2; receipt++) auditCapacityArtifact(f.path, f.digest, read);
  chmodSync(f.full, 0o444); linkSync(f.full, `${f.full}.alias`);
  for (let receipt = 0; receipt < 2; receipt++) auditCapacityArtifact(f.path, f.digest, read);
  assert.deepEqual(work, { calls: 4, bytes: 4 * f.bytes.length });
  assert.equal(read.artifactDigestWork().reused, 0);
  chmodSync(f.full, 0o644); writeFileSync(f.full, Buffer.alloc(f.bytes.length, 0x42));
  assert.throws(() => auditCapacityArtifact(f.path, f.digest, read), /Executed capacity artifact changed/);
});

test('separate negative readers never reuse each other, and virtual overrides always hash their current bytes', t => {
  const f = fixture(t), work = hashWork(t);
  const first = capacityRegressionReader(f.root, new Map()), second = capacityRegressionReader(f.root, new Map());
  for (const read of [first, second]) {
    auditCapacityArtifact(f.path, f.digest, read); auditCapacityArtifact(f.path, f.digest, read);
    assert.deepEqual(read.artifactDigestWork(), { requests: 2, fullHashes: 1, hashedBytes: f.bytes.length, reused: 1 });
  }
  assert.deepEqual(work, { calls: 2, bytes: 2 * f.bytes.length });
  const overrides = new Map([[f.path, readFileSync(f.full)]]), virtual = capacityRegressionReader(f.root, overrides);
  auditCapacityArtifact(f.path, f.digest, virtual); auditCapacityArtifact(f.path, f.digest, virtual);
  assert.deepEqual(work, { calls: 4, bytes: 4 * f.bytes.length });
  overrides.get(f.path)[0] = 0x42;
  assert.throws(() => auditCapacityArtifact(f.path, f.digest, virtual), /Executed capacity artifact changed/);
  assert.deepEqual(work, { calls: 5, bytes: 5 * f.bytes.length });
  assert.deepEqual(virtual.artifactDigestWork(), { requests: 0, fullHashes: 0, hashedBytes: 0, reused: 0 });
});

test('legacy readers without the physical port keep the full actual file hash on every call', t => {
  const f = fixture(t), work = hashWork(t), read = path => readFileSync(join(f.root, path));
  for (let receipt = 0; receipt < 4; receipt++) auditCapacityArtifact(f.path, f.digest, read);
  assert.deepEqual(work, { calls: 4, bytes: 4 * f.bytes.length });
});

test('an initial symlink keeps full hashing without adopting its target as an immutable original', t => {
  const f = fixture(t), target = `${f.full}.target`;
  renameSync(f.full, target); symlinkSync(target, f.full);
  const { read } = pipelineEvidenceReader(f.directory, f.root), work = hashWork(t);
  auditCapacityArtifact(f.path, f.digest, read); auditCapacityArtifact(f.path, f.digest, read);
  assert.deepEqual(work, { calls: 2, bytes: 2 * f.bytes.length });
  assert.equal(read.artifactDigestWork().reused, 0);
  chmodSync(target, 0o644); writeFileSync(target, Buffer.alloc(f.bytes.length, 0x42));
  assert.throws(() => auditCapacityArtifact(f.path, f.digest, read), /Executed capacity artifact changed/);
});

test('a file changed during the original full hash never installs a reusable digest', t => {
  const f = fixture(t), { read } = pipelineEvidenceReader(f.directory, f.root), createHash = crypto.createHash;
  let mutated = false;
  t.mock.method(crypto, 'createHash', function (...args) {
    const hash = Reflect.apply(createHash, this, args), update = hash.update;
    hash.update = function (...args) {
      const result = Reflect.apply(update, this, args);
      if (!mutated) {
        mutated = true; chmodSync(f.full, 0o644);
        writeFileSync(f.full, Buffer.alloc(f.bytes.length, 0x42)); chmodSync(f.full, 0o444);
      }
      return result;
    };
    return hash;
  });
  syncBuiltinESMExports();
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports(); });
  assert.throws(() => auditCapacityArtifact(f.path, f.digest, read), /Evidence changed while reading|identity changed while hashing/);
  assert.equal(mutated, true); assert.equal(read.artifactDigestWork().reused, 0);
  assert.throws(() => auditCapacityArtifact(f.path, f.digest, read), /Executed capacity artifact changed/);
});
