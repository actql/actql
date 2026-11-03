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
  assert.equal(Object.keys(currentPackageConfigurations).length, 19);
  assert.equal(Object.values(currentPackageConfigurations).filter(entry => entry.revision !== undefined).length, 11);
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

// This is a finite configuration-input review, not a compiler or VM witness.
test('current physical Resource review binds platform VM selectors and refuses stale or changed input', () => {
  const path = 'src/physical_resources/moon.pkg';
  const revision = '3484e0f43d8eee0013bb5fb8fba03e7fc873377f';
  const reviewed = gitTree(root, revision);
  const bytes = reviewed.read(path), body = bytes.toString();
  const digest = '23447fecf75b00a7f5f5828d0dd27c9711a4386d34d3e3320ae805950b4ccfeb';
  assert.equal(hash(bytes), digest);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const prior = gitTree(root, '523ada3259bf9e8147f746727fbfd56065036fd5').read(path);
  const selectors = '    "platform_vm_capacity_wasm.mbt": [ "wasm" ],\n' +
    '    "platform_vm_capacity_unsupported.mbt": [ "not", "wasm" ],\n';
  assert.equal(body.split(selectors).length, 2);
  assert.equal(body.replace(selectors, ''), prior.toString());
  assert.deepEqual(packageImports(body).imports, packageImports(prior.toString()).imports);
  assert.deepEqual(currentPackageConfigurationReviewFor(request(path, digest)), {
    revision, target: 'js', toolchainDigest,
    moonRevision: packageConfigurationReview.moonRevision,
    rule: 'literal-target-selectors-with-bound-source-membership',
  });
  const head = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
  assert.deepEqual(head.read(path), bytes);
  const selected = packageSourceInputs({tree: head, packages: ['src/physical_resources'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  for (const member of ['platform_vm_capacity_wasm.mbt', 'platform_vm_capacity_unsupported.mbt']) {
    const input = 'src/physical_resources/' + member;
    assert(selected.paths.includes(input), 'Target clauses never hide original source membership');
    assert.equal(head.entries.get(input).mode, '100644');
  }
  for (const changed of [prior.toString(), body + '\noptions(pre_build: {command: "unreviewed"})\n',
    body.replace('"platform_vm_capacity_wasm.mbt": [ "wasm" ]',
      '"platform_vm_capacity_wasm.mbt": [ "native" ]')]) {
    assert.notEqual(changed, body);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...head, read: member => member === path ? Buffer.from(changed) : head.read(member)};
    assert(packageSourceInputs({tree: altered, packages: ['src/physical_resources'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
});

// One current literal Native link option is inert on this existing JS path.
// No compiler, linker, container or runtime acceptance is asserted here.
test('current remote Client review binds only its Native link driver on JS', () => {
  const path = 'src/platform_native/remote_client/moon.pkg';
  const digest = '2d564b643659ca806c35da2414f432b52292fa8c79a94cffc0706191ae156832';
  const revision = 'deea413fba8b255cf5be7300d94eccd883b5b5eb';
  const reviewed = gitTree(root, revision), bytes = reviewed.read(path);
  assert.equal(hash(bytes), digest);
  assert.equal(bytes.toString().split('  link: { "native": { "cc": "./scripts/native-sqlite-link-driver.sh" } },\n').length, 2);
  assert.deepEqual(currentPackageConfigurationReviewFor(request(path, digest)), {
    revision, target: 'js', toolchainDigest,
    moonRevision: packageConfigurationReview.moonRevision,
    rule: 'literal-native-options-with-bound-source-membership',
  });
  for (const target of ['native', 'wasm'])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, digest), target}), null);
  const head = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
  assert.deepEqual(head.read(path), bytes);
  const directory = 'src/platform_native/remote_client';
  const selected = packageSourceInputs({tree: head, packages: [directory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  // Native selectors do not remove any original package member from the key.
  const members = [...head.entries.keys()].filter(member => member.startsWith(directory + '/') &&
    !member.slice(directory.length + 1).includes('/')).sort();
  assert.deepEqual(selected.directories.find(entry => entry.path === directory + '/*').members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(head.entries.get(member).mode, '100644');
  }
});
