// Moon owns package/import semantics; CI adds the non-Moon input boundaries.
// Whole-module checks and selected proof/product families remain unchanged.
// Native consumes the same closure inside its original physical profiles.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {snapshotDirectories, snapshotFiles} from '../proofs/relation-pipeline/inventory.mjs';

const sha = /^[a-f0-9]{40}$/u;
const digest = /^[a-f0-9]{64}$/u;
const pathPattern = /^(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+$/u;
const safePath = path => typeof path === 'string' && pathPattern.test(path) &&
  !path.split('/').some(part => part === '.' || part === '..');
const sorted = values => [...new Set(values)].sort();
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

// These relations cannot be inferred from Moon imports. Unknown inputs also
// stay full; the table explains the retained owner rather than granting an
// exception for an entire directory or a filename extension.
export const nonMoonInputOwners = Object.freeze([
  {name:'FFI/platform', pattern:/\.(?:c|h|cc|cpp|a|so|dylib|wasm)$/u,
    jobs:['core', 'native', 'native-macos']},
  {name:'generator/build', pattern:/^scripts\/(?:generate-|build-|produce-|compile-|setup-|.*(?:package-inputs|bundle|toolchain))|(?:^|\/)(?:moon\.pkg|moon\.mod|toolchain\.json|package(?:-lock)?\.json)$/u,
    jobs:['preflight', 'spec', 'host', 'client']},
  {name:'JS bridge/distribution', pattern:/^(?:adapters|packages)\/|^src\/(?:[^/]*_abi|[^/]*_bridge|connectors_builtin_node)(?:\/|$)|\/host_node\//u,
    jobs:['host', 'client', 'workers', 'python-wheels']},
]);

export function nonMoonRequirements(paths) {
  const owners = nonMoonInputOwners.filter(owner => paths.some(path => owner.pattern.test(path)))
    .map(({name, jobs}) => ({name, jobs:[...jobs]}));
  if (paths.some(path => snapshotFiles.includes(path) || snapshotDirectories.some(root =>
    path === root || path.startsWith(root + '/')))) owners.push({name:'proof snapshot',
    jobs:['session-evidence', 'session-controls', 'pipeline-evidence']});
  return owners;
}

export function moonGraphCandidate(paths) {
  return Array.isArray(paths) && paths.length > 0 && paths.every(path =>
    safePath(path) &&
    /^src\/.+\.mbt$/u.test(path) && !/^src\/(?:cmd|platform_native)\//u.test(path) &&
    !nonMoonInputOwners.some(owner => owner.pattern.test(path)));
}

function trackedTree(git) {
  const raw = git(['ls-tree', '-rz', 'HEAD', '--', 'src']);
  assert(raw.endsWith('\0'), 'Missing or truncated Moon source inventory');
  return raw.slice(0, -1).split('\0').map(line => {
    const match = /^(\d{6}) blob ([a-f0-9]{40})\t(.+)$/u.exec(line);
    assert(match, 'Unsupported source inventory entry');
    return {mode:match[1], object:match[2], path:match[3]};
  });
}

export function normalizeMoonGraph(graph, tree, repository) {
  assert.equal(graph?.version, 2, 'Unknown pinned Moon package graph schema');
  assert.equal(graph.status, 'success'); assert.equal(graph.error, null);
  assert(Array.isArray(graph.logs) && graph.logs.length === 0, 'Moon graph has diagnostics');
  assert(Array.isArray(graph.nodes) && Array.isArray(graph.edges) && Array.isArray(graph.root));
  const roots = new Set(graph.root);
  assert.equal(roots.size, graph.root.length, 'Duplicate root package');
  const nodes = graph.nodes.map((node, index) => {
    assert(typeof node.module === 'string' && node.module.length > 0);
    assert(node.rel === '' || safePath(node.rel));
    if (roots.has(index)) {
      assert.equal(node.module, 'actql/actql');
      assert.equal(node.source?.kind, 'local');
      assert.equal(resolve(node.source.path), resolve(repository), 'Foreign root package');
    }
    return `${node.module}${node.rel ? '/' + node.rel : ''}`;
  });
  assert.equal(new Set(nodes).size, nodes.length, 'Ambiguous package identity');
  assert([...roots].every(id => Number.isSafeInteger(id) && id >= 0 && id < nodes.length));
  const packages = [...roots].map(id => ({id, name:nodes[id],
    path:'src' + (graph.nodes[id].rel ? '/' + graph.nodes[id].rel : '')}));
  const manifests = tree.filter(entry => entry.path.endsWith('/moon.pkg'));
  assert(manifests.every(entry => entry.mode === '100644'), 'Aliased package manifest');
  assert.deepEqual(sorted(packages.map(pkg => pkg.path + '/moon.pkg')),
    sorted(manifests.map(entry => entry.path)), 'Incomplete compiler package inventory');
  const edges = graph.edges.map(edge => {
    assert(Number.isSafeInteger(edge.from) && nodes[edge.from] && Number.isSafeInteger(edge.to) && nodes[edge.to]);
    assert(typeof edge.alias === 'string' && edge.alias.length > 0);
    assert(Array.isArray(edge.kinds) && edge.kinds.length > 0 && edge.kinds.every(kind =>
      ['source', 'whitebox-test', 'blackbox-test'].includes(kind)), 'Unknown import target kind');
    return {from:nodes[edge.from], to:nodes[edge.to], alias:edge.alias, kinds:sorted(edge.kinds)};
  }).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const normalized = {packages:packages.map(({name, path}) => ({name, path})).sort((a, b) => a.path.localeCompare(b.path)),
    edges, manifests:manifests.map(({path, object}) => ({path, object})).sort((a, b) => a.path.localeCompare(b.path))};
  return {...normalized, digest:hash(normalized)};
}

export function planMoonTests(paths, graph, tree) {
  assert(moonGraphCandidate(paths), 'Unreviewed Moon selection input');
  const byPath = new Map(graph.packages.map(pkg => [pkg.path, pkg.name]));
  const originals = new Map(tree.map(entry => [entry.path, entry]));
  const changed = paths.map(path => {
    assert.equal(originals.get(path)?.mode, '100644', 'Missing/aliased changed source');
    const parent = path.slice(0, path.lastIndexOf('/'));
    assert(byPath.has(parent), 'Changed file has no original compiler package');
    return byPath.get(parent);
  });
  const selected = new Set(changed);
  // Include source, blackbox and whitebox imports, including cycles and every
  // transitively affected importer. Test dependencies must not disappear.
  let changedSet = true;
  while (changedSet) {
    changedSet = false;
    for (const edge of graph.edges) if (selected.has(edge.to) && !selected.has(edge.from)) {
      selected.add(edge.from); changedSet = true;
    }
  }
  const packages = graph.packages.filter(pkg => selected.has(pkg.name)).map(pkg => pkg.path).sort();
  const packageSet = new Set(packages);
  const files = tree.filter(entry => entry.path.endsWith('.mbt') &&
    packageSet.has(entry.path.slice(0, entry.path.lastIndexOf('/'))));
  assert(files.length > 0 && files.every(entry => entry.mode === '100644'), 'Missing/aliased selected source');
  const names = files.map(entry => entry.path).sort();
  assert(names.join('\0').length <= 128 * 1024, 'Selected argv exceeds its finite bound');
  return {schema:'actql-ci-moon-tests/0.1', graphSha256:graph.digest,
    changedPackages:sorted(changed), packages, files:names,
    portableTargets:['js', 'wasm'], native:'compiler-owned-existing-profiles',
    supplemental:nonMoonRequirements(paths)};
}

export function validateMoonTestPlan(plan) {
  assert.deepEqual(Object.keys(plan ?? {}).sort(), ['schema', 'graphSha256', 'changedPackages', 'packages',
    'files', 'portableTargets', 'native', 'supplemental'].sort());
  assert.equal(plan.schema, 'actql-ci-moon-tests/0.1'); assert(digest.test(plan.graphSha256));
  for (const key of ['changedPackages', 'packages', 'files']) {
    assert(Array.isArray(plan[key]) && plan[key].length > 0 && plan[key].every(value =>
      safePath(value)));
    assert.deepEqual(plan[key], sorted(plan[key]));
  }
  assert(plan.packages.every(path => path === 'src' || path.startsWith('src/')));
  assert(plan.changedPackages.every(name => name === 'actql/actql' || name.startsWith('actql/actql/')));
  assert(plan.changedPackages.every(name => plan.packages.includes('src' + name.slice('actql/actql'.length))));
  assert(plan.files.every(path => path.endsWith('.mbt') && plan.packages.includes(path.slice(0, path.lastIndexOf('/')))));
  assert(plan.files.join('\0').length <= 128 * 1024);
  assert.deepEqual(plan.portableTargets, ['js', 'wasm']);
  assert.equal(plan.native, 'compiler-owned-existing-profiles');
  assert.deepEqual(plan.supplemental, [{name:'proof snapshot', jobs:['session-evidence', 'session-controls', 'pipeline-evidence']}]);
  return plan;
}

export function readMoonTestPlan(paths, base, {repository = process.cwd(), git,
  execute = execFileSync} = {}) {
  assert(moonGraphCandidate(paths), 'Unreviewed Moon selection input');
  assert(sha.test(base), 'Missing original diff base');
  git ??= args => execute('git', args, {cwd:repository, encoding:'utf8', timeout:15000, maxBuffer:32 * 1024 ** 2});
  const head = git(['rev-parse', 'HEAD']).trim(); assert(sha.test(head));
  const names = git(['diff', '--no-renames', '--name-only', '-z', base, head, '--']);
  assert(names.endsWith('\0'), 'Truncated complete diff');
  assert.deepEqual(names.slice(0, -1).split('\0'), paths, 'Moon scope omits changed inputs');
  const raw = git(['diff', '--no-renames', '--raw', '--no-abbrev', '-z', base, head, '--', ...paths]);
  assert(raw.endsWith('\0'), 'Truncated original Moon diff');
  const records = raw.slice(0, -1).split('\0');
  assert.equal(records.length, paths.length * 2, 'Incomplete changed Moon inventory');
  for (let i = 0; i < records.length; i += 2) {
    assert(/^:100644 100644 [a-f0-9]{40} [a-f0-9]{40} M$/u.test(records[i]), 'Structural Moon change requires full coverage');
    assert.equal(records[i + 1], paths[i / 2]);
  }
  assert.equal(git(['diff', 'HEAD', '--', 'src', 'vendor', 'moon.mod']), '', 'Dirty compiler inputs');
  assert.equal(git(['ls-files', '--others', '--exclude-standard', '--', 'src', 'vendor']), '', 'Untracked compiler inputs');
  const tree = trackedTree(git);
  const graph = JSON.parse(execute('moon', ['tree', '--package', '--json'],
    {cwd:repository, encoding:'utf8', timeout:60000, maxBuffer:16 * 1024 ** 2}));
  const plan = planMoonTests(paths, normalizeMoonGraph(graph, tree, repository), tree);
  assert.equal(git(['rev-parse', 'HEAD']).trim(), head, 'Source changed during graph discovery');
  assert.equal(git(['diff', 'HEAD', '--', 'src', 'vendor', 'moon.mod']), '', 'Compiler inputs changed during discovery');
  assert.equal(git(['ls-files', '--others', '--exclude-standard', '--', 'src', 'vendor']), '', 'New compiler inputs during discovery');
  return validateMoonTestPlan(plan);
}
