// Explicit Release selection reuses the existing collectors and their formal
// final mode. Unsupported CLI retained-Host routes remain incomplete.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {cpus, platform, arch, release, totalmem} from 'node:os';
import {nodeOperationProtocol, runNodeWarmBenchmark} from './benchmark-node-operations.mjs';
import {runNodeProcessBenchmark} from './benchmark-node-process-operations.mjs';
import {readFixedSQLiteComparison} from './ordinary-operation-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {jsonDigest, digest} from './health-monitor-report.mjs';

export function formalCollectorVerdict(result) {
  if (result.firstFailure || result.packageFailure || result.cleanup?.failure ||
      result.latency?.some(series => series.samples.some(row => !row.verified || !row.completed))) {
    return {status: 'error', reason: JSON.stringify(result.firstFailure ?? result.packageFailure ?? result.cleanup?.failure ?? 'Original failed public sample')};
  }
  if (result.assessments?.some(row => row.status === 'failed')) return {status: 'regression', reason: 'Existing formal assessment failed; original evidence retained'};
  if (!result.latency?.length || result.assessments?.some(row => row.status !== 'passed')) return {status: 'incomplete', reason: result.stoppedAt ?? 'Existing formal assessment incomplete'};
  return {};
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
      artifacts = manifest.packages.map(pkg => ({name: pkg.name, version: pkg.version, sourceSha: source.sha,
        artifactKind: 'npm', sha256: pkg.sha256, acquisitionBytes: pkg.bytes,
        installedBytes: pkg.files.reduce((sum, row) => sum + row.bytes, 0), file: pkg.file,
        bundled: pkg.files.filter(row => /duckdb|wasmtime|\.wasm$|actql-native-client$/u.test(row.path))}));
      for (const pkg of manifest.packages) for (const file of pkg.files.filter(row => /actql-native-client$/u.test(row.path))) {
        artifacts.push({name: pkg.name + ':' + file.path, version: pkg.version, sourceSha: source.sha,
          artifactKind: 'native', sha256: file.sha256, acquisitionBytes: file.bytes});
      }
    } else {
      const result = await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/health-release-artifacts.py'),
        options.pythonManifest, options.pythonConsumer, source.sha], {cwd: repository, name: 'inspect-python'});
      artifacts = JSON.parse(result.stdout);
    }
    for (const artifact of artifacts) {
      await onArtifact(artifact);
      await onMetric({id: artifact.name, target: adapter, kind: 'size', artifactKind: artifact.artifactKind,
        value: artifact.acquisitionBytes, unit: 'bytes', required: true,
        fixtureSha256: jsonDigest({kind: artifact.artifactKind, name: artifact.name}), evidence: options[adapter + 'Manifest']});
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
  if (!options.comparison) {
    await onMetric({id: 'formal-node-collector', kind: 'latency', target: 'node-local', required: true,
      status: 'incomplete', reason: 'Existing final Node collector requires a fixed matched SQLite comparison'});
    return;
  }
  const comparison = await readFixedSQLiteComparison(options.comparison, env, options.load ?? 'concurrent');
  const controlsPath = join(root, 'release-controls.json');
  await writeFile(controlsPath, JSON.stringify({sourceSha: source.sha,
    cohortSha256: digest(await readFile(prepared.manifestPath)), environment: env,
    load: options.load ?? 'concurrent', historyProtocolSha256: jsonDigest(nodeOperationProtocol('final')), comparison}, null, 2));
  const common = {manifestPath: prepared.manifestPath, consumer: prepared.consumer, controlsPath, mode: 'final'};
  for (const id of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'first-init', 'cold-existing']) {
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
  for (const adapter of ['native', 'python']) for (const operation of ['first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status']) {
    if (adapter === 'native' && operation.startsWith('warm-')) {
      await onMetric({id: operation, target: adapter, kind: 'latency', required: true, status: 'incomplete',
        reason: 'Existing ordinary Native CLI collector has no retained-Host warm entry; new CLI processes cannot substitute'});
      continue;
    }
    if (adapter === 'python' && !options.pythonVenv) {
      await onMetric({id: operation, target: adapter, kind: 'latency', required: true, status: 'incomplete', reason: 'Matching ordinary Python venv absent'}); continue;
    }
    const output = join(root, `formal-${adapter}-${operation}`);
    await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/benchmark-ordinary-processes.py'),
      '--adapter', adapter, '--manifest', options[adapter + 'Manifest'], '--consumer', options[adapter + 'Consumer'],
      '--source', source.sha, '--output', output, '--operation', operation, '--mode', 'final',
      '--load', options.load ?? 'concurrent', ...(adapter === 'python' ? ['--venv', options.pythonVenv] : [])],
    {cwd: repository, name: `formal-${adapter}-${operation}`, timeout: 0});
    const raw = JSON.parse(await readFile(join(output, 'measurements.json')));
    for (const series of raw.latency) await onMetric({id: operation, target: adapter, kind: 'latency', required: true,
      unit: 'ms', temperature: operation.startsWith('warm-') ? 'warm' : 'cold', requiredSamples: operation.startsWith('warm-') ? 100 : 30,
      fixtureSha256: series.fixtureSha256, samples: series.samples, evidence: join(output, 'measurements.json'),
      ...(raw.assessments?.some(row => row.status !== 'passed') ? {status: 'incomplete', reason: 'Existing formal assessment incomplete/failed'} : {})});
  }
}
