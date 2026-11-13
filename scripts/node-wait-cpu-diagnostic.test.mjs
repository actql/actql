import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';
import {parse} from 'yaml';
import {verifyNodeWaitArchive, summarizeNodeWaitProfile} from './test-node-wait-cpu-diagnostic.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/node-wait-cpu-diagnostic.yml', import.meta.url), 'utf8'));
const driver = readFileSync(new URL('./test-node-wait-cpu-diagnostic.mjs', import.meta.url), 'utf8');
const actor = readFileSync(new URL('./fixtures/node-wait-cpu.actor.mjs', import.meta.url), 'utf8');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('CPU archive requires both original metadata digest and exact downloaded ZIP bytes', () => {
  const bytes = Buffer.from('original archive fixture'), expected = hash(bytes);
  verifyNodeWaitArchive(bytes, {artifactDigest: 'sha256:' + expected}, expected);
  assert.throws(() => verifyNodeWaitArchive(Buffer.from('changed archive fixture'),
    {artifactDigest: 'sha256:' + expected}, expected));
  assert.throws(() => verifyNodeWaitArchive(bytes, {artifactDigest: 'sha256:' + 'a'.repeat(64)}, expected));
  assert.throws(() => verifyNodeWaitArchive(Buffer.alloc(0), {artifactDigest: 'sha256:' + expected}, expected));
});

function profileFixture() {
  const consumer = '/private/selected-consumer';
  const url = pathToFileURL(join(consumer, 'node_modules/@actql/local-node/runtime.js')).href;
  const frame = (functionName, url = '') => ({functionName, url, lineNumber: 3, columnNumber: 7});
  return {consumer, packages: [{name: '@actql/local-node', files: [{path: 'runtime.js', sha256: 'b'.repeat(64)}]}],
    profile: {nodes: [
      {id: 1, callFrame: frame('(root)'), children: [2, 3]},
      {id: 2, callFrame: frame('originalExport', url), children: [4]},
      {id: 3, callFrame: frame('secret/state/key', 'file:///private/foreign/state/key')},
      {id: 4, callFrame: frame('originalRow', url)},
    ], samples: [4, 4, 2, 3]}};
}

test('CPU projection keeps exact installed member attribution and separates self from inclusive samples', () => {
  const f = profileFixture(), result = summarizeNodeWaitProfile(f.profile, f.consumer, f.packages);
  assert.equal(result.samples, 4); assert.equal(result.mainThreadOnly, true);
  assert.equal(result.topSelf.find(row => row.functionName === 'originalExport').samples, 1);
  const inclusive = result.topInclusive.find(row => row.functionName === 'originalExport');
  assert.equal(inclusive.samples, 3); assert.equal(inclusive.share, 0.75);
  assert.equal(inclusive.member, 'runtime.js'); assert.equal(inclusive.sha256, 'b'.repeat(64));
  assert.equal(inclusive.line, 3); assert.equal(inclusive.column, 7);
  assert.doesNotMatch(JSON.stringify(result), /private|foreign|state\/key|file:\/\//u);
});

test('CPU projection refuses unknown sample identities and cyclic parent chains', () => {
  for (const mutate of [f => f.profile.samples.push(99),
    f => f.profile.nodes[3].children = [2],
    f => f.profile.nodes.push({...f.profile.nodes[1]})]) {
    const f = profileFixture(); mutate(f);
    assert.throws(() => summarizeNodeWaitProfile(f.profile, f.consumer, f.packages));
  }
});

test('Node CPU workflow is one manual Linux job with read-only permissions and no ordinary matrix', () => {
  assert.deepEqual(Object.keys(workflow.on), ['workflow_dispatch']);
  assert.deepEqual(Object.keys(workflow.jobs), ['node-wait-cpu']);
  assert.deepEqual(workflow.permissions, {contents: 'read', actions: 'read'});
  for (const input of Object.values(workflow.on.workflow_dispatch.inputs)) {
    assert.equal(input.type, 'string'); assert.equal(input.required, true);
  }
  const job = workflow.jobs['node-wait-cpu'];
  assert.equal(job['runs-on'], 'ubuntu-24.04'); assert.equal(job['timeout-minutes'], 20);
  assert(job.if.includes("visibility == 'public'"));
  assert.equal(job.steps.find(step => step.uses?.startsWith('actions/checkout@')).with['persist-credentials'], false);
  assert.equal(job.steps.find(step => step.uses?.startsWith('actions/setup-node@')).with['node-version'], '22.22.0');
  assert(!job.steps.some(step => step.uses?.includes('performance-matrix')));
  assert.doesNotMatch(job.steps.map(step => step.run ?? '').join('\n'), /moon build|npm (?:pack|run)|operation-performance\.mjs/u);
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  assert(ci.jobs.lint.steps.some(step => step.run?.includes('scripts/node-wait-cpu-diagnostic.test.mjs')));
});

test('original producer and digest precede exact-source checkout and the one consumer', () => {
  const steps = workflow.jobs['node-wait-cpu'].steps;
  const bind = steps.find(step => step.name === 'Verify the original producer source and exact artifact archive');
  const consume = steps.find(step => step.name === 'Sample one installed wait with unchanged normal packages');
  assert(steps.indexOf(bind) < steps.indexOf(consume));
  assert(bind.run.indexOf('diagnostic.mjs" artifact') < bind.run.indexOf('git checkout --detach'));
  assert.equal(bind.env.PACKAGE_EVENT_HEAD_SHA, '${{ inputs.package-event-head }}');
  assert.equal(bind.env.PACKAGE_BUILD_SOURCE_SHA, '${{ inputs.package-build-source }}');
  assert.equal(bind.env.PACKAGE_ARCHIVE_SHA256, '${{ inputs.package-archive-sha256 }}');
  assert(driver.includes('inspectPerformancePackageProducer({...options, packages, adapter: \'node\'})'));
  assert(driver.includes("assert.equal(binding.sourceSha, process.env.PACKAGE_BUILD_SOURCE_SHA)"));
  assert(driver.includes("verifyNodeWaitArchive(result, producer, options.expectedDigest)"));
  assert(driver.includes('normalLifecycle: true'));
  assert(driver.includes('verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer)'));
  assert(driver.includes('assert.deepEqual(checkoutState(root), source)'));
  for (const step of steps.filter(step => step.run)) {
    const shell = spawnSync('bash', ['-n'], {input: step.run, encoding: 'utf8'});
    assert.equal(shell.status, 0, shell.stderr);
  }
});

test('one wait is profiled with existing budgets while original all EOF and first close are retained', () => {
  assert.equal([...actor.matchAll(/client\.startSource\(/gu)].length, 1);
  assert.equal([...actor.matchAll(/run\.wait\(/gu)].length, 1);
  assert.equal([...actor.matchAll(/post\('Profiler.start'\)/gu)].length, 1);
  assert(actor.indexOf("span('profiler-setup'") < actor.indexOf("span('wait-100000'"));
  assert(actor.indexOf("span('profiler-stop'") < actor.indexOf("span('all-100000'"));
  assert(actor.includes('sourceFreeMaxWork: 30000000'));
  assert(actor.includes('retainedBytes: 1073741824, executionBytes: 1073741824'));
  assert(actor.includes('report.stream = {rows, eof: true, exact: true}'));
  assert(actor.includes("span('FIRST-close', () => client.close())"));
  assert(actor.includes('report.aliveScopedFD, {before: 0, after: 0}'));
  assert.doesNotMatch(actor, /client\.attach|client\.approve|client\.cancel|startSource.*retry/u);
});

test('only sanitized CPU summary and original artifact metadata are uploaded, including incomplete outcomes', () => {
  const upload = workflow.jobs['node-wait-cpu'].steps.at(-1);
  assert.equal(upload.if, 'always()');
  assert.deepEqual(upload.with.path.trim().split('\n'), [
    '${{ runner.temp }}/node-wait-cpu/cpu.json', '${{ runner.temp }}/node-wait-cpu/cpu-pending.json',
    '${{ runner.temp }}/node-wait-cpu/producer.json',
    '${{ runner.temp }}/node-wait-cpu/source.json',
    '${{ runner.temp }}/node-wait-cpu/packages/packed-client-packages.json',
  ]);
  assert.doesNotMatch(upload.with.path, /cpuprofile|state|original-ref|consumer\.json|\.zip|installed/u);
  assert(driver.includes("report.failure = {stage, name: error.name, code: error.code ?? null}"));
});
