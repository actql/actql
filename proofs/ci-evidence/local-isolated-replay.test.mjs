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

const root = fileURLToPath(new URL('../../', import.meta.url));
const compressed = readFileSync(join(root, 'docs/reviews/evidence/2026-10-06-local-isolated-session-fc2962f43.json.gz'));
const bytes = gunzipSync(compressed, {maxOutputLength: 8 * 1024 * 1024});
assert.equal(hash(bytes), 'e61d9c3c69c012fe4613644e3bc7b084ec402b6506aad4bf569660ab1a429ee4');
const original = JSON.parse(bytes);
const tree = gitTree(root, original.revision), before = snapshotFromGit(tree);

const consume = record => {
  assert.equal(record.authority, 'local-physical-acceptance'); assert.equal(record.reuseAuthorized, false);
  assert.equal(record.revision, 'fc2962f43431e5c4c86cb47970251aa4c7c7f98c');
  const {prepared, answer} = record;
  assert.equal(record.manifestDigest, hash(JSON.stringify(prepared.manifest)));
  assert.equal(answer.owner, prepared.owner);
  checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree, local: true});
  checkLocalImageDefinition({image: answer.imageDefinition, imageId: answer.imageId, owner: answer.owner});
  assert.equal(encode(answer.arguments), encode(localIsolatedRunArguments({imageId: answer.imageId,
    owner: answer.owner, cidFile: join(prepared.context, 'container.id')})));
  return checkIsolatedResult({payload: answer.payload, manifest: prepared.manifest, before});
};

test('the immutable real local image original is accepted by the shared consumer with all 13 logs and restored bytes', () => {
  assert(consume(original));
  assert.equal(original.answer.payload.report.results.length, 13);
  assert.throws(() => checkIsolatedInputs({runtime: original.prepared.runtime,
    manifest: original.prepared.manifest, tree}), /authority/u);
});

test('the historical real image cannot be applied after a product input changes', () => {
  const path = 'src/bounded_execution/session.mbt';
  const changed = {entries: tree.entries, read: input => input === path ? Buffer.concat([tree.read(input), Buffer.from('\n// changed candidate input\n')]) : tree.read(input)};
  assert.throws(() => checkIsolatedInputs({runtime: original.prepared.runtime,
    manifest: original.prepared.manifest, tree: changed, local: true}), /Wrong reviewed source cohort/u);
  assert(consume(original)); // The original remains valid for its actual source.
});

test('tampering with the real original cannot substitute compile failure, missing observations or failed restoration', () => {
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
