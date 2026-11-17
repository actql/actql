// Positive installed acceptance, never an expected refusal or a skip. CI runs
// this independently of source-free acceptance on the same prepared Native
// release. Missing suppliers or approval continuation are failures.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {approvalCallCounts, assertApprovalCallCounts, approvalResources, approvalPhases, publishNativeApprovalReceipt, nativeApprovalObservationOptions,
  nativeApprovalObservedCommand, retainNativeApprovalObservation, observeNativeMockHarnessPhase} from './native-approval-performance.mjs';
import {captureNativeMockCommand, mockTemplates, runNativeCliMockScenario} from './native-cli-mock-scenario.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, ...extra] = process.argv.slice(2);
const {measureResources, diagnoseSyscalls} = nativeApprovalObservationOptions(extra, process.platform);
assert(input, 'usage: test-native-cli-mock-install.mjs <fixed-CLI-RC> [--measure-approval-resources] [--diagnose-approval-syscalls]');
const syscallTool = diagnoseSyscalls ? {
  path: '/usr/bin/strace',
  sha256: createHash('sha256').update(await readFile('/usr/bin/strace')).digest('hex'),
  version: (await promisify(execFile)('/usr/bin/strace', ['--version'], {encoding: 'utf8', timeout: 5000})).stdout.trim(),
} : undefined;
const harnessPhases = [];
const observe = (phase, action, template) => observeNativeMockHarnessPhase(harnessPhases, phase, action, template);
const directory = resolve(input), manifest = await observe('release-verification', async () => await verifyNativeCliRelease(directory));
const {source, glibc, platform, expectedArtifact} = await observe('source-platform-admission', () => {
  const source = checkoutState(repository);
  assert(source.clean, 'Installed mock acceptance requires clean source');
  assert.equal(source.revision, manifest.sourceSha, 'Fixtures and Native artifact must share the fixed source');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  assert(manifest.platforms[platform], 'No fixed Native artifact for this platform');
  const expectedArtifact = manifest.artifacts.find(value => value.platform === platform);
  assert(expectedArtifact?.localRuntime, 'Mock acceptance requires the packaged Local runtime');
  return {source, glibc, platform, expectedArtifact};
});
const scratch = await observe('scratch-creation', () => createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-mock-install-',
  label: 'Native mock public workflow external installation'}));
const registry = await observe('registry-open', () => openReleaseTestRegistry([{directory, manifest}]));
const root = scratch.path, prefix = join(root, 'global'), records = [], scenarios = [];
// No inherited account, provider key, Host selection, library override, SDK or
// private runtime path may rescue a missing installed Native implementation.
const env = {PATH: process.env.PATH, HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'), LANG: 'C.UTF-8',
  npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
  npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
  npm_config_proxy: '', npm_config_https_proxy: '', npm_config_update_notifier: 'false',
  NO_PROXY: '127.0.0.1,localhost'};
const execute = promisify(execFile);
let receipt;
async function run(command, args, cwd = root, timeoutMs = 120_000) {
  const started = process.hrtime.bigint();
  const resources = measureResources && command === process.execPath && args[1] === 'approve'
    ? join(root, `approval-resources-${records.length}.txt`) : undefined;
  const syscalls = resources && diagnoseSyscalls ? join(root, `approval-syscalls-${records.length}.txt`) : undefined;
  const observed = nativeApprovalObservedCommand(command, args, {platform: process.platform, resources, syscalls});
  let result;
  try {
    const options = {cwd, env, timeout: timeoutMs, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024};
    const captured = command === process.execPath
      ? await captureNativeMockCommand(observed.command, observed.args,
        {...options, stderrPath: join(root, `command-${records.length}.stderr`)})
      : await execute(observed.command, observed.args, options);
    result = {...captured, code: 0, signal: null};
  } catch (error) {
    result = {code: error.code ?? null, signal: error.signal ?? null,
      killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? '',
      ...(error.exitCode !== undefined ? {childExitCode: error.exitCode} : {})};
  }
  const wallNs = Number(process.hrtime.bigint() - started);
  assert(Number.isSafeInteger(wallNs) && wallNs >= 0);
  const record = {command, args, cwd, timeoutMs, elapsedMs: wallNs / 1e6, wallNs, ...result};
  if (resources) {
    record.observationFiles = [];
    for (const [kind, file] of [['resources', resources], ['syscalls', syscalls]]) {
      if (!file) continue;
      try {
        record.observationFiles.push(await retainNativeApprovalObservation(file,
          join(directory, `approval-${kind}-${basename(root)}-${records.length}.txt`), kind));
      } catch (error) { record.resourceObservationIssue ??= error.message; }
    }
    if (result.code === 0 && result.signal === null) {
      try { record.resources = approvalResources(await readFile(resources, 'utf8'), process.platform); }
      catch (error) { record.resourceObservationIssue ??= error.message; }
    }
    record.measurement = {sampler: '/usr/bin/time', wallIncludesSampler: true,
      ...(diagnoseSyscalls ? {diagnosticOnly: true, acceptanceEligible: false,
        instrumentation: 'strace -f -c; Node launcher and waited Native child'} : {})};
  }
  records.push(record);
  // Persist before any assertion, including the first unsupported binding.
  await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
  return record;
}

try {
  await observe('installation', async () => {
    await mkdir(prefix);
    await mkdir(env.HOME);
    await mkdir(env.TMPDIR);
    await mkdir(join(root, 'empty-path'));
    await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
    await writeFile(join(root, 'npmrc-global'), '');
    const installed = await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts',
      '--no-audit', '--no-fund', `actql@${manifest.cohort.packageVersion}`]);
    assert.equal(installed.code, 0, installed.stderr);
    assert.equal(installed.signal, null);
  });
  const packageRoot = join(prefix, 'lib/node_modules/actql');
  const launcher = join(prefix, 'bin/actql');
  const {platformRoot, artifact, binary} = await observe('installed-package-admission', async () => {
    assert.deepEqual((await readdir(join(packageRoot, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
    const platformRoot = join(packageRoot, 'node_modules/@actql', `cli-${platform}`);
    const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
    assert.deepEqual(artifact, expectedArtifact);
    const binary = await readFile(join(platformRoot, 'bin/actql-native-client'));
    assert.equal(binary.length, manifest.platforms[platform].binaryBytes);
    assert.equal(createHash('sha256').update(binary).digest('hex'), manifest.platforms[platform].binarySha256);
    return {platformRoot, artifact, binary};
  });
  env.PATH = join(root, 'empty-path');
  env.ACTQL_NATIVE_TIMINGS = '1';
  env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS = '1';
  for (const template of mockTemplates) scenarios.push(await observe('scenario', () => runNativeCliMockScenario({root, template, launcherTimings: 'required',
    run: (args, cwd) => run(process.execPath, [launcher, ...args], cwd)}), template));
  assert.equal(scenarios.length, 2, 'Both README and Quickstart must finish without skips');
  for (const scenario of scenarios) {
    const approvals = scenario.commands.filter(record => record.args.includes('approve'));
    assert.equal(approvals.length, 1);
    const approval = approvals[0];
    approval.validationCalls = approvalCallCounts(approval);
    approval.phases = approvalPhases(approval, {requireCompleted: false});
    assertApprovalCallCounts(approval.validationCalls, approval.acceptance.writes.length);
  }
  await observe('installed-integrity', async () => {
    assert.deepEqual(await readFile(join(platformRoot, 'bin/actql-native-client')), binary);
    assert.deepEqual(checkoutState(repository), source);
  });
  receipt = {version: 'actql-native-cli-install-acceptance/0.1', scope: 'local-mock-approval-recovery',
    cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null, artifact,
    scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
    scenarioSha256: createHash('sha256').update(await readFile(new URL('./native-cli-mock-scenario.mjs', import.meta.url))).digest('hex'),
    cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
    publicRegistryPublication: 'not-tested', harnessPhases, scenarios, records,
    ...(diagnoseSyscalls ? {diagnosticOnly: true, acceptanceEligible: false,
      diagnostic: {purpose: 'native-approval-syscall-summary', tool: syscallTool,
        qualification: 'one instrumented workflow; not formal latency or a replacement for failed samples'}} : {}),
    unverified: ['live providers', 'crash or power-loss fault injection', 'other platforms']};

} finally {
  await observe('registry-close', async () => { await registry.close(); });
}
// Successful evidence is published only after every child has exited and the
// private registry has confirmed closure. Cleanup failure is not acceptance.
const receiptFile = join(directory, `${diagnoseSyscalls ? 'mock-syscalls' : 'mock-install'}-${platform}-${Date.now()}.json`);
await publishNativeApprovalReceipt({receipt, receiptFile, measureResources, scratch});
