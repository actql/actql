// Reuse the existing normal Client artifact. This consumer never packs,
// compiles, publishes or substitutes source packages for a missing artifact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile, execFileSync} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, totalmem} from 'node:os';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {promisify} from 'node:util';
import {CLIENT_PACKAGES, checkoutState} from './packed-client-packages.mjs';
import {inventory, unpack} from './package-release.mjs';
import {nodeOperationProtocol, nodePriorityProtocol, nodeWarmSmallQueryFixtures} from './benchmark-node-operations.mjs';
import {calibrateSqliteComparisonProfile} from './operation-performance.mjs';

const hash = (value, algorithm = 'sha256', encoding = 'hex') =>
  createHash(algorithm).update(value).digest(encoding);
const positiveId = value => /^[1-9][0-9]*$/u.test(String(value ?? ''));

export async function readFixedSQLiteComparison(path, environment, load) {
  const bytes = await readFile(path);
  assert(bytes.length <= 16 * 1024 ** 2, 'Comparison exceeds bounded input');
  const comparison = JSON.parse(bytes);
  assert.deepEqual(comparison.profile, calibrateSqliteComparisonProfile(comparison.baseline, comparison.resultControl),
    'Comparison differs from the baseline-only fixed policy');
  assert.deepEqual(comparison.baseline.environment, environment, 'Comparator environment differs');
  assert.equal(comparison.baseline.load, load, 'Comparator load differs');
  return comparison;
}

// The original run records the PR identity and workflow checkout. Git tree and
// parent verification still follow after the downloaded manifest is admitted.
function originalPerformanceMerge(repository, eventHeadSha, buildSourceSha, run) {
  assert.equal(run.event, 'pull_request', 'Only the original PR merge may differ from its event head');
  assert.equal(run.pull_requests.length, 1);
  const pr = run.pull_requests[0];
  assert(positiveId(pr.number)); assert.equal(pr.head.sha, eventHeadSha);
  assert.match(pr.base.sha, /^[a-f0-9]{40}$/u);
  assert.equal(pr.head.repo.id, run.repository.id); assert.equal(pr.base.repo.id, run.repository.id);
  const reference = run.referenced_workflows.filter(value =>
    value.path === `${repository}/.github/workflows/performance-matrix.yml@${buildSourceSha}`);
  assert.equal(reference.length, 1, 'Built source is not the original recorded PR workflow source');
  assert.equal(reference[0].sha, buildSourceSha);
  assert.equal(reference[0].ref, `refs/pull/${pr.number}/merge`);
  return pr;
}

export function validatePerformancePackageProducer({repository, sourceSha, runId, artifactId,
  artifact, run, jobs, buildSourceSha}) {
  assert.match(repository, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u);
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  assert(positiveId(runId) && positiveId(artifactId), 'Exact producer run/artifact IDs are required');
  assert.equal(String(run.id), String(runId));
  assert.equal(run.repository.full_name, repository);
  assert(positiveId(run.repository.id));
  assert.equal(artifact.workflow_run.repository_id, run.repository.id);
  assert.equal(artifact.workflow_run.head_repository_id, run.repository.id);
  assert.match(artifact.digest, /^sha256:[a-f0-9]{64}$/u);
  assert.equal(run.head_sha, sourceSha, 'Producer event head differs from the selected reviewed head');
  assert.equal(run.path.split('@')[0], '.github/workflows/ci.yml');
  assert.equal(run.status, 'completed');
  assert(positiveId(run.run_attempt));
  assert.equal(String(artifact.id), String(artifactId));
  assert.equal(artifact.expired, false);
  assert.equal(String(artifact.workflow_run.id), String(runId));
  assert.equal(artifact.workflow_run.head_sha, sourceSha);
  // CI names this archive with its checkout SHA, not the REST event head.
  const prefix = `actql-client-packages-${runId}-${run.run_attempt}-`;
  assert.equal(typeof artifact.name, 'string'); assert(artifact.name.startsWith(prefix));
  const artifactSource = artifact.name.slice(prefix.length);
  assert.match(artifactSource, /^[a-f0-9]{40}$/u);
  if (artifactSource !== sourceSha) originalPerformanceMerge(repository, sourceSha, artifactSource, run);
  if (buildSourceSha !== undefined) assert.equal(artifact.name, prefix + buildSourceSha);
  const producers = jobs.filter(job => job.name === 'client-packages');
  assert.equal(producers.length, 1, 'Exactly one original Client package producer is required');
  assert.equal(producers[0].status, 'completed');
  assert.equal(producers[0].conclusion, 'success');
  assert.equal(producers[0].head_sha, sourceSha);
  assert(positiveId(producers[0].id));
  assert.equal(String(producers[0].run_id), String(runId));
  assert.equal(producers[0].run_attempt, run.run_attempt);
  return {repository, eventHeadSha: sourceSha, artifactDigest: artifact.digest, runId: String(runId), artifactId: String(artifactId),
    attempt: run.run_attempt, producerJobId: producers[0].id, artifactName: artifact.name,
    qualification: 'Successful package producer only; other source-run failures remain failures.'};
}

export function validatePerformanceProcessPackageProducer(options) {
  const {repository, sourceSha, runId, artifactId, artifact, run, jobs, producerJob, adapter,
    nativeApproval = false} = options;
  assert.equal(typeof nativeApproval, 'boolean');
  assert(['native', 'python'].includes(adapter));
  assert.match(repository, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u);
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  assert(positiveId(runId) && positiveId(artifactId), 'Exact producer run/artifact IDs are required');
  assert.equal(typeof producerJob, 'string'); assert(producerJob.trim().length > 0);
  assert.equal(String(run.id), String(runId));
  assert.equal(run.repository.full_name, repository);
  assert(positiveId(run.repository.id));
  assert.equal(artifact.workflow_run.repository_id, run.repository.id);
  assert.equal(artifact.workflow_run.head_repository_id, run.repository.id);
  assert.match(artifact.digest, /^sha256:[a-f0-9]{64}$/u);
  assert.equal(run.head_sha, sourceSha);
  assert.equal(run.path.split('@')[0], '.github/workflows/ci.yml');
  if (nativeApproval) {
    assert.equal(adapter, 'native'); assert.equal(producerJob, 'native-cli-linux-local');
    assert(['completed', 'in_progress'].includes(run.status));
  } else assert.equal(run.status, 'completed');
  assert(positiveId(run.run_attempt));
  assert.equal(String(artifact.id), String(artifactId)); assert.equal(artifact.expired, false);
  assert.equal(String(artifact.workflow_run.id), String(runId));
  assert.equal(artifact.workflow_run.head_sha, sourceSha);
  const selected = jobs.filter(job => job.name === producerJob);
  assert.equal(selected.length, 1, 'Exactly one selected normal package job is required');
  assert.equal(selected[0].status, 'completed'); assert.equal(selected[0].conclusion, 'success');
  assert.equal(selected[0].head_sha, sourceSha);
  assert(positiveId(selected[0].id));
  assert.equal(String(selected[0].run_id), String(runId));
  assert.equal(selected[0].run_attempt, run.run_attempt);
  if (nativeApproval) assert.equal(artifact.name, `native-cli-linux-local-${runId}-${run.run_attempt}`);
  return {repository, eventHeadSha: sourceSha, artifactDigest: artifact.digest,
    ...(nativeApproval ? {sourceRunStatus: run.status, sourceRunConclusion: run.conclusion} : {}), adapter,
    runId: String(runId), artifactId: String(artifactId),
    attempt: run.run_attempt, producerJobId: selected[0].id, artifactName: artifact.name,
    qualification: nativeApproval
      ? 'Successful original Native package job only; final source-run CI acceptance remains separate.'
      : 'Original same-run artifact and selected package job only; installed payload and performance checks remain required.'};
}

export function validatePerformanceBuildSource(options) {
  const {sourceSha: eventHeadSha, manifest, manifestSha256, run, headCommit, sourceCommit} = options;
  const producer = options.nativeApproval || (options.adapter !== undefined && options.adapter !== 'node')
    ? validatePerformanceProcessPackageProducer(options)
    : validatePerformancePackageProducer({...options, buildSourceSha: manifest.sourceSha});
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.match(manifestSha256, /^[a-f0-9]{64}$/u);
  assert.equal(headCommit.sha, eventHeadSha);
  assert.equal(sourceCommit.sha, manifest.sourceSha);
  assert.match(headCommit.tree.sha, /^[a-f0-9]{40}$/u);
  assert.equal(sourceCommit.tree.sha, headCommit.tree.sha, 'Built source differs from the reviewed head tree');
  let relation = 'same-head';
  if (manifest.sourceSha !== eventHeadSha) {
    const pr = originalPerformanceMerge(options.repository, eventHeadSha, manifest.sourceSha, run);
    assert.deepEqual(sourceCommit.parents.map(parent => parent.sha), [pr.base.sha, eventHeadSha],
      'Built source does not have the original PR base/head parents');
    relation = 'pull-request-merge';
  }
  return {...producer, sourceSha: manifest.sourceSha, sourceTreeSha: sourceCommit.tree.sha,
    sourceParents: sourceCommit.parents.map(parent => parent.sha), manifestSha256, relation};
}

export function validateNativeApprovalSource(options) {
  return validatePerformanceBuildSource({...options, nativeApproval: true});
}

export async function inspectPerformancePackageProducer(options, fetchMetadata = fetch) {
  const {repository, runId, artifactId, token} = options;
  assert.match(repository, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u);
  assert(positiveId(runId) && positiveId(artifactId), 'Missing original package artifact');
  assert.equal(typeof token, 'string'); assert(token.length > 0);
  async function get(path) {
    const response = await fetchMetadata(`https://api.github.com/repos/${repository}/${path}`, {
      headers: {Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28'}, signal: AbortSignal.timeout(30_000), redirect: 'error',
    });
    assert.equal(response.ok, true, `Cannot read original package metadata: ${response.status}`);
    const text = await response.text(); assert(Buffer.byteLength(text) <= 8 * 1024 ** 2);
    return JSON.parse(text);
  }
  const run = await get(`actions/runs/${runId}`);
  const artifact = await get(`actions/artifacts/${artifactId}`);
  const jobs = [];
  let complete = false;
  for (let page = 1; page <= 10; page++) {
    const result = await get(`actions/runs/${runId}/attempts/${run.run_attempt}/jobs?per_page=100&page=${page}`);
    assert(Array.isArray(result.jobs)); jobs.push(...result.jobs);
    if (jobs.length >= result.total_count) { complete = true; break; }
  }
  assert(complete, 'Incomplete producer job inventory');
  if (options.packages !== undefined || (options.nativeApproval && options.nativePackages !== undefined)) {
    (options.nativeApproval || (options.adapter !== undefined && options.adapter !== 'node')
      ? validatePerformanceProcessPackageProducer : validatePerformancePackageProducer)({...options, run, artifact, jobs});
    const adapter = options.adapter ?? 'node';
    const manifestFile = {node: 'packed-client-packages.json', native: 'release.json', python: 'cohort.json'}[adapter];
    assert(manifestFile, 'Exact package adapter is required');
    const bytes = await readFile(join(options.packages ?? options.nativePackages, manifestFile));
    assert(bytes.length <= 8 * 1024 ** 2, 'Package manifest exceeds bounded input');
    const original = JSON.parse(bytes);
    let manifest;
    if (adapter === 'native') {
      const {admitNativeReleaseManifest} = await import('./native-cli-release.mjs');
      manifest = admitNativeReleaseManifest(original);
    } else if (adapter === 'node') {
      assert.deepEqual(Object.keys(original).sort(), ['revision', 'tarballs']);
      assert.deepEqual(Object.keys(original.tarballs).sort(), [...CLIENT_PACKAGES].sort());
      for (const digest of Object.values(original.tarballs)) assert.match(digest, /^[a-f0-9]{64}$/u);
      manifest = {sourceSha: original.revision};
    } else manifest = {sourceSha: original.source_sha};
    assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
    const headCommit = await get(`git/commits/${options.sourceSha}`);
    const sourceCommit = manifest.sourceSha === options.sourceSha ? headCommit
      : await get(`git/commits/${manifest.sourceSha}`);
    return {...validatePerformanceBuildSource({...options, run, artifact, jobs, manifest,
      manifestSha256: hash(bytes), headCommit, sourceCommit}), manifestFile};
  }
  return (options.nativeApproval || (options.adapter !== undefined && options.adapter !== 'node')
    ? validatePerformanceProcessPackageProducer : validatePerformancePackageProducer)({...options, run, artifact, jobs});
}

export async function prepareOrdinaryNativePerformanceConsumer({packages, sourceSha, output,
  verify, openRegistry, install}) {
  packages = resolve(packages); output = resolve(output);
  verify ??= (await import('./native-cli-release.mjs')).verifyNativeCliRelease;
  openRegistry ??= (await import('./release-test-registry.mjs')).openReleaseTestRegistry;
  const manifest = await verify(packages);
  assert.equal(manifest.sourceSha, sourceSha, 'Native packages differ from the checked source');
  await mkdir(output);
  const registry = await openRegistry([{directory: packages, manifest}]);
  try {
    const env = {...process.env};
    for (const key of Object.keys(env)) if (/^npm_config_/iu.test(key)) delete env[key];
    Object.assign(env, {npm_config_registry: registry.url,
      npm_config_cache: join(output, 'npm-cache'), npm_config_userconfig: join(output, 'npmrc'),
      npm_config_globalconfig: join(output, 'npmrc-global'), npm_config_update_notifier: 'false',
      npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost'});
    delete env.NODE_PATH;
    await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
    await writeFile(env.npm_config_globalconfig, '');
    install ??= async (args, options) => promisify(execFile)('npm', args,
      {...options, timeout: 120_000, maxBuffer: 8 * 1024 ** 2});
    await install(['install', '-g', '--prefix', output, '--ignore-scripts', '--no-audit', '--no-fund',
      `actql@${manifest.cohort.packageVersion}`], {cwd: output, env});
    return {consumer: join(output, 'lib/node_modules/actql'), sourceSha};
  } finally { await registry.close(); }
}

export async function prepareOrdinaryPerformanceConsumer({packages, sourceSha, output, comparisonPath, selection, mode, resourceObservations, rowObservations,
  install = (args, cwd) => execFileSync('npm', args, {cwd, stdio: 'inherit', timeout: 120_000})}) {
  let protocol;
  if (selection === undefined) {
    assert(mode === undefined || mode === 'record-only', 'Only record-only mode is allowed without a priority selection');
    assert.equal(resourceObservations, undefined, 'Resource observations require the explicit priority selection');
    assert.equal(rowObservations, undefined, 'Row observations require the explicit priority selection');
    protocol = nodeOperationProtocol(mode ?? 'final');
  } else {
    assert.equal(selection, 'priority-transition', 'Unknown performance selection');
    assert.equal(comparisonPath, undefined, 'Priority controls do not use the full-release comparator');
    protocol = nodePriorityProtocol(mode ?? 'diagnostic', resourceObservations, rowObservations);
  }
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  packages = resolve(packages); output = resolve(output);
  const original = JSON.parse(await readFile(join(packages, 'packed-client-packages.json'), 'utf8'));
  assert.equal(original.revision, sourceSha, 'Existing tarballs are from another source');
  assert.deepEqual(Object.keys(original.tarballs).sort(), [...CLIENT_PACKAGES].sort());
  await mkdir(output, {mode: 0o700}); // No old consumer or Run state is reused.
  const manifest = {sourceSha, packages: []};
  const tarballs = [];
  for (const name of CLIENT_PACKAGES) {
    const file = `actql-${name}-0.0.0-development.tgz`, path = join(packages, file);
    const bytes = await readFile(path);
    assert.equal(hash(bytes), original.tarballs[name], `Changed original ${name} tarball`);
    const directory = await unpack(path, join(output, `original-${name}`));
    const metadata = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
    assert.equal(metadata.name, `@actql/${name}`);
    manifest.packages.push({name: metadata.name, file, bytes: bytes.length, sha256: hash(bytes),
      integrity: 'sha512-' + hash(bytes, 'sha512', 'base64'), files: await inventory(directory)});
    tarballs.push(path);
  }
  // Keep the formal manifest beside its unchanged tarballs. The collector
  // reads those exact files; no source overlay or rebuilt package is allowed.
  const manifestPath = join(packages, 'ordinary-operation-packages.json');
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx'});
  const consumer = join(output, 'consumer'); await mkdir(consumer);
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  await install(['install', '--no-audit', '--no-fund', '--no-save', ...tarballs], consumer);
  for (const pkg of manifest.packages) {
    assert.deepEqual(await inventory(join(consumer, 'node_modules', pkg.name)), pkg.files,
      `Installed ${pkg.name} differs from its original tarball`);
  }
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  const controls = {sourceSha, cohortSha256: hash(await readFile(manifestPath)), environment, load: 'isolated',
    historyProtocolSha256: hash(JSON.stringify(protocol))};
  if (comparisonPath) controls.comparison = await readFixedSQLiteComparison(comparisonPath, environment, controls.load);
  await writeFile(join(output, 'controls.json'), JSON.stringify(controls, null, 2) + '\n', {flag: 'wx'});
  return {manifestPath, consumer, controlsPath: join(output, 'controls.json')};
}

// Join only these existing collectors' actual reports. Missing families stay
// absent for the full assessor; no counters, samples or successful rows are made up.
export async function combineOrdinaryPerformanceMeasurements(root) {
  root = resolve(root);
  const controls = JSON.parse(await readFile(join(root, 'prepared/controls.json'), 'utf8'));
  const manifest = await readFile(join(root, 'packages/ordinary-operation-packages.json'));
  assert.equal(controls.cohortSha256, hash(manifest));
  assert.equal(controls.sourceSha, JSON.parse(manifest).sourceSha);
  assert.equal(controls.historyProtocolSha256, hash(JSON.stringify(nodeOperationProtocol('final'))));
  const binding = {cohortSha256: controls.cohortSha256,
    environmentSha256: hash(JSON.stringify(controls.environment)),
    historyProtocolSha256: controls.historyProtocolSha256};
  const combined = {sourceSha: controls.sourceSha, ...binding, latency: [],
    functional: {...binding, rows: []}, collectors: [],
    qualification: 'Actual warm, process and selected boundary reports only; unmeasured release gates remain incomplete.'};
  if (controls.comparison) {
    assert.deepEqual(controls.comparison.profile, calibrateSqliteComparisonProfile(controls.comparison.baseline, controls.comparison.resultControl),
      'Comparison differs from the baseline-only fixed policy');
    assert.deepEqual(controls.comparison.baseline.environment, controls.environment, 'Comparator environment differs');
    assert.equal(controls.comparison.baseline.load, controls.load, 'Comparator load differs');
    combined.comparison = controls.comparison;
  }
  for (const [family, operations] of Object.entries({warm: ['warm-select', 'warm-result', 'warm-status',
    ...nodeWarmSmallQueryFixtures.map(fixture => fixture.operation)],
    'cold-existing': ['cold-existing'], 'first-init': ['first-init']})) {
    const directory = join(root, 'measurement', family);
    let bytes;
    try { bytes = await readFile(join(directory, 'measurements.json')); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    assert(bytes.length <= 16 * 1024 ** 2, 'Collector report exceeds assessor input bound');
    const report = JSON.parse(bytes);
    assert.equal(report.sourceSha, combined.sourceSha, 'Collector source differs');
    for (const [key, value] of Object.entries(binding)) {
      assert.equal(report[key], value, `Collector ${key} differs`);
      assert.equal(report.functional[key], value, `Functional ${key} differs`);
    }
    assert.equal(report.mode, 'final');
    if (family === 'warm') assert.deepEqual(report.comparison, controls.comparison,
      'Collector comparison differs from the fixed pre-measurement profile');
    assert(report.firstFailure == null && report.packageFailure == null,
      'Collector recorded a public operation or package failure');
    assert.equal(report.installedPayloadsUnchanged, true, 'Collector package verification did not complete');
    assert(report.cleanup && report.cleanup.failure == null, 'Collector cleanup failed or is missing');
    if (family === 'warm') assert.equal(report.cleanup.closed, true, 'Original warm Client was not closed');
    else {
      assert.equal(report.cleanup.allChildrenExited, true, 'Original child processes did not exit');
      assert.equal(report.cleanup.allOriginalClientsClosed, true, 'Original child Clients were not closed');
    }
    const seen = new Set();
    for (const series of report.latency) {
      assert(operations.includes(series.operation) && !seen.has(series.operation), 'Foreign or duplicate operation');
      seen.add(series.operation);
      const fixture = nodeWarmSmallQueryFixtures.find(value => value.operation === series.operation);
      if (fixture) {
        assert.deepEqual(series.query, fixture, 'Collector query differs from the fixed protocol');
        const fixtureSha256 = hash(JSON.stringify(fixture));
        assert.equal(series.fixtureSha256, fixtureSha256, 'Collector query identity differs');
        assert(series.samples.every(sample => sample.fixtureSha256 === fixtureSha256),
          'Raw sample query identity differs');
      }
    }
    assert(report.functional.rows.every(row => seen.has(row.operation)));
    for (const row of report.functional.rows) {
      const fixture = nodeWarmSmallQueryFixtures.find(value => value.operation === row.operation);
      if (fixture) {
        const expectedSha256 = hash(JSON.stringify(fixture.expected));
        assert.equal(row.expectedSha256, expectedSha256, 'Functional query oracle differs');
        if (row.completed === true) assert.equal(row.actualSha256, expectedSha256,
          'Completed functional query result differs');
      }
    }
    const raw = await readFile(join(directory, 'samples.jsonl'), 'utf8');
    assert(Buffer.byteLength(raw) <= 16 * 1024 ** 2, 'Raw samples exceed assessor input bound');
    assert.deepEqual(raw.split('\n').filter(Boolean).map(line => JSON.parse(line)),
      report.latency.flatMap(series => series.samples.map(sample => ({operation: series.operation, ...sample}))),
      'Raw measurements differ from collector samples');
    combined.latency.push(...report.latency);
    combined.functional.rows.push(...report.functional.rows);
    combined.collectors.push({family, reportSha256: hash(bytes), rawSha256: hash(raw),
      cleanup: report.cleanup, firstFailure: report.firstFailure ?? null});
  }
  let boundaryBytes;
  try {boundaryBytes = await readFile(join(root, 'measurement/used-material/boundaries.json'));}
  catch (error) {if (error.code !== 'ENOENT') throw error;}
  if (boundaryBytes) {
    assert(boundaryBytes.length <= 16 * 1024 ** 2, 'Boundary report exceeds assessor input bound');
    const report = JSON.parse(boundaryBytes);
    assert.equal(report.sourceSha, combined.sourceSha, 'Boundary source differs');
    for (const [key, value] of Object.entries(binding)) {
      assert.equal(report[key], value, `Boundary ${key} differs`);
      assert.equal(report.boundaries[key], value, `Boundary section ${key} differs`);
    }
    assert.equal(hash(JSON.stringify(report.historyProtocol)), binding.historyProtocolSha256,
      'Boundary experiment protocol differs');
    assert.equal(report.mode, 'final');
    assert(report.firstFailure == null && report.packageFailure == null, 'Boundary operation or package failed');
    assert.equal(report.installedPayloadsUnchanged, true, 'Boundary package verification did not complete');
    assert(report.cleanup?.closed === true && report.cleanup.failure == null, 'Boundary original Client cleanup failed');
    assert.equal(report.latencyMeasured, false); assert.equal(report.fullAcceptance, false);
    assert.equal(report.boundaries.rows.length, 1, 'Exactly one selected boundary observation required');
    const row = report.boundaries.rows[0];
    assert.equal(row.case, 'used-row-tamper');
    assert(['rejected', 'succeeded'].includes(row.outcome), 'Selected boundary outcome is missing');
    assert.deepEqual(row, report.observedBoundary, 'Selected boundary observation differs');
    assert.equal(report.selectedBoundaryPassed, row.outcome === 'rejected');
    // A successful corrupt read is a failing observation, not missing coverage.
    combined.boundaries = report.boundaries;
    combined.collectors.push({family: 'used-material', reportSha256: hash(boundaryBytes),
      cleanup: report.cleanup, firstFailure: null, packageFailure: null});
  }
  const output = join(root, 'measurements.json');
  await writeFile(output, JSON.stringify(combined, null, 2) + '\n', {flag: 'wx'});
  return output;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (['inspect-producer', 'inspect-process-producer', 'inspect-native-approval-producer',
      'inspect-native-approval-source', 'inspect-source'].includes(command)) {
      const nativeApproval = command.startsWith('inspect-native-approval-');
      assert.equal(args.length, ['inspect-native-approval-source', 'inspect-source'].includes(command) ? 1 : 0);
      if (command === 'inspect-source') assert(['node', 'native', 'python'].includes(process.env.PACKAGE_ADAPTER));
      if (command === 'inspect-process-producer') {
        assert(['native', 'python'].includes(process.env.PACKAGE_ADAPTER), 'Exact process adapter is required');
      }
      console.log(JSON.stringify(await inspectPerformancePackageProducer({repository: process.env.GITHUB_REPOSITORY,
        sourceSha: process.env.PACKAGE_EVENT_HEAD_SHA ?? process.env.GITHUB_SHA,
        runId: process.env.PACKAGE_RUN_ID,
        artifactId: process.env.PACKAGE_ARTIFACT_ID, token: process.env.GITHUB_TOKEN,
        ...(nativeApproval ? {adapter: 'native', producerJob: process.env.PACKAGE_PRODUCER_JOB,
          nativeApproval: true, ...(args.length ? {nativePackages: resolve(args[0])} : {})} : {}),
        ...(command === 'inspect-source' ? {adapter: process.env.PACKAGE_ADAPTER, packages: resolve(args[0]),
          ...(process.env.PACKAGE_ADAPTER === 'node' ? {} : {producerJob: process.env.PACKAGE_PRODUCER_JOB})} : {}),
        ...(command === 'inspect-process-producer' ? {adapter: process.env.PACKAGE_ADAPTER,
          producerJob: process.env.PACKAGE_PRODUCER_JOB} : {})})));
    } else if (command === 'prepare-native') {
      assert.equal(args.length, 3);
      const before = checkoutState(process.cwd());
      assert(before.clean && before.revision === args[1], 'Performance checkout differs from the package source');
      console.log(JSON.stringify(await prepareOrdinaryNativePerformanceConsumer({packages: args[0],
        sourceSha: args[1], output: args[2]})));
      assert.deepEqual(checkoutState(process.cwd()), before);
    } else if (command === 'combine') {
      assert.equal(args.length, 1);
      console.log(await combineOrdinaryPerformanceMeasurements(args[0]));
    } else {
      assert.equal(command, 'prepare');
      assert(args.length >= 3 && (args.length - 3) % 2 === 0);
      const options = {};
      for (let i = 3; i < args.length; i += 2) {
        const key = {'--comparison': 'comparisonPath', '--selection': 'selection', '--mode': 'mode',
          '--resource-observations': 'resourceObservations', '--row-observations': 'rowObservations'}[args[i]];
        assert(key && !Object.hasOwn(options, key), 'Unknown or duplicate preparation option');
        options[key] = args[i + 1];
      }
      const before = checkoutState(process.cwd());
      assert(before.clean && before.revision === args[1], 'Performance checkout differs from the package source');
      const result = await prepareOrdinaryPerformanceConsumer({packages: args[0],
        sourceSha: args[1], output: args[2], ...options});
      assert.deepEqual(checkoutState(process.cwd()), before, 'Source changed during consumer preparation');
      console.log(JSON.stringify(result));
    }
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
