// Exercise the actual checker with controlled Git object boundaries. Actual
// repository/history checks remain mandatory in the pipeline-evidence job.
import { mock } from 'node:test';
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
mock.module('node:child_process', { namedExports: { spawnSync: (command, args) => {
  if (command !== 'git') throw new Error('Unexpected command');
  if (args[0] === 'merge-base') return { status: scenario === 'non-ancestor' ? 1 : 0 };
  if (args[0] !== 'show') throw new Error('Unexpected Git command');
  const value = blobs.get(args[1]);
  return { status: value === undefined ? 128 : 0, stdout: Buffer.from(value ?? '') };
} } });
const { checkFoundation } = await import('../history.mjs');
checkFoundation(root);
