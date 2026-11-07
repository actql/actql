import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readCatalog, compareCatalogs} from './actions.mjs';
import {actionInputs, compareInputs, packageImports, sharedFiles, mutationSnapshotExtras, mutationPackages, mutationSourceInputs, pipelineInventoryBoundary, hash} from './inputs.mjs';
import {mutationContracts} from './mutation-inventory.mjs';
import {reviewedPackageConfiguration, reviewedPackageConfigurations, packageConfigurationReview,
  packageConfigurationReviewFor, foreignLibraryConfigurationReview, currentPackageConfigurationReviewFor} from './package-configurations.mjs';

const catalog = readCatalog();
const runtime = {profile: 'controlled-test-runtime', components: {node: '1'.repeat(64)}, unresolved: []};
const base = new Map([
  ...sharedFiles.map(path => [path, path]),
  ...[pipelineInventoryBoundary, ...pipelineInventoryBoundary.dependencies]
    .map(({path}) => [path, readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8')]),
  ['proofs/ci-evidence/actions.mjs', 'actions'], ['proofs/ci-evidence/inputs.mjs', 'inputs'],
  ['proofs/bounded-session/action-inputs.mjs', 'encoder'], ['toolchain.json', '{}'], ['moon.mod', 'module'],
  ['scripts/setup-moonbit.mjs', 'setup'], ['.github/actions/setup-toolchain/action.yml', 'setup'],
  ['src/bounded_execution/moon.pkg', 'supported_targets = "+js+wasm+native"'],
  ['src/bounded_execution/session.mbt', 'Session source'],
  ['src/bounded_execution/session_contract_wbtest.mbt', 'independent Session oracle'],
  ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'].map(name => [`proofs/bounded-session/${name}`, name]),
]);
function tree(files = base, modes = {}) {
  return {entries: new Map([...files].map(([path]) => [path, {path, mode: modes[path] ?? '100644', kind: 'blob'}])),
    read: path => Buffer.from(files.get(path))};
}
const action = catalog.actions.find(value => value.id === 'session-js');
const inventory = (files = base, revision = 'a'.repeat(40), selected = action, modes = {}) =>
  actionInputs({tree: tree(files, modes), revision, action: selected, runtime});

test('unrelated source and provenance changes preserve a closed Session input identity', () => {
  const files = new Map(base); files.set('src/unrelated/new.mbt', 'new operation');
  const old = inventory(), candidate = inventory(files, 'b'.repeat(40));
  assert.equal(compareInputs(old, candidate).eligible, true);
  assert.equal(old.key, candidate.key);
});

test('separate pipeline consumers and membership do not invalidate Session inputs', () => {
  const files = new Map(base); files.set('proofs/relation-pipeline/execution-original.mjs', 'reviewed shared consumer');
  const original = inventory(files);
  files.set('proofs/relation-pipeline/execution-original.mjs', 'changed consumer');
  assert.equal(compareInputs(original, inventory(files)).eligible, true);
  files.set('proofs/relation-pipeline/execution-original.mjs', 'reviewed shared consumer');
  files.set('proofs/relation-pipeline/new-import.mjs', 'new module');
  assert.equal(compareInputs(original, inventory(files)).eligible, true);
  files.delete('proofs/relation-pipeline/execution-original.mjs');
  assert.equal(compareInputs(original, inventory(files)).eligible, true);
});

test('remaining evaluated pipeline inventory bytes and new imports stay bound and open until reviewed', () => {
  const original = inventory();
  for (const change of [
    files => files.set(pipelineInventoryBoundary.path, files.get(pipelineInventoryBoundary.path) + '\nimport "./new-reader.mjs";\n'),
    files => files.set(pipelineInventoryBoundary.path, files.get(pipelineInventoryBoundary.path) + '\nreadFileSync("external-input");\n'),
    files => files.delete(pipelineInventoryBoundary.path),
  ]) {
    const files = new Map(base); change(files);
    const observed = inventory(files);
    assert(observed.unresolved.includes('unreviewed pipeline inventory import/effect boundary'));
    assert.equal(compareInputs(original, observed).eligible, false);
  }
  assert.equal(compareInputs(original, inventory(base, 'b'.repeat(40), action,
    {[pipelineInventoryBoundary.path]: '100755'})).eligible, false);
});

test('the reviewed transitive helper is bound; new imports, effects, missing bytes and modes remain open', () => {
  const path = 'proofs/relation-pipeline/proof-runner-extension.mjs';
  const original = inventory();
  assert.deepEqual(original.unresolved, []);
  assert(original.inputs.files.some(entry => entry.path === path));
  for (const change of [
    files => files.set(path, files.get(path) + '\nimport "./unreviewed-extension.mjs";\n'),
    files => files.set(path, files.get(path) + '\nspawnSync("unreviewed-process");\n'),
    files => files.delete(path),
  ]) {
    const files = new Map(base); change(files);
    const observed = inventory(files);
    assert(observed.unresolved.includes('unreviewed pipeline inventory import/effect boundary'));
    assert.equal(compareInputs(original, observed).eligible, false);
  }
  const changedMode = inventory(base, 'b'.repeat(40), action, {[path]: '100755'});
  assert(changedMode.unresolved.includes('unreviewed pipeline inventory import/effect boundary'));
  assert.equal(compareInputs(original, changedMode).eligible, false);
});

for (const [label, mutate] of [
  ['source bytes', files => files.set('src/bounded_execution/session.mbt', 'changed body')],
  ['oracle bytes', files => files.set('src/bounded_execution/session_contract_wbtest.mbt', 'changed expectation')],
  ['added package member', files => files.set('src/bounded_execution/new.mbt', 'new kernel')],
  ['deleted package member', files => files.delete('src/bounded_execution/session_contract_wbtest.mbt')],
  ['renamed package member', files => {files.set('src/bounded_execution/renamed.mbt', files.get('src/bounded_execution/session.mbt')); files.delete('src/bounded_execution/session.mbt');}],
]) test(`${label} invalidates the Session leaf`, () => {
  const files = new Map(base); mutate(files);
  assert.equal(compareInputs(inventory(), inventory(files)).eligible, false);
});

test('same import graph does not hide changed transitive dependency bytes', () => {
  const files = new Map(base);
  files.set('src/bounded_execution/moon.pkg', 'import { "actql/actql/child" @child, }');
  files.set('src/child/moon.pkg', ''); files.set('src/child/value.mbt', 'one');
  const original = inventory(files);
  files.set('src/child/value.mbt', 'two');
  assert.equal(compareInputs(original, inventory(files)).eligible, false);
});

test('unknown import/configuration affects the package leaf, without invalidating the separate model', () => {
  const files = new Map(base); files.set('src/bounded_execution/moon.pkg', 'options(pre_build: { "command": "external" })');
  assert(inventory(files).unresolved.length > 0);
  const model = catalog.actions.find(value => value.id === 'model');
  assert.equal(compareInputs(inventory(base, 'a'.repeat(40), model), inventory(files, 'b'.repeat(40), model)).eligible, true);
});

test('mode, runtime, target and minimum-obligation changes invalidate identity', () => {
  assert.equal(compareInputs(inventory(), inventory(base, 'a'.repeat(40), action, {'src/bounded_execution/session.mbt': '100755'})).eligible, false);
  for (const selected of [{...action, target: 'native'}, {...action, minimumUnits: 2}])
    assert.equal(compareInputs(inventory(), inventory(base, 'a'.repeat(40), selected)).eligible, false);
  const changed = actionInputs({tree: tree(), revision: 'a'.repeat(40), action, runtime: {...runtime, components: {node: '2'.repeat(64)}}});
  assert.equal(compareInputs(inventory(), changed).eligible, false);
});

test('a new registration retains existing required obligations; deleting one is rejected', () => {
  const changed = structuredClone(catalog);
  changed.actions.push({...action, id: 'additional-session-js'});
  assert.deepEqual(compareCatalogs(catalog, changed).changed, ['additional-session-js']);
  const removed = structuredClone(catalog); removed.actions = removed.actions.filter(value => value.id !== 'nest-kernel-js');
  assert.throws(() => compareCatalogs(catalog, removed), /Removed required action/u);
});

test('Bridge model and connection bind their proof closure, additions, modes and missing prerequisites', () => {
  const files = new Map(base);
  const proofFiles = ['Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean', 'lean-toolchain', 'check.mjs'];
  for (const file of proofFiles) files.set(`proofs/events-bridge/${file}`, file);
  files.set('src/query_integration/moon.pkg', 'import { "actql/actql/bounded_execution" } for "wbtest"');
  files.set('src/query_integration/events_bridge_evidence_wbtest.mbt', 'independent ordered nullable expectations');
  for (const id of ['events-model', 'events-connection-js']) {
    const selected = catalog.actions.find(value => value.id === id);
    const original = inventory(files, 'a'.repeat(40), selected);
    assert.deepEqual(original.unresolved, []);
    assert(proofFiles.every(file => original.inputs.files.some(entry => entry.path === `proofs/events-bridge/${file}`)));
    for (const [path, value] of [['proofs/events-bridge/Claims.lean', 'weakened type'],
      ['proofs/events-bridge/new.lean', 'new dependency']]) {
      const changed = new Map(files); changed.set(path, value);
      assert.equal(compareInputs(original, inventory(changed, 'b'.repeat(40), selected)).eligible, false);
    }
    const changed = new Map(files); changed.delete('proofs/events-bridge/Claims.lean');
    assert(inventory(changed, 'b'.repeat(40), selected).unresolved.includes('missing source input: proofs/events-bridge/Claims.lean'));
    assert.equal(compareInputs(original, inventory(files, 'b'.repeat(40), selected,
      {'proofs/events-bridge/Claims.lean': '100755'})).eligible, false);
  }
});

test('literal normal, test and whitebox imports are tracked; arbitrary expressions are not guessed', () => {
  assert.deepEqual(packageImports('import { "actql/actql/a" @a } import { "moonbitlang/core/json" } for "wbtest"').imports,
    ['actql/actql/a', 'moonbitlang/core/json']);
  assert.throws(() => packageImports('import { dynamic_dependency() }'), /unknown package import/u);
});

test('reviewed native-only configuration requires its independent path/bytes/toolchain and JS target', () => {
  const [path, digest] = Object.entries(reviewedPackageConfigurations)[0];
  const request = {path, digest, target: 'js', toolchainDigest: packageConfigurationReview.toolchainDigest};
  assert(reviewedPackageConfiguration(request));
  for (const changed of [
    {...request, path: 'src/unreviewed/moon.pkg'},
    {...request, digest: 'f'.repeat(64)},
    {...request, target: 'native'},
    {...request, target: 'wasm'},
    {...request, toolchainDigest: 'f'.repeat(64)},
  ]) assert.equal(reviewedPackageConfiguration(changed), false);
  // Even at a reviewed path, source is read independently; a copied descriptor
  // or a changed pre-build option does not inherit the reviewed digest.
  const files = new Map(base);
  files.set(path, 'options(pre_build: { "command": "unreviewed" })');
  const selected = {...action, package: path.slice(0, -'/moon.pkg'.length)};
  const observed = inventory(files, 'a'.repeat(40), selected);
  assert(observed.unresolved.some(reason => reason.endsWith(path)));
  assert.deepEqual(observed.inputs.packageConfigurations, []);
  assert(observed.inputs.files.some(file => file.path === path));
});

test('the exact JS foreign library binds imports and source bytes under its separate review', () => {
  const path = 'src/connectors_builtin_node/moon.pkg';
  const source = readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
  const files = new Map(base);
  files.set('toolchain.json', readFileSync(new URL('../../toolchain.json', import.meta.url), 'utf8'));
  files.set(path, source);
  files.set('src/connectors_builtin_node/bridge.mbt', 'original foreign source');
  for (const dependency of packageImports(source).imports) if (dependency.startsWith('actql/actql/')) {
    const directory = `src/${dependency.slice('actql/actql/'.length)}`;
    files.set(`${directory}/moon.pkg`, 'supported_targets = "js"');
    files.set(`${directory}/source.mbt`, 'original literal dependency');
  }
  const selected = {...action, package: 'src/connectors_builtin_node'};
  const original = inventory(files, 'a'.repeat(40), selected);
  assert.deepEqual(original.unresolved, []);
  assert.equal(original.inputs.packageConfigurations.find(entry => entry.path === path)?.review.rule,
    'literal-js-foreign-library-with-bound-source-membership');
  assert.equal(packageImports(source).unknown, 'Unreviewed package configuration',
    'The generic parser must not accept arbitrary package kinds');
  for (const dependency of packageImports(source).imports) if (dependency.startsWith('actql/actql/'))
    assert(original.inputs.files.some(entry => entry.path === `src/${dependency.slice('actql/actql/'.length)}/source.mbt`));
  const changed = new Map(files);
  changed.set('src/connectors_builtin_node/bridge.mbt', 'changed foreign source');
  assert.equal(compareInputs(original, inventory(changed, 'b'.repeat(40), selected)).eligible, false);
  changed.set(path, source + '\noptions(pre_build: { "command": "unreviewed" })\n');
  const unreviewed = inventory(changed, 'b'.repeat(40), selected);
  assert(unreviewed.unresolved.includes(`Unreviewed package configuration: ${path}`));
  assert.deepEqual(unreviewed.inputs.packageConfigurations, []);
  const request = {path, digest: hash(source), target: 'js', toolchainDigest: packageConfigurationReview.toolchainDigest};
  assert.deepEqual(packageConfigurationReviewFor(request), currentPackageConfigurationReviewFor(request));
  assert.equal(packageConfigurationReviewFor(request).rule, foreignLibraryConfigurationReview.rule);
  for (const wrong of [{...request, target: 'native'}, {...request, target: 'wasm'},
    {...request, toolchainDigest: 'f'.repeat(64)}, {...request, path: 'src/other/moon.pkg'},
    {...request, digest: 'f'.repeat(64)}]) assert.equal(packageConfigurationReviewFor(wrong), null);
});

test('literal formatter exclusions remain bound; dynamic configuration stays open', () => {
  assert.equal(packageImports('formatter(ignore: [ "fixture.generated_wbtest.mbt", ])').unknown, null);
  assert.throws(() => packageImports('formatter(ignore: [ discover_files() ])'), /formatter ignore/u);
  assert(packageImports('formatter(ignore: [ "fixture.mbt" ], build: "external")').unknown);
  const changed = new Map(base);
  changed.set('src/bounded_execution/moon.pkg', 'formatter(ignore: [ "session_contract_wbtest.mbt" ])');
  assert.equal(inventory(changed).unresolved.length, 0);
  assert.equal(compareInputs(inventory(), inventory(changed)).eligible, false);
});

test('mutation input identity follows the physically staged package cohort and retains audit inputs', () => {
  const selected = catalog.actions.find(value => value.id === 'mutations-js'), files = new Map(base);
  for (const path of mutationSnapshotExtras) if (!files.has(path)) files.set(path, 'independent audit');
  files.set('proofs/bounded-session/mutations.mjs', 'original mutation executor');
  files.set('proofs/bounded-session/evidence.mjs', 'original snapshot');
  files.set('src/connectors/local/moon.pkg', ''); files.set('src/query_integration/moon.pkg', '');
  const original = inventory(files, 'a'.repeat(40), selected);
  assert.equal(original.unresolved.length, 0);
  const unrelated = new Map(files); unrelated.set('src/unrelated/new.mbt', 'absent from isolated image');
  assert.equal(compareInputs(original, inventory(unrelated, 'b'.repeat(40), selected)).eligible, true);
  for (const change of [
    map => map.set('src/connectors/local/new.mbt', 'physically staged package member'),
    map => map.set(mutationSnapshotExtras[2], 'changed audit'),
    map => map.delete(mutationSnapshotExtras[3]),
    map => map.delete('proofs/bounded-session/mutations.mjs'),
  ]) {
    const changed = new Map(files); change(changed);
    assert.equal(compareInputs(original, inventory(changed, 'b'.repeat(40), selected)).eligible, false);
  }
});

test('the ordinary mutation CJS dependency is keyed by exact bytes, presence and mode', () => {
  const selected = catalog.actions.find(value => value.id === 'mutations-js');
  const files = new Map(base);
  for (const path of mutationSnapshotExtras) if (!files.has(path)) files.set(path,'independent input');
  files.set('proofs/bounded-session/mutations.mjs','original mutation executor');
  files.set('src/connectors/local/moon.pkg','');
  files.set('src/query_integration/moon.pkg','');
  const path = 'adapters/host-node/ordinary-node-resource-runtime.cjs';
  const original = inventory(files,'a'.repeat(40),selected);
  assert.equal(original.unresolved.length,0);
  assert(original.inputs.files.some(entry => entry.path === path && entry.digest === hash(files.get(path))));
  for (const change of [copy => copy.set(path,'changed original CJS'),copy => copy.delete(path)]) {
    const changed = new Map(files);change(changed);
    assert.equal(compareInputs(original,inventory(changed,'b'.repeat(40),selected)).eligible,false);
  }
  assert.equal(compareInputs(original,inventory(files,'b'.repeat(40),selected,{[path]:'100755'})).eligible,false);
});

test('mutation roots match the actual thirteen registered test suites', () => {
  const actual = [...new Set(Object.values(mutationContracts).map(entry => entry.suite.endsWith('.mbt') ?
    entry.suite.slice(0, entry.suite.lastIndexOf('/')) : entry.suite))].sort();
  assert.deepEqual(actual, mutationPackages.slice().sort());
});

test('a changed transitive test import expands the physical cohort and invalidates the mutation key', () => {
  const selected = catalog.actions.find(value => value.id === 'mutations-js'), files = new Map(base);
  for (const path of mutationSnapshotExtras) if (!files.has(path)) files.set(path, 'audit');
  files.set('proofs/bounded-session/mutations.mjs', 'executor');
  files.set('src/connectors/local/moon.pkg', ''); files.set('src/query_integration/moon.pkg', '');
  files.set('src/new_dependency/moon.pkg', ''); files.set('src/new_dependency/value.mbt', 'value');
  const before = inventory(files, 'a'.repeat(40), selected);
  assert(!mutationSourceInputs(tree(files)).paths.includes('src/new_dependency/value.mbt'));
  files.set('src/query_integration/moon.pkg', 'import { "actql/actql/new_dependency" } for "wbtest"');
  assert(mutationSourceInputs(tree(files)).paths.includes('src/new_dependency/value.mbt'));
  assert.equal(compareInputs(before, inventory(files, 'b'.repeat(40), selected)).eligible, false);
  const imported = inventory(files, 'b'.repeat(40), selected);
  files.set('src/new_dependency/value.mbt', 'changed');
  assert.equal(compareInputs(imported, inventory(files, 'c'.repeat(40), selected)).eligible, false);
});

test('unknown mutation dependency configuration preserves broad sources and explicit refusal reasons', () => {
  const files = new Map(base);
  files.set('src/connectors/local/moon.pkg', '');
  files.set('src/query_integration/moon.pkg', 'options(pre_build: dynamic_command())');
  files.set('src/unrelated/value.mbt', 'conservative source');
  const selected = mutationSourceInputs(tree(files));
  assert(selected.paths.includes('src/unrelated/value.mbt'));
  assert(selected.unresolved.length > 0);
  assert(selected.directories.some(entry => entry.path === 'src/**'));
});

test('the evaluated Bridge scope observer is bound even for shared Session consumers', () => {
  const path = 'proofs/events-bridge/observations.mjs';
  assert(sharedFiles.includes(path));
  const original = inventory();
  const changed = new Map(base); changed.set(path, 'changed observer or new dynamic read');
  assert.equal(compareInputs(original, inventory(changed)).eligible, false);
  changed.delete(path);
  assert(inventory(changed).unresolved.includes(`missing source input: ${path}`));
});
