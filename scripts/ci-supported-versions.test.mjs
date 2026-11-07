// CI scheduling/fixture controls, not formal tar/wheel compatibility evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdir, mkdtemp, rm, copyFile} from 'node:fs/promises';
import {execFileSync, spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import {supportedNodeCases, acceptSupportedNode} from './ci-supported-node.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const {jobs} = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('supported Node versions consume one explicit normal artifact and retain aggregate refusal', () => {
  const job = jobs['client-supported-versions'];
  assert.deepEqual(job.needs, ['select-targets', 'preflight', 'client-packages']);
  assert.equal(job.strategy['fail-fast'], false);
  assert.deepEqual(job.strategy.matrix.include, supportedNodeCases.map(({profile, version}) => ({profile, node: version})));
  assert(job.if.includes("outputs.profile == 'full'"));
  const download = job.steps.find(step => step.name === 'Download the exact Client package artifact');
  assert.equal(download.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  assert.equal(job.steps.filter(step => step.run).length, 1);
  assert(job.steps.at(-1).run.includes('scripts/ci-supported-node.mjs'));
  assert(jobs.client.needs.includes('client-supported-versions'));
  assert(jobs.client.steps[0].run.includes('"client-supported-versions"'));
  assert(!JSON.stringify(job).includes('continue-on-error'));
  assert(!JSON.stringify(job).includes('moon'));
});

test('supported Node selection refuses foreign versions before preparation or package access', async () => {
  await assert.rejects(acceptSupportedNode({profile: 'local', version: '22.0.0', parent: '/must-not-touch'}),
    {message: 'Unselected supported-version case'});
  const foreign = supportedNodeCases.find(entry => entry.profile === 'sdk' && entry.version !== process.versions.node);
  await assert.rejects(acceptSupportedNode({...foreign, parent: '/must-not-touch'}),
    error => error.code === 'ERR_ASSERTION' && error.message.startsWith('Consumer interpreter differs from the selected version'));
});

test('Python supported consumers retain the SAME producer cohort and independent failure collection', () => {
  const steps = jobs['python-wheels'].steps;
  const producer = steps.find(step => step.id === 'python-normal-cohort');
  assert(producer.run.includes('scripts/ci-python-wheels.py'));
  for (const [name, version] of [['minimum', '3.11.0'], ['latest', '3.15.2']]) {
    const setup = steps.find(step => step.id === 'python-' + name);
    assert.equal(setup.with['python-version'], version);
    assert.equal(setup.if, "${{ !cancelled() && steps.python-normal-cohort.outcome == 'success' }}");
    const accept = steps.find(step => step.name === `Accept the ${name} Python version from the same normal wheels`);
    assert(accept.if.includes(`steps.python-${name}.outcome == 'success'`));
    assert(accept.run.includes('--cohort "$RUNNER_TEMP/python-wheel-acceptance/cohort"'));
    assert(!accept.run.includes('build'));
  }
});

test('SDK compatibility actor completes the public roundtrip against checked-in SDK Source without a runtime', async t => {
  const consumer = await mkdtemp(join(tmpdir(), 'actql-sdk-version-source-'));
  t.after(() => rm(consumer, {recursive: true, force: true}));
  const paths = execFileSync('git', ['ls-files', '-z', 'packages/client-wire', 'packages/sdk'], {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean);
  for (const path of paths) {
    const [, name, ...parts] = path.split('/');
    const target = join(consumer, 'node_modules/@actql', name, ...parts);
    await mkdir(dirname(target), {recursive: true}); await copyFile(join(root, path), target);
  }
  const actor = join(consumer, 'acceptance.mjs');
  await copyFile(join(root, 'scripts/fixtures/ci-supported-node.mjs'), actor);
  const env = {...process.env}; delete env.NODE_PATH; delete env.NODE_OPTIONS;
  const child = spawnSync(process.execPath, [actor, 'sdk', process.versions.node],
    {cwd: consumer, env, encoding: 'utf8', timeout: 10000});
  assert.ifError(child.error); assert.equal(child.signal, null); assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(child.stdout), {profile: 'sdk', node: process.versions.node,
    installed: true, publicApiRoundtrip: true, closed: true, localHost: false});
});


test('Python supported-version orchestration guards execute without a wheel or runtime', () => {
  const child = spawnSync('python3', ['-B', 'scripts/test_ci_supported_python.py'],
    {cwd: root, encoding: 'utf8', timeout: 10000});
  assert.ifError(child.error); assert.equal(child.signal, null);
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stderr, /Ran 2 tests/); assert.match(child.stderr, /OK/);
});


test('compatibility floors remain bound to the current package support declarations', async () => {
  for (const [name, expected] of [['sdk', '>=22'], ['node', '^22.16.0 || >=24.0.0'],
    ['local-node', '^22.16.0 || >=24.0.0']]) {
    const metadata = JSON.parse(await readFile(new URL('../packages/' + name + '/package.json', import.meta.url), 'utf8'));
    assert.equal(metadata.engines.node, expected);
  }
  for (const name of ['python-sdk', 'python-product', 'python-local-runtime']) {
    const metadata = await readFile(new URL('../packages/' + name + '/pyproject.toml', import.meta.url), 'utf8');
    assert.match(metadata, /^requires-python = ">=3\.11"$/mu);
  }
});
