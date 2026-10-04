import test from 'node:test';
import assert from 'node:assert/strict';
import {readCatalog, compareCatalogs} from './actions.mjs';
import {actionInputs, compareInputs, packageImports, sharedFiles} from './inputs.mjs';

const catalog = readCatalog();
const runtime = {profile: 'controlled-test-runtime', components: {node: '1'.repeat(64)}, unresolved: []};
const base = new Map([
  ...sharedFiles.map(path => [path, path]),
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

test('literal normal, test and whitebox imports are tracked; arbitrary expressions are not guessed', () => {
  assert.deepEqual(packageImports('import { "actql/actql/a" @a } import { "moonbitlang/core/json" } for "wbtest"').imports,
    ['actql/actql/a', 'moonbitlang/core/json']);
  assert.throws(() => packageImports('import { dynamic_dependency() }'), /unknown package import/u);
});
