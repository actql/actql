import assert from 'node:assert/strict';
import { readFileSync, renameSync, symlinkSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { composeFoundation, foundationSourceBinding, foundationMergeObligations } from './foundation.mjs';
import { ADDED, CI, DECLARATION_DIRECTORY, DISTINCT, FoundationRepository, PACKAGE,
  PROTECTED_PATHS, RENAME, ciBytes, disjointBranches, olderInFlightBranch, overlappingBranches,
  packageBytes, sha256, singleChange, threePullRequestBranches } from './fixtures/foundation-repository.mjs';

const compose = (repo, options = {}) => composeFoundation(repo.root,
  { checkpoint: repo.checkpoint, paths: PROTECTED_PATHS, ...options });
const rejects = (repo, options) => assert.throws(() => compose(repo, options),
  /foundation|declaration|merge|Git|changed|Uncommitted|ENOENT|JSON|Unexpected|digest|mode|rationale|parent/i);
const file = (aggregate, path) => aggregate.files.find(entry => entry.path === path);
const declaration = (aggregate, id) => aggregate.declarations.find(entry => entry.id === id);

function lateResolution(t, { knownBeforeOriginal = false, twoLateGroups = false } = {}) {
  const repo = new FoundationRepository(t);
  repo.branch('late');
  const leftSource = repo.source({ [PACKAGE]: packageBytes({ left: 'node left.mjs' }) });
  const left = repo.declaration('left-registration', leftSource, [PACKAGE]);
  repo.record(left);
  repo.checkout('late');
  const rightSource = repo.source({ [PACKAGE]: packageBytes({ right: 'node right.mjs' }) });
  const right = repo.declaration('right-registration', rightSource, [PACKAGE]);
  const late = [right];
  if (twoLateGroups) {
    const next = repo.source({ [PACKAGE]: packageBytes({ right: 'node right.mjs', extra: 'node extra.mjs' }) });
    late.push(repo.declaration('extra-registration', next, [PACKAGE]));
  }
  if (knownBeforeOriginal) repo.record(right);
  repo.checkout('main');
  const merge = repo.merge('late', { [PACKAGE]: packageBytes({ left: 'node left.mjs', right: 'node right.mjs',
    ...(twoLateGroups ? { extra: 'node extra.mjs' } : {}) }) });
  const original = repo.declaration('original-resolution', merge, [PACKAGE], { kind: 'resolution', inputs: [left.id] });
  const originalIntroduction = repo.record(original);
  const originalBytes = readFileSync(join(repo.root, repo.declarationPath(original.id)));
  for (const value of late) if (!knownBeforeOriginal || value !== right) repo.record(value);
  const supplement = { version: 'actql-foundation-resolution-supplement/0.1', id: 'complete-late-resolution',
    target: { id: original.id, digest: sha256(originalBytes) },
    inputs: late.map(value => value.id).sort(), reason: 'Bind receipts introduced after the immutable original' };
  const supplementPath = `${DECLARATION_DIRECTORY}-supplements/${supplement.id}.json`;
  const record = (value = supplement) => {
    repo.write(supplementPath, `${JSON.stringify(value, null, 2)}\n`);
    return repo.commit('Append exact late dependency supplement');
  };
  return { repo, original, originalIntroduction, originalBytes, supplement, supplementPath, record, right };
}

test('late receipt supplement closes dependency coverage while preserving original bytes and introduction', t => {
  const fixture = lateResolution(t);
  assert.throws(() => compose(fixture.repo), /Incomplete or ambiguous foundation resolution inputs/);
  const introduction = fixture.record();
  const aggregate = compose(fixture.repo);
  const original = declaration(aggregate, fixture.original.id);
  assert.deepEqual(original.inputs, ['left-registration']);
  assert.deepEqual(original.introductions, [fixture.originalIntroduction]);
  assert.equal(original.digest, sha256(fixture.originalBytes));
  assert.deepEqual(readFileSync(join(fixture.repo.root, original.path)), fixture.originalBytes);
  assert.deepEqual(aggregate.supplements[0].introductions, [introduction]);
  assert.deepEqual(aggregate.supplements[0].target, fixture.supplement.target);
  assert.deepEqual(aggregate.integrations[0].supplements, ['complete-late-resolution']);
});

for (const [name, edit, pattern] of [
  ['wrong original digest', value => { value.target.digest = '0'.repeat(64); }, /Changed foundation supplement original/],
  ['unknown target', value => { value.target.id = 'missing'; }, /supplement target/],
  ['non-resolution target', value => { value.target.id = 'right-registration'; }, /supplement target/],
  ['unknown dependency', value => { value.inputs = ['missing']; }, /supplement inputs/],
  ['self cycle', value => { value.inputs = ['original-resolution']; }, /cyclic foundation supplement dependency/],
  ['redundant original dependency', value => { value.inputs = ['left-registration', 'right-registration']; }, /Redundant foundation supplement dependency/],
  ['duplicate dependency', value => { value.inputs.push(value.inputs[0]); }, /Noncanonical foundation supplement inputs/],
  ['empty dependencies', value => { value.inputs = []; }, /empty foundation supplement inputs/],
  ['undeclared field', value => { value.bypass = true; }, /foundation supplement fields/],
]) test(`late receipt supplement rejects ${name}`, t => {
  const fixture = lateResolution(t);
  const value = structuredClone(fixture.supplement);
  edit(value);
  fixture.record(value);
  assert.throws(() => compose(fixture.repo), pattern);
});

test('late receipt supplement rejects omission of one of two required late source groups', t => {
  const fixture = lateResolution(t, { twoLateGroups: true });
  fixture.supplement.inputs = [fixture.right.id];
  fixture.record();
  assert.throws(() => compose(fixture.repo), /Incomplete or ambiguous foundation resolution inputs/);
});

test('late receipt supplement cannot excuse an originally visible omitted dependency', t => {
  const fixture = lateResolution(t, { knownBeforeOriginal: true });
  fixture.record();
  assert.throws(() => compose(fixture.repo), /Incomplete original foundation resolution inputs/);
});

test('late receipt supplement rejects a downstream source dependency', t => {
  const fixture = lateResolution(t);
  const source = fixture.repo.source({ [PACKAGE]: packageBytes({ unrelated: 'node unrelated.mjs' }) });
  const later = fixture.repo.declaration('later-registration', source, [PACKAGE]);
  fixture.repo.record(later);
  fixture.supplement.inputs = [later.id];
  fixture.record();
  assert.throws(() => compose(fixture.repo), /Non-ancestral or cyclic foundation supplement dependency/);
});

test('late receipt supplement cannot legitimize a changed original declaration', t => {
  const fixture = lateResolution(t);
  fixture.original.inputs.push(fixture.right.id);
  fixture.repo.record(fixture.original);
  fixture.supplement.target.digest = sha256(readFileSync(join(fixture.repo.root, fixture.repo.declarationPath(fixture.original.id))));
  fixture.record();
  assert.throws(() => compose(fixture.repo), /Changed or removed foundation declaration/);
});

test('late receipt supplement remains immutable after introduction', t => {
  const fixture = lateResolution(t);
  fixture.record();
  fixture.supplement.reason = 'Rewritten historical review rationale';
  fixture.record();
  assert.throws(() => compose(fixture.repo), /Changed or removed foundation declaration/);
});

test('late receipt supplement survives an unrelated later commit', t => {
  const fixture = lateResolution(t);
  const introduction = fixture.record();
  const before = compose(fixture.repo);
  fixture.repo.write('unrelated.txt', 'Independent later documentation\n');
  fixture.repo.commit('Add unrelated documentation after supplementation');
  const after = compose(fixture.repo);
  assert.deepEqual(after.supplements, before.supplements);
  assert.deepEqual(after.supplements.find(value => value.id === fixture.supplement.id).introductions, [introduction]);
  assert.deepEqual(declaration(after, fixture.original.id), declaration(before, fixture.original.id));
  assert.equal(after.sourceRevision, fixture.repo.head());
});

test('late receipt supplement survives another legitimate supplement on a different resolution', t => {
  const fixture = lateResolution(t);
  fixture.record();
  const before = compose(fixture.repo);
  const repo = fixture.repo;
  repo.branch('second-late');
  const leftSource = repo.source({ [CI]: ciBytes(['check:left']) });
  const left = repo.declaration('second-left-registration', leftSource, [CI]);
  repo.record(left);
  repo.checkout('second-late');
  const rightSource = repo.source({ [CI]: ciBytes(['check:right']) });
  const right = repo.declaration('second-right-registration', rightSource, [CI]);
  repo.checkout('main');
  const merge = repo.merge('second-late', { [CI]: ciBytes(['check:left', 'check:right']) });
  const original = repo.declaration('second-resolution', merge, [CI], { kind: 'resolution', inputs: [left.id] });
  repo.record(original);
  repo.record(right);
  const originalBytes = readFileSync(join(repo.root, repo.declarationPath(original.id)));
  const supplement = { version: 'actql-foundation-resolution-supplement/0.1', id: 'complete-second-resolution',
    target: { id: original.id, digest: sha256(originalBytes) },
    inputs: [right.id], reason: 'Complete the independent CI resolution without changing existing receipts' };
  repo.write(`${DECLARATION_DIRECTORY}-supplements/${supplement.id}.json`, `${JSON.stringify(supplement, null, 2)}\n`);
  repo.commit('Append a second independently justified supplement');
  const after = compose(repo);
  assert.deepEqual(after.supplements.find(value => value.id === fixture.supplement.id),
    before.supplements.find(value => value.id === fixture.supplement.id));
  assert.deepEqual(after.supplements.find(value => value.id === supplement.id).target, supplement.target);
  assert.deepEqual(declaration(after, fixture.original.id), declaration(before, fixture.original.id));
  assert.deepEqual(readFileSync(join(repo.root, repo.declarationPath(original.id))), originalBytes);
});

test('an unchanged real Git checkpoint composes without declarations', t => {
  const repo = new FoundationRepository(t);
  const aggregate = compose(repo);
  assert.equal(aggregate.version, 'actql-composed-foundation/0.1');
  assert.equal(aggregate.sourceRevision, repo.checkpoint);
  assert.equal(aggregate.checkpoint, repo.checkpoint);
  assert.deepEqual(aggregate.declarations, []);
  assert.deepEqual(aggregate.integrations, []);
  assert.deepEqual(file(aggregate, PACKAGE), { path: PACKAGE, revision: repo.head(),
    digest: sha256(packageBytes()), mode: '100644' });
});

test('a declaration binds exact source, parent, digest, rationale and later introduction', t => {
  const { repo, revision, declaration: input, bytes } = singleChange(t);
  const introduction = repo.record(input);
  const aggregate = compose(repo);
  const actual = declaration(aggregate, input.id);
  assert.equal(actual.revision, revision);
  assert.deepEqual(actual.introductions, [introduction]);
  assert.deepEqual(actual.parents, [repo.checkpoint]);
  assert.deepEqual(actual.changes, input.changes);
  assert.equal(actual.digest, sha256(readFileSync(join(repo.root, actual.path))));
  assert.equal(file(aggregate, PACKAGE).digest, sha256(bytes));
});

test('disjoint branches compose without editing a shared aggregate or adding a resolution', t => {
  const { repo, rename, distinct, renameBytes, distinctBytes } = disjointBranches(t);
  const aggregate = compose(repo);
  assert.deepEqual(aggregate.declarations.map(entry => entry.id), ['extend-distinct', 'extend-rename']);
  assert.equal(file(aggregate, RENAME).digest, sha256(renameBytes));
  assert.equal(file(aggregate, DISTINCT).digest, sha256(distinctBytes));
  assert.deepEqual(declaration(aggregate, rename.id).changes, rename.changes);
  assert.deepEqual(declaration(aggregate, distinct.id).changes, distinct.changes);
  assert.deepEqual(aggregate.integrations, []);
});

test('overlapping package and CI registrations retain both rationales and validate integrated bytes', t => {
  const { repo, rename, distinct, resolution, merge, mergedPackage, mergedCI } = overlappingBranches(t);
  const aggregate = compose(repo);
  assert.equal(aggregate.sourceRevision, repo.head());
  assert.deepEqual(aggregate.declarations.map(entry => entry.id),
    ['register-distinct', 'register-rename', 'resolve-registrations']);
  assert.deepEqual(declaration(aggregate, rename.id).changes.map(change => change.reason),
    rename.changes.map(change => change.reason));
  assert.deepEqual(declaration(aggregate, distinct.id).changes.map(change => change.reason),
    distinct.changes.map(change => change.reason));
  assert.equal(file(aggregate, PACKAGE).digest, sha256(mergedPackage));
  assert.equal(file(aggregate, CI).digest, sha256(mergedCI));
  assert.notEqual(file(aggregate, PACKAGE).digest, rename.changes.find(change => change.path === PACKAGE).afterDigest);
  assert.notEqual(file(aggregate, PACKAGE).digest, distinct.changes.find(change => change.path === PACKAGE).afterDigest);
  assert.deepEqual(declaration(aggregate, resolution.id).inputs, ['register-distinct', 'register-rename']);
  assert.deepEqual(aggregate.integrations, [{ revision: merge, parents: repo.parents(merge),
    mergeBase: repo.checkpoint, declarations: [resolution.id] }]);
  assert.deepEqual(JSON.parse(mergedPackage).scripts, {
    'check:base': 'node base.mjs', 'check:rename': 'node rename.test.mjs', 'check:distinct': 'node distinct.test.mjs',
  });
});

test('adding a protected file declares the null parent identity', t => {
  const repo = new FoundationRepository(t);
  const bytes = 'export const evidence = "new";\n';
  const revision = repo.source({ [ADDED]: bytes });
  const input = repo.declaration('add-evidence', revision, [ADDED]);
  repo.record(input);
  const aggregate = compose(repo, { paths: [...PROTECTED_PATHS, ADDED] });
  assert.deepEqual(declaration(aggregate, input.id).changes[0].before,
    [{ revision: repo.checkpoint, digest: null, mode: null }]);
  assert.equal(file(aggregate, ADDED).digest, sha256(bytes));
});

test('identical Git inputs produce byte-identical output across roots, path order and repeated reads', t => {
  const first = overlappingBranches(t);
  const second = overlappingBranches(t);
  assert.notEqual(first.repo.root, second.repo.root);
  assert.equal(first.repo.head(), second.repo.head(), 'Fixture commits must be reproducible');
  const expected = JSON.stringify(compose(first.repo));
  assert.equal(JSON.stringify(compose(second.repo)), expected);
  assert.equal(JSON.stringify(compose(first.repo, { paths: [...PROTECTED_PATHS].reverse() })), expected);
  assert.equal(JSON.stringify(compose(first.repo)), expected);
  assert.ok(!expected.includes(first.repo.root));
  assert.ok(!expected.includes(second.repo.root));
  assert.deepEqual(compose(first.repo).files.map(entry => entry.path), [...PROTECTED_PATHS].sort());
  for (const input of compose(first.repo).declarations) {
    assert.deepEqual(input.changes.map(change => change.path), input.changes.map(change => change.path).sort());
  }
});

test('overlapping branch changes need an explicit merge resolution', t => {
  rejects(overlappingBranches(t, { recordResolution: false }).repo);
});

for (const [name, inputs] of [
  ['omitted incoming declaration', ['register-distinct']],
  ['unknown incoming declaration', ['register-distinct', 'register-rename', 'unknown-change']],
  ['duplicate incoming declaration', ['register-distinct', 'register-distinct', 'register-rename']],
  ['nondeterministic incoming order', ['register-rename', 'register-distinct']],
]) {
  test(`a merge resolution rejects ${name}`, t => {
    rejects(overlappingBranches(t, { inputs }).repo);
  });
}

test('a remaining declaration and resolution cannot implicitly authorize an undeclared branch change', t => {
  rejects(overlappingBranches(t, { includeRenameDeclaration: false, inputs: ['register-distinct'] }).repo);
});

test('removing a declaration after integration is rejected even if all merged source bytes remain', t => {
  const { repo, rename } = overlappingBranches(t);
  repo.remove(repo.declarationPath(rename.id));
  repo.commit('Remove one branch rationale');
  rejects(repo);
});

test('an ours-only merge cannot discard inherited declarations', t => {
  rejects(disjointBranches(t, { ours: true }).repo);
});

test('an ours-only merge retaining both declarations still cannot silently drop source changes', t => {
  rejects(disjointBranches(t, { ours: true, preserveDeclarations: true }).repo);
});

test('resolution evidence must describe actual merged bytes, not a desired union', t => {
  const fixture = overlappingBranches(t, { recordResolution: false,
    mergedPackage: packageBytes({ 'check:rename': 'node rename.test.mjs' }) });
  fixture.resolution.changes.find(change => change.path === PACKAGE).afterDigest = sha256(packageBytes({
    'check:rename': 'node rename.test.mjs', 'check:distinct': 'node distinct.test.mjs',
  }));
  fixture.repo.record(fixture.resolution);
  rejects(fixture.repo);
});

const invalidDeclarations = [
  ['wrong after digest', input => { input.changes[0].afterDigest = '0'.repeat(64); }],
  ['wrong before digest', input => { input.changes[0].before[0].digest = '0'.repeat(64); }],
  ['wrong prior revision', input => { input.changes[0].before[0].revision = input.revision; }],
  ['wrong prior mode', input => { input.changes[0].before[0].mode = '100755'; }],
  ['wrong after mode', input => { input.changes[0].afterMode = '100755'; }],
  ['wrong parents', input => { input.parents = [input.revision]; }],
  ['duplicate parents', input => { input.parents.push(input.parents[0]); }],
  ['missing parent identity', input => { input.changes[0].before = []; }],
  ['unknown supporting commit', input => { input.revision = 'f'.repeat(40); }],
  ['abbreviated supporting commit', input => { input.revision = input.revision.slice(0, 12); }],
  ['mutable supporting ref', input => { input.revision = 'HEAD'; }],
  ['uppercase digest', input => { input.changes[0].afterDigest = 'A'.repeat(64); }],
  ['unknown path', input => { input.changes[0].path = 'unknown.mjs'; }],
  ['path traversal', input => { input.changes[0].path = '../package.json'; }],
  ['duplicate change paths', input => { input.changes.push(structuredClone(input.changes[0])); }],
  ['empty changes', input => { input.changes = []; }],
  ['empty rationale', input => { input.changes[0].reason = '  \n'; }],
  ['invalid declaration ID', input => { input.id = 'INVALID_ID'; }],
  ['unknown schema version', input => { input.version = input.version.replace('/0.1', '/999'); }],
  ['unknown schema field', input => { input.approved = true; }],
  ['unknown change field', input => { input.changes[0].approved = true; }],
  ['change with resolution inputs', input => { input.inputs = []; }],
  ['resolution of a one-parent commit', input => { input.kind = 'resolution'; input.inputs = []; }],
];
for (const [name, mutate] of invalidDeclarations) {
  test(`real Git declaration rejects ${name}`, t => {
    const { repo, declaration: input } = singleChange(t);
    mutate(input);
    repo.record(input, 'register-rename');
    rejects(repo);
  });
}

test('independently validated aliases retain both records for one source binding', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.writeDeclaration(input);
  const alias = structuredClone(input);
  alias.id = 'second-rationale';
  alias.changes[0].reason = 'Independent retained rationale';
  repo.writeDeclaration(alias);
  repo.commit('Two declarations for one source commit');
  const aggregate = compose(repo);
  assert.deepEqual(aggregate.declarations.map(entry => entry.id), ['register-rename', 'second-rationale']);
  assert.deepEqual(declaration(aggregate, alias.id).changes, alias.changes);
});

test('duplicate IDs cannot hide behind separate declaration filenames', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.writeDeclaration(input);
  repo.writeDeclaration(input, 'second-rationale');
  repo.commit('Duplicate declaration ID');
  rejects(repo);
});

test('supporting source commits must be ancestors, not merely available Git objects', t => {
  const repo = new FoundationRepository(t);
  repo.branch('unrelated');
  repo.checkout('unrelated');
  const revision = repo.source({ [PACKAGE]: packageBytes({ 'check:other': 'node other.mjs' }) });
  const input = repo.declaration('unrelated-source', revision, [PACKAGE]);
  repo.checkout('main');
  repo.record(input);
  rejects(repo);
});

test('all changed paths in a source commit require evidence', t => {
  const repo = new FoundationRepository(t);
  const revision = repo.source({ [PACKAGE]: packageBytes({ 'check:rename': 'node rename.test.mjs' }),
    [CI]: ciBytes(['check:rename']) });
  repo.record(repo.declaration('partial-source', revision, [PACKAGE]));
  rejects(repo);
});

test('unchanged paths cannot be added as spurious declaration authority', t => {
  const { repo, revision, declaration: input } = singleChange(t);
  input.changes.push(repo.declaration('unused', revision, [CI]).changes[0]);
  repo.record(input);
  rejects(repo);
});

test('an undeclared intermediate edit is rejected even when a later declared commit reverts it', t => {
  const repo = new FoundationRepository(t);
  repo.source({ [PACKAGE]: packageBytes({ 'check:unreviewed': 'node unreviewed.mjs' }) }, 'Undeclared intermediate edit');
  const revert = repo.source({ [PACKAGE]: packageBytes() }, 'Restore checkpoint bytes');
  repo.record(repo.declaration('restore-package', revert, [PACKAGE]));
  assert.equal(repo.state(repo.head(), PACKAGE).digest, sha256(packageBytes()));
  rejects(repo);
});

test('declared edits and declared reverts remain present even when final bytes equal the checkpoint', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  const revision = repo.source({ [PACKAGE]: packageBytes() }, 'Revert declared registration');
  repo.record(repo.declaration('revert-registration', revision, [PACKAGE]));
  const aggregate = compose(repo);
  assert.deepEqual(aggregate.declarations.map(entry => entry.id), ['register-rename', 'revert-registration']);
  assert.equal(file(aggregate, PACKAGE).digest, sha256(packageBytes()));
});

test('committed source edits without any declaration fail closed', t => {
  rejects(singleChange(t).repo);
});

for (const [name, mutate] of [
  ['uncommitted protected source', repo => repo.write(PACKAGE, 'uncommitted source\n')],
  ['uncommitted protected mode', repo => repo.chmod(PACKAGE, 0o755)],
  ['uncommitted declaration bytes', (repo, input) => repo.write(repo.declarationPath(input.id), '{}\n')],
  ['missing declaration file', (repo, input) => repo.remove(repo.declarationPath(input.id))],
  ['untracked declaration', repo => repo.write(`${DECLARATION_DIRECTORY}/untracked.json`, '{}\n')],
]) {
  test(`composition rejects ${name}`, t => {
    const { repo, declaration: input } = singleChange(t);
    repo.record(input);
    mutate(repo, input);
    rejects(repo);
  });
}

test('declaration rationale is immutable after introduction', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  input.changes[0].reason = 'Rewrite the original rationale';
  repo.record(input);
  rejects(repo);
});

test('protected deletion is rejected even with a matching declaration attempt', t => {
  const repo = new FoundationRepository(t);
  const revision = repo.source({ [PACKAGE]: null });
  repo.record(repo.declaration('delete-package', revision, [PACKAGE]));
  rejects(repo);
});

test('protected executable-mode changes are rejected even with exact digest and mode evidence', t => {
  const repo = new FoundationRepository(t);
  repo.chmod(PACKAGE, 0o755);
  const revision = repo.commit('Make package executable');
  repo.record(repo.declaration('change-mode', revision, [PACKAGE]));
  rejects(repo);
});

test('a missing supporting Git commit object fails closed', t => {
  const { repo, revision, declaration: input } = singleChange(t);
  repo.record(input);
  repo.remove(`.git/objects/${revision.slice(0, 2)}/${revision.slice(2)}`);
  rejects(repo);
});

test('unknown checkpoints, mutable checkpoints and traversal paths fail closed', t => {
  const repo = new FoundationRepository(t);
  rejects(repo, { checkpoint: 'f'.repeat(40) });
  rejects(repo, { checkpoint: 'HEAD' });
  rejects(repo, { paths: ['../package.json'] });
  rejects(repo, { paths: [...PROTECTED_PATHS, PACKAGE] });
  rejects(repo, { directory: '../declarations' });
});

test('an older side branch with no protected changes can merge normally', t => {
  const repo = new FoundationRepository(t);
  repo.branch('older-side');
  repo.write('README.md', 'Establish migration checkpoint\n');
  repo.checkpoint = repo.commit('Migration checkpoint');
  repo.checkout('older-side');
  repo.write('older-side.txt', 'No protected edit is needed to exercise ancestry\n');
  repo.commit('Older side branch');
  repo.checkout('main');
  repo.merge('older-side');
  const aggregate = compose(repo);
  assert.equal(aggregate.sourceRevision, repo.head());
  assert.deepEqual(aggregate.declarations, []);
  assert.equal(file(aggregate, PACKAGE).digest, sha256(packageBytes()));
});

test('staged source drift cannot be hidden by restoring only the working file', t => {
  const { repo, declaration: input, bytes } = singleChange(t);
  repo.record(input);
  repo.write(PACKAGE, 'staged source rewrite\n');
  repo.git('add', '--', PACKAGE);
  repo.write(PACKAGE, bytes);
  rejects(repo);
});

test('staged declaration drift cannot be hidden by restoring only the working file', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  const path = repo.declarationPath(input.id);
  const original = readFileSync(join(repo.root, path));
  repo.write(path, '{}\n');
  repo.git('add', '--', path);
  repo.write(path, original);
  rejects(repo);
});

test('a declaration executable-bit change cannot hide behind unchanged bytes', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  repo.git('config', 'core.filemode', 'false');
  repo.chmod(repo.declarationPath(input.id), 0o755);
  rejects(repo);
});

test('a symlinked declaration directory is rejected even when its files match HEAD', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  const original = join(repo.root, DECLARATION_DIRECTORY);
  const moved = `${original}-moved`;
  renameSync(original, moved);
  symlinkSync(moved, original, 'dir');
  rejects(repo);
});

const HISTORICAL = 'proofs/relation-pipeline/reuse-baseline.json';
const HISTORICAL_BYTES = '{"version":"fixture/0.1","immutable":"original evidence"}\n';
function immutableFixture(t) {
  const repo = new FoundationRepository(t);
  repo.checkpoint = repo.source({ [HISTORICAL]: HISTORICAL_BYTES }, 'Pin immutable historical evidence');
  return { repo, immutable: [{ path: HISTORICAL, revision: repo.checkpoint }] };
}

test('pinned historical records preserve exact bytes alongside the composed source', t => {
  const { repo, immutable } = immutableFixture(t);
  const revision = repo.source({ [RENAME]: 'export const rename = "updated";\n' });
  repo.record(repo.declaration('extend-rename', revision, [RENAME]));
  const aggregate = compose(repo, { immutable });
  assert.equal(aggregate.sourceRevision, repo.head());
  assert.equal(readFileSync(join(repo.root, HISTORICAL), 'utf8'), HISTORICAL_BYTES);
});

test('a canonical immutable record can be introduced from an exact historical source path', t => {
  const { repo, immutable } = immutableFixture(t);
  const migratedPath = 'proofs/relation-pipeline/migration-checkpoint.json';
  repo.source({ [migratedPath]: HISTORICAL_BYTES }, 'Introduce exact-byte migration checkpoint');
  const aggregate = compose(repo, { immutable: [...immutable,
    { path: migratedPath, revision: repo.checkpoint, sourcePath: HISTORICAL }] });
  assert.equal(aggregate.sourceRevision, repo.head());
  assert.equal(readFileSync(join(repo.root, migratedPath), 'utf8'), HISTORICAL_BYTES);
});

test('committed historical edits are rejected when only working bytes are restored', t => {
  const { repo, immutable } = immutableFixture(t);
  repo.source({ [HISTORICAL]: '{"immutable":"rewritten"}\n' }, 'Rewrite historical evidence');
  repo.write(HISTORICAL, HISTORICAL_BYTES);
  rejects(repo, { immutable });
});

test('an immutable historical edit followed by a committed revert is still rejected', t => {
  const { repo, immutable } = immutableFixture(t);
  repo.source({ [HISTORICAL]: '{"immutable":"rewritten"}\n' }, 'Rewrite historical evidence');
  repo.source({ [HISTORICAL]: HISTORICAL_BYTES }, 'Restore historical evidence');
  rejects(repo, { immutable });
});

test('staged immutable-history drift is rejected after restoring working bytes', t => {
  const { repo, immutable } = immutableFixture(t);
  repo.write(HISTORICAL, '{"immutable":"staged rewrite"}\n');
  repo.git('add', '--', HISTORICAL);
  repo.write(HISTORICAL, HISTORICAL_BYTES);
  rejects(repo, { immutable });
});

test('deleting and reintroducing an immutable historical record is rejected', t => {
  const { repo, immutable } = immutableFixture(t);
  repo.source({ [HISTORICAL]: null }, 'Delete historical evidence');
  repo.source({ [HISTORICAL]: HISTORICAL_BYTES }, 'Reintroduce historical evidence');
  rejects(repo, { immutable });
});

test('a linked-worktree graft cannot hide an undeclared edit and revert', t => {
  const repo = new FoundationRepository(t);
  repo.source({ [PACKAGE]: 'undeclared edit\n' });
  repo.source({ [PACKAGE]: packageBytes() });
  repo.write('README.md', 'Unprotected final commit\n');
  const head = repo.commit('Unprotected final commit');
  const linked = join(repo.root, 'linked-worktree');
  repo.git('worktree', 'add', '--detach', linked, head);
  repo.write('.git/info/grafts', `${head} ${repo.checkpoint}\n`);
  assert.throws(() => composeFoundation(linked, { checkpoint: repo.checkpoint, paths: PROTECTED_PATHS }),
    /Grafted|foundation|Unlisted/i);
});

test('identical declaration files converge while retaining every independent introduction', t => {
  const { repo, revision, declaration: input } = singleChange(t);
  repo.branch('parallel', revision);
  repo.writeDeclaration(input);
  repo.write('left.txt', 'left introduction\n');
  const first = repo.commit('First introduction');
  repo.checkout('parallel');
  repo.writeDeclaration(input);
  repo.write('right.txt', 'right introduction\n');
  const second = repo.commit('Independent second introduction');
  repo.checkout('main');
  repo.merge('parallel');
  const aggregate = compose(repo);
  assert.deepEqual(declaration(aggregate, input.id).introductions, [first, second].sort());
  assert.equal(aggregate.declarations.length, 1);
});

test('an unprotected criss-cross records every base without a spurious declaration', t => {
  const repo = new FoundationRepository(t);
  repo.branch('right');
  repo.write('left.txt', 'left\n');
  repo.branch('left-tip', repo.commit('Left pre-merge'));
  repo.checkout('right');
  repo.write('right.txt', 'right\n');
  repo.branch('right-tip', repo.commit('Right pre-merge'));
  repo.checkout('main');
  repo.merge('right-tip');
  repo.checkout('right');
  repo.merge('left-tip');
  repo.checkout('main');
  const merge = repo.merge('right');
  const mergeBases = repo.git('merge-base', '--all', ...repo.parents(merge)).split('\n').sort();
  assert.equal(mergeBases.length, 2);
  assert.deepEqual(compose(repo).integrations, [{ revision: merge, parents: repo.parents(merge),
    mergeBases, obligations: [], declarations: [] }]);
});

function protectedCrissCross(t, { omit, mutate, record = true, reverse = false } = {}) {
  const repo = new FoundationRepository(t);
  repo.branch('right');
  const left = repo.source({ [RENAME]: 'export const rename = "left";\n' });
  repo.record(repo.declaration('left-source', left, [RENAME]));
  repo.branch('left-tip');
  repo.checkout('right');
  const right = repo.source({ [DISTINCT]: 'export const distinct = "right";\n' });
  repo.record(repo.declaration('right-source', right, [DISTINCT]));
  repo.branch('right-tip');
  repo.checkout('main');
  repo.merge('right-tip');
  repo.checkout('right');
  repo.merge('left-tip');
  repo.checkout(reverse ? 'right' : 'main');
  const merge = repo.merge(reverse ? 'main' : 'right');
  const mergeBases = repo.git('merge-base', '--all', ...repo.parents(merge)).split('\n').sort();
  assert.equal(mergeBases.length, 2);
  const resolution = repo.declaration('resolve-criss-cross', merge, [RENAME, DISTINCT].filter(path => path !== omit),
    { kind: 'resolution', inputs: ['left-source', 'right-source'] });
  resolution.mergeBases = mergeBases;
  mutate?.(resolution, repo);
  if (record) repo.record(resolution);
  return { repo, merge, mergeBases, resolution };
}

test('real criss-cross obligations retain every base and converge by full source identity', t => {
  const { repo, merge, mergeBases, resolution } = protectedCrissCross(t);
  const aggregate = compose(repo), integration = aggregate.integrations.find(entry => entry.revision === merge);
  assert.deepEqual(integration.mergeBases, mergeBases);
  assert(!Object.hasOwn(integration, 'mergeBase'));
  assert.deepEqual(integration.parents, repo.parents(merge));
  assert.deepEqual(integration.obligations.map(entry => entry.path), [DISTINCT, RENAME].sort());
  for (const obligation of integration.obligations) {
    assert.equal(obligation.revision, merge);
    assert.deepEqual(obligation.parents, repo.parents(merge));
    assert.deepEqual(obligation.grounds.map(ground => ground.mergeBase), mergeBases);
    assert.equal(obligation.grounds.filter(ground => ground.required).length, 1);
    for (const ground of obligation.grounds) {
      const object = repo.git('rev-parse', `${ground.mergeBase}:${obligation.path}`);
      assert.deepEqual(ground.base, { object, mode: '100644' });
    }
  }
  assert.deepEqual(foundationSourceBinding(resolution, ['left', 'right']).mergeBases, mergeBases);
  assert.equal(JSON.stringify(compose(repo)), JSON.stringify(aggregate));
  assert.equal(JSON.stringify(compose(repo, { paths: [...PROTECTED_PATHS].reverse() })), JSON.stringify(aggregate));
});

for (const omit of [RENAME, DISTINCT]) {
  test(`a real criss-cross rejects omission of the path exclusive to either base: ${omit}`, t => {
    const { repo } = protectedCrissCross(t, { omit });
    assert.throws(() => compose(repo), /Incomplete foundation changed paths/);
  });
}

for (const [name, mutate] of [
  ['missing entire base set', input => { delete input.mergeBases; }],
  ['omitted base', input => { input.mergeBases.pop(); }],
  ['extra nonmaximal base', (input, repo) => { input.mergeBases.push(repo.checkpoint); input.mergeBases.sort(); }],
  ['unknown base', input => { input.mergeBases[0] = 'f'.repeat(40); input.mergeBases.sort(); }],
  ['duplicate base', input => { input.mergeBases.push(input.mergeBases[0]); input.mergeBases.sort(); }],
  ['noncanonical base order', input => { input.mergeBases.reverse(); }],
  ['swapped parents', input => { input.parents.reverse(); }],
  ['swapped before identities', input => { input.changes[0].before.reverse(); }],
  ['missing input revision', input => { input.inputs.pop(); }],
]) {
  test(`a real criss-cross rejects ${name}`, t => {
    const { repo } = protectedCrissCross(t, { mutate });
    rejects(repo);
  });
}

test('a valid multi-base resolution cannot hide an alias with changed base grounds', t => {
  const { repo, resolution } = protectedCrissCross(t);
  const alias = { ...structuredClone(resolution), id: 'wrong-base-alias' };
  alias.mergeBases.pop();
  repo.record(alias);
  rejects(repo);
});

test('single-base declarations reject spurious multi-base metadata', t => {
  const { repo, resolution } = overlappingBranches(t, { recordResolution: false });
  resolution.mergeBases = [repo.checkpoint];
  repo.record(resolution);
  assert.throws(() => compose(repo), /Spurious foundation merge bases/);
});

test('reversing real merge parents preserves base obligations without erasing parent order', t => {
  const first = protectedCrissCross(t), reversed = protectedCrissCross(t, { reverse: true });
  const a = compose(first.repo).integrations.find(entry => entry.revision === first.merge);
  const b = compose(reversed.repo).integrations.find(entry => entry.revision === reversed.merge);
  assert.deepEqual(b.parents, [...a.parents].reverse());
  assert.deepEqual(b.mergeBases, a.mergeBases);
  assert.deepEqual(b.obligations.map(({ path, grounds }) => ({ path, grounds })),
    a.obligations.map(({ path, grounds }) => ({ path, grounds })));
});

for (const index of [0, 1]) {
  test(`a missing maximal-base commit ${index} fails closed`, t => {
    const { repo, mergeBases } = protectedCrissCross(t);
    const object = mergeBases[index];
    repo.remove(`.git/objects/${object.slice(0, 2)}/${object.slice(2)}`);
    rejects(repo);
  });
  test(`a missing protected blob from maximal base ${index} fails closed`, t => {
    const { repo, mergeBases } = protectedCrissCross(t);
    const object = repo.git('rev-parse', `${mergeBases[index]}:${RENAME}`);
    repo.remove(`.git/objects/${object.slice(0, 2)}/${object.slice(2)}`);
    rejects(repo);
  });
}

function publishedMultiBaseFixture() {
  const fixture = JSON.parse(readFileSync(new URL('./fixtures/multiple-merge-bases.json', import.meta.url)));
  const evaluations = fixture.mergeBases.map(mergeBase => ({ mergeBase,
    paths: fixture.paths.map(entry => ({ path: entry.path, before: structuredClone(entry.before), after: structuredClone(entry.after),
      base: structuredClone(entry.bases.find(base => base.revision === mergeBase).identity) })) }));
  return { fixture, evaluations };
}

test('published 19b0 identities require 5 and 20 obligations with a 21-path union', () => {
  const { fixture, evaluations } = publishedMultiBaseFixture();
  assert.equal(fixture.revision, '19b0b464b983695c68df60d601016bb25a4fd06d');
  assert.deepEqual(fixture.parents, ['4a4f4f10eb9723e3537c2b0fb444fca20dd28f33', '88fbcc95306abb4fc41f0d488bcc6d38ec19506d']);
  assert.deepEqual(fixture.mergeBases, ['8b21ddd3f4a17fcecbb9bcf5878082148af0aa99', '8baa87fc6b6cb7d7caa981cef1692c9d73d88318']);
  assert.equal(fixture.paths.length, 73);
  assert.deepEqual(fixture.expected.perBase.map(entry => entry.required.length), [5, 20]);
  for (const evaluation of evaluations) {
    const obligations = foundationMergeObligations(fixture.revision, fixture.parents, [evaluation.mergeBase], [evaluation]);
    assert.deepEqual(obligations.map(entry => entry.path), fixture.expected.perBase.find(entry => entry.revision === evaluation.mergeBase).required);
  }
  const combined = foundationMergeObligations(fixture.revision, fixture.parents, fixture.mergeBases, evaluations);
  assert.equal(combined.length, 21);
  assert.deepEqual(combined.map(entry => entry.path), fixture.expected.required);
  for (const obligation of combined) {
    assert.deepEqual(obligation.grounds.map(ground => ground.mergeBase), fixture.mergeBases);
    for (const ground of obligation.grounds) assert.deepEqual(ground.base,
      fixture.paths.find(entry => entry.path === obligation.path).bases.find(base => base.revision === ground.mergeBase).identity);
  }
  assert.deepEqual(foundationMergeObligations(fixture.revision, fixture.parents, [...fixture.mergeBases].reverse(),
    [...evaluations].reverse().map(value => ({ ...value, paths: [...value.paths].reverse() }))), combined);
});

for (const [name, mutate] of [
  ['one omitted base', values => values.pop()],
  ['base-one-exclusive obligation', values => { values[0].paths = values[0].paths.filter(entry => entry.path !== 'proofs/relation-pipeline/capacity/finish.mjs'); }],
  ['base-two-exclusive obligation', values => { values[1].paths = values[1].paths.filter(entry => entry.path !== 'proofs/relation-pipeline/workspaces.mjs'); }],
  ['inconsistent same-path source result', values => { values[1].paths[0].after.object = 'f'.repeat(40); }],
  ['inconsistent same-path parent identity', values => { values[1].paths[0].before.reverse(); }],
  ['inconsistent same-path mode', values => { values[1].paths[0].after.mode = '100755'; }],
]) {
  test(`multi-base obligation combination rejects ${name}`, () => {
    const { fixture, evaluations } = publishedMultiBaseFixture();
    const values = structuredClone(evaluations);
    mutate(values);
    assert.throws(() => foundationMergeObligations(fixture.revision, fixture.parents, fixture.mergeBases, values),
      /Incomplete|Inconsistent/);
  });
}

for (const omitPriorResolution of [false, true]) {
  test(`later resolutions preserve the complete prior rationale chain (omission=${omitPriorResolution})`, t => {
    const { repo } = overlappingBranches(t);
    repo.branch('second-round');
    const scripts = { 'check:rename': 'node rename.test.mjs', 'check:distinct': 'node distinct.test.mjs' };
    const left = repo.source({ [PACKAGE]: packageBytes({ ...scripts, 'check:left': 'node left.test.mjs' }) });
    repo.record(repo.declaration('left-again', left, [PACKAGE]));
    repo.checkout('second-round');
    const right = repo.source({ [PACKAGE]: packageBytes({ ...scripts, 'check:right': 'node right.test.mjs' }) });
    repo.record(repo.declaration('right-again', right, [PACKAGE]));
    repo.checkout('main');
    const bytes = packageBytes({ ...scripts, 'check:left': 'node left.test.mjs', 'check:right': 'node right.test.mjs' });
    const merged = repo.merge('second-round', { [PACKAGE]: bytes });
    const inputs = ['left-again', 'register-distinct', 'register-rename', 'resolve-registrations', 'right-again'];
    repo.record(repo.declaration('resolve-again', merged, [PACKAGE], { kind: 'resolution',
      inputs: omitPriorResolution ? inputs.filter(id => id !== 'resolve-registrations') : inputs }));
    if (omitPriorResolution) rejects(repo);
    else {
      const aggregate = compose(repo);
      assert.deepEqual(declaration(aggregate, 'resolve-again').inputs, inputs);
      assert.equal(aggregate.declarations.length, 6);
      assert.equal(aggregate.integrations.length, 2);
      assert.equal(file(aggregate, PACKAGE).digest, sha256(bytes));
    }
  });
}

test('PRs 172, 173 and 175 compose through two merges with all commands, CI and rationales retained', t => {
  const fixture = threePullRequestBranches(t);
  const aggregate = compose(fixture.repo);
  assert.deepEqual(aggregate.declarations.map(input => input.id), [
    'pr-172-public-check', 'pr-173-native-release', 'pr-175-capacity', 'resolve-all-three', 'resolve-public-native',
  ]);
  assert.deepEqual(JSON.parse(readFileSync(join(fixture.repo.root, PACKAGE), 'utf8')).scripts,
    { 'check:base': 'node base.mjs', ...fixture.scripts });
  assert.equal(file(aggregate, PACKAGE).digest, sha256(fixture.mergedPackage));
  assert.equal(file(aggregate, CI).digest, sha256(fixture.mergedCI));
  assert.deepEqual(declaration(aggregate, fixture.finalResolution.id).inputs, fixture.inputs);
  for (const input of [fixture.publicCheck, fixture.nativeRelease, fixture.capacity]) {
    const originalReasons = input.changes.map(change => change.reason).sort();
    assert.deepEqual(declaration(aggregate, input.id).changes.map(change => change.reason).sort(), originalReasons);
    assert.notEqual(file(aggregate, PACKAGE).digest, input.changes.find(change => change.path === PACKAGE).afterDigest);
  }
  assert.deepEqual(aggregate.integrations.map(integration => integration.revision).sort(),
    [fixture.firstMerge, fixture.secondMerge].sort());
});

for (const omitFinalInput of ['pr-172-public-check', 'resolve-public-native']) {
  test(`the three-PR integration rejects an omitted original or resolution rationale (${omitFinalInput})`, t => {
    rejects(threePullRequestBranches(t, { omitFinalInput }).repo);
  });
}

test('duplicate JSON object keys cannot silently replace declaration identity', t => {
  const { repo, declaration: input } = singleChange(t);
  const bytes = `${JSON.stringify(input, null, 2)}\n`
    .replace('"id": "register-rename",', '"id": "discarded-identity",\n  "id": "register-rename",');
  assert.equal(JSON.parse(bytes).id, input.id, 'Exercise a duplicate key normally lost by JSON.parse');
  repo.write(repo.declarationPath(input.id), bytes);
  repo.commit('Ambiguous JSON declaration');
  rejects(repo);
});

test('external Git diff configuration cannot hide staged protected source changes', t => {
  const { repo, declaration: input, bytes } = singleChange(t);
  repo.record(input);
  repo.write(PACKAGE, 'different staged bytes\n');
  repo.git('add', '--', PACKAGE);
  repo.write(PACKAGE, bytes);
  repo.git('config', 'diff.external', '/bin/true');
  repo.git('config', 'diff.trustExitCode', 'true');
  rejects(repo);
});

test('binary and CRLF source bytes are hashed exactly without line-ending normalization', t => {
  const repo = new FoundationRepository(t);
  const bytes = Buffer.from([0, 255, 128, 13, 10, 65, 13, 10]);
  const revision = repo.source({ [RENAME]: bytes });
  repo.record(repo.declaration('binary-evidence', revision, [RENAME]));
  assert.equal(file(compose(repo), RENAME).digest, sha256(bytes));
  repo.write(RENAME, Buffer.from([0, 255, 128, 10, 65, 10]));
  rejects(repo);
});

test('a protected source symlink is rejected even when the referent has exact committed bytes', t => {
  const { repo, declaration: input, bytes } = singleChange(t);
  repo.record(input);
  repo.write('matching-package.json', bytes);
  repo.remove(PACKAGE);
  symlinkSync('matching-package.json', join(repo.root, PACKAGE));
  rejects(repo);
});

test('an older in-flight branch keeps its original SHA while resolving against the frozen checkpoint', t => {
  const fixture = olderInFlightBranch(t);
  const aggregate = compose(fixture.repo, { immutable: fixture.immutable });
  assert.notEqual(fixture.fork, fixture.repo.checkpoint);
  assert.equal(fixture.repo.run(['merge-base', '--is-ancestor', fixture.repo.checkpoint, fixture.sideRevision]).status, 1,
    'The fixture must preserve a supporting commit outside checkpoint ancestry');
  assert.equal(declaration(aggregate, fixture.side.id).revision, fixture.sideRevision);
  assert.deepEqual(declaration(aggregate, fixture.side.id).parents, [fixture.fork]);
  assert.deepEqual(declaration(aggregate, fixture.resolution.id).inputs, [fixture.side.id]);
  assert.deepEqual(aggregate.declarations.map(input => input.id), ['old-side-native', 'resolve-old-in-flight']);
  assert.equal(file(aggregate, PACKAGE).digest, sha256(fixture.mergedPackage));
  assert.deepEqual(JSON.parse(fixture.mergedPackage).scripts, {
    'check:base': 'node base.mjs', 'check:public': 'node public-check.test.mjs', 'check:native': 'node native-release.test.mjs',
  });
  assert.equal(readFileSync(join(fixture.repo.root, fixture.historicalPath), 'utf8'), fixture.checkpointBytes);
  assert.equal(JSON.parse(fixture.checkpointBytes).reason, fixture.historicalReason);
  assert.deepEqual(aggregate.immutable, [{ path: fixture.historicalPath, revision: fixture.repo.checkpoint,
    digest: sha256(fixture.checkpointBytes) }]);
  assert.deepEqual(aggregate.integrations, [{ revision: fixture.merge, parents: fixture.repo.parents(fixture.merge),
    mergeBase: fixture.fork, declarations: [fixture.resolution.id] }]);
});

test('an old-fork merge resolution cannot authorize the omitted incoming source declaration', t => {
  const fixture = olderInFlightBranch(t, { recordSide: false });
  rejects(fixture.repo, { immutable: fixture.immutable });
});

test('an old-fork merge editing both sides of a protected path still requires a resolution', t => {
  const fixture = olderInFlightBranch(t, { recordResolution: false });
  rejects(fixture.repo, { immutable: fixture.immutable });
});

test('an unrelated root history remains rejected after allowing ordinary old-fork merges', t => {
  const repo = new FoundationRepository(t);
  repo.git('checkout', '--quiet', '--orphan', 'unrelated-root');
  repo.commit('Independent root with identical protected bytes');
  repo.checkout('main');
  repo.git('merge', '--allow-unrelated-histories', '--no-ff', '--no-commit', 'unrelated-root');
  repo.commit('Try to integrate unrelated root');
  rejects(repo);
});


// A valid representative must never mask an independently invalid alias.
for (const [name, mutate] of invalidDeclarations) {
  test(`convergence rejects an alias with ${name}`, t => {
    const { repo, declaration: input } = singleChange(t);
    repo.record(input);
    const alias = structuredClone(input);
    alias.id = 'alias';
    mutate(alias);
    repo.record(alias, 'alias');
    rejects(repo);
  });
}

test('convergence rejects a partial changed-path alias despite a complete record', t => {
  const repo = new FoundationRepository(t);
  const revision = repo.source({ [PACKAGE]: packageBytes({ extra: 'node extra.mjs' }), [CI]: ciBytes(['extra']) });
  repo.record(repo.declaration('complete', revision, [PACKAGE, CI]));
  repo.record(repo.declaration('partial', revision, [PACKAGE]));
  rejects(repo);
});

test('parallel same-path introductions independently require source ancestry', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.branch('unrelated-introduction', repo.checkpoint);
  repo.record(input);
  repo.checkout('unrelated-introduction');
  repo.record(input);
  repo.checkout('main');
  repo.merge('unrelated-introduction');
  rejects(repo);
});

test('parallel same-path introductions cannot disagree even only in rationale', t => {
  const { repo, revision, declaration: input } = singleChange(t);
  repo.branch('parallel-conflict', revision);
  repo.record(input);
  repo.checkout('parallel-conflict');
  const changed = structuredClone(input);
  changed.changes[0].reason = 'Conflicting independently published bytes';
  repo.record(changed);
  repo.checkout('main');
  repo.merge('parallel-conflict', { [repo.declarationPath(input.id)]: `${JSON.stringify(input, null, 2)}\n` });
  rejects(repo);
});

test('resolution aliases retain old input spelling and equivalent independent dependency grounds', t => {
  const { repo, rename, resolution, merge } = overlappingBranches(t);
  // Introduce a new spelling later: old immutable resolutions remain valid.
  const renameAlias = { ...structuredClone(rename), id: 'rename-alias' };
  repo.record(renameAlias);
  const resolutionAlias = { ...structuredClone(resolution), id: 'resolution-alias',
    inputs: ['register-distinct', 'rename-alias'] };
  resolutionAlias.changes.reverse(); // Path order is not binding; parent order is.
  repo.record(resolutionAlias);
  const aggregate = compose(repo);
  assert.deepEqual(declaration(aggregate, resolution.id).inputs, resolution.inputs);
  assert.deepEqual(declaration(aggregate, resolutionAlias.id).inputs, resolutionAlias.inputs);
  assert.deepEqual(aggregate.integrations.find(entry => entry.revision === merge).declarations,
    ['resolution-alias', 'resolve-registrations']);
  assert.equal(aggregate.declarations.length, 5);
});

for (const [name, mutate] of [
  ['ordered parents', input => { input.parents.reverse(); }],
  ['before identities', input => { input.changes[0].before.reverse(); }],
  ['missing dependency', input => { input.inputs.pop(); }],
  ['unknown dependency', input => { input.inputs.push('unknown'); }],
  ['duplicate raw dependency', input => { input.inputs.push(input.inputs[0]); input.inputs.sort(); }],
  ['unsorted dependencies', input => { input.inputs.reverse(); }],
  ['self dependency', input => { input.inputs.push(input.id); input.inputs.sort(); }],
  ['same-source alias dependency', input => { input.inputs.push('resolve-registrations'); input.inputs.sort(); }],
]) {
  test(`resolution convergence rejects ${name}`, t => {
    const { repo, resolution } = overlappingBranches(t);
    const alias = { ...structuredClone(resolution), id: 'alias-resolution' };
    mutate(alias);
    repo.record(alias);
    rejects(repo);
  });
}

test('resolution convergence rejects unrelated and future dependency groups', t => {
  const { repo, resolution } = overlappingBranches(t);
  const revision = repo.source({ [DISTINCT]: 'export const distinct = "future";\n' });
  repo.record(repo.declaration('future-source', revision, [DISTINCT]));
  repo.record({ ...structuredClone(resolution), id: 'future-alias',
    inputs: [...resolution.inputs, 'future-source'].sort() });
  rejects(repo);
});

test('equivalent source aliases never fill a missing merge declaration', t => {
  const { repo, rename } = overlappingBranches(t, { recordResolution: false });
  repo.record({ ...structuredClone(rename), id: 'rename-alias' });
  rejects(repo);
});

test('converged records remain independently immutable and required', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.record(input);
  repo.record({ ...structuredClone(input), id: 'alias' });
  repo.remove(repo.declarationPath(input.id));
  repo.commit('Remove original after alias convergence');
  rejects(repo);
});


// These are the exact published records, not generated composer output. Their
// real source/parent/blob/dependency audit is linked from current-foundation.md.
// Full validation above uses actual temporary Git DAGs; descriptors are not proof.
test('four published CI records share one binding and the resident package merge remains separate', () => {
  const fixture = JSON.parse(readFileSync(new URL('./fixtures/convergent-declarations.json', import.meta.url)));
  assert.equal(fixture.records.length, 5);
  assert.deepEqual(fixture.records.map(entry => [entry.declaration.id, entry.blob]), [
    ['main-pr225-ci-resolution', '2bab7142e7cea72147d2d9bd3e19d16a3354490b'],
    ['resolve-local-guard-portable-pr-ci', '49cc43f2e1b40e7ad1d96625fc194b1f4c217b31'],
    ['resolve-main-local-guard-ci-6520c3f59', 'f7f8f52777cdad190e3fc84fe59e2939e4120fc9'],
    ['resolve-main-local-guard-ci', '20e95385cf3e1092a2c243eca58b9850a1f18fa0'],
    ['resolve-resident-source-latest-main', 'decd45cd1187ec7dc8c967de1084e3b0bd3ead5d'],
  ]);
  const dependencies = new Map(fixture.dependencies.map(entry => [entry.declaration.id, entry.declaration]));
  assert.equal(dependencies.size, fixture.dependencies.length, 'Duplicate recorded dependency ID');
  for (const entry of [...fixture.records, ...fixture.dependencies]) {
    const bytes = Buffer.from(`${JSON.stringify(entry.declaration, null, 2)}\n`);
    const object = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    assert.equal(object, entry.blob, `Changed original Git bytes: ${entry.path}`);
    assert.equal(entry.path, `${DECLARATION_DIRECTORY}/${entry.declaration.id}.json`);
    assert.match(entry.reference, /^[0-9a-f]{40}$/);
  }
  const bindings = fixture.records.map(({ declaration: input }) => foundationSourceBinding(input,
    input.inputs.map(id => { assert(dependencies.has(id), `Missing recorded dependency ${id}`); return dependencies.get(id).revision; })));
  for (const binding of bindings.slice(0, 4)) {
    assert.deepEqual(binding, bindings[0]);
    assert.equal(binding.revision, '6520c3f59b86307229536824fac8f8b5ac5450e4');
    assert.deepEqual(binding.parents, ['398b85c87e0eb29a3d3db0ed21e53ea84464566c', '89a7fd00479c70093cb88282ac3d0cb08b7bcda2']);
    assert.equal(binding.inputs.length, 16);
    assert.deepEqual(binding.changes.map(change => change.path), [CI]);
  }
  assert.notDeepEqual(bindings[4], bindings[0]);
  assert.equal(bindings[4].revision, '3ad450f7996ccb8187de5d3d8e5288a5d4f640ed');
  assert.equal(bindings[4].inputs.length, 15);
  assert.deepEqual(bindings[4].changes.map(change => change.path), [PACKAGE]);
});
