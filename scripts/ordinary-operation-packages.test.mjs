import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {cp, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {parse} from 'yaml';
import {CLIENT_PACKAGES} from './packed-client-packages.mjs';
import {validatePerformancePackageProducer, inspectPerformancePackageProducer,
  prepareOrdinaryPerformanceConsumer} from './ordinary-operation-packages.mjs';

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
  await assert.rejects(prepareOrdinaryPerformanceConsumer({...p, install: syntheticInstall}));
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

test('controlled performance check consumes existing artifacts and cannot omit failed or missing raw assessment', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  assert.deepEqual(ci.jobs['performance-matrix'].with, {
    'package-run-id': '${{ inputs.performance_package_run_id }}',
    'package-artifact-id': '${{ inputs.performance_package_artifact_id }}',
  });
  assert.ok(ci.jobs.lint.steps.some(s => s.run === 'node --test scripts/ordinary-operation-packages.test.mjs'));
  const job = workflow.jobs['ordinary-operations'];
  assert.equal(job.permissions.actions, 'read');
  const inspect = job.steps.findIndex(s => s.name === 'Validate the original normal package producer');
  const download = job.steps.findIndex(s => s.name === 'Reuse the exact existing normal package artifact');
  const prepare = job.steps.findIndex(s => s.name === 'Install a fresh ordinary consumer without a producer fallback');
  const measure = job.steps.findIndex(s => s.name === 'Measure completed public operations from the installed cohort');
  const assess = job.steps.findIndex(s => s.name === 'Require measured latency and structural release evidence');
  assert(inspect < download && download < prepare && prepare < measure && measure < assess);
  assert.equal(job.steps[download].with['artifact-ids'], '${{ inputs.package-artifact-id }}');
  assert.equal(job.steps[assess].if, 'always()');
  assert.equal(job.steps[assess]['continue-on-error'], undefined);
  assert.equal(job.steps[measure]['continue-on-error'], undefined);
  assert(job.steps[measure].run.endsWith('--mode final\n'));
  assert(job.steps[assess].run.includes('scripts/operation-performance.mjs --input'));
  const upload = job.steps.at(-1); assert.equal(upload.if, 'always()');
  assert(upload.with.path.includes('/measurement/*.jsonl'));
  assert(!job.steps.some(s => /setup-toolchain|setup-moonbit/u.test(s.uses ?? '')));
  assert(!job.steps.some(s => /\b(?:npm pack|moon build|packed-client-packages\.mjs)\b/u.test(s.run ?? '')));
});
