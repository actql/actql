// Temporary single-case Linux diagnostic, never a product/release consumer.
// Current repository Store/test diagnostics use retained normal runtime bytes;
// production compiled-input correspondence is checked before any execution.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, symlinkSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {productionDependencyClosure} from './source-dependency-closure.mjs';

const [argument, ...extra] = process.argv.slice(2);
assert(argument && extra.length === 0, 'Supply the fresh diagnostic directory');
assert.equal(process.platform, 'linux');
assert.equal(process.arch, 'x64');
assert.equal(process.versions.node, '22.22.0');
const root = fileURLToPath(new URL('../', import.meta.url)), evidence = resolve(argument);
const product = '7b62c1226466601279875fae50d02eab3017490f';
const original = 'bda5c942c20472d34ff512477941106370e98298';
const oldHead = '217d8fa9b31345780bfd3f0fd99d77618a92d6fe';
const additions = ['.github/workflows/performance-matrix.yml', 'scripts/diagnose-effect-first-close.mjs'];
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', timeout: 30000,
  maxBuffer: 32 * 1024 * 1024}).trim();
const save = (name, value) => writeFileSync(join(evidence, name), JSON.stringify(value, null, 2) + '\n');
const result = {qualification: 'four-case ordered mixed-source diagnostic only; original Linux failure remains failed',
  product, runtimeSource: original, artifact: 14027925417, status: 'preparing',
  firstClose: null, testCounts: null, stage: 'source-correspondence', newCommonBuilds: 0, newNormalPackages: 0};
save('diagnostic-result.json', result);
try {
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '');
  assert.equal(git(['rev-parse', 'HEAD^']), product, 'Use only a genuine diagnostic child');
  assert.deepEqual(git(['diff', '--name-only', product, 'HEAD']).split('\n').sort(), additions);
  assert.equal(git(['show', '-s', '--format=%T', original]), git(['show', '-s', '--format=%T', oldHead]));
  const readManifest = name => git(['show', `${original}:src/${name}/moon.pkg`]);
  const entrances = ['connectors_builtin_node', 'checkpoint_runtime_node', 'client_values_host_abi'];
  const packages = [...new Set(entrances.flatMap(name => [name,
    ...productionDependencyClosure(name, readManifest)]))].sort();
  const tree = ref => new Map(git(['ls-tree', '-r', ref, '--', 'src']).split('\n').map(line => {
    const [object, path] = line.split('\t'); return [path, object];
  }));
  const oldTree = tree(original), currentTree = tree('HEAD');
  const paths = [...new Set([...oldTree.keys(), ...currentTree.keys()])].filter(path =>
    packages.includes(dirname(path).slice(4)) && (path.endsWith('/moon.pkg') ||
      path.endsWith('/pkg.generated.mbti') || path.endsWith('.mbt') &&
      !/(?:_test|_wbtest|_bbtest)\.mbt$/u.test(path))).sort();
  assert(paths.length > 0);
  for (const path of paths) assert.equal(currentTree.get(path), oldTree.get(path), `Changed compiled input: ${path}`);
  for (const path of ['moon.mod', 'toolchain.json',
    'scripts/build-local-node-assets.mjs', 'scripts/local-node-package-inputs.mjs',
    'scripts/build-run-host-core-package.mjs', 'scripts/runtime-package-inputs.mjs']) {
    assert.equal(git(['rev-parse', `HEAD:${path}`]), git(['rev-parse', `${original}:${path}`]), path);
  }
  save('source-correspondence.json', {product, runtimeSource: original, diagnosticSource: git(['rev-parse', 'HEAD']),
    entrances, packages, inputs: paths.map(path => ({path, gitObject: currentTree.get(path)})),
    qualification: 'production compiled-input correspondence only; no original raw-unminified or ordinary acceptance'});

  // Verify the ZIP, all five tars, actual CJS originals and Linux image before
  // copying only explicit, previously absent generated inputs. No old JS
  // adapter replaces the repository Store, Host, SDK or diagnostic test.
  const python = String.raw`
import hashlib, io, json, pathlib, sys, tarfile, zipfile
root, evidence, node = map(pathlib.Path, sys.argv[1:])
metadata = json.loads((evidence/'artifact-metadata.json').read_text())
assert metadata['id'] == 14027925417 and not metadata['expired']
assert metadata['workflow_run']['id'] == 43405189585
assert metadata['workflow_run']['head_sha'] == '217d8fa9b31345780bfd3f0fd99d77618a92d6fe'
body = (evidence/'artifact.zip').read_bytes()
digest = '16aac9c1d4beda4ae5be03b3183367101c7209e85ea1b715224dbb9daa435ed7'
assert len(body) == 10522785 and hashlib.sha256(body).hexdigest() == digest
assert metadata['digest'] == 'sha256:'+digest
expected = {
 'client-wire':'6333d20e85435440d839f240a2860b2322112f2aa0bbd20819493d5379257c0a',
 'sdk':'b8e3c976a56093076f46097f6105693bae0878693f454da5111849ef2b221d5c',
 'run-host-core':'46dabfe833dd1a5bb9005c30c01427b52d8ce7f604c1d189bdd9a75fe6901c07',
 'local-node':'3a656f157063f76753a72df83c93379d1283cbb32bb0bc3842df30a9f89dc504',
 'node':'0676350aa12b5beb4e4606a5fbccd39275501cdd4fd4c9a5abd7f55f7b8cc61d'}
archives = {}
with zipfile.ZipFile(io.BytesIO(body)) as z:
 assert set(z.namelist()) == {'packed-client-packages.json', *['actql-'+k+'-0.0.0-development.tgz' for k in expected]}
 manifest = json.loads(z.read('packed-client-packages.json'))
 assert manifest['revision'] == 'bda5c942c20472d34ff512477941106370e98298'
 assert manifest['tarballs'] == expected
 for name, sha in expected.items():
  b = z.read('actql-'+name+'-0.0.0-development.tgz')
  assert hashlib.sha256(b).hexdigest() == sha
  archives[name] = tarfile.open(fileobj=io.BytesIO(b))
local, host = archives['local-node'], archives['run-host-core']
for path in ['adapters/host-node/infer-trusted-node-preload.cjs','adapters/host-node/ordinary-node-resource-runtime.cjs']:
 assert local.extractfile('package/'+path).read() == (root/path).read_bytes()
assert host.extractfile('package/index.mjs').read() == (root/'packages/run-host-core/index.mjs').read_bytes()
native = json.loads(local.extractfile('package/_build/native/directory-original.json').read())
assert (native['platform'],native['arch'],native['node'],native['napi']) == ('linux','x64','22.22.0',8)
assert hashlib.sha256(node.read_bytes()).hexdigest() == native['nodeSha256']
for item in [native['source'], *native['headers']]:
 if item['path'].startswith('adapters/'):
  assert hashlib.sha256((root/item['path']).read_bytes()).hexdigest() == item['sha256']
selected = [
 (local,'package/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js','_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'),
 (host,'package/dist/checkpoint_runtime_node.js','_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js'),
 (host,'package/dist/client_values_host_abi.js','packages/run-host-core/dist/client_values_host_abi.js'),
 (host,'package/dist/checkpoint_runtime_node.js','packages/run-host-core/dist/checkpoint_runtime_node.js'),
 (local,'package/_build/native/local-files-linux-x64.node','_build/native/local-files-linux-x64.node'),
 (local,'package/_build/native/directory-original.json','_build/native/directory-original.json')]
files = []
for archive, member, destination in selected:
 item = archive.getmember(member); assert item.isfile()
 b = archive.extractfile(item).read(); path = root/destination
 assert not path.exists() and not path.is_symlink()
 path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(b); path.chmod(item.mode)
 files.append({'path':destination,'bytes':len(b),'mode':item.mode,'sha256':hashlib.sha256(b).hexdigest()})
image = next(item for item in files if item['path'] == native['binary']['path'])
assert image['sha256'] == native['binary']['sha256'] and image['bytes'] == native['binary']['bytes']
(evidence/'prepared-inputs.json').write_text(json.dumps({'manifest':manifest,'files':files,'native':'original retained Linux N-API image; no compiler invoked'},indent=2)+'\n')
`;
  result.stage = 'verified-generated-input-staging'; save('diagnostic-result.json', result);
  execFileSync('python3', ['-c', python, root, evidence, process.execPath], {timeout: 60000, stdio: 'pipe'});
  const alias = join(root, 'node_modules/@actql/client-wire');
  assert(!existsSync(alias)); mkdirSync(dirname(alias), {recursive: true});
  symlinkSync(join(root, 'packages/client-wire'), alias, 'dir');
  const testArgs = ['--test-name-pattern', "^(?:one installed Host reads and applies independent Effects|coinstalled historical read and current commit approvals survive the same Host restart|coinstalled read denial cannot authorize or suppress independent commit|public Effect dispatch waits for and obeys the Host barrier)$",
    'adapters/host-node/remote-checkpoint-host.test.mjs'];
  const focused = `import {runFocusedTests} from './scripts/test-execution.mjs';
    process.exitCode=runFocusedTests('node',${JSON.stringify(testArgs)},{expectedTests:4,timeout:150000});`;
  const config = {root, heavy: true,
    heavyResources: {memoryBytes: 3 * 1024 ** 3, diskBytes: 512 * 1024 ** 2, cpuThreads: 1},
    timeoutSeconds: 180, graceSeconds: 5,
    steps: [{name: 'Three original preceding cases + Effect barrier required FIRST close', command: process.execPath,
      args: ['--input-type=module', '-e', focused]}]};
  const guard = `import {runLocalCheck} from ${JSON.stringify(join(root, 'scripts/local-checks-guard.mjs'))};
    process.exitCode=await runLocalCheck(${JSON.stringify(config)});`;
  const env = {...process.env};
  for (const name of ['GH_TOKEN', 'GITHUB_TOKEN', 'NODE_OPTIONS', 'NODE_PATH']) delete env[name];
  result.status = 'executing'; result.stage = 'original-case'; save('diagnostic-result.json', result);
  // Preserve full output only inside this fresh runner. Upload no fixture
  // state/key or raw console, and never replace a failed first close by a retry.
  const ran = spawnSync(process.execPath, ['--input-type=module', '-e', guard],
    {cwd: root, env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  const raw = (ran.stdout ?? '') + (ran.stderr ?? '');
  writeFileSync(join(evidence, 'private-case-console.log'), raw, {mode: 0o600});
  const resources = new Set(['physicalRemovalOriginals', 'physicalRemovalAcquisitions',
    'clockObservations', 'reservedObjects', 'preparedObjects', 'preparedSchemas', 'reclaimableCustodies',
    'resultDeletions', 'metadataDeletions', 'uncommittedMetadataCleanups', 'physicalHoldingDeletions',
    'resultReaders', 'physicalHoldingReaders', 'modelStorageBindingReaders',
    'installationPublicationStorageBindingReaders', 'semanticReaders', 'physicalRecordWriters']);
  const owners = new Set(['store', 'diagnostic', 'observation', 'initialControl', 'finalize',
    'stop', 'drain', 'retire', 'checkpoint', 'journal', 'source', 'effect', 'publicationOwnership', 'ownerViews']);
  for (const line of raw.split('\n')) {
    if (line.startsWith('ACTQL_TEST_SUMMARY ')) {
      const value = JSON.parse(line.slice('ACTQL_TEST_SUMMARY '.length));
      if (value.file === undefined) result.testCounts = value.counts;
    }
    if (!line.startsWith('# {')) continue;
    const value = JSON.parse(line.slice(2));
    if (value.phase !== 'original_host_first_close_failure') continue;
    result.firstClose = {code: value.code === 'InstalledHostCleanupPending' ? value.code : 'other',
      pendingOwners: (value.pendingOwners ?? []).filter(name => owners.has(name)),
      storeResources: (value.cleanupErrors ?? []).filter(item => item.owner === 'store' &&
        item.code === 'PublicationStoreCleanupPending').flatMap(item =>
        (item.storeResources ?? []).filter(item => resources.has(item.resource) &&
          Number.isSafeInteger(item.count) && item.count > 0))};
  }
  result.exitCode = ran.status; result.signal = ran.signal;
  result.status = ran.status === 0 ? 'case-passed-original-linux-failure-not-repaired'
    : result.firstClose ? 'original-first-close-refused' : 'failed-before-first-close-observation';
  save('diagnostic-result.json', result);
  console.log(JSON.stringify(result));
  process.exitCode = ran.status ?? 1;
} catch (error) {
  result.status = 'preparation-failed';
  result.errorCode = /^[A-Za-z0-9_]+$/u.test(error?.code ?? '') ? error.code : 'DiagnosticPreparationFailed';
  save('diagnostic-result.json', result);
  console.error(JSON.stringify(result));
  process.exitCode = 1;
}
