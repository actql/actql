import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {CLIENT_PACKAGES} from './packed-client-packages.mjs';
import {validatePerformancePackageProducer, inspectPerformancePackageProducer,
  prepareOrdinaryPerformanceConsumer, combineOrdinaryPerformanceMeasurements,
  validatePerformanceProcessPackageProducer, prepareOrdinaryNativePerformanceConsumer} from './ordinary-operation-packages.mjs';
import {readFixedSQLiteComparison} from './ordinary-operation-packages.mjs';
import {nodeOperationProtocol, nodePriorityProtocol, nodeWarmSmallQueryFixtures} from './benchmark-node-operations.mjs';
import {assessPerformanceEvidence, calibrateSqliteComparisonProfile} from './operation-performance.mjs';
import {syntheticSQLiteBaseline, syntheticResultStorageControl} from './fixtures/operation-performance-comparison.mjs';

const sha = 'a'.repeat(40), hash = bytes => createHash('sha256').update(bytes).digest('hex');
function provenance() {
  return {repository: 'actql/actql', sourceSha: sha, runId: '17', artifactId: '23',
    run: {id: 17, run_attempt: 2, repository: {full_name: 'actql/actql'},
      head_sha: sha, path: '.github/workflows/ci.yml', status: 'completed', conclusion: 'failure'},
    artifact: {id: 23, expired: false, name: `actql-client-packages-17-2-${sha}`,
      workflow_run: {id: 17, head_sha: sha}},
    jobs: [{id: 41, name: 'client-packages', status: 'completed', conclusion: 'success', head_sha: sha}]};
}

test('reuse authenticates one successful original package job without relabeling its other failed jobs', () => {
  const result = validatePerformancePackageProducer(provenance());
  assert.equal(result.producerJobId, 41); assert.equal(result.attempt, 2);
  assert.match(result.qualification, /other source-run failures remain failures/u);
});
test('missing, foreign, expired, incomplete and duplicate producers cannot select an artifact', () => {
  for (const mutate of [p => {p.artifactId = '';}, p => {p.runId = '17,18';},
    p => {p.run.repository.full_name = 'foreign/repo';}, p => {p.run.head_sha = 'b'.repeat(40);},
    p => {p.run.path = '.github/workflows/unrelated.yml';}, p => {p.run.status = 'in_progress';},
    p => {p.artifact.expired = true;}, p => {p.artifact.workflow_run.id = 18;},
    p => {p.artifact.workflow_run.head_sha = 'b'.repeat(40);}, p => {p.artifact.name = `actql-client-packages-17-1-${sha}`;},
    p => {p.jobs[0].conclusion = 'failure';}, p => {p.jobs.push({...p.jobs[0], id: 42});},
    p => {p.jobs[0].head_sha = 'b'.repeat(40);}, p => {p.jobs = [];},
  ]) { const p = provenance(); mutate(p); assert.throws(() => validatePerformancePackageProducer(p)); }
});
test('metadata lookup reads the original attempt and complete job pages', async () => {
  const p = provenance(), calls = [];
  const result = await inspectPerformancePackageProducer({...p, token: 'test-only'}, async (url, options) => {
    calls.push(url); assert.equal(options.redirect, 'error');
    const value = url.endsWith('/runs/17') ? p.run : url.endsWith('/artifacts/23') ? p.artifact
      : url.endsWith('page=1') ? {total_count: 2, jobs: [{id: 7, name: 'lint'}]}
      : {total_count: 2, jobs: p.jobs};
    return {ok: true, text: async () => JSON.stringify(value)};
  });
  assert.equal(result.producerJobId, 41);
  assert(calls[2].includes('/runs/17/attempts/2/jobs?'));
  assert.equal(calls.length, 4);
});
test('metadata failure never falls back to an unverified artifact or package producer', async () => {
  await assert.rejects(inspectPerformancePackageProducer({...provenance(), token: 'test-only'},
    async () => ({ok: false, status: 404})), /Cannot read original package metadata/u);
});

test('ordinary process artifacts bind the actual source run and selected successful job', () => {
  for (const adapter of ['native', 'python']) {
    const input = () => ({...provenance(), adapter, producerJob: 'client-packages'});
    const result = validatePerformanceProcessPackageProducer(input());
    assert.equal(result.adapter, adapter); assert.equal(result.producerJobId, 41);
    for (const mutate of [p => {p.producerJob = '';}, p => {p.producerJob = 'missing';},
      p => {p.run.head_sha = 'b'.repeat(40);}, p => {p.artifact.workflow_run.id = 19;},
      p => {p.artifact.workflow_run.head_sha = 'b'.repeat(40);}, p => {p.artifact.expired = true;},
      p => {p.jobs[0].conclusion = 'failure';}, p => {p.jobs.push({...p.jobs[0]});},
      p => {p.run.status = 'in_progress';}, p => {p.artifactId = '';}, p => {p.adapter = 'node';}]) {
      const p = input(); mutate(p); assert.throws(() => validatePerformanceProcessPackageProducer(p));
    }
  }
});

test('ordinary process inspection cannot fall back to Client artifacts when its adapter is missing', () => {
  for (const adapter of [undefined, '', 'node']) {
    const env = {...process.env}; delete env.PACKAGE_ADAPTER;
    if (adapter !== undefined) env.PACKAGE_ADAPTER = adapter;
    const child = spawnSync(process.execPath, ['scripts/ordinary-operation-packages.mjs', 'inspect-process-producer'],
      {env, encoding: 'utf8', timeout: 5000});
    assert.equal(child.status, 1);
    assert.match(child.stderr, /Exact process adapter is required/u);
  }
});

test('ordinary Native installation resolves only fixed artifacts and always closes its registry', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-performance-install-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const manifest = {sourceSha: sha, cohort: {packageVersion: '0.1.0'}};
  let closed = 0, installs = 0;
  const options = {packages: join(root, 'packages'), sourceSha: sha,
    verify: async () => manifest,
    openRegistry: async entries => {
      assert.equal(entries[0].manifest, manifest);
      return {url: 'http://127.0.0.1:12345/', close: async () => {closed++;}};
    }, install: async (args, {env}) => {
      installs++;
      assert.deepEqual(args.slice(0, 2), ['install', '-g']);
      assert(args.includes('--ignore-scripts')); assert(args.includes('--no-audit'));
      assert.equal(args.at(-1), 'actql@0.1.0');
      assert.equal(env.npm_config_registry, 'http://127.0.0.1:12345/');
      assert.equal(env.NODE_PATH, undefined);
      assert.match(await readFile(env.npm_config_userconfig, 'utf8'), /@actql:registry=http:\/\/127\.0\.0\.1:12345\//u);
    }};
  const result = await prepareOrdinaryNativePerformanceConsumer({...options, output: join(root, 'success')});
  assert.equal(result.consumer, join(root, 'success/lib/node_modules/actql'));
  assert.equal(installs, 1); assert.equal(closed, 1);
  await assert.rejects(prepareOrdinaryNativePerformanceConsumer({...options,
    output: join(root, 'failed'), install: async () => {throw new Error('Actual install failure');}}), /Actual install failure/u);
  assert.equal(closed, 2);
  await assert.rejects(prepareOrdinaryNativePerformanceConsumer({...options,
    sourceSha: 'b'.repeat(40), output: join(root, 'foreign')}), /differ/u);
  assert.equal(installs, 1); assert.equal(closed, 2);
});

async function packages(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-performance-artifact-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packed = join(root, 'packed'); await mkdir(packed);
  const tarballs = {};
  for (const name of CLIENT_PACKAGES) {
    const dir = join(root, name, 'package'); await mkdir(dir, {recursive: true});
    await writeFile(join(dir, 'package.json'), JSON.stringify({name: `@actql/${name}`, version: '0.0.0-development'}));
    await writeFile(join(dir, 'index.mjs'), '// Synthetic artifact fixture; no product operation.\n');
    const archive = join(packed, `actql-${name}-0.0.0-development.tgz`);
    // Keep this archive limited to the authored fixture payload.
    execFileSync('tar', ['-czf', archive, '-C', join(root, name), 'package'],
      {env: {...process.env, COPYFILE_DISABLE: '1'}});
    tarballs[name] = hash(await readFile(archive));
  }
  await writeFile(join(packed, 'packed-client-packages.json'), JSON.stringify({revision: sha, tarballs}));
  return {root, packages: packed, sourceSha: sha, output: join(root, 'prepared')};
}
async function syntheticInstall(args, cwd) {
  assert.deepEqual(args.slice(0, 4), ['install', '--no-audit', '--no-fund', '--no-save']);
  assert.equal(args.length, 9); // Five original tarballs, no pack/build command.
  for (const name of CLIENT_PACKAGES) {
    await cp(join(cwd, '..', `original-${name}`, 'package'), join(cwd, 'node_modules', '@actql', name), {recursive: true});
  }
}
test('existing five tarballs become the collector manifest and a fresh ordinary-install command', async t => {
  const p = await packages(t);
  const result = await prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall});
  const manifest = JSON.parse(await readFile(result.manifestPath));
  assert.equal(manifest.sourceSha, sha);
  assert.deepEqual(manifest.packages.map(row => row.name), CLIENT_PACKAGES.map(name => `@actql/${name}`));
  for (const item of manifest.packages) {
    assert.equal(item.files.length, 2); assert(item.files.some(row => row.path === 'index.mjs'));
  }
  const controls = JSON.parse(await readFile(result.controlsPath));
  assert.equal(controls.cohortSha256, hash(await readFile(result.manifestPath)));
  assert.equal(controls.sourceSha, sha); assert.equal(controls.load, 'isolated');
  assert.equal(controls.historyProtocolSha256, hash(JSON.stringify(nodeOperationProtocol('final'))));
  await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall}));
});
test('priority consumer controls bind the explicit protocol without inventing experiment observations', async t => {
  for (const mode of ['diagnostic', 'final']) {
    const p = await packages(t);
    const result = await prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall,
      selection: 'priority-transition', mode});
    const controls = JSON.parse(await readFile(result.controlsPath));
    assert.equal(controls.historyProtocolSha256, hash(JSON.stringify(nodePriorityProtocol(mode))));
    assert.equal(controls.cohortSha256, hash(await readFile(result.manifestPath)));
    assert.equal(controls.sourceSha, sha);
    for (const key of ['comparison', 'priorityConditions', 'population', 'boundaries']) {
      assert.equal(Object.hasOwn(controls, key), false, `${key} must come from actual observation`);
    }
  }
});
test('managed Run priority controls bind only the selected resource-observation protocol', async t => {
  for (const mode of ['diagnostic', 'final']) {
    const p = await packages(t);
    const result = await prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall,
      selection: 'priority-transition', mode, resourceObservations: 'managed-run-ledger'});
    const controls = JSON.parse(await readFile(result.controlsPath));
    assert.equal(controls.historyProtocolSha256,
      hash(JSON.stringify(nodePriorityProtocol(mode, 'managed-run-ledger'))));
    assert.notEqual(controls.historyProtocolSha256, hash(JSON.stringify(nodePriorityProtocol(mode))));
    assert.equal(controls.cohortSha256, hash(await readFile(result.manifestPath)));
    assert.equal(controls.sourceSha, sha);
    for (const key of ['comparison', 'priorityConditions', 'population', 'boundaries', 'managedRunObservations']) {
      assert.equal(Object.hasOwn(controls, key), false, `${key} is not issued by protocol selection`);
    }
  }
});

test('selected-row priority controls bind only the requested collection protocol', async t => {
  for (const mode of ['diagnostic', 'final']) {
    for (const resourceObservations of [undefined, 'managed-run-ledger']) {
      const p = await packages(t);
      const result = await prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall,
        selection: 'priority-transition', mode, resourceObservations, rowObservations: 'selected-returned'});
      const controls = JSON.parse(await readFile(result.controlsPath));
      assert.equal(controls.historyProtocolSha256,
        hash(JSON.stringify(nodePriorityProtocol(mode, resourceObservations, 'selected-returned'))));
      assert.notEqual(controls.historyProtocolSha256,
        hash(JSON.stringify(nodePriorityProtocol(mode, resourceObservations))));
      assert.equal(controls.cohortSha256, hash(await readFile(result.manifestPath)));
      assert.equal(controls.sourceSha, sha);
      for (const key of ['comparison', 'priorityConditions', 'population', 'boundaries',
        'managedRunObservations', 'selectedRowObservations']) {
        assert.equal(Object.hasOwn(controls, key), false, `${key} must come from actual observation`);
      }
    }
  }
});

test('unknown or mixed priority preparation options refuse before installation', async t => {
  for (const options of [
    {selection: 'unknown'}, {mode: 'diagnostic'},
    {selection: 'priority-transition', mode: 'unknown'},
    {selection: 'priority-transition', comparisonPath: 'unused'},
    {resourceObservations: 'managed-run-ledger'},
    {selection: 'priority-transition', resourceObservations: 'unknown'},
    {selection: 'priority-transition', resourceObservations: ''},
    {rowObservations: 'selected-returned'},
    {selection: 'priority-transition', rowObservations: 'unknown'},
    {selection: 'priority-transition', rowObservations: ''},
  ]) {
    const p = await packages(t); let installs = 0;
    await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, ...options,
      install: () => { installs++; }}));
    assert.equal(installs, 0);
    await assert.rejects(readFile(join(p.output, 'controls.json')), {code: 'ENOENT'});
  }
});
test('a missing or corrupted original tarball cannot trigger install or build fallback', async t => {
  for (const corrupt of [false, true]) {
    const p = await packages(t); let installs = 0;
    const path = join(p.packages, 'actql-node-0.0.0-development.tgz');
    if (corrupt) await writeFile(path, 'changed'); else await rm(path);
    await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, install: () => { installs++; }}));
    assert.equal(installs, 0);
  }
});
test('foreign source and altered installed payloads refuse instead of qualifying another cohort', async t => {
  const p = await packages(t);
  await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, sourceSha: 'b'.repeat(40), install: syntheticInstall}));
  await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, install: async (args, cwd) => {
    await syntheticInstall(args, cwd);
    await writeFile(join(cwd, 'node_modules/@actql/node/index.mjs'), 'changed');
  }}));
});

test('CLI uses an unchanged checkout and actual default npm installation of only retained synthetic tarballs', async t => {
  const p = await packages(t), repository = join(p.root, 'checkout');
  await mkdir(repository);
  execFileSync('git', ['init', '-q'], {cwd: repository});
  execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'test: synthetic source'], {cwd: repository});
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const file = join(p.packages, 'packed-client-packages.json');
  const manifest = JSON.parse(await readFile(file)); manifest.revision = source;
  await writeFile(file, JSON.stringify(manifest));
  const script = fileURLToPath(new URL('./ordinary-operation-packages.mjs', import.meta.url));
  const run = candidate => spawnSync(process.execPath, [script, 'prepare', p.packages, candidate, p.output], {
    cwd: repository, env: {...process.env, npm_config_cache: join(p.root, 'npm-cache')},
    encoding: 'utf8', timeout: 30_000,
  });
  const foreign = run(sha); assert.notEqual(foreign.status, 0);
  assert.match(foreign.stderr, /Performance checkout differs/u);
  const installed = run(source); assert.equal(installed.status, 0, installed.stderr);
  assert.equal(JSON.parse(await readFile(join(p.output, 'consumer/node_modules/@actql/node/package.json'))).name, '@actql/node');
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: repository, encoding: 'utf8'}), '');
});
test('priority CLI prepares the tested protocol from retained synthetic tarballs', async t => {
  const p = await packages(t), repository = join(p.root, 'checkout');
  await mkdir(repository);
  execFileSync('git', ['init', '-q'], {cwd: repository});
  execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'test: synthetic source'], {cwd: repository});
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const file = join(p.packages, 'packed-client-packages.json');
  const manifest = JSON.parse(await readFile(file)); manifest.revision = source;
  await writeFile(file, JSON.stringify(manifest));
  const script = fileURLToPath(new URL('./ordinary-operation-packages.mjs', import.meta.url));
  const argv = [script, 'prepare', p.packages, source, p.output,
    '--selection', 'priority-transition', '--mode', 'diagnostic'];
  const options = {cwd: repository, env: {...process.env, npm_config_cache: join(p.root, 'npm-cache')},
    encoding: 'utf8', timeout: 30_000};
  const duplicate = spawnSync(process.execPath, [...argv, '--mode', 'final'], options);
  assert.notEqual(duplicate.status, 0);
  assert.match(duplicate.stderr, /Unknown or duplicate preparation option/u);
  const result = spawnSync(process.execPath, argv, options);
  assert.equal(result.status, 0, result.stderr);
  const controls = JSON.parse(await readFile(join(p.output, 'controls.json')));
  assert.equal(controls.historyProtocolSha256, hash(JSON.stringify(nodePriorityProtocol('diagnostic'))));
  assert.equal(controls.sourceSha, source);
  assert.equal(Object.hasOwn(controls, 'comparison'), false);
  assert.equal(Object.hasOwn(controls, 'priorityConditions'), false);
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: repository, encoding: 'utf8'}), '');
});

test('managed Run priority CLI binds the same option and rejects duplicate selection', async t => {
  const p = await packages(t), repository = join(p.root, 'checkout');
  await mkdir(repository);
  execFileSync('git', ['init', '-q'], {cwd: repository});
  execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'test: synthetic source'], {cwd: repository});
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const file = join(p.packages, 'packed-client-packages.json');
  const manifest = JSON.parse(await readFile(file)); manifest.revision = source;
  await writeFile(file, JSON.stringify(manifest));
  const script = fileURLToPath(new URL('./ordinary-operation-packages.mjs', import.meta.url));
  const argv = [script, 'prepare', p.packages, source, p.output,
    '--selection', 'priority-transition', '--mode', 'diagnostic',
    '--resource-observations', 'managed-run-ledger'];
  const options = {cwd: repository, env: {...process.env, npm_config_cache: join(p.root, 'npm-cache')},
    encoding: 'utf8', timeout: 30_000};
  const duplicate = spawnSync(process.execPath, [...argv, '--resource-observations', 'managed-run-ledger'], options);
  assert.notEqual(duplicate.status, 0);
  assert.match(duplicate.stderr, /Unknown or duplicate preparation option/u);
  const result = spawnSync(process.execPath, argv, options);
  assert.equal(result.status, 0, result.stderr);
  const controls = JSON.parse(await readFile(join(p.output, 'controls.json')));
  assert.equal(controls.historyProtocolSha256,
    hash(JSON.stringify(nodePriorityProtocol('diagnostic', 'managed-run-ledger'))));
  assert.equal(controls.sourceSha, source);
  assert.equal(Object.hasOwn(controls, 'managedRunObservations'), false);
  assert.equal(Object.hasOwn(controls, 'population'), false);
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: repository, encoding: 'utf8'}), '');
});

test('selected-row priority CLI forwards the exact option with and without managed Run capture', async t => {
  for (const resourceObservations of [undefined, 'managed-run-ledger']) {
    const p = await packages(t), repository = join(p.root, 'checkout');
    await mkdir(repository);
    execFileSync('git', ['init', '-q'], {cwd: repository});
    execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
      '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'test: synthetic source'], {cwd: repository});
    const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
    const file = join(p.packages, 'packed-client-packages.json');
    const manifest = JSON.parse(await readFile(file)); manifest.revision = source;
    await writeFile(file, JSON.stringify(manifest));
    const script = fileURLToPath(new URL('./ordinary-operation-packages.mjs', import.meta.url));
    const argv = [script, 'prepare', p.packages, source, p.output,
      '--selection', 'priority-transition', '--mode', 'diagnostic',
      '--row-observations', 'selected-returned',
      ...(resourceObservations ? ['--resource-observations', resourceObservations] : [])];
    const options = {cwd: repository, env: {...process.env, npm_config_cache: join(p.root, 'npm-cache')},
      encoding: 'utf8', timeout: 30_000};
    const duplicate = spawnSync(process.execPath, [...argv, '--row-observations', 'selected-returned'], options);
    assert.notEqual(duplicate.status, 0);
    assert.match(duplicate.stderr, /Unknown or duplicate preparation option/u);
    const result = spawnSync(process.execPath, argv, options);
    assert.equal(result.status, 0, result.stderr);
    const controls = JSON.parse(await readFile(join(p.output, 'controls.json')));
    assert.equal(controls.historyProtocolSha256,
      hash(JSON.stringify(nodePriorityProtocol('diagnostic', resourceObservations, 'selected-returned'))));
    assert.equal(controls.sourceSha, source);
    for (const key of ['managedRunObservations', 'selectedRowObservations', 'population']) {
      assert.equal(Object.hasOwn(controls, key), false);
    }
    assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: repository, encoding: 'utf8'}), '');
  }
});

test('controlled performance check consumes existing artifacts and cannot omit failed or missing raw assessment', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  assert.deepEqual(ci.jobs['performance-matrix'].with, {
    'priority-node-mode': '${{ inputs.performance_priority_node_mode }}',
    'priority-python-mode': '${{ inputs.performance_priority_python_mode }}',
    'package-run-id': '${{ inputs.performance_package_run_id }}',
    'package-artifact-id': '${{ inputs.performance_package_artifact_id }}',
    'native-package-run-id': '${{ inputs.performance_native_package_run_id }}',
    'native-package-artifact-id': '${{ inputs.performance_native_package_artifact_id }}',
    'native-package-producer-job': "${{ fromJSON(inputs.performance_process_package_jobs || '{}').native || '' }}",
    'python-package-run-id': '${{ inputs.performance_python_package_run_id }}',
    'python-package-artifact-id': '${{ inputs.performance_python_package_artifact_id }}',
    'python-package-producer-job': "${{ fromJSON(inputs.performance_process_package_jobs || '{}').python || '' }}",
  });
  assert.ok(ci.jobs.lint.steps.some(s => s.run === 'node --test scripts/ordinary-operation-packages.test.mjs'));
  assert.equal(ci.jobs.lint.steps.find(s => s.name === 'Test ordinary operation performance assessment').run,
    'node --test scripts/operation-performance.test.mjs scripts/benchmark-node-operations.test.mjs scripts/operation-performance-policy.test.mjs scripts/operation-performance-native-control.test.mjs scripts/benchmark-node-process-operations.test.mjs scripts/benchmark-node-sqlite.test.mjs scripts/benchmark-node-boundaries.test.mjs scripts/node-operation-fs-trace.test.mjs scripts/operation-performance-priority-transition.test.mjs scripts/operation-performance-transition-ci.test.mjs');
  const job = workflow.jobs['ordinary-operations'];
  assert.equal(job.permissions.actions, 'read');
  const inspect = job.steps.findIndex(s => s.name === 'Validate the original normal package producer');
  const download = job.steps.findIndex(s => s.name === 'Reuse the exact existing normal package artifact');
  const prepare = job.steps.findIndex(s => s.name === 'Install a fresh ordinary consumer without a producer fallback');
  const baseline = job.steps.findIndex(s => s.name === 'Measure the same-machine local SQLite diagnostic baseline');
  const calibrate = job.steps.findIndex(s => s.name === 'Freeze the baseline-only comparison before candidate measurements');
  const measure = job.steps.findIndex(s => s.name === 'Measure completed public operations from the installed cohort');
  const boundary = job.steps.findIndex(s => s.name === 'Check selected Result material integrity using the installed cohort');
  const assess = job.steps.findIndex(s => s.name === 'Require measured latency and structural release evidence');
  assert(inspect < download && download < baseline && baseline < calibrate && calibrate < prepare && prepare < measure && measure < assess);
  assert(prepare < boundary && boundary < measure);
  assert(job.steps[boundary].run.includes('scripts/benchmark-node-boundaries.mjs'));
  assert(job.steps[boundary].run.includes('--manifest "$RUNNER_TEMP/ordinary-operation/packages/ordinary-operation-packages.json"'));
  assert(job.steps[boundary].run.includes('--consumer "$RUNNER_TEMP/ordinary-operation/prepared/consumer"'));
  assert(job.steps[boundary].run.includes('--controls "$RUNNER_TEMP/ordinary-operation/prepared/controls.json"'));
  assert(job.steps[boundary].run.includes('--output "$RUNNER_TEMP/ordinary-operation/measurement/used-material"'));
  assert(job.steps[boundary].run.endsWith('--mode final\n'));
  assert.equal(job.steps[boundary]['continue-on-error'], undefined);
  assert(job.steps[baseline].run.includes('--warm-samples 100 --cold-samples 5 --load isolated'));
  assert(job.steps[calibrate].run.includes('--calibrate-sqlite'));
  assert(job.steps[prepare].run.endsWith('--comparison "$RUNNER_TEMP/ordinary-operation/comparison.json"'));
  assert.equal(job.steps[download].with['artifact-ids'], '${{ inputs.package-artifact-id }}');
  assert.equal(job.steps[assess].if, 'always()');
  assert.equal(job.steps[assess]['continue-on-error'], undefined);
  assert.equal(job.steps[measure]['continue-on-error'], undefined);
  assert(job.steps[measure].run.endsWith('--mode final\n'));
  assert(job.steps[assess].run.includes('scripts/operation-performance.mjs --input'));
  const upload = job.steps.at(-1); assert.equal(upload.if, 'always()');
  assert(upload.with.path.includes('/measurement/*/*.jsonl'));
  assert(upload.with.path.includes('/sqlite/sqlite-baseline.json'));
  assert(upload.with.path.includes('/comparison.json'));
  const cold = job.steps.findIndex(s => s.name === 'Measure existing-state reads in new processes');
  const init = job.steps.findIndex(s => s.name === 'Measure first initialization in distinct new states');
  const combine = job.steps.findIndex(s => s.name === 'Bind actual reports to the same cohort and raw samples');
  assert(measure < cold && cold < init && init < combine && combine < assess);
  for (const index of [cold, init]) {
    assert(job.steps[index].run.includes('scripts/benchmark-node-process-operations.mjs'));
    assert.equal(job.steps[index]['continue-on-error'], undefined);
    assert(job.steps[index].run.includes('--consumer "$RUNNER_TEMP/ordinary-operation/prepared/consumer"'));
  }
  assert(job.steps[cold].run.includes('--operation cold-existing'));
  assert(job.steps[init].run.includes('--operation first-init'));
  assert.equal(job.steps[combine].if, 'always()');
  assert(!job.steps.some(s => /setup-toolchain|setup-moonbit/u.test(s.uses ?? '')));
  assert(!job.steps.some(s => /\b(?:npm pack|moon build|packed-client-packages\.mjs)\b/u.test(s.run ?? '')));
});

test('ordinary platform assessment rejects missing, failed and skipped public collectors', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const names = ['ordinary-operations', 'ordinary-native', 'ordinary-python'];
  const job = workflow.jobs['ordinary-platform-assessment'];
  assert(job, 'Required public Node, Native and Python assessment is missing');
  assert.deepEqual(job.needs, names);
  assert(job.if.includes('always()'));
  const step = job.steps.find(value => value.env?.RESULTS === '${{ toJSON(needs) }}');
  assert(step, 'Assessment must consume the actual collector job results');
  assert.equal(step['continue-on-error'], undefined);
  const run = results => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    encoding: 'utf8', env: {...process.env, RESULTS: JSON.stringify(results)},
    timeout: 5000, maxBuffer: 65536,
  });
  const complete = Object.fromEntries(names.map(name => [name, {result: 'success'}]));
  assert.equal(run(complete).status, 0);
  for (const name of names) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const child = run({...complete, [name]: {result}});
      assert.equal(child.status, 1, `${name}: ${result}\n${child.stdout}\n${child.stderr}`);
    }
    const missing = {...complete}; delete missing[name];
    assert.equal(run(missing).status, 1, `Missing ${name} must not pass`);
  }
  assert.equal(run({}).status, 1);
  assert.equal(run({...complete, unrelated: {result: 'success'}}).status, 1);
});

test('ordinary process producer names stay empty on non-performance entry without invented jobs', () => {
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  for (const adapter of ['native', 'python']) {
    const expression = ci.jobs['performance-matrix'].with[`${adapter}-package-producer-job`].slice(3, -2);
    for (const inputs of [{}, {performance_process_package_jobs: ''}, {performance_process_package_jobs: '{}'}]) {
      assert.equal(runInNewContext(expression, {inputs, fromJSON: JSON.parse}, {timeout: 100}), '');
    }
    assert.equal(runInNewContext(expression, {inputs: {performance_process_package_jobs: '{"native":"actual Native job","python":"actual Python job"}'},
      fromJSON: JSON.parse}, {timeout: 100}), `actual ${adapter === 'native' ? 'Native' : 'Python'} job`);
  }
});

test('ordinary platform assessment depends on real required artifact collectors', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  for (const name of workflow.jobs['ordinary-platform-assessment'].needs) {
    const job = workflow.jobs[name];
    assert(job, `Missing ordinary platform collector: ${name}`);
    assert.equal(job['continue-on-error'], undefined);
    assert(job.steps.some(step => step.uses?.startsWith('actions/download-artifact@')),
      `${name} must reuse an actual artifact`);
    assert(!job.steps.some(step => /\b(?:moon build|npm pack|pip wheel)\b/u.test(step.run ?? '')),
      `${name} must not replace missing artifacts with a producer`);
    assert(job.steps.some(step => step.if === 'always()' &&
      step.uses?.startsWith('actions/upload-artifact@')), `${name} must retain failed and incomplete evidence`);
  }
});

test('ordinary process jobs execute the tested collector contract and retain assessment failure', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const root = await mkdtemp(join(tmpdir(), 'actql-platform-command test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const bin = join(root, 'bin'); await mkdir(bin);
  for (const executable of ['python3', 'node']) {
    const path = join(bin, executable);
    await writeFile(path, `#!${process.execPath}\nrequire('node:fs').writeFileSync(process.env.ARGV, JSON.stringify(process.argv.slice(2)));process.exit(1);\n`);
    await chmod(path, 0o755);
  }
  for (const adapter of ['native', 'python']) {
    const job = workflow.jobs[`ordinary-${adapter}`];
    assert.deepEqual(job.strategy.matrix.operation, adapter === 'native'
      ? ['first-init', 'cold-existing', 'native-operations'] : ['first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status']);
    const collect = job.steps.find(step => step.run?.includes('scripts/benchmark-ordinary-processes.py'));
    const assess = job.steps.find(step => step.run?.includes('scripts/operation-performance.mjs --input'));
    assert.equal(collect.if, adapter === 'native' ? "matrix.operation != 'native-operations'" : undefined);
    assert.equal(assess.if, adapter === 'native' ? "always() && matrix.operation != 'native-operations'" : 'always()');
    assert.equal(assess['continue-on-error'], undefined);
    const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: root,
      GITHUB_SHA: sha, ARGV: join(root, `${adapter}.json`)};
    const body = collect.run.replaceAll('${{ matrix.operation }}', 'cold-existing')
      .replaceAll('${{ steps.consumer.outputs.path }}', join(root, 'site-packages'));
    const child = spawnSync('bash', ['-eo', 'pipefail', '-c', body], {env, encoding: 'utf8', timeout: 5000});
    assert.equal(child.status, 1, child.stderr);
    const args = JSON.parse(await readFile(env.ARGV, 'utf8'));
    assert.deepEqual(args.slice(0, 5), ['-I', '-B', 'scripts/benchmark-ordinary-processes.py', '--adapter', adapter]);
    assert.equal(args[args.indexOf('--source') + 1], sha);
    assert.equal(args[args.indexOf('--operation') + 1], 'cold-existing');
    assert.equal(args[args.indexOf('--mode') + 1], 'final');
    assert.equal(args[args.indexOf('--consumer') + 1], adapter === 'native'
      ? join(root, 'ordinary-native/consumer/lib/node_modules/actql') : join(root, 'site-packages'));
    if (adapter === 'python') assert.equal(args[args.indexOf('--venv') + 1], join(root, 'ordinary-python/venv'));
    const assessed = spawnSync('bash', ['-eo', 'pipefail', '-c', assess.run], {env, encoding: 'utf8', timeout: 5000});
    assert.equal(assessed.status, 1, assessed.stderr);
    assert.equal(JSON.parse(await readFile(env.ARGV, 'utf8'))[0], 'scripts/operation-performance.mjs');
  }
  const entry = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  // GitHub.com workflow_dispatch supports 25 inputs, matching the priority lane's check.
  // https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatchinputs
  assert(Object.keys(entry.on.workflow_dispatch.inputs).length <= 25);
  for (const adapter of ['native', 'python']) {
    for (const key of ['run-id', 'artifact-id', 'producer-job']) {
      assert(workflow.on.workflow_call.inputs[`${adapter}-package-${key}`].required);
      assert(entry.jobs['performance-matrix'].with[`${adapter}-package-${key}`]);
    }
  }
});

test('Native operation artifact row selects its actual collector and refuses missing or failed evidence', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['ordinary-native'];
  const collectors = job.steps.filter(step => step.run?.includes('scripts/benchmark-ordinary-processes.py'));
  const assessors = job.steps.filter(step => step.run?.includes('scripts/operation-performance.mjs --'));
  for (const operation of job.strategy.matrix.operation) {
    const selected = steps => steps.filter(step => runInNewContext(step.if ?? 'true', {
      matrix: {operation}, always: () => true,
    }, {timeout: 100}));
    assert.equal(selected(collectors).length, 1);
    assert.equal(selected(assessors).length, 1);
    assert.equal(selected(collectors)[0].run.includes('--selection native-operations'), operation === 'native-operations');
    assert.equal(selected(assessors)[0].run.includes('--native-operations'), operation === 'native-operations');
    assert(selected(assessors)[0].if.startsWith('always()'));
  }
  const collect = collectors.find(step => step.run.includes('--selection native-operations'));
  const assess = assessors.find(step => step.run.includes('--native-operations'));
  assert.equal(collect['continue-on-error'], undefined);
  assert.equal(assess['continue-on-error'], undefined);
  const root = await mkdtemp(join(tmpdir(), 'actql-native-operation-command-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const bin = join(root, 'bin'); await mkdir(bin);
  for (const executable of ['python3', 'node']) {
    const path = join(bin, executable);
    await writeFile(path, `#!${process.execPath}\nrequire('node:fs').writeFileSync(process.env.ARGV, JSON.stringify(process.argv.slice(2)));process.exit(Number(process.env.COMMAND_STATUS));\n`);
    await chmod(path, 0o755);
  }
  const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: root,
    GITHUB_SHA: sha, ARGV: join(root, 'args.json'), COMMAND_STATUS: '1'};
  const run = step => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {env, encoding: 'utf8', timeout: 5000});
  const collected = run(collect); assert.equal(collected.status, 1, collected.stderr);
  const args = JSON.parse(await readFile(env.ARGV, 'utf8'));
  assert.deepEqual(args.slice(0, 5), ['-I', '-B', 'scripts/benchmark-ordinary-processes.py', '--adapter', 'native']);
  const expected = {
    '--manifest': join(root, 'ordinary-native/packages/release.json'),
    '--consumer': join(root, 'ordinary-native/consumer/lib/node_modules/actql'),
    '--source': sha, '--selection': 'native-operations', '--mode': 'final', '--load': 'isolated',
    '--output': join(root, 'ordinary-native/measurement'),
  };
  for (const [flag, value] of Object.entries(expected)) assert.equal(args[args.indexOf(flag) + 1], value);
  assert(!args.includes('--operation'));
  const assessed = run(assess); assert.equal(assessed.status, 1, assessed.stderr);
  assert.deepEqual(JSON.parse(await readFile(env.ARGV, 'utf8')), ['scripts/operation-performance.mjs',
    '--native-operations', join(root, 'ordinary-native/measurement/measurements.json'),
    '--output', join(root, 'ordinary-native/assessment.json')]);
  // Execute the real assessor with absent raw measurements: missing evidence cannot pass the lane.
  const missing = spawnSync(process.execPath, ['scripts/operation-performance.mjs',
    '--native-operations', join(root, 'missing.json'), '--output', join(root, 'missing-assessment.json')], {
    cwd: fileURLToPath(new URL('..', import.meta.url)), encoding: 'utf8', timeout: 5000,
  });
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /ENOENT|missing/iu);
});

test('ordinary Python setup validates original wheels before offline binary-only installation', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const step = workflow.jobs['ordinary-python'].steps.find(step => step.id === 'consumer');
  const source = step.run.split("<<'PYTHON'\n")[1].split('\nPYTHON')[0];
  const root = await mkdtemp(join(tmpdir(), 'actql-python-performance-setup-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packages = join(root, 'ordinary-python/packages'); await mkdir(join(packages, 'wheels'), {recursive: true});
  const wheels = [];
  for (const distribution of ['actql', 'actql-sdk', 'actql-local-runtime']) {
    const file = `${distribution}.whl`, bytes = Buffer.from(`Explicit synthetic ${distribution} wheel metadata fixture`);
    await writeFile(join(packages, 'wheels', file), bytes);
    wheels.push({distribution, file, bytes: bytes.length, sha256: hash(bytes)});
  }
  const manifest = {source_sha: sha, package_version: '0.1.0', wheels};
  const path = join(packages, 'cohort.json'); await writeFile(path, JSON.stringify(manifest));
  const log = join(root, 'commands.json'), output = join(root, 'outputs');
  const harness = `import json,os,subprocess\nfrom unittest.mock import patch\ncommands=[]\ndef run(args,check):\n commands.append(args)\nclass Result: pass\ntry:\n with patch.object(subprocess,'run',run),patch.object(subprocess,'check_output',return_value='/explicit/synthetic/site-packages\\n'):\n  exec(compile(${JSON.stringify(source)},'<actual-workflow-python-setup>','exec'))\nfinally:\n open(os.environ['COMMAND_LOG'],'w').write(json.dumps(commands))\n`;
  const run = () => spawnSync(process.env.ACTQL_PYTHON ?? 'python3', ['-I', '-B', '-c', harness], {
    env: {...process.env, RUNNER_TEMP: root, GITHUB_SHA: sha, GITHUB_OUTPUT: output, COMMAND_LOG: log},
    encoding: 'utf8', timeout: 10000,
  });
  let child = run(); assert.equal(child.status, 0, child.stderr);
  const commands = JSON.parse(await readFile(log, 'utf8'));
  assert.equal(commands.length, 2);
  assert.deepEqual(commands[0].slice(1, 4), ['-m', 'venv', '--symlinks']);
  const pip = commands[1];
  for (const flag of ['--no-index', '--only-binary=:all:', '--no-compile', '--no-cache-dir']) assert(pip.includes(flag));
  assert.equal(pip.at(-1), 'actql==0.1.0');
  assert.equal(pip[pip.indexOf('--find-links') + 1], join(packages, 'wheels'));
  await writeFile(path, JSON.stringify({...manifest, source_sha: 'b'.repeat(40)}));
  child = run(); assert.notEqual(child.status, 0); assert.deepEqual(JSON.parse(await readFile(log, 'utf8')), []);
  await writeFile(path, JSON.stringify(manifest));
  await writeFile(join(packages, 'wheels', wheels[0].file), 'changed');
  child = run(); assert.notEqual(child.status, 0); assert.deepEqual(JSON.parse(await readFile(log, 'utf8')), []);
});

async function reports(t, comparison) {
  const root = await mkdtemp(join(tmpdir(), 'actql-performance-report-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  await mkdir(join(root, 'prepared')); await mkdir(join(root, 'packages'));
  const manifest = JSON.stringify({sourceSha: sha, packages: []});
  await writeFile(join(root, 'packages/ordinary-operation-packages.json'), manifest);
  const controls = {sourceSha: sha, cohortSha256: hash(manifest),
    environment: comparison?.baseline.environment ?? {synthetic: true}, load: 'isolated',
    ...(comparison ? {comparison} : {}),
    historyProtocolSha256: hash(JSON.stringify(nodeOperationProtocol('final')))};
  await writeFile(join(root, 'prepared/controls.json'), JSON.stringify(controls));
  const binding = {cohortSha256: controls.cohortSha256,
    environmentSha256: hash(JSON.stringify(controls.environment)), historyProtocolSha256: controls.historyProtocolSha256};
  async function add(family, operations) {
    const directory = join(root, 'measurement', family); await mkdir(directory, {recursive: true});
    const latency = operations.map(operation => ({operation, mode: 'final', ...binding, samples: []}));
    const report = {sourceSha: sha, mode: 'final', ...binding, latency,
      ...(family === 'warm' && comparison ? {comparison: structuredClone(comparison)} : {}),
      functional: {...binding, rows: []}, installedPayloadsUnchanged: true,
      cleanup: family === 'warm' ? {closed: true} : {allChildrenExited: true, allOriginalClientsClosed: true}};
    for (const series of latency) {
      const query = nodeWarmSmallQueryFixtures.find(fixture => fixture.operation === series.operation);
      if (query) Object.assign(series, {query: structuredClone(query), fixtureSha256: hash(JSON.stringify(query))});
      series.samples.push({iteration: 0, wallNs: 1, synthetic: true,
        ...(query ? {fixtureSha256: series.fixtureSha256} : {})});
    }
    const save = async () => {
      await writeFile(join(directory, 'measurements.json'), JSON.stringify(report));
      await writeFile(join(directory, 'samples.jsonl'), latency.flatMap(series =>
        series.samples.map(sample => JSON.stringify({operation: series.operation, ...sample}))).join('\n') + '\n');
    };
    await save(); return {report, directory, save};
  }
  async function addBoundary(outcome = 'rejected') {
    const directory = join(root, 'measurement', 'used-material'); await mkdir(directory, {recursive: true});
    // Synthetic collector report only; no product operation or fault injection.
    const observedBoundary = {case: 'used-row-tamper', outcome,
      ...(outcome === 'rejected' ? {error: {code: 'ClientHostFailure', message: 'refused'}} : {actualSha256: hash('changed')})};
    const report = {sourceSha: sha, ...binding, mode: 'final', historyProtocol: nodeOperationProtocol('final'),
      boundaries: {...binding, rows: [observedBoundary]}, observedBoundary,
      cleanup: {closed: true}, installedPayloadsUnchanged: true, latencyMeasured: false,
      selectedBoundaryPassed: outcome === 'rejected', fullAcceptance: false};
    const save = () => writeFile(join(directory, 'boundaries.json'), JSON.stringify(report));
    await save(); return {report, directory, save};
  }
  return {root, add, addBoundary};
}

test('selected boundary aggregation preserves exact observation and leaves unmeasured gates incomplete', async t => {
  const p = await reports(t), original = await p.addBoundary();
  const before = await readFile(join(original.directory, 'boundaries.json'));
  const combined = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(combined.boundaries, original.report.boundaries);
  assert.deepEqual(combined.latency, []); assert.deepEqual(combined.functional.rows, []);
  assert.equal(combined.collectors[0].family, 'used-material');
  assert.equal(combined.collectors[0].reportSha256, hash(before));
  const assessed = assessPerformanceEvidence(combined);
  assert.equal(assessed.status, 'incomplete');
  assert.equal(assessed.gates.boundaries.missing.includes('used-row-tamper'), false);
  assert(assessed.gates.boundaries.missing.includes('commit-unknown'));
  assert.deepEqual(await readFile(join(original.directory, 'boundaries.json')), before);
  const failed = await reports(t); await failed.addBoundary('succeeded');
  const bad = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(failed.root)));
  assert.equal(assessPerformanceEvidence(bad).status, 'failed');
  assert.equal(bad.boundaries.rows[0].outcome, 'succeeded');
});

test('selected boundary aggregation refuses foreign attribution, hidden observations and incomplete cleanup or package proof', async t => {
  for (const mutate of [r => {r.sourceSha = 'b'.repeat(40);},
    ...['cohortSha256', 'environmentSha256', 'historyProtocolSha256'].flatMap(key => [
      r => {r[key] = 'b'.repeat(64);}, r => {r.boundaries[key] = 'b'.repeat(64);}]),
    r => {delete r.historyProtocol.boundaries;}, r => {r.mode = 'diagnostic';},
    r => {r.firstFailure = {message: 'failed seed'};}, r => {r.packageFailure = {message: 'changed'};},
    r => {r.cleanup.closed = false;}, r => {delete r.cleanup;}, r => {r.cleanup.failure = {message: 'close'};},
    r => {delete r.installedPayloadsUnchanged;}, r => {r.latencyMeasured = true;},
    r => {r.boundaries.rows = [];}, r => {r.boundaries.rows.push(r.observedBoundary);},
    r => {r.boundaries.rows[0].case = 'foreign-cache';},
    r => {r.observedBoundary = {...r.observedBoundary, outcome: 'succeeded'};},
    r => {r.selectedBoundaryPassed = false;}]) {
    const p = await reports(t), original = await p.addBoundary(); mutate(original.report); await original.save();
    const before = await readFile(join(original.directory, 'boundaries.json'));
    await assert.rejects(combineOrdinaryPerformanceMeasurements(p.root));
    await assert.rejects(readFile(join(p.root, 'measurements.json')), {code: 'ENOENT'});
    assert.deepEqual(await readFile(join(original.directory, 'boundaries.json')), before);
  }
});

test('baseline CLI and consumer binding freeze diagnostic history without issuing public acceptance', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-sqlite-policy-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const baseline = syntheticSQLiteBaseline(), input = join(root, 'baseline.json'), output = join(root, 'comparison.json');
  await writeFile(input, JSON.stringify(baseline));
  const script = fileURLToPath(new URL('./operation-performance.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [script, '--calibrate-sqlite', input, '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  const fixed = await readFixedSQLiteComparison(output, baseline.environment, 'isolated');
  assert.deepEqual(fixed.baseline, baseline);
  assert.match(fixed.profile.qualification, /not an unconditional SDK SLA/u);
  await assert.rejects(readFixedSQLiteComparison(output, {...baseline.environment, node: 'foreign'}, 'isolated'), /environment differs/u);
  await assert.rejects(readFixedSQLiteComparison(output, baseline.environment, 'concurrent'), /load differs/u);
  fixed.profile.entries[0].p95Ms = 1000;
  await writeFile(output, JSON.stringify(fixed));
  await assert.rejects(readFixedSQLiteComparison(output, baseline.environment, 'isolated'), /fixed policy/u);
});

test('aggregation retains the exact pre-measurement comparison and refuses a missing or changed collector copy', async t => {
  const baseline = syntheticSQLiteBaseline(), comparison = {baseline, profile: calibrateSqliteComparisonProfile(baseline)};
  const p = await reports(t, comparison);
  await p.add('warm', ['warm-select']);
  const result = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(result.comparison, comparison);
  for (const mutate of [r => {delete r.comparison;}, r => {r.comparison.profile.entries[0].p95Ms += 1;}]) {
    const invalid = await reports(t, comparison), original = await invalid.add('warm', ['warm-select']);
    mutate(original.report); await original.save();
    await assert.rejects(combineOrdinaryPerformanceMeasurements(invalid.root), /comparison differs/u);
    await assert.rejects(readFile(join(invalid.root, 'measurements.json')), {code: 'ENOENT'});
  }
});

test('Result storage raw control survives calibration, binding and aggregation without claiming public coverage', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-result-storage-policy-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const baseline = syntheticSQLiteBaseline(), resultControl = syntheticResultStorageControl(baseline);
  const input = join(root, 'baseline.json'), control = join(root, 'result.json'), output = join(root, 'comparison.json');
  await writeFile(input, JSON.stringify(baseline)); await writeFile(control, JSON.stringify(resultControl));
  const script = fileURLToPath(new URL('./operation-performance.mjs', import.meta.url));
  const run = spawnSync(process.execPath, [script, '--calibrate-sqlite', input,
    '--result-control', control, '--output', output], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  const fixed = await readFixedSQLiteComparison(output, baseline.environment, baseline.load);
  assert.deepEqual(fixed.resultControl, resultControl);
  assert.match(fixed.profile.resultStorage.qualification, /not an unconditional SDK SLA/u);
  const p = await reports(t, fixed); await p.add('warm', ['warm-result']);
  const combined = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(combined.comparison, fixed);
  fixed.resultControl.cleanup.closed = false; await writeFile(output, JSON.stringify(fixed));
  await assert.rejects(readFixedSQLiteComparison(output, baseline.environment, baseline.load), /successful unprofiled/u);
});

test('same-cohort warm and process reports retain their exact raw samples without inventing missing gates', async t => {
  const p = await reports(t);
  await p.add('warm', ['warm-select', 'warm-result', 'warm-status',
    'warm-join', 'warm-union', 'warm-decimal-sum']);
  await p.add('cold-existing', ['cold-existing']); await p.add('first-init', ['first-init']);
  const result = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(result.latency.map(row => row.operation),
    ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum',
      'cold-existing', 'first-init']);
  assert.equal(result.collectors.length, 3);
  assert.equal(Object.hasOwn(result, 'structure'), false);
  assert.equal(Object.hasOwn(result, 'history'), false);
  assert(result.latency.every(row => row.samples.length === 1));
});

test('missing collector families stay incomplete instead of manufacturing successful observations', async t => {
  const p = await reports(t);
  const output = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(output.latency, []); assert.deepEqual(output.functional.rows, []);
  assert.equal(assessPerformanceEvidence(output).status, 'incomplete');
});

test('small-query reports retain the exact protocol query, oracle and raw identity without completing release evidence', async t => {
  const p = await reports(t);
  const original = await p.add('warm', ['warm-join', 'warm-union', 'warm-decimal-sum']);
  for (const series of original.report.latency) {
    Object.assign(series, {profiled: false, load: 'isolated'});
    Object.assign(series.samples[0], {cohortSha256: series.cohortSha256,
      cpuUserUs: 1, cpuSystemUs: 1, pid: 1, cpuScope: 'synthetic fixture',
      hostId: 'synthetic-host', stateId: 'synthetic-state', completed: true, verified: true});
  }
  original.report.functional.rows = original.report.latency.map(({operation, query}) => ({operation,
    completed: true, expectedSha256: hash(JSON.stringify(query.expected)),
    actualSha256: hash(JSON.stringify(query.expected))}));
  await original.save();
  const output = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
  assert.deepEqual(output.latency, original.report.latency);
  assert.deepEqual(output.functional.rows, original.report.functional.rows);
  assert.deepEqual(output.latency.map(series => series.query.expected),
    [[{id: 1, label: 'joined'}], [{id: 1}, {id: 2}], [{total: '4.00'}]]);
  assert.equal(assessPerformanceEvidence(output).status, 'incomplete');
  for (const mutation of ['query', 'oracle', 'series-identity', 'sample-identity']) {
    const invalid = await reports(t), report = await invalid.add('warm', ['warm-decimal-sum']);
    const series = report.report.latency[0];
    if (mutation === 'query') series.query.text = 'SELECT 1 AS total';
    if (mutation === 'oracle') series.query.expected = [{total: 4}];
    if (mutation === 'series-identity') series.fixtureSha256 = 'b'.repeat(64);
    if (mutation === 'sample-identity') delete series.samples[0].fixtureSha256;
    await report.save();
    await assert.rejects(combineOrdinaryPerformanceMeasurements(invalid.root), /query identity|query differs/u);
    await assert.rejects(readFile(join(invalid.root, 'measurements.json')), {code: 'ENOENT'});
  }
});

test('functional small-query hashes are bound to the independent protocol oracle', async t => {
  for (const mutation of ['both-hashes', 'actual-hash', 'missing-functional-row']) {
    const p = await reports(t), original = await p.add('warm', ['warm-decimal-sum']);
    const expectedSha256 = hash(JSON.stringify([{total: '4.00'}]));
    original.report.functional.rows.push({operation: 'warm-decimal-sum', completed: true,
      expectedSha256, actualSha256: expectedSha256});
    if (mutation === 'both-hashes') Object.assign(original.report.functional.rows[0],
      {expectedSha256: 'b'.repeat(64), actualSha256: 'b'.repeat(64)});
    if (mutation === 'actual-hash') original.report.functional.rows[0].actualSha256 = 'b'.repeat(64);
    if (mutation === 'missing-functional-row') original.report.functional.rows = [];
    await original.save();
    if (mutation === 'missing-functional-row') {
      const output = JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(p.root)));
      assert.deepEqual(output.functional.rows, []);
      // Absent functional coverage remains absent for the release assessor.
    } else {
      await assert.rejects(combineOrdinaryPerformanceMeasurements(p.root), /Functional query oracle|functional query result/u);
      await assert.rejects(readFile(join(p.root, 'measurements.json')), {code: 'ENOENT'});
    }
  }
});

test('foreign identities and missing or changed raw measurements refuse aggregation', async t => {
  for (const mutation of ['source', 'cohort', 'environment', 'protocol', 'operation', 'missing-raw', 'changed-raw']) {
    const p = await reports(t), original = await p.add('warm', ['warm-select']);
    if (mutation === 'source') original.report.sourceSha = 'b'.repeat(40);
    if (mutation === 'cohort') original.report.cohortSha256 = 'b'.repeat(64);
    if (mutation === 'environment') original.report.environmentSha256 = 'b'.repeat(64);
    if (mutation === 'protocol') original.report.historyProtocolSha256 = 'b'.repeat(64);
    if (mutation === 'operation') original.report.latency[0].operation = 'first-init';
    await original.save();
    if (mutation === 'missing-raw') await rm(join(original.directory, 'samples.jsonl'));
    if (mutation === 'changed-raw') await writeFile(join(original.directory, 'samples.jsonl'), '{}\n');
    await assert.rejects(combineOrdinaryPerformanceMeasurements(p.root), mutation);
    if (mutation === 'missing-raw') {
      const script = fileURLToPath(new URL('./ordinary-operation-packages.mjs', import.meta.url));
      const result = spawnSync(process.execPath, [script, 'combine', p.root], {encoding: 'utf8'});
      assert.equal(result.status, 1); assert.match(result.stderr, /ENOENT/u);
    }
  }
});

test('successful samples cannot hide failed or unfinished original cleanup and package verification', async t => {
  const valid = await reports(t);
  await valid.add('warm', ['warm-select']);
  assert.equal(JSON.parse(await readFile(await combineOrdinaryPerformanceMeasurements(valid.root))).latency.length, 1);
  for (const [family, mutate] of [
    ['warm', r => {r.cleanup.closed = false;}],
    ['warm', r => {delete r.cleanup.closed;}],
    ['warm', r => {r.cleanup.failure = {message: 'close failed'};}],
    ['warm', r => {r.firstFailure = {message: 'original operation failed'};}],
    ['warm', r => {r.packageFailure = 'changed installed payload';}],
    ['warm', r => {r.installedPayloadsUnchanged = false;}],
    ['warm', r => {delete r.installedPayloadsUnchanged;}],
    ['cold-existing', r => {r.cleanup.allChildrenExited = false;}],
    ['first-init', r => {delete r.cleanup.allOriginalClientsClosed;}],
  ]) {
    const p = await reports(t), original = await p.add(family, [family === 'warm' ? 'warm-select' : family]);
    original.report.latency[0].samples[0].completed = true;
    original.report.latency[0].samples[0].verified = true;
    original.report.functional.rows.push({operation: original.report.latency[0].operation, completed: true,
      expectedSha256: 'c'.repeat(64), actualSha256: 'c'.repeat(64)});
    mutate(original.report); await original.save();
    const reportBefore = await readFile(join(original.directory, 'measurements.json'));
    const rawBefore = await readFile(join(original.directory, 'samples.jsonl'));
    await assert.rejects(combineOrdinaryPerformanceMeasurements(p.root), /Collector|Original/u);
    await assert.rejects(readFile(join(p.root, 'measurements.json')), {code: 'ENOENT'});
    assert.deepEqual(await readFile(join(original.directory, 'measurements.json')), reportBefore);
    assert.deepEqual(await readFile(join(original.directory, 'samples.jsonl')), rawBefore);
  }
});

test('record-only prepares the same five original packages with its own bound protocol', async t => {
  const p = await packages(t);
  const result = await prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall, mode: 'record-only'});
  const controls = JSON.parse(await readFile(result.controlsPath));
  assert.equal(controls.historyProtocolSha256, hash(JSON.stringify(nodeOperationProtocol('record-only'))));
  assert.equal(controls.comparison, undefined);
});

test('main trend lane reuses exact normal packages without dispatch, rebuild, or speed gating', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['main-performance'];
  assert.match(job.if, /github.event_name == 'push'/u);
  assert.match(job.if, /github.ref == 'refs\/heads\/main'/u);
  assert.deepEqual(job.needs, ['preflight', 'client-packages']);
  assert.equal(job['timeout-minutes'], 15);
  const download = job.steps.find(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(download.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const commands = job.steps.map(step => step.run ?? '').join('\n');
  assert.match(commands, /ordinary-operation-packages.mjs prepare/u);
  assert.match(commands, /benchmark-node-operations.mjs/u);
  assert.match(commands, /benchmark-node-process-operations.mjs/u);
  assert.match(commands, /--mode record-only/u);
  assert.doesNotMatch(commands, /npm (?:ci|run|pack)|continue-on-error|workflow_dispatch/u);
  for (const step of job.steps.filter(step => step.run)) {
    assert.equal(spawnSync('bash', ['-n'], {input: step.run, encoding: 'utf8'}).status, 0);
  }
  const upload = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(upload.if, 'always()'); assert.equal(upload.with['if-no-files-found'], 'error');
});
