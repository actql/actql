// One fresh installed Native resource case. Failed producers remain failed;
// this collector grants no formal acceptance or permission to replay a Run.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {mkdir, readFile, writeFile, realpath} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {promisify} from 'node:util';
import {observeNativeResourceOperatorShape} from './native-source-free-resource-shape.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const errorData = error => ({name: error?.name, code: error?.code,
  message: String(error?.message ?? error).slice(0, 2048)});

// The failed record is valid input here. Approval-only parsers require exit0
// and select other phases; neither can stand in for this original failure.
export function nativeSourceFreeShapeDiagnostics(stderr, launcherEnvelope) {
  const native = launcherEnvelope(stderr, 'required').native;
  const rows = prefix => native.split('\n').filter(line => line.startsWith(prefix))
    .map(line => JSON.parse(line.slice(prefix.length)));
  const metadata = rows('ACTQL_NATIVE_TIMINGS ');
  assert.equal(metadata.length, 1, 'One exited Native process required');
  const meta = metadata[0];
  assert(Number.isSafeInteger(meta.pid) && meta.pid > 0);
  assert.equal(meta.overflow, false);
  for (const name of ['initializing_drops', 'invalid_tags', 'invalid_amounts',
    'clock_failures', 'stack_overflows']) assert.equal(meta[name], 0, name);
  const counters = rows('ACTQL_NATIVE_COUNTER '), byTag = new Map();
  for (const value of counters) {
    assert(Number.isInteger(value.tag) && value.tag >= 0 && value.tag < 70);
    assert(Number.isSafeInteger(value.count) && value.count >= 0 && !byTag.has(value.tag));
    byTag.set(value.tag, value.count);
  }
  assert.equal(byTag.size, 70, 'Complete existing counter stream required');
  const phases = rows('ACTQL_NATIVE_PHASE ').filter(row => row.tag === 3 || row.tag === 4);
  assert.equal(phases.length, 2); assert.equal(new Set(phases.map(row => row.tag)).size, 2);
  for (const row of phases) {
    assert(Number.isSafeInteger(row.begins) && row.begins >= 0 && row.begins === row.ends);
    assert.equal(row.active, 0); assert.equal(row.unmatched_end, 0);
    assert(Number.isSafeInteger(row.inclusive_ns) && row.inclusive_ns >= 0);
    assert(Number.isSafeInteger(row.exclusive_ns) && row.exclusive_ns >= 0 &&
      row.exclusive_ns <= row.inclusive_ns);
  }
  const stageTag = byTag.get(10), familyTag = byTag.get(11), causeTag = byTag.get(12);
  const publication = {available: stageTag === 11 && familyTag >= 9001 && familyTag <= 9009,
    stageTag, familyTag, causeTag, ledgerTag: byTag.get(13)};
  // These are the existing closed diagnostic mappings, not runtime enum
  // ordinals. Other causes remain exact scalar DATA without a guessed label.
  if (publication.available && familyTag === 9005 && causeTag === 5208) {
    publication.path = 'Store.PublicationPreparation.Owner.Capacity.Resource';
    if (publication.ledgerTag === 6) publication.resource = 'RetentionLimit';
    if (publication.ledgerTag === 7) publication.resource = 'ExecutionLimit';
  }
  return {complete: true, metadata: meta, counters, phases, publication,
    phaseScope: 'Process-local monotonic wall; phase3 includes phase4. No CPU/RSS or additive phase claim.'};
}

export function nativeShapeCommandEnvironment(base, root, diagnostic) {
  // Reuse only basic process locale facts. Native libraries/runtime come from
  // the admitted installed package, never ambient ACTQL/Node/loader overlays.
  return {HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'), PATH: join(root, 'empty-path'),
    LANG: base.LANG ?? 'C.UTF-8', TZ: base.TZ ?? 'UTC',
    ...(diagnostic ? {ACTQL_NATIVE_TIMINGS: '1'} : {})};
}

export async function nativeSourceFreeShapeDiagnostic({root, normal, binding, output, collectorSource}) {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  assert.notEqual(process.getuid(), 0, 'Use the normal hosted runner UID');
  root = await realpath(root); normal = await realpath(normal); output = resolve(output);
  const load = path => import(pathToFileURL(join(root, path)).href);
  const {verifyNativeCliRelease} = await load('scripts/native-cli-release.mjs');
  const {checkoutState} = await load('scripts/packed-client-packages.mjs');
  const {prepareOrdinaryNativePerformanceConsumer} = await load('scripts/ordinary-operation-packages.mjs');
  const {inventory} = await load('scripts/package-release.mjs');
  const {admitInstalledLocalRuntime} = await load('packages/native-cli/lib/local-runtime.mjs');
  const {captureNativeMockCommand, nativeLauncherEnvelope} = await load('scripts/native-cli-mock-scenario.mjs');
  const {prepareNativeNumericOperator, nativeResourceShapeFixtures, verifyNativeResourceRows} =
    await load('scripts/test-native-cli-source-free-install.mjs');
  const manifest = await verifyNativeCliRelease(normal), source = checkoutState(root);
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact original build source required');
  const original = JSON.parse(await readFile(binding, 'utf8'));
  // Reuse the existing failed-producer authentication/extraction boundary.
  // Its purpose labels artifact eligibility only; no CPU profiler runs here.
  assert.equal(original.purpose, 'native-approval-cpu-diagnostic');
  assert.equal(original.diagnosticOnly, true); assert.equal(original.acceptanceEligible, false);
  assert.equal(original.artifactDigest, `sha256:${original.archiveSha256}`);
  assert.equal(original.sourceSha, source.revision);
  assert.equal(hash(await readFile(join(normal, 'release.json'))), original.manifestSha256);
  assert.match(collectorSource, /^[a-f0-9]{40}$/u);
  await mkdir(output, {mode: 0o700});
  const privateRoot = join(output, 'private'); await mkdir(privateRoot, {mode: 0o700});
  const commandsRoot = join(output, 'commands'); await mkdir(commandsRoot, {mode: 0o700});
  const report = {purpose: 'native-source-free-shape-diagnostic', diagnosticOnly: true,
    acceptanceEligible: false, collectorSourceSha: collectorSource, sourceSha: source.revision,
    collectorSha256: hash(await readFile(fileURLToPath(import.meta.url))),
    helperSha256: hash(await readFile(new URL('./native-source-free-resource-shape.mjs', import.meta.url))),
    artifactBinding: original, case: 'small-input-large-output', commandTimeoutMs: 180000,
    requestMemory: {retainedBytes: 536870912, executionBytes: 536870912},
    complete: false, commands: [], privateStateRetainedLocally: true,
    privateStateDirectory: 'private/project', cleanup: [],
    qualification: 'One fresh Run; same original binary and fixture limits. No formal latency, physical ACK, or failed-Run replay claim.'};
  let installed, platformRoot;
  const auditInstalled = async () => {
    await verifyNativeCliRelease(normal);
    assert.deepEqual(checkoutState(root), source, 'Original source changed');
    for (const pkg of manifest.packages) {
      const directory = pkg.name === 'actql' ? installed : join(installed, 'node_modules', pkg.name);
      assert.deepEqual(await inventory(directory, '', {ignoreInstalledDependencies: true}), pkg.files,
        `Installed original changed: ${pkg.name}`);
    }
  };
  try {
    const prepared = await prepareOrdinaryNativePerformanceConsumer({packages: normal,
      sourceSha: source.revision, output: join(privateRoot, 'installation'),
      install: (args, options) => {
        const env = {...options.env};
        for (const key of Object.keys(env)) if (/^(?:ACTQL_|DYLD_)/u.test(key) ||
          ['NODE_PATH', 'NODE_OPTIONS', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'MOON_HOME'].includes(key)) delete env[key];
        return promisify(execFile)('npm', args, {...options, env, timeout: 120000, maxBuffer: 8 * 1024 ** 2});
      }});
    installed = prepared.consumer;
    const platform = 'linux-x64-gnu', expected = manifest.artifacts.find(value => value.platform === platform);
    assert(expected?.localRuntime);
    platformRoot = join(installed, 'node_modules/@actql/cli-' + platform);
    assert.deepEqual(JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8')), expected);
    const localRuntime = admitInstalledLocalRuntime({root: platformRoot, metadata: expected.localRuntime,
      expected: {sourceSha: manifest.sourceSha, platform, localRuntimeSha256: expected.localRuntime.sha256}});
    await auditInstalled(); report.installedPinsBefore = true;
    for (const name of ['home', 'tmp', 'empty-path', 'output']) await mkdir(join(privateRoot, name));
    const assets = {};
    for (const asset of localRuntime.assets) assets[asset.role] = await readFile(join(platformRoot, asset.path), 'utf8');
    const libraries = Object.fromEntries(localRuntime.libraries.map(item => [item.role, join(platformRoot, item.path)]));
    const project = join(output, report.privateStateDirectory);
    const selected = await prepareNativeNumericOperator({project, assets, libraries,
      runtimeWire: await readFile(join(platformRoot, expected.localRuntime.path), 'utf8'), maxRows: 1024});
    const launcher = join(installed, 'bin/actql.mjs');
    const cli = async (args, cwd) => {
      const operation = args[args.indexOf('operator.json') + 1];
      assert(['adopt', 'run', 'result', 'status'].includes(operation));
      const ordinal = report.commands.length, name = String(ordinal).padStart(3, '0') + '-' + operation;
      const started = process.hrtime.bigint();
      let record;
      try {
        const result = await captureNativeMockCommand(process.execPath, [launcher, ...args], {cwd,
          env: nativeShapeCommandEnvironment(process.env, privateRoot, operation === 'run'),
          stderrPath: join(commandsRoot, name + '.stderr'), timeout: 180000});
        record = {...result, code: 0, signal: null, killed: false};
      } catch (error) {
        record = {stdout: error.stdout ?? '', stderr: error.stderr ?? '',
          code: error.exitCode ?? error.code ?? null, signal: error.signal ?? null,
          killed: error.killed ?? false, observerError: errorData(error)};
      }
      record.wallNs = Number(process.hrtime.bigint() - started);
      record.operation = operation;
      if (operation === 'run') try {record.native = nativeSourceFreeShapeDiagnostics(record.stderr, nativeLauncherEnvelope);}
      catch (error) {record.diagnosticFailure = errorData(error);}
      await writeFile(join(commandsRoot, name + '.stdout'), record.stdout, {flag: 'wx', mode: 0o600});
      report.commands.push(record);
      await writeFile(join(commandsRoot, name + '.json'), JSON.stringify(record, null, 2) + '\n', {flag: 'wx', mode: 0o600});
      if (record.code !== 0 || record.signal !== null) throw Object.assign(new Error('OriginalNativeShapeCommandFailed'),
        {code: record.code, command: ordinal});
      return record;
    };
    const adopted = await cli([...selected.configuration, 'adopt', '--initialize-signing', '--json'], project);
    assert.equal(JSON.parse(adopted.stdout).kind, 'local_host_adopted');
    const fixture = nativeResourceShapeFixtures().find(value => value.id === report.case);
    assert(fixture); assert.equal(fixture.expectedRows.length, 512);
    report.observation = await observeNativeResourceOperatorShape({project, cli,
      configuration: selected.configuration, fixture, outputDirectory: join(privateRoot, 'output'),
      verifyRows: verifyNativeResourceRows});
    assert.equal(report.commands.filter(value => value.operation === 'run').length, 1);
    assert.equal(report.commands.find(value => value.operation === 'run').native?.complete, true,
      'Original successful command needs complete timing diagnostics');
    report.complete = true;
  } catch (error) {report.failure = errorData(error);}
  finally {
    if (installed !== undefined) try {await auditInstalled(); report.installedPinsAfter = true;}
    catch (error) {report.cleanup.push(errorData(error)); report.complete = false;}
    await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  }
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const values = {};
  for (let index = 2; index < process.argv.length; index += 2) {
    const option = process.argv[index], value = process.argv[index + 1];
    assert(['--root', '--normal', '--binding', '--output', '--collector-source'].includes(option) && value);
    assert(!Object.hasOwn(values, option.slice(2))); values[option.slice(2)] = value;
  }
  assert.equal(Object.keys(values).length, 5);
  const report = await nativeSourceFreeShapeDiagnostic({...values, collectorSource: values['collector-source']});
  process.exitCode = report.complete ? 0 : 1;
}
