// Current finite-experiment review, actual Git bytes and retained physical
// observations. No local record is promoted to authenticated main evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree, hash} from './inputs.mjs';
import {isolatedContract, isolatedExperimentDigest, isolatedExperimentPaths, matchesIsolatedContract} from './isolated-contract.mjs';
import {mutationIds} from './mutation-inventory.mjs';
import {checkIsolatedInputs, checkIsolatedResult, snapshotFromGit, imageRuntime} from './isolated-runtime.mjs';
import {historicalIsolatedFixture} from './historical-isolated-fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const tree = gitTree(root, isolatedContract.reviewRevision);
const originalBytes = gunzipSync(readFileSync(join(root,
  'docs/reviews/evidence/2026-10-06-local-isolated-session-8bbe08fca.json.gz')), {maxOutputLength: 8 * 1024 * 1024});
assert.equal(hash(originalBytes), '52d9e7931fe6a3b14d2b00a51094f4f83f4161363440360ab22b207d33afb6aa');
const original = JSON.parse(originalBytes);
const originalConsumer = await historicalIsolatedFixture(root, original.revision);

test('the reviewed current experiment matches actual Git and every experiment file in the retained real image', () => {
  assert.equal(isolatedExperimentDigest(tree), isolatedContract.experimentDigest);
  assert.equal(original.prepared.manifest.experimentDigest, isolatedContract.experimentDigest);
  const imageInputs = new Map(original.prepared.manifest.root.entries.map(entry => [entry.path, entry]));
  for (const path of isolatedExperimentPaths) {
    const entry = imageInputs.get(`source/${path}`), bytes = tree.read(path);
    assert.equal(entry?.kind, 'file', path);
    assert.equal(entry.digest, hash(bytes), path);
    assert.equal(entry.bytes, bytes.length, path);
    assert.equal(entry.mode, Number.parseInt(tree.entries.get(path).mode.slice(-3), 8), path);
  }
  const originalTree = gitTree(root, original.revision);
  assert.equal(original.authority, 'local-physical-acceptance');
  assert.equal(original.reuseAuthorized, false);
  assert(originalConsumer.checkIsolatedInputs({runtime: original.prepared.runtime, manifest: original.prepared.manifest, tree: originalTree, local: true}));
  assert(originalConsumer.checkIsolatedResult({payload: original.answer.payload, manifest: original.prepared.manifest, before: originalConsumer.snapshotFromGit(originalTree)}));
  assert.throws(() => checkIsolatedInputs({runtime: original.prepared.runtime,
    manifest: original.prepared.manifest, tree: originalTree, local: true}), /Wrong reviewed source cohort/u);
  assert.deepEqual(original.answer.payload.report.results.map(entry => entry.id).sort(), [...mutationIds].sort());
  // The actual local kernel/image remain outside the Actions contract.
  assert.equal(matchesIsolatedContract(original.prepared.manifest), false);
});

const reviewedEnvironment = () => ({experimentDigest: isolatedContract.experimentDigest,
  toolchainDigest: isolatedContract.toolchainDigest, hostImage: isolatedContract.hostImage,
  platformInputs: {kernelRelease: isolatedContract.kernelRelease}});

test('the old experiment and any later changed fixture remain unreviewed', () => {
  const descriptor = reviewedEnvironment();
  assert(matchesIsolatedContract(descriptor)); // Contract predicate fixture, not physical acceptance.
  const old = gitTree(root, '2034069ff171d09684b43cba21e9e9552dc3aa69');
  assert.equal(matchesIsolatedContract({...descriptor, experimentDigest: isolatedExperimentDigest(old)}), false);
  for (const path of isolatedExperimentPaths) {
    const changed = {...tree, read: input => input === path
      ? Buffer.concat([tree.read(input), Buffer.from('\n// unreviewed experiment change\n')]) : tree.read(input)};
    assert.equal(matchesIsolatedContract({...descriptor, experimentDigest: isolatedExperimentDigest(changed)}), false, path);
  }
});

test('refreshing the finite experiment does not relax toolchain, host or kernel conditions', () => {
  const descriptor = reviewedEnvironment();
  for (const changed of [
    {...descriptor, toolchainDigest: '0'.repeat(64)},
    {...descriptor, hostImage: 'another-image'},
    {...descriptor, platformInputs: {kernelRelease: 'another-kernel'}},
  ]) assert.equal(matchesIsolatedContract(changed), false);
});

test('CPU observations remain bound independently of the reviewed experiment files', () => {
  const manifest = original.prepared.manifest;
  const before = imageRuntime(manifest, {local: true});
  const changed = {...manifest, platformInputs: {...manifest.platformInputs, models: ['another CPU']}};
  assert.notEqual(encode(imageRuntime(changed, {local: true})), encode(before));
  const payload = {...original.answer.payload, platformInputs: changed.platformInputs};
  assert.throws(() => checkIsolatedResult({payload, manifest,
    before: snapshotFromGit(gitTree(root, original.revision))}), /Changed kernel\/CPU execution profile/u);
});
