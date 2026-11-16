import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, immutableGitTree, gitInputScope, actionInputs, packageSourceInputs, mutationSourceInputs, sharedFiles} from './inputs.mjs';
import {readCatalog} from './actions.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
const action = readCatalog().actions.find(value => value.id === 'session-js');
const runtime = () => ({profile: 'controlled-input-data', unresolved: [], configuration: {mode: 'original'}});

test('immutable Git data exposes neither mutable entries nor backing buffers', () => {
  const tree = immutableGitTree(root, revision);
  assert.equal(tree.entries.set, undefined);
  assert.equal(tree.entries.delete, undefined);
  assert.equal(tree.entries.clear, undefined);
  const entry = tree.entries.get('moon.mod');
  assert.throws(() => {entry.mode = '100755';}, TypeError);
  const copy = tree.read('moon.mod'), original = Buffer.from(copy);
  copy.fill(0);
  assert(tree.read('moon.mod').equals(original));
  assert.equal(tree.read('moon.mod') === tree.read('moon.mod'), false);
});

test('scoped pure manifests equal ordinary reconstruction and cannot be poisoned by callers', () => {
  const treeAt = gitInputScope(root), tree = treeAt(revision), input = runtime();
  assert.equal(treeAt(revision), tree);
  const ordinary = actionInputs({tree: gitTree(root, revision), revision, action, runtime: input});
  const first = actionInputs({tree, revision, action, runtime: input});
  assert.deepEqual(first, ordinary);
  first.inputs.files[0].digest = 'changed returned DATA';
  first.inputs.runtime.configuration.mode = 'changed returned runtime';
  first.inputs.action.minimumUnits += 1;
  const next = actionInputs({tree, revision, action, runtime: input});
  assert.deepEqual(next, ordinary);
  assert.equal(input.configuration.mode, 'original');
  const packages = mutationSourceInputs(tree);
  packages.paths.length = 0;
  assert(mutationSourceInputs(tree).paths.length > 0);
});

test('runtime, action, mode and provenance changes never inherit another manifest input', () => {
  const tree = immutableGitTree(root, revision), input = runtime();
  const first = actionInputs({tree, revision, action, runtime: input});
  input.configuration.mode = 'new actual runtime';
  const changed = actionInputs({tree, revision, action, runtime: input});
  assert.notEqual(changed.key, first.key);
  const changedAction = actionInputs({tree, revision, action: {...action, minimumUnits: action.minimumUnits + 1}, runtime: input});
  assert.notEqual(changedAction.key, changed.key);
  const provenance = 'f'.repeat(40);
  assert.equal(actionInputs({tree, revision: provenance, action, runtime: input}).revision, provenance);
  const ordinary = gitTree(root, revision);
  ordinary.entries.get('moon.mod').mode = '100755';
  assert.notEqual(actionInputs({tree: ordinary, revision, action, runtime: input}).key, changed.key);
});

test('ordinary and injected mutable trees retain live Buffer and callback semantics', () => {
  const ordinary = gitTree(root, revision), bytes = ordinary.read('toolchain.json');
  const before = actionInputs({tree: ordinary, revision, action, runtime: runtime()});
  bytes[0] = bytes[0] === 32 ? 9 : 32;
  const after = actionInputs({tree: ordinary, revision, action, runtime: runtime()});
  assert.notEqual(after.key, before.key);
  let reads = 0;
  const injected = {...gitTree(root, revision), read(path) { reads++; return ordinary.read(path); }};
  actionInputs({tree: injected, revision, action, runtime: runtime()});
  const firstReads = reads;
  actionInputs({tree: injected, revision, action, runtime: runtime()});
  assert(reads > firstReads);
});


test('nonenumerable input fields preserve original manifests without memoization', () => {
  const tree = immutableGitTree(root, revision);
  for (const id of ['session-js', 'model']) {
    const selected = {...action};
    Object.defineProperty(selected, 'id', {value: id, enumerable: false});
    const input = {tree, revision, action: selected, runtime: runtime()};
    const expected = actionInputs({...input, tree: gitTree(root, revision)});
    const actual = actionInputs(input);
    assert.deepEqual(actual, expected);
    assert.equal(actual.inputs.action.id, id);
    assert.equal(Object.getOwnPropertyDescriptor(actual.inputs.action, 'id').enumerable, false);
  }
  const input = runtime();
  Object.defineProperty(input.configuration, 'mode', {value: 'hidden mode', enumerable: false});
  assert.deepEqual(actionInputs({tree, revision, action, runtime: input}),
    actionInputs({tree: gitTree(root, revision), revision, action, runtime: input}));
});

test('outer accessor and proxy options retain one original observation per field', () => {
  const tree = immutableGitTree(root, revision);
  let reads = 0;
  const options = {tree, revision, runtime: runtime(), get action() {
    reads++; return {...action, minimumUnits: action.minimumUnits + reads};
  }};
  const first = actionInputs(options), second = actionInputs(options);
  assert.equal(reads, 2);
  assert.equal(first.inputs.action.minimumUnits, action.minimumUnits + 1);
  assert.equal(second.inputs.action.minimumUnits, action.minimumUnits + 2);
  assert.notEqual(first.key, second.key);
  let proxyReads = 0;
  const proxied = new Proxy({tree, revision, action, runtime: runtime()}, {get(target, name) {
    proxyReads++; return target[name];
  }});
  actionInputs(proxied);
  assert.equal(proxyReads, 4);
  let packageReads = 0;
  const packages = {tree, target: 'js', get packages() {packageReads++; return ['canonical_json'];}};
  packageSourceInputs(packages);
  assert.equal(packageReads, 1);
});


test('mutable scientific scope remains an actual input to pure manifest memoization', () => {
  const tree = immutableGitTree(root, revision), options = {tree, revision, action, runtime: runtime()};
  const before = actionInputs(options);
  sharedFiles.push('README.md');
  try {
    const after = actionInputs(options);
    assert.notEqual(after.key, before.key);
    assert.deepEqual(after, actionInputs({...options, tree: gitTree(root, revision)}));
  } finally { sharedFiles.pop(); }
  assert.deepEqual(actionInputs(options), before);
});
