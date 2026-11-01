// Explicit Release selection reuses the existing collectors and their formal
// final mode. Unsupported CLI retained-Host routes remain incomplete.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile, writeFile, lstat} from 'node:fs/promises';
import {join, resolve, basename} from 'node:path';
import {inventory} from './package-release.mjs';
import {cpus, platform, arch, release, totalmem} from 'node:os';
import {runNodeWarmBenchmark} from './benchmark-node-operations.mjs';
import {runNodeProcessBenchmark} from './benchmark-node-process-operations.mjs';
import {readFixedSQLiteComparison} from './ordinary-operation-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {jsonDigest, digest} from './health-monitor-report.mjs';
import {assessLatency, assessNativeOperations} from './operation-performance.mjs';

// Observe the interpreter that the existing ordinary collector will execute,
// rather than substituting the controller's optional --python interpreter.
export function pythonRuntimeIdentity(venv) {
  const executable = resolve(venv, 'bin/python');
  const program = 'import hashlib,json,pathlib,platform,sys;print(json.dumps(dict(version=platform.python_version(),executableSha256=hashlib.sha256(pathlib.Path(sys.executable).read_bytes()).hexdigest())))';
  const value = JSON.parse(execFileSync(executable, ['-I', '-B', '-c', program],
    {encoding: 'utf8', timeout: 30000, maxBuffer: 8192}));
  assert.match(value.version, /^\d+\.\d+\.\d+[a-z0-9.+-]*$/iu);
  assert.match(value.executableSha256, /^[a-f0-9]{64}$/u);
  return {version: value.version, executableSha256: value.executableSha256};
}

export function assertPythonCollectorRuntime(result, expected) {
  assert.equal(result.environment?.python, expected.version, 'Actual Python collector version changed');
  assert.equal(result.environment?.pythonExecutableSha256, expected.executableSha256,
    'Actual Python collector executable changed');
}

export function formalCollectorVerdict(result) {
  if (result.firstFailure || result.packageFailure || result.cleanup?.failure ||
      result.latency?.some(series => series.samples.some(row => !row.verified || !row.completed))) {
    return {status: 'error', reason: JSON.stringify(result.firstFailure ?? result.packageFailure ?? result.cleanup?.failure ?? 'Original failed public sample')};
  }
  if (result.assessments?.some(row => row.status === 'failed')) return {status: 'regression', reason: 'Existing formal assessment failed; original evidence retained'};
  if (!result.latency?.length || result.assessments?.length !== result.latency.length ||
      result.assessments?.some(row => row.status !== 'passed')) return {status: 'incomplete', reason: result.stoppedAt ?? 'Existing formal assessment incomplete'};
  return {};
}

// Inventory only the selected product-wheel namespaces, including installed
// metadata/bytecode. The ordinary verifier owns payload identity; this reader
// reuses its observations and the existing non-following inventory utility.
export async function pythonInstalledInventory(consumer, artifacts) {
  const directory = await lstat(consumer);
  assert(directory.isDirectory() && !directory.isSymbolicLink(), 'Installed Python consumer cannot be linked');
  assert.deepEqual(artifacts.map(row => row.name).sort(), ['actql', 'actql-local-runtime', 'actql-sdk']);
  for (const artifact of artifacts) {
    assert(Array.isArray(artifact.installedRoots) && artifact.installedRoots.length > 0);
    assert(Array.isArray(artifact.verifiedPayloads) && artifact.verifiedPayloads.length > 0);
  }
  const roots = [...new Set(artifacts.flatMap(row => row.installedRoots))].sort();
  const files = [];
  for (const name of roots) {
    assert(typeof name === 'string' && name !== '' && name !== '.' && name !== '..' &&
      name === basename(name) && !name.includes('\\'), 'Unsafe installed wheel namespace');
    const path = join(consumer, name), metadata = await lstat(path);
    assert(!metadata.isSymbolicLink(), 'Installed wheel namespace cannot be linked');
    if (metadata.isDirectory()) files.push(...await inventory(path, name + '/'));
    else {
      assert(metadata.isFile(), 'Installed wheel namespace must be regular');
      const body = await readFile(path);
      files.push({path: name, bytes: body.length, mode: metadata.mode & 0o777, sha256: digest(body)});
    }
  }
  files.sort((a, b) => a.path.localeCompare(b.path));
  const byPath = new Map(files.map(row => [row.path, row]));
  for (const artifact of artifacts) for (const expected of artifact.verifiedPayloads) {
    assert.deepEqual(byPath.get(expected.path), expected, 'Verified Python payload changed during size inspection');
  }
  const bytes = files.reduce((sum, row) => sum + row.bytes, 0);
  assert(Number.isSafeInteger(bytes) && bytes > 0);
  return {roots, files, bytes, sha256: jsonDigest(files)};
}

export async function releaseNativeOperations({options, repository, root, source, command, onMetric}) {
  const output = join(root, 'formal-native-operations'), path = join(output, 'measurements.json');
  let commandFailure;
  try {
    await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/benchmark-ordinary-processes.py'),
      '--adapter', 'native', '--selection', 'native-operations', '--manifest', options.nativeManifest,
      '--consumer', options.nativeConsumer, '--source', source.sha, '--output', output, '--mode', 'final',
      '--load', options.load ?? 'concurrent'], {cwd: repository, name: 'formal-native-operations', timeout: 0});
  } catch (error) {commandFailure = error;}
  let raw, rawBytes, assessment;
  try {
    rawBytes = await readFile(path); raw = JSON.parse(rawBytes);
    assert.equal(raw.sourceSha, source.sha, 'Native operation source differs');
    assert.equal(raw.cohortSha256, digest(await readFile(options.nativeManifest)), 'Native operation cohort differs');
    assert.equal(raw.mode, 'final', 'Native Release requires the existing final selection');
    assessment = assessNativeOperations(raw);
  } catch (error) {throw commandFailure ?? error;}
  const assessmentPath = join(output, 'health-assessments.json');
  await writeFile(assessmentPath, JSON.stringify({sourceSha: source.sha, cohortSha256: raw.cohortSha256,
    rawSha256: digest(rawBytes), assessment}, null, 2) + '\n', {flag: 'wx'});
  const routes = raw.latency ?? [];
  const failedPublic = commandFailure || raw.firstFailure || raw.packageFailure || raw.cleanup?.closed === false ||
    routes.some(series => series.samples.some(row => !row.verified || !row.completed));
  const originalCause = raw.firstFailure ?? raw.packageFailure ?? raw.cleanup?.failure ?? commandFailure?.message ??
    'Original Native process cleanup or public sample did not complete';
  const verdict = failedPublic ? {status: 'error', reason: 'Original Native command/public/package failure: ' + JSON.stringify(originalCause)}
    : assessment.status === 'failed' ? {status: 'regression', reason: 'Existing Native CLI latency/functional assessment failed'}
      : assessment.status === 'incomplete' ? {status: 'incomplete', reason: 'Existing Native CLI latency/functional assessment incomplete'}
        : {status: 'pass', reason: 'Native CLI latency/functional selection only; retained-Host warm, SQLite and release acceptance remain unproved'};
  const evidence = {evidence: path, formalAssessment: assessmentPath, purpose: assessment.purpose,
    fullPerformanceAccepted: false, releaseAccepted: false};
  for (const [id, observation] of [['init-separate', raw.initialization], ['first-query-separate', raw.firstQuery]]) {
    await onMetric({id, target: 'native', kind: 'reference', unit: 'ms', required: true,
      ...(Number.isSafeInteger(observation?.wallNs) ? {value: observation.wallNs / 1e6} : {}),
      observedCount: observation ? 1 : 0, fixtureSha256: raw.historyProtocolSha256,
      scope: id === 'init-separate' ? 'Single original initialization CLI child; reference only, no SDK close ACK'
        : 'Single separate first query/rows observation; parent includes child exit, response/file oracle; raw child duration retained',
      ...evidence, ...verdict});
  }
  for (const operation of ['cold-new-run', 'cold-result']) {
    const series = routes.find(row => row.operation === operation);
    await onMetric({id: operation, target: 'native', kind: 'latency', temperature: 'cold', unit: 'ms', required: true,
      requiredSamples: 100, ...(series ? {samples: series.samples, fixtureSha256: series.fixtureSha256} : {}),
      scope: 'Distinct CLI child per durable NEW/file rows or original saved Result; launch through exit, response and row oracle; raw child duration retained',
      ...evidence, ...verdict});
  }
  if (commandFailure) throw commandFailure; // No retry, failure replacement or later collector after the original failed child.
  return assessment;
}

export async function releaseArtifacts({options, repository, source, command, onArtifact, onMetric}) {
  let ready = true;
  const platformKey = { 'darwin-arm64': 'darwin-arm64', 'linux-x64': 'linux-x64-gnu' }[platform() + '-' + arch()];
  for (const adapter of ['native', 'python']) {
    if (!options[adapter + 'Manifest'] || !options[adapter + 'Consumer']) {
      ready = false;
      await onMetric({id: adapter + '-artifacts', target: adapter, kind: 'size', required: true,
        status: 'incomplete', reason: `Required ordinary ${adapter} manifest/consumer not supplied`});
      continue;
    }
    const selected = JSON.parse(await readFile(options[adapter + 'Manifest']));
    if (!platformKey || (adapter === 'native' ? !selected.platforms?.[platformKey] : selected.platform !== platformKey)) {
      ready = false;
      await onMetric({id: adapter + '-platform-artifacts', target: adapter, kind: 'size', required: true,
        status: 'incomplete', reason: 'Required ordinary artifacts absent for the actual selected OS/architecture'});
      continue;
    }
    let artifacts;
    if (adapter === 'native') {
      const path = options.nativeManifest;
      const manifest = await verifyNativeCliRelease(join(path, '..'));
      assert.equal(manifest.sourceSha, source.sha);
      assert.equal(jsonDigest(manifest), jsonDigest(selected), 'Selected Native manifest differs from the verified canonical release');
      const result = await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/health-release-artifacts.py'),
        '--native-installed', path, options.nativeConsumer, source.sha], {cwd: repository, name: 'inspect-native'});
      const installed = JSON.parse(result.stdout);
      assert.equal(installed.sourceSha, source.sha);
      assert.equal(installed.cohortSha256, digest(await readFile(path)));
      assert.equal(installed.platform, platformKey);
      assert.deepEqual(Object.keys(installed.packages).sort(), ['actql', '@actql/cli-' + platformKey].sort());
      for (const row of Object.values(installed.packages)) {
        assert(Number.isSafeInteger(row.installedBytes) && row.installedBytes > 0);
        assert(Number.isSafeInteger(row.payloads) && row.payloads > 0);
        assert.match(row.inventorySha256, /^[a-f0-9]{64}$/u);
      }
      await onArtifact({name: 'native-products-installed', artifactKind: 'installed', sourceSha: source.sha,
        version: manifest.packages.find(row => row.name === 'actql').version,
        sha256: jsonDigest(installed), installedInventory: installed,
        installedBytes: Object.values(installed.packages).reduce((sum, row) => sum + row.installedBytes, 0)});
      artifacts = manifest.packages.map(pkg => ({name: pkg.name, version: pkg.version, sourceSha: source.sha,
        artifactKind: 'npm', sha256: pkg.sha256, acquisitionBytes: pkg.bytes, file: pkg.file,
        ...(installed.packages[pkg.name] ? {...installed.packages[pkg.name],
          installedScope: 'Verified selected Native product payload bytes; npm metadata and unrelated dependencies excluded'}
          : {installedStatus: 'unmeasured', installedReason: 'Package is not installed for the actual selected platform'}),
        bundled: pkg.files.filter(row => /duckdb|wasmtime|\.wasm$|actql-native-client$/u.test(row.path))}));
      for (const pkg of manifest.packages) for (const file of pkg.files.filter(row => /actql-native-client$/u.test(row.path))) {
        artifacts.push({name: pkg.name + ':' + file.path, version: pkg.version, sourceSha: source.sha,
          artifactKind: 'native', sha256: file.sha256, acquisitionBytes: file.bytes});
      }
    } else {
      const result = await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/health-release-artifacts.py'),
        options.pythonManifest, options.pythonConsumer, source.sha], {cwd: repository, name: 'inspect-python'});
      artifacts = JSON.parse(result.stdout);
      for (const artifact of artifacts) {
        assert.equal(artifact.sourceSha, source.sha);
        assert.equal(artifact.artifactKind, 'wheel');
      }
      const installed = await pythonInstalledInventory(options.pythonConsumer, artifacts);
      await onArtifact({name: 'python-products-installed', artifactKind: 'installed', sourceSha: source.sha,
        version: selected.package_version, sha256: installed.sha256, installedInventory: installed,
        installedBytes: installed.bytes});
      await onMetric({id: 'installed:python-products', target: 'python', kind: 'size', artifactKind: 'installed',
        value: installed.bytes, unit: 'bytes', required: true,
        scope: 'Complete selected product-wheel module and metadata namespaces, including generated bytecode; unrelated dependency roots and filesystem allocation excluded',
        fixtureSha256: jsonDigest({kind: 'installed-python-product-namespaces', distributions: ['actql', 'actql-sdk', 'actql-local-runtime']}),
        evidence: options.pythonManifest});
    }
    for (const artifact of artifacts) {
      await onArtifact(artifact);
      await onMetric({id: artifact.name, target: adapter, kind: 'size', artifactKind: artifact.artifactKind,
        value: artifact.acquisitionBytes, unit: 'bytes', required: true,
        fixtureSha256: jsonDigest({kind: artifact.artifactKind, name: artifact.name}), evidence: options[adapter + 'Manifest']});
      if (adapter === 'native' && artifact.installedBytes !== undefined) {
        await onMetric({id: 'installed:' + artifact.name, target: adapter, kind: 'size', artifactKind: 'installed',
          value: artifact.installedBytes, unit: 'bytes', required: true, scope: artifact.installedScope,
          fixtureSha256: jsonDigest({kind: 'installed', name: artifact.name}), evidence: options.nativeManifest});
      } else if (adapter === 'native' && artifact.installedStatus === 'unmeasured') {
        await onMetric({id: 'installed:' + artifact.name, target: adapter, kind: 'size', artifactKind: 'installed',
          unit: 'bytes', required: false, status: 'incomplete', reason: artifact.installedReason,
          fixtureSha256: jsonDigest({kind: 'installed', name: artifact.name}), evidence: options.nativeManifest});
      }
      for (const member of artifact.bundled ?? []) if (member.path.endsWith('.wasm')) {
        await onArtifact({name: artifact.name + ':' + member.path, artifactKind: 'wasm', version: artifact.version,
          sourceSha: source.sha, sha256: member.sha256, acquisitionBytes: member.bytes});
        await onMetric({id: artifact.name + ':' + member.path, target: adapter, kind: 'size', artifactKind: 'wasm',
          value: member.bytes, unit: 'bytes', required: true, fixtureSha256: jsonDigest(member.path), evidence: options[adapter + 'Manifest']});
      }
    }
    if (adapter === 'python' && !artifacts.some(row => row.bundled.some(member => member.path.endsWith('.wasm')))) {
      ready = false;
      await onMetric({id: 'distributed-wasm', target: adapter, kind: 'size', required: true,
        status: 'incomplete', reason: 'No actual distributed Python-contained Wasm observed'});
    }
  }
  return ready;
}

export async function releaseMeasurements({options, prepared, repository, root, source, command, onMetric}) {
  const env = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  if (!options.nodeControls) {
    await onMetric({id: 'formal-node-collector', kind: 'latency', target: 'node-local', required: true,
      status: 'incomplete', reason: 'Existing final Node collector requires a fixed matched SQLite comparison'});
  }
  // Native CLI evidence is independent of the Node SQLite comparison.
  for (const id of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']) {
    await onMetric({id, target: 'native', kind: 'latency', temperature: 'warm', unit: 'ms',
      requiredSamples: 100, required: true, status: 'incomplete',
      reason: 'Existing ordinary Native CLI collector has no retained-Host warm entry; new CLI processes cannot substitute'});
  }
  await releaseNativeOperations({options, repository, root, source, command, onMetric});
  if (!options.nodeControls) return;
  const controlsPath = options.nodeControls, controls = JSON.parse(await readFile(controlsPath));
  assert.equal(controls.sourceSha, source.sha);
  assert.equal(controls.cohortSha256, digest(await readFile(prepared.manifestPath)));
  assert.deepEqual(controls.environment, env);
  assert.equal(controls.load, options.load ?? 'concurrent');
  if (options.comparison) assert.deepEqual(controls.comparison,
    await readFixedSQLiteComparison(options.comparison, env, options.load ?? 'concurrent'));
  const common = {manifestPath: prepared.manifestPath, consumer: prepared.consumer, controlsPath, mode: 'final'};
  for (const id of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode', 'first-init', 'cold-existing']) {
    await onMetric({id, kind: 'latency', target: 'node-local', required: true, status: 'incomplete', reason: 'Required final collector family not yet observed'});
  }
  for (const operation of ['warm', 'first-init', 'cold-existing']) {
    const output = join(root, 'formal-node-' + operation);
    const result = operation === 'warm' ? await runNodeWarmBenchmark({...common, output})
      : await runNodeProcessBenchmark({...common, output, operation});
    const verdict = formalCollectorVerdict(result);
    if (!result.latency.length) await onMetric({id: 'formal-node-' + operation, kind: 'latency', target: 'node-local', required: true, ...verdict});
    for (const series of result.latency) await onMetric({id: series.operation, kind: 'latency', target: 'node-local',
      temperature: series.operation.startsWith('warm-') ? 'warm' : 'cold', required: true,
      samples: series.samples, requiredSamples: series.operation.startsWith('warm-') ? 100 : 30,
      fixtureSha256: series.fixtureSha256, evidence: join(output, 'measurements.json'), unit: 'ms',
      ...verdict});
  }
  await onMetric({id: 'peak-rss', kind: 'rss', target: 'node-local', unit: 'bytes', required: true,
    value: process.resourceUsage().maxRSS * 1024, fixtureSha256: jsonDigest('Release Node collector including verification and public Host'),
    scope: 'actual Release Node collector process high-water RSS, including verification/reporting; spawned compiler/Native/Python processes excluded; Node KiB converted to bytes', evidence: root});
  const pythonRuntime = options.pythonVenv ? pythonRuntimeIdentity(options.pythonVenv) : null;
  const pythonControls = options.pythonControls ? JSON.parse(await readFile(options.pythonControls)) : null;
  for (const adapter of ['python']) for (const operation of ['first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']) {
    if (adapter === 'python' && !options.pythonVenv) {
      await onMetric({id: operation, target: adapter, kind: 'latency', required: true, status: 'incomplete', reason: 'Matching ordinary Python venv absent'}); continue;
    }
    const output = join(root, `formal-${adapter}-${operation}`);
    const interpreter = adapter === 'python' ? join(options.pythonVenv, 'bin/python') : options.python ?? 'python3';
    await command(interpreter, ['-I', '-B', join(repository, 'scripts/benchmark-ordinary-processes.py'),
      '--adapter', adapter, '--manifest', options[adapter + 'Manifest'], '--consumer', options[adapter + 'Consumer'],
      '--source', source.sha, '--output', output, '--operation', operation, '--mode', 'final',
      '--load', options.load ?? 'concurrent', ...(adapter === 'python' ? ['--venv', options.pythonVenv] : [])],
    {cwd: repository, name: `formal-${adapter}-${operation}`, timeout: 0});
    const raw = JSON.parse(await readFile(join(output, 'measurements.json')));
    if (adapter === 'python') assertPythonCollectorRuntime(raw, pythonRuntime);
    if (adapter === 'python' && pythonControls) {
      assert.equal(pythonControls.sourceSha, source.sha);
      assert.equal(pythonControls.cohortSha256, digest(await readFile(options.pythonManifest)));
      assert.equal(pythonControls.environmentSha256, raw.environmentSha256);
      for (const series of raw.latency) {
        Object.assign(series, {executableSha256: raw.environment.pythonExecutableSha256,
          expectedSha256: raw.functional.rows.find(row => row.operation === operation)?.expectedSha256,
          comparisonMatch: pythonControls.comparisonMatches?.[operation], comparisonSettings: pythonControls.comparisonSettings,
          resultStorageMatch: pythonControls.resultStorageMatches?.[operation]});
      }
    }
    raw.assessments = raw.latency.map(series => assessLatency(series, adapter === 'python' ? pythonControls?.comparison : undefined));
    const assessmentPath = join(output, 'health-assessments.json');
    await writeFile(assessmentPath, JSON.stringify({sourceSha: source.sha, assessments: raw.assessments,
      ...(adapter === 'python' ? {pythonRuntime} : {}),
      controlsSha256: adapter === 'python' && options.pythonControls ? digest(await readFile(options.pythonControls)) : null}, null, 2), {flag: 'wx'});
    const verdict = formalCollectorVerdict(raw);
    for (const series of raw.latency) await onMetric({id: operation, target: adapter, kind: 'latency', required: true,
      unit: 'ms', temperature: operation.startsWith('warm-') ? 'warm' : 'cold', requiredSamples: operation.startsWith('warm-') ? 100 : 30,
      fixtureSha256: series.fixtureSha256, samples: series.samples, evidence: join(output, 'measurements.json'),
      formalAssessments: assessmentPath, ...verdict});
  }
}
