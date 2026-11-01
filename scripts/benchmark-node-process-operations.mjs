// Actual child-process adapters for separately prepared ordinary packages.
// Never replay failed state or substitute the parent PID for a cold sample.
import assert from 'node:assert/strict';
import {fork} from 'node:child_process';
import {createHash} from 'node:crypto';
import {appendFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, totalmem} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {assessLatency, operationTargets} from './operation-performance.mjs';
import {nodeBenchmarkInstrumentation, nodeOperationProtocol, verifyNodeBenchmarkPackages} from './benchmark-node-operations.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const integer = n => Number.isSafeInteger(n) && n >= 0;
const expected = [{id: 1}];

// Only the parent may invoke the private sample worker. It imports the public
// installed entry and uses public Client/Execution/Result methods exclusively.
async function sample(config) {
  assert(process.send && ['seed', 'cold-existing', 'first-init'].includes(config.operation));
  const cpuStart = process.cpuUsage(), started = process.hrtime.bigint();
  const row = {pid: process.pid, operation: config.operation, stateId: config.stateId,
    cleanup: {closed: false}, completed: false, verified: false};
  let client, failure;
  try {
    const {open} = await import(pathToFileURL(join(config.consumer, 'node_modules/@actql/node/index.mjs')).href);
    client = await open({stateDir: config.stateId});
    const run = config.operation === 'cold-existing' ? await client.attach(config.originalRun)
      : await client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'benchmark-original'});
    if (config.operation === 'cold-existing') assert.deepEqual(run.ref, config.originalRun);
    else assert.equal((await run.wait()).status, 'succeeded');
    assert.deepEqual(await run.result('main').all(), expected);
    row.publicTiming = {kind: 'process-result-close', startNs: Number(started),
      observedNs: Number(process.hrtime.bigint())};
    assert(run.ref !== null && typeof run.ref === 'object', 'Public Run reference is required');
    row.originalRun = run.ref;
    row.actualSha256 = hash(Buffer.from(JSON.stringify(expected)));
  } catch (error) {
    failure = error;
    row.firstFailure = {name: error.name, code: error.code ?? null, message: error.message};
  } finally {
    if (client) {
      const closeStart = process.hrtime.bigint();
      if (row.publicTiming) row.publicTiming.closeStartNs = Number(closeStart);
      try { await client.close(); row.cleanup.closed = true; }
      catch (error) {
        failure ??= error;
        row.cleanup.failure = {name: error.name, code: error.code ?? null, message: error.message};
      }
      row.cleanup.wallNs = Number(process.hrtime.bigint() - closeStart);
      if (row.publicTiming) row.publicTiming.closeEndNs = Number(process.hrtime.bigint());
    }
    const cpu = process.cpuUsage(), operationCpu = process.cpuUsage(cpuStart);
    row.cpuUserUs = cpu.user; row.cpuSystemUs = cpu.system;
    row.operationCpuUserUs = operationCpu.user; row.operationCpuSystemUs = operationCpu.system;
    row.operationWallNs = Number(process.hrtime.bigint() - started);
    row.peakRssBytes = process.resourceUsage().maxRSS * 1024;
    row.rssScope = 'actual child process high-water RSS; not allocation or other-process memory';
    if (row.publicTiming) row.publicTiming.endNs = Number(started) + row.operationWallNs;
    row.completed = row.verified = !failure && row.cleanup.closed;
    await new Promise((resolve, reject) => process.send(row, error => error ? reject(error) : resolve()));
    process.disconnect();
  }
  return row.verified ? 0 : 1;
}

async function runChild(config, output, name) {
  const stdout = [], stderr = [], messages = [];
  let bytes = 0, overflow = false;
  // Do not inherit a profiler, preload or a source/runtime selection override.
  const env = Object.fromEntries(['HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TZ', 'TMPDIR', 'PATH', 'SystemRoot']
    .filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]]));
  const start = process.hrtime.bigint(), cpu = process.cpuUsage();
  const child = fork(fileURLToPath(import.meta.url), ['--sample', JSON.stringify(config)], {
    cwd: config.consumer, env, execArgv: [], stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  const capture = list => data => {
    bytes += data.length;
    if (bytes <= 256 * 1024) list.push(data); else overflow = true;
  };
  child.stdout.on('data', capture(stdout)); child.stderr.on('data', capture(stderr));
  child.on('message', value => messages.push(value));
  const terminal = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('close', (code, signal) => resolve({code, signal}));
  });
  const wallNs = Number(process.hrtime.bigint() - start), parentCpu = process.cpuUsage(cpu);
  await writeFile(join(output, `${name}.stdout`), Buffer.concat(stdout), {mode: 0o600, flag: 'wx'});
  await writeFile(join(output, `${name}.stderr`), Buffer.concat(stderr), {mode: 0o600, flag: 'wx'});
  const actual = messages.length === 1 ? messages[0] : null;
  let stateDirectory = null;
  try {
    const stat = await lstat(config.stateId);
    if (stat.isDirectory() && !stat.isSymbolicLink()) stateDirectory = {dev: stat.dev, ino: stat.ino,
      entryCount: (await readdir(config.stateId)).length};
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const valid = !overflow && actual?.pid === child.pid && actual?.operation === config.operation &&
    actual?.stateId === config.stateId && integer(actual?.cpuUserUs) && integer(actual?.cpuSystemUs);
  const verified = valid && stateDirectory?.entryCount > 0 && terminal.code === 0 && terminal.signal === null &&
    actual.completed === true && actual.verified === true && actual.cleanup?.closed === true &&
    actual.actualSha256 === hash(Buffer.from(JSON.stringify(expected)));
  const observation = {pid: child.pid, stateId: config.stateId, wallNs, ...terminal, verified,
    completed: verified, overflow, stateDirectory, childObservation: actual,
    cpuUserUs: valid ? actual.cpuUserUs : parentCpu.user,
    cpuSystemUs: valid ? actual.cpuSystemUs : parentCpu.system,
    cpuScope: valid ? 'actual-child-startup-through-close; other processes and post-close reporting/exit excluded'
      : 'collector-process-only; child CPU unavailable',
    childCpuAvailable: valid,
    ...(actual?.peakRssBytes ? {peakRssBytes: actual.peakRssBytes, rssScope: actual.rssScope} : {}),
    ...(actual?.publicTiming ? {publicTiming: actual.publicTiming} : {}),
    ...(!verified ? {error: actual?.firstFailure?.message ?? actual?.cleanup?.failure?.message ??
      'Child did not supply a valid verified public completion and awaited close'} : {})};
  await writeFile(join(output, `${name}.json`), JSON.stringify(observation, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
  return observation;
}

export async function runNodeProcessBenchmark({manifestPath, consumer, output, controlsPath,
  operation, mode = 'diagnostic'}) {
  assert(['cold-existing', 'first-init'].includes(operation));
  assert(['diagnostic', 'final'].includes(mode));
  consumer = resolve(consumer); output = resolve(output);
  const manifestBytes = await readFile(manifestPath), manifest = JSON.parse(manifestBytes);
  const controls = JSON.parse(await readFile(controlsPath));
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(controls.sourceSha, manifest.sourceSha);
  assert.equal(controls.cohortSha256, hash(manifestBytes));
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  assert.deepEqual(controls.environment, environment);
  assert(['isolated', 'concurrent'].includes(controls.load));
  const protocol = nodeOperationProtocol(mode);
  assert.equal(controls.historyProtocolSha256, hash(Buffer.from(JSON.stringify(protocol))));
  const before = await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  await mkdir(output, {mode: 0o700}); // No existing benchmark/state is accepted.
  const identity = {cohortSha256: hash(manifestBytes),
    fixtureSha256: hash(Buffer.from('SELECT 1 AS id\n[{"id":1}]\n'))};
  const binding = {cohortSha256: identity.cohortSha256,
    environmentSha256: hash(Buffer.from(JSON.stringify(environment))),
    historyProtocolSha256: controls.historyProtocolSha256};
  const series = {operation, mode, ...identity, ...binding, ...nodeBenchmarkInstrumentation(), load: controls.load,
    samples: [], stoppedEarly: false, stopReason: null};
  const report = {sourceSha: manifest.sourceSha, ...binding, mode, observedEnvironment: environment,
    historyProtocol: protocol, latency: [series], functional: {...binding, rows: []},
    cleanup: {allChildrenExited: false, allOriginalClientsClosed: false}, fullAcceptance: false,
    qualification: 'Selected process operation only; no OS page-cache eviction or other release gate is inferred.'};
  const save = () => writeFile(join(output, 'measurements.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  let originalRun, seed, primary;
  const state = join(output, 'existing-state'), pids = new Set();
  try {
    if (operation === 'cold-existing') {
      seed = await runChild({operation: 'seed', consumer, stateId: state}, output, 'seed');
      report.seed = seed;
      if (!seed.verified) {
        report.firstFailure = {operation: 'seed', message: seed.error};
        series.stoppedEarly = true; series.stopReason = 'Seed failed; no cold samples or resend';
      } else { originalRun = seed.childObservation.originalRun; pids.add(seed.pid); }
    }
    const count = mode === 'final' ? operationTargets[operation].samples : 3;
    if (!seed || seed.verified) for (let iteration = 0; iteration < count; iteration++) {
      const stateId = operation === 'cold-existing' ? state : join(output, `new-state-${iteration}`);
      const result = await runChild({operation, consumer, stateId, ...(originalRun ? {originalRun} : {})},
        output, `sample-${iteration}`);
      assert(!pids.has(result.pid), 'A process sample reused another sample/seed PID'); pids.add(result.pid);
      const row = {...identity, iteration, ...result};
      series.samples.push(row);
      await appendFile(join(output, 'samples.jsonl'), JSON.stringify({operation, ...row}) + '\n', {mode: 0o600});
      await save();
      if (!result.verified || result.wallNs > operationTargets[operation].p95Ms * 1e6 * 10) {
        series.stoppedEarly = true;
        series.stopReason = result.verified ? 'Slow diagnostic; final distribution not measured' : 'Public functional failure';
        if (!result.verified) report.firstFailure = {operation, message: result.error};
        break;
      }
    }
    report.functional.rows.push({operation,
      completed: series.samples.length > 0 && series.samples.every(row => row.verified),
      expectedSha256: hash(Buffer.from(JSON.stringify(expected))),
      ...(series.samples.length && series.samples.every(row => row.verified)
        ? {actualSha256: hash(Buffer.from(JSON.stringify(expected)))} : {})});
  } catch (error) { primary = error; report.firstFailure = {operation, name: error.name, message: error.message}; }
  finally {
    report.cleanup.allChildrenExited = true; // runChild resolves only after actual close/exit.
    report.cleanup.allOriginalClientsClosed = (!seed || seed.childObservation?.cleanup?.closed === true) &&
      series.samples.every(row => row.childObservation?.cleanup?.closed === true);
    try { assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer), before); report.installedPayloadsUnchanged = true; }
    catch (error) { primary ??= error; report.packageFailure = error.message; }
    report.assessments = [assessLatency(series)];
    await save();
  }
  if (primary) throw primary;
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] === '--sample') {
      assert.equal(process.argv.length, 4);
      process.exitCode = await sample(JSON.parse(process.argv[3]));
    } else {
      const args = process.argv.slice(2), options = {};
      assert.equal(args.length % 2, 0);
      for (let n = 0; n < args.length; n += 2) {
        const key = {'--manifest': 'manifestPath', '--consumer': 'consumer', '--output': 'output',
          '--controls': 'controlsPath', '--mode': 'mode', '--operation': 'operation'}[args[n]];
        assert(key && !Object.hasOwn(options, key)); options[key] = args[n + 1];
      }
      for (const key of ['manifestPath', 'consumer', 'output', 'controlsPath', 'operation']) assert(options[key]);
      const report = await runNodeProcessBenchmark(options);
      console.log(JSON.stringify({sourceSha: report.sourceSha, operation: options.operation,
        assessments: report.assessments, fullAcceptance: false}));
      process.exitCode = report.firstFailure || report.assessments.some(row => row.status !== 'passed') ? 1 : 0;
    }
  } catch (error) { console.error(error.message); process.exitCode = 2; }
}
