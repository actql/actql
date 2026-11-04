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
const currentTree = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
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
test('current Local Host review binds the original carrier and Source builder union with existing JS selectors', () => {
  const path = 'src/client_local_host/moon.pkg';
  const entry = currentPackageConfigurations[path];
  assert.equal(entry.revision, '227cb49fc1a4e42776e33ec1efcdbb55ccb9260c');
  assert.equal(entry.digest, 'ad1be1bec19e3026ec8336fa4757e8edb0ffcfc8f70c92be281d043310a4b608');
  const selectedTree = gitTree(root, entry.revision);
  const body = selectedTree.read(path).toString();
  assert.equal(hash(body), entry.digest);
  execFileSync('git', ['merge-base', '--is-ancestor', entry.revision, 'HEAD'], {cwd: root});
  const jsOnly = ['installed_direct_occurrences_js_wbtest.mbt',
    'installed_effect_content_model_js_wbtest.mbt']
    .map(name => `    "${name}": [ "js" ],\n`);
  let importUnion = body;
  for (const selector of jsOnly) {
    assert.equal(body.split(selector).length, 2);
    importUnion = importUnion.replace(selector, '');
  }
  const originalUnion = gitTree(root, 'caa8884bce17bac780ac657265bde7c23e9af61b').read(path).toString();
  assert.equal(hash(originalUnion), '8daab7851344bbffaf55267e4becbcea039d45deb6f889604f15f005bf3093a9');
  assert.equal(importUnion, originalUnion, 'only the two actual JS fixture selectors changed');
  const prior = gitTree(root, 'e9b3409db9a89b230b1c5a1598f2221d6e80388e').read(path).toString();
  assert.equal(hash(prior), '42f83fa2f1ad053fa7b456e3ff58216827ae1ef8321e10b16cfe6ac79c3d7d5d');
  const dependency = '  "actql/actql/carrier_contract" @carrier,\n';
  const sourceBuilder = '  "actql/actql/program_source_builder" @source_builder,\n';
  assert.equal(body.split(dependency).length, 2);
  assert.equal(body.split(sourceBuilder).length, 2);
  assert.equal(importUnion.replace(dependency, '').replace(sourceBuilder, ''), prior);
  const publicParent = gitTree(root, '8c95f244e92e1e7bd2f3876445ed08dbac17fc07').read(path).toString();
  assert.equal(hash(publicParent), '40b9424ff3f16803b7287bdbf94265b04567bb6cc457aec5568bd711a74e8e37');
  assert.equal(importUnion.replace(dependency, ''), publicParent);
  const carrierParent = gitTree(root, '6b3099abb66ad19db08558ff077b508a743a0431').read(path).toString();
  assert.equal(hash(carrierParent), 'd912a60c2dc285826993b93adc3528cb74d7240a9df21de264b07fecc3c72564');
  assert.equal(importUnion.replace(sourceBuilder, ''), carrierParent);
  const selector = '    "preparation_request_model_recovery_js_wbtest.mbt": [ "js" ],\n';
  assert.equal(body.split(selector).length, 2);
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(prior).imports, 'actql/actql/carrier_contract', 'actql/actql/program_source_builder'].sort());
  assert.equal(body.split('  "actql/actql/effect_application" @effect,\n').length, 2);
  assert.equal(entry.rule, 'literal-target-selectors-with-bound-source-membership');
  assert(packageImports(body).imports.includes('actql/actql/relation_typing'));
  assert(body.includes('"installed_kintone_whole_source_js_wbtest.mbt": [ "js" ],'));
  assert.equal(currentTree.read(path).toString(), body);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert(selected.paths.includes('src/relation_typing/moon.pkg'));
  assert(selected.paths.includes('src/effect_application/moon.pkg'));
  assert(selected.paths.includes('src/carrier_contract/moon.pkg'));
  assert(selected.paths.includes('src/program_source_builder/moon.pkg'));
  assert(selected.paths.includes('src/client_local_host/installed_kintone_whole_source_js_wbtest.mbt'));
  assert(selected.paths.includes('src/client_local_host/preparation_request_model_recovery_js_wbtest.mbt'));
  for (const name of ['installed_direct_occurrences_js_wbtest.mbt', 'installed_effect_content_model_js_wbtest.mbt'])
    assert(selected.paths.includes('src/client_local_host/' + name));
  for (const changed of [prior, publicParent, carrierParent, originalUnion,
    body.replace(selector, selector.replace('"js"', '"native"')),
    ...jsOnly.map(value => body.replace(value, value.replace('"js"', '"native"')))]) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...selectedTree, read: member => member === path ? Buffer.from(changed) : selectedTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: ['src/client_local_host'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const target of ['native', 'wasm']) {
    assert.equal(currentPackageConfigurationReviewFor({...request(path, entry.digest), target}), null);
  }
});

test('current preparation manifest binds the integrated literal value-admission dependency', () => {
  const path = 'src/client_local_preparation/moon.pkg';
  const revision = 'ef74293ba33e4493ba0777e3bb4ee29eac3b9551';
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const reviewed = gitTree(root, revision), bytes = reviewed.read(path), body = bytes.toString();
  assert.equal(hash(bytes), '15c87c0278844f963c003ee10256cd9bece3c436cdb9e00ffe1d4cb43e9304cd');
  const parent = execFileSync('git', ['rev-parse', revision + '^'], {cwd: root, encoding: 'utf8'}).trim();
  const prior = gitTree(root, parent).read(path).toString();
  assert.equal(hash(prior), '86235f30cbe02faee143dddb93b7b9ce623b86e3eaeb89c4d7c7046900daf296');
  const dependency = '  "actql/actql/value_admission" @admitted,\n';
  assert.equal(body.split(dependency).length, 2);
  assert.equal(body.replace(dependency, ''), prior);
  assert.equal(packageImports(body).unknown, null, 'Literal imports use the existing parser, without an options exception');
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(prior).imports, 'actql/actql/value_admission'].sort());
  const head = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
  assert.deepEqual(head.read(path), bytes);
  const selected = packageSourceInputs({tree: head, packages: ['src/client_local_preparation'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  for (const directory of ['src/client_local_preparation', 'src/parameter_binding', 'src/value_admission']) {
    const members = [...head.entries.keys()].filter(member => member.startsWith(directory + '/') &&
      !member.slice(directory.length + 1).includes('/')).sort();
    assert.deepEqual(selected.directories.find(entry => entry.path === directory + '/*')?.members, members);
    for (const member of members) {
      assert(selected.paths.includes(member));
      assert.equal(head.entries.get(member).kind, 'blob');
      assert.equal(head.entries.get(member).mode, '100644');
    }
  }
});

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
  const revision = 'bf198225499436c26be2f7d763582b0efaeeae2b';
  const reviewed = gitTree(root, revision);
  const bytes = reviewed.read(path), body = bytes.toString();
  const digest = '508d45513dd76478ece212cd3e9a2da45aa93f2e100d99c44076a31afa46be23';
  assert.equal(hash(bytes), digest);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const arithmetic = '  "actql/actql/capacity_arithmetic" @preparation_counts,\n';
  assert.equal(body.split(arithmetic).length, 2);
  const selectorOnly = body.replace(arithmetic, '');
  assert.equal(hash(selectorOnly), '23447fecf75b00a7f5f5828d0dd27c9711a4386d34d3e3320ae805950b4ccfeb');
  assert.equal(selectorOnly, gitTree(root, '3484e0f43d8eee0013bb5fb8fba03e7fc873377f').read(path).toString());
  const prior = gitTree(root, '523ada3259bf9e8147f746727fbfd56065036fd5').read(path);
  const selectors = '    "platform_vm_capacity_wasm.mbt": [ "wasm" ],\n' +
    '    "platform_vm_capacity_unsupported.mbt": [ "not", "wasm" ],\n';
  assert.equal(body.split(selectors).length, 2);
  assert.equal(selectorOnly.replace(selectors, ''), prior.toString());
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(prior.toString()).imports, 'actql/actql/capacity_arithmetic'].sort());
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
  for (const changed of [prior.toString(), selectorOnly, body + '\noptions(pre_build: {command: "unreviewed"})\n',
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
