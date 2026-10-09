// Actual global npm installation, installed Native/mTLS Host and wire failures.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {copyFile, mkdir, readFile, writeFile, rename} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [cliInput, sdkInput] = process.argv.slice(2); assert(cliInput && sdkInput, 'usage: test-native-cli-release-install.mjs <CLI-RC> <SDK-RC>');
const cliDirectory = resolve(cliInput), sdkDirectory = resolve(sdkInput);
const cli = await verifyNativeCliRelease(cliDirectory), sdk = await verifyPackageRelease(sdkDirectory);
const key = process.platform === 'darwin' && process.arch === 'arm64' ? 'darwin-arm64' : 'linux-x64-gnu';
assert(cli.platforms[key], 'No fixed artifact for this actual platform');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-cli-install-', label: 'Native CLI fixed release installation'});
const root = scratch.path, registry = await openReleaseTestRegistry([
  {directory: cliDirectory, manifest: cli}, {directory: sdkDirectory, manifest: sdk}]);
const prefix = join(root, 'global'), consumer = join(root, 'host'), records = [];
await mkdir(consumer); await mkdir(prefix);
await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
await writeFile(join(root, 'npmrc-global'), '');
const env = {...process.env, npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
  npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
  npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost', npm_config_update_notifier: 'false'};
delete env.NODE_PATH;
async function run(command, args, cwd = root, expectedCode = 0) {
  const started = Date.now();
  const record = await new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd, env, stdio: ['ignore', 'pipe', 'pipe']}); let stdout = '', stderr = '', length = 0;
    const timer = setTimeout(() => child.kill('SIGTERM'), 180_000);
    for (const [stream, append] of [[child.stdout, v => {stdout += v;}], [child.stderr, v => {stderr += v;}]]) {
      stream.on('data', chunk => {length += chunk.length; if (length > 8 * 1024 * 1024) child.kill('SIGTERM'); else append(chunk.toString());});
    }
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({command, args, code, signal, stdout, stderr, elapsedMs: Date.now() - started});});
  });
  records.push(record); assert.equal(record.code, expectedCode, `${command}: ${record.stdout}\n${record.stderr}`);
  console.log(record.stdout.trimEnd()); return record;
}
try {
  await run('npm', ['install', '-g', '--prefix', prefix, '--no-audit', '--no-fund', `actql@${cli.cohort.packageVersion}`]);
  const installed = join(prefix, 'lib/node_modules'), executable = join(prefix, 'bin/actql');
  const {readdir} = await import('node:fs/promises');
  assert.deepEqual((await readdir(join(installed, 'actql/node_modules/@actql'))).sort(), [`cli-${key}`]);
  await run(executable, ['--help']); await run(executable, ['--version']);
  const installedPlatform = join(installed, 'actql/node_modules/@actql', `cli-${key}`);
  const installedBinary = join(installedPlatform, 'bin/actql-native-client');
  const artifact = JSON.parse(await readFile(join(installedPlatform, 'artifact.json'), 'utf8'));
  assert.equal(artifact.binarySha256, cli.platforms[key].binarySha256);
  // Prove that the installed wrapper detects missing and corrupted binaries.
  await rename(installedPlatform, `${installedPlatform}.held`);
  try {assert.match((await run(executable, ['--help'], root, 69)).stderr, /Missing @actql\/cli-/u);}
  finally {await rename(`${installedPlatform}.held`, installedPlatform);}
  const original = await readFile(installedBinary);
  try {await writeFile(installedBinary, Buffer.from('wrong artifact'));
    assert.match((await run(executable, ['--help'], root, 65)).stderr, /identity mismatch/u);
  } finally {await writeFile(installedBinary, original);}
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/node@${sdk.cohort.packageVersion}`], consumer);
  await copyFile(join(repository, 'scripts/fixtures/release-native-host.mjs'), join(consumer, 'host-acceptance.mjs'));
  await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key', '-out', 'remote.crt',
    '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    '-addext', 'extendedKeyUsage=serverAuth,clientAuth'], consumer);
  env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER = executable;
  env.ACTQL_TEST_NATIVE_CLIENT_BINARY = installedBinary;
  env.NODE_EXTRA_CA_CERTS = join(consumer, 'remote.crt');
  await run(process.execPath, ['host-acceptance.mjs', executable], consumer);
  // The same installed launcher/executable must preserve all existing mTLS
  // auth, response-loss, identity and no-resend regressions. Mock Host evidence
  // is separate from the actual Host acceptance above.
  await run(process.execPath, [join(repository, 'scripts/test-native-client.mjs')]);
  const receipt = {version: 'actql-native-cli-install-acceptance/0.1', cliSourceSha: cli.sourceSha, hostSourceSha: sdk.sourceSha,
    platform: key, node: process.version, glibc: process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : null,
    artifact, cliPackages: cli.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    hostPackages: sdk.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    registry: 'private-loopback-fixed-RC', publicRegistryPublication: 'not-tested', records};
  await writeFile(join(cliDirectory, `install-${key}-${Date.now()}.json`), `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  scratch.passed(); console.log(`Native Remote CLI global installation passed: ${key}`);
} finally {await registry.close();}
