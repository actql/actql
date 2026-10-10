import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {composeFoundation} from './foundation.mjs';
import {FoundationRepository, DECLARATION_DIRECTORY, PROTECTED_PATHS, RENAME, sha256} from './fixtures/foundation-repository.mjs';

const encode = value => `${JSON.stringify(value, null, 2)}\n`;
const compose = repo => composeFoundation(repo.root, {checkpoint: repo.checkpoint, paths: PROTECTED_PATHS});
function copiedDeclaration(t, {copyMode = false, copyChanged = false, bundled = false, mergeChanges = false, originalBundled = false, oursWithMissingFile = false} = {}) {
  const repo = new FoundationRepository(t);
  repo.branch('original');
  repo.checkout('original');
  const value = 'export const rename = "new proof";\n';
  const source = repo.source({[RENAME]: value, ...(oursWithMissingFile ? {'original-only.txt': 'Must be normally merged\n'} : {})});
  const original = repo.declaration('original-source', source, [RENAME]);
  if (originalBundled) repo.write('original-bundled.txt', 'Bundled with original declaration\n');
  const author = repo.record(original);
  const raw = readFileSync(join(repo.root, repo.declarationPath(original.id)));
  repo.checkout('main');
  const copiedSource = repo.source({[RENAME]: value});
  repo.record(repo.declaration('independent-source', copiedSource, [RENAME]));
  repo.writeDeclaration(copyChanged ? {...original, changes: [{...original.changes[0], reason: 'Different copy'}]} : original);
  if (copyMode) repo.chmod(repo.declarationPath(original.id), 0o755);
  if (bundled) repo.write('unprotected.txt', 'Bundled change\n');
  const copy = repo.commit('Copy immutable declaration without original ancestry');
  const merge = repo.merge('original', mergeChanges ? {'unprotected.txt': 'Changed during merge\n'} : {},
    {ours: copyMode || copyChanged || oursWithMissingFile});
  repo.record(repo.declaration('reconcile-source', merge, [RENAME],
    {kind: 'resolution', inputs: ['independent-source', original.id]}));
  const binding = revision => ({revision, parents: repo.parents(revision)});
  const record = {version: 'actql-foundation-declaration-copy/0.1', id: 'reconcile-exact-copy',
    target: {id: original.id, digest: sha256(raw)}, original: binding(author), copy: binding(copy),
    reconciliation: binding(merge), reason: 'Preserve the exact copied introduction after its real source is normally merged'};
  const path = `${DECLARATION_DIRECTORY}-supplements/${record.id}.json`;
  const append = (next = record) => {repo.write(path, encode(next)); return repo.commit('Record exact copy reconciliation');};
  return {repo, record, append, raw, path, source, author, copy, merge};
}

test('exact copy reconciliation preserves original bytes and both introductions', t => {
  const f = copiedDeclaration(t);
  assert.throws(() => compose(f.repo), /must follow its source commit/);
  const introduced = f.append();
  const result = compose(f.repo);
  const original = result.declarations.find(value => value.id === f.record.target.id);
  assert.deepEqual(original.introductions, [f.author, f.copy].sort());
  assert.equal(original.digest, sha256(f.raw));
  assert.deepEqual(readFileSync(join(f.repo.root, f.repo.declarationPath(original.id))), f.raw);
  assert.deepEqual(result.supplements.find(value => value.id === f.record.id),
    {path: f.path, digest: sha256(encode(f.record)), introductions: [introduced], ...f.record});
});

for (const [name, mutate, expected] of [
  ['target digest', f => {f.record.target.digest = '0'.repeat(64);}, /Changed foundation copy target/],
  ['target name', f => {f.record.target.id = 'absent';}, /Missing.*copy target/],
  ['original commit', f => {f.record.original = {...f.record.copy};}, /original must follow/],
  ['copy commit', f => {f.record.copy = {...f.record.original};}, /original must follow|non-ancestral/],
  ['original parents', f => {f.record.original.parents = [];}, /copy parents/],
  ['copy parents', f => {f.record.copy.parents = [f.source];}, /copy parents/],
  ['merge parent order', f => {f.record.reconciliation.parents.reverse();}, /copy parents/],
  ['merge commit', f => {f.record.reconciliation = {...f.record.copy};}, /must merge its exact original/],
  ['unknown field', f => {f.record.ignoreAncestry = true;}, /copy fields/],
  ['extra binding field', f => {f.record.copy.mode = '100644';}, /copy copy fields/],
  ['empty rationale', f => {f.record.reason = '';}, /copy rationale/],
  ['unrelated commit', f => {f.record.original.revision = '0'.repeat(40);}, /Unrelated foundation copy commit/],
]) test(`exact copy rejects altered ${name}`, t => {
  const f = copiedDeclaration(t); mutate(f); f.append(); assert.throws(() => compose(f.repo), expected);
});

for (const [name, options, expected] of [
  ['copy contents', {copyChanged: true}, /Conflicting foundation declaration introduction/],
  ['copy mode', {copyMode: true}, /Invalid foundation declaration mode|Conflicting foundation declaration introduction/],
  ['bundled unprotected changes', {bundled: true}, /introduction contains other changes/],
  ['reconciliation tree changes', {mergeChanges: true}, /reconciliation changed the copied tree/],
  ['bundled original changes', {originalBundled: true}, /introduction contains other changes/],
  ['ours merge that drops an original file', {oursWithMissingFile: true}, /reconciliation differs from normal merge/],
]) test(`exact copy rejects ${name}`, t => {
  const f = copiedDeclaration(t, options); f.append(); assert.throws(() => compose(f.repo), expected);
});

test('copy record cannot replace the missing original ancestry', t => {
  const f = copiedDeclaration(t); f.repo.checkout(f.copy); f.append();
  assert.throws(() => compose(f.repo), /Unrelated foundation copy supporting revision/);
});
test('record introduced before reconciliation remains rejected after later merge', t => {
  const f = copiedDeclaration(t); f.repo.branch('reconciled'); f.repo.checkout(f.copy); f.append();
  f.repo.merge('reconciled'); assert.throws(() => compose(f.repo), /must follow reconciliation/);
});
test('unrecorded second non-ancestral copy is not exempted', t => {
  const f = copiedDeclaration(t); f.repo.branch('reconciled'); f.repo.checkout(f.repo.checkpoint);
  f.repo.writeDeclaration(JSON.parse(f.raw)); f.repo.commit('Another unrelated copy');
  f.repo.merge('reconciled'); f.append(); assert.throws(() => compose(f.repo), /must follow its source commit/);
});
test('duplicate copy records for a target are rejected', t => {
  const f = copiedDeclaration(t); f.append(); const next = {...f.record, id: 'second-copy-record'};
  f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${next.id}.json`, encode(next)); f.repo.commit('Duplicate copy binding');
  assert.throws(() => compose(f.repo), /Duplicate foundation copy target/);
});
test('copy reconciliation does not waive the ordinary changed-path obligations', t => {
  const f = copiedDeclaration(t); f.append(); const source = f.repo.source({[RENAME]: 'export const rename = "unlisted";\n'});
  assert.notEqual(source, f.source); assert.throws(() => compose(f.repo), /Unlisted foundation source change/);
});
