// Bind the actual contents of the isolated executor and check correspondence
// independently from the receipt's summary. This profile is comparison-only
// until its reviewed action/environment closure is accepted for activation.
import assert from 'node:assert/strict';
import {readFileSync, realpathSync, lstatSync} from 'node:fs';
import {join, relative, isAbsolute} from 'node:path';
import {release, cpus} from 'node:os';
import {inventoryDistribution} from './runtime.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {hash} from './inputs.mjs';
import {isolatedEnvironment, localIsolatedEnvironment, mutationSourcePaths, scratchDockerfile, localScratchDockerfile, isolatedCoreBuildMetadata} from './isolation.mjs';
import {mutationIds} from './mutation-inventory.mjs';
import {isolatedRunArguments, mutationSnapshotExtras, checkImageDefinition} from './isolation.mjs';
import {isolatedContract, matchesIsolatedContract, isolatedExperimentDigest} from './isolated-contract.mjs';
import {mutationObservation} from './mutation-observation.mjs';

export const isolatedProfile = 'isolated-session-mutations-linux';
export const isolatedResidual = 'isolated comparison only: reviewed action/kernel/CPU closure and acceptance remain required';
export const imageRoots = Object.freeze(['bin', 'lib', 'lib64', 'runtime', 'source', 'usr']);

export function platformInputs() {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  const info = readFileSync('/proc/cpuinfo', 'utf8');
  const values = key => [...new Set([...info.matchAll(new RegExp(`^${key}\\s*:\\s*(.*)$`, 'gmu'))].map(match => match[1]))].sort();
  return {platform: process.platform, architecture: process.arch, kernelRelease: release(),
    processorCount: cpus().length, vendors: values('vendor_id'), models: values('model name'),
    features: values('flags')};
}

export function observeImageRoot(root) {
  const entries = [], unresolved = [], links = [];
  for (const prefix of imageRoots) {
    let exists;
    try { exists = lstatSync(join(root, prefix)); } catch (error) { assert.equal(error.code, 'ENOENT'); continue; }
    assert(exists.isDirectory() && !exists.isSymbolicLink(), 'Image input root must be a real directory');
    const observation = inventoryDistribution(join(root, prefix), {maxEntries: 30000, maxBytes: 1024 ** 3});
    entries.push(...observation.entries.map(entry => ({...entry, path: entry.path ? `${prefix}/${entry.path}` : prefix})));
    // Keep the raw untraversed-link observation. Add a separate witness rather
    // than editing the preceding whole-installation inventory's gaps.
    for (const reason of observation.unresolved) unresolved.push(`${prefix}: ${reason}`);
  }
  for (const entry of entries.filter(value => value.kind === 'symlink')) {
    const resolved = relative(realpathSync(root), realpathSync(join(root, entry.path)));
    assert(resolved && !isAbsolute(resolved) && !resolved.startsWith('../'), 'Image link escapes immutable input roots');
    assert(entries.some(value => value.path === resolved && ['file', 'directory'].includes(value.kind)), 'Missing image link destination');
    links.push({path: entry.path, destination: resolved});
  }
  return {entries: entries.sort((a, b) => a.path.localeCompare(b.path)), unresolved: unresolved.sort(), links};
}

export function imageRuntime(manifest, {local = false} = {}) {
  assert(local ? manifest.localDiagnostic === true : manifest.localDiagnostic === undefined, 'Wrong local/Actions input authority');
  assert.equal(manifest.version, 'actql-isolated-mutation-inputs/0.1');
  const runtimeEntries = manifest.root.entries.filter(entry => !entry.path.startsWith('source/') && entry.path !== 'source');
  return {profile: local ? 'local-isolated-session-mutations-linux' : isolatedProfile, platform: 'linux', architecture: 'x64',
    environment: local ? localIsolatedEnvironment : isolatedEnvironment, platformInputs: manifest.platformInputs,
    rootDigest: hash(encode({entries: runtimeEntries, links: manifest.root.links.filter(link => !link.path.startsWith('source/')),
      unresolved: manifest.root.unresolved.filter(reason => !reason.startsWith('source: '))})),
    specificationDigest: hash(manifest.dockerfile),
    contract: !local && matchesIsolatedContract(manifest) ? isolatedContract : null,
    unresolved: local ? [isolatedResidual, 'local physical execution has no authenticated Actions origin'] : matchesIsolatedContract(manifest) ? [] : [isolatedResidual]};
}

export function checkIsolatedInputs({runtime, manifest, tree, local = false}) {
  assert.equal(encode(runtime), encode(imageRuntime(manifest, {local})), 'Wrong isolated runtime inputs or erased residual');
  assert.equal(encode(manifest.environment), encode(local ? localIsolatedEnvironment : isolatedEnvironment), 'Changed isolated environment');
  assert.equal(manifest.dockerfile, local ? localScratchDockerfile() : scratchDockerfile(), 'Changed isolated executor definition');
  assert.equal(manifest.sourceSnapshotDigest, snapshotFromGit(tree).digest, 'Wrong reviewed source cohort');
  assert.equal(manifest.experimentDigest, isolatedExperimentDigest(tree), 'Wrong reviewed finite experiment');
  assert.equal(manifest.toolchainDigest, hash(tree.read('toolchain.json')), 'Wrong reviewed toolchain pin');
  assert(typeof manifest.hostImage === 'string' && /^[A-Za-z0-9_.-]+$/u.test(manifest.hostImage), 'Invalid host image identity');
  assert.equal(manifest.platformInputs.platform, 'linux'); assert.equal(manifest.platformInputs.architecture, 'x64');
  const byPath = new Map(manifest.root.entries.map(entry => [entry.path, entry]));
  assert.equal(byPath.size, manifest.root.entries.length, 'Duplicate image input');
  for (const path of isolatedCoreBuildMetadata)
    assert(!byPath.has(`runtime/moonbit/${path}`), 'Installed core build metadata must be absent from the isolated image');
  const children = new Map();
  for (const entry of manifest.root.entries) {
    assert(typeof entry.path === 'string', 'Invalid image path');
    const offset = entry.path.lastIndexOf('/');
    if (offset >= 0) {
      const parent = entry.path.slice(0, offset);
      if (!children.has(parent)) children.set(parent, []);
      children.get(parent).push(entry.path.slice(offset + 1));
    }
  }
  for (const entry of manifest.root.entries) {
    assert(/^[A-Za-z0-9_.\/+\-]+$/u.test(entry.path) && !entry.path.split('/').some(part => ['', '.', '..'].includes(part)), 'Invalid image path');
    assert(imageRoots.includes(entry.path.split('/')[0]), 'Unreviewed image root');
    assert(['file', 'directory', 'symlink'].includes(entry.kind) && Number.isInteger(entry.mode) && entry.mode >= 0 && entry.mode <= 0o777, 'Unsupported image entry');
    if (entry.path.includes('/')) assert.equal(byPath.get(entry.path.slice(0, entry.path.lastIndexOf('/')))?.kind, 'directory', 'Missing image parent directory');
    if (entry.kind === 'file') assert(Number.isSafeInteger(entry.bytes) && entry.bytes >= 0 && /^[a-f0-9]{64}$/u.test(entry.digest), 'Incomplete image file');
    if (entry.kind === 'directory') {
      const actual = (children.get(entry.path) ?? []).sort();
      assert.deepEqual(entry.members, actual, 'Incomplete image directory membership');
    }
  }
  for (const path of ['runtime/node', 'runtime/moonbit/bin/moon', 'runtime/moonbit/bin/moonc', 'runtime/moonbit/bin/moonrun', 'bin/sh']) {
    const entry = byPath.get(path);
    assert(entry?.kind === 'file' && (entry.mode & 0o111) && entry.bytes > 0, 'Missing isolated executable');
  }
  assert(!byPath.has('runtime/lean'), 'Mutation action must not acquire a Lean installation');
  assert(new Set(manifest.root.links.map(link => link.path)).size === manifest.root.links.length, 'Duplicate link witness');
  for (const link of manifest.root.links) {
    assert(byPath.get(link.path)?.kind === 'symlink' && ['file', 'directory'].includes(byPath.get(link.destination)?.kind), 'Invalid image link witness');
  }
  // Every unresolved entry must be an internal link with an explicit bound
  // target. Unknown/limited/unstable observations never become complete.
  for (const reason of manifest.root.unresolved) {
    const match = /^([a-z0-9]+): untraversed symlink: (.+)$/u.exec(reason);
    assert(match, 'Incomplete isolated image observation');
    const path = `${match[1]}/${match[2]}`;
    assert(manifest.root.links.some(link => link.path === path && byPath.has(link.destination)), 'Unresolved image link');
  }
  const expected = mutationSourcePaths(tree);
  const sourceDirectories = new Set(['source']);
  for (const path of expected) {
    const parts = path.split('/');
    for (let length = 1; length < parts.length; length++) sourceDirectories.add(`source/${parts.slice(0, length).join('/')}`);
  }
  assert.deepEqual(manifest.root.entries.filter(entry => entry.kind === 'directory' && (entry.path === 'source' || entry.path.startsWith('source/')))
    .map(entry => entry.path).sort(), [...sourceDirectories].sort(), 'Missing/extra isolated source directory');
  const actual = manifest.root.entries.filter(entry => entry.kind !== 'directory' && entry.path.startsWith('source/'));
  assert.deepEqual(actual.map(entry => entry.path.slice('source/'.length)).sort(), expected, 'Missing/extra isolated source inputs');
  for (const path of expected) {
    const entry = byPath.get(`source/${path}`), source = tree.entries.get(path), bytes = tree.read(path);
    assert.equal(entry.kind, 'file'); assert.equal(entry.mode, Number.parseInt(source.mode.slice(-3), 8));
    assert.equal(entry.bytes, bytes.length); assert.equal(entry.digest, hash(bytes), 'Image source differs from actual Git');
  }
  assert(Array.isArray(manifest.loaderObservations) && manifest.loaderObservations.length === 5, 'Missing executable loader observations');
  const executablePaths = ['runtime/node', ...['moon', 'moonc', 'moonrun'].map(name => `runtime/moonbit/bin/${name}`), 'bin/sh'];
  assert.deepEqual(manifest.loaderObservations.map(value => value.executable), executablePaths);
  for (const loader of manifest.loaderObservations) {
    assert.equal(loader.digest, byPath.get(loader.executable).digest, 'Wrong inspected executable');
    assert(typeof loader.static === 'boolean' && Array.isArray(loader.paths));
    assert(loader.static ? loader.paths.length === 0 : loader.paths.length > 0);
    for (const path of loader.paths) assert(/^\/(?:usr\/)?lib(?:64)?\/[A-Za-z0-9_./+-]+$/u.test(path) && !path.split('/').includes('..') && byPath.get(path.slice(1))?.kind === 'file', 'Missing copied ELF input');
  }
  return true;
}

export function snapshotFromGit(tree) {
  const paths = mutationSourcePaths(tree).filter(path => path.startsWith('src/') || path.startsWith('proofs/bounded-session/') || mutationSnapshotExtras.includes(path));
  tree.prefetch?.(paths);
  const sources = Object.fromEntries(paths.sort().map(path => [path, hash(tree.read(path))]));
  return {digest: hash(JSON.stringify(sources)), sources};
}

// Check only the action's selected physical source inputs. Collection retains
// its separate full-checkout clean/HEAD checks for every candidate action.
// Reading unrelated blob bytes here would put them back into this action's
// dependency boundary even when they are absent from the isolated image.
export function checkMutationCheckout({root, tree}) {
  const expected = snapshotFromGit(tree);
  for (const [path, digest] of Object.entries(expected.sources)) {
    const entry = tree.entries.get(path), file = join(root, path), state = lstatSync(file);
    assert(state.isFile() && !state.isSymbolicLink(), 'Nonregular mutation checkout input');
    assert.equal(state.mode & 0o777, Number.parseInt(entry.mode.slice(-3), 8), 'Mutation checkout mode differs from Git');
    assert.equal(hash(readFileSync(file)), digest, 'Mutation checkout bytes differ from Git');
  }
  return expected;
}

export function checkIsolatedResult({payload, manifest, before}) {
  assert.equal(payload.version, 'actql-isolated-mutation-observation/0.1');
  assert.equal(encode(payload.root), encode(manifest.root), 'Actual immutable image differs from staged inputs');
  assert.equal(encode(payload.platformInputs), encode(manifest.platformInputs), 'Changed kernel/CPU execution profile');
  assert.equal(encode(payload.environment), encode(manifest.environment), 'Inherited or changed execution environment');
  assert.equal(payload.readOnlyConfirmed, true); assert.equal(payload.restored, true);
  assert.equal(payload.shellStartupConfirmed, true, 'Required build shell did not start');
  assert.equal(encode(payload.report.source), encode(before), 'Isolated action did not execute the selected actual source');
  mutationObservation(payload.report);
  assert.deepEqual(payload.report.results.map(entry => entry.id).sort(), [...mutationIds].sort());
  assert.deepEqual(Object.keys(payload.logs).sort(), [...mutationIds].sort(), 'Missing/extra original mutation logs');
  for (const entry of payload.report.results) {
    const output = payload.logs[entry.id];
    assert(typeof output === 'string' && Buffer.byteLength(output) <= 4 * 1024 * 1024);
    const failed = Number(output.match(/Total tests: \d+, passed: \d+, failed: (\d+)/u)?.[1] ?? 0);
    assert(entry.killed === true && entry.target === 'js' && entry.failureCount === failed && failed > 0 && !/Error: \[\d+\]/u.test(output),
      'Mutation was not detected by an executed assertion');
  }
  return true;
}

// Called only after opening an API-digest-bound immutable artifact. The input
// inventory and execution observation are independently checked against Git.
export async function readCandidateActionRuntimes({zip, state, tree}) {
  assert.deepEqual(Object.keys(state.actionRuntimes), ['mutations-js'], 'Missing/unreviewed isolated action scope');
  const manifest = await zip.json('isolated-inputs.json');
  checkIsolatedInputs({runtime: state.actionRuntimes['mutations-js'], manifest, tree});
  // Input preparation alone does not certify an execution. A reused action
  // must separately authenticate the original execution and its final owner.
  return state.actionRuntimes;
}

export async function readActionRuntimes({zip, state, tree}) {
  await readCandidateActionRuntimes({zip, state, tree});
  const manifest = await zip.json('isolated-inputs.json'), payload = await zip.json('isolated-observation.json');
  const execution = await zip.json('isolated-execution.json');
  checkIsolatedInputs({runtime: state.actionRuntimes['mutations-js'], manifest, tree});
  checkIsolatedResult({payload, manifest, before: snapshotFromGit(tree)});
  const owner = `${state.origin.runId}:${state.origin.runAttempt}:${state.origin.jobId}`;
  assert.equal(execution.owner, owner, 'Wrong isolated executor owner');
  checkImageDefinition({image: execution.imageDefinition, imageId: execution.imageId, owner});
  const cidIndex = execution.arguments.indexOf('--cidfile'); assert(cidIndex >= 0);
  assert.deepEqual(execution.arguments, isolatedRunArguments({imageId: execution.imageId,
    cidFile: execution.arguments[cidIndex + 1], owner}), 'Changed isolation configuration');
  assert.deepEqual(Object.keys(execution.costs).sort(), ['preparationMilliseconds', 'buildMilliseconds', 'executionMilliseconds', 'inspectionMilliseconds', 'closeMilliseconds'].sort());
  assert(Object.values(execution.costs).every(value => Number.isSafeInteger(value) && value >= 0));
  const result = await zip.json('results/mutations-js.json');
  assert.equal(encode(result), encode({...payload.report, sourceRestored: true, revision: state.context.candidateRevision}), 'Wrong original isolated mutation report');
  const receipt = await zip.json('receipts/mutations-js.json');
  assert.equal(encode(receipt.origin), encode(state.origin), 'Mixed isolated receipt owner');
  assert.equal(encode(receipt.inputs.inputs.runtime), encode(state.actionRuntimes['mutations-js']), 'Wrong isolated receipt runtime');
  assert.equal(receipt.execution.milliseconds, Object.values(execution.costs).reduce((sum, value) => sum + value, 0), 'Wrong isolated cost correspondence');
  return state.actionRuntimes;
}

export function runtimeForAction(action, fallback, actionRuntimes = {}) {
  assert.deepEqual(Object.keys(actionRuntimes).sort(), Object.keys(actionRuntimes).filter(id => id === 'mutations-js').sort(),
    'Unreviewed isolated runtime registration');
  if (action.id === 'mutations-js' && Object.hasOwn(actionRuntimes, action.id)) {
    assert.equal(actionRuntimes[action.id].profile, isolatedProfile, 'Wrong isolated action scope');
    assert.deepEqual(actionRuntimes[action.id].unresolved, actionRuntimes[action.id].contract ? [] : [isolatedResidual],
      'Wrong isolated contract coverage');
    if (actionRuntimes[action.id].contract) assert.equal(encode(actionRuntimes[action.id].contract), encode(isolatedContract),
      'Unreviewed isolated contract');
    return actionRuntimes[action.id];
  }
  return fallback;
}
