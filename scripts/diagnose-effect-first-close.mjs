// Temporary selected-source Linux diagnosis, never a product/release consumer.
// Compile the actual raw JS entrances once. Reuse only the source-checked Linux
// N-API image, never an older/minified Common or provider/bridge payload.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, realpathSync, symlinkSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const [argument, ...extra] = process.argv.slice(2);
assert(argument && extra.length === 0, 'Supply the fresh diagnostic directory');
assert.equal(process.platform, 'linux');
assert.equal(process.arch, 'x64');
assert.equal(process.versions.node, '22.22.0');
const root = fileURLToPath(new URL('../', import.meta.url)), evidence = resolve(argument);
const product = '56919c87f90df90002b7c27d8c4a6165d760c880';
const original = 'bda5c942c20472d34ff512477941106370e98298';
const additions = ['.github/workflows/performance-matrix.yml', 'scripts/diagnose-effect-first-close.mjs'];
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', timeout: 30000,
  maxBuffer: 32 * 1024 * 1024}).trim();
const save = (name, value) => writeFileSync(join(evidence, name), JSON.stringify(value, null, 2) + '\n');
const result = {qualification: 'faithful current raw-JS-source one-case diagnosis; not normal/release acceptance',
  product, runtimeSource: product, nativeImageSource: original, artifact: 14027925417, status: 'preparing',
  firstClose: null, testCounts: null, stage: 'source-identity', newCommonBuilds: 0, newNormalPackages: 0};
save('diagnostic-result.json', result);
try {
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '');
  assert.equal(git(['rev-parse', 'HEAD^']), product, 'Use only a genuine diagnostic child');
  assert.deepEqual(git(['diff', '--name-only', product, 'HEAD']).split('\n').sort(), additions);
  const targets = ['connectors_builtin_node', 'checkpoint_runtime_node', 'client_values_host_abi',
    'connectors/duckdb/host_node', 'retained_host_bridge', 'process_host_bridge'];
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const env = {...process.env};
  for (const name of ['GH_TOKEN', 'GITHUB_TOKEN', 'NODE_OPTIONS', 'NODE_PATH']) delete env[name];
  // Verify the complete old ZIP but retain ONLY its exact Linux N-API image
  // and provenance after checking the actual current C/header/Node bytes.
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
native = json.loads(local.extractfile('package/_build/native/directory-original.json').read())
assert (native['platform'],native['arch'],native['node'],native['napi']) == ('linux','x64','22.22.0',8)
assert hashlib.sha256(node.read_bytes()).hexdigest() == native['nodeSha256']
for item in [native['source'], *native['headers']]:
 if item['path'].startswith('adapters/'):
  assert hashlib.sha256((root/item['path']).read_bytes()).hexdigest() == item['sha256']
selected = [
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
  if (existsSync(alias)) assert.equal(realpathSync(alias), realpathSync(join(root, 'packages/client-wire')));
  else {mkdirSync(dirname(alias), {recursive: true}); symlinkSync(join(root, 'packages/client-wire'), alias, 'dir');}
  // Exact existing build inputs, without the normal Local/Workers/package fan-out.
  const abi = `import {deferredFunctionRuntime} from './scripts/deferred-function-runtime.mjs';
    import {mkdirSync,writeFileSync} from 'node:fs';
    mkdirSync('packages/run-host-core/dist',{recursive:true});
    for(const name of ['client_values_host_abi','checkpoint_runtime_node'])
      writeFileSync('packages/run-host-core/dist/'+name+'.js',deferredFunctionRuntime(
        '_build/js/release/build/'+name+'/'+name+'.js',{minify:true}));`;
  const buildConfig = {root, heavy: true,
    heavyResources: {memoryBytes: 6 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 2},
    timeoutSeconds: 900, graceSeconds: 10, steps: [
      {name: 'ONE selected same-source JS release build',command:'moon',
        args:['build','--frozen','--target','js','--release',...targets.map(name=>'src/'+name)]},
      {name: 'Only the two existing ABI projections through their original generator',command:process.execPath,
        args:['--input-type=module','-e',abi]}]};
  const buildGuard = `import {runLocalCheck} from ${JSON.stringify(join(root,'scripts/local-checks-guard.mjs'))};
    process.exitCode=await runLocalCheck(${JSON.stringify(buildConfig)});`;
  result.stage='selected-raw-js-build'; save('diagnostic-result.json',result);
  const built=spawnSync(process.execPath,['--input-type=module','-e',buildGuard],
    {cwd:root,env,encoding:'utf8',maxBuffer:64*1024*1024});
  writeFileSync(join(evidence,'private-build-console.log'),(built.stdout??'')+(built.stderr??''),{mode:0o600});
  result.buildExitCode=built.status; result.buildSignal=built.signal;
  result.newCommonBuilds=built.status===0 ? 1 : null;
  if(built.status!==0 || built.signal!==null) {
    result.status='selected-build-not-completed';save('diagnostic-result.json',result);
    console.error(JSON.stringify(result));process.exit(built.status||1);
  }
  const generated=[...targets.map(name=>'_build/js/release/build/'+name+'/'+name.split('/').at(-1)+'.js'),
    'packages/run-host-core/dist/client_values_host_abi.js','packages/run-host-core/dist/checkpoint_runtime_node.js'];
  save('source-correspondence.json',{source:product,diagnosticSource:git(['rev-parse','HEAD']),targets,
    compiler:execFileSync('moon',['version','--all'],{cwd:root,env,encoding:'utf8'}).trim(),
    toolchainSHA256:hash(readFileSync(join(root,'toolchain.json'))),
    generated:generated.map(path=>({path,bytes:readFileSync(join(root,path)).length,
      sha256:hash(readFileSync(join(root,path)))})),
    ffi:'Current-source CJS originals and inline JS, compiled by current pinned source. Original N-API manifest checks every first-party C/header and Node binary before reuse.'});
  const testArgs = ['--test-name-pattern', '^one installed Host reads and applies independent Effects$',
    'adapters/host-node/remote-checkpoint-host.test.mjs'];
  const focused = `import {runFocusedTests} from './scripts/test-execution.mjs';
    process.exitCode=runFocusedTests('node',${JSON.stringify(testArgs)},{expectedTests:1,timeout:150000});`;
  const config = {root, heavy: true,
    heavyResources: {memoryBytes: 3 * 1024 ** 3, diskBytes: 512 * 1024 ** 2, cpuThreads: 1},
    timeoutSeconds: 180, graceSeconds: 5,
    steps: [{name: 'ONLY actual failed two-member Source/Effect case with required FIRST close', command: process.execPath,
      args: ['--input-type=module', '-e', focused]}]};
  const guard = `import {runLocalCheck} from ${JSON.stringify(join(root, 'scripts/local-checks-guard.mjs'))};
    process.exitCode=await runLocalCheck(${JSON.stringify(config)});`;
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
  result.status = ran.status === 0 ? 'case-passed-original-normal-failure-not-repaired'
    : result.firstClose ? 'original-first-close-refused' : 'failed-without-first-close-refusal-observation';
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
