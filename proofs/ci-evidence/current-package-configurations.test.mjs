import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageSourceInputs, packageImports} from './inputs.mjs';
import {currentConfigurationReviewRevision, currentPackageConfigurations,
  currentPackageConfigurationReviewFor, currentNestedFixtureConfigurations, reviewedNestedFixture,
  packageConfigurationReview} from './package-configurations.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const tree = gitTree(root, currentConfigurationReviewRevision);
const toolchainDigest = packageConfigurationReview.toolchainDigest;
const report = JSON.parse(readFileSync(new URL('../../docs/reviews/2026-10-25-session-current-configuration-review.json', import.meta.url)));
const request = (path, digest) => ({path, digest, target: 'js', toolchainDigest});

test('archived review retains exact authored preimages without promoting them to current evidence', () => {
  assert.equal(report.source, currentConfigurationReviewRevision);
  execFileSync('git', ['merge-base', '--is-ancestor', currentConfigurationReviewRevision, 'HEAD'], {cwd: root});
  assert.equal(report.configurations.length, 16);
  for (const entry of report.configurations) {
    assert.equal(hash(entry.content), entry.sha256);
    assert.equal(tree.read(entry.path).toString(), entry.content);
    const current = currentPackageConfigurations[entry.path];
    assert(current);
    const review = currentPackageConfigurationReviewFor(request(entry.path, entry.sha256));
    if (current.revision === undefined) {
      assert.equal(current.digest, entry.sha256);
      assert.equal(review?.rule, entry.rule);
      assert.equal(review?.revision, report.source);
    } else {
      assert.notEqual(current.digest, entry.sha256);
      assert.equal(review, null, 'Archived input is not a current review');
    }
    for (const dependency of packageImports(entry.content).imports)
      if (dependency.startsWith('actql/actql/'))
        assert(tree.entries.has(`src/${dependency.slice('actql/actql/'.length)}/moon.pkg`));
  }
});

for (const [path, entry] of Object.entries(currentPackageConfigurations)) {
  test(`current configuration refuses changed meaning, unknown options and foreign scope: ${path}`, () => {
    const selectedTree = gitTree(root, entry.revision ?? currentConfigurationReviewRevision);
    const body = selectedTree.read(path).toString();
    const changes = [body + '\noptions(pre_build: {command: "unreviewed"})\n',
      body.replace(/"(?:actql\/actql|moonbitlang\/core)\/[^"\n]+"/, '"actql/actql/unreviewed_resource_owner"'),
      body.replace(/"js"|"native"|"wasm"/, '"unreviewed-target"')];
    for (const changed of changes) {
      assert.notEqual(changed, body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      const altered = {...selectedTree, read: p => p === path ? Buffer.from(changed) : selectedTree.read(p)};
      assert(packageSourceInputs({tree: altered, packages: [path.slice(0, -9)], target: 'js'}).unresolved.length > 0);
    }
    for (const delta of [{target:'native'}, {target:'wasm'}, {toolchainDigest:'0'.repeat(64)}, {path:'./'+path}, {path:'src/unreviewed/moon.pkg'}, {digest:'0'.repeat(64)}])
      assert.equal(currentPackageConfigurationReviewFor({...request(path, entry.digest), ...delta}), null);
  });
}

test('exact nested C fixtures stay bound inert inputs; changed or additional members remain unresolved', () => {
  assert.equal(report.nested_fixtures.length, 3);
  const directory = 'src/platform_native/filesystem';
  for (const [path, digest] of Object.entries(currentNestedFixtureConfigurations)) {
    assert.equal(hash(tree.read(path)), digest);
    assert(reviewedNestedFixture(request(path, digest)));
    for (const delta of [{digest:'0'.repeat(64)}, {path:path+'.extra'}, {target:'native'}, {toolchainDigest:'0'.repeat(64)}])
      assert.equal(reviewedNestedFixture({...request(path, digest), ...delta}), false);
    const altered = {...tree, read: p => p === path ? Buffer.concat([tree.read(p), Buffer.from('\nchanged')]) : tree.read(p)};
    const selected = packageSourceInputs({tree: altered, packages:[directory], target:'js'});
    assert(selected.paths.includes(path));
    assert(selected.unresolved.includes(`nested package input requires review: ${path}`));
  }
  const added = `${directory}/fixtures/unreviewed.c`;
  const altered = {...tree, entries:new Map([...tree.entries, [added,{path:added,kind:'blob',mode:'100644'}]]),
    read:p => p === added ? Buffer.from('int unknown;') : tree.read(p)};
  const selected = packageSourceInputs({tree:altered, packages:[directory], target:'js'});
  assert(selected.paths.includes(added));
  assert(selected.unresolved.includes(`nested package input requires review: ${added}`));
});

// One current map records each input's exact review, while archived preimages
// above remain evidence for their own source only, never runtime acceptance.
test('single current map binds exact per-entry reviews and full literal import closure', () => {
  assert.equal(Object.keys(currentPackageConfigurations).length, 18);
  assert.equal(Object.values(currentPackageConfigurations).filter(entry => entry.revision !== undefined).length, 8);
  const head = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
  for (const [path, entry] of Object.entries(currentPackageConfigurations)) {
    const revision = entry.revision ?? currentConfigurationReviewRevision;
    const selectedTree = gitTree(root, revision);
    assert.equal(hash(selectedTree.read(path)), entry.digest, path);
    assert.deepEqual(head.read(path), selectedTree.read(path), path);
    const review = currentPackageConfigurationReviewFor(request(path, entry.digest));
    assert.equal(review?.revision, revision);
    assert.equal(review?.rule, entry.rule);
    const selected = packageSourceInputs({tree: head, packages: [path.slice(0, -9)], target: 'js'});
    assert.deepEqual(selected.unresolved, [], path);
    for (const dependency of packageImports(head.read(path).toString()).imports)
      if (dependency.startsWith('actql/actql/'))
        assert(selected.paths.includes(`src/${dependency.slice('actql/actql/'.length)}/moon.pkg`));
    for (const member of selected.paths) {
      assert.equal(head.entries.get(member)?.kind, 'blob', member);
      assert.equal(head.entries.get(member)?.mode, '100644', member);
    }
  }
});
