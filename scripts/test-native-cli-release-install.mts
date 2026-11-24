// Actual global npm installation, installed Native/mTLS Host and wire failures.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {copyFile, mkdir, readFile, realpath, writeFile, rename} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {verifyNativeCliRelease, sharedRuntimeSourceDelta} from './native-cli-release.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {admitInstalledNativeRemoteHttp, nativeCliReleaseInstallSelection} from './release-native-install.mjs';
import {runNativeInstallCommand} from './release-install-child.mjs';
import {checkoutState} from './packed-client-packages.mjs';

type SharedCommand = Awaited<ReturnType<typeof runNativeInstallCommand>>;
type CommandRecord = {command: string; args: readonly string[]; code: number | null;
  signal: NodeJS.Signals | null; terminationReason: 'timeout' | 'output-limit' | null;
  timeoutMs: number; stdout: string; stderr: string; elapsedMs: number};

const repository = fileURLToPath(new URL('../', import.meta.url));
const {cliDirectory, sdkDirectory, sharedClients, verifiedRemoteHttp} = nativeCliReleaseInstallSelection(process.argv.slice(2));
const cli = await verifyNativeCliRelease(cliDirectory), sdk = await verifyPackageRelease(sdkDirectory);
const runtimeSourceDelta = sharedRuntimeSourceDelta(repository, sdk.sourceSha, cli.sourceSha);
assert.equal(runtimeSourceDelta, '', 'This combined acceptance requires unchanged Host/protocol runtime inputs between its distinct fixed sources');
if (sharedClients) {
  const selected = checkoutState(repository);
  assert(selected.clean && cli.sourceSha === selected.revision && sdk.sourceSha === selected.revision,
    'Shared Host acceptance requires both fixed packages and the fixture from the same clean Source');
}
const key = process.platform === 'darwin' && process.arch === 'arm64' ? 'darwin-arm64' : 'linux-x64-gnu';
assert(cli.platforms[key], 'No fixed artifact for this actual platform');
const scratch = await createOwnedScratch({parent: await realpath(tmpdir()), prefix: 'actql-cli-install-',
  label: 'Native CLI fixed release installation'});
const root = scratch.path, registry = await openReleaseTestRegistry([
  {directory: cliDirectory, manifest: cli}, {directory: sdkDirectory, manifest: sdk}]);
const prefix = join(root, 'global'), consumer = join(root, 'host'), records: (CommandRecord | SharedCommand)[] = [];
await mkdir(consumer); await mkdir(prefix);
await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
await writeFile(join(root, 'npmrc-global'), '');
const env = {...process.env, npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
  npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
  npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost', npm_config_update_notifier: 'false'} as NodeJS.ProcessEnv;
delete env.NODE_PATH;
delete env.ACTQL_TEST_NATIVE_HTTP_LIBRARY;
const useRemoteHttp = sharedClients &&
  (verifiedRemoteHttp || cli.platforms[key].localRuntimeSha256 !== undefined);
if (useRemoteHttp) {
  for (const key of Object.keys(env)) {
    if (key.startsWith('DYLD_') || key.startsWith('LD_')) delete env[key];
  }
}
async function run(command: string, args: readonly string[], cwd = root, expectedCode = 0, timeoutMs = 180_000) {
  const started = Date.now();
  const record = await new Promise<CommandRecord>((resolve, reject) => {
    const child = spawn(command, args, {cwd, env, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', length = 0, terminationReason: CommandRecord['terminationReason'] = null;
    const timer = setTimeout(() => {terminationReason = 'timeout'; child.kill('SIGTERM');}, timeoutMs);
    for (const [stream, append] of [[child.stdout, (v: string) => {stdout += v;}], [child.stderr, (v: string) => {stderr += v;}]] as const) {
      stream.on('data', chunk => {length += chunk.length; if (length > 8 * 1024 * 1024) {terminationReason = 'output-limit'; child.kill('SIGTERM');} else append(chunk.toString());});
    }
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({command, args, code, signal, terminationReason, timeoutMs, stdout, stderr, elapsedMs: Date.now() - started});});
  });
  records.push(record); assert.equal(record.code, expectedCode, `${command}: code=${record.code} signal=${record.signal} reason=${record.terminationReason}\n${record.stdout}\n${record.stderr}`);
  console.log(record.stdout.trimEnd()); return record;
}
try {
  await run('npm', ['install', '-g', '--prefix', prefix, '--no-audit', '--no-fund', `actql@${cli.cohort.packageVersion}`]);
  const installed = join(prefix, 'lib/node_modules'), executable = join(prefix, 'bin/actql');
  const {readdir} = await import('node:fs/promises');
  assert.deepEqual((await readdir(join(installed, 'actql/node_modules/@actql'))).sort(), [`cli-${key}`]);
  const installedPlatform = join(installed, 'actql/node_modules/@actql', `cli-${key}`);
  const installedBinary = join(installedPlatform, 'bin/actql-native-client');
  const artifact = JSON.parse(await readFile(join(installedPlatform, 'artifact.json'), 'utf8'));
  assert.equal(artifact.binarySha256, cli.platforms[key].binarySha256);
  const readRemoteHttp = () => admitInstalledNativeRemoteHttp(installedPlatform,
    {...cli.platforms[key], sourceSha: cli.sourceSha} as Parameters<typeof admitInstalledNativeRemoteHttp>[1], artifact);
  const remoteHttp = useRemoteHttp ? readRemoteHttp() : undefined;
  if (remoteHttp !== undefined) env.ACTQL_TEST_NATIVE_HTTP_LIBRARY = remoteHttp.libraryPath;
  if (!sharedClients) {
    await run(executable, ['--help']); await run(executable, ['--version']);
    // Prove that the installed wrapper detects missing and corrupted binaries.
    await rename(installedPlatform, `${installedPlatform}.held`);
    try {assert.match((await run(executable, ['--help'], root, 69)).stderr, /Missing @actql\/cli-/u);}
    finally {await rename(`${installedPlatform}.held`, installedPlatform);}
    const original = await readFile(installedBinary);
    try {await writeFile(installedBinary, Buffer.from('wrong artifact'));
      assert.match((await run(executable, ['--help'], root, 65)).stderr, /identity mismatch/u);
    } finally {await writeFile(installedBinary, original);}
  }
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/node@${sdk.cohort.packageVersion}`], consumer);
  await copyFile(join(repository, 'scripts/fixtures/release-native-host.mjs'), join(consumer, 'host-acceptance.mjs'));
  await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key', '-out', 'remote.crt',
    '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    '-addext', 'extendedKeyUsage=serverAuth,clientAuth'], consumer);
  env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER = executable;
  env.ACTQL_TEST_NATIVE_CLIENT_BINARY = installedBinary;
  env.NODE_EXTRA_CA_CERTS = join(consumer, 'remote.crt');
  let sharedHost: {original: unknown; reopened: unknown} | undefined, sourceControl: unknown[] | undefined;
  if (sharedClients) {
    // Both processes use the same state directory. The observer requires
    // the first successful close, live FD observation, ACK and process exit
    // before this test opens a second explicit owner.
    const state = join(consumer, 'host-state');
    async function runSharedOwner(selector: string, stem: string) {
      let record: SharedCommand;
      try {
        record = await runNativeInstallCommand(process.execPath,
          ['host-acceptance.mjs', executable, selector], {cwd: consumer, env, state});
      } catch (failure) {
        if ((failure as {commandRecord?: SharedCommand}).commandRecord) await writeFile(join(root, stem + '-command.json'),
          JSON.stringify((failure as {commandRecord?: SharedCommand}).commandRecord, null, 2) + '\n', {flag: 'wx'});
        throw failure;
      }
      records.push(record);
      await writeFile(join(root, stem + '-command.json'), JSON.stringify(record, null, 2) + '\n', {flag: 'wx'});
      console.log(record.stdout.trimEnd());
      const evidence = JSON.parse(await readFile(join(consumer, 'native-' + stem + '-acceptance.json'), 'utf8'));
      assert.equal(evidence.ownerPid, record.pid);
      return evidence;
    }
    const original = await runSharedOwner('--shared-clients', 'shared-host');
    const reopened = await runSharedOwner('--shared-saved-restart', 'shared-host-restart');
    assert.equal(reopened.originalOwnerPid, original.ownerPid);
    assert.notEqual(reopened.ownerPid, original.ownerPid);
    sharedHost = {original, reopened};
    const {fixedSharedHostSourceScenarios, runSharedHostSourceAcceptance} =
      await import('./fixtures/shared-host-source-acceptance.mjs');
    sourceControl = [];
    for (const scenario of fixedSharedHostSourceScenarios) {
      const outputRoot = join(root, `shared-source-${scenario}`);
      sourceControl.push(await runSharedHostSourceAcceptance({
        outputRoot, nativeDirectory: cliDirectory, sdkDirectory, scenario,
      }));
    }
  } else {
    await run(process.execPath, ['host-acceptance.mjs', executable], consumer);
    // The same installed launcher/executable must preserve all existing mTLS
    // auth, response-loss, identity and no-resend regressions. Mock Host evidence
    // is separate from the actual Host acceptance above.
    // Hundreds of independently checked wire cases also run under x64 emulation.
    // Keep a finite budget without truncating that required refusal coverage.
    await run(process.execPath, [join(repository, 'scripts/test-native-client.mjs')], root, 0, 420_000);
  }
  if (remoteHttp !== undefined) assert.deepEqual(readRemoteHttp(), remoteHttp);
  const receipt = {version: 'actql-native-cli-install-acceptance/0.1', cliSourceSha: cli.sourceSha, hostSourceSha: sdk.sourceSha,
    runtimeSourceDelta: [],
    ...(remoteHttp ? {remoteHttp: remoteHttp.member} : {}),
    platform: key, node: process.version, glibc: process.platform === 'linux'
      ? (process.report.getReport() as {header: {glibcVersionRuntime?: string}}).header.glibcVersionRuntime : null,
    artifact, cliPackages: cli.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    hostPackages: sdk.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    registry: 'private-loopback-fixed-RC', publicRegistryPublication: 'not-tested',
    ...(sharedClients ? {acceptedScope: 'parallel named queries, original Saved and separate Source cancellation and crash cases',
      ...(remoteHttp ? {transport: 'verified-packaged-synchronous-https'} : {}),
      sharedHost, sourceControl, unexecuted: ['wire-fault-matrix']} : {}), records};
  await writeFile(join(cliDirectory, `install-${key}-${Date.now()}.json`), `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  scratch.passed(); console.log(`Native Remote CLI ${sharedClients ? 'parallel shared-Host' : 'global installation'} passed: ${key}`);
} finally {await registry.close();}
