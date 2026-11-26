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
const nativeEffectfulPublicationReview = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-24-session-native-effectful-publication-selector-review.json', import.meta.url)));
const generatedContentReview = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-25-session-generated-content-test-import-review.json', import.meta.url)));
const sqliteCapacityReview = JSON.parse(readFileSync(new URL(
  '../../docs/reviews/2026-11-19-session-sqlite-key-capacity-selector-review.json', import.meta.url)));
const taskAuthorityReview = JSON.parse(currentTree.read(
  'docs/reviews/2026-11-25-session-explorer-task-authority-review.json'));
const taskAuthorityPaths = ['src/client_local_host/moon.pkg', 'src/physical_strategy_host/moon.pkg'];
const retainedRequestRevision = 'b58d8581136cf7b6783d38031e5753d80d47b2e5';
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
    const selectedTree = taskAuthorityPaths.includes(path) ? currentTree
      : gitTree(root, entry.revision ?? currentConfigurationReviewRevision);
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
      const storeDescriptor = selectedTree.read(path).toString();
      assert.equal(entry.revision, generatedContentReview.source);
      assert.equal(hash(storeDescriptor), generatedContentReview.sha256);
      assert.equal(Buffer.byteLength(storeDescriptor), generatedContentReview.bytes);
      assert.equal(generatedContentReview.previousRevision, nativeEffectfulPublicationReview.source);
      let current = storeDescriptor;
      for (const {package: dependency, alias} of generatedContentReview.testImports) {
        const line = `  "${dependency}" @${alias},\n`;
        assert.equal(storeDescriptor.split(line).length, 2);
        current = current.replace(line, '');
        assert.equal(currentPackageConfigurationReviewFor(
          request(path, hash(storeDescriptor.replace(line, line.replace(`@${alias}`, '@foreign'))))), null);
      }
      assert.equal(current, gitTree(root, nativeEffectfulPublicationReview.source).read(path).toString());
      assert.equal(hash(current), nativeEffectfulPublicationReview.sha256);
      assert.equal(hash(current), generatedContentReview.previousSha256);
      assert.equal(Buffer.byteLength(current), generatedContentReview.previousBytes);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(current))), null);
      assert.deepEqual(packageImports(storeDescriptor).imports, [...new Set([...packageImports(current).imports,
        ...generatedContentReview.testImports.map(entry => entry.package)])].sort());
      const preparationSelector = '    "effectful_preparation_native.mbt": [ "native" ],\n';
      assert.equal(current.split(preparationSelector).length, 2);
      const publication = current.replace(preparationSelector, '');
      assert.equal(publication, gitTree(root, nativePublicationReview.source).read(path).toString());
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(publication))), null);
      const publicationSelector = '    "publication_construction_native.mbt": [ "native" ],\n';
      assert.equal(publication.split(publicationSelector).length, 2);
      const successor = publication.replace(publicationSelector, '');
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
      assert.equal(currentTree.read(path).toString(), storeDescriptor);
      assert.equal(currentPackageConfigurationReviewFor(request(path, hash(prior))), null);
      const selected = packageSourceInputs({tree: currentTree, packages: ['src/platform_native/publication_store'], target: 'js'});
      for (const fixture of generatedContentReview.fixtures) {
        assert.equal(hash(selectedTree.read(fixture.path)), fixture.sha256);
        assert.equal(selectedTree.read(fixture.path).length, fixture.bytes);
        assert.equal(selectedTree.entries.get(fixture.path)?.mode, fixture.mode);
        assert(selected.paths.includes(fixture.path));
      }
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
      const anchor = path === taskAuthorityPaths[0] ? retainedRequestRevision : review.revision;
      execFileSync('git', ['merge-base', '--is-ancestor', anchor, 'HEAD'], {cwd: root});
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

test('current Local JS review binds task authorization, retained Request imports and existing fixture selectors', () => {
  const review = JSON.parse(readFileSync(new URL(
    '../../docs/reviews/2026-11-21-session-local-namespace-quote-selector-review.json', import.meta.url)));
  const path = review.path;
  const entry = currentPackageConfigurations[path];
  const reviewedTree = gitTree(root, review.source);
  const historical = reviewedTree.read(path).toString();
  const previous = gitTree(root, review.previousRevision).read(path).toString();
  assert.equal(hash(historical), review.sha256);
  assert.equal(hash(previous), review.previousSha256);
  assert.equal(Buffer.byteLength(historical), review.bytes);
  assert.equal(Buffer.byteLength(previous), review.previousBytes);
  assert.equal(reviewedTree.entries.get(path)?.mode, review.mode);
  assert.equal(currentTree.entries.get(path)?.mode, review.mode);
  let reconstructed = historical;
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
    assert(historical.includes(`    "${dependency}": [ "js" ],\n`),
      `Original JS fixture dependency: ${dependency}`);
  }
  assert.deepEqual(packageImports(historical).imports, packageImports(previous).imports);
  const intakeTree = gitTree(root, retainedRequestRevision);
  const body = currentTree.read(path).toString();
  assert.equal(hash(body), entry.digest);
  const utf8 = '  "moonbitlang/core/encoding/utf8",\n';
  const string = '  "moonbitlang/core/string",\n';
  const json = '  "moonbitlang/core/json",\n';
  const debug = '  "moonbitlang/core/debug",\n';
  assert.equal(historical.split(utf8 + debug).length, 2);
  assert.equal(historical.split(json).length, 2);
  const retainedRequest = intakeTree.read(path).toString();
  assert.equal(retainedRequest, historical.replace(utf8 + debug, debug).replace(json, utf8 + json + string),
    'The retained Request stage changes only the two ordinary imports');
  const local = taskAuthorityReview.configurations.find(config => config.path === path);
  assert.equal(local.addedImport, '  "actql/actql/execution_authorization" @authorization,\n');
  assert.equal(body.split(local.addedImport).length, 2);
  assert.equal(body.replace(local.addedImport, ''), retainedRequest,
    'Task authority adds one import and preserves every option and target selector');
  assert.equal(hash(retainedRequest), local.previous.sha256);
  assert.equal(currentPackageConfigurationReviewFor(request(path, local.previous.sha256)), null);
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(retainedRequest).imports, 'actql/actql/execution_authorization'].sort());
  assert.equal(currentPackageConfigurationReviewFor(request(path, review.sha256)), null);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert(!selected.unresolved.includes('Unreviewed package configuration: ' + path));
  assert(selected.packageConfigurations.some(value => value.path === path && value.digest === entry.digest));
  assert(selected.paths.includes('src/execution_authorization/moon.pkg'));
  const intake = 'src/client_local_host/preparation_request_retained_intent.mbt';
  assert(selected.paths.includes(intake));
  assert.equal(currentTree.entries.get(intake)?.mode, '100644');
  assert.deepEqual(currentTree.read(intake), intakeTree.read(intake));
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
    body.replace(string, ''),
    body.replace(utf8 + json, json).replace(debug, utf8 + debug),
    body.replace(local.addedImport, ''),
    body.replace(local.addedImport, local.addedImport.replace('@authorization', '@foreign')),
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
    assert.equal(currentPackageConfigurationReviewFor({...request(path, entry.digest), ...changed}), null);
  }
  assert.equal(currentPackageConfigurationReviewFor(request(path, review.previousSha256)), null);
});

test('task authority preserves reviewed old manifests and admits only the exact current JS strategy fixture', () => {
  const review = taskAuthorityReview;
  // The review retains the source and tested tree for provenance. A replacement
  // PR can preserve those bytes without keeping the old PR head as an ancestor.
  for (const identity of [review.head, review.source, review.tree]) assert.match(identity, /^[a-f0-9]{40}$/u);
  execFileSync('git', ['merge-base', '--is-ancestor', review.previousRevision, 'HEAD'], {cwd: root});
  const original = gitTree(root, review.previousRevision);
  assert.deepEqual(review.configurations.map(config => config.path), taskAuthorityPaths);
  for (const config of review.configurations) {
    assert.equal(currentPackageConfigurations[config.path].revision, review.head);
    for (const [snapshot, expected, path] of [[original, config.previous, config.path],
      [currentTree, config, config.path]]) {
      assert.equal(snapshot.entries.get(path)?.mode, expected.mode);
      assert.equal(snapshot.read(path).length, expected.bytes);
      assert.equal(hash(snapshot.read(path)), expected.sha256);
    }
  }
  assert.equal(review.toolchain.sha256, toolchainDigest);
  assert.equal(currentTree.entries.get('toolchain.json')?.mode, review.toolchain.mode);
  assert.equal(currentTree.read('toolchain.json').length, review.toolchain.bytes);
  assert.equal(hash(currentTree.read('toolchain.json')), toolchainDigest);
  const strategy = review.configurations.find(config => config.fixture);
  const path = strategy.path, prior = original.read(path).toString(), body = currentTree.read(path).toString();
  const fixture = strategy.fixture;
  assert.deepEqual(fixture.targets, ['js']);
  assert.equal(fixture.path, 'src/physical_strategy_host/task_completion_current_js_wbtest.mbt');
  assert.equal(strategy.addedBlock,
    '\nimport {\n  "moonbitlang/core/debug",\n} for "wbtest"\n\noptions(\n  targets: { "task_completion_current_js_wbtest.mbt": [ "js" ] },\n)\n');
  assert.equal(body, prior + strategy.addedBlock);
  assert.deepEqual(packageImports(body).imports, [...packageImports(prior).imports, 'moonbitlang/core/debug'].sort());
  assert.equal(currentTree.entries.get(fixture.path)?.mode, fixture.mode);
  assert.equal(currentTree.read(fixture.path).length, fixture.bytes);
  assert.equal(hash(currentTree.read(fixture.path)), fixture.sha256);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/physical_strategy_host'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert(selected.paths.includes(fixture.path));
  assert(selected.packageConfigurations.some(entry => entry.path === path && entry.digest === strategy.sha256));
  for (const changed of [prior, body.replace('"js"', '"native"'),
    body.replace('for "wbtest"', 'for "test"'), body + '\noptions(pre_build: "unreviewed-hook")\n']) {
    assert.notEqual(changed, body);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
  }
  assert.equal(currentPackageConfigurationReviewFor({...request(path, strategy.sha256), target: 'native'}), null);
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
    ['b58d8581136cf7b6783d38031e5753d80d47b2e5', '69f0f83ea6b499104c1e5b501a6b7b47511e62d422d85cc9281fca18a375d63b'],
  ]) {
    assert.equal(hash(gitTree(root, revision).read(path)), digest);
    assert.equal(currentPackageConfigurationReviewFor(request(path, digest)), null);
  }
});

test('archived timestamp dependency review binds both literal imports and complete child sources', () => {
  const review = JSON.parse(readFileSync(new URL(
    '../../docs/reviews/2026-11-18-session-timestamp-pattern-import-review.json', import.meta.url)));
  const reviewed = gitTree(root, review.source), previous = gitTree(root, review.previousRevision);
  execFileSync('git', ['merge-base', '--is-ancestor', review.source, 'HEAD'], {cwd: root});
  assert.equal(currentPackageConfigurationReviewFor(request(review.path, review.sha256)), null,
    'The timestamp preimage is historical after the regex imports');
  const body = reviewed.read(review.path).toString(), prior = previous.read(review.path).toString();
  assert.equal(hash(body), review.sha256);
  assert.equal(hash(prior), review.previousSha256);
  assert.equal(Buffer.byteLength(body), review.bytes);
  assert.equal(Buffer.byteLength(prior), review.previousBytes);
  assert.equal(reviewed.entries.get(review.path)?.mode, review.mode);
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

test('current regex imports bind both literal aliases and complete pattern and replacement package inputs', () => {
  const prior = gitTree(root, 'eb441ff1ed3c42bd243730306d883d1ddee41d45');
  const revision = '9c50dd42067fb1298123c07e751070cf13222f43';
  const reviewed = gitTree(root, revision);
  const relation = 'src/execution_relation';
  const lowering = 'src/lowering_relation';
  const path = relation + '/moon.pkg';
  const entry = currentPackageConfigurations[path];
  const shaRevision = '31411703b2bc9af39aba83db2eb7c0174472eb46';
  const shaReview = gitTree(root, shaRevision);
  const packages = {
    regex_pattern: {alias: 'regex', members: [
      'emit.mbt', 'matcher.mbt', 'matcher_test.mbt', 'moon.pkg', 'parser.mbt',
      'pattern_test.mbt', 'pkg.generated.mbti', 'types.mbt', 'vectors.generated_test.mbt',
    ]},
    regex_replacement: {alias: 'replacement', members: [
      'moon.pkg', 'pkg.generated.mbti', 'replacement.mbt', 'replacement_test.mbt',
      'sql_replacement_test.mbt', 'vectors.generated_test.mbt',
    ]},
  };
  assert.equal(entry.revision, shaRevision);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  execFileSync('git', ['merge-base', '--is-ancestor', shaRevision, 'HEAD'], {cwd: root});
  const body = reviewed.read(path).toString();
  assert.equal(hash(body), 'ed50ecf39857c24b0f7f166c038131cd92ff32be335497c10bc63d50770fd7eb');
  assert.equal(reviewed.entries.get(path)?.mode, '100644');
  const successor = shaReview.read(path).toString();
  assert.equal(hash(successor), entry.digest);
  assert.equal(currentTree.read(path).toString(), successor);
  assert.equal(shaReview.entries.get(path)?.mode, '100644');
  const shaImport = '  "actql/actql/sha256" @sha,\n';
  const encoder = '  "actql/actql/encode_core" @encode,\n';
  const slack = '  "actql/actql/connectors/slack/catalog" @slack,\n';
  assert.equal(successor.split(shaImport).length, 2);
  assert.equal(successor.split(encoder + shaImport).length, 2);
  assert.equal(successor.split(slack).length, 2);
  assert.equal(successor.replace(encoder + shaImport, encoder).replace(slack, slack + shaImport), body);

  for (const directory of [relation, lowering]) {
    const manifest = directory + '/moon.pkg';
    const before = prior.read(manifest).toString(), after = reviewed.read(manifest).toString();
    let reconstructed = after;
    for (const [name, {alias}] of Object.entries(packages)) {
      const line = `  "actql/actql/${name}" @${alias},\n`;
      assert.equal(reconstructed.split(line).length, 2, manifest);
      reconstructed = reconstructed.replace(line, '');
    }
    assert.equal(reconstructed, before, manifest);
    assert.deepEqual(packageImports(after).imports, [
      ...packageImports(before).imports, ...Object.keys(packages).map(name => 'actql/actql/' + name),
    ].sort());
  }
  const loweringManifest = currentTree.read(lowering + '/moon.pkg').toString();
  assert.equal(loweringManifest, reviewed.read(lowering + '/moon.pkg').toString());
  assert.equal(packageImports(loweringManifest).unknown, null);
  assert.equal(currentPackageConfigurations[lowering + '/moon.pkg'], undefined);

  const selected = packageSourceInputs({tree: currentTree, packages: [relation, lowering], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert(selected.directories.some(row => row.path === 'src/sha256/*'));
  const mutation = mutationSourceInputs(currentTree);
  assert.deepEqual(mutation.unresolved, []);
  assert(!mutation.directories.some(row => row.path === 'src/**'));
  for (const [name, {members}] of Object.entries(packages)) {
    const directory = 'src/' + name;
    const manifest = directory + '/moon.pkg';
    assert.equal(packageImports(reviewed.read(manifest).toString()).unknown, null);
    assert.equal(currentPackageConfigurations[manifest], undefined);
    const reviewedMembers = [...reviewed.entries.keys()].filter(member =>
      member.startsWith(directory + '/') && !member.slice(directory.length + 1).includes('/')).sort();
    assert.deepEqual(reviewedMembers, members.map(member => directory + '/' + member));
    const currentMembers = [...currentTree.entries.keys()].filter(member =>
      member.startsWith(directory + '/') && !member.slice(directory.length + 1).includes('/')).sort();
    for (const selection of [selected, mutation]) {
      assert.deepEqual(selection.directories.find(row => row.path === directory + '/*')?.members, currentMembers);
      for (const member of currentMembers) {
        assert(selection.paths.includes(member), member);
        assert.equal(currentTree.entries.get(member)?.kind, 'blob');
        assert.equal(currentTree.entries.get(member)?.mode, '100644');
      }
    }
  }
  for (const changed of [prior.read(path).toString(), body, successor.replace('@regex', '@unreviewed'),
    successor.replace('regex_replacement', 'unreviewed_replacement'),
    successor.replace('[ "not", "js" ]', '[ "native" ]'),
    successor + '\noptions(pre_build: "unreviewed-hook")\n']) {
    assert.notEqual(changed, successor);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const changedTree = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: changedTree, packages: [relation], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
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

test('current Store publication preparation selector keeps mutation inputs closed and every source bound', () => {
  const review = nativeEffectfulPublicationReview, currentReview = generatedContentReview;
  const directory = 'src/platform_native/publication_store', path = review.path;
  const authored = gitTree(root, review.source);
  const body = authored.read(path).toString();
  const previous = gitTree(root, review.previousRevision).read(path).toString();
  const selector = '    "effectful_preparation_native.mbt": [ "native" ],\n';
  assert.equal(path, directory + '/moon.pkg');
  assert.equal(review.addedSelector.file, 'effectful_preparation_native.mbt');
  assert.deepEqual(review.addedSelector.targets, ['native']);
  const priorReview = JSON.parse(readFileSync(new URL('../../' + review.previousReview, import.meta.url)));
  assert.deepEqual([review.previousRevision, review.previousSha256, review.previousBytes],
    [priorReview.source, priorReview.sha256, priorReview.bytes]);
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', review.source],
    {cwd: root, encoding: 'utf8'}).trim(), review.parent);
  assert.equal(gitTree(root, review.parent).read(path).toString(), previous);
  assert.deepEqual(currentPackageConfigurations[path], {revision: currentReview.source,
    digest: currentReview.sha256, rule: currentReview.rule});
  assert.equal(authored.entries.get(path)?.mode, review.mode);
  assert.equal(currentTree.entries.get(path)?.mode, review.mode);
  assert.equal(Buffer.byteLength(body), review.bytes);
  assert.equal(Buffer.byteLength(previous), review.previousBytes);
  assert.equal(hash(body), review.sha256);
  assert.equal(hash(previous), review.previousSha256);
  assert.equal(body.split(selector).length, 2);
  assert.equal(body.replace(selector, ''), previous,
    'Only the literal Native selector changes; existing imports, aliases, hooks and options remain exact');
  assert.deepEqual(packageImports(body).imports, packageImports(previous).imports);
  execFileSync('git', ['merge-base', '--is-ancestor', review.source, 'HEAD'], {cwd: root});
  const current = currentTree.read(path).toString();
  assert.equal(hash(current), currentReview.sha256);
  assert.equal(currentPackageConfigurationReviewFor(request(path, review.sha256)), null);
  assert.deepEqual(currentPackageConfigurationReviewFor(request(path, currentReview.sha256)), {
    revision: currentReview.source, target: 'js', toolchainDigest, moonRevision: packageConfigurationReview.moonRevision,
    rule: currentReview.rule,
  });
  const selected = packageSourceInputs({tree: currentTree, packages: [directory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === path)?.review.revision, currentReview.source);
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith(directory + '/') &&
    !member.slice(directory.length + 1).includes('/')).sort();
  const implementation = directory + '/' + review.addedSelector.file;
  assert.equal(authored.entries.get(implementation)?.mode, review.addedSelector.mode);
  assert.equal(authored.entries.get(implementation)?.kind, 'blob');
  assert.equal(authored.read(implementation).length, review.addedSelector.bytes);
  assert.equal(hash(authored.read(implementation)), review.addedSelector.sha256);
  assert(members.includes(implementation));
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
  assert.equal(mutation.packageConfigurations.find(entry => entry.path === path)?.review.revision, currentReview.source);
  assert(!mutation.directories.some(entry => entry.path === 'src/**'), 'No unresolved fallback masks an open boundary');
  for (const member of members) assert(mutation.paths.includes(member));

  const scalarImport = '  "actql/actql/decode_scalar" @scalar,\n';
  const constructorSelector = '    "publication_construction_native.mbt": [ "native" ],\n';
  for (const changed of [previous, body,
    current.replace(selector, selector.replace('"native"', '"js"')),
    current.replace(selector, selector.replace('"native"', '"wasm"')),
    current.replace(constructorSelector, constructorSelector.replace('"native"', '"js"')),
    current.replace(constructorSelector, constructorSelector.replace('"native"', '"wasm"')),
    current.replace(selector, selector + '    "unreviewed_chunk_native_wbtest.mbt": [ "native" ],\n'),
    current.replace(scalarImport, scalarImport.replace('@scalar', '@permission')),
    current.replace(scalarImport, scalarImport.replace('decode_scalar', 'unreviewed_scalar')),
    current.replace('"actql/actql/sha256"', '"actql/actql/string"'),
    current.replace('"store_format_stub.c"', '"unreviewed_stub.c"'),
    current.replace('"+js+wasm+native"', '"+js"'),
    current + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.notEqual(changed, current);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: [directory], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)},
    {path: './' + path}, {path: 'src/unreviewed/moon.pkg'}, {digest: review.sha256}, {digest: review.previousSha256}])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, currentReview.sha256), ...delta}), null);
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
