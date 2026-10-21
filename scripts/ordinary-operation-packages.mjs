// Reuse the existing normal Client artifact. This consumer never packs,
// compiles, publishes or substitutes source packages for a missing artifact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, totalmem} from 'node:os';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {CLIENT_PACKAGES, checkoutState} from './packed-client-packages.mjs';
import {inventory, unpack} from './package-release.mjs';
import {nodeOperationProtocol} from './benchmark-node-operations.mjs';

const hash = (value, algorithm = 'sha256', encoding = 'hex') =>
  createHash(algorithm).update(value).digest(encoding);
const positiveId = value => /^[1-9][0-9]*$/u.test(String(value ?? ''));

export function validatePerformancePackageProducer({repository, sourceSha, runId, artifactId,
  artifact, run, jobs}) {
  assert.match(repository, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u);
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  assert(positiveId(runId) && positiveId(artifactId), 'Exact producer run/artifact IDs are required');
  assert.equal(String(run.id), String(runId));
  assert.equal(run.repository.full_name, repository);
  assert.equal(run.head_sha, sourceSha, 'Producer source differs from the checked performance source');
  assert.equal(run.path.split('@')[0], '.github/workflows/ci.yml');
  assert.equal(run.status, 'completed');
  assert(positiveId(run.run_attempt));
  assert.equal(String(artifact.id), String(artifactId));
  assert.equal(artifact.expired, false);
  assert.equal(String(artifact.workflow_run.id), String(runId));
  assert.equal(artifact.workflow_run.head_sha, sourceSha);
  assert.equal(artifact.name, `actql-client-packages-${runId}-${run.run_attempt}-${sourceSha}`);
  const producers = jobs.filter(job => job.name === 'client-packages');
  assert.equal(producers.length, 1, 'Exactly one original Client package producer is required');
  assert.equal(producers[0].status, 'completed');
  assert.equal(producers[0].conclusion, 'success');
  assert.equal(producers[0].head_sha, sourceSha);
  return {repository, sourceSha, runId: String(runId), artifactId: String(artifactId),
    attempt: run.run_attempt, producerJobId: producers[0].id,
    qualification: 'Successful package producer only; other source-run failures remain failures.'};
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
  return validatePerformancePackageProducer({...options, run, artifact, jobs});
}

export async function prepareOrdinaryPerformanceConsumer({packages, sourceSha, output,
  install = (args, cwd) => execFileSync('npm', args, {cwd, stdio: 'inherit', timeout: 120_000})}) {
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
    historyProtocolSha256: hash(JSON.stringify(nodeOperationProtocol('final')))};
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
    qualification: 'Actual warm and process reports only; unmeasured release gates remain incomplete.'};
  for (const [family, operations] of Object.entries({warm: ['warm-select', 'warm-result', 'warm-status'],
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
    const seen = new Set();
    for (const series of report.latency) {
      assert(operations.includes(series.operation) && !seen.has(series.operation), 'Foreign or duplicate operation');
      seen.add(series.operation);
    }
    assert(report.functional.rows.every(row => seen.has(row.operation)));
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
  const output = join(root, 'measurements.json');
  await writeFile(output, JSON.stringify(combined, null, 2) + '\n', {flag: 'wx'});
  return output;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (command === 'inspect-producer') {
      assert.equal(args.length, 0);
      console.log(JSON.stringify(await inspectPerformancePackageProducer({repository: process.env.GITHUB_REPOSITORY,
        sourceSha: process.env.GITHUB_SHA, runId: process.env.PACKAGE_RUN_ID,
        artifactId: process.env.PACKAGE_ARTIFACT_ID, token: process.env.GITHUB_TOKEN})));
    } else if (command === 'combine') {
      assert.equal(args.length, 1);
      console.log(await combineOrdinaryPerformanceMeasurements(args[0]));
    } else {
      assert.equal(command, 'prepare'); assert.equal(args.length, 3);
      const before = checkoutState(process.cwd());
      assert(before.clean && before.revision === args[1], 'Performance checkout differs from the package source');
      const result = await prepareOrdinaryPerformanceConsumer({packages: args[0],
        sourceSha: args[1], output: args[2]});
      assert.deepEqual(checkoutState(process.cwd()), before, 'Source changed during consumer preparation');
      console.log(JSON.stringify(result));
    }
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
