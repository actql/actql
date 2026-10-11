// Exercise the actual checker with controlled Git object boundaries. Actual
// repository/history checks remain mandatory in the pipeline-evidence job.
import { mock } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { hash } from '../inventory.mjs';
const [root, scenario] = process.argv.slice(2);
const prefix = 'proofs/relation-pipeline/';
const baselinePath = `${prefix}reuse-baseline.json`;
const currentPath = `${prefix}current-foundation.json`;
const historicalRevision = '0aa3bc921362b53536d5bf9d541a889e09ccc24b';
const baselineRevision = 'a'.repeat(40), revision = 'b'.repeat(40);
const paths = ['.github/workflows/ci.yml', `${prefix}mutations.mjs`, `${prefix}history.mjs`, `${prefix}engine.mjs`];
const additions = ['current-foundation.md', 'history.test.mjs', 'mutations.test.mjs',
  'fixtures/history-driver.mjs', 'fixtures/mutation-driver.mjs'].map(path => `${prefix}${path}`);
const blobs = new Map();
const write = (path, body) => { mkdirSync(dirname(join(root, path)), { recursive: true }); writeFileSync(join(root, path), body); };
const common = Object.fromEntries(paths.map(path => [path, hash(`before:${path}`)]));
const baseline = { revision: baselineRevision, common, originalExperiment: { meaning: 'preserved comparison' } };
const historical = JSON.stringify(baseline);
blobs.set(`${historicalRevision}:${baselinePath}`, historical);
const current = { version: 'actql-relation-pipeline-current-foundation/0.1',
  historicalBaseline: { revision: historicalRevision, path: baselinePath, digest: hash(historical), foundationRevision: baselineRevision },
  revision, changedCommon: [], addedFoundation: [] };
paths.forEach((path, i) => {
  const before = `before:${path}`, after = i === 3 ? before : `after:${path}`;
  blobs.set(`${baselineRevision}:${path}`, before); blobs.set(`${revision}:${path}`, after); write(path, after);
  if (after !== before) current.changedCommon.push({ path, beforeDigest: hash(before), afterDigest: hash(after), reason: 'Separate common correction' });
});
for (const path of additions) {
  const body = `new:${path}`; blobs.set(`${revision}:${path}`, body); write(path, body);
  current.addedFoundation.push({ path, digest: hash(body) });
}
write(baselinePath, historical);
if (scenario === 'historical-edit') write(baselinePath, `${historical}\n`);
if (scenario === 'historical-remove-entry') { delete baseline.common[paths[3]]; write(baselinePath, JSON.stringify(baseline)); }
if (scenario === 'historical-add-entry') { baseline.common.other = '0'.repeat(64); write(baselinePath, JSON.stringify(baseline)); }
if (scenario === 'missing-baseline') unlinkSync(join(root, baselinePath));
if (scenario === 'missing-historical-object') blobs.delete(`${historicalRevision}:${baselinePath}`);
if (scenario === 'missing-baseline-object') blobs.delete(`${baselineRevision}:${paths[0]}`);
if (scenario === 'missing-current-object') blobs.delete(`${revision}:${paths[0]}`);
if (scenario === 'changed-ci') write(paths[0], 'altered workflow');
if (scenario === 'changed-unlisted-file') write(paths[3], 'altered engine');
if (scenario === 'unlisted-change') current.changedCommon.shift();
if (scenario === 'spurious-change') current.changedCommon.push({ path: paths[3] });
if (scenario === 'duplicate-change') current.changedCommon.push(current.changedCommon[0]);
if (scenario === 'unknown-change') current.changedCommon.push({ path: 'other' });
if (scenario === 'fake-before') current.changedCommon[0].beforeDigest = '0'.repeat(64);
if (scenario === 'fake-after') current.changedCommon[0].afterDigest = '0'.repeat(64);
if (scenario === 'record-and-source-edit') { write(paths[0], 'altered workflow'); current.changedCommon[0].afterDigest = hash('altered workflow'); }
if (scenario === 'wrong-anchor') current.historicalBaseline.revision = 'c'.repeat(40);
if (scenario === 'wrong-baseline-digest') current.historicalBaseline.digest = '0'.repeat(64);
if (scenario === 'wrong-baseline-revision') current.historicalBaseline.foundationRevision = 'c'.repeat(40);
if (scenario === 'missing-addition') current.addedFoundation.shift();
if (scenario === 'duplicate-addition') current.addedFoundation.push(current.addedFoundation[0]);
if (scenario === 'changed-addition') write(additions[0], 'altered documentation');
if (scenario === 'missing-addition-object') blobs.delete(`${revision}:${additions[0]}`);
const contents = JSON.stringify(current);
write(currentPath, contents); blobs.set(`HEAD:${currentPath}`, contents);
if (scenario === 'uncommitted-record') write(currentPath, `${contents}\n`);
if (scenario === 'missing-record') unlinkSync(join(root, currentPath));
const inspection = scenario.startsWith('inspection-');
const checkpoint = '16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a';
let compositionCalls = 0;
if (inspection) {
  write(`${prefix}foundation-baseline.json`, contents);
  blobs.set(`${checkpoint}:${currentPath}`, contents);
  unlinkSync(join(root, currentPath));
  mock.module('../foundation.mjs', { namedExports: { composeFoundation: (inspectedRoot, options) => {
    compositionCalls++;
    assert.equal(inspectedRoot, root);
    assert.equal(options.checkpoint, checkpoint);
    assert(paths.every(path => options.paths.includes(path)));
    assert.deepEqual(options.immutable, [
      {path: baselinePath, revision: historicalRevision},
      {path: `${prefix}foundation-baseline.json`, revision: checkpoint, sourcePath: currentPath},
    ]);
    if (scenario === 'inspection-composition-reject') throw new Error('Controlled composition rejection');
    return {sourceRevision: revision, files: [{path: 'package.json', digest: hash('checked package')}]};
  } } });
}
mock.module('node:child_process', { namedExports: { spawnSync: (command, args) => {
  if (command !== 'git') throw new Error('Unexpected command');
  if (args[0] === 'merge-base') return { status: scenario === 'non-ancestor' ? 1 : 0 };
  if (inspection && ['ls-files', 'ls-tree'].includes(args[0])) return {status: 0, stdout: Buffer.alloc(0)};
  if (args[0] !== 'show') throw new Error('Unexpected Git command');
  let value = blobs.get(args[1]);
  if (inspection && value === undefined && args[1].startsWith(checkpoint + ':'))
    value = blobs.get(args[1].replace(checkpoint + ':', revision + ':'));
  if (value === undefined && args[1].startsWith('HEAD:') && args[1] !== `HEAD:${currentPath}`) value = blobs.get(args[1].replace('HEAD:', `${revision}:`));
  return { status: value === undefined ? 128 : 0, stdout: Buffer.from(value ?? '') };
} } });
// Preserve the old representation's negative cases at the frozen checkpoint.
const { checkLegacyFoundation, inspectFoundation, currentFoundation, checkFoundation } = await import('../history.mjs');
if (!inspection) checkLegacyFoundation(root);
else if (scenario === 'inspection-historical-edit') {
  write(baselinePath, historical + '\n');
  assert.throws(() => inspectFoundation(root), /Historical reuse baseline changed/);
  assert.equal(compositionCalls, 0, 'Reject the changed original before composing');
} else if (scenario === 'inspection-composition-reject') {
  assert.throws(() => inspectFoundation(root), /Controlled composition rejection/);
  assert.equal(compositionCalls, 1);
} else {
  const value = inspectFoundation(root);
  assert.deepEqual(value.baseline, baseline);
  assert.equal(value.current.sourceRevision, revision);
  assert.equal(compositionCalls, 1, 'One complete inspection supplies both views');
  assert.deepEqual(checkFoundation(root), baseline);
  assert.equal(compositionCalls, 2, 'Separate validation must execute again');
  assert.deepEqual(currentFoundation(root), value.current);
  assert.equal(compositionCalls, 3);
  value.baseline.common = {};
  value.current.files = [];
  assert.deepEqual(inspectFoundation(root).baseline, baseline);
  assert.equal(compositionCalls, 4, 'A returned value cannot replace a new inspection');
  write(baselinePath, historical + '\n');
  assert.throws(() => inspectFoundation(root), /Historical reuse baseline changed/);
  assert.equal(compositionCalls, 4, 'Prior inspection must not hide changed bytes');
}
if (inspection) console.log(JSON.stringify({scenario, compositionCalls, synthetic: true}));
