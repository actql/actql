// Focused installed Native Local preparation acceptance. This does not claim
// Run execution, approval, restart recovery or a complete standard Local CLI.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {admitInstalledLocalRuntime} from '../packages/native-cli/lib/local-runtime.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, ...extra] = process.argv.slice(2);
assert(input && extra.length === 0, 'usage: test-native-cli-local-install.mjs <fixed-CLI-RC>');
const directory = resolve(input);
const manifest = await verifyNativeCliRelease(directory);
const source = checkoutState(repository);
assert(source.clean, 'Installed Local preparation acceptance requires clean source');
assert.equal(source.revision, manifest.sourceSha, 'Fixture and Native artifact must share the fixed source');
const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
assert(manifest.platforms[platform], 'No fixed Native artifact for this platform');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-local-install-',
  label: 'Native Local preparation external installation'});
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const root = scratch.path, prefix = join(root, 'global'), records = [];
const env = {...process.env};
for (const key of Object.keys(env)) if (/^npm_config_/iu.test(key)) delete env[key];
Object.assign(env, {npm_config_registry: registry.url,
  npm_config_userconfig: join(root, 'npmrc'), npm_config_globalconfig: join(root, 'npmrc-global'),
  npm_config_cache: join(root, 'cache'), npm_config_proxy: '', npm_config_https_proxy: '',
  npm_config_update_notifier: 'false', NO_PROXY: '127.0.0.1,localhost'});
delete env.NODE_PATH;
const execute = promisify(execFile);
async function run(command, args, timeoutMs = 120_000) {
  const started = Date.now();
  let result;
  try {
    result = {...await execute(command, args, {cwd: root, env, timeout: timeoutMs,
      killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024}), code: 0, signal: null};
  } catch (error) {
    result = {code: error.code ?? null, signal: error.signal ?? null,
      killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? ''};
  }
  const record = {command, args, cwd: root, timeoutMs, elapsedMs: Date.now() - started, ...result};
  records.push(record);
  process.stdout.write(record.stdout);
  process.stderr.write(record.stderr);
  // The owned failed installation is retained with its exact command output.
  await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
  assert.equal(record.code, 0, `${command}: ${record.code}/${record.signal}\n${record.stdout}\n${record.stderr}`);
  assert.equal(record.signal, null);
}

try {
  await mkdir(prefix);
  await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(join(root, 'npmrc-global'), '');
  // Async npm keeps the private loopback registry responsive. No SDK/Host RC or
  // public-registry package is needed by this Native-only installed boundary.
  await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts',
    '--no-audit', '--no-fund', `actql@${manifest.cohort.packageVersion}`]);
  const installed = join(prefix, 'lib/node_modules/actql');
  const launcher = join(prefix, 'bin/actql');
  assert.deepEqual((await readdir(join(installed, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
  const platformRoot = join(installed, 'node_modules/@actql', `cli-${platform}`);
  const binary = join(platformRoot, 'bin/actql-native-client');
  const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
  assert.deepEqual(artifact, manifest.artifacts.find(value => value.platform === platform));
  const bytes = await readFile(binary);
  assert.equal(bytes.length, manifest.platforms[platform].binaryBytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), manifest.platforms[platform].binarySha256);
  await run(launcher, ['--help']);
  await run(launcher, ['--version']);
  assert(artifact.localRuntime,'Native Local checks require the actual selected Local runtime');
  const localRuntime=admitInstalledLocalRuntime({root:platformRoot,metadata:artifact.localRuntime,
    expected:{sourceSha:manifest.sourceSha,platform,localRuntimeSha256:artifact.localRuntime.sha256}});
  for(const [role,key] of [['sqlite','ACTQL_TEST_NATIVE_SQLITE_LIBRARY'],['crypto','ACTQL_TEST_NATIVE_CRYPTO_LIBRARY']]) {
    const library=localRuntime.libraries.find(value=>value.role===role);assert(library);
    env[key]=join(platformRoot,library.path);
  }
  env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER = launcher;
  env.ACTQL_TEST_NATIVE_CLIENT_BINARY = binary;
  const focused = new URL('./test-execution.mjs', import.meta.url).href;
  const fixture = fileURLToPath(new URL('./test-native-local-cli.test.mjs', import.meta.url));
  const evidenceScratch = join(directory, 'local-install-focused-evidence');
  await run(process.execPath, ['--input-type=module', '-e',
    `import {runFocusedTests} from ${JSON.stringify(focused)}; process.exitCode=runFocusedTests("node",[${JSON.stringify(fixture)}],{cwd:process.cwd(),evidenceScratch:${JSON.stringify(evidenceScratch)}});`]);
  assert.deepEqual(checkoutState(repository), source);
  const receipt = {version: 'actql-native-cli-install-acceptance/0.1', scope: 'local-preparation',
    cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null,
    artifact, scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
    cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
    publicRegistryPublication: 'not-tested', records,
    unverified: ['Local Run execution', 'approval', 'cross-process Local recovery', 'other platforms']};
  const receiptFile = join(directory, `local-preparation-install-${platform}-${Date.now()}.json`);
  await writeFile(receiptFile, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  console.log(`Installed Native Local preparation passed: ${receiptFile}`);
} finally {
  await registry.close();
}
// Registry and every spawned child are stopped before cleanup is certified.
scratch.passed();
