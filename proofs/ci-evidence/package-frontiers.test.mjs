import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readCatalog} from './actions.mjs';
import {actionInputs, gitTree, mutationSourceInputs, packageSourceInputs} from './inputs.mjs';
import {loadReference} from '../../scripts/profile-session-input-frontiers.mjs';

function fixture(files) {
  const entries = new Map(Object.keys(files).map(path => [path, {kind: 'blob', mode: '100644'}]));
  const prefetched = new Set(), batches = [], reads = [];
  return {entries, batches, reads, prefetch(paths) {
    for (const path of paths) { assert(entries.has(path)); prefetched.add(path); }
    batches.push([...paths]);
  }, read(path) {
    assert(Object.hasOwn(files, path), path);
    if (path.endsWith('/moon.pkg')) assert(prefetched.has(path), `Unbatched manifest read: ${path}`);
    reads.push(path); return Buffer.from(files[path]);
  }};
}

test('reachable diamond/cycle manifests are batched while independent membership and external inputs remain exact', () => {
  const tree = fixture({
    'toolchain.json': '{}',
    'src/a/moon.pkg': 'import { "actql/actql/b", "actql/actql/c" }',
    'src/a/value.mbt': 'a',
    'src/b/moon.pkg': 'import { "actql/actql/d" } for "test"',
    'src/c/moon.pkg': 'import { "actql/actql/d", "actql/actql/a", "moonbitlang/core/json" } for "wbtest"',
    'src/d/moon.pkg': '',
    'src/d/value.mbt': 'd',
    'src/unrelated/moon.pkg': 'dynamic_dependency()',
  });
  const observed = packageSourceInputs({tree, packages: ['src/a', 'src/a'], target: 'js'});
  assert.deepEqual(observed.paths, ['src/a/moon.pkg', 'src/a/value.mbt', 'src/b/moon.pkg',
    'src/c/moon.pkg', 'src/d/moon.pkg', 'src/d/value.mbt']);
  assert.deepEqual(observed.directories, [
    {path: 'src/a/*', members: ['src/a/moon.pkg', 'src/a/value.mbt']},
    {path: 'src/b/*', members: ['src/b/moon.pkg']},
    {path: 'src/c/*', members: ['src/c/moon.pkg']},
    {path: 'src/d/*', members: ['src/d/moon.pkg', 'src/d/value.mbt']},
  ]);
  assert.deepEqual(observed.externalPackages, ['moonbitlang/core/json']);
  assert.deepEqual(observed.unresolved, []);
  assert.deepEqual(tree.batches, [['src/a/moon.pkg'], ['src/b/moon.pkg', 'src/c/moon.pkg'], ['src/d/moon.pkg']]);
  assert(!tree.reads.includes('src/unrelated/moon.pkg'));
});

test('missing/dynamic/nested inputs stay unresolved and each new call observes member/import changes', () => {
  const files = {'toolchain.json': '{}', 'src/bounded_execution/moon.pkg': '',
    'src/connectors/local/moon.pkg': '',
    'src/query_integration/moon.pkg': 'import { "actql/actql/missing", "actql/actql/open" }',
    'src/open/moon.pkg': 'options(pre_build: dynamic())',
    'src/open/nested/data.json': '{}', 'src/unrelated/value.mbt': 'broad fallback'};
  const tree = fixture(files);
  const first = mutationSourceInputs(tree);
  assert(first.unresolved.includes('missing source input: src/missing/moon.pkg'));
  assert(first.unresolved.includes('Unreviewed package configuration: src/open/moon.pkg'));
  assert(first.unresolved.includes('nested package input requires review: src/open/nested/data.json'));
  assert(first.paths.includes('src/unrelated/value.mbt'));
  assert(first.directories.some(entry => entry.path === 'src/**'));
  files['src/query_integration/moon.pkg'] = '';
  delete files['src/open/nested/data.json'];
  files['src/query_integration/new.mbt'] = 'new member';
  tree.entries.delete('src/open/nested/data.json');
  tree.entries.set('src/query_integration/new.mbt', {kind: 'blob', mode: '100644'});
  const second = mutationSourceInputs(tree);
  assert.deepEqual(second.unresolved, []);
  assert(second.paths.includes('src/query_integration/new.mbt'));
  assert(!second.paths.includes('src/open/moon.pkg'));
  assert(!second.paths.includes('src/unrelated/value.mbt'));
});

test('indexed directory boundaries retain deep unmodelled inputs and refuse unsupported member modes', () => {
  const tree = fixture({'toolchain.json': '{}', 'src/a/moon.pkg': '', 'src/a/value.mbt': 'value',
    'src/a/link.mbt': 'not a regular input', 'src/a/assets/deep/input.json': '{}',
    'src/a/assets/../outside.json': 'invalid path',
    'src/a/module/moon.pkg': '', 'src/a/module/value.mbt': 'not imported',
    'src/ab/moon.pkg': '', 'src/ab/value.mbt': 'different directory prefix'});
  tree.entries.get('src/a/link.mbt').mode = '120000';
  const observed = packageSourceInputs({tree, packages: ['src/a'], target: 'js'});
  assert.deepEqual(observed.paths, ['src/a/assets/../outside.json', 'src/a/assets/deep/input.json',
    'src/a/link.mbt', 'src/a/moon.pkg', 'src/a/value.mbt']);
  assert.deepEqual(observed.directories, [{path: 'src/a/*',
    members: ['src/a/link.mbt', 'src/a/moon.pkg', 'src/a/value.mbt']}]);
  assert.deepEqual(observed.unresolved, [
    'nested package input requires review: src/a/assets/../outside.json',
    'nested package input requires review: src/a/assets/deep/input.json',
    'unmodelled source path: src/a/assets/../outside.json',
    'unsupported source kind/mode: src/a/link.mbt',
  ]);
  assert(!tree.reads.includes('src/a/module/moon.pkg'));
  assert(!tree.reads.includes('src/ab/moon.pkg'));
});

test('every registered actual Git action input matches the previous traversal on the same candidate bytes', async () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const before = await loadReference(root);
  const oldTree = gitTree(root, revision), newTree = gitTree(root, revision);
  const runtime = {profile: 'input-extractor-equivalence-only', unresolved: ['not runtime acceptance']};
  const catalog = readCatalog();
  assert(catalog.actions.length > 0);
  for (const action of catalog.actions) assert.deepEqual(
    actionInputs({tree: newTree, revision, action, runtime}),
    before.actionInputs({tree: oldTree, revision, action, runtime}), action.id);
});
