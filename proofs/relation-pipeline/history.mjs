import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { composeFoundation } from './foundation.mjs';
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
export function checkLegacyFoundation(root, { recordPath = currentPath, reference = 'HEAD', compareWorkingTree = true } = {}) {
  const historical = gitBlob(root, historicalRevision, baselinePath);
  assert.equal(hash(readFileSync(`${root}/${baselinePath}`)), hash(historical), 'Historical reuse baseline changed');
  const baseline = JSON.parse(historical);
  assert.match(baseline.revision, /^[0-9a-f]{40}$/);
  const contents = readFileSync(`${root}/${recordPath}`);
  assert.equal(hash(contents), hash(gitBlob(root, reference, currentPath)), 'Uncommitted current foundation record');
  const current = JSON.parse(contents);
  assert.equal(current.version, 'actql-relation-pipeline-current-foundation/0.1');
  assert.deepEqual(current.historicalBaseline, { revision: historicalRevision,
    path: baselinePath, digest: hash(historical), foundationRevision: baseline.revision });
  assert.match(current.revision, /^[0-9a-f]{40}$/);
  const ancestor = spawnSync('git', ['merge-base', '--is-ancestor', current.revision, reference], { cwd: root });
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
    assert.equal(hash(gitBlob(root, reference, path)), expected, `Changed committed common foundation ${path}`);
    if (compareWorkingTree) assert.equal(hash(readFileSync(`${root}/${path}`)), expected, `Changed common foundation ${path}`);
  }
  assert.deepEqual([...paths].sort(), changed.sort(), 'Spurious common foundation change');
  const additions = current.addedFoundation.map(entry => entry.path);
  assert.equal(new Set(additions).size, additions.length, 'Duplicate added foundation file');
  assert.deepEqual([...additions].sort(), [...addedFoundation].sort(), 'Incomplete added foundation files');
  for (const entry of current.addedFoundation) {
    assert(!Object.hasOwn(baseline.common, entry.path), 'Added foundation file was already common');
    assert.equal(hash(gitBlob(root, current.revision, entry.path)), entry.digest, `Unrelated added foundation file ${entry.path}`);
    assert.equal(hash(gitBlob(root, reference, entry.path)), entry.digest, `Changed committed added foundation file ${entry.path}`);
    if (compareWorkingTree) assert.equal(hash(readFileSync(`${root}/${entry.path}`)), entry.digest, `Changed added foundation file ${entry.path}`);
  }
  return baseline;
}

// Fixed migration after #172, #173 and #175. The old aggregate is retained
// byte-for-byte as an immutable input, never advanced by later declarations.
export const foundationCheckpoint = '16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a';
const checkpointPath = 'proofs/relation-pipeline/foundation-baseline.json';
const compositionFoundation = ['foundation.mjs', 'foundation.test.mjs',
  'fixtures/foundation-repository.mjs', 'fixtures/convergent-declarations.json',
  'fixtures/multiple-merge-bases.json', 'workspaces.mjs', 'workspaces.test.mjs',
  'execute.test.mjs', 'fixture.test.mjs', 'fixtures/execution-driver.mjs',
  'capacity/finish.mjs', 'executor-close.test.mjs'].map(path => `proofs/relation-pipeline/${path}`);
export function currentFoundation(root) {
  const baseline = checkLegacyFoundation(root, { recordPath: checkpointPath,
    reference: foundationCheckpoint, compareWorkingTree: false });
  const manifest = composeFoundation(root, { checkpoint: foundationCheckpoint,
    paths: [...Object.keys(baseline.common), ...addedFoundation, ...compositionFoundation],
    immutable: [{ path: baselinePath, revision: historicalRevision },
      { path: checkpointPath, revision: foundationCheckpoint, sourcePath: currentPath }] });
  const obsolete = spawnSync('git', ['ls-files', '--stage', '--', currentPath], { cwd: root });
  const committedObsolete = spawnSync('git', ['ls-tree', 'HEAD', '--', currentPath], { cwd: root });
  assert.equal(obsolete.status, 0); assert.equal(committedObsolete.status, 0);
  assert(!obsolete.stdout.length && !committedObsolete.stdout.length && !existsSync(`${root}/${currentPath}`),
    'Obsolete shared foundation manifest: retain the immutable migration record and generate only the ignored artifact');
  return { ...manifest, historicalBaseline: { revision: historicalRevision, path: baselinePath,
    digest: hash(gitBlob(root, historicalRevision, baselinePath)), foundationRevision: baseline.revision },
    migrationBaseline: { revision: foundationCheckpoint, path: checkpointPath,
      digest: hash(gitBlob(root, foundationCheckpoint, currentPath)) } };
}
export function checkFoundation(root) {
  currentFoundation(root);
  return JSON.parse(gitBlob(root, historicalRevision, baselinePath));
}
// No tracked generated manifest: CI archives the exact-source deterministic file.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const manifest = currentFoundation(root);
  const output = process.argv[2];
  assert(!output || output === '--write', 'Usage: node proofs/relation-pipeline/history.mjs [--write]');
  const contents = `${JSON.stringify(manifest, null, 2)}\n`;
  if (output) {
    const path = `${root}/.artifacts/relation-pipeline/current-foundation.json`;
    mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, contents);
  } else process.stdout.write(contents);
}
