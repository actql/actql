import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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

// This historical anchor is the accepted #148 registration, not the later
// optimization's current validation reference. Keep its baseline byte-for-byte.
const historicalRevision = '0aa3bc921362b53536d5bf9d541a889e09ccc24b';
const baselinePath = 'proofs/relation-pipeline/reuse-baseline.json';
const currentPath = 'proofs/relation-pipeline/current-foundation.json';
const addedFoundation = ['current-foundation.md', 'history.test.mjs', 'mutations.test.mjs',
  'fixtures/history-driver.mjs', 'fixtures/mutation-driver.mjs']
  .map(path => `proofs/relation-pipeline/${path}`);
function gitBlob(root, revision, path) {
  const blob = spawnSync('git', ['show', `${revision}:${path}`], { cwd: root });
  assert.equal(blob.status, 0, `Missing foundation Git object ${revision}:${path}`);
  return blob.stdout;
}
export function checkFoundation(root) {
  const historical = gitBlob(root, historicalRevision, baselinePath);
  assert.equal(hash(readFileSync(`${root}/${baselinePath}`)), hash(historical), 'Historical reuse baseline changed');
  const baseline = JSON.parse(historical);
  assert.match(baseline.revision, /^[0-9a-f]{40}$/);
  const contents = readFileSync(`${root}/${currentPath}`);
  assert.equal(hash(contents), hash(gitBlob(root, 'HEAD', currentPath)), 'Uncommitted current foundation record');
  const current = JSON.parse(contents);
  assert.equal(current.version, 'actql-relation-pipeline-current-foundation/0.1');
  assert.deepEqual(current.historicalBaseline, { revision: historicalRevision,
    path: baselinePath, digest: hash(historical), foundationRevision: baseline.revision });
  assert.match(current.revision, /^[0-9a-f]{40}$/);
  const ancestor = spawnSync('git', ['merge-base', '--is-ancestor', current.revision, 'HEAD'], { cwd: root });
  assert.equal(ancestor.status, 0, 'Current foundation reference is not an ancestor of HEAD');
  assert(Array.isArray(current.changedCommon));
  assert(Array.isArray(current.addedFoundation));
  const paths = current.changedCommon.map(change => change.path);
  assert.equal(new Set(paths).size, paths.length, 'Duplicate common foundation change');
  assert(paths.every(path => Object.hasOwn(baseline.common, path)), 'Unknown common foundation change');
  const changed = [];
  for (const [path, digest] of Object.entries(baseline.common)) {
    assert.equal(hash(gitBlob(root, baseline.revision, path)), digest, `Unrelated foundation baseline ${path}`);
    const expected = hash(gitBlob(root, current.revision, path));
    if (expected !== digest) {
      changed.push(path);
      const change = current.changedCommon.find(change => change.path === path);
      assert(change, `Unlisted common foundation change ${path}`);
      assert.equal(change.beforeDigest, digest, `Incorrect prior foundation digest ${path}`);
      assert.equal(change.afterDigest, expected, `Incorrect current foundation digest ${path}`);
      assert.equal(typeof change.reason, 'string');
      assert(change.reason.trim(), `Missing foundation change rationale ${path}`);
    }
    assert.equal(hash(readFileSync(`${root}/${path}`)), expected, `Changed common foundation ${path}`);
  }
  assert.deepEqual([...paths].sort(), changed.sort(), 'Spurious common foundation change');
  const additions = current.addedFoundation.map(entry => entry.path);
  assert.equal(new Set(additions).size, additions.length, 'Duplicate added foundation file');
  assert.deepEqual([...additions].sort(), [...addedFoundation].sort(), 'Incomplete added foundation files');
  for (const entry of current.addedFoundation) {
    assert(!Object.hasOwn(baseline.common, entry.path), 'Added foundation file was already common');
    assert.equal(hash(gitBlob(root, current.revision, entry.path)), entry.digest, `Unrelated added foundation file ${entry.path}`);
    assert.equal(hash(readFileSync(`${root}/${entry.path}`)), entry.digest, `Changed added foundation file ${entry.path}`);
  }
  return baseline;
}
