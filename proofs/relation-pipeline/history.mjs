import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { hash } from './inventory.mjs';
export function checkTakeHistory(root) {
  const extension = JSON.parse(readFileSync(`${root}/proofs/relation-pipeline/extension.json`));
  for (const [path, digest] of Object.entries(extension.frozen)) {
    const blob = spawnSync('git', ['show', `${extension.baseRevision}:${path}`], { cwd: root });
    assert.equal(blob.status, 0, 'Missing historical take foundation (fetch full history)');
    assert.equal(hash(blob.stdout), digest, `Historical take foundation changed: ${path}`);
  }
  const corrected = spawnSync('git', ['show', 'b5a7219b66c47f24a36d28df9aaf1421d23704d4:proofs/relation-pipeline/audit.mjs'], { cwd: root });
  assert.equal(corrected.status, 0);
  assert.equal(hash(corrected.stdout), extension.postRegistrationCorrections['proofs/relation-pipeline/audit.mjs'].correctedDigest);
  return extension;
}

export function checkFoundation(root) {
  const path = `${root}/proofs/relation-pipeline/reuse-baseline.json`;
  if (!existsSync(path)) return null;
  const baseline = JSON.parse(readFileSync(path));
  assert.match(baseline.revision, /^[0-9a-f]{40}$/);
  for (const [file, digest] of Object.entries(baseline.common)) {
    const blob = spawnSync('git', ['show', `${baseline.revision}:${file}`], { cwd: root });
    assert.equal(blob.status, 0, 'Missing completed foundation revision');
    assert.equal(hash(blob.stdout), digest, `Unrelated foundation baseline ${file}`);
    assert.equal(hash(readFileSync(`${root}/${file}`)), digest, `Changed common foundation ${file}`);
  }
  return baseline;
}
