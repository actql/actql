import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync, symlinkSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {hash, gitTree, actionInputs, mutationSourceInputs, packageImports} from './inputs.mjs';
import {readCatalog} from './actions.mjs';
import {mutationIds} from './receipts.mjs';
import {mutationContracts} from './mutation-inventory.mjs';
import {stageMutationSource, isolatedSourceFiles, mutationSnapshotExtras, isolatedEnvironment, scratchDockerfile, isolatedRunArguments} from './isolation.mjs';
import {observeImageRoot, imageRuntime, checkIsolatedInputs, checkIsolatedResult, snapshotFromGit, checkMutationCheckout, runtimeForAction, readActionRuntimes} from './isolated-runtime.mjs';
import {staticElf} from './isolated-execution.mjs';
import {isolatedContract, matchesIsolatedContract, isolatedExperimentDigest, isolatedExperimentPaths} from './isolated-contract.mjs';
import {snapshot} from '../bounded-session/evidence.mjs';

test('actual Git sources have the same keyed cohort, staged bytes/modes and original restoration snapshot', t => {
  const repository = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const tree = gitTree(repository, revision), destination = mkdtempSync(join(tmpdir(), 'actql-actual-source-cohort-'));
  t.after(() => rmSync(destination, {recursive: true, force: true}));
  const selected = mutationSourceInputs(tree);
  assert.deepEqual(selected.unresolved, [], 'Healthy current source must use the reviewed narrowed cohort');
  const journalManifest = 'src/platform_native/remote_transfer_journal/moon.pkg';
  assert(packageImports(tree.read(journalManifest).toString('utf8')).imports.includes('actql/actql/sha256'),
    'Transfer destination reader identity requires the literal SHA-256 dependency');
  assert(selected.packageConfigurations.some(entry => entry.path === journalManifest &&
    entry.digest === hash(tree.read(journalManifest))), 'Transfer journal must have an exact configuration review');
  const allSources = [...tree.entries.keys()].filter(path => path.startsWith('src/'));
  assert(selected.paths.length < allSources.length, 'Full-source fallback is not narrowed-cohort coverage');
  for (const directory of ['src/client_row_source_host', 'src/bounded_graph_diff',
    'src/platform_native/remote_transfer_journal', 'src/sha256']) {
    const immediateMembers = allSources.filter(path => path.startsWith(`${directory}/`) &&
      !path.slice(directory.length + 1).includes('/')).sort();
    assert(immediateMembers.includes(`${directory}/moon.pkg`));
    assert(immediateMembers.includes(`${directory}/pkg.generated.mbti`));
    assert(immediateMembers.some(path => path.endsWith('_wbtest.mbt')));
    assert.deepEqual(selected.directories.find(entry => entry.path === `${directory}/*`)?.members, immediateMembers);
    for (const path of immediateMembers) assert(selected.paths.includes(path), `Missing integrated package member: ${path}`);
  }
  const staged = stageMutationSource({tree, destination});
  const action = readCatalog().actions.find(value => value.id === 'mutations-js');
  // This verifies physical source correspondence only, never a runtime claim.
  const inputs = actionInputs({tree, revision, action,
    runtime: {profile: 'source-correspondence-only', unresolved: ['runtime not executed']}});
  const keyedSources = inputs.inputs.files.filter(entry => entry.path.startsWith('src/')).map(entry => entry.path).sort();
  assert.deepEqual(staged.files.filter(entry => entry.path.startsWith('source/src/'))
    .map(entry => entry.path.slice('source/'.length)).sort(), keyedSources);
  const actualFiles = observeImageRoot(destination).entries.filter(entry => entry.kind === 'file');
  assert.deepEqual(actualFiles.map(entry => entry.path).sort(), staged.files.map(entry => entry.path).sort());
  const byPath = new Map(actualFiles.map(entry => [entry.path, entry]));
  for (const entry of staged.files) {
    const actual = byPath.get(entry.path);
    assert.deepEqual({mode: actual.mode, bytes: actual.bytes, digest: actual.digest},
      {mode: entry.mode, bytes: entry.bytes, digest: entry.digest});
  }
  const sourceRoot = join(destination, 'source'), expected = snapshotFromGit(tree);
  assert.deepEqual(snapshot(sourceRoot), expected);
  assert.deepEqual(checkMutationCheckout({root: sourceRoot, tree}), expected);
  for (const path of tree.entries.keys()) if (path.startsWith('src/') && !Object.hasOwn(expected.sources, path))
    assert.equal(existsSync(join(sourceRoot, path)), false);
  assert(inputs.unresolved.includes('runtime not executed'));
  t.diagnostic(JSON.stringify({revision, stagedFiles: staged.files.length, sourceFiles: keyedSources.length,
    stagedBytes: staged.bytes, scope: 'Git/filesystem correspondence; no compiler, image execution or reuse'}));
});

test('an unreviewed Transfer journal manifest retains full-source fallback and unresolved reuse', () => {
  const repository = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const tree = gitTree(repository, revision);
  const manifest = 'src/platform_native/remote_transfer_journal/moon.pkg';
  const changedTree = {...tree, read(path) {
    const original = tree.read(path);
    return path === manifest ? Buffer.concat([original, Buffer.from('\n// Unreviewed configuration revision.\n')]) : original;
  }};
  const selected = mutationSourceInputs(changedTree);
  assert(selected.unresolved.includes(`Unreviewed package configuration: ${manifest}`));
  assert(selected.directories.some(entry => entry.path === 'src/**'));
  for (const path of tree.entries.keys()) if (path.startsWith('src/')) assert(selected.paths.includes(path));
});

function fixture(t, scoped = false) {
  const root = mkdtempSync(join(tmpdir(), 'actql-image-correspondence-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const bodies = new Map([...isolatedSourceFiles, ...mutationSnapshotExtras, ...isolatedExperimentPaths,
    'proofs/bounded-session/mutations.mjs', 'proofs/bounded-session/evidence.mjs', 'src/example/moon.pkg', 'src/example/source.mbt']
    .map(path => [path, Buffer.from(path)]));
  if (scoped) {
    for (const path of ['src/bounded_execution', 'src/connectors/local', 'src/query_integration'])
      bodies.set(`${path}/moon.pkg`, Buffer.from('import { "actql/actql/example" }'));
    bodies.set('src/example/moon.pkg', Buffer.from(''));
    bodies.set('src/unrelated/value.mbt', Buffer.from('outside physical scope'));
  }
  const tree = {entries: new Map([...bodies.keys()].map(path => [path, {mode: '100644', kind: 'blob'}])), read: path => bodies.get(path)};
  stageMutationSource({tree, destination: root});
  const executables = ['runtime/node', ...['moon', 'moonc', 'moonrun'].map(name => `runtime/moonbit/bin/${name}`), 'bin/sh'];
  for (const path of [...executables, 'lib/libstdc++.so.6', 'runtime/moonbit/lib/core/README.md']) {
    mkdirSync(dirname(join(root, path)), {recursive: true}); writeFileSync(join(root, path), path);
    chmodSync(join(root, path), executables.includes(path) ? 0o755 : 0o644);
  }
  mkdirSync(join(root, 'runtime/moonbit/lib/core/lazy_list'));
  symlinkSync('../README.md', join(root, 'runtime/moonbit/lib/core/lazy_list/README.md'));
  const manifest = {version: 'actql-isolated-mutation-inputs/0.1', environment: isolatedEnvironment,
    dockerfile: scratchDockerfile(), root: observeImageRoot(root),
    platformInputs: {platform: 'linux', architecture: 'x64', kernelRelease: 'fixture'},
    loaderObservations: executables.map(executable => ({executable, digest: hash(executable), static: false, paths: ['/lib/libstdc++.so.6']})),
    sourceSnapshotDigest: snapshotFromGit(tree).digest, experimentDigest: isolatedExperimentDigest(tree),
    toolchainDigest: hash(tree.read('toolchain.json')), hostImage: 'fixture'};
  const runtime = imageRuntime(manifest), before = snapshotFromGit(tree);
  const report = {source: before, results: mutationIds.map(id => ({id, ...mutationContracts[id], killed: true, target: 'js', failureCount: 1}))};
  const payload = {version: 'actql-isolated-mutation-observation/0.1', root: manifest.root,
    platformInputs: manifest.platformInputs, environment: isolatedEnvironment, readOnlyConfirmed: true, shellStartupConfirmed: true, restored: true, report,
    logs: Object.fromEntries(mutationIds.map(id => [id, 'Total tests: 1, passed: 0, failed: 1.\n']))};
  const state = {context: {candidateRevision: 'a'.repeat(40)}, origin: {runId: 1, runAttempt: 2, jobId: 3}, actionRuntimes: {'mutations-js': runtime}};
  const imageId = `sha256:${'b'.repeat(64)}`, owner = '1:2:3';
  const execution = {imageId, owner, imageDefinition: {Id: imageId, Os: 'linux', Architecture: 'amd64', Config: {
    Labels: {'org.actql.ci.owner': owner}, Env: Object.entries(isolatedEnvironment).map(([name, value]) => `${name}=${value}`),
    User: '1000:1000', WorkingDir: '/workspace', Entrypoint: ['/runtime/node', '/source/proofs/ci-evidence/isolated-mutations.mjs']}},
    arguments: isolatedRunArguments({imageId, owner, cidFile: '/owned/container.id'}),
    costs: {preparationMilliseconds: 1, buildMilliseconds: 2, executionMilliseconds: 3, inspectionMilliseconds: 4, closeMilliseconds: 5}};
  const files = {'isolated-inputs.json': manifest, 'isolated-observation.json': payload, 'isolated-execution.json': execution,
    'receipts/mutations-js.json': {origin: state.origin, inputs: {inputs: {runtime}}, execution: {milliseconds: 15}},
    'results/mutations-js.json': {...report, sourceRestored: true, revision: state.context.candidateRevision}};
  return {root, tree, manifest, runtime, before, payload, state, execution, files, zip: {json: async path => files[path]}};
}

test('the child snapshot and independent Git snapshot bind the same physically narrowed cohort', t => {
  const f = fixture(t, true);
  assert.equal(existsSync(join(f.root, 'source/src/unrelated/value.mbt')), false);
  assert.deepEqual(snapshot(join(f.root, 'source')), f.before);
  assert.deepEqual(checkMutationCheckout({root: join(f.root, 'source'), tree: f.tree}), f.before);
  assert(checkIsolatedInputs(f)); assert(checkIsolatedResult(f));
  mkdirSync(join(f.root, 'source/src/unrelated')); writeFileSync(join(f.root, 'source/src/unrelated/value.mbt'), 'unexpected image input');
  const manifest = {...f.manifest, root: observeImageRoot(f.root)};
  assert.throws(() => checkIsolatedInputs({runtime: imageRuntime(manifest), manifest, tree: f.tree}), /source directory|source inputs/u);
  const input = join(f.root, 'source/src/example/source.mbt');
  writeFileSync(input, 'unrestored selected source');
  assert.throws(() => checkMutationCheckout({root: join(f.root, 'source'), tree: f.tree}), /bytes differ/u);
});

test('selected host source modes and links cannot substitute for actual Git inputs', t => {
  const f = fixture(t, true), input = join(f.root, 'source/src/example/source.mbt');
  chmodSync(input, 0o755);
  assert.throws(() => checkMutationCheckout({root: join(f.root, 'source'), tree: f.tree}), /mode differs/u);
  rmSync(input); symlinkSync('moon.pkg', input);
  assert.throws(() => checkMutationCheckout({root: join(f.root, 'source'), tree: f.tree}), /Nonregular/u);
});

test('actual staged bytes, internal link targets, Git source and original assertion logs correspond', async t => {
  const f = fixture(t);
  assert(checkIsolatedInputs(f)); assert(checkIsolatedResult(f));
  assert.deepEqual(await readActionRuntimes(f), f.state.actionRuntimes);
  const host = {profile: 'host', unresolved: ['host loader remains open']};
  assert.equal(runtimeForAction({id: 'session-js'}, host, f.state.actionRuntimes), host);
  assert.equal(runtimeForAction({id: 'mutations-js'}, host, f.state.actionRuntimes), f.runtime);
});

test('missing source, false directory membership, changed environment/definition and missing loader inputs reject', t => {
  const f = fixture(t);
  for (const alter of [
    manifest => manifest.root.entries.find(entry => entry.path === 'source/src/example/source.mbt').digest = 'f'.repeat(64),
    manifest => manifest.root.entries.find(entry => entry.path === 'source/src/example').members = [],
    manifest => manifest.root.entries = manifest.root.entries.filter(entry => entry.path !== 'runtime/node'),
    manifest => manifest.root.entries = manifest.root.entries.filter(entry => entry.path !== 'bin/sh'),
    manifest => manifest.loaderObservations.pop(),
    manifest => manifest.loaderObservations.at(-1).digest = 'f'.repeat(64),
    manifest => manifest.root.links[0].destination = 'absent',
    manifest => manifest.environment = {...manifest.environment, SECRET: 'must not enter'},
    manifest => manifest.dockerfile += 'ENV UNREVIEWED=true\n',
    manifest => manifest.loaderObservations[0].paths = ['/outside/unbound.so'],
    manifest => manifest.root.unresolved.push('runtime: byte limit: needed-file'),
  ]) {
    const manifest = structuredClone(f.manifest); alter(manifest);
    assert.throws(() => checkIsolatedInputs({runtime: imageRuntime(manifest), manifest, tree: f.tree}));
  }
  assert.throws(() => checkIsolatedInputs({...f, runtime: {...f.runtime, unresolved: []}}));
});

test('independent image validation refuses reintroduced installed core build metadata', t => {
  const f = fixture(t);
  for (const path of ['lib/core/_build/.moon_db', ...['js', 'wasm', 'native']
    .map(target => `lib/core/_build/${target}/release/bundle/all_pkgs.json`)]) {
    const manifest = structuredClone(f.manifest);
    manifest.root.entries.push({path: `runtime/moonbit/${path}`, kind: 'file', mode: 0o644,
      bytes: 1, digest: hash('owner-dependent metadata')});
    assert.throws(() => checkIsolatedInputs({runtime: imageRuntime(manifest), manifest, tree: f.tree}),
      /Installed core build metadata must be absent/u);
  }
});

test('restoration, runtime/kernel mismatch, missing mutation logs and compiler-only failure cannot seal success', t => {
  const f = fixture(t);
  for (const alter of [
    payload => payload.restored = false,
    payload => payload.readOnlyConfirmed = false,
    payload => payload.shellStartupConfirmed = false,
    payload => payload.platformInputs.kernelRelease = 'changed',
    payload => payload.root.entries[0].mode = 0,
    payload => payload.report.source.digest = 'f'.repeat(64),
    payload => payload.report.results[0].suite = 'src/unrelated',
    payload => delete payload.logs[mutationIds[0]],
    payload => payload.logs[mutationIds[0]] = 'Compiler failed',
    payload => payload.logs[mutationIds[0]] += 'Error: [1000] compile failed\n',
  ]) {
    const payload = structuredClone(f.payload); alter(payload); assert.throws(() => checkIsolatedResult({...f, payload}));
  }
});

test('the actual archive entrance rejects another owner, widened scope or host mount', async t => {
  for (const alter of [
    f => f.execution.owner = '1:2:4',
    f => f.execution.arguments.splice(1, 0, '--mount=host'),
    f => f.state.actionRuntimes['session-js'] = f.runtime,
    f => f.files['results/mutations-js.json'].revision = 'c'.repeat(40),
    f => f.files['receipts/mutations-js.json'].execution.milliseconds = 0,
  ]) {
    const f = fixture(t); alter(f); await assert.rejects(readActionRuntimes(f));
  }
  const f = fixture(t);
  assert.throws(() => runtimeForAction({id: 'mutations-js'}, {}, {'mutations-js': {...f.runtime, unresolved: []}}));
});

test('static classification reads ELF program headers rather than trusting an ldd label', () => {
  const elf = Buffer.alloc(120); Buffer.from([0x7f, 69, 76, 70, 2, 1, 1]).copy(elf);
  elf.writeUInt16LE(62, 18); elf.writeBigUInt64LE(64n, 32); elf.writeUInt16LE(56, 54); elf.writeUInt16LE(1, 56);
  elf.writeUInt32LE(1, 64); assert(staticElf(elf));
  for (const type of [2, 3]) { const changed = Buffer.from(elf); changed.writeUInt32LE(type, 64); assert.equal(staticElf(changed), false); }
  assert.equal(staticElf(elf.subarray(0, 100)), false); assert.equal(staticElf(Buffer.from('statically linked')), false);
});

test('conditional source/environment contract cannot be widened or copied onto independent image inputs', t => {
  const f = fixture(t);
  assert.equal(matchesIsolatedContract(f.manifest), false);
  const purported = {...f.manifest, experimentDigest: isolatedContract.experimentDigest,
    toolchainDigest: isolatedContract.toolchainDigest, hostImage: isolatedContract.hostImage,
    platformInputs: {...f.manifest.platformInputs, kernelRelease: isolatedContract.kernelRelease}};
  assert(matchesIsolatedContract(purported));
  const runtime = imageRuntime(purported);
  assert.throws(() => checkIsolatedInputs({runtime, manifest: purported, tree: f.tree}), /finite experiment/u);
  for (const changed of [
    {...purported, experimentDigest: 'f'.repeat(64)},
    {...purported, toolchainDigest: 'f'.repeat(64)},
    {...purported, hostImage: 'unknown'},
    {...purported, platformInputs: {...purported.platformInputs, kernelRelease: 'unknown'}},
  ]) {
    assert.equal(matchesIsolatedContract(changed), false);
    assert.equal(imageRuntime(changed).unresolved.length, 1);
  }
});
