// Build the existing selected command for its actual test platform.
// The producer owns source/allocator/header checks; raw unselected executables
// are never a fallback for an install/activate acceptance path.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync, realpathSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {preparedNativeCommand, preparedNativeComponents, preparedNativeHttpReceipt,
  verifyNativeHttpPreparation, receiveNativeCompiledCommand} from './native-preparation-originals.mjs';

export function prepareNativeRuntimeBundle(repository, destination, options) {
  return prepareNativeCommand(repository, destination, 'native_runtime_bundle', options);
}

export function prepareNativeResidentSite(repository, destination, options) {
  return prepareNativeCommand(repository, destination, 'native_remote_resident_site', options);
}

function prepareNativeCommand(repository, destination, entry, {
  execute = execFileSync, platform = process.platform, arch = process.arch,
  moonHome = process.env.MOON_HOME, seconds = 600,
  preparation = process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
  compiledInput,
} = {}) {
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 1800);
  const target = platform === 'darwin' && arch === 'arm64' ? 'darwin-arm64'
    : platform === 'linux' && arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No selected bundle command recipe for this actual platform');
  const entryPath = 'src/cmd/' + entry;
  assert(typeof moonHome === 'string' && moonHome.length > 0,
    'The existing pinned Moon toolchain is required');
  repository = realpathSync(repository);
  destination = join(realpathSync(dirname(resolve(destination))), basename(destination));
  const run = (command, args) => execute(command, args, {cwd: repository,
    encoding: 'utf8', timeout: (seconds + 30) * 1000, maxBuffer: 8 * 1024 ** 2});
  const source = run('git', ['rev-parse', 'HEAD']).trim();
  assert.match(source, /^[0-9a-f]{40}$/u);
  assert.equal(run('git', ['status', '--porcelain']), '', 'Clean fixed bundle build Source required');
  const clang = realpathSync(platform === 'darwin' ? run('xcrun', ['--find', 'clang']).trim()
    : run('sh', ['-c', 'command -v clang']).trim());
  const sdk = platform === 'darwin' ? realpathSync(run('xcrun', ['--show-sdk-path']).trim()) : undefined;
  if (compiledInput !== undefined) {
    assert(preparation === undefined || preparation === null, 'One explicit preparation mode required');
    const binary = receiveNativeCompiledCommand(compiledInput, destination, entry,
      {source,target,clang,sdk,moon_home:realpathSync(moonHome),repository}, {seconds});
    assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
    assert.equal(run('git', ['status', '--porcelain']), '');
    return binary;
  }
  if (preparation !== undefined && preparation !== null) {
    const prepared = preparedNativeCommand(preparation, entry, {source,target,clang,sdk,
      moon_home:realpathSync(moonHome),repository});
    if (prepared.kind === 'received') {
      assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
      assert.equal(run('git', ['status', '--porcelain']), '');
      return prepared.binary;
    }
    destination = prepared;
  } else run('python3', [join(repository, 'scripts/produce-native-remote-scoped-runtime.py'),
    '--source', source, '--moon-home', realpathSync(moonHome), '--clang', clang,
    ...(sdk === undefined ? [] : ['--sdk', sdk]), '--target', target,
    '--destination', destination, '--seconds', String(seconds),
    '--entry', entryPath]);
  const receiptPath = join(destination, 'build.json');
  const receipt = JSON.parse(readFileSync(receiptPath, 'utf8'));
  assert.equal(receipt.source, source);assert.equal(receipt.entry, entryPath);
  assert.equal(receipt.target, target);assert.equal(receipt.plan_only, false);
  assert.equal(receipt.moon_build_exit, 0);assert.equal(receipt.providers, 1);
  const binary = join(destination, 'emission/native/release/build/cmd', entry, entry + '.exe');
  assert.equal(receipt.executable.path, binary);
  const original = lstatSync(binary);assert(original.isFile() && !original.isSymbolicLink() && (original.mode & 0o111) !== 0);
  const bytes = readFileSync(binary);
  assert.equal(bytes.length, receipt.executable.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), receipt.executable.sha256);
  assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
  assert.equal(run('git', ['status', '--porcelain']), '');
  const after = lstatSync(binary);
  for (const key of ['dev','ino','size','mode','mtimeMs','ctimeMs']) assert.equal(after[key],original[key]);
  return binary;
}

export function prepareNativeResidentHttpLibrary({
  receiptPath = process.env.ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT,
  platform = process.platform, arch = process.arch, execute = execFileSync,
  preparation = process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
} = {}) {
  const target = platform === 'darwin' && arch === 'arm64' ? 'darwin-arm64'
    : platform === 'linux' && arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No selected Resident HTTP component for this actual platform');
  assert(typeof receiptPath === 'string' && receiptPath.length > 0,
    'The original owned HTTP component receipt is required; stock libcurl is not a fallback');
  if(preparation!==undefined && preparation!==null) {
    const repository=realpathSync(fileURLToPath(new URL('../',import.meta.url)));
    const run=(command,args)=>execute(command,args,{cwd:repository,encoding:'utf8',timeout:60000});
    const source=run('git',['rev-parse','HEAD']).trim();
    assert.equal(run('git',['status','--porcelain']),'');
    const clang=realpathSync(platform==='darwin'?run('xcrun',['--find','clang']).trim()
      :run('sh',['-c','command -v clang']).trim());
    const sdk=platform==='darwin'?realpathSync(run('xcrun',['--show-sdk-path']).trim()):undefined;
    assert.equal(receiptPath,preparedNativeHttpReceipt(preparation,{source,target,clang,sdk}));
  }
  const receiptFile = lstatSync(receiptPath,{bigint:true});
  assert(receiptFile.isFile() && !receiptFile.isSymbolicLink() && receiptFile.size <= 4n * 1024n ** 2n);
  const receipt = JSON.parse(readFileSync(receiptPath, 'utf8'));
  const recipeBytes = readFileSync(new URL('./native-http-component-source.json', import.meta.url));
  const recipe = JSON.parse(recipeBytes);
  assert.match(receipt.source, /^[0-9a-f]{40}$/u);
  assert.equal(receipt.target, target);
  if (platform === 'darwin') {
    const current = execute('/usr/bin/sw_vers', ['-productVersion'],
      {encoding: 'utf8', timeout: 10000, maxBuffer: 4096}).trim();
    assert.match(current, /^\d+\.\d+(?:\.\d+)?$/u);
    assert(['11.0', '26.0'].includes(receipt.minimumMacOS), 'Selected HTTP macOS deployment profile required');
    const version = value => {
      const parts = value.split('.').map(Number).concat([0,0]).slice(0,3);
      assert(parts.every(Number.isSafeInteger), 'Bounded actual macOS version required');
      return parts;
    };
    const actual = version(current), minimum = version(receipt.minimumMacOS);
    const difference = minimum.map((value,index) => value - actual[index]).find(value => value !== 0) ?? 0;
    assert(difference <= 0, 'HTTP component deployment requirement exceeds this actual macOS');
  } else assert.equal(receipt.minimumMacOS, null);
  assert.equal(receipt.recipe_sha256, createHash('sha256').update(recipeBytes).digest('hex'));
  assert.deepEqual(receipt.upstream, recipe.upstream);
  assert.equal(receipt.loaded, 0); assert.equal(receipt.initialized, 0);
  assert.equal(receipt.installed_supplier, false);
  for (const name of ['component_tls_lifetime.c', 'component_tls_lifetime.h']) {
    const relative = 'src/platform_native/http_client/' + name;
    const originals = receipt.inputs.filter(item => item.path.endsWith('/' + relative));
    assert.equal(originals.length, 1, 'Exact HTTP TLS implementation original required');
    const sourceBytes = readFileSync(new URL('../' + relative, import.meta.url));
    assert.equal(originals[0].bytes, sourceBytes.length);
    assert.equal(originals[0].sha256, createHash('sha256').update(sourceBytes).digest('hex'));
  }
  // The existing producer checks the same-image allocator/TLS v3 export when
  // this original receipt is present. This DATA is not a Read or load grant.
  assert(receipt.ownedOpenSSLReceipt && typeof receipt.ownedOpenSSLReceipt.path === 'string',
    'HTTP component lacks its original owned TLS construction');
  const item = receipt.library;
  const before = lstatSync(item.path,{bigint:true});
  assert(before.isFile() && !before.isSymbolicLink() && before.size > 0n && before.size <= 64n * 1024n ** 2n);
  for (const key of ['dev', 'ino', 'mode']) {
    if(typeof item[key]==='string')assert.match(item[key],/^(?:0|[1-9][0-9]{0,19})$/u);
    else assert(Number.isSafeInteger(item[key]) && item[key]>=0);
    const expected=BigInt(item[key]);assert(expected<=0xffffffffffffffffn);
    assert.equal(before[key],expected);
  }
  const bytes = readFileSync(item.path);
  assert.equal(bytes.length, item.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
  for (const [path, original] of [[item.path, before], [receiptPath, receiptFile]]) {
    const after = lstatSync(path,{bigint:true});
    for (const key of ['dev','ino','size','mode','mtimeNs','ctimeNs']) assert.equal(after[key], original[key]);
  }
  return item.path;
}

export function prepareNativeResidentHttpComponent(repository,destination,{
  execute=execFileSync,platform=process.platform,arch=process.arch,seconds=900,
  curlArchive=process.env.ACTQL_TEST_NATIVE_HTTP_CURL_ARCHIVE,
  curlSignature=process.env.ACTQL_TEST_NATIVE_HTTP_CURL_SIGNATURE,
  releaseKey=process.env.ACTQL_TEST_NATIVE_HTTP_RELEASE_KEY,
  tlsArchive=process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE,
  tlsJobs=1,
}={}) {
  assert(Number.isSafeInteger(seconds) && seconds>0 && seconds<=1800);
  assert(Number.isSafeInteger(tlsJobs) && [1,2].includes(tlsJobs));
  const target=platform==='darwin' && arch==='arm64'?'darwin-arm64'
    :platform==='linux' && arch==='x64'?'linux-x64':undefined;
  assert(target,'No selected Resident HTTP preparation target');
  repository=realpathSync(repository);
  destination=join(realpathSync(dirname(resolve(destination))),basename(destination));
  const run=(command,args)=>execute(command,args,{cwd:repository,encoding:'utf8',
    timeout:(seconds+30)*1000,maxBuffer:8*1024**2});
  const source=run('git',['rev-parse','HEAD']).trim();assert.match(source,/^[0-9a-f]{40}$/u);
  assert.equal(run('git',['status','--porcelain']),'');
  const clang=realpathSync(platform==='darwin'?run('xcrun',['--find','clang']).trim()
    :run('sh',['-c','command -v clang']).trim());
  const sdk=platform==='darwin'?realpathSync(run('xcrun',['--show-sdk-path']).trim()):undefined;
  const tools=['make','perl','gpg','gpgv'].flatMap(name=>['--'+name,
    realpathSync(run('sh',['-c','command -v '+name]).trim())]);
  run('python3',[join(repository,'scripts/prepare-native-resident-http-component.py'),
    '--source',source,'--target',target,'--clang',clang,
    ...(sdk===undefined?[]:['--sdk',sdk]),...tools,'--destination',destination,'--seconds',String(seconds),
    '--tls-jobs',String(tlsJobs),
    ...[['curl-archive',curlArchive],['curl-signature',curlSignature],['release-key',releaseKey],
      ['tls-archive',tlsArchive]].flatMap(([name,path])=>path===undefined?[]:['--'+name,realpathSync(path)])]);
  const receipt=verifyNativeHttpPreparation(join(destination,'preparation.json'),{source,target});
  prepareNativeResidentHttpLibrary({receiptPath:receipt,platform,arch,execute,preparation:null});
  assert.equal(run('git',['rev-parse','HEAD']).trim(),source);
  assert.equal(run('git',['status','--porcelain']),'');
  return receipt;
}

export function prepareNativeRuntimeBundleLibraries(repository, destination, {
  execute = execFileSync, platform = process.platform, arch = process.arch,
  opensslPrefix = process.env.ACTQL_TEST_NATIVE_OPENSSL_PREFIX ??
    (platform === 'linux' ? '/usr' : '/opt/homebrew/opt/openssl@3'),
  darwinCryptoProfile = process.env.ACTQL_TEST_NATIVE_CRYPTO_PROFILE ?? 'source-macos11',
  opensslSourceArchive = process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE,
  moonHome = process.env.MOON_HOME,
  preparation = process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
  seconds = 600,
} = {}) {
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 1800);
  const target = platform === 'darwin' && arch === 'arm64' ? 'darwin-arm64'
    : platform === 'linux' && arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No selected bundle component recipe for this actual platform');
  repository = realpathSync(repository);
  destination = join(realpathSync(dirname(resolve(destination))), basename(destination));
  const run = (command, args) => execute(command, args, {cwd: repository,
    encoding: 'utf8', timeout: (seconds + 30) * 1000, maxBuffer: 8 * 1024 ** 2});
  const source = run('git', ['rev-parse', 'HEAD']).trim();
  assert.match(source, /^[0-9a-f]{40}$/u);
  assert.equal(run('git', ['status', '--porcelain']), '');
  const clang = realpathSync(platform === 'darwin' ? run('xcrun', ['--find', 'clang']).trim()
    : run('sh', ['-c', 'command -v clang']).trim());
  const sdk = platform === 'darwin' ? realpathSync(run('xcrun', ['--show-sdk-path']).trim()) : undefined;
  if (preparation !== undefined && preparation !== null) {
    destination = preparedNativeComponents(preparation, {source,target,clang,sdk,
      moon_home:typeof moonHome==='string'?realpathSync(moonHome):undefined});
  } else run('python3', [join(repository, 'scripts/prepare-native-runtime-bundle-components.py'),
    '--source', source, '--target', target, '--clang', clang,
    ...(sdk === undefined ? [] : ['--sdk', sdk, '--darwin-crypto-profile', darwinCryptoProfile]),
    ...(platform === 'linux' || darwinCryptoProfile === 'homebrew26'
      ? ['--openssl-prefix', realpathSync(opensslPrefix)] : []),
    ...(opensslSourceArchive === undefined || platform !== 'darwin' ? []
      : ['--openssl-source-archive', realpathSync(opensslSourceArchive)]),
    '--destination', destination, '--seconds', String(seconds)]);
  const receipt = JSON.parse(readFileSync(join(destination, 'bundle-components.json'), 'utf8'));
  assert.equal(receipt.source, source); assert.equal(receipt.target, target);
  assert.equal(receipt.providers, 0); assert.equal(receipt.loaded, false);
  assert.equal(receipt.initialized, false);
  for (const name of ['sqlite', 'crypto']) {
    const item = receipt[name];
    assert.equal(dirname(item.path), join(destination, name));
    const original = lstatSync(item.path);
    assert(original.isFile() && !original.isSymbolicLink());
    const bytes = readFileSync(item.path);
    assert.equal(bytes.length, item.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
  }
  assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
  assert.equal(run('git', ['status', '--porcelain']), '');
  return {sqliteLibrary: receipt.sqlite.path, cryptoLibrary: receipt.crypto.path};
}
