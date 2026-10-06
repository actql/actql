import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {encode} from '../bounded-session/action-inputs.mjs';
import {reviewedPackageConfiguration, packageConfigurationReview} from './package-configurations.mjs';

export const inputVersion = 'actql-verification-action-inputs/0.1';
export const hash = value => createHash('sha256').update(value).digest('hex');
// The mutation executor also reads these audit inputs during restoration.
export const mutationSnapshotExtras = Object.freeze([
  'toolchain.json', 'moon.mod',
  'docs/reviews/2026-09-23-local-resource-production-routes.json',
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
]);
const validSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const validPath = value => typeof value === 'string' && /^[A-Za-z0-9_.\/-]+$/u.test(value) &&
  !value.startsWith('/') && !value.split('/').some(part => ['', '.', '..'].includes(part));
export const sharedFiles = ['proofs/ci-evidence/actions.mjs', 'proofs/ci-evidence/inputs.mjs',
  'proofs/ci-evidence/costs.mjs',
  'proofs/ci-evidence/execution-recipes.mjs',
  'proofs/events-bridge/evidence.mjs',
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
  return {entries, prefetch, read(path) {
    const entry = entries.get(path);
    assert(entry?.kind === 'blob', `Missing source input: ${path}`);
    if (!bytes.has(entry.object)) prefetch([path]);
    return bytes.get(entry.object);
  }};
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
export function packageSourceInputs({tree, packages, target}) {
  const paths = new Set(), listings = new Map(), external = new Set(), unresolved = new Set(), configurations = [];
  const visited = new Set();
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
    const members = [...tree.entries.keys()].filter(path => path.startsWith(`${directory}/`) &&
      !path.slice(directory.length + 1).includes('/')).sort();
    listings.set(`${directory}/*`, members); members.forEach(add);
    const manifest = `${directory}/moon.pkg`; add(manifest);
    if (tree.entries.get(manifest)?.kind !== 'blob') return;
    let result;
    try { result = packageImports(tree.read(manifest).toString('utf8')); }
    catch { unresolved.add(`unmodelled import syntax: ${manifest}`); return; }
    if (result.unknown) {
      const digest = hash(tree.read(manifest));
      if (reviewedPackageConfiguration({path: manifest, digest, target, toolchainDigest}))
        configurations.push({path: manifest, digest, target, toolchainDigest, review: packageConfigurationReview});
      else unresolved.add(`${result.unknown}: ${manifest}`);
    }
    for (const dependency of result.imports) {
      if (dependency.startsWith('actql/actql/')) {
        const child = `src/${dependency.slice('actql/actql/'.length)}`;
        if (!validPath(child)) { unresolved.add(`invalid local dependency: ${manifest}`); continue; }
        visit(child);
      } else if (dependency.startsWith('moonbitlang/core/')) external.add(dependency);
      else unresolved.add(`unmodelled external dependency: ${dependency}`);
    }
    for (const path of tree.entries.keys()) {
      if (path.startsWith(`${directory}/`) && path.slice(directory.length + 1).includes('/')) {
        const first = `${directory}/${path.slice(directory.length + 1).split('/')[0]}`;
        if (!tree.entries.has(`${first}/moon.pkg`)) { add(path); unresolved.add(`nested package input requires review: ${path}`); }
      }
    }
  }
  packages.forEach(visit);
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

export function actionInputs({tree, revision, action, runtime}) {
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
  sharedFiles.forEach(add);
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
      mutationSnapshotExtras.forEach(add);
      add('proofs/bounded-session/mutations.mjs');
      add('proofs/bounded-session/evidence.mjs');
    } else if (!action.package) unresolved.add(`unreviewed executor: ${action.id}`);
  }
  const paths = [...included].sort();
  tree.prefetch?.(paths.filter(path => tree.entries.get(path).kind === 'blob'));
  const files = paths.map(path => {
    const entry = tree.entries.get(path);
    const bytes = entry.kind === 'blob' ? tree.read(path) : null;
    return {path, kind: entry.kind, mode: entry.mode, bytes: bytes?.length ?? 0, digest: bytes ? hash(bytes) : entry.object};
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
