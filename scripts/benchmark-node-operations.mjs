// Run only against a separately prepared, source-qualified ordinary installation.
// No preload, package preparation, product overlay, internal Host port or resend.
import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {appendFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {arch, platform, release, cpus, totalmem} from 'node:os';
import {dirname, join, relative, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assessLatency, collectOperationSamples} from './operation-performance.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function nodeBenchmarkInstrumentation({execArgv = process.execArgv,
  nodeOptions = process.env.NODE_OPTIONS ?? '', coverage = process.env.NODE_V8_COVERAGE} = {}) {
  // Known startup instrumentation is evidence against unprofiled acceptance.
  // This is not whole-runtime provenance or hostile embedding detection.
  const flags = [...execArgv, nodeOptions].join(' ');
  return {profiled: /--(?:cpu-prof|heap-prof|prof|inspect|perf-basic-prof)(?:[=\s-]|$)/u.test(flags) || Boolean(coverage)};
}
export function nodeWarmProtocol(mode) {
  assert(['diagnostic', 'final'].includes(mode));
  return {entry: 'ordinary open/stateDir', mode, priorState: 'new empty directory',
    seed: {source: 'SELECT 1 AS id', format: 'sql', expected: [{id: 1}], successfulRuns: 1},
    operationOrder: ['warm-select', 'warm-result', 'warm-status'], samplesPerOperation: mode === 'final' ? 100 : 3,
    diagnosticContinuation: mode === 'diagnostic' ? 'verified success only; stop each slow family' : 'none',
    newShortQueries: 'one per warm-select sample', savedReads: 'same original seed Run',
    status: 'same original revision after initial status observation', close: 'await original Client in finally'};
}
// One explicit experiment definition lets warm and process measurements share
// the assessor's cohort/environment/history binding without accepting arbitrary
// successful reports from different histories. Warm-only callers stay valid.
export function nodeOperationProtocol(mode) {
  return {warm: nodeWarmProtocol(mode), process: {
    samplesPerOperation: mode === 'final' ? 30 : 3,
    coldExisting: 'one new successful seed Run; distinct child per original saved Result read',
    firstInit: 'distinct empty state and actual child per SELECT/Result/awaited close',
    wall: 'parent launch through natural child exit, including import/open/operation/close',
    cpu: 'actual child process; separate workers and subprocesses excluded',
    failedOrUnknown: 'retain sample and stop; never replay the failed Run',
  }};
}
export async function verifyNodeBenchmarkPackages(manifest, manifestPath, consumer) {
  assert(Array.isArray(manifest.packages) && manifest.packages.length > 0);
  assert(manifest.packages.some(row => row.name === '@actql/node'));
  const observations = [], names = new Set();
  for (const pkg of manifest.packages) {
    assert(/^(?:@actql\/)?[a-z0-9-]+$/u.test(pkg.name) && !names.has(pkg.name));
    names.add(pkg.name);
    assert.equal(pkg.file, pkg.file.split('/').at(-1));
    const tar = await readFile(join(dirname(manifestPath), pkg.file));
    assert.equal(tar.length, pkg.bytes); assert.equal(hash(tar), pkg.sha256);
    assert.equal('sha512-' + createHash('sha512').update(tar).digest('base64'), pkg.integrity);
    const base = join(consumer, 'node_modules', pkg.name), files = [];
    async function visit(dir) {
      assert(!(await lstat(dir)).isSymbolicLink(), 'Installed package cannot be a source symlink');
      for (const name of (await readdir(dir)).sort()) {
        const file = join(dir, name), st = await lstat(file);
        assert(!st.isSymbolicLink(), 'Installed product payload cannot be linked');
        if (st.isDirectory()) await visit(file);
        else {
          assert(st.isFile()); const data = await readFile(file);
          files.push({path: relative(base, file), bytes: data.length, mode: st.mode & 0o777, sha256: hash(data)});
        }
      }
    }
    await visit(base);
    const sort = rows => rows.toSorted((a, b) => a.path.localeCompare(b.path));
    assert.deepEqual(sort(files), sort(pkg.files));
    observations.push({package: pkg.name, files});
  }
  return observations;
}
export async function runNodeWarmBenchmark({manifestPath, consumer, output, controlsPath, mode = 'diagnostic'}) {
  assert(['diagnostic', 'final'].includes(mode));
  consumer = resolve(consumer); output = resolve(output);
  const manifestBytes = await readFile(manifestPath), manifest = JSON.parse(manifestBytes);
  const controls = JSON.parse(await readFile(controlsPath));
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(controls.sourceSha, manifest.sourceSha);
  assert.equal(controls.cohortSha256, hash(manifestBytes));
  const actualEnvironment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  for (const [key, value] of Object.entries(actualEnvironment)) assert.equal(controls.environment[key], value, key);
  const combined = nodeOperationProtocol(mode);
  const protocol = controls.historyProtocolSha256 === hash(Buffer.from(JSON.stringify(combined)))
    ? combined : nodeWarmProtocol(mode);
  assert.equal(controls.historyProtocolSha256, hash(Buffer.from(JSON.stringify(protocol))));
  assert(['isolated', 'concurrent'].includes(controls.load));
  const before = await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  await mkdir(output, {mode: 0o700}); // An existing benchmark directory is never reused.
  const stateId = join(output, 'new-state'), hostId = randomUUID();
  const identity = {cohortSha256: hash(manifestBytes),
    fixtureSha256: hash(Buffer.from('SELECT 1 AS id\n[{"id":1}]\n')), hostId};
  const environmentSha256 = hash(Buffer.from(JSON.stringify(controls.environment)));
  const report = {sourceSha: manifest.sourceSha, cohortSha256: identity.cohortSha256, environmentSha256,
    historyProtocolSha256: controls.historyProtocolSha256, mode, ordinaryPackageManifest: manifestPath,
    observedEnvironment: actualEnvironment,
    historyProtocol: protocol,
    load: controls.load, latency: [], diagnosticFindings: [], functional: {cohortSha256: identity.cohortSha256,
      environmentSha256, historyProtocolSha256: controls.historyProtocolSha256, rows: []}, cleanup: {closed: false},
    qualification: 'Selected warm public operations only. Other latency, structural, history, chunk and fault gates remain unmeasured.'};
  const save = () => writeFile(join(output, 'measurements.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  let client, original, primary, active = 'ordinary public open and initial Result';
  const initial = process.hrtime.bigint();
  try {
    const {open} = await import(pathToFileURL(join(consumer, 'node_modules/@actql/node/index.mjs')).href);
    client = await open({stateDir: stateId});
    original = await client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'benchmark-original'});
    assert.equal((await original.wait()).status, 'succeeded');
    assert.deepEqual(await original.result('main').all(), [{id: 1}]);
    report.originalRun = original.ref;
    report.initialOpenAndResultNs = Number(process.hrtime.bigint() - initial);
    // This observation lacks close, so it is not a first-init percentile.
    // Diagnostic mode may still locate the separate saved-Result/status cost
    // after a slow SUCCESS. It never repeats an unknown or failed submission.
    report.initialLatencyExceeded = report.initialOpenAndResultNs > 5e9;
    if (report.initialLatencyExceeded) report.diagnosticFindings.push('initial operation exceeded 5s');
    if (report.initialLatencyExceeded && mode === 'final') report.stoppedAt = 'initial operation exceeded 5s; final sampling not started';
    else {
      const baseline = await original.status();
      for (const operation of ['warm-select', 'warm-result', 'warm-status']) {
        active = operation;
        const expected = operation === 'warm-status' ? {status: 'succeeded', revision: baseline.revision} : [{id: 1}];
        let observed;
        const execute = operation === 'warm-select' ? async () => {
          observed = await client.sql('SELECT 1 AS id').all(); assert.deepEqual(observed, expected);
        } : operation === 'warm-result' ? async () => {
          observed = await original.result('main').all(); assert.deepEqual(observed, expected);
        } : async () => {
          const state = await original.status();
          observed = {status: state.status, revision: state.revision}; assert.deepEqual(observed, expected);
        };
        const collected = await collectOperationSamples({operation, mode, identity, stateId, execute,
          emit: row => appendFile(join(output, 'samples.jsonl'), JSON.stringify({operation, ...row}) + '\n', {mode: 0o600})});
        const series = {operation, mode, ...identity, environmentSha256,
          historyProtocolSha256: controls.historyProtocolSha256, ...nodeBenchmarkInstrumentation(), load: controls.load, ...collected};
        report.latency.push(series);
        report.functional.rows.push({operation, completed: collected.samples.every(row => row.verified),
          expectedSha256: hash(Buffer.from(JSON.stringify(expected))),
          ...(observed === undefined ? {} : {actualSha256: hash(Buffer.from(JSON.stringify(observed)))})});
        await save();
        if (collected.stoppedEarly) {
          const failed = collected.samples.find(row => row.verified !== true);
          if (failed) {
            report.firstFailure = {operation, message: failed.error}; report.stoppedAt = operation; break;
          }
          report.diagnosticFindings.push(`${operation}: ${collected.stopReason}`);
          if (mode !== 'diagnostic') { report.stoppedAt = operation; break; }
        }
      }
    }
  } catch (error) {
    primary = error;
    report.firstFailure = {operation: active, name: error.name, code: error.code ?? null, message: error.message};
  } finally {
    if (client) {
      const closeStart = process.hrtime.bigint();
      try { await client.close(); report.cleanup.closed = true; }
      catch (error) { primary ??= error; report.cleanup.failure = {name: error.name, code: error.code ?? null, message: error.message}; }
      report.cleanup.wallNs = Number(process.hrtime.bigint() - closeStart);
    }
    try { assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer), before); report.installedPayloadsUnchanged = true; }
    catch (error) { primary ??= error; report.packageFailure = error.message; }
    report.assessments = report.latency.map(assessLatency);
    report.fullAcceptance = false;
    await save();
  }
  if (primary) throw primary;
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2), options = {};
    assert(args.length % 2 === 0);
    for (let n = 0; n < args.length; n += 2) {
      const key = {'--manifest': 'manifestPath', '--consumer': 'consumer', '--output': 'output',
        '--controls': 'controlsPath', '--mode': 'mode'}[args[n]];
      assert(key && !Object.hasOwn(options, key)); options[key] = args[n + 1];
    }
    for (const key of ['manifestPath', 'consumer', 'output', 'controlsPath']) assert(options[key]);
    const report = await runNodeWarmBenchmark(options);
    console.log(JSON.stringify({sourceSha: report.sourceSha, stoppedAt: report.stoppedAt ?? null,
      assessments: report.assessments, fullAcceptance: false}));
    process.exitCode = report.initialLatencyExceeded || report.stoppedAt || report.assessments.some(row => row.status !== 'passed') ? 1 : 0;
  } catch (error) { console.error(error.message); process.exitCode = 2; }
}
