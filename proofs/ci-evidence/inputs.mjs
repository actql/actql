import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {encode} from '../bounded-session/action-inputs.mjs';

export const inputVersion = 'actql-verification-action-inputs/0.1';
export const hash = value => createHash('sha256').update(value).digest('hex');
const validSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const validPath = value => typeof value === 'string' && /^[A-Za-z0-9_.\/-]+$/u.test(value) &&
  !value.startsWith('/') && !value.split('/').some(part => ['', '.', '..'].includes(part));
export const sharedFiles = ['proofs/ci-evidence/actions.mjs', 'proofs/ci-evidence/inputs.mjs',
  'proofs/ci-evidence/receipts.mjs', 'proofs/ci-evidence/check.mjs',
  'proofs/ci-evidence/applications.mjs',
  'proofs/ci-evidence/collect.mjs', 'proofs/ci-evidence/transport.mjs', 'proofs/ci-evidence/final.mjs',
  'proofs/ci-evidence/cli.mjs',
  'proofs/ci-evidence/Reuse.lean', 'proofs/ci-evidence/Claims.lean',
  'scripts/test-execution.mjs', 'scripts/packed-query-evidence.mjs', 'scripts/ci-artifact-reader.mjs',
  'proofs/bounded-session/action-inputs.mjs', 'toolchain.json', 'moon.mod',
  'scripts/setup-moonbit.mjs', 'scripts/moonbit-installation.mjs',
  'scripts/ci-main-base.mjs', 'scripts/ci-targets.mjs',
  '.github/workflows/ci.yml', '.github/actions/setup-toolchain/action.yml'];

// Read an immutable Git revision. No generated/untracked inputs can silently
// join the closure. The execution boundary must independently require a clean
// tracked checkout and the corresponding runtime manifest.
export function gitTree(root, revision) {
  assert(validSha(revision), 'Expected full input revision');
  const git = args => execFileSync('git', args, {cwd: root, maxBuffer: 64 * 1024 * 1024});
  assert.equal(git(['replace', '-l']).toString().trim(), '', 'Replaced Git history');
  const entries = new Map();
  const bytes = new Map();
  for (const record of git(['ls-tree', '-rz', '--full-tree', revision]).toString('utf8').split('\0').filter(Boolean)) {
    const match = /^(\d{6}) (blob|commit) ([a-f0-9]{40})\t([\s\S]+)$/u.exec(record);
    assert(match, 'Unmodelled Git object');
    entries.set(match[4], {path: match[4], mode: match[1], object: match[3], kind: match[2]});
  }
  return {entries, read(path) {
    const entry = entries.get(path);
    assert(entry?.kind === 'blob', `Missing source input: ${path}`);
    if (!bytes.has(entry.object)) bytes.set(entry.object, git(['cat-file', 'blob', entry.object]));
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
  return {imports: [...new Set(imports)].sort(), unknown: remainder.trim() ? 'Unreviewed package configuration' : null};
}

export function actionInputs({tree, revision, action, runtime}) {
  assert(validSha(revision));
  assert(runtime && typeof runtime === 'object' && Array.isArray(runtime.unresolved), 'Missing runtime boundary');
  const included = new Set(), listings = new Map(), external = new Set(), unresolved = new Set(runtime.unresolved);
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
  // The descriptor is hashed separately, so adding a registered provider
  // cannot reuse evidence solely by copying an old requested scope.
  if (action.id === 'model') {
    for (const file of ['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs']) add(`proofs/bounded-session/${file}`);
  } else {
    listing('proofs/bounded-session', true);
    const visited = new Set();
    function visit(directory) {
      if (visited.has(directory)) return;
      visited.add(directory);
      listing(directory, false);
      const manifest = `${directory}/moon.pkg`;
      add(manifest);
      if (!tree.entries.has(manifest)) return;
      let result;
      try { result = packageImports(tree.read(manifest).toString('utf8')); }
      catch { unresolved.add(`unmodelled import syntax: ${manifest}`); return; }
      if (result.unknown) unresolved.add(`${result.unknown}: ${manifest}`);
      for (const dependency of result.imports) {
        if (dependency.startsWith('actql/actql/')) {
          const child = `src/${dependency.slice('actql/actql/'.length)}`;
          if (!validPath(child)) { unresolved.add(`invalid local dependency: ${manifest}`); continue; }
          visit(child);
        } else if (dependency.startsWith('moonbitlang/core/')) external.add(dependency);
        else unresolved.add(`unmodelled external dependency: ${dependency}`);
      }
      // Nested non-package files can be include/data/native inputs. This initial
      // package boundary does not guess that such files are irrelevant.
      for (const path of tree.entries.keys()) {
        if (path.startsWith(`${directory}/`) && path.slice(directory.length + 1).includes('/')) {
          const first = `${directory}/${path.slice(directory.length + 1).split('/')[0]}`;
          if (!tree.entries.has(`${first}/moon.pkg`)) { add(path); unresolved.add(`nested package input requires review: ${path}`); }
        }
      }
    }
    if (action.package) visit(action.package);
    else if (action.id === 'mutations-js') {
      for (const path of ['src/bounded_execution', 'src/connectors/local', 'src/query_integration']) visit(path);
    } else unresolved.add(`unreviewed executor: ${action.id}`);
  }
  const files = [...included].sort().map(path => {
    const entry = tree.entries.get(path);
    const bytes = entry.kind === 'blob' ? tree.read(path) : null;
    return {path, kind: entry.kind, mode: entry.mode, bytes: bytes?.length ?? 0, digest: bytes ? hash(bytes) : entry.object};
  });
  const inputs = {action, files, directories: [...listings].sort(([a], [b]) => a.localeCompare(b)).map(([path, members]) => ({path, members})),
    externalPackages: [...external].sort(), runtime, unresolved: [...unresolved].sort()};
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
