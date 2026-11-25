import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {encode} from '../bounded-session/action-inputs.mjs';
import {packageConfigurationReviewFor, reviewedNestedFixture} from './package-configurations.mjs';

export const inputVersion = 'actql-verification-action-inputs/0.1';
export const hash = value => createHash('sha256').update(value).digest('hex');
// The shared Session image utilities evaluate the inventory and its exact
// proof-runner extension. The extension imports Node built-ins only; neither
// module performs top-level I/O. Baseline history reads remain behind explicit
// function calls. The current-only HEAD validator is also lazy. New bytes
// require reviewing this complete import/effect
// boundary before a closed key may be issued; a digest update is not a review.
export const pipelineInventoryBoundary = Object.freeze({
  path: 'proofs/relation-pipeline/inventory.mjs',
  authoredPath: 'proofs/relation-pipeline/inventory.mts',
  authoredDigest: '00d44ae289d9920d2e5d810053f5bbcfb92d60f339608915ce374b4b2e3beb4c',
  preTypedRunnerDigest: '78e51eef02e37de40f4188068a47e3e61c1f5ce399bbc6345e854e53073b3d35',
  digest: 'e5b055d7c80869c1e24a66521a3eb9cbf48f5e0c3433f172fadcc142a152bd3f',
  preTypedExecutorDigest: '3c9f611d8d88c6fa834cda5ca6deb4cbc797e572b17061e470c065afd9f647d5',
  preTypedWorkspaceDigest: '2bc01a914e134411834d5324a54369838c6b359bbec0eafb495233de88f2203c',
  preTypedExecutionDigest: '4c779e20477798896409e9d967b78557e81804fc625aa309db8e4faabc220b33',
  preTypedPlanDigest: '5c24d9e731cfc6859ff91d0a7da1d5a62c23cec0491ba3ff4860924ee9dbcf39',
  legacyDigest: '5f4dabc338bb780b8cdd965946815eef7b0c0f3f4a03dc824c06e4783d9989ca',
  preResourceDigest: '6acea9bb8f3669853489b481e5f2dc3a986b196f9247be76c51bcb29031301d3',
  dependencies: Object.freeze([Object.freeze({
    path: 'proofs/relation-pipeline/proof-runner-extension.mjs',
    authoredPath: 'proofs/relation-pipeline/proof-runner-extension.mts',
    authoredDigest: 'c75ff6b2fc9453f8d2d2d2cca7574f36bbad8346b7abe88f6d9c969ace653334',
    digest: 'e510caa50fbdb48c1c0d179f74ab351f158de81e086620e801ecd8f2aa80b9bb',
  })]),
});
// The mutation executor also reads these audit inputs during restoration.
export const mutationSnapshotExtras = Object.freeze([
  'toolchain.json', 'moon.mod',
  'docs/reviews/2026-09-23-local-resource-production-routes.json',
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
  'adapters/host-node/ordinary-node-resource-runtime.cjs',
]);
const resourceRuntime = 'adapters/host-node/ordinary-node-resource-runtime.cjs';
const resourceOriginal = 'adapters/host-node/ordinary-node-resource-runtime.cts';
export function mutationSnapshotPaths(tree) {
  if (!tree.entries.has(resourceOriginal)) return mutationSnapshotExtras;
  return [...mutationSnapshotExtras.filter(path => path !== resourceRuntime), resourceOriginal,
    'tsconfig.base.json', 'tsconfig.tooling.json', 'package-lock.json'];
}
const validSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const validPath = value => typeof value === 'string' && /^[A-Za-z0-9_.\/-]+$/u.test(value) &&
  !value.startsWith('/') && !value.split('/').some(part => ['', '.', '..'].includes(part));
const pipelineBoundaries = [pipelineInventoryBoundary, ...pipelineInventoryBoundary.dependencies];
export const sharedFiles = ['proofs/ci-evidence/actions.mjs', 'proofs/ci-evidence/inputs.mjs',
  ...pipelineBoundaries.map(({path}) => path),
  'proofs/ci-evidence/costs.mjs',
  'proofs/ci-evidence/execution-recipes.mjs',
  'proofs/events-bridge/evidence.mjs',
  'proofs/events-bridge/observations.mjs',
  'proofs/bounded-session/evidence.mjs', 'proofs/bounded-session/run.mjs',
  'proofs/ci-evidence/package-configurations.mjs',
  'proofs/ci-evidence/isolated-contract.mjs',
  'proofs/ci-evidence/receipts.mjs', 'proofs/ci-evidence/check.mjs',
  'proofs/ci-evidence/applications.mjs',
  'proofs/ci-evidence/acceptance.mjs', 'proofs/ci-evidence/acquisition.mjs',
  'proofs/ci-evidence/plan.mjs',
  'proofs/ci-evidence/isolation.mjs', 'proofs/ci-evidence/isolated-mutations.mjs',
  'proofs/ci-evidence/isolated-runtime.mjs', 'proofs/ci-evidence/isolated-execution.mjs',
  'proofs/ci-evidence/mutation-inventory.mjs',
  'proofs/ci-evidence/mutation-observation.mjs',
  'proofs/ci-evidence/runtime.mjs', 'proofs/ci-evidence/collect.mjs', 'proofs/ci-evidence/transport.mjs', 'proofs/ci-evidence/final.mjs',
  'proofs/ci-evidence/cli.mjs',
  'proofs/ci-evidence/Reuse.lean', 'proofs/ci-evidence/Claims.lean',
  'package.json', 'package-lock.json',
  'scripts/test-execution.mjs', 'scripts/packed-query-evidence.mjs', 'scripts/ci-artifact-reader.mjs',
  'proofs/bounded-session/action-inputs.mjs', 'toolchain.json', 'moon.mod',
  'scripts/setup-moonbit.mjs', 'scripts/moonbit-installation.mjs',
  'scripts/ci-main-base.mjs', 'scripts/ci-targets.mjs',
  '.github/workflows/ci.yml', '.github/actions/setup-toolchain/action.yml'];

// Migrated runtime entry names stay stable. In a Git input inventory retain
// the actual authored member. An old tree with only JavaScript keeps its
// original path and key. Never bind a checkout's untracked emitted bytes.
const migratedTooling = new Map([
  ...pipelineBoundaries.map(({path, authoredPath}) => [path, authoredPath]),
  ['scripts/test-execution.mjs', 'scripts/test-execution.mts'],
  ['scripts/packed-query-evidence.mjs', 'scripts/packed-query-evidence.mts'],
  ['scripts/ci-artifact-reader.mjs', 'scripts/ci-artifact-reader.mts'],
  ['scripts/ci-main-base.mjs', 'scripts/ci-main-base.mts'],
]);
export const typescriptPreparationInputs = Object.freeze([
  'tsconfig.base.json', 'tsconfig.tooling.json', 'scripts/typescript-executable-modes.mts',
]);
export function proofToolingInputs(tree, originalPaths) {
  const paths = new Set(), unresolved = [];
  let typescript = false;
  function addTyped(authored, runtime) {
    if (tree.entries.has(runtime)) unresolved.push(`ambiguous authored tooling input: ${runtime}`);
    paths.add(authored);
    typescript = true;
  }
  for (const path of originalPaths) {
    const authored = migratedTooling.get(path);
    if (authored && tree.entries.has(authored)) addTyped(authored, path);
    else paths.add(path);
    if (path === 'scripts/test-execution.mjs' && tree.entries.has(authored)) {
      addTyped('scripts/test-execution-reporter.mts', 'scripts/test-execution-reporter.mjs');
    }
    if (path === 'scripts/ci-main-base.mjs') {
      const runtime = 'scripts/ci-core-partitions.mjs', original = 'scripts/ci-core-partitions.mts';
      if (tree.entries.has(authored) || tree.entries.has(original)) addTyped(original, runtime);
      else {
        // A legacy Git original retains its existing evidence key. A missing
        // companion cannot be treated as the historical tracked runtime.
        const legacy = tree.entries.get(runtime);
        if (!legacy) addTyped(original, runtime);
        else if (legacy.kind !== 'blob' || !['100644', '100755'].includes(legacy.mode))
          unresolved.push(`unsupported source kind/mode: ${runtime}`);
      }
    }
  }
  if (typescript) typescriptPreparationInputs.forEach(path => paths.add(path));
  return {paths: [...paths], unresolved};
}

// Read cat-file's length-delimited binary protocol, never split blob bytes on
// newlines. Bind every returned object to the ls-tree identity and content; a
// missing/truncated/reordered/substituted response cannot populate the cache.
export function readBlobBatch(output, objects) {
  assert(Buffer.isBuffer(output) && Array.isArray(objects) && objects.length > 0 && objects.length <= 256);
  const parsed = new Map();
  let offset = 0;
  for (const object of objects) {
    assert(validSha(object) && !parsed.has(object), 'Invalid/duplicate requested Git blob');
    const end = output.indexOf(10, offset);
    assert(end >= offset, 'Missing Git batch header');
    const header = output.subarray(offset, end).toString('ascii');
    const match = /^([a-f0-9]{40}) blob (0|[1-9][0-9]*)$/u.exec(header);
    assert(match && match[1] === object, 'Missing/wrong Git batch blob identity/type');
    const size = Number(match[2]); offset = end + 1;
    assert(Number.isSafeInteger(size) && size <= 64 * 1024 * 1024 && offset + size < output.length && output[offset + size] === 10,
      'Truncated/unbounded Git batch blob');
    const bytes = output.subarray(offset, offset + size);
    const digest = createHash('sha1').update(`blob ${size}\0`).update(bytes).digest('hex');
    assert.equal(digest, object, 'Git batch blob bytes differ from object identity');
    parsed.set(object, Buffer.from(bytes)); offset += size + 1;
  }
  assert.equal(offset, output.length, 'Unexpected extra Git batch output');
  return parsed;
}

// Read an immutable Git revision. No generated/untracked inputs can silently
// join the closure. The execution boundary must independently require a clean
// tracked checkout and the corresponding runtime manifest.
export function gitTree(root, revision) {
  assert(validSha(revision), 'Expected full input revision');
  const git = (args, input) => execFileSync('git', args, {cwd: root, input, maxBuffer: 64 * 1024 * 1024});
  assert.equal(git(['replace', '-l']).toString().trim(), '', 'Replaced Git history');
  const entries = new Map();
  const bytes = new Map();
  for (const record of git(['ls-tree', '-rz', '--full-tree', revision]).toString('utf8').split('\0').filter(Boolean)) {
    const match = /^(\d{6}) (blob|commit) ([a-f0-9]{40})\t([\s\S]+)$/u.exec(record);
    assert(match, 'Unmodelled Git object');
    entries.set(match[4], {path: match[4], mode: match[1], object: match[3], kind: match[2]});
  }
  function prefetch(paths) {
    const objects = new Set();
    for (const path of paths) {
      const entry = entries.get(path);
      assert(entry?.kind === 'blob', `Missing source input: ${path}`);
      if (!bytes.has(entry.object)) objects.add(entry.object);
    }
    const selected = [...objects];
    for (let offset = 0; offset < selected.length; offset += 256) {
      const batch = selected.slice(offset, offset + 256);
      const parsed = readBlobBatch(git(['cat-file', '--batch'], `${batch.join('\n')}\n`), batch);
      for (const [object, data] of parsed) bytes.set(object, data);
    }
  }
  return {revision, entries, prefetch, read(path) {
    const entry = entries.get(path);
    assert(entry?.kind === 'blob', `Missing source input: ${path}`);
    if (!bytes.has(entry.object)) prefetch([path]);
    return bytes.get(entry.object);
  }};
}

// Only this opt-in Git snapshot owns private immutable bytes and entries.
// Legacy gitTree and caller-supplied trees retain their original semantics.
const immutableSnapshots = new WeakMap();
function plainData(value, seen = new Set()) {
  if (value === null || ['string', 'boolean'].includes(typeof value)) return true;
  if (typeof value === 'number') return Number.isSafeInteger(value) && !Object.is(value, -0);
  if (typeof value !== 'object' || types.isProxy(value) || seen.has(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== Array.prototype) return false;
  if (Object.getOwnPropertySymbols(value).length) return false;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const names = Object.keys(descriptors);
  if (Array.isArray(value) && (names.length !== value.length + 1 ||
      !Array.from({length: value.length}, (_, index) => String(index)).every(name => Object.hasOwn(descriptors, name)))) return false;
  seen.add(value);
  const valid = names.every(name => Array.isArray(value) && name === 'length' ||
    descriptors[name].enumerable && Object.hasOwn(descriptors[name], 'value') && plainData(descriptors[name].value, seen));
  seen.delete(value);
  return valid;
}
// Inspect only descriptors: unsupported options must reach the original
// destructuring exactly once, without first observing accessors or proxies.
function stableOptions(options, names) {
  if (!options || typeof options !== 'object' || types.isProxy(options) ||
      Object.getPrototypeOf(options) !== Object.prototype || Object.getOwnPropertySymbols(options).length) return null;
  const descriptors = Object.getOwnPropertyDescriptors(options);
  if (!Object.values(descriptors).every(entry => entry.enumerable && Object.hasOwn(entry, 'value')) ||
      !names.every(name => Object.hasOwn(descriptors, name))) return null;
  return Object.fromEntries(names.map(name => [name, descriptors[name].value]));
}
function snapshotMemo(tree, family, input, calculate) {
  const state = immutableSnapshots.get(tree);
  if (!state || !plainData(input)) return calculate();
  const key = encode(input), cache = state[family];
  if (cache.has(key)) return structuredClone(cache.get(key));
  const result = calculate();
  // Neither caller input objects nor returned manifests alias cached DATA.
  cache.set(key, structuredClone(result));
  return structuredClone(cache.get(key));
}

export function immutableGitTree(root, revision) {
  const original = gitTree(root, revision);
  const entries = new Map([...original.entries].map(([path, entry]) =>
    [path, Object.freeze({...entry})]));
  const bytes = new Map(), facts = new Map();
  const retained = path => {
    const entry = entries.get(path);
    assert(entry?.kind === 'blob', `Missing source input: ${path}`);
    if (!bytes.has(entry.object)) bytes.set(entry.object, Buffer.from(original.read(path)));
    return bytes.get(entry.object);
  };
  const view = Object.freeze({size: entries.size,
    get: path => entries.get(path), has: path => entries.has(path),
    keys: () => entries.keys(), values: () => entries.values(),
    entries: () => entries.entries(), [Symbol.iterator]: () => entries[Symbol.iterator]()});
  const tree = Object.freeze({revision, entries: view,
    prefetch(paths) { original.prefetch(paths); },
    read(path) { return Buffer.from(retained(path)); }});
  immutableSnapshots.set(tree, {packages: new Map(), actions: new Map(), fact(path) {
    const entry = entries.get(path), data = retained(path);
    if (!facts.has(entry.object)) facts.set(entry.object, {bytes: data.length, digest: hash(data)});
    return facts.get(entry.object);
  }});
  return tree;
}

// Scope only immutable Git DATA, never a remote receipt, permission, availability
// or currentness result. Every tree lookup still refuses replaced Git history.
export function gitInputScope(root) {
  const trees = new Map();
  return revision => {
    assert(validSha(revision), 'Expected full input revision');
    if (!trees.has(revision)) trees.set(revision, immutableGitTree(root, revision));
    else assert.equal(execFileSync('git', ['replace', '-l'], {cwd: root, encoding: 'utf8'}).trim(), '', 'Replaced Git history');
    return trees.get(revision);
  };
}

// This is a deliberately limited parser, not a general MoonBit interpreter.
// It accepts the existing literal import/supported-target syntax. Unknown
// options or dependency expressions keep only the affected action fresh.
export function packageImports(source) {
  const imports = [];
  let remainder = source.replace(/\/\*[\s\S]*?\*\//gu, '').replace(/\/\/[^\n]*/gu, '');
  remainder = remainder.replace(/import\s*\{([^{}]*)\}\s*(?:for\s*"(?:test|wbtest)")?/gu, (_, body) => {
    const residue = body.replace(/"([a-zA-Z0-9_\/-]+)"\s*(?:@[A-Za-z0-9_]+)?\s*,?/gu, (__, dependency) => {
      imports.push(dependency); return '';
    });
    assert(!residue.trim(), 'Nonliteral/unknown package import');
    return '';
  });
  remainder = remainder.replace(/supported_targets\s*=\s*"[+a-z-]+"/gu, '');
  // The existing formatter's literal ignore list cannot execute build work or
  // change dependency selection. Keep its bytes in the manifest nevertheless.
  // No other formatter expression/option is silently treated as harmless.
  remainder = remainder.replace(/formatter\s*\(\s*ignore\s*:\s*\[([^\[\]]*)\]\s*,?\s*\)/gu, (_, body) => {
    const residue = body.replace(/"[A-Za-z0-9_.-]+\.mbt"\s*,?/gu, '');
    assert(!residue.trim(), 'Nonliteral/unknown formatter ignore');
    return '';
  });
  return {imports: [...new Set(imports)].sort(), unknown: remainder.trim() ? 'Unreviewed package configuration' : null};
}

// Bind the selected compiler packages and their literal transitive imports.
// Package members include tests and non-Moon files; nested unmodelled data and
// configuration never become an inferred closed boundary.
export function packageSourceInputs(options) {
  const stable = stableOptions(options, ['tree', 'packages', 'target']);
  if (!stable) return buildPackageSourceInputs(options);
  return snapshotMemo(stable.tree, 'packages', [stable.packages, stable.target], () => buildPackageSourceInputs(stable));
}
function buildPackageSourceInputs({tree, packages, target}) {
  const paths = new Set(), listings = new Map(), external = new Set(), unresolved = new Set(), configurations = [];
  const visited = new Set();
  let pending = [...packages];
  // Build directory membership once for this invocation. Every Git path is
  // observed, including unmodelled nested inputs; a later call rebuilds the
  // index and therefore observes additions, removals and renames anew.
  const immediate = new Map(), descendants = new Map();
  for (const path of tree.entries.keys()) {
    const last = path.lastIndexOf('/');
    if (last < 0) continue;
    const parent = path.slice(0, last);
    if (!immediate.has(parent)) immediate.set(parent, []);
    immediate.get(parent).push(path);
    for (let offset = path.indexOf('/'); offset >= 0 && offset < last; offset = path.indexOf('/', offset + 1)) {
      const ancestor = path.slice(0, offset);
      if (!descendants.has(ancestor)) descendants.set(ancestor, []);
      descendants.get(ancestor).push(path);
    }
  }
  const toolchainDigest = tree.entries.get('toolchain.json')?.kind === 'blob' ? hash(tree.read('toolchain.json')) : null;
  function add(path) {
    if (!tree.entries.has(path)) { unresolved.add(`missing source input: ${path}`); return; }
    paths.add(path);
    const entry = tree.entries.get(path);
    if (!validPath(path)) unresolved.add(`unmodelled source path: ${path}`);
    if (!['100644', '100755'].includes(entry.mode) || entry.kind !== 'blob') unresolved.add(`unsupported source kind/mode: ${path}`);
  }
  function visit(directory) {
    if (visited.has(directory)) return;
    visited.add(directory);
    const members = (immediate.get(directory) ?? []).sort();
    listings.set(`${directory}/*`, members); members.forEach(add);
    const manifest = `${directory}/moon.pkg`; add(manifest);
    if (tree.entries.get(manifest)?.kind !== 'blob') return;
    let result;
    try { result = packageImports(tree.read(manifest).toString('utf8')); }
    catch { unresolved.add(`unmodelled import syntax: ${manifest}`); return; }
    if (result.unknown) {
      const digest = hash(tree.read(manifest));
      const review = packageConfigurationReviewFor({path: manifest, digest, target, toolchainDigest});
      if (review)
        configurations.push({path: manifest, digest, target, toolchainDigest, review});
      else unresolved.add(`${result.unknown}: ${manifest}`);
    }
    for (const dependency of result.imports) {
      if (dependency.startsWith('actql/actql/')) {
        const child = `src/${dependency.slice('actql/actql/'.length)}`;
        if (!validPath(child)) { unresolved.add(`invalid local dependency: ${manifest}`); continue; }
        pending.push(child);
      } else if (dependency.startsWith('moonbitlang/core/')) external.add(dependency);
      else unresolved.add(`unmodelled external dependency: ${dependency}`);
    }
    for (const path of descendants.get(directory) ?? []) {
      const first = `${directory}/${path.slice(directory.length + 1).split('/')[0]}`;
      if (!tree.entries.has(`${first}/moon.pkg`)) {
        add(path);
        if (tree.entries.get(path)?.kind !== 'blob' || !reviewedNestedFixture({
          path, digest: hash(tree.read(path)), target, toolchainDigest,
        })) unresolved.add(`nested package input requires review: ${path}`);
      }
    }
  }
  while (pending.length) {
    const frontier = [...new Set(pending)].filter(directory => !visited.has(directory));
    pending = [];
    // Only already discovered dependency manifests are fetched. The tree's
    // bounded, object-verified batch reader retains exact immutable bytes;
    // no unrelated package or cross-call closure cache is introduced.
    const manifests = frontier.map(directory => `${directory}/moon.pkg`)
      .filter(path => tree.entries.get(path)?.kind === 'blob');
    if (manifests.length) tree.prefetch?.(manifests);
    frontier.forEach(visit);
  }
  return {paths: [...paths].sort(), directories: [...listings].sort(([a], [b]) => a.localeCompare(b))
    .map(([path, members]) => ({path, members})), externalPackages: [...external].sort(),
    packageConfigurations: configurations.sort((a, b) => a.path.localeCompare(b.path)), unresolved: [...unresolved].sort()};
}

export const mutationPackages = Object.freeze(['src/bounded_execution', 'src/connectors/local', 'src/query_integration']);
export function mutationSourceInputs(tree) {
  const selected = packageSourceInputs({tree, packages: mutationPackages, target: 'js'});
  if (selected.unresolved.length) {
    // Unknown dependency syntax prevents narrowing. Keep fresh execution's
    // complete source tree, and preserve the reasons that forbid reuse.
    const members = [...tree.entries.keys()].filter(path => path.startsWith('src/')).sort();
    selected.paths = [...new Set([...selected.paths, ...members])].sort();
    selected.directories.push({path: 'src/**', members});
    selected.directories.sort((a, b) => a.path.localeCompare(b.path));
  }
  return selected;
}

export function actionInputs(options) {
  const stable = stableOptions(options, ['tree', 'revision', 'action', 'runtime']);
  if (!stable) return buildActionInputs(options);
  return snapshotMemo(stable.tree, 'actions', [inputVersion, stable.revision, stable.action, stable.runtime, sharedFiles], () => buildActionInputs(stable));
}
function buildActionInputs({tree, revision, action, runtime}) {
  assert(validSha(revision));
  assert(runtime && typeof runtime === 'object' && Array.isArray(runtime.unresolved), 'Missing runtime boundary');
  const included = new Set(), listings = new Map(), external = new Set(), unresolved = new Set(runtime.unresolved);
  const configurations = [];
  function add(path) {
    if (!tree.entries.has(path)) { unresolved.add(`missing source input: ${path}`); return; }
    included.add(path);
    const entry = tree.entries.get(path);
    if (!validPath(path)) unresolved.add(`unmodelled source path: ${path}`);
    if (!['100644', '100755'].includes(entry.mode) || entry.kind !== 'blob') unresolved.add(`unsupported source kind/mode: ${path}`);
  }
  function listing(directory, recursive) {
    const paths = [...tree.entries.keys()].filter(path => path.startsWith(`${directory}/`) &&
      (recursive || !path.slice(directory.length + 1).includes('/'))).sort();
    listings.set(directory + (recursive ? '/**' : '/*'), paths);
    paths.forEach(add);
  }
  const tooling = proofToolingInputs(tree, sharedFiles);
  tooling.paths.forEach(add);
  tooling.unresolved.forEach(reason => unresolved.add(reason));
  // Pipeline scientific consumers are now loaded only in explicit local
  // pipeline executions. Their directory is not read/evaluated by Session.
  // Bind every evaluated module in the reviewed inventory import graph. A
  // changed dependency cannot inherit the inventory's unchanged digest.
  const pipelineRoot = 'proofs/relation-pipeline/';
  const hasTypedPlan = tree.entries.has(pipelineRoot + 'proof-parts.mts');
  const hasTypedExecution = tree.entries.has(pipelineRoot + 'execution-names.mts') ||
    tree.entries.has(pipelineRoot + 'execution-names.test.mts');
  const hasTypedWorkspace = ['workspaces.mts', 'workspaces.test.mts', 'fixtures/execution-driver.mts']
    .some(path => tree.entries.has(pipelineRoot + path));
  const hasTypedExecutor = [
    'execute.mts', 'execute.test.mts', 'execution-original.mts', 'executor-close.test.mts', 'fixture.mts', 'fixture.test.mts',
  ].some(path => tree.entries.has(pipelineRoot + path));
  const allTyped = pipelineBoundaries.every(({authoredPath}) => tree.entries.has(authoredPath));
  for (const {path, digest, authoredPath, authoredDigest, legacyDigest, preResourceDigest, preTypedPlanDigest,
    preTypedExecutionDigest, preTypedWorkspaceDigest, preTypedExecutorDigest, preTypedRunnerDigest} of pipelineBoundaries) {
    const typed = authoredPath && tree.entries.has(authoredPath);
    const selected = typed ? authoredPath : path;
    const entry = tree.entries.get(selected);
    const actual = entry?.kind === 'blob' && entry.mode === '100644' ? hash(tree.read(selected)) : null;
    if (typed) {
      const declaration = authoredPath.slice(0, -4) + '.d.mts';
      const expected = preTypedRunnerDigest && !allTyped ? preTypedRunnerDigest : authoredDigest;
      if (actual !== expected || tree.entries.has(declaration))
        unresolved.add('unreviewed pipeline inventory import/effect boundary');
      continue;
    }
    const preTypedPlan = !hasTypedPlan && !hasTypedExecution && !hasTypedWorkspace && !hasTypedExecutor;
    const preTypedExecution = hasTypedPlan && !hasTypedExecution && !hasTypedWorkspace && !hasTypedExecutor;
    const preTypedWorkspace = hasTypedPlan && hasTypedExecution && !hasTypedWorkspace && !hasTypedExecutor;
    const preTypedExecutor = hasTypedPlan && hasTypedExecution && hasTypedWorkspace && !hasTypedExecutor;
    const historicalResource = preTypedPlan && !tree.entries.has(resourceOriginal);
    const legacy = legacyDigest && historicalResource && !tree.entries.has('scripts/owned-scratch.mts');
    const preResource = preResourceDigest && historicalResource;
    if (actual !== digest && (!legacy || actual !== legacyDigest) &&
        (!preResource || actual !== preResourceDigest) && (!preTypedPlan || actual !== preTypedPlanDigest) &&
        (!preTypedExecution || actual !== preTypedExecutionDigest) && (!preTypedWorkspace || actual !== preTypedWorkspaceDigest) &&
        (!preTypedExecutor || actual !== preTypedExecutorDigest))
      unresolved.add('unreviewed pipeline inventory import/effect boundary');
  }
  function bridgeInputs() {
    listing('proofs/events-bridge', true);
    for (const file of ['Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean',
      'lean-toolchain', 'check.mjs']) add(`proofs/events-bridge/${file}`);
  }
  // The descriptor is hashed separately, so adding a registered provider
  // cannot reuse evidence solely by copying an old requested scope.
  if (action.id === 'model') {
    for (const file of ['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs']) add(`proofs/bounded-session/${file}`);
  } else if (action.id === 'events-model') {
    bridgeInputs();
  } else {
    listing('proofs/bounded-session', true);
    if (action.id.startsWith('events-connection-')) bridgeInputs();
    const packageInputs = action.package ? packageSourceInputs({tree, packages: [action.package], target: action.target}) :
      action.id === 'mutations-js' ? mutationSourceInputs(tree) : null;
    if (packageInputs) {
      packageInputs.paths.forEach(add);
      packageInputs.directories.forEach(({path, members}) => listings.set(path, members));
      packageInputs.externalPackages.forEach(path => external.add(path));
      packageInputs.unresolved.forEach(reason => unresolved.add(reason));
      configurations.push(...packageInputs.packageConfigurations);
    }
    if (action.id === 'mutations-js') {
      mutationSnapshotPaths(tree).forEach(add);
      if (tree.entries.has(resourceOriginal) && tree.entries.has(resourceRuntime))
        unresolved.add('ambiguous authored Node Resource bridge');
      add('proofs/bounded-session/mutations.mjs');
      add('proofs/bounded-session/evidence.mjs');
    } else if (!action.package) unresolved.add(`unreviewed executor: ${action.id}`);
  }
  const paths = [...included].sort();
  tree.prefetch?.(paths.filter(path => tree.entries.get(path).kind === 'blob'));
  const files = paths.map(path => {
    const entry = tree.entries.get(path);
    const fact = entry.kind === 'blob' ? immutableSnapshots.get(tree)?.fact(path) : null;
    const bytes = entry.kind === 'blob' && !fact ? tree.read(path) : null;
    return {path, kind: entry.kind, mode: entry.mode, bytes: fact?.bytes ?? bytes?.length ?? 0,
      digest: fact?.digest ?? (bytes ? hash(bytes) : entry.object)};
  });
  const inputs = {action, files, directories: [...listings].sort(([a], [b]) => a.localeCompare(b)).map(([path, members]) => ({path, members})),
    externalPackages: [...external].sort(), packageConfigurations: configurations.sort((a, b) => a.path.localeCompare(b.path)),
    runtime, unresolved: [...unresolved].sort()};
  return {version: inputVersion, revision, inputs, key: hash(`actql-verification-action-key/0.1\0${encode(inputs)}`),
    unresolved: [...unresolved].sort()};
}

export function compareInputs(origin, candidate) {
  assert.equal(origin.version, inputVersion); assert.equal(candidate.version, inputVersion);
  for (const manifest of [origin, candidate]) {
    assert.equal(manifest.key, hash(`actql-verification-action-key/0.1\0${encode(manifest.inputs)}`), 'Input identity mismatch');
    assert(validSha(manifest.revision) && Array.isArray(manifest.unresolved));
    assert.equal(encode(manifest.unresolved), encode(manifest.inputs.unresolved), 'Carried unresolved boundary changed');
  }
  return {equal: encode(origin.inputs) === encode(candidate.inputs),
    eligible: origin.unresolved.length === 0 && candidate.unresolved.length === 0 && encode(origin.inputs) === encode(candidate.inputs),
    reasons: [...new Set([...origin.unresolved, ...candidate.unresolved])].sort()};
}
