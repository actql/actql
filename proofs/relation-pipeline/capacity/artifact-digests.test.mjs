import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { pipelineEvidenceReader } from '../evidence-reader.mjs';
import { auditCapacityArtifact } from './audit.mjs';

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
