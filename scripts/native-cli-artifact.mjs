import {checkInterfaceOwners} from './check-interface-owners.mjs';
// Run under the existing heavy guard in a clean, platform-native checkout.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {chmod, copyFile, mkdir, open, readFile, realpath, writeFile} from 'node:fs/promises';
import {isAbsolute, join, resolve, delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {prepareNativeLocalRuntime} from './native-cli-local-runtime.mjs';
import {assertScalarPairEvidenceFresh} from './native-local-scalar-pair-evidence.mjs';
import {assertNativeLocalFreshRuntimeRecipe} from './native-cli-default-assets.mjs';
import {admitCompletedNativeLocalProvider} from './native-cli-completed-provider.mjs';
import {prepareNativeVersionCompiler, observeNativePackageVersion, nativePackageVersion} from './native-cli-version.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const run = (command, args, {timeout = 300_000, env = process.env} = {}) => execFileSync(command, args, {cwd: repository,
  encoding: 'utf8', timeout, env, maxBuffer: 8 * 1024 * 1024});

export function inspectNativeAbi(binary, platform, execute = execFileSync) {
  const inspect = (tool, args) => execute(tool, args, {encoding: 'utf8', maxBuffer: 8 * 1024 * 1024});
  if (platform === 'darwin-arm64') {
    const loadCommands = inspect('otool', ['-l', binary]);
    const minimumMacOS = /\bcmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos (\d+\.\d+(?:\.\d+)?)/u.exec(loadCommands)?.[1];
    assert(minimumMacOS, 'No observed macOS executable deployment requirement');
    return {format: 'Mach-O', minimumMacOS,
      sharedLibraries: inspect('otool', ['-L', binary]).split('\n').slice(1).filter(Boolean).map(v => v.trim()),
      loadCommands, httpLibrary: '/usr/lib/libcurl.4.dylib', httpLibraryBundled: false};
  }
  const versionInfo = inspect('readelf', ['--version-info', binary]);
  const versions = [...versionInfo.matchAll(/\bGLIBC_(\d+)\.(\d+)\b/gu)]
    .map(v => [Number(v[1]), Number(v[2])]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  assert(versions.length, 'No observed executable glibc symbol requirements');
  const dynamic = inspect('readelf', ['-d', binary]);
  return {format: 'ELF', minimumGlibc: versions.at(-1).join('.'),
    sharedLibraries: [...dynamic.matchAll(/\(NEEDED\).*?\[([^\]]+)\]/gu)].map(v => v[1]),
    versionInfo, dynamic, httpLibrary: 'libcurl.so.4', httpLibraryBundled: false,
    httpLibraryRequirements: 'Separately supplied libcurl and its transitive dependencies may require a newer glibc than the executable.'};
}

// This bounds compilation time only; it changes neither compiler flags nor admission.
export function nativeCliCompileBudget(compileSeconds, scoped = false) {
  assert.equal(typeof scoped, 'boolean');
  const seconds = compileSeconds === undefined ? (scoped ? 900 : 300) : compileSeconds;
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 86400,
    'compileSeconds must be an integer from 1 to 86400');
  return {seconds, timeoutMs: (seconds + (scoped ? 30 : 0)) * 1000};
}

// Actual producer selection only. The same target's original scoped provider
// and component observations still decide whether a Local artifact can exist.
export function nativeLocalCompilerArguments(platform, {clang, sdk}) {
  assert(typeof clang === 'string' && isAbsolute(clang));
  if (platform === 'darwin-arm64') {
    assert(typeof sdk === 'string' && isAbsolute(sdk));
    return ['--clang', clang, '--sdk', sdk, '--target', 'darwin-arm64'];
  }
  assert.equal(platform, 'linux-x64-gnu', 'No selected Local producer target');
  assert.equal(sdk, undefined, 'Linux Local cannot substitute a Darwin SDK');
  return ['--clang', clang, '--target', 'linux-x64'];
}

export async function buildNativeCliArtifact(destination, {verbose = false, localRuntime, compileSeconds,
  completedLocalProvider = false, packageVersion} = {}) {
  const selectedVersion = packageVersion === undefined ? undefined : nativePackageVersion(packageVersion);
  const budget = nativeCliCompileBudget(compileSeconds, localRuntime !== undefined);
  assert.equal(typeof verbose, 'boolean', 'verbose must be an explicit Boolean');
  assert.equal(typeof completedLocalProvider, 'boolean');
  if (completedLocalProvider) {
    assert(localRuntime !== undefined, 'Completing a Local provider requires its selected runtime recipe');
    assert.equal(compileSeconds, undefined, 'Completion never starts another compilation');
    assert(process.env.MOON_HOME, 'Set MOON_HOME to the selected pinned toolchain');
  }
  const source = checkoutState(repository); assert(source.clean, 'Native artifact requires clean source HEAD');
  await checkInterfaceOwners(repository, {manifests: ['packages/native-cli/package.json']});
  const pins = JSON.parse(await readFile(join(repository, 'toolchain.json'), 'utf8'));
  const moon = run('moon', ['version']).trim(), moonc = run('moonc', ['-v']).trim();
  assert(moon.includes(pins.moon)); assert(moonc.includes(pins.moonc));
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  destination = resolve(destination);
  const completed = completedLocalProvider ? await admitCompletedNativeLocalProvider(
    destination, source.revision, repository, await realpath(process.env.MOON_HOME),
    {packageVersion: selectedVersion, platform}) : undefined;
  let localMetadata;
  if (localRuntime !== undefined) {
    assert.equal(localRuntime.sourceSha, source.revision, 'Local runtime must belong to this exact source');
    assert.equal(localRuntime.platform, platform, 'Local runtime must match the producer platform');
    // Current fresh originals and the frozen historical proof have distinct
    // subjects. Historical operational use is fenced by the Native Owner.
    assertNativeLocalFreshRuntimeRecipe(localRuntime, source.revision, repository);
    assertScalarPairEvidenceFresh(repository);
    if (!completed) await mkdir(destination);
    localMetadata = await prepareNativeLocalRuntime(destination, localRuntime);
  }
  const buildArgs = ['build', ...(verbose ? ['--verbose'] : []),
    '--target', 'native', '--release', '-j', '1', 'src/cmd/native_client'];
  let buildCommand = 'moon', selectedBuildArgs = buildArgs, buildEnvironment = process.env, versionCompiler;
  let built = join(repository, '_build/native/release/build/cmd/native_client/native_client.exe');
  let c = join(repository, '_build/native/release/build/cmd/native_client/native_client.c');
  let scopedReceipt = completed?.receipt;
  if (selectedVersion !== undefined && localMetadata === undefined) {
    await mkdir(destination);
    versionCompiler = await prepareNativeVersionCompiler(join(destination, 'version-compiler'), repository, selectedVersion);
    // A fresh target directory prevents an older macro/object from being
    // silently reused when only the explicitly selected package version changes.
    const emission = join(destination, 'native-build');
    selectedBuildArgs = [...buildArgs.slice(0, -1), '--target-dir', emission, buildArgs.at(-1)];
    built = join(emission, 'native/release/build/cmd/native_client/native_client.exe');
    c = join(emission, 'native/release/build/cmd/native_client/native_client.c');
    buildEnvironment = {...process.env, PATH: `${versionCompiler.directory}${delimiter}${process.env.PATH ?? ''}`};
  }
  if (localMetadata !== undefined) {
    assert(process.env.MOON_HOME, 'Set MOON_HOME to the selected pinned toolchain');
    const sdk = platform === 'darwin-arm64' ? await realpath(run('xcrun', ['--show-sdk-path']).trim()) : undefined;
    const clang = await realpath(platform === 'darwin-arm64' ? run('xcrun', ['--find', 'clang']).trim()
      : run('sh', ['-c', 'command -v clang']).trim());
    buildCommand = run('python3', ['-c', 'import os,sys;print(os.path.realpath(sys.executable))']).trim();
    selectedBuildArgs = [join(repository, 'scripts/produce-native-remote-scoped-runtime.py'),
      '--source', source.revision, '--moon-home', await realpath(process.env.MOON_HOME),
      ...nativeLocalCompilerArguments(platform, {clang, sdk}), '--destination', join(destination, 'native-producer'),
      '--seconds', String(budget.seconds), '--entry', 'src/cmd/native_client',
      ...(selectedVersion === undefined ? [] : ['--package-version', selectedVersion])];
    built = join(destination, 'native-producer/emission/native/release/build/cmd/native_client/native_client.exe');
    c = join(destination, 'native-producer/emission/native/release/build/cmd/native_client/native_client.c');
  }
  if (completed) {
    [buildCommand, ...selectedBuildArgs] = completed.generation;
    assert.equal(built, completed.binary);
    assert.equal(c, completed.generatedC);
  }
  const startedAt = performance.now();
  if (verbose) console.log(JSON.stringify({phase: completed ? 'native-cli-provider-completed' : 'native-cli-build-start',
    sourceSha: source.revision, command: [buildCommand, ...selectedBuildArgs], timeoutMs: budget.timeoutMs}));
  try {
    const output = completed ? '' : run(buildCommand, selectedBuildArgs,
      {timeout: budget.timeoutMs, env: buildEnvironment});
    if (localMetadata !== undefined && !completed) {
      scopedReceipt = JSON.parse(await readFile(join(destination, 'native-producer/build.json'), 'utf8'));
      assert.equal(scopedReceipt.source, source.revision);
      assert.equal(scopedReceipt.entry, 'src/cmd/native_client');
      assert.equal(scopedReceipt.target, platform === 'darwin-arm64' ? 'darwin-arm64' : 'linux-x64');
      assert.equal(scopedReceipt.plan_only, false);
      assert.equal(scopedReceipt.providers, 1);
      assert.equal(scopedReceipt.moon_build_exit, 0);
      assert.equal(scopedReceipt.executable.path, built);
      if (selectedVersion !== undefined) assert.equal(scopedReceipt.package_version, selectedVersion);
    }
    if (verbose) {
      process.stdout.write(output);
      console.log(JSON.stringify({phase: completed ? 'native-cli-provider-verified' : 'native-cli-build-exited', code: 0,
        elapsedMs: Math.round(performance.now() - startedAt)}));
    }
  } catch (error) {
    if (verbose) {
      // Retain the actual compiler's bounded output on failure. This neither
      // retries compilation nor treats the old executable as a new artifact.
      if (error.stdout) process.stdout.write(error.stdout);
      if (error.stderr) process.stderr.write(error.stderr);
      console.error(JSON.stringify({phase: 'native-cli-build-failed',
        sourceSha: source.revision, elapsedMs: Math.round(performance.now() - startedAt),
        code: error.code ?? null, status: error.status ?? null,
        signal: error.signal ?? null}));
    }
    throw error;
  }
  assert.deepEqual(checkoutState(repository), source);
  if (localMetadata === undefined && selectedVersion === undefined) await mkdir(destination);
  const binary = join(destination, 'actql-native-client');
  await copyFile(built, binary); await chmod(binary, 0o755);
  const bytes = await readFile(binary);
  if (scopedReceipt !== undefined) {
    assert.equal(bytes.length, scopedReceipt.executable.bytes);
    assert.equal(hash(bytes), scopedReceipt.executable.sha256);
  }
  let versionObservation;
  if (selectedVersion !== undefined) {
    if (versionCompiler) assert.equal(hash(await readFile(versionCompiler.path)), versionCompiler.sha256,
      'Original version compiler input changed during the build');
    const observed = observeNativePackageVersion(binary, selectedVersion);
    const buildInputSha256 = versionCompiler?.sha256 ?? hash(await readFile(join(destination, 'native-producer/commands.json')));
    versionObservation = {...observed, binarySha256: hash(bytes), binaryBytes: bytes.length, buildInputSha256};
    assert.deepEqual(await readFile(binary), bytes, 'Version observation cannot change the selected executable');
  }
  const notices = {};
  for (const [filename, coreFile] of [['MOONBIT-CORE-LICENSE', 'LICENSE'], ['MOONBIT-CORE-NOTICE', 'NOTICE']]) {
    const text = await readFile(join(repository, 'packages/local-node', filename));
    assert(process.env.MOON_HOME, 'Set MOON_HOME to the selected pinned toolchain');
    assert.deepEqual(text, await readFile(join(process.env.MOON_HOME, 'lib/core', coreFile)), 'Distribution notices must match the compiler Core');
    notices[filename] = hash(text);
  }
  let httpRuntime;
  if (platform === 'linux-x64-gnu') {
    const library = run('ldconfig', ['-p']).split('\n').find(line => /libcurl\.so\.4 .*x86-64.*=> /u.test(line))?.split('=> ')[1]?.trim();
    assert(library, 'No x64 libcurl.so.4 runtime available for the declared distribution');
    const dependencies = run('ldd', [library]); assert(!dependencies.includes('not found'), 'Unresolved libcurl dependency');
    const paths = [library, ...[...dependencies.matchAll(/(?:=>\s+|^\s*)(\/[^\s]+)\s+\(/gmu)].map(v => v[1])];
    const files = [];
    for (const path of [...new Set(await Promise.all(paths.map(path => realpath(path))))]) {
      const data = await readFile(path), versionInfo = run('readelf', ['--version-info', path]);
      const versions = [...versionInfo.matchAll(/\bGLIBC_(\d+)\.(\d+)\b/gu)]
        .map(v => [Number(v[1]), Number(v[2])]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      files.push({path, bytes: data.length, sha256: hash(data), greatestListedGlibc: versions.at(-1)?.join('.') ?? null});
    }
    httpRuntime = {library, dependencies, files, testedGlibc: glibc,
      interpretation: 'Observed installed libcurl closure; not a promise about other libcurl distributions.'};
  } else httpRuntime = {library: '/usr/lib/libcurl.4.dylib', provider: 'OS dyld shared cache',
    osVersion: run('sw_vers', ['-productVersion']).trim(), osBuild: run('sw_vers', ['-buildVersion']).trim(),
    interpretation: 'The separately installed OS libcurl is validated by actual mTLS acceptance, not bundled.'};
  const generatedCSha256 = hash(await readFile(c));
  if (scopedReceipt) assert.equal(generatedCSha256, scopedReceipt.generated_c.sha256);
  const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: source.revision,
    platform, binarySha256: hash(bytes), binaryBytes: bytes.length,
    generatedCSha256, toolchainPinSha256: hash(await readFile(join(repository, 'toolchain.json'))), notices,
    toolchain: {moon, moonc, node: process.version, cc: run('cc', ['--version']).split('\n')[0]},
    abi: inspectNativeAbi(binary, platform), testedHost: {platform: process.platform, arch: process.arch, glibc: glibc ?? null, httpRuntime},
    generation: [buildCommand, ...selectedBuildArgs], ...(localMetadata ? {localRuntime: localMetadata} : {}),
    ...(selectedVersion === undefined ? {} : {packageVersion: selectedVersion, packageVersionObservation: versionObservation})};
  await writeFile(join(destination, 'artifact.json'), `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx'});
  return record;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [destination, ...options] = process.argv.slice(2);
  let verbose = false, recipe, compileSeconds, completedLocalProvider = false, packageVersion;
  while (options.length) {
    const option = options.shift();
    if (option === '--verbose' && !verbose) verbose = true;
    else if (option === '--complete-local-provider' && !completedLocalProvider) completedLocalProvider = true;
    else if (option === '--local-runtime-recipe' && recipe === undefined && options.length) recipe = options.shift();
    else if (option === '--package-version' && packageVersion === undefined && options.length) packageVersion = nativePackageVersion(options.shift());
    else if (option === '--compile-seconds' && compileSeconds === undefined && options.length) {
      const value = options.shift();
      assert.match(value, /^[1-9][0-9]*$/u, 'compile-seconds must be a positive integer');
      compileSeconds = Number(value);
      nativeCliCompileBudget(compileSeconds);
    }
    else assert.fail('usage: native-cli-artifact.mjs <artifact-directory> [--verbose] [--package-version <explicit-full-version>] [--local-runtime-recipe <selected-recipe>] [--compile-seconds <positive-integer> | --complete-local-provider]');
  }
  assert(destination);
  let wire;
  if (recipe) {
    const descriptor = await open(resolve(recipe), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const before = await descriptor.stat();
      assert(before.isFile() && before.size > 0 && before.size <= 65536, 'Local runtime recipe exceeds the finite metadata envelope');
      const bytes = Buffer.alloc(before.size + 1);
      let offset = 0;
      while (offset < bytes.length) {
        const {bytesRead} = await descriptor.read(bytes, offset, bytes.length - offset, null);
        if (!bytesRead) break;
        offset += bytesRead;
      }
      const after = await descriptor.stat();
      assert(offset === before.size && after.size === before.size && after.mtimeMs === before.mtimeMs && after.ctimeMs === before.ctimeMs);
      wire = bytes.subarray(0, offset);
    } finally {await descriptor.close();}
  }
  const record = await buildNativeCliArtifact(destination, {verbose, compileSeconds, completedLocalProvider, packageVersion,
    ...(wire ? {localRuntime: JSON.parse(wire.toString('utf8'))} : {})});
  console.log(JSON.stringify({sourceSha: record.sourceSha, platform: record.platform,
    binarySha256: record.binarySha256, abi: record.abi.sharedLibraries}, null, 2));
}
