// Positive installed acceptance, never an expected refusal or a skip. CI runs
// this independently of source-free acceptance on the same prepared Native
// release. Missing suppliers or approval continuation are failures.
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
import {approvalCallCounts, assertApprovalCallCounts, approvalResources, approvalPhases, assessOrdinaryNativeApprovalSmoke} from './native-approval-performance.mjs';
import {captureNativeMockCommand, mockTemplates, runNativeCliMockScenario} from './native-cli-mock-scenario.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, ...extra] = process.argv.slice(2);
const measureResources = extra.length === 1 && extra[0] === '--measure-approval-resources';
assert(input && (extra.length === 0 || measureResources),
  'usage: test-native-cli-mock-install.mjs <fixed-CLI-RC> [--measure-approval-resources]');
const directory = resolve(input), manifest = await verifyNativeCliRelease(directory);
const source = checkoutState(repository);
assert(source.clean, 'Installed mock acceptance requires clean source');
assert.equal(source.revision, manifest.sourceSha, 'Fixtures and Native artifact must share the fixed source');
const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
assert(manifest.platforms[platform], 'No fixed Native artifact for this platform');
const expectedArtifact = manifest.artifacts.find(value => value.platform === platform);
assert(expectedArtifact?.localRuntime, 'Mock acceptance requires the packaged Local runtime');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-mock-install-',
  label: 'Native mock public workflow external installation'});
const registry = await openReleaseTestRegistry([{directory, manifest}]);
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
  const observedCommand = resources ? '/usr/bin/time' : command;
  const observedArgs = resources ? [...(process.platform === 'darwin'
    ? ['-l', '-p', '-o', resources] : ['--verbose', '--output', resources]), command, ...args] : args;
  let result;
  try {
    const options = {cwd, env, timeout: timeoutMs, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024};
    const captured = command === process.execPath
      ? await captureNativeMockCommand(observedCommand, observedArgs,
        {...options, stderrPath: join(root, `command-${records.length}.stderr`)})
      : await execute(observedCommand, observedArgs, options);
    result = {...captured, code: 0, signal: null};
  } catch (error) {
    result = {code: error.code ?? null, signal: error.signal ?? null,
      killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? '',
      ...(error.exitCode !== undefined ? {childExitCode: error.exitCode} : {})};
  }
  const wallNs = Number(process.hrtime.bigint() - started);
  assert(Number.isSafeInteger(wallNs) && wallNs >= 0);
  const record = {command, args, cwd, timeoutMs, elapsedMs: wallNs / 1e6, wallNs, ...result};
  if (resources && result.code === 0 && result.signal === null) {
    try { record.resources = approvalResources(await readFile(resources, 'utf8'), process.platform); }
    catch (error) { record.resourceObservationIssue = error.message; }
    record.measurement = {sampler: '/usr/bin/time', wallIncludesSampler: true};
  }
  records.push(record);
  // Persist before any assertion, including the first unsupported binding.
  await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
  return record;
}

try {
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
  const packageRoot = join(prefix, 'lib/node_modules/actql');
  const launcher = join(prefix, 'bin/actql');
  assert.deepEqual((await readdir(join(packageRoot, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
  const platformRoot = join(packageRoot, 'node_modules/@actql', `cli-${platform}`);
  const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
  assert.deepEqual(artifact, expectedArtifact);
  const binary = await readFile(join(platformRoot, 'bin/actql-native-client'));
  assert.equal(binary.length, manifest.platforms[platform].binaryBytes);
  assert.equal(createHash('sha256').update(binary).digest('hex'), manifest.platforms[platform].binarySha256);
  env.PATH = join(root, 'empty-path');
  env.ACTQL_NATIVE_TIMINGS = '1';
  env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS = '1';
  for (const template of mockTemplates) scenarios.push(await runNativeCliMockScenario({root, template, launcherTimings: 'required',
    run: (args, cwd) => run(process.execPath, [launcher, ...args], cwd)}));
  assert.equal(scenarios.length, 2, 'Both README and Quickstart must finish without skips');
  for (const scenario of scenarios) {
    const approvals = scenario.commands.filter(record => record.args.includes('approve'));
    assert.equal(approvals.length, 1);
    const approval = approvals[0];
    approval.validationCalls = approvalCallCounts(approval);
    approval.phases = approvalPhases(approval, {requireCompleted: false});
    assertApprovalCallCounts(approval.validationCalls, approval.acceptance.writes.length);
  }
  assert.deepEqual(await readFile(join(platformRoot, 'bin/actql-native-client')), binary);
  assert.deepEqual(checkoutState(repository), source);
  receipt = {version: 'actql-native-cli-install-acceptance/0.1', scope: 'local-mock-approval-recovery',
    cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null, artifact,
    scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
    scenarioSha256: createHash('sha256').update(await readFile(new URL('./native-cli-mock-scenario.mjs', import.meta.url))).digest('hex'),
    cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
    registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
    publicRegistryPublication: 'not-tested', scenarios, records,
    unverified: ['live providers', 'crash or power-loss fault injection', 'other platforms']};

} finally {
  await registry.close();
}
// Successful evidence is published only after every child has exited and the
// private registry has confirmed closure. Cleanup failure is not acceptance.
const receiptFile = join(directory, `mock-install-${platform}-${Date.now()}.json`);
if (!measureResources) receipt.approvalSmoke = assessOrdinaryNativeApprovalSmoke(receipt.scenarios);
await writeFile(receiptFile, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
// Keep the completed original workflows and slow timings before failing CI.
// Resource-enabled formal collection retains every sample for its own assessor.
if (!measureResources) assert.equal(receipt.approvalSmoke.status, 'passed', receipt.approvalSmoke.failures.join('; '));
scratch.passed();
console.log(`Installed Native mock approval/recovery passed: ${receiptFile}`);
