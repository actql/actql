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
    if (path === 'src/platform_native/sqlite/moon.pkg') {
      assert.equal(entry.revision, 'bddee734fca915cfca815562d1407ceb73d0e087');
      const prior = tree.read(path).toString();
      const selectors = ['    "owned_body_extent_native.mbt": [ "native" ],\n',
        '    "owned_body_extent_unsupported.mbt": [ "not", "native" ],\n'];
      let reconstructed = body;
      for (const selector of selectors) {
        assert.equal(body.split(selector).length, 2);
        reconstructed = reconstructed.replace(selector, '');
      }
      assert.equal(reconstructed, prior, 'only the paired Native/unsupported body-extent selectors changed');
      assert.deepEqual(packageImports(body).imports, packageImports(prior).imports);
      assert.equal(currentTree.read(path).toString(), body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(prior))), null);
      const selected = packageSourceInputs({tree: currentTree, packages: ['src/platform_native/sqlite'], target: 'js'});
      for (const member of ['owned_body_extent_native.mbt', 'owned_body_extent_unsupported.mbt', 'sqlite_stub.c']) {
        const source = `src/platform_native/sqlite/${member}`;
        assert(selected.paths.includes(source));
        assert.equal(currentTree.entries.get(source)?.kind, 'blob');
        assert.equal(currentTree.entries.get(source)?.mode, '100644');
      }
    }
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
    if (!path.startsWith(directory + '/')) continue;
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

test('the current keyed README fixture is exact JSON data and cannot admit changed or additional nested inputs', () => {
  const path = 'src/connectors_builtin_node/fixtures/readme-deferred-keyed-input.json';
  const digest = currentNestedFixtureConfigurations[path];
  assert.equal(hash(currentTree.read(path)), digest);
  const fixture = JSON.parse(currentTree.read(path));
  assert.deepEqual(Object.keys(fixture).sort(), ['environmentWire', 'publicationWire', 'source', 'task']);
  assert(Object.values(fixture).every(value => typeof value === 'string'));
  assert(reviewedNestedFixture(request(path, digest)));
  for (const delta of [{digest:'0'.repeat(64)}, {path:path+'.extra'}, {target:'native'}, {toolchainDigest:'0'.repeat(64)}])
    assert.equal(reviewedNestedFixture({...request(path,digest),...delta}), false);
  const altered = {...currentTree, read: p => p === path ? Buffer.concat([currentTree.read(p), Buffer.from('\nchanged')]) : currentTree.read(p)};
  const selected = packageSourceInputs({tree:altered, packages:['src/connectors_builtin_node'], target:'js'});
  assert(selected.paths.includes(path));
  assert(selected.unresolved.includes(`nested package input requires review: ${path}`));
});

// One current map records each input's exact review, while archived preimages
// above remain evidence for their own source only, never runtime acceptance.
test('current Source JSON review binds only its checked normalization count dependency', () => {
  const path='src/source_value/moon.pkg', revision='3ce2057976a7c88a13246a6349fbd7a584d11478';
  const digest='7924497475b1578e83add3ebe773c473b6eba23182ed7c8e9b54ec38ecfba44b';
  const entry=currentPackageConfigurations[path], selectedTree=gitTree(root,revision);
  const body=selectedTree.read(path).toString();
  const prior=gitTree(root,'523ada3259bf9e8147f746727fbfd56065036fd5').read(path).toString();
  assert.equal(entry.revision,revision);assert.equal(entry.digest,digest);
  assert.equal(hash(body),digest);
  const dependency='  "actql/actql/capacity_arithmetic" @counts,\n';
  assert.equal(body.split(dependency).length,2);
  assert.equal(body.replace(dependency,''),prior,'all target and file selectors remain exact');
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(prior).imports,'actql/actql/capacity_arithmetic'].sort());
  assert.equal(currentPackageConfigurationReviewFor(request(path,hash(prior))),null,
    'the old preimage is not promoted to the new current review');
  const selected=packageSourceInputs({tree:currentTree,packages:['src/source_value'],target:'js'});
  assert.deepEqual(selected.unresolved,[]);
  for(const member of ['src/capacity_arithmetic/moon.pkg','src/capacity_arithmetic/preparation_counts.mbt',
    'src/source_value/native_json_construction_extent.mbt','src/source_value/native_json_js_wbtest.mbt']) {
    assert(selected.paths.includes(member),member);
    assert.equal(currentTree.entries.get(member)?.kind,'blob');
    assert.equal(currentTree.entries.get(member)?.mode,'100644');
  }
  for(const changed of [body.replace('@counts','@permission'),
    body.replace('native_json_js_wbtest.mbt','unreviewed_native_json.mbt')]) {
    assert.equal(currentPackageConfigurationReviewFor(request(path,hash(changed))),null);
  }
});

test('current Local Host successor preserves its capacity import and binds four JS callback selectors', () => {
  const path = 'src/client_local_host/moon.pkg';
  const revision = '131b446df837e49f6277c8582460e521dd97c153';
  const digest = '2d1cea3783b4e932e2dd107b4159e8b32dad4f1f57470ee8d3cbd1d30e319802';
  const rule = 'literal-target-selectors-with-bound-source-membership';
  assert.deepEqual(currentPackageConfigurations[path], {revision, digest, rule});
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const reviewed = gitTree(root, revision), body = reviewed.read(path).toString();
  const previous = gitTree(root, '65dd1da4c260610e9a88e430665fdc8f6106bc94').read(path).toString();
  assert.equal(hash(body), digest);
  assert.equal(hash(previous), '8596c0cb5e158a33b98214e9d09a6185dbce3925b3d947def6036ec75bb7dfda');
  const introduced = gitTree(root, 'ff880c0fee559efd6d6f2d4fe86a6c229ad86979').read(path).toString();
  assert.equal(hash(introduced), '73b0cddc426eb97a56302dc76c8e9438fb113508302532dd29e34157c8186969');
  const dependency = '  "actql/actql/capacity_policy" @capacity,\n';
  const selectors = ['preparation_request_native_document_js_wbtest.mbt',
    'preparation_request_native_intake_js_wbtest.mbt'].map(name => `    "${name}": [ "js" ],\n`);
  let reconstructed = introduced;
  for (const addition of [dependency, ...selectors]) {
    assert.equal(introduced.split(addition).length, 2);
    reconstructed = reconstructed.replace(addition, '');
  }
  assert.equal(reconstructed, previous, 'all other imports, targets and options retain their original bytes');
  const successorSelectors = ['preparation_request_native_intake_retirement_js_wbtest.mbt',
    'preparation_request_artifact_retention_js_wbtest.mbt'].map(name => `    "${name}": [ "js" ],\n`);
  let reconstructedIntroduction = body;
  for (const selector of successorSelectors) {
    assert.equal(body.split(selector).length, 2);
    reconstructedIntroduction = reconstructedIntroduction.replace(selector, '');
  }
  assert.equal(reconstructedIntroduction, introduced, 'the successor adds only its two reviewed JS fixtures');
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(previous).imports, 'actql/actql/capacity_policy'].sort());
  assert.equal(currentTree.read(path).toString(), body);
  assert.equal(hash(currentTree.read('toolchain.json')), toolchainDigest);
  assert.equal(currentPackageConfigurationReviewFor(request(path, digest))?.revision, revision);
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(previous))), null);
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(introduced))), null);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith('src/capacity_policy/') &&
    !member.slice('src/capacity_policy/'.length).includes('/')).sort();
  assert(members.includes('src/capacity_policy/moon.pkg'));
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/capacity_policy/*')?.members, members);
  for (const member of [...members, ...[...selectors, ...successorSelectors].map(selector =>
    'src/client_local_host/' + JSON.parse(selector.trim().split(':')[0]))]) {
    assert(selected.paths.includes(member), member);
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  for (const changed of [previous, body.replace(dependency, ''), body.replace('@capacity,', '@permission,'),
    ...[...selectors, ...successorSelectors].map(selector => body.replace(selector, selector.replace('"js"', '"native"'))),
    body + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: ['src/client_local_host'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, digest), ...delta}), null);
});

test('historical Local Host review preserves the original carrier, Source builder and Model completion preimages', () => {
  const path = 'src/client_local_host/moon.pkg';
  const entry = {revision: '65dd1da4c260610e9a88e430665fdc8f6106bc94',
    digest: '8596c0cb5e158a33b98214e9d09a6185dbce3925b3d947def6036ec75bb7dfda',
    rule: 'literal-target-selectors-with-bound-source-membership'};
  const selectedTree = gitTree(root, entry.revision);
  const currentBody = selectedTree.read(path).toString();
  assert.equal(hash(currentBody), entry.digest);
  execFileSync('git', ['merge-base', '--is-ancestor', entry.revision, 'HEAD'], {cwd: root});
  // Keep every historical preimage check on its original bytes. The current
  // successor adds only this literal dependency, not selectors or options.
  const body = gitTree(root, '583969bb5b1a668528eed5db954c2b47e6c0dad6').read(path).toString();
  assert.equal(hash(body), 'ad14b60b64580f0ef6daff2aa7abee2de24af7a71bd254365ef32a18580264a0');
  const modelDependency = '  "actql/actql/model_execution" @model,\n';
  assert.equal(currentBody.split(modelDependency).length, 2);
  assert.equal(currentBody.replace(modelDependency, ''), body);
  assert.equal(packageImports(currentBody).unknown, 'Unreviewed package configuration',
    'existing literal selectors still require the exact finite configuration review');
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(currentBody))), null,
    'the historical preimage cannot qualify the current successor');
  assert.deepEqual(packageImports(currentBody).imports,
    [...packageImports(body).imports, 'actql/actql/model_execution'].sort());
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(body))), null,
    'the previous preimage cannot qualify this current manifest');
  const jsOnly = ['installed_direct_occurrences_js_wbtest.mbt',
    'installed_effect_content_model_js_wbtest.mbt',
    'installed_keyed_capture_parent_js_wbtest.mbt']
    .map(name => `    "${name}": [ "js" ],\n`);
  const priorJsUnion = gitTree(root, '227cb49fc1a4e42776e33ec1efcdbb55ccb9260c').read(path).toString();
  assert.equal(hash(priorJsUnion), 'ad1be1bec19e3026ec8336fa4757e8edb0ffcfc8f70c92be281d043310a4b608');
  assert.equal(body.replace(jsOnly[2], ''), priorJsUnion,
    'only the original managed keyed caller selector extends the prior JS union');
  let importUnion = body;
  for (const selector of jsOnly) {
    assert.equal(body.split(selector).length, 2);
    importUnion = importUnion.replace(selector, '');
  }
  const originalUnion = gitTree(root, 'caa8884bce17bac780ac657265bde7c23e9af61b').read(path).toString();
  assert.equal(hash(originalUnion), '8daab7851344bbffaf55267e4becbcea039d45deb6f889604f15f005bf3093a9');
  assert.equal(importUnion, originalUnion, 'only the three actual JS fixture selectors changed');
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
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert(selected.paths.includes('src/relation_typing/moon.pkg'));
  assert(selected.paths.includes('src/effect_application/moon.pkg'));
  assert(selected.paths.includes('src/carrier_contract/moon.pkg'));
  assert(selected.paths.includes('src/program_source_builder/moon.pkg'));
  const modelMembers = [...currentTree.entries.keys()].filter(member =>
    member.startsWith('src/model_execution/') &&
    !member.slice('src/model_execution/'.length).includes('/')).sort();
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/model_execution/*')?.members, modelMembers);
  assert(modelMembers.includes('src/model_execution/original_completed_parent.mbt'));
  for (const member of modelMembers) {
    assert(selected.paths.includes(member));
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  assert(selected.paths.includes('src/client_local_host/installed_kintone_whole_source_js_wbtest.mbt'));
  assert(selected.paths.includes('src/client_local_host/preparation_request_model_recovery_js_wbtest.mbt'));
  for (const name of ['installed_direct_occurrences_js_wbtest.mbt', 'installed_effect_content_model_js_wbtest.mbt',
    'installed_keyed_capture_parent_js_wbtest.mbt'])
    assert(selected.paths.includes('src/client_local_host/' + name));
  for (const changed of [prior, publicParent, carrierParent, originalUnion, priorJsUnion,
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

test('current query configuration binds both JS-only files without changing imports or Native options', () => {
  const path = 'src/query_integration/moon.pkg';
  const revision = 'd0a65454c66690c3725c9cfbcc31ee84fdd4c3f1';
  const digest = '85c6a9e865217e88e0322ca57208d43cc60742d508da3f04d5be00c724f8c15b';
  const prior = gitTree(root, '66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c').read(path).toString();
  const body = gitTree(root, revision).read(path).toString();
  assert.equal(hash(prior), '179d0c70d9c11c032372634cef98528fdebe13e3afb97a1e917c51bf0d1515fe');
  assert.equal(hash(body), digest);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const before = '  targets: { "strategy_cleanup_current_js_wbtest.mbt": [ "js" ] },';
  const after = `  targets: {
    "strategy_cleanup_current_js_wbtest.mbt": [ "js" ],
    "row_stream_current_js_wbtest.mbt": [ "js" ],
  },`;
  assert.equal(body.split(after).length, 2);
  assert.equal(body.replace(after, before), prior);
  assert.deepEqual(packageImports(body).imports, packageImports(prior).imports);
  assert.equal(currentTree.read(path).toString(), body);
  assert.equal(currentPackageConfigurationReviewFor(request(path, digest))?.revision, revision);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/query_integration'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith('src/query_integration/') &&
    !member.slice('src/query_integration/'.length).includes('/')).sort();
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/query_integration/*')?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  for (const name of ['strategy_cleanup_current_js_wbtest.mbt', 'row_stream_current_js_wbtest.mbt']) {
    assert(members.includes('src/query_integration/' + name));
    assert.equal([...currentTree.read('src/query_integration/' + name).toString().matchAll(/^test "/gmu)].length, 2);
    for (const changed of [body.replace(name, 'unreviewed_wbtest.mbt'),
      body.replace(`"${name}": [ "js" ]`, `"${name}": [ "native" ]`)]) {
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    }
  }
  for (const changed of [prior, body + '\noptions(pre_build: {command: "unreviewed"})\n',
    body.replace('"-lssl -lcrypto"', '"-lunreviewed"')]) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: ['src/query_integration'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
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
