import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageSourceInputs, packageImports, mutationSourceInputs} from './inputs.mjs';
import {currentConfigurationReviewRevision, currentPackageConfigurations,
  currentPackageConfigurationReviewFor, currentNestedFixtureConfigurations, reviewedNestedFixture,
  packageConfigurationReview, packageConfigurationReviewFor, reviewedPackageConfigurations} from './package-configurations.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const tree = gitTree(root, currentConfigurationReviewRevision);
const currentTree = gitTree(root, execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim());
const toolchainDigest = packageConfigurationReview.toolchainDigest;
const report = JSON.parse(readFileSync(new URL('../../docs/reviews/2026-10-25-session-current-configuration-review.json', import.meta.url)));
const nativePublicationReview = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-17-session-native-publication-constructor-selector-review.json', import.meta.url)));
const sqliteCapacityReview = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-19-session-sqlite-key-capacity-selector-review.json', import.meta.url)));
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
      assert.equal(entry.revision, sqliteCapacityReview.source);
      assert.equal(hash(body), sqliteCapacityReview.sha256);
      const prior = gitTree(root, sqliteCapacityReview.previousRevision).read(path).toString();
      assert.equal(hash(prior), sqliteCapacityReview.previousSha256);
      let reconstructed = body;
      for (const selector of sqliteCapacityReview.addedSelectors) {
        assert.deepEqual(selector.targets, ['native']);
        const line = `    "${selector.file}": [ "native" ],\n`;
        assert.equal(body.split(line).length, 2);
        reconstructed = reconstructed.replace(line, '');
      }
      assert.equal(reconstructed, prior, 'Only the reviewed Native key-capacity selector changed');
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
      for (const fixture of sqliteCapacityReview.fixtures) {
        assert.equal(hash(selectedTree.read(fixture.path)), fixture.sha256);
        assert.equal(selectedTree.read(fixture.path).length, fixture.bytes);
        assert.equal(selectedTree.entries.get(fixture.path)?.mode, fixture.mode);
        assert(selected.paths.includes(fixture.path));
      }
    }
    if (path === 'src/platform_native/publication_store/moon.pkg') {
      assert.equal(entry.revision, nativePublicationReview.source);
      const current = selectedTree.read(path).toString();
      const publicationSelector = '    "publication_construction_native.mbt": [ "native" ],\n';
      assert.equal(current.split(publicationSelector).length, 2);
      const successor = current.replace(publicationSelector, '');
      assert.equal(successor,
        gitTree(root, nativePublicationReview.previousRevision).read(path).toString(),
        'only the literal Native publication constructor selector extends the scalar configuration');
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(successor))), null);
      const scalarImport = '  "actql/actql/decode_scalar" @scalar,\n';
      assert.equal(successor.split(scalarImport).length, 2);
      const deliverySuccessor = successor.replace(scalarImport, '');
      assert.equal(deliverySuccessor,
        gitTree(root, '3feeecd4936fcf156d8b5293354332813913e59f').read(path).toString(),
        'only the pure scalar admission import extends the delivery configuration');
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(deliverySuccessor))), null);
      const deliverySelector = '    "delivery_chunk_native_wbtest.mbt": [ "native" ],\n';
      assert.equal(successor.split(deliverySelector).length, 2);
      const modelSuccessor = deliverySuccessor.replace(deliverySelector, '');
      assert.equal(modelSuccessor,
        gitTree(root, 'f86f409e62d39511380497cb0fe5639d5259f191').read(path).toString(),
        'only the original Native delivery test selector extends the prior review');
      const body = gitTree(root, 'f7dfa3c3b3e61b71e63986342636039d20eaece2').read(path).toString();
      const modelSelectors = ['    "model_evidence_custody_native.mbt": [ "native" ],\n',
        '    "model_evidence_custody_native_wbtest.mbt": [ "native" ],\n',
        '    "model_evidence_custody_unsupported.mbt": [ "not", "native" ],\n'];
      let beforeModel = modelSuccessor;
      for (const selector of modelSelectors) {
        assert.equal(beforeModel.split(selector).length, 2);
        beforeModel = beforeModel.replace(selector, '');
        const changed = successor.replace(selector, selector.replace('"native"', '"js"'));
        assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      }
      assert.equal(beforeModel, body, 'only the three original Model evidence selectors extend the reviewed Store');
      assert.deepEqual(packageImports(successor).imports,
        [...packageImports(body).imports, 'actql/actql/decode_scalar'].sort());
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(body))), null);
      const precursor = gitTree(root, 'f519f34b2d45d5365c1af3b1d42ad92524514716').read(path).toString();
      const capacityInputs = ['  "actql/actql/decode_shape" @shape,\n',
        '  "actql/actql/execution_relation" @execution,\n',
        '    "captured_content_capacity_native.mbt": [ "native" ],\n'];
      let beforeCapacity = body;
      for (const input of capacityInputs) {
        assert.equal(body.split(input).length, 2);
        beforeCapacity = beforeCapacity.replace(input, '');
      }
      assert.equal(beforeCapacity, precursor,
        'only two common inventory imports and the Native inventory selector changed');
      assert.deepEqual(packageImports(body).imports, [...packageImports(precursor).imports,
        'actql/actql/decode_shape', 'actql/actql/execution_relation'].sort());
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(precursor))), null,
        'the previous configuration cannot qualify the new custody inventory inputs');
      const introduced = gitTree(root, '5f2e0ecdeeaea9fb011c514806ef4dee80b03dad').read(path).toString();
      const local = '  "actql/actql/client_local_host" @local,\n';
      assert.equal(precursor.split(local).length, 2);
      assert.equal(precursor.replace(local, ''), introduced,
        'the genuine reviewed union adds only the same-parent Local capture-validation dependency');
      assert.deepEqual(packageImports(precursor).imports,
        ['actql/actql/client_local_host', ...packageImports(introduced).imports].sort());
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(introduced))), null,
        'the prior Store configuration cannot qualify the current literal import');
      const prior = tree.read(path).toString();
      const selectors = ['    "captured_content_custody_native.mbt": [ "native" ],\n',
        '    "captured_content_custody_native_wbtest.mbt": [ "native" ],\n',
        '    "captured_content_custody_unsupported.mbt": [ "not", "native" ],\n'];
      let reconstructed = introduced;
      for (const selector of selectors) {
        assert.equal(introduced.split(selector).length, 2);
        reconstructed = reconstructed.replace(selector, '');
      }
      assert.equal(reconstructed, prior, 'only the three reviewed Native custody selectors changed');
      assert.deepEqual(packageImports(introduced).imports, packageImports(prior).imports);
      assert.equal(currentTree.read(path).toString(), current);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(prior))), null);
      const selected = packageSourceInputs({tree: currentTree, packages: ['src/platform_native/publication_store'], target: 'js'});
      for (const member of ['captured_content_custody_native.mbt', 'captured_content_custody_native_wbtest.mbt',
        'captured_content_custody_unsupported.mbt', 'captured_content_capacity.mbt',
        'captured_content_capacity_native.mbt', 'store_format_stub.c',
        'model_evidence_custody_native.mbt', 'model_evidence_custody_native_wbtest.mbt',
        'model_evidence_custody_unsupported.mbt']) {
        const source = `src/platform_native/publication_store/${member}`;
        assert(selected.paths.includes(source));
        assert.equal(currentTree.entries.get(source)?.kind, 'blob');
        assert.equal(currentTree.entries.get(source)?.mode, '100644');
      }
    }
    if (path === 'src/platform_native/signature/moon.pkg') {
      assert.equal(entry.revision, 'f86f409e62d39511380497cb0fe5639d5259f191');
      const prior = gitTree(root, '14050e0d50b79a01dc07e52024b8ada85ab14203').read(path).toString();
      assert.equal(hash(prior), 'c9f579ed2e7db177e27ae45e694788e76332cbc058594eca03e120539c138a7e');
      const selector = '    "model_private_evidence_native_wbtest.mbt": [ "native" ],\n';
      assert.equal(body.split(selector).length, 2);
      assert.equal(body.replace(selector, ''), prior,
        'only the existing Native Model evidence test selector extends the reviewed signature package');
      assert.deepEqual(packageImports(body).imports, packageImports(prior).imports);
      assert.equal(currentTree.read(path).toString(), body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(prior))), null);
      const changed = body.replace(selector, selector.replace('"native"', '"js"'));
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      const selected = packageSourceInputs({tree: currentTree, packages: ['src/platform_native/signature'], target:'js'});
      const member = 'src/platform_native/signature/model_private_evidence_native_wbtest.mbt';
      assert(selected.paths.includes(member));
      assert.equal(currentTree.entries.get(member)?.kind, 'blob');
      assert.equal(currentTree.entries.get(member)?.mode, '100644');
    }
    const changes = [body + '\noptions(pre_build: {command: "unreviewed"})\n',
      body.replace(/"(?:actql\/actql|moonbitlang\/core)\/[^"\n]+"/, '"actql/actql/unreviewed_resource_owner"'),
      (/"js"|"native"|"wasm"/u.test(body)
        ? body.replace(/"js"|"native"|"wasm"/u, '"unreviewed-target"')
        : body+'\noptions(targets: {"unreviewed.mbt": ["unreviewed-target"]})\n')];
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
  const prior=gitTree(root,'14050e0d50b79a01dc07e52024b8ada85ab14203').read(path).toString();
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

// Current admission owns exact configuration identity. Check the actual Git
// entry and closure instead of reconstructing every migration as text edits.
test('current configuration entries bind exact authored Git inputs and literal dependencies', () => {
  for (const [path, entry] of Object.entries(currentPackageConfigurations)) {
    const body = currentTree.read(path).toString();
    assert.equal(hash(body), entry.digest, `Current configuration identity: ${path}`);
    const review = currentPackageConfigurationReviewFor(request(path, entry.digest));
    assert.equal(review?.revision, entry.revision ?? currentConfigurationReviewRevision);
    assert.equal(review?.rule, entry.rule);
    if (['src/client_local_host/moon.pkg', 'src/platform_native/sqlite/moon.pkg',
      'src/physical_resources/moon.pkg', 'src/connectors/local/driver/moon.pkg'].includes(path)) {
      // A shared local object database must not hide an unpublished review.
      execFileSync('git', ['merge-base', '--is-ancestor', review.revision, 'HEAD'], {cwd: root});
    }
    const selected = packageSourceInputs({tree: currentTree, packages: [path.slice(0, -9)], target: 'js'});
    assert(selected.paths.includes(path));
    if (packageImports(body).unknown) {
      assert(selected.packageConfigurations.some(value => value.path === path && value.digest === entry.digest),
        `Selected original configuration: ${path}`);
    }
    for (const dependency of packageImports(body).imports) if (dependency.startsWith('actql/actql/')) {
      const imported = `src/${dependency.slice('actql/actql/'.length)}/moon.pkg`;
      assert(selected.paths.includes(imported), `Missing literal dependency: ${imported}`);
      assert.equal(currentTree.entries.get(imported)?.kind, 'blob');
    }
  }
});

test('current Local JS review admits only reviewed fixture selectors and keeps every source bound', () => {
  const review = JSON.parse(readFileSync(new URL(
    '../../docs/reviews/2026-11-21-session-local-namespace-quote-selector-review.json', import.meta.url)));
  const path = review.path;
  const entry = currentPackageConfigurations[path];
  const reviewedTree = gitTree(root, review.source);
  const body = reviewedTree.read(path).toString();
  const previous = gitTree(root, review.previousRevision).read(path).toString();
  assert.equal(entry.revision, review.source);
  assert.equal(entry.digest, review.sha256);
  assert.equal(hash(body), review.sha256);
  assert.equal(hash(previous), review.previousSha256);
  assert.equal(Buffer.byteLength(body), review.bytes);
  assert.equal(Buffer.byteLength(previous), review.previousBytes);
  assert.equal(reviewedTree.entries.get(path)?.mode, review.mode);
  assert.equal(currentTree.entries.get(path)?.mode, review.mode);
  let reconstructed = body;
  for (const selector of review.addedSelectors) {
    assert.deepEqual(selector.targets, ['js']);
    const line = `    "${selector.file}": [ "js" ],\n`;
    assert.equal(reconstructed.split(line).length, 2);
    reconstructed = reconstructed.replace(line, '');
  }
  assert.equal(reconstructed, previous, 'Imports, aliases, hooks and every preceding option remain exact');
  const priorReview = JSON.parse(readFileSync(new URL('../../' + review.previousReview, import.meta.url)));
  assert.equal(priorReview.source, review.previousRevision);
  assert.equal(priorReview.sha256, review.previousSha256);
  assert.equal(priorReview.bytes, review.previousBytes);
  for (const fixture of [...review.fixtures, ...review.fixtureDependencies]) {
    assert.equal(hash(reviewedTree.read(fixture.path)), fixture.sha256);
    assert.equal(reviewedTree.read(fixture.path).length, fixture.bytes);
    assert.equal(reviewedTree.entries.get(fixture.path)?.mode, fixture.mode);
  }
  for (const fixture of review.fixtures) for (const dependency of fixture.jsFixtureDependencies) {
    assert(body.includes(`    "${dependency}": [ "js" ],\n`),
      `Original JS fixture dependency: ${dependency}`);
  }
  assert.deepEqual(packageImports(body).imports, packageImports(previous).imports);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert(!selected.unresolved.includes('Unreviewed package configuration: ' + path));
  assert(selected.packageConfigurations.some(value => value.path === path && value.digest === review.sha256));
  for (const selector of review.addedSelectors) {
    const source = 'src/client_local_host/' + selector.file;
    assert(selected.paths.includes(source));
    assert.equal(currentTree.entries.get(source)?.kind, 'blob');
    assert.equal(currentTree.entries.get(source)?.mode, '100644');
  }
  for (const changed of [
    ...review.addedSelectors.flatMap(selector => {
      const original = `    "${selector.file}": [ "js" ],\n`;
      return [body.replace(original, ''), body.replace(original, original.replace('"js"', '"native"'))];
    }),
    body + '\noptions(pre_build: "unreviewed-hook")\n',
    body.replace('"actql/actql/decode_shape" @shape', '"actql/actql/decode_shape" @permission'),
  ]) {
    assert.notEqual(changed, body);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const changedTree = {...currentTree, read(file) {
      return file === path ? Buffer.from(changed) : currentTree.read(file);
    }};
    assert(packageSourceInputs({tree: changedTree, packages: ['src/client_local_host'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const changed of [{target: 'native'}, {toolchainDigest: '0'.repeat(64)}, {path: 'src/foreign/moon.pkg'}]) {
    assert.equal(currentPackageConfigurationReviewFor({...request(path, review.sha256), ...changed}), null);
  }
  assert.equal(currentPackageConfigurationReviewFor(request(path, review.previousSha256)), null);
});

test('the prior Local descriptor stays historical without admitting it as current', () => {
  const path = 'src/client_local_host/moon.pkg';
  for (const [revision, digest] of [
    ['ea209b7776eef4934202b8a2924a07464a43bdd7', '6c3f796557c52242f7702c3cb66380d91eecd95f7531f0a1d8e5fb1c08c7cd03'],
    ['3cb1294bbc2c2c8f49580b99eda135c7140c9d40', 'b30ff1c30337f7ac7903f712f8768ba44d7b59194e3b1d20fa92627d208a6f6f'],
    ['24bf383caf9ad31fe921410ee6da2cd30ee4cb47', '6dbacda120b06ee3b75b7748c466e26e3ede49564cb296c89607513a009eccad'],
    ['8385cf48bbffd611f7fa62e872a21c764aa7787f', '497f93c3defd265ba83791d7a8c3290302f368406e1d348f04a5d5f1c472fefd'],
    ['942da5f7cff320f37489be12498fee6f742c40c3', 'b0d5e68d9e82221e6ae49e364de6175ca92377e8227443eafa84149e5ee25b23'],
    ['776746d359ec107cf3172d90016d07e009384fc9', '8c60608fabbcc3310000730ac92fb17768d5b87796e189a192dd1bee513f3ce8'],
    ['4d25879b4f9443cfc73758b948fc472401a5a96e', '4411b9a5d341bf6d5ab235cb1c1a4f99ac12de9387b08f582bbe9e41c610f359'],
  ]) {
    assert.equal(hash(gitTree(root, revision).read(path)), digest);
    assert.equal(currentPackageConfigurationReviewFor(request(path, digest)), null);
  }
});

test('current timestamp dependency review binds both literal imports and complete original child sources', () => {
  const review = JSON.parse(readFileSync(new URL(
    '../../docs/reviews/2026-11-18-session-timestamp-pattern-import-review.json', import.meta.url)));
  const reviewed = gitTree(root, review.source), previous = gitTree(root, review.previousRevision);
  execFileSync('git', ['merge-base', '--is-ancestor', review.source, 'HEAD'], {cwd: root});
  const entry = currentPackageConfigurations[review.path];
  assert.equal(entry.revision, review.source);
  assert.equal(entry.digest, review.sha256);
  const body = reviewed.read(review.path).toString(), prior = previous.read(review.path).toString();
  assert.equal(hash(body), review.sha256);
  assert.equal(hash(prior), review.previousSha256);
  assert.equal(Buffer.byteLength(body), review.bytes);
  assert.equal(Buffer.byteLength(prior), review.previousBytes);
  assert.equal(reviewed.entries.get(review.path)?.mode, review.mode);
  assert.equal(currentTree.read(review.path).toString(), body);
  for (const path of [review.path, review.companion.path]) {
    const after = reviewed.read(path).toString(), before = previous.read(path).toString();
    assert.equal(after.split(review.addedImport).length, 2);
    assert.equal(after.replace(review.addedImport, ''), before);
    assert.deepEqual(packageImports(after).imports,
      [...packageImports(before).imports, 'actql/actql/timestamp_pattern'].sort());
  }
  const lowering = reviewed.read(review.companion.path);
  assert.equal(hash(lowering), review.companion.sha256);
  assert.equal(lowering.length, review.companion.bytes);
  assert.equal(packageImports(lowering.toString()).unknown, null);
  assert.equal(currentPackageConfigurations[review.companion.path], undefined);
  const selected = packageSourceInputs({tree: currentTree,
    packages: ['src/execution_relation', 'src/lowering_relation'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  const members = [...currentTree.entries.keys()].filter(path =>
    path.startsWith('src/timestamp_pattern/') && !path.slice('src/timestamp_pattern/'.length).includes('/')).sort();
  assert(members.includes('src/timestamp_pattern/moon.pkg'));
  assert.deepEqual(selected.directories.find(value => value.path === 'src/timestamp_pattern/*')?.members, members);
  for (const path of members) {
    assert(selected.paths.includes(path), path);
    assert.equal(currentTree.entries.get(path)?.mode, '100644');
  }
  assert.equal(hash(gitTree(root, review.historicalReviewRevision).read(review.path)), review.previousSha256);
  assert.equal(currentPackageConfigurationReviewFor(request(review.path, review.previousSha256)), null);
  for (const changed of [body.replace('@timestamp', '@unreviewed'),
    body.replace('[ "not", "js" ]', '[ "native" ]'),
    body + '\noptions(pre_build: "unreviewed-hook")\n']) {
    assert.notEqual(changed, body);
    assert.equal(currentPackageConfigurationReviewFor(request(review.path, hash(changed))), null);
    const changedTree = {...currentTree, read: path => path === review.path ? Buffer.from(changed) : currentTree.read(path)};
    assert(packageSourceInputs({tree: changedTree, packages: ['src/execution_relation'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + review.path));
  }
});

test('current capacity observation review binds Native bridges and refuses stale or changed input', () => {
  const review = JSON.parse(readFileSync(new URL(
    '../../docs/reviews/2026-11-20-session-native-capacity-observation-review.json', import.meta.url)));
  const reviewed = gitTree(root, review.source);
  execFileSync('git', ['merge-base', '--is-ancestor', review.source, 'HEAD'], {cwd: root});
  for (const config of review.configurations) {
    const {path, rule} = config;
    const bytes = reviewed.read(path), body = bytes.toString();
    const previous = gitTree(root, config.previousRevision).read(path).toString();
    assert.equal(hash(bytes), config.sha256);
    assert.equal(bytes.length, config.bytes);
    assert.equal(hash(previous), config.previousSha256);
    assert.equal(Buffer.byteLength(previous), config.previousBytes);
    assert.equal(currentTree.entries.get(path)?.mode, config.mode);
    assert.deepEqual(currentTree.read(path), bytes);
    assert.deepEqual(packageImports(body).imports, packageImports(previous).imports);
    assert.deepEqual(currentPackageConfigurationReviewFor(request(path, config.sha256)), {
      revision: review.source, target: 'js', toolchainDigest,
      moonRevision: packageConfigurationReview.moonRevision, rule,
    });
    assert.deepEqual(config.addedSelectors, [
      {file: 'capacity_observation_native.mbt', targets: ['native']},
      {file: 'capacity_observation_unsupported.mbt', targets: ['not', 'native']},
    ]);
    const selectors = config.addedSelectors.map(({file, targets}) =>
      `    "${file}": [ ${targets.map(value => JSON.stringify(value)).join(', ')} ],\n`).join('');
    assert.equal(body.split(selectors).length, 2);
    let reconstructed;
    if (config.nativeStub !== null) {
      assert.equal(config.nativeStub, 'capacity_observation_stub.c');
      assert.equal(rule, 'literal-native-options-with-bound-source-membership');
      const stub = `  "native-stub": [ "${config.nativeStub}" ],\n`;
      assert.equal(body.split(stub).length, 2);
      reconstructed = body.replace(stub, '').replace(selectors, '');
    } else {
      assert.equal(rule, 'literal-target-selectors-with-bound-source-membership');
      reconstructed = body.replace(`\noptions(\n  targets: {\n${selectors}  },\n)\n`, '');
    }
    assert.equal(reconstructed, previous, 'Only the reviewed Native bridge/predicates changed');
    const directory = path.slice(0, -9);
    const selected = packageSourceInputs({tree: currentTree, packages: [directory], target: 'js'});
    assert.deepEqual(selected.unresolved, []);
    const members = [...currentTree.entries.keys()].filter(member => member.startsWith(directory + '/') &&
      !member.slice(directory.length + 1).includes('/')).sort();
    assert.deepEqual(selected.directories.find(entry => entry.path === directory + '/*').members, members);
    for (const member of members) assert(selected.paths.includes(member));
    for (const original of review.bridgeSources.filter(value => value.path.startsWith(directory + '/'))) {
      assert.equal(hash(reviewed.read(original.path)), original.sha256);
      assert.equal(reviewed.read(original.path).length, original.bytes);
      assert.equal(reviewed.entries.get(original.path)?.mode, original.mode);
      assert.equal(currentTree.entries.get(original.path)?.mode, original.mode);
      assert(selected.paths.includes(original.path), 'Native/no-op/C bytes stay keyed on JS');
    }
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(previous))), null);
    const unreviewed = [body + '\noptions(pre_build: "unreviewed")\n',
      body.replace('"capacity_observation_native.mbt": [ "native" ]',
        '"capacity_observation_native.mbt": [ "js" ]')];
    // The prior driver had only ordinary literal imports, which remain a
    // supported input language; it does not inherit this current option review.
    if (packageImports(previous).unknown) unreviewed.push(previous);
    for (const changed of unreviewed) {
      assert.notEqual(changed, body);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
      const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
      assert(packageSourceInputs({tree: altered, packages: [directory], target: 'js'})
        .unresolved.includes('Unreviewed package configuration: ' + path));
    }
  }
  const nativeTest = review.testPackage.configuration;
  assert.equal(review.testPackage.supportedTarget, 'native');
  assert.equal(review.testPackage.JSConfigurationAdmitted, false);
  assert.equal(hash(reviewed.read(nativeTest.path)), nativeTest.sha256);
  const nativeTestDirectory = nativeTest.path.slice(0, -9);
  const parentJS = packageSourceInputs({tree: currentTree, packages: ['src/physical_resources'], target: 'js'});
  assert(!parentJS.paths.some(path => path.startsWith(nativeTestDirectory + '/')));
  assert.equal(currentPackageConfigurationReviewFor(request(nativeTest.path, nativeTest.sha256)), null);
  const directJS = packageSourceInputs({tree: currentTree, packages: [nativeTestDirectory], target: 'js'});
  assert(directJS.unresolved.includes('Unreviewed package configuration: ' + nativeTest.path));
  for (const original of review.testPackage.sources) {
    assert.equal(hash(reviewed.read(original.path)), original.sha256);
    assert.equal(reviewed.entries.get(original.path)?.mode, original.mode);
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

// This selector is bound as JS Source input, not Native runtime acceptance.
test('historical Store scalar successor preserves the exact delivery selector and prior preimages', () => {
  const directory = 'src/platform_native/publication_store', path = directory + '/moon.pkg';
  const revision = '3feeecd4936fcf156d8b5293354332813913e59f';
  const digest = 'dfaf6105d166e28289190c97a9aae16bf4eff037da5cbcd5fa767aeb2ebc8598';
  const priorDigest = '14135602cf019169768a0ebcf33e59a1795c1553b672d6347d34c10fc2ff9618';
  const selector = '    "delivery_chunk_native_wbtest.mbt": [ "native" ],\n';
  const reviewed = gitTree(root, revision), body = reviewed.read(path).toString();
  const prior = gitTree(root, '213f671c7ab7c0fb31c1e8a6c99407fe8e50ce69').read(path).toString();
  assert.equal(Buffer.byteLength(body), 2695);
  assert.equal(Buffer.byteLength(prior), 2641);
  assert.equal(Buffer.byteLength(selector), 54);
  assert.equal(hash(body), digest);
  assert.equal(hash(prior), priorDigest);
  assert.equal(body.split(selector).length, 2);
  assert.equal(body.replace(selector, ''), prior);
  assert.equal(prior, gitTree(root, 'f86f409e62d39511380497cb0fe5639d5259f191').read(path).toString());
  assert.equal(prior, gitTree(root, '268d1d9bfd6bf2c97f396172a12cfa38d24b8306').read(path).toString());
  assert.deepEqual(packageImports(body).imports, packageImports(prior).imports);
  const currentRevision = '5c1a8935e03bfaf9bb95d04e0f6d6d5bb03d82df';
  const currentDigest = 'cd70efa7cfa79c9a765b602ed3550ba518ab66ad6bd3ec7766f00e9e4301818b';
  const scalarImport = '  "actql/actql/decode_scalar" @scalar,\n';
  const currentBody = gitTree(root, currentRevision).read(path).toString();
  assert.equal(Buffer.byteLength(currentBody), 2734);
  assert.equal(Buffer.byteLength(scalarImport), 39);
  assert.equal(hash(currentBody), currentDigest);
  assert.equal(currentBody.split(scalarImport).length, 2);
  assert.equal(currentBody.replace(scalarImport, ''), body);
  assert.deepEqual(packageImports(currentBody).imports,
    [...packageImports(body).imports, 'actql/actql/decode_scalar'].sort());
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  execFileSync('git', ['merge-base', '--is-ancestor', currentRevision, 'HEAD'], {cwd: root});
  assert.equal(currentPackageConfigurationReviewFor(request(path, digest)), null);
  assert.equal(currentPackageConfigurationReviewFor(request(path, currentDigest)), null);
  assert.equal(packageConfigurationReviewFor(request(path, reviewedPackageConfigurations[path]))?.revision,
    packageConfigurationReview.revision, 'The historical configuration keeps its own unchanged review');
});

test('current Store publication constructor selector keeps mutation inputs closed and every source bound', () => {
  const review = nativePublicationReview;
  const directory = 'src/platform_native/publication_store', path = review.path;
  const body = gitTree(root, review.source).read(path).toString();
  const previous = gitTree(root, review.previousRevision).read(path).toString();
  const selector = '    "publication_construction_native.mbt": [ "native" ],\n';
  assert.equal(path, directory + '/moon.pkg');
  assert.deepEqual(review.addedSelectors, [{file: 'publication_construction_native.mbt', targets: ['native']}]);
  assert.deepEqual(currentPackageConfigurations[path], {revision: review.source, digest: review.sha256,
    rule: review.rule});
  assert.equal(Buffer.byteLength(body), review.bytes);
  assert.equal(Buffer.byteLength(previous), review.previousBytes);
  assert.equal(hash(body), review.sha256);
  assert.equal(hash(previous), review.previousSha256);
  assert.equal(body.split(selector).length, 2);
  assert.equal(body.replace(selector, ''), previous,
    'Only the literal Native selector changes; existing imports, aliases, hooks and options remain exact');
  assert.deepEqual(packageImports(body).imports, packageImports(previous).imports);
  execFileSync('git', ['merge-base', '--is-ancestor', review.source, 'HEAD'], {cwd: root});
  assert.equal(currentTree.read(path).toString(), body);
  assert.deepEqual(currentPackageConfigurationReviewFor(request(path, review.sha256)), {
    revision: review.source, target: 'js', toolchainDigest, moonRevision: packageConfigurationReview.moonRevision,
    rule: review.rule,
  });
  const selected = packageSourceInputs({tree: currentTree, packages: [directory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === path)?.review.revision, review.source);
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith(directory + '/') &&
    !member.slice(directory.length + 1).includes('/')).sort();
  assert(members.includes(directory + '/publication_construction_native.mbt'));
  assert(members.includes(directory + '/delivery_chunk_native_wbtest.mbt'));
  assert(members.includes(directory + '/private_evidence_construction.mbt'));
  assert(members.includes(directory + '/private_evidence_construction_wbtest.mbt'));
  assert(members.includes(directory + '/store_format_stub.c'));
  assert.deepEqual(selected.directories.find(entry => entry.path === directory + '/*')?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member), 'Native selection cannot hide Source membership from the JS key');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
  }
  const scalarDirectory = 'src/decode_scalar';
  const scalarMembers = [...currentTree.entries.keys()].filter(member => member.startsWith(scalarDirectory + '/') &&
    !member.slice(scalarDirectory.length + 1).includes('/')).sort();
  assert(scalarMembers.includes(scalarDirectory + '/moon.pkg'));
  assert(scalarMembers.includes(scalarDirectory + '/text.mbt'));
  assert.deepEqual(selected.directories.find(entry => entry.path === scalarDirectory + '/*')?.members, scalarMembers);
  for (const member of scalarMembers) {
    assert(selected.paths.includes(member));
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
  }
  const mutation = mutationSourceInputs(currentTree);
  assert.deepEqual(mutation.unresolved, []);
  assert.equal(mutation.packageConfigurations.find(entry => entry.path === path)?.review.revision, review.source);
  assert(!mutation.directories.some(entry => entry.path === 'src/**'), 'No unresolved fallback masks an open boundary');
  for (const member of members) assert(mutation.paths.includes(member));

  const scalarImport = '  "actql/actql/decode_scalar" @scalar,\n';
  for (const changed of [previous,
    body.replace(selector, selector.replace('"native"', '"js"')),
    body.replace(selector, selector.replace('"native"', '"wasm"')),
    body.replace(selector, selector + '    "unreviewed_chunk_native_wbtest.mbt": [ "native" ],\n'),
    body.replace(scalarImport, scalarImport.replace('@scalar', '@permission')),
    body.replace(scalarImport, scalarImport.replace('decode_scalar', 'unreviewed_scalar')),
    body.replace('"actql/actql/sha256"', '"actql/actql/string"'),
    body.replace('"store_format_stub.c"', '"unreviewed_stub.c"'),
    body.replace('"+js+wasm+native"', '"+js"'),
    body + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.notEqual(changed, body);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: [directory], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)},
    {path: './' + path}, {path: 'src/unreviewed/moon.pkg'}, {digest: review.previousSha256}])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, review.sha256), ...delta}), null);
});


const accountConstructionImports = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-15-account-construction-import-review.json', import.meta.url)));
for (const entry of accountConstructionImports.configurations) {
  test(`Account constructor import successor preserves exact previous descriptor and unknown refusal: ${entry.path}`, () => {
    const before = gitTree(root, entry.previousRevision), selected = gitTree(root, entry.source);
    const previous = before.read(entry.path).toString(), current = selected.read(entry.path).toString();
    assert.equal(previous, entry.previousContent); assert.equal(hash(previous), entry.previousSha256);
    assert.equal(current, entry.content); assert.equal(hash(current), entry.sha256);
    let restored = current;
    for (const line of entry.addedImports) {
      assert.equal(restored.split(line).length, 2); restored = restored.replace(line, '');
    }
    assert.equal(restored, previous, 'Only the exact reviewed ordinary imports changed');
    assert.deepEqual(packageImports(current).imports, [...packageImports(previous).imports,
      ...entry.addedImports.map(line => /"([^"\n]+)"/u.exec(line)[1])].sort());
    assert.equal(currentPackageConfigurations[entry.path].revision, entry.source);
    assert.equal(currentPackageConfigurationReviewFor(request(entry.path, entry.sha256))?.rule, entry.rule);
    assert.equal(currentPackageConfigurationReviewFor(request(entry.path, entry.previousSha256)), null);
    for (const changed of [current+'\noptions(pre_build: {command: "unknown"})\n',
      current.replace('"+js+wasm+native"', '"+js"'),
      current.replace(entry.addedImports[0], '  "actql/actql/unreviewed_owner",\n')]) {
      assert.notEqual(changed, current);
      assert.equal(currentPackageConfigurationReviewFor(request(entry.path, hash(changed))), null);
    }
    for (const delta of [{target:'native'}, {target:'wasm'}, {toolchainDigest:'0'.repeat(64)},
      {path:'./'+entry.path}, {path:'src/unreviewed/moon.pkg'}]) {
      assert.equal(currentPackageConfigurationReviewFor({...request(entry.path, entry.sha256), ...delta}), null);
    }
  });
}
