// Ordinary Native CLI build/pack followed by an external, fresh installation.
// This is a private CI cohort, never a registry release or Linux Local claim.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, readdir, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildNativeCliArtifact} from './native-cli-artifact.mjs';
import {prepareNativeCliRelease, verifyNativeCliRelease} from './native-cli-release.mjs';
import {checkoutState, CLIENT_PACKAGES, packedClientPackage} from './packed-client-packages.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {publicConsumerEnvironment, releaseConsumerDestination} from './release-public-install.mjs';
import {runNativeInstallCommand} from './test-native-standalone-install.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
// An explicit immutable test input, not a proposed public package version.
export const nativeCliTestCohort = Object.freeze({packageVersion: '0.0.2-rc.0',
  registry: 'https://registry.npmjs.org/', access: 'public', tag: 'rc'});

export function requireNativeCliCiInputs(environment, source, platform = process.platform, arch = process.arch) {
  assert.equal(platform, 'linux'); assert.equal(arch, 'x64');
  assert(source.clean, 'Native CLI installed acceptance requires clean source');
  assert(environment.ACTQL_PACKED_CLIENT_PACKAGES,
    'Use the same-run normal Client package producer; do not repack inside this consumer');
}

export function requireNativeHostAuthorizationReceipt(value) {
  assert.equal(value?.version, 'actql-native-release-host-authorization/0.1');
  assert(Array.isArray(value.receipts));
  assert.deepEqual(value.receipts.map(receipt => receipt?.omitted), ['run-read', 'result-main-read']);
  for (const receipt of value.receipts) {
    assert.equal(receipt.computes, 1);
    for (const field of ['clientCloseReturned', 'serverCloseReturned', 'hostCloseReturned'])
      assert.equal(receipt[field], true);
    assert(receipt.ref && typeof receipt.ref === 'object' && !Array.isArray(receipt.ref) &&
      Object.keys(receipt.ref).length > 0);
    if (receipt.omitted === 'run-read') {
      assert.deepEqual(receipt.denials, ['wait', 'status', 'attach', 'lookup-submission']
        .map(operation => ({operation, code: 'ClientConnectionDenied'})));
      assert.deepEqual(receipt.rows, [{id: 1}, {id: 2}]);
      assert(Number.isSafeInteger(receipt.resultReadAttempts) &&
        receipt.resultReadAttempts >= 1 && receipt.resultReadAttempts <= 300);
      assert.deepEqual(receipt.pendingResultReads, Array.from(
        {length: receipt.resultReadAttempts - 1}, (_, index) =>
          ({attempt: index + 1, code: 'ResultAccessDenied', rowsYielded: 0})));
    } else {
      assert.deepEqual(receipt.denials, [
        {operation: 'read', code: 'ResultAccessDenied', rowsYielded: 0},
        {operation: 'result-describe', code: 'ResultAccessDenied'},
      ]);
    }
  }
  return value;
}

export async function acceptInstalledNativeCli(directory) {
  const source = checkoutState(repository);
  requireNativeCliCiInputs(process.env, source);
  const manifest = await verifyNativeCliRelease(directory);
  assert.equal(manifest.sourceSha, source.revision);
  const platform = 'linux-x64-gnu';
  const artifact = manifest.artifacts.find(value => value.platform === platform);
  assert(artifact, 'Require the actual Linux artifact');
  // The current ordinary Remote producer does not claim a Linux Local payload.
  // A later Local profile must add positive execution acceptance, not drop this
  // explicit unsupported-cohort regression or count it as Local success.
  assert.equal(artifact.localRuntime, undefined);
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-cli-ci-',
    label: 'Fresh Native CLI consumer', preserve: true});
  const root = scratch.path;
  const consumer = await releaseConsumerDestination(join(root, 'consumer'), [repository, directory]);
  await mkdir(consumer);
  const prefix = join(consumer, 'global'), host = join(consumer, 'host');
  await mkdir(prefix); await mkdir(host);
  const env = publicConsumerEnvironment(process.env, consumer);
  await mkdir(env.HOME); await mkdir(env.TMPDIR);
  const records = [], registry = await openReleaseTestRegistry([{directory, manifest}]);
  const save = body => writeFile(join(directory, 'installed-ci.json'), `${JSON.stringify(body, null, 2)}\n`);
  const run = async (command, args, options = {}) => {
    try {
      const record = await runNativeInstallCommand(command, args, {cwd: consumer, env, ...options});
      records.push(record); await save({source: source.revision, status: 'running', consumer, records});
      return record;
    } catch (failure) {
      if (failure?.commandRecord) records.push(failure.commandRecord);
      throw failure;
    }
  };
  let receipt, failure, rejected = false;
  try {
    Object.assign(env, {npm_config_registry: registry.url, NO_PROXY: '127.0.0.1,localhost'});
    await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
    await writeFile(env.npm_config_globalconfig, '');
    await run('npm', ['install', '-g', '--prefix', prefix, '--no-audit', '--no-fund',
      `actql@${manifest.cohort.packageVersion}`]);
    const launcher = join(prefix, 'bin/actql');
    const platformRoot = join(prefix, 'lib/node_modules/actql/node_modules/@actql', `cli-${platform}`);
    const binary = join(platformRoot, 'bin/actql-native-client');
    assert.deepEqual(JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8')), artifact);
    assert.equal(hash(await readFile(binary)), artifact.binarySha256);
    assert.equal((await run(launcher, ['version'])).stdout, `${manifest.cohort.packageVersion}\n`);
    await run(launcher, ['--help']); await run(launcher, ['init', '--help']);
    const projects = join(consumer, 'projects'); await mkdir(projects);
    for (const template of [undefined, 'deal-review-mock', 'churn-risk-mock']) {
      for (const existing of [false, true]) {
        const target = join(projects, `${template ?? 'plain'}-${existing ? 'empty' : 'new'}`);
        if (existing) await mkdir(target, {mode: 0o700});
        const before = existing ? await stat(target) : undefined;
        for (let attempt = 0; attempt < 2; attempt++) {
          const args = ['init', ...(template === undefined ? [] : ['--template', template]), target];
          const refusal = await run(launcher, args, {expectedCode: 69});
          assert.match(refusal.stderr, /Packaged Local runtime is unavailable/iu);
          assert.equal(refusal.stdout, '');
          if (existing) {
            assert.deepEqual(await readdir(target), []);
            const after = await stat(target);
            assert.equal(after.ino, before.ino); assert.equal(after.mode, before.mode);
            assert.equal(after.mtimeMs, before.mtimeMs);
          } else await assert.rejects(stat(target), {code: 'ENOENT'});
        }
      }
    }
    // Reuse only normal lifecycle-enabled exact-source tarballs, authenticated
    // by their producer manifest. Copy no product source into this consumer.
    const tarballs = [];
    for (const name of CLIENT_PACKAGES) {
      await packedClientPackage({repository, name, destination: host,
        pack() {throw Error('Native CLI CI requires the original Client producer');}});
      tarballs.push(join(host, `actql-${name}-0.0.0-development.tgz`));
    }
    await writeFile(join(host, 'package.json'), '{"private":true,"type":"module"}\n');
    await run('npm', ['install', '--ignore-scripts', '--engine-strict', '--no-audit', '--no-fund', ...tarballs], {cwd: host});
    for (const name of ['release-native-host.mjs', 'release-native-host-authorization.mjs'])
      await copyFile(join(repository, 'scripts/fixtures', name), join(host, name));
    await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key',
      '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      '-addext', 'extendedKeyUsage=serverAuth,clientAuth'], {cwd: host});
    const nativeHome = join(consumer, 'native-home');
    await mkdir(nativeHome); await mkdir(join(nativeHome, 'tmp'));
    const hostEnv = {...env, NODE_EXTRA_CA_CERTS: join(host, 'remote.crt'),
      ACTQL_TEST_NATIVE_STANDALONE_HOME: nativeHome};
    // The npm launcher is checked above. This existing boundary additionally
    // proves the same installed binary runs without Node/npm on its PATH and
    // acknowledges actual live closed state descriptors before process exit.
    await run(process.execPath, ['release-native-host.mjs', binary],
      {cwd: host, env: hostEnv, state: join(host, 'host-state')});
    // Separately exercise the public npm launcher against fresh Host state.
    // Its fixture resolves the same installed Host packages from the parent
    // consumer, never checkout code or a second product build.
    const launcherHost = join(host, 'launcher-positive'); await mkdir(launcherHost);
    for (const name of ['release-native-host.mjs', 'remote.key', 'remote.crt'])
      await copyFile(join(host, name), join(launcherHost, name));
    await run(process.execPath, ['release-native-host.mjs', launcher], {cwd: launcherHost,
      env: {...env, NODE_EXTRA_CA_CERTS: join(launcherHost, 'remote.crt')}});
    const authorizationEnv = {...env, NODE_EXTRA_CA_CERTS: join(host, 'remote.crt')};
    await run(process.execPath, ['release-native-host-authorization.mjs', binary],
      {cwd: host, env: authorizationEnv});
    assert.equal(hash(await readFile(binary)), artifact.binarySha256);
    assert.deepEqual(checkoutState(repository), source);
    await verifyNativeCliRelease(directory);
    const authorization = requireNativeHostAuthorizationReceipt(
      JSON.parse(await readFile(join(host, 'native-host-authorization.json'), 'utf8')));
    receipt = {source: source.revision, status: 'passed', platform, consumer,
      publicPublication: false, cliVersion: manifest.cohort.packageVersion,
      binarySha256: artifact.binarySha256, registryRequests: registry.requested, records,
      hostAcceptance: {
        nodeFreeBinary: JSON.parse(await readFile(join(host, 'native-host-acceptance.json'), 'utf8')),
        npmLauncher: JSON.parse(await readFile(join(launcherHost, 'native-host-acceptance.json'), 'utf8')),
        authorization,
      },
      scope: ['fresh npm installation', 'npm launcher Remote real Host', 'finite Account refusals',
        'Node-free installed executable', 'closed state descriptors', 'unavailable Local init leaves no files'],
      unverified: ['Linux Local execution', 'mock workflow execution', 'other platforms']};
  } catch (error) {failure = error; rejected = true;}
  try {await registry.close();}
  catch (error) {
    failure = rejected ? new AggregateError([failure, error], 'Installed acceptance and registry cleanup failed') : error;
    rejected = true;
  }
  if (rejected) {
    await save({source: source.revision, status: 'failed', consumer, error: failure?.message, records});
    throw failure;
  }
  // A receipt is successful only after every owned resource has closed.
  await save(receipt);
  scratch.passed();
}

export async function runNativeCliInstalledCi(output) {
  requireNativeCliCiInputs(process.env, checkoutState(repository));
  const destination = resolve(output);
  await mkdir(destination);
  const artifact = join(destination, 'artifact'), release = join(destination, 'release');
  await buildNativeCliArtifact(artifact, {packageVersion: nativeCliTestCohort.packageVersion,
    compileSeconds: 1200});
  await prepareNativeCliRelease(release, [artifact], nativeCliTestCohort);
  await acceptInstalledNativeCli(release);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: ci-native-cli-installed.mjs <new-output-directory>');
  await runNativeCliInstalledCi(process.argv[2]);
}
