// Actual public Native bytes and direct Node-free child, with the existing
// separately installed Remote Host fixture. No product fallback or publisher.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyReleaseSet} from './release-set.mjs';
import {downloadNativeReleaseTarget, observeNpmReleaseTarget} from './release-registry.mjs';
import {publicConsumerEnvironment, publicInstallCommand, releaseConsumerDestination, verifyPublicConsumer} from './release-public-install.mjs';
import {nativeReleaseInstallSelection, nativeStandaloneEnvironment, extractNativeStandaloneDownload,
  verifyNativeStandaloneInstallation} from './release-native-install.mjs';
import {platformKey, macOSProductVersion, admitInstalledBinary} from '../packages/native-cli/bin/actql.mjs';
import {observeChildFds} from './test-python-release-install.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

export async function runNativeInstallCommand(command, args, {cwd, env, state, expectedCode = 0, expectedError} = {}) {
  let observation = Promise.resolve(), childRecord;
  await new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, {cwd, env, stdio: ['pipe', 'pipe', 'pipe']});
    childRecord = {command, args, pid: child.pid ?? null, startedAt: new Date().toISOString(), stdout: '', stderr: ''};
    let bytes = 0, lines = '', observing = false;
    const timer = setTimeout(() => {childRecord.terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 180_000);
    child.stdin.on('error', failure => {childRecord.stdinFailure = failure.code;});
    child.on('error', failure => {childRecord.spawnFailure = failure.code;});
    const output = (chunk, error) => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) {childRecord.terminationReason = 'output-limit'; child.kill('SIGTERM'); return;}
      if (error) {childRecord.stderr += chunk; return;}
      childRecord.stdout += chunk; lines += chunk;
      let end;
      while ((end = lines.indexOf('\n')) !== -1) {
        const line = lines.slice(0, end); lines = lines.slice(end + 1);
        if (!state) continue;
        let body; try {body = JSON.parse(line);} catch {continue;}
        if (body.stage === 'close-observation-ack') {childRecord.closeObservationAcknowledged = body.pid === child.pid; continue;}
        if (body.stage !== 'closed' || observing) continue;
        observing = true;
        observation = (async () => {
          assert.equal(body.pid, child.pid); assert.equal(body.clientCloseReturned, true); assert.equal(body.hostCloseReturned, true);
          childRecord.close = await observeChildFds(child, state); child.stdin.end('observed\n');
        })().catch(failure => {childRecord.closeObservationFailure = failure.message; child.stdin.end('unobserved\n');});
      }
    };
    child.stdout.on('data', chunk => output(chunk, false)); child.stderr.on('data', chunk => output(chunk, true));
    child.once('close', async (code, signal) => {
      clearTimeout(timer); await observation;
      Object.assign(childRecord, {code, signal, endedAt: new Date().toISOString()});
      try {
        if (expectedError !== undefined) {assert.equal(childRecord.spawnFailure, expectedError); assert.notEqual(code, 0); assert.equal(signal, null);}
        else {assert.equal(code, expectedCode, childRecord.stderr); assert.equal(signal, null); assert(!childRecord.spawnFailure);}
        assert(!childRecord.terminationReason);
        if (state) {
          assert.equal(childRecord.close?.scopedStateFd0, true); assert.equal(childRecord.closeObservationAcknowledged, true);
          assert(!childRecord.closeObservationFailure && !childRecord.stdinFailure);
        }
        resolveRun();
      } catch (failure) {failure.commandRecord = childRecord; rejectRun(failure);}
    });
    if (!state) child.stdin.end();
  });
  return childRecord;
}

export async function runNativeStandaloneInstall(args) {
  const selection = nativeReleaseInstallSelection(args), fixed = await verifyReleaseSet(selection.directory,
    {expectedSha256: selection.manifestSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === selection.targetId);
  const hostTarget = fixed.manifest.request.targets.find(value => value.id === selection.hostTargetId);
  assert.equal(target?.ecosystem, 'native'); assert(target.profiles.includes('remote'));
  assert.equal(hostTarget?.ecosystem, 'npm'); assert.equal(hostTarget.destination, 'https://registry.npmjs.org/');
  const hostCohort = fixed.manifest.cohorts.find(value => value.targetId === hostTarget.id); assert.equal(hostCohort.kind, 'node-npm');
  const hostManifest = JSON.parse(await readFile(join(selection.directory, hostCohort.path)));
  publicInstallCommand(hostManifest, 'node');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc}); assert(target.platforms.includes(platform));
  const facts = {glibc, macOS: process.platform === 'darwin' ? macOSProductVersion() : undefined};
  const root = await releaseConsumerDestination(selection.consumer, [repository, selection.directory]);
  await mkdir(root, {mode: 0o700});
  const records = [], save = (name, body) => writeFile(join(root, name), `${JSON.stringify(body, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  const run = async (command, argv, options) => {
    try {const record = await runNativeInstallCommand(command, argv, options); records.push(record); await save(`command-${records.length}.json`, record); return record;}
    catch (failure) {if (failure.commandRecord) {records.push(failure.commandRecord); await save(`command-${records.length}.json`, failure.commandRecord);} throw failure;}
  };
  try {
    const {download, standalone} = await downloadNativeReleaseTarget(selection.directory, fixed.sha256, target.id, join(root, 'downloads'));
    const archive = standalone.archives.find(value => value.platform === platform);
    const artifact = JSON.parse(standalone.origin.manifest).artifacts.find(value => value.platform === platform);
    const installed = await extractNativeStandaloneDownload(join(root, 'downloads', archive.file), join(root, 'installed'),
      archive, artifact, standalone.sourceSha, standalone.packageVersion, facts);
    const env = nativeStandaloneEnvironment(process.env, root);
    await mkdir(env.HOME); await mkdir(env.TMPDIR);
    const version = await run(installed.executable, ['--version'], {cwd: root, env});
    assert.equal(version.stdout, `${standalone.packageVersion}\n`); assert.equal(version.stderr, '');
    const help = await run(installed.executable, ['--help'], {cwd: root, env});
    assert.match(help.stdout, /Usage: actql-native-client/u); assert.equal(help.stderr, '');
    await run(installed.executable, ['--actql-invalid-release-option'], {cwd: root, env, expectedCode: 2});
    await run(join(root, 'missing-native-binary'), ['--version'], {cwd: root, env, expectedError: 'ENOENT'});
    const originalBinary = await readFile(installed.executable), corrupted = Buffer.from(originalBinary); corrupted[0] ^= 1;
    assert.throws(() => admitInstalledBinary({key: platform, expected: artifact, metadata: artifact, binary: corrupted, ...facts}), /identity mismatch/u);
    const audit = () => verifyNativeStandaloneInstallation(installed.directory, archive, artifact, standalone.sourceSha, standalone.packageVersion, facts);
    await audit();
    const host = join(root, 'remote-host'); await mkdir(host);
    const hostEnv = publicConsumerEnvironment(process.env, host);
    for (const path of [hostEnv.HOME, hostEnv.TMPDIR]) await mkdir(path);
    await writeFile(hostEnv.npm_config_userconfig, 'registry=https://registry.npmjs.org/\n'); await writeFile(hostEnv.npm_config_globalconfig, '');
    await writeFile(join(host, 'package.json'), '{"private":true,"type":"module"}\n');
    const observeHost = async label => {
      const observation = await observeNpmReleaseTarget(selection.directory, fixed.sha256, hostTarget.id);
      await save(`host-public-${label}.json`, observation); assert(observation.observations.every(value => value.state === 'present'));
    };
    await observeHost('before');
    await run('npm', ['--version'], {cwd: host, env: hostEnv});
    await run('npm', publicInstallCommand(hostManifest, 'node'), {cwd: host, env: hostEnv});
    const hostAudit = await verifyPublicConsumer(host, hostManifest, 'node');
    const fixture = join(repository, 'scripts/fixtures/release-native-host.mjs'); await copyFile(fixture, join(host, 'host-acceptance.mjs'));
    await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key', '-out', 'remote.crt',
      '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      '-addext', 'extendedKeyUsage=serverAuth,clientAuth'], {cwd: host, env: hostEnv});
    const nativeHome = join(root, 'native-remote-home'); await mkdir(nativeHome); await mkdir(join(nativeHome, 'tmp'));
    hostEnv.ACTQL_TEST_NATIVE_STANDALONE_HOME = nativeHome;
    hostEnv.NODE_EXTRA_CA_CERTS = join(host, 'remote.crt');
    await run(process.execPath, ['host-acceptance.mjs', installed.executable], {cwd: host, env: hostEnv, state: join(host, 'host-state')});
    await verifyPublicConsumer(host, hostManifest, 'node'); await observeHost('after'); await audit();
    await verifyReleaseSet(selection.directory, {expectedSha256: fixed.sha256});
    const result = {schemaVersion: 'actql-native-public-install/0.1', manifestSha256: fixed.sha256,
      targetId: target.id, hostTargetId: hostTarget.id, platform, facts, download,
      installed, hostAudit, nodeSupervisor: process.version, nativeEnvironment: env,
      fixtureSha256: sha(await readFile(fixture)), records,
      acceptedScope: 'only completed direct Native --version/help/refusal and original Remote Host fixture; Node-free Native child PATH; separate public Node Host installation',
      unverified: ['Local execution/bootstrap/approval', 'standard Project/README CLI', 'other platforms', 'npm Native launcher installation', 'full fault matrix', 'owner approval/publication authority']};
    await save('result.json', result); return result;
  } catch (failure) {await save('failure.json', {status: 'incomplete', message: failure.message, records}); throw failure;}
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  console.log(JSON.stringify(await runNativeStandaloneInstall(process.argv.slice(2)), null, 2));
