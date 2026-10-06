// Replay the retained local physical original through the real scientific
// consumer. This neither invents Actions provenance nor executes a new campaign.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree, hash} from './inputs.mjs';
import {checkLocalImageDefinition, localIsolatedRunArguments} from './isolation.mjs';
import {checkIsolatedInputs, checkIsolatedResult, snapshotFromGit} from './isolated-runtime.mjs';
import {historicalIsolatedFixture} from './historical-isolated-fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const originals = [
  ['b34f6e544', 'b34f6e5445b731584729a1f8c09ec8c2404ccde6', '9a2e83e9be1396bedc7410fa11b48a8e8942c39f80098f7baa4b238969454c04'],
  ['fc2962f43', 'fc2962f43431e5c4c86cb47970251aa4c7c7f98c', 'e61d9c3c69c012fe4613644e3bc7b084ec402b6506aad4bf569660ab1a429ee4'],
  ['8bbe08fca', '8bbe08fca045be6c00a64eb5a68889295082c67c', '52d9e7931fe6a3b14d2b00a51094f4f83f4161363440360ab22b207d33afb6aa'],
  ['9a083b1d3', '9a083b1d32621b73a89e223c0c6cb1a0be3d3d29', '48db50ef669ce6ff8b92ad6d80f30b094a82619068a3791ac25e1e19448d21d7'],
];

for (const [name, revision, digest] of originals) {
  const currentPolicy = name === '9a083b1d3';
  const date = currentPolicy ? '2026-10-07' : '2026-10-06';
  const compressed = readFileSync(join(root, `docs/reviews/evidence/${date}-local-isolated-session-${name}.json.gz`));
  const bytes = gunzipSync(compressed, {maxOutputLength: 8 * 1024 * 1024});
  assert.equal(hash(bytes), digest);
  const original = JSON.parse(bytes);
  const consumer = currentPolicy ? {checkIsolatedInputs, checkIsolatedResult, snapshotFromGit}
    : await historicalIsolatedFixture(root, revision);
  const tree = gitTree(root, revision), before = consumer.snapshotFromGit(tree);

  const consume = record => {
    assert.equal(record.authority, 'local-physical-acceptance'); assert.equal(record.reuseAuthorized, false);
    assert.equal(record.revision, revision);
    const {prepared, answer} = record;
    assert.equal(record.manifestDigest, hash(JSON.stringify(prepared.manifest)));
    assert.equal(answer.owner, prepared.owner);
    consumer.checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree, local: true});
    checkLocalImageDefinition({image: answer.imageDefinition, imageId: answer.imageId, owner: answer.owner});
    assert.equal(encode(answer.arguments), encode(localIsolatedRunArguments({imageId: answer.imageId,
      owner: answer.owner, cidFile: join(prepared.context, 'container.id')})));
    return consumer.checkIsolatedResult({payload: answer.payload, manifest: prepared.manifest, before});
  };

  test(`${name}: the immutable real local image original is accepted with all 13 logs and restored bytes`, () => {
    assert(consume(original));
    assert.equal(original.answer.payload.report.results.length, 13);
    assert.throws(() => consumer.checkIsolatedInputs({runtime: original.prepared.runtime,
      manifest: original.prepared.manifest, tree}), /authority/u);
  });

  test(`${name}: the historical real image cannot be applied after a product input changes`, () => {
    const path = 'src/bounded_execution/session.mbt';
    const changed = {entries: tree.entries, read: input => input === path ? Buffer.concat([tree.read(input), Buffer.from('\n// changed candidate input\n')]) : tree.read(input)};
    assert.throws(() => consumer.checkIsolatedInputs({runtime: original.prepared.runtime,
      manifest: original.prepared.manifest, tree: changed, local: true}), /Wrong reviewed source cohort/u);
    assert(consume(original)); // The original remains valid for its actual source.
  });

  test(`${name}: tampering cannot substitute compile failure, missing observations or failed restoration`, () => {
    for (const alter of [
      r => r.reuseAuthorized = true,
      r => r.answer.payload.restored = false,
      r => delete r.answer.payload.logs['stale-token-reuse'],
      r => r.answer.payload.logs['stale-token-reuse'] = 'Error: [123] Compilation failed\n',
      r => r.answer.payload.report.results[0].failureCount = 0,
      r => r.prepared.runtime.unresolved = [],
    ]) {
      const changed = structuredClone(original); alter(changed); assert.throws(() => consume(changed));
    }
  });

  if (!currentPolicy) test(`${name}: a historical cohort cannot be relabeled as the current input policy`, () => {
    assert.throws(() => checkIsolatedInputs({runtime: original.prepared.runtime,
      manifest: original.prepared.manifest, tree, local: true}), /Wrong reviewed source cohort/u);
  });
}
