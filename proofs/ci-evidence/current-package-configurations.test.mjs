import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageSourceInputs, packageImports} from './inputs.mjs';
import {currentConfigurationReviewRevision, currentPackageConfigurations,
  currentPackageConfigurationReviewFor, currentNestedFixtureConfigurations, reviewedNestedFixture,
  packageConfigurationReview, packageConfigurationReviewFor, reviewedPackageConfigurations} from './package-configurations.mjs';

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
    if (path === 'src/platform_native/publication_store/moon.pkg') {
      assert.equal(entry.revision, '5c1a8935e03bfaf9bb95d04e0f6d6d5bb03d82df');
      const successor = selectedTree.read(path).toString();
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
      assert.equal(currentTree.read(path).toString(), successor);
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
      const prior = gitTree(root, '523ada3259bf9e8147f746727fbfd56065036fd5').read(path).toString();
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

test('current Local Host successor binds its pure Ledger-open import and preserves prior preimages', () => {
  const path = 'src/client_local_host/moon.pkg';
  const revision = 'db039dc07a845fc420be9f95b750fe5208183735';
  const digest = '1ce3256e4f3b1dc32ee5136fcbbe5076fd996ad0a05c901a5cd175a3b16af326';
  const rule = 'literal-target-selectors-with-bound-source-membership';
  const currentRevision = '3c5dcdf49b732d4510360580d2ad3304252de3b7';
  const currentDigest = '63dd3e4a78397a73ba2991b8c656d4d699234c67c6d01d11c2058047bc397ef6';
  const scopeRevision = 'ff4e214d60984ee7b5c42ae57943d0b6d3e95437';
  const catalogRevision = 'f213d49c0748b99a69ae25fd462e8f9d500d7109';
  const catalogDigest = '11e08f7a636e2e73d47863ea626632b5dbf6e45e16ba00a32a27952c72e4007e';
  assert.deepEqual(currentPackageConfigurations[path], {revision: currentRevision, digest: currentDigest, rule});
  execFileSync('git', ['merge-base', '--is-ancestor', currentRevision, 'HEAD'], {cwd: root});
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const reviewed = gitTree(root, revision), body = reviewed.read(path).toString();
  const keyedSelector = '    "request_native_keyed_plan_js_wbtest.mbt": [ "js" ],\n';
  const currentBody = gitTree(root, currentRevision).read(path).toString();
  const scopeBody = gitTree(root, scopeRevision).read(path).toString();
  const completionSelectors = ['installed_effect_header_lifetime_js_wbtest.mbt',
    'installed_effect_native_control_js_wbtest.mbt', 'installed_effect_discarded_projection_js_wbtest.mbt']
    .map(name => `    "${name}": [ "js" ],\n`);
  let beforeCompletion = currentBody;
  for (const selector of completionSelectors) {
    assert.equal(currentBody.split(selector).length, 2);
    beforeCompletion = beforeCompletion.replace(selector, '');
  }
  assert.equal(beforeCompletion, scopeBody,
    'only the three reviewed JS-only regressions extend the complete scope descriptor');
  assert.equal(hash(scopeBody), '590ae12dd0826dd9143d9cc62babaf713cff15d82cdf5efafe0621234f5fefee');
  assert.deepEqual(packageImports(currentBody).imports, packageImports(scopeBody).imports);
  execFileSync('git', ['merge-base', '--is-ancestor', scopeRevision, currentRevision], {cwd: root});
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(scopeBody))), null);
  const catalogBody = gitTree(root, catalogRevision).read(path).toString();
  execFileSync('git', ['merge-base', '--is-ancestor', catalogRevision, currentRevision], {cwd: root});
  const scopeImport = '  "actql/actql/logical_request_scope" @request_scope,\n';
  assert.equal(Buffer.byteLength(currentBody), 10215);
  assert.equal(Buffer.byteLength(scopeBody), 10019);
  assert.equal(Buffer.byteLength(scopeImport), 54);
  assert.equal(hash(currentBody), currentDigest);
  assert.equal(currentBody.split(scopeImport).length, 2);
  assert.equal(scopeBody.replace(scopeImport, ''), catalogBody,
    'only the pure scope-construction inventory import extends the complete reviewed descriptor');
  const productionImports = currentBody.match(/\nimport \{([^{}]*)\}\n/u);
  assert(productionImports && productionImports[1].includes(scopeImport),
    'the actual Ledger-open quantity consumer retains its production dependency');
  assert.deepEqual(packageImports(currentBody).imports,
    [...packageImports(catalogBody).imports, 'actql/actql/logical_request_scope'].sort());
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(catalogBody))), null,
    'the earlier WB descriptor cannot qualify this current production dependency');
  const reentryRevision = '1d65ca8b449c6a6edae8ba0b5a0b0bfbed05a243';
  const reentryBody = gitTree(root, reentryRevision).read(path).toString();
  execFileSync('git', ['merge-base', '--is-ancestor', reentryRevision, currentRevision], {cwd: root});
  const catalogImport = '  "actql/actql/connectors/hubspot/catalog" @hubspot_catalog,\n';
  assert.equal(Buffer.byteLength(catalogBody), 9965);
  assert.equal(Buffer.byteLength(catalogImport), 61);
  assert.equal(hash(catalogBody), catalogDigest);
  assert.equal(catalogBody.split(catalogImport).length, 2);
  assert.equal(catalogBody.replace(catalogImport, ''), reentryBody,
    'only the reviewed literal HubSpot Catalog WB import extends the complete prior descriptor');
  const whiteboxImports = catalogBody.match(/\nimport \{([^{}]*)\} for "wbtest"/u);
  assert(whiteboxImports);
  assert(whiteboxImports[1].includes(catalogImport), 'the Catalog dependency remains whitebox-only');
  assert.deepEqual(packageImports(catalogBody).imports,
    [...packageImports(reentryBody).imports, 'actql/actql/connectors/hubspot/catalog'].sort());
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(reentryBody))), null);
  const reentrySelector = '    "managed_import_reentry_js_wbtest.mbt": [ "js" ],\n';
  assert.equal(Buffer.byteLength(reentryBody), 9904);
  assert.equal(Buffer.byteLength(reentrySelector), 54);
  assert.equal(hash(reentryBody), 'e48db6b1683f6b841e56439452a65388f5298549e6c8b740e117a40359d8c8b5');
  assert.equal(reentryBody.split(reentrySelector).length, 2);
  assert.equal(reentryBody.replace(reentrySelector, ''), body,
    'only the actual original Node Resource current regression selector extends the keyed Plan descriptor');
  assert.deepEqual(packageImports(reentryBody).imports, packageImports(body).imports);

  const effectBody = gitTree(root, '70ab00c1fae78c176ac34e65857f7332d6619aa7').read(path).toString();
  assert.equal(hash(effectBody), '64220f07f198e537a6d9c785fd6abd93a2a3293f3959a24fc313f63135ae1d66');
  assert.equal(Buffer.byteLength(body), 9850);
  assert.equal(Buffer.byteLength(effectBody), 9793);
  assert.equal(Buffer.byteLength(keyedSelector), 57);
  assert.equal(body.split(keyedSelector).length, 2);
  assert.equal(body.replace(keyedSelector, ''), effectBody,
    'only the existing Node Request parent fixture selector extends the reviewed descriptor');
  assert.deepEqual(packageImports(body).imports, packageImports(effectBody).imports,
    'every dependency, alias and other target or option retains its original bytes');
  const originalSelector = '    "preparation_request_effect_original_js_wbtest.mbt": [ "js" ],\n';
  const valuesBody = gitTree(root, 'e99acee7bc3ea3a5b0ae3e71ce64aa7c958f2bf4').read(path).toString();
  assert.equal(hash(valuesBody), '0974fff42f958477654738b726f07d929aeccd274463404fc86206545fff2f00');
  assert.equal(body.split(originalSelector).length, 2);
  assert.equal(effectBody.replace(originalSelector, ''), valuesBody,
    'only the original Effect JS fixture selector extends the reviewed descriptor');
  assert.deepEqual(packageImports(body).imports, packageImports(valuesBody).imports,
    'the existing literal UTF-8 whitebox import and every other dependency remain exact');
  const valuesSelector = '    "original_values_text_working_js_wbtest.mbt": [ "js" ],\n';
  const callbackBody = gitTree(root, 'd3aed5e30374353163fe2beb3f7a8b4f784b2ea9').read(path).toString();
  assert.equal(hash(callbackBody), '508773432a6b071bb057fc41d51008054462a6f8006f862ce6638e91e448d00e');
  assert.equal(valuesBody.split(valuesSelector).length, 2);
  assert.equal(valuesBody.replace(valuesSelector, ''), callbackBody,
    'only the existing JS Values callback selector extends the reviewed descriptor');
  assert.deepEqual(packageImports(body).imports, packageImports(callbackBody).imports);
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
    'preparation_request_artifact_retention_js_wbtest.mbt', 'native_publication_workspace_js_wbtest.mbt'].map(name => `    "${name}": [ "js" ],\n`);
  let reconstructedIntroduction = callbackBody;
  for (const selector of successorSelectors) {
    assert.equal(callbackBody.split(selector).length, 2);
    reconstructedIntroduction = reconstructedIntroduction.replace(selector, '');
  }
  assert.equal(reconstructedIntroduction, introduced, 'the successor adds only its three reviewed JS fixtures');
  const intakeRevision = gitTree(root, '131b446df837e49f6277c8582460e521dd97c153').read(path).toString();
  assert.equal(hash(intakeRevision), '2d1cea3783b4e932e2dd107b4159e8b32dad4f1f57470ee8d3cbd1d30e319802');
  assert.equal(callbackBody.replace(successorSelectors[2], ''), intakeRevision,
    'the new publication fixture preserves the two original intake/artifact selectors');
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(intakeRevision))), null);
  assert.deepEqual(packageImports(body).imports,
    [...packageImports(previous).imports, 'actql/actql/capacity_policy'].sort());
  assert.equal(currentTree.read(path).toString(), currentBody);
  assert.equal(hash(currentTree.read('toolchain.json')), toolchainDigest);
  assert.equal(currentPackageConfigurationReviewFor(request(path, currentDigest))?.revision, currentRevision);
  assert.equal(currentPackageConfigurationReviewFor(request(path, digest)), null);
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(previous))), null);
  assert.equal(currentPackageConfigurationReviewFor(request(path, hash(introduced))), null);
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/client_local_host'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith('src/capacity_policy/') &&
    !member.slice('src/capacity_policy/'.length).includes('/')).sort();
  assert(members.includes('src/capacity_policy/moon.pkg'));
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/capacity_policy/*')?.members, members);
  const catalogMembers = [...currentTree.entries.keys()].filter(member => member.startsWith('src/connectors/hubspot/catalog/') &&
    !member.slice('src/connectors/hubspot/catalog/'.length).includes('/')).sort();
  assert(catalogMembers.includes('src/connectors/hubspot/catalog/moon.pkg'));
  assert(catalogMembers.includes('src/connectors/hubspot/catalog/source_read_construction.mbt'));
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/connectors/hubspot/catalog/*')?.members, catalogMembers);
  const scopeMembers = [...currentTree.entries.keys()].filter(member => member.startsWith('src/logical_request_scope/') &&
    !member.slice('src/logical_request_scope/'.length).includes('/')).sort();
  assert(scopeMembers.includes('src/logical_request_scope/scope.mbt'));
  assert(scopeMembers.includes('src/logical_request_scope/pkg.generated.mbti'));
  assert.deepEqual(selected.directories.find(entry => entry.path === 'src/logical_request_scope/*')?.members, scopeMembers);
  assert.deepEqual(packageImports(currentTree.read('src/logical_request_scope/moon.pkg').toString()).imports,
    ['actql/actql/canonical_value', 'actql/actql/encode_core', 'actql/actql/sha256', 'moonbitlang/core/encoding/utf8'].sort());
  for (const member of [...members, ...catalogMembers, ...scopeMembers, ...[reentrySelector, keyedSelector, originalSelector, valuesSelector, ...selectors, ...successorSelectors, ...completionSelectors].map(selector =>
    'src/client_local_host/' + JSON.parse(selector.trim().split(':')[0]))]) {
    assert(selected.paths.includes(member), member);
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  for (const changed of [previous, callbackBody, valuesBody, effectBody, body, reentryBody, catalogBody,
    currentBody.replace('@request_scope,', '@unreviewed_scope,'),
    currentBody.replace('actql/actql/logical_request_scope', 'actql/actql/unreviewed_scope'),
    currentBody.replace(scopeImport, scopeImport + '  "actql/actql/unreviewed_scope" @extra,\n'),
    currentBody.replace('@hubspot_catalog,', '@unreviewed_hubspot,'),
    currentBody.replace('actql/actql/connectors/hubspot/catalog', 'actql/actql/unreviewed_catalog'),
    currentBody.replace(dependency, ''), currentBody.replace('@capacity,', '@permission,'),
    currentBody.replace('"moonbitlang/core/encoding/utf8"', '"moonbitlang/core/encoding/utf16"'),
    ...[reentrySelector, keyedSelector, originalSelector, valuesSelector, ...selectors, ...successorSelectors].map(selector => currentBody.replace(selector, selector.replace('"js"', '"native"'))),
    ...completionSelectors.flatMap(selector => [currentBody.replace(selector, ''),
      currentBody.replace(selector, selector.replace('"js"', '"native"')),
      currentBody.replace(selector, selector.replace('"js"', '"wasm"'))]),
    currentBody.replace(keyedSelector, keyedSelector + '    "unreviewed_keyed_target.mbt": [ "js" ],\n'),
    currentBody + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: ['src/client_local_host'], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, currentDigest), ...delta}), null);
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
  assert.equal(Object.keys(currentPackageConfigurations).length, 20);
  assert.equal(Object.values(currentPackageConfigurations).filter(entry => entry.revision !== undefined).length, 14);
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

test('current JS foreign library binds only the original Whole input schema and DuckDB imports', () => {
  const path = 'src/connectors_builtin_node/moon.pkg';
  const revision = '6f27dfdf10aa232977277ec8580557463e44e81f';
  const digest = 'd515c9868140c30ef68b5778b71863813cad0d53cc7300e4ba8fcc3e00405d9d';
  const prior = gitTree(root, '66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c').read(path).toString();
  const body = gitTree(root, revision).read(path).toString();
  const imports = '  "actql/actql/relation_schema" @schema,\n' +
    '  "actql/actql/connectors/duckdb/adapter" @duckdb_input,\n';
  assert.equal(hash(prior), '707ebd62113403d8c1a08c3db9ea28d5e899c3c80d6ac7dc5cfadd545045ac38');
  assert.equal(hash(body), digest);
  assert.equal(body.split(imports).length, 2);
  assert.equal(body.replace(imports, ''), prior, 'kind, targets, aliases and every other option remain exact');
  assert.deepEqual(packageImports(body).imports, [...packageImports(prior).imports,
    'actql/actql/relation_schema', 'actql/actql/connectors/duckdb/adapter'].sort());
  assert.deepEqual(currentPackageConfigurations[path], {revision, digest,
    rule: 'literal-js-foreign-library-with-bound-source-membership'});
  assert.equal(currentTree.read(path).toString(), body);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/connectors_builtin_node'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  for (const member of ['src/relation_schema/moon.pkg', 'src/connectors/duckdb/adapter/moon.pkg',
    'src/connectors_builtin_node/client_whole_source_capture_bridge.mbt']) {
    assert(selected.paths.includes(member), member);
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  for (const changed of [prior, body.replace('@duckdb_input', '@foreign_input'),
    body.replace('pkgtype(kind: "foreign_library")', 'pkgtype(kind: "library")'),
    body + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
  }
});

test('current Text target review keeps both original sizing files and unchanged imports in the key', () => {
  const path = 'src/execution_relation/moon.pkg';
  const revision = '6813ab0330a17f99c8eef5c9f4a70480ecc7e96c';
  const digest = '2a223e06a52cbb8c01280e9d5c5132485434728f59271ff02900f74ea582d079';
  const prior = gitTree(root, '549b54952ceae6eea91bf6ed5dacd42dfd028e14').read(path).toString();
  const body = gitTree(root, revision).read(path).toString();
  const selectors = '\noptions(\n  targets: {\n' +
    '    "text_workspace_growth_js.mbt": [ "js" ],\n' +
    '    "text_workspace_growth_nonjs.mbt": [ "not", "js" ],\n  },\n)\n';
  assert.equal(hash(body), digest);
  assert.equal(body.split(selectors).length, 2);
  assert.equal(body.replace(selectors, ''), prior);
  assert.deepEqual(packageImports(body).imports, packageImports(prior).imports);
  assert.deepEqual(currentPackageConfigurations[path], {revision, digest,
    rule: 'literal-target-selectors-with-bound-source-membership'});
  assert.equal(currentTree.read(path).toString(), body);
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  const selected = packageSourceInputs({tree: currentTree, packages: ['src/execution_relation'], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  for (const name of ['text_workspace_growth.mbt', 'text_workspace_growth_js.mbt',
    'text_workspace_growth_nonjs.mbt', 'text_workspace_growth_wbtest.mbt']) {
    const member = 'src/execution_relation/' + name;
    assert(selected.paths.includes(member), 'Target routing cannot hide nonselected source or tests');
    assert.equal(currentTree.entries.get(member)?.kind, 'blob');
    assert.equal(currentTree.entries.get(member)?.mode, '100644');
  }
  for (const changed of [prior, body.replace('[ "js" ]', '[ "native" ]'),
    body.replace('text_workspace_growth_nonjs.mbt', 'unreviewed.mbt'),
    body + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
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

// This selector is bound as JS Source input, not Native runtime acceptance.
test('current Store scalar successor preserves the exact delivery selector and prior preimages', () => {
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
  assert.deepEqual(currentPackageConfigurations[path], {revision: currentRevision, digest: currentDigest,
    rule: 'literal-native-options-with-bound-source-membership'});
  execFileSync('git', ['merge-base', '--is-ancestor', revision, 'HEAD'], {cwd: root});
  execFileSync('git', ['merge-base', '--is-ancestor', currentRevision, 'HEAD'], {cwd: root});
  assert.equal(currentTree.read(path).toString(), currentBody);
  assert.equal(currentPackageConfigurationReviewFor(request(path, digest)), null);
  assert.deepEqual(currentPackageConfigurationReviewFor(request(path, currentDigest)), {
    revision: currentRevision, target: 'js', toolchainDigest, moonRevision: packageConfigurationReview.moonRevision,
    rule: 'literal-native-options-with-bound-source-membership',
  });
  const selected = packageSourceInputs({tree: currentTree, packages: [directory], target: 'js'});
  assert.equal(selected.packageConfigurations.find(entry => entry.path === path)?.review.revision, currentRevision);
  assert(!selected.unresolved.includes('Unreviewed package configuration: ' + path));
  const members = [...currentTree.entries.keys()].filter(member => member.startsWith(directory + '/') &&
    !member.slice(directory.length + 1).includes('/')).sort();
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
  for (const changed of [prior, body,
    currentBody.replace(selector, selector.replace('"native"', '"js"')),
    currentBody.replace(selector, selector + '    "unreviewed_chunk_native_wbtest.mbt": [ "native" ],\n'),
    currentBody.replace(scalarImport, scalarImport.replace('@scalar', '@permission')),
    currentBody.replace(scalarImport, scalarImport.replace('decode_scalar', 'unreviewed_scalar')),
    currentBody.replace('"actql/actql/sha256"', '"actql/actql/string"'),
    currentBody + '\noptions(pre_build: {command: "unreviewed"})\n']) {
    assert.notEqual(changed, currentBody);
    assert.equal(currentPackageConfigurationReviewFor(request(path, hash(changed))), null);
    const altered = {...currentTree, read: member => member === path ? Buffer.from(changed) : currentTree.read(member)};
    assert(packageSourceInputs({tree: altered, packages: [directory], target: 'js'})
      .unresolved.includes('Unreviewed package configuration: ' + path));
  }
  for (const delta of [{target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)},
    {path: './' + path}, {path: 'src/unreviewed/moon.pkg'}, {digest: priorDigest}])
    assert.equal(currentPackageConfigurationReviewFor({...request(path, currentDigest), ...delta}), null);
  assert.equal(packageConfigurationReviewFor(request(path, reviewedPackageConfigurations[path]))?.revision,
    packageConfigurationReview.revision, 'The historical configuration keeps its own unchanged review');
});
