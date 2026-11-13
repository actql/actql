import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { hash } from '../inventory.mjs';
import { pipelineEvidenceReader } from '../evidence-reader.mjs';
import { validate } from './audit.mjs';
import { semanticAuditFixture } from './semantic-audit.fixture.mjs';

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-capacity-semantic-audit-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bytes = Buffer.alloc(2 * 1024 ** 2, 0xa5), digest = hash(bytes);
  const path = `.artifacts/relation-pipeline/capacity/binaries/js/${digest}`, full = join(root, path);
  mkdirSync(dirname(full), { recursive: true }); writeFileSync(full, bytes); chmodSync(full, 0o444);
  const f = semanticAuditFixture(path, digest);
  const { read: physical } = pipelineEvidenceReader(join(root, '.artifacts/relation-pipeline'), root);
  const read = name => name === path ? readFileSync(full) : f.read(name);
  Object.defineProperty(read, 'artifactDigest', { value: physical.artifactDigest });
  return { ...f, read, full, bytes, work: physical.artifactDigestWork };
}

// These complete synthetic JS records exercise the production validator. They
// do not assert that a compiler or the three-target capacity proof was run.
test('healthy capacity semantics still check every receipt against actual artifact bytes before success', t => {
  const f = fixture(t), result = validate(f.report, f.current, ['js'], f.read);
  assert.deepEqual(result, { cases: f.report.corpus.length, targets: ['js'], unconditionalAllocationBytes: false });
  const requests = f.report.executions.length;
  assert.deepEqual(f.work(), { requests, fullHashes: 1, hashedBytes: f.bytes.length, reused: requests - 1 });
});

for (const [name, change, reason] of [
  ['target/case', r => { r.normal.js[0] = r.normal.js[1]; }, /Requested target\/case differs from independent execution/],
  ['handoff edge', r => { delete r.mutations.find(m => m.name === 'handoff-copy-without-accounting').anchor.receiver; }, /Missing checked handoff edge/],
  ['shrink history', r => { r.mutations[0].history[0].accepted = -2; }, /Shrink choice differs from real resource observations/],
]) test(`invalid ${name} refuses for its original reason before any heavy artifact digest`, t => {
  const f = fixture(t); change(f.report);
  assert.throws(() => validate(f.report, f.current, ['js'], f.read), reason);
  assert.deepEqual(f.work(), { requests: 0, fullHashes: 0, hashedBytes: 0, reused: 0 });
});

test('otherwise valid capacity semantics cannot admit a tampered physical artifact', t => {
  const f = fixture(t);
  chmodSync(f.full, 0o644); writeFileSync(f.full, Buffer.alloc(f.bytes.length, 0x42)); chmodSync(f.full, 0o444);
  assert.throws(() => validate(f.report, f.current, ['js'], f.read), /Executed capacity artifact changed/);
  assert.deepEqual(f.work(), { requests: 1, fullHashes: 1, hashedBytes: f.bytes.length, reused: 0 });
});

for (const [name, change] of [
  ['empty artifact inventory', e => { e.receipt.artifacts = {}; }],
  ['foreign compiled path', e => { e.receipt.artifacts = { '_build/native/debug/test/query_integration/foreign.exe': Object.values(e.receipt.artifacts)[0] }; }],
  ['foreign archive path', e => { e.capacityArchives[Object.keys(e.receipt.artifacts)[0]] = '.artifacts/relation-pipeline/capacity/binaries/native/foreign'; }],
]) test(`semantic deferral preserves ${name} refusal`, t => {
  const f = fixture(t), e = f.report.executions[0]; change(e);
  f.files.set(e.path, Buffer.from(JSON.stringify(e.receipt))); e.digest = hash(JSON.stringify(e.receipt));
  assert.throws(() => validate(f.report, f.current, ['js'], f.read), { code: 'ERR_ASSERTION' });
  assert.deepEqual(f.work(), { requests: 0, fullHashes: 0, hashedBytes: 0, reused: 0 });
});
