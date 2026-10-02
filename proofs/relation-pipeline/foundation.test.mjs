import assert from 'node:assert/strict';
import { readFileSync, renameSync, symlinkSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { composeFoundation } from './foundation.mjs';
import { ADDED, CI, DECLARATION_DIRECTORY, DISTINCT, FoundationRepository, PACKAGE,
  PROTECTED_PATHS, RENAME, ciBytes, disjointBranches, olderInFlightBranch, overlappingBranches,
  packageBytes, sha256, singleChange, threePullRequestBranches } from './fixtures/foundation-repository.mjs';

const compose = (repo, options = {}) => composeFoundation(repo.root,
  { checkpoint: repo.checkpoint, paths: PROTECTED_PATHS, ...options });
const rejects = (repo, options) => assert.throws(() => compose(repo, options),
  /foundation|declaration|merge|Git|changed|Uncommitted|ENOENT|JSON|Unexpected|digest|mode|rationale|parent/i);
const file = (aggregate, path) => aggregate.files.find(entry => entry.path === path);
const declaration = (aggregate, id) => aggregate.declarations.find(entry => entry.id === id);

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
  assert.equal(actual.introduction, introduction);
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
    mergeBase: repo.checkpoint, declaration: resolution.id }]);
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
  ['unknown schema version', input => { input.version = 'actql-foundation-declaration/999'; }],
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

test('duplicate source revisions cannot be represented as independent declarations', t => {
  const { repo, declaration: input } = singleChange(t);
  repo.writeDeclaration(input);
  repo.writeDeclaration({ ...input, id: 'second-rationale' });
  repo.commit('Two declarations for one source commit');
  rejects(repo);
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

test('identical declaration files cannot be introduced independently on separate branches', t => {
  const { repo, revision, declaration: input } = singleChange(t);
  repo.branch('parallel', revision);
  repo.writeDeclaration(input);
  repo.write('left.txt', 'left introduction\n');
  repo.commit('First introduction');
  repo.checkout('parallel');
  repo.writeDeclaration(input);
  repo.write('right.txt', 'right introduction\n');
  repo.commit('Independent second introduction');
  repo.checkout('main');
  repo.merge('parallel');
  rejects(repo);
});

test('a criss-cross merge with multiple merge bases fails closed even when protected bytes agree', t => {
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
  repo.merge('right');
  rejects(repo);
});

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
    mergeBase: fixture.fork, declaration: fixture.resolution.id }]);
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
