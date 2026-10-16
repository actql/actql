// Real Git histories retain both rejected raw records; no source/identity mock.
import assert from 'node:assert/strict';
import test from 'node:test';
import {composeFoundation} from './foundation.mjs';
import {overlappingBranches, FoundationRepository, RENAME, DISTINCT, PROTECTED_PATHS, PACKAGE, CI, DECLARATION_DIRECTORY, sha256} from './fixtures/foundation-repository.mjs';
const encode = value => `${JSON.stringify(value, null, 2)}\n`;
const compose = repo => composeFoundation(repo.root, {checkpoint: repo.checkpoint, paths: PROTECTED_PATHS});
function crissCross(t) {
  const repo = new FoundationRepository(t);
  repo.branch('right');
  const left = repo.source({[RENAME]: 'export const rename = "left";\n'});
  const rename = repo.declaration('left-source', left, [RENAME]); repo.record(rename);
  repo.branch('left-tip'); repo.checkout('right');
  const right = repo.source({[DISTINCT]: 'export const distinct = "right";\n'});
  const distinct = repo.declaration('right-source', right, [DISTINCT]); repo.record(distinct);
  repo.branch('right-tip'); repo.checkout('main'); repo.merge('right-tip');
  repo.checkout('right'); repo.merge('left-tip'); repo.checkout('main');
  const merge = repo.merge('right');
  const resolution = repo.declaration('resolve-criss-cross', merge, [RENAME, DISTINCT], {
    kind: 'resolution', inputs: [rename.id, distinct.id].sort(),
  });
  resolution.mergeBases = repo.git('merge-base', '--all', ...repo.parents(merge)).split('\n').sort();
  assert.equal(resolution.mergeBases.length, 2);
  return {repo, merge, rename, distinct, resolution};
}
function fixture(t, {replacement = true, early = false, multiBase = false, mutateEdited} = {}) {
  const f = multiBase ? crissCross(t) : overlappingBranches(t, {recordResolution: false});
  const {repo} = f;
  const original = {...f.resolution, inputs: [f.distinct.id]};
  const originalRevision = repo.record(original);
  const rawBinding = revision => {
    const path = repo.declarationPath(original.id);
    const line = repo.git('ls-tree', revision, '--', path);
    const [, mode, object] = /^(\d+) blob ([0-9a-f]{40})\t/.exec(line);
    return {revision, parents: repo.parents(revision), object,
      digest: repo.state(revision, path).digest, mode};
  };
  const before = rawBinding(originalRevision);
  const edited = {...original, inputs: [f.distinct.id, f.rename.id].sort()};
  mutateEdited?.(edited);
  const editRevision = repo.record(edited);
  const after = rawBinding(editRevision);
  const complete = repo.declaration('independent-complete-binding', f.merge, f.resolution.changes.map(change => change.path), {
    kind: 'resolution', inputs: [f.distinct.id, f.rename.id].sort(), reason: original.changes[0].reason,
  });
  if (multiBase) complete.mergeBases = [...f.resolution.mergeBases];
  const record = {version: 'actql-foundation-historical-input-edit/0.1', id: 'recover-exact-input-edit',
    target: {id: original.id, digest: after.digest}, original: before, edit: after,
    addedInput: {id: f.rename.id, digest: repo.state(originalRevision, repo.declarationPath(f.rename.id)).digest},
    replacement: {id: complete.id, digest: sha256(encode(complete))},
    reason: 'Retain rejected raw provenance and require an independently complete later binding'};
  const path = `${DECLARATION_DIRECTORY}-supplements/${record.id}.json`;
  if (replacement && !early) repo.record(complete);
  const publish = () => {repo.write(path, encode(record)); return repo.commit('Append exact historical disposition');};
  if (early) {publish(); repo.record(complete);}
  return {...f, original, edited, before, after, complete, record, path, publish};
}
test('a complete alias alone cannot erase the original historical edit', t => {
  const f = fixture(t); assert.throws(() => compose(f.repo), /Changed or removed foundation declaration/);
});
test('strict later recovery retains both raw failures and independently checks the complete lineage', t => {
  const f = fixture(t); f.publish();
  const result = compose(f.repo), recovery = result.historicalRecoveries[0];
  assert.equal(recovery.rawValidity, 'rejected');
  assert.deepEqual(recovery.rejectedProvenance.failures, ['visible_input_omitted', 'inherited_declaration_edited']);
  assert.deepEqual(recovery.rejectedProvenance.original, f.before);
  assert.deepEqual(recovery.rejectedProvenance.edit, f.after);
  assert.equal(result.declarations.find(value => value.id === f.original.id).rawValidity, 'rejected');
  assert.equal(result.declarations.find(value => value.id === f.complete.id).rawValidity, undefined);
  assert.equal(f.repo.git('show', `${f.before.revision}:${f.repo.declarationPath(f.original.id)}`), encode(f.original).trim());
  assert.equal(f.repo.git('show', `${f.after.revision}:${f.repo.declarationPath(f.original.id)}`), encode(f.edited).trim());
  f.repo.write('unrelated.txt', 'descendant\n'); f.repo.commit('Unrelated descendant');
  assert.deepEqual(compose(f.repo).historicalRecoveries, result.historicalRecoveries);
});
for (const [label, change, pattern] of [
  ['wrong original digest', f => f.record.original.digest = '0'.repeat(64), /raw binding/],
  ['wrong edited digest', f => f.record.edit.digest = '0'.repeat(64), /raw binding/],
  ['wrong original object', f => f.record.original.object = '0'.repeat(40), /raw binding/],
  ['wrong mode', f => f.record.edit.mode = '100755', /raw binding/],
  ['wrong ordered parent', f => f.record.edit.parents = [f.merge], /parents/],
  ['wrong edit revision', f => f.record.edit.revision = f.before.revision, /parents|raw binding|directly/],
  ['unknown target path', f => f.record.target.id = 'other-target', /raw binding/],
  ['changed current target digest', f => f.record.target.digest = '0'.repeat(64), /Changed historical recovery target/],
  ['wrong added dependency', f => f.record.addedInput.id = f.distinct.id, /already present/],
  ['wrong added dependency digest', f => f.record.addedInput.digest = '0'.repeat(64), /visible and unchanged/],
  ['wrong replacement digest', f => f.record.replacement.digest = '0'.repeat(64), /replacement/],
  ['missing replacement', f => f.record.replacement.id = 'absent-replacement', /replacement/],
  ['self replacement', f => f.record.replacement = {...f.record.target}, /Self-replacing/],
  ['empty rationale', f => f.record.reason = ' ', /rationale/],
  ['unrecognized authority field', f => f.record.allow = true, /fields/],
]) test(`exact historical disposition rejects ${label}`, t => {
  const f = fixture(t); change(f); f.publish(); assert.throws(() => compose(f.repo), pattern);
});
test('disposition before replacement is not a later independent recovery', t => {
  const f = fixture(t, {early: true}); assert.throws(() => compose(f.repo), /strictly follow replacement/);
});
test('co-introduced replacement and disposition are rejected', t => {
  const f = fixture(t, {replacement: false}); f.repo.writeDeclaration(f.complete); f.publish();
  assert.throws(() => compose(f.repo), /strictly follow replacement/);
});
test('replacement must strictly follow the edit and cannot be an earlier alias', t => {
  const f = fixture(t, {replacement: false});
  f.record.replacement = {id: f.rename.id, digest: f.record.addedInput.digest}; f.publish();
  assert.throws(() => compose(f.repo), /replacement/);
});
test('an independently incomplete replacement is refused, not covered by the disposition', t => {
  const f = fixture(t, {replacement: false}); f.complete.inputs = [f.distinct.id];
  f.record.replacement.digest = sha256(encode(f.complete)); f.repo.record(f.complete); f.publish();
  assert.throws(() => compose(f.repo), /replacement changes source binding/);
});
test('duplicate and reused disposition authority is rejected', t => {
  const f = fixture(t); f.publish();
  const other = {...f.record, id: 'duplicate-recovery'};
  f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${other.id}.json`, encode(other)); f.repo.commit('Duplicate disposition');
  assert.throws(() => compose(f.repo), /Duplicate historical recovery/);
});
for (const action of ['edit', 'remove']) test(`descendants cannot ${action} the frozen edited original`, t => {
  const f = fixture(t); f.publish();
  if (action === 'edit') {f.edited.changes[0].reason = 'Later edit'; f.repo.writeDeclaration(f.edited);}
  else f.repo.remove(f.repo.declarationPath(f.edited.id));
  f.repo.commit('Invalid later original change');
  assert.throws(() => compose(f.repo), /Changed historical recovery target/);
});
test('an unrelated invalid alias is not excused by a valid historical recovery', t => {
  const f = fixture(t); f.publish();
  f.repo.record({...f.edited, id: 'unrelated-incomplete', inputs: []});
  assert.throws(() => compose(f.repo), /Incomplete or ambiguous foundation resolution inputs/);
});
test('recovery cannot acquire later normalization or supplement authority', t => {
  const f = fixture(t); f.publish();
  const record = {version: 'actql-foundation-resolution-supplement/0.1', id: 'not-late',
    target: {...f.record.target}, inputs: [f.rename.id], reason: 'Attempt to reuse ordinary repair'};
  f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${record.id}.json`, encode(record)); f.repo.commit('Invalid additional repair');
  assert.throws(() => compose(f.repo), /unsupplemented bindings/);
});

test('recovered criss-cross preserves both actual maximal bases and every protected obligation', t => {
  const f = fixture(t, {multiBase: true}); f.publish();
  const report = compose(f.repo), integration = report.integrations.find(value => value.revision === f.merge);
  assert.deepEqual(integration.mergeBases, f.resolution.mergeBases);
  assert.deepEqual(integration.obligations.map(value => value.path), [DISTINCT, RENAME].sort());
  for (const obligation of integration.obligations) {
    assert.deepEqual(obligation.grounds.map(value => value.mergeBase), f.resolution.mergeBases);
  }
  assert.equal(report.historicalRecoveries[0].rawValidity, 'rejected');
});
for (const [label, mutateEdited, pattern] of [
  ['another field edit', value => value.changes[0].reason = 'Changed rationale', /fields other than inputs/],
  ['input deletion', value => value.inputs = [], /exactly one input/],
  ['input reordering', value => value.inputs.reverse(), /Noncanonical historical recovery inputs/],
  ['extra input', value => value.inputs.push('unknown-extra'), /exactly one input|Noncanonical historical recovery inputs/],
  ['base deletion', value => value.mergeBases.pop(), /fields other than inputs/],
]) test(`historical disposition rejects ${label} in raw edited bytes`, t => {
  // Mutating a shallow shared object would also alter the fixture's original;
  // the real original Git bytes, not either in-memory object, are authoritative.
  const f = fixture(t, {multiBase: true, mutateEdited}); f.publish();
  assert.throws(() => compose(f.repo), pattern);
});
test('a non-descendant replacement branch carrying the raw original is refused as ambiguous', t => {
  const f = fixture(t, {replacement: false});
  f.repo.branch('early-replacement', f.before.revision); f.repo.checkout('early-replacement');
  f.repo.record(f.complete); f.repo.checkout('main'); f.repo.merge('early-replacement'); f.publish();
  assert.throws(() => compose(f.repo), /Ambiguous foundation declaration/);
});

for (const chained of [false, true]) test(`historical recovery rejects ${chained ? 'chained targets' : 'reused independent replacement'}`, t => {
  const f = fixture(t);
  const nextOriginal = {...f.original, id: 'another-rejected-original'};
  const originalRevision = f.repo.record(nextOriginal);
  const describe = revision => {
    const path = f.repo.declarationPath(nextOriginal.id);
    const [, mode, object] = /^(\d+) blob ([0-9a-f]{40})\t/.exec(f.repo.git('ls-tree', revision, '--', path));
    return {revision, parents: f.repo.parents(revision), object, digest: f.repo.state(revision, path).digest, mode};
  };
  const original = describe(originalRevision);
  f.repo.record({...nextOriginal, inputs: [...f.edited.inputs]});
  const edit = describe(f.repo.head());
  const other = {...f.record, id: 'other-disposition', target: {id: nextOriginal.id, digest: edit.digest},
    original, edit, replacement: chained ? {...f.record.target} : {...f.record.replacement}};
  f.publish();
  f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${other.id}.json`, encode(other)); f.repo.commit('Invalid reusable disposition');
  assert.throws(() => compose(f.repo), chained ? /Chained historical recovery/ : /Reused historical recovery replacement/);
});
