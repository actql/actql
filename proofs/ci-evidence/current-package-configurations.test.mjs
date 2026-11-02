import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageSourceInputs, packageImports} from './inputs.mjs';
import {currentConfigurationReviewRevision, currentPackageConfigurations,
  currentSourceConfigurationReviewRevision, currentSourcePackageConfigurations,
  currentPackageConfigurationReviewFor, currentNestedFixtureConfigurations, reviewedNestedFixture,
  packageConfigurationReview} from './package-configurations.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const tree = gitTree(root, currentConfigurationReviewRevision);
const toolchainDigest = packageConfigurationReview.toolchainDigest;
const report = JSON.parse(readFileSync(new URL('../../docs/reviews/2026-10-25-session-current-configuration-review.json', import.meta.url)));
const request = (path, digest) => ({path, digest, target: 'js', toolchainDigest});

test('finite successor review binds exact authored configuration preimages and actual fixed Git inputs', () => {
  assert.equal(report.source, currentConfigurationReviewRevision);
  execFileSync('git', ['merge-base', '--is-ancestor', currentConfigurationReviewRevision, 'HEAD'], {cwd: root});
  assert.equal(report.configurations.length, 16);
  assert.deepEqual(report.configurations.map(x => x.path).sort(), Object.keys(currentPackageConfigurations).sort());
  for (const entry of report.configurations) {
    assert.equal(hash(entry.content), entry.sha256);
    assert.equal(tree.read(entry.path).toString(), entry.content);
    const review = currentPackageConfigurationReviewFor(request(entry.path, entry.sha256));
    assert.equal(review?.rule, entry.rule);
    assert.equal(review?.revision, report.source);
    const selected = packageSourceInputs({tree, packages: [entry.path.slice(0, -'/moon.pkg'.length)], target: 'js'});
    assert.deepEqual(selected.unresolved, []);
    for (const dependency of packageImports(entry.content).imports)
      if (dependency.startsWith('actql/actql/')) assert(selected.paths.includes(`src/${dependency.slice('actql/actql/'.length)}/moon.pkg`));
  }
});

for (const [path, entry] of Object.entries(currentPackageConfigurations)) {
  test(`current configuration refuses changed meaning, unknown options and foreign scope: ${path}`, () => {
    const body = tree.read(path).toString();
    const changes = [body + '\noptions(pre_build: {command: "unreviewed"})\n',
      body.replace(/"(?:actql\/actql|moonbitlang\/core)\/[^"\n]+"/, '"actql/actql/unreviewed_resource_owner"'),
      body.replace(/"js"|"native"|"wasm"/, '"unreviewed-target"')];
    for (const changed of changes) {
      assert.notEqual(changed, body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      const altered = {...tree, read: p => p === path ? Buffer.from(changed) : tree.read(p)};
      assert(packageSourceInputs({tree: altered, packages: [path.slice(0, -9)], target: 'js'}).unresolved.length > 0);
    }
    for (const delta of [{target:'native'}, {target:'wasm'}, {toolchainDigest:'0'.repeat(64)}, {path:'./'+path}, {digest:'0'.repeat(64)}])
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

// Review current exact inputs separately; retain every historical descriptor and
// negative fixture above. This grants no runtime/Host acceptance or reuse alone.
const currentSourceTree = gitTree(root, currentSourceConfigurationReviewRevision);
test('current eight-manifest successor binds the reviewed source and full literal import closure', () => {
  assert.equal(Object.keys(currentSourcePackageConfigurations).length, 8);
  execFileSync('git', ['merge-base', '--is-ancestor', currentSourceConfigurationReviewRevision, 'HEAD'], {cwd: root});
  const head = treeAtCurrentHead();
  for (const [path, entry] of Object.entries(currentSourcePackageConfigurations)) {
    assert.equal(hash(currentSourceTree.read(path)), entry.digest, path);
    assert.deepEqual(head.read(path), currentSourceTree.read(path), path);
    const review = currentPackageConfigurationReviewFor(request(path, entry.digest));
    assert.equal(review?.revision, currentSourceConfigurationReviewRevision);
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
function treeAtCurrentHead() {
  return gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
}
for (const [path, entry] of Object.entries(currentSourcePackageConfigurations)) {
  test(`current eight-manifest successor refuses changed bytes and foreign scope: ${path}`, () => {
    const body = currentSourceTree.read(path).toString();
    for (const changed of [body + '\noptions(pre_build: {command: "unreviewed"})\n',
      body.replace(/"(?:actql\/actql|moonbitlang\/core)\/[^"\n]+"/, '"actql/actql/unreviewed_resource_owner"'),
      body.replace(/"js"|"native"|"wasm"/, '"unreviewed-target"')]) {
      assert.notEqual(changed, body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      const altered = {...currentSourceTree, read: p => p === path ? Buffer.from(changed) : currentSourceTree.read(p)};
      assert(packageSourceInputs({tree: altered, packages: [path.slice(0, -9)], target: 'js'}).unresolved.length > 0);
    }
    for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)},
      {path: './' + path}, {path: 'src/unreviewed/moon.pkg'}, {digest: '0'.repeat(64)}])
      assert.equal(currentPackageConfigurationReviewFor({...request(path, entry.digest), ...delta}), null);
  });
}
