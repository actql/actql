import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync, rmSync, symlinkSync, existsSync} from 'node:fs';
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

test('actual staged Session dependencies load and bind the ordinary CJS through restoration', t => {
  const repository = fileURLToPath(new URL('../../',import.meta.url));
  const revision = execFileSync('git',['rev-parse','HEAD'],{cwd:repository,encoding:'utf8'}).trim();
  const tree = gitTree(repository,revision);
  const destination = mkdtempSync(join(tmpdir(),'actql-session-dependency-'));
  t.after(() => rmSync(destination,{recursive:true,force:true}));
  const staged = stageMutationSource({tree,destination});
  const sourceRoot = join(destination,'source');
  const output = execFileSync(process.execPath,['--input-type=module','-e',`
    import assert from 'node:assert/strict';
    import {join} from 'node:path';
    import {pathToFileURL} from 'node:url';
    import {createRequire} from 'node:module';
    const root = process.argv[1];
    const runtime = await import(pathToFileURL(join(root,'proofs/ci-evidence/isolated-runtime.mjs')).href);
    assert.equal(typeof runtime.checkMutationCheckout,'function');
    const load = createRequire(join(root,'_build/js/debug/test/query_integration/query_integration.whitebox_test.js'));
    const ordinary = load('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs');
    assert(Object.isFrozen(ordinary));
    assert.equal(typeof ordinary.prepareOriginalManagedRunPorts,'function');
    console.log('PASS actual staged Session declarations; no operations invoked');
  `,sourceRoot],{cwd:sourceRoot,encoding:'utf8',timeout:30000,maxBuffer:1024*1024});
  assert.match(output,/^PASS actual staged Session declarations; no operations invoked/u);
  const action = readCatalog().actions.find(value => value.id === 'mutations-js');
  const inputs = actionInputs({tree,revision,action,runtime:{profile:'source-correspondence-only',unresolved:['runtime not executed']}});
  const bridge = 'adapters/host-node/ordinary-node-resource-runtime.cjs';
  for (const path of [bridge,'proofs/relation-pipeline/proof-runner-extension.mjs']) {
    assert(staged.files.some(entry => entry.path === 'source/'+path && entry.digest === hash(tree.read(path))));
    assert(inputs.inputs.files.some(entry => entry.path === path && entry.digest === hash(tree.read(path))));
  }
  const expected = snapshotFromGit(tree);
  assert.deepEqual(snapshot(sourceRoot),expected);
  assert.equal(expected.sources[bridge],hash(tree.read(bridge)));
  const file = join(sourceRoot,bridge),original = readFileSync(file);
  try {
    writeFileSync(file,Buffer.concat([original,Buffer.from('\n// changed copied dependency\n')]));
    assert.notEqual(snapshot(sourceRoot).digest,expected.digest);
    assert.throws(() => checkMutationCheckout({root:sourceRoot,tree}),/Mutation checkout bytes differ from Git/u);
  } finally { writeFileSync(file,original); }
  assert.deepEqual(checkMutationCheckout({root:sourceRoot,tree}),expected);
});

test('changed dependency restoration bytes cannot inherit the historical isolated experiment contract', () => {
  const repository = fileURLToPath(new URL('../../',import.meta.url));
  const revision = execFileSync('git',['rev-parse','HEAD'],{cwd:repository,encoding:'utf8'}).trim();
  const digest = isolatedExperimentDigest(gitTree(repository,revision));
  assert.notEqual(digest,isolatedContract.experimentDigest);
  assert.equal(matchesIsolatedContract({experimentDigest:digest,toolchainDigest:isolatedContract.toolchainDigest,
    hostImage:isolatedContract.hostImage,platformInputs:{kernelRelease:isolatedContract.kernelRelease}}),false);
});

test('actual Git sources have the same keyed cohort, staged bytes/modes and original restoration snapshot', t => {
  const repository = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const tree = gitTree(repository, revision), destination = mkdtempSync(join(tmpdir(), 'actql-actual-source-cohort-'));
  t.after(() => rmSync(destination, {recursive: true, force: true}));
  const selected = mutationSourceInputs(tree);
  assert.deepEqual(selected.unresolved, [], 'Healthy current source must use the reviewed narrowed cohort');
  const transferManifest = 'src/platform_native/remote_transfer_journal/moon.pkg';
  assert(packageImports(tree.read(transferManifest).toString('utf8')).imports.includes('actql/actql/sha256'),
    'Transfer destination reader identity requires the literal SHA-256 dependency');
  for (const path of [transferManifest, 'src/client_local_host/moon.pkg', 'src/connectors_builtin_node/moon.pkg', 'src/execution_relation/moon.pkg', 'src/native_values_integration/moon.pkg',
    'src/platform_native/publication_store/moon.pkg', 'src/platform_native/remote_client/moon.pkg',
    'src/platform_native/remote_journal/moon.pkg', 'src/platform_native/remote_transfer_client/moon.pkg',
    'src/platform_native/signature/moon.pkg', 'src/query_integration/moon.pkg',
    'src/platform_native/remote_standard_host/moon.pkg']) {
    assert(selected.packageConfigurations.some(entry => entry.path === path &&
      entry.digest === hash(tree.read(path))), `Missing exact current configuration review: ${path}`);
    for (const dependency of packageImports(tree.read(path).toString('utf8')).imports)
      if (dependency.startsWith('actql/actql/')) assert(selected.paths.includes(
        `src/${dependency.slice('actql/actql/'.length)}/moon.pkg`), `Missing literal dependency: ${dependency}`);
  }
  const allSources = [...tree.entries.keys()].filter(path => path.startsWith('src/'));
  assert(selected.paths.length < allSources.length, 'Full-source fallback is not narrowed-cohort coverage');
  for (const directory of ['src/native_values_integration', 'src/platform_native/publication_store',
    'src/platform_native/remote_client', 'src/platform_native/signature', 'src/checkpoint_runtime',
    'src/effect_application', 'src/logical_request_scope', 'src/client_row_source_host', 'src/bounded_graph_diff',
    'src/platform_native/remote_transfer_journal', 'src/sha256',
    'src/platform_native/remote_journal', 'src/platform_native/remote_standard_host',
    'src/platform_native/retained_task_file', 'src/client_local_host', 'src/client_local_preparation',
    'src/value_admission',
    'src/client_local_run', 'src/client_host_buffers']) {
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
  const interruptionHelper = 'proofs/bounded-session/mutation-command.mjs';
  assert(inputs.inputs.files.some(entry => entry.path === interruptionHelper &&
    entry.digest === hash(tree.read(interruptionHelper))), 'Mutation helper must be a keyed input');
  assert(staged.files.some(entry => entry.path === `source/${interruptionHelper}` &&
    entry.digest === hash(tree.read(interruptionHelper))), 'Mutation helper must be physically staged');
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
  const recovery = 'src/client_local_host/preparation_request_model_recovery_js_wbtest.mbt';
  const preparation = 'src/client_local_preparation/moon.pkg';
  assert(packageImports(tree.read(preparation).toString()).imports.includes('actql/actql/value_admission'));
  for (const path of [recovery, preparation, 'src/value_admission/moon.pkg']) {
    assert(inputs.inputs.files.some(entry => entry.path === path && entry.digest === hash(tree.read(path))));
    assert.equal(expected.sources[path], hash(tree.read(path)));
  }
  const recoveryFile = join(sourceRoot, recovery), original = readFileSync(recoveryFile);
  try {
    writeFileSync(recoveryFile, Buffer.concat([original, Buffer.from('\n// unrestored current fixture\n')]));
    assert.throws(() => checkMutationCheckout({root: sourceRoot, tree}), /Mutation checkout bytes differ from Git/u);
    writeFileSync(recoveryFile, original);
    chmodSync(recoveryFile, 0o755);
    assert.throws(() => checkMutationCheckout({root: sourceRoot, tree}), /Mutation checkout mode differs from Git/u);
  } finally {
    writeFileSync(recoveryFile, original);
    chmodSync(recoveryFile, 0o644);
  }
  assert.deepEqual(checkMutationCheckout({root: sourceRoot, tree}), expected);
  for (const path of tree.entries.keys()) if (path.startsWith('src/') && !Object.hasOwn(expected.sources, path))
    assert.equal(existsSync(join(sourceRoot, path)), false);
  assert(inputs.unresolved.includes('runtime not executed'));
  t.diagnostic(JSON.stringify({revision, stagedFiles: staged.files.length, sourceFiles: keyedSources.length,
    stagedBytes: staged.bytes, scope: 'Git/filesystem correspondence; no compiler, image execution or reuse'}));
});

for (const manifest of ['src/client_local_host/moon.pkg', 'src/connectors_builtin_node/moon.pkg', 'src/native_values_integration/moon.pkg',
  'src/platform_native/filesystem/moon.pkg', 'src/platform_native/http_client/moon.pkg',
  'src/platform_native/result_access/moon.pkg', 'src/platform_native/sqlite/moon.pkg',
  'src/platform_native/publication_store/moon.pkg', 'src/platform_native/remote_client/moon.pkg',
  'src/platform_native/remote_journal/moon.pkg', 'src/platform_native/remote_transfer_client/moon.pkg',
  'src/platform_native/remote_transfer_journal/moon.pkg', 'src/platform_native/signature/moon.pkg',
  'src/query_integration/moon.pkg', 'src/platform_native/remote_standard_host/moon.pkg'])
test(`an unreviewed ${manifest} retains full-source fallback and unresolved reuse`, () => {
  const repository = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const tree = gitTree(repository, revision);
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
    costs: {preparationMilliseconds: 1, buildMilliseconds: 2, executionMilliseconds: 3, inspectionMilliseconds: 4, closeMilliseconds: 5, inputInspectionMilliseconds: 0}};
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

test('six-phase isolated cost metadata retains nonzero input inspection exactly once', async t => {
  const f = fixture(t);
  f.execution.costs.inputInspectionMilliseconds = 7;
  f.files['receipts/mutations-js.json'].execution.milliseconds += 7;
  const original = JSON.stringify(f.execution);
  assert.deepEqual(await readActionRuntimes(f), f.state.actionRuntimes);
  assert.equal(f.files['receipts/mutations-js.json'].execution.milliseconds, 22);
  assert.equal(JSON.stringify(f.execution), original);
});

test('six-phase isolated cost metadata refuses omitted extra invalid and unbound phases', async t => {
  for (const alter of [
    f => delete f.execution.costs.inputInspectionMilliseconds,
    f => f.execution.costs.unlistedMilliseconds = 0,
    f => f.execution.costs.inputInspectionMilliseconds = -1,
    f => f.execution.costs.inputInspectionMilliseconds = 0.5,
    f => f.execution.costs.inputInspectionMilliseconds = NaN,
    f => f.execution.costs.inputInspectionMilliseconds = Number.MAX_SAFE_INTEGER + 1,
    f => f.files['receipts/mutations-js.json'].execution.milliseconds -= 7,
  ]) {
    const f = fixture(t);
    f.execution.costs.inputInspectionMilliseconds = 7;
    f.files['receipts/mutations-js.json'].execution.milliseconds += 7;
    alter(f);
    await assert.rejects(readActionRuntimes(f));
  }
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
