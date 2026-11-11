import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdir, mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {gateJobs, gateJobRequired, selectTargets, verifyGate} from './ci-targets.mjs';
import {mockWorkflowMetrics} from './health-monitor-adapters.mjs';
import {packedReadmeCases} from './test-packed-readme-workflows.mjs';

const workflow = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const name = 'client-readme-packed', job = workflow.jobs[name];
const repository = new URL('../', import.meta.url).pathname;
test('required README job reuses the exact single producer on Node 22 and 24 with failure retention', () => {
  assert(job); assert.deepEqual(job.needs, ['select-targets', 'preflight', 'client-packages']);
  assert.equal(job.strategy['fail-fast'], false);
  assert.deepEqual(job.strategy.matrix.node, ['22.22.0', '24']);
  const input = job.steps.find(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(input.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  assert(job.steps.some(step => step.run === 'node scripts/test-packed-readme-workflows.mjs "$RUNNER_TEMP/client-readme-packed"'));
  assert(!job.steps.some(step => /npm pack|build:runtime|moon (?:build|test)/u.test(step.run ?? '')));
  assert(job.steps.every(step => !Object.hasOwn(step.env ?? {}, 'CI_PLAN')));
  const output = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(output.if, 'always()'); assert.equal(output.with['if-no-files-found'], 'error');
  assert(output.with.path.includes('raw/*')); assert(output.with.path.includes('*.observation.json'));
  assert.deepEqual(workflow.jobs.check.needs, gateJobs);
  const basic = workflow.jobs.lint.steps.map(step => step.run ?? '').join('\n');
  assert(basic.includes('adapters/host-node/client-result-collection-policy.test.mjs'));
  assert(basic.includes('scripts/packed-readme-ci.test.mjs'));
  assert(basic.includes('scripts/native-cli-default-numeric.test.mjs'));
});

test('required README gate selects actual SDK Host Core schema and packaging PR inputs and rejects skipped failure', () => {
  const sha = 'a'.repeat(40);
  for (const path of ['packages/sdk/internal/result-read.mjs', 'adapters/host-node/embedded-local.mjs',
    'src/client_local_host/resource_policy.mbt', 'spec/contracts/actql-client-host.json',
    'scripts/packed-client-packages.mjs']) {
    const selection = selectTargets([path], {draft: false, event: 'pull_request'});
    assert.equal(gateJobRequired(selection, name), true, path);
    const results = Object.fromEntries(gateJobs.map(key => [key,
      {result: gateJobRequired(selection, key) ? 'success' : 'skipped'}]));
    const envelope = {sourceRevision: sha, selection};
    const context = {event: 'pull_request', sourceRevision: sha, draft: false};
    verifyGate(envelope, results, context);
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      assert.throws(() => verifyGate(envelope, {...results, [name]: {result}}, context), /client-readme-packed/u);
    }
  }
  assert.equal(gateJobRequired({profile: 'maintenance', event: 'pull_request'}, name), false);
  assert.equal(gateJobRequired({profile: 'draft', event: 'pull_request'}, name), false);
});

async function scratch(t) {
  // Authored callback-only fixture: no Host, Run, database or key is created.
  const root = await mkdtemp(join(tmpdir(), 'actql-readme-ci-unit-'));
  const consumer = join(root, 'consumer'); await mkdir(join(consumer, 'node_modules'), {recursive: true});
  t.after(() => rm(root, {recursive: true, force: true}));
  return {root, consumer};
}
test('required README cases use three distinct project paths and original independent phase counts', async t => {
  assert.deepEqual(packedReadmeCases, [
    {template: 'churn-risk-mock', variant: 'readme'},
    {template: 'deal-review-mock', variant: 'readme'},
    {template: 'deal-review-mock', variant: 'two-models'},
  ]);
  const {root, consumer} = await scratch(t), commands = [];
  for (const selected of packedReadmeCases) {
    const metric = await mockWorkflowMetrics({prepared: {consumer}, root, repository,
      counts: {coldSamples: 1}, ...selected, onMetric() {},
      async command(executable, args, options) {
        commands.push({executable, args, options});
        const phase = args[1], expected = {capture: 9, approve: 11, recover: 7}[phase];
        return {pid: 10000 + commands.length, code: 0, signal: null, wallNs: 100,
          stdout: [...Array.from({length: expected}, (_, n) => ({phase, step: `explicit-${n}`, status: 'passed'})),
            {phase, status: 'passed', firstFailedStep: null}].map(value => JSON.stringify(value)).join('\n')};
      }});
    assert.equal(metric.samples.length, 1); assert.equal(metric.samples[0].verified, true);
    assert.equal(metric.samples[0].phases.length, 3);
    const project = join(root, `mock-project-${selected.template}-${selected.variant}-0`);
    assert(!(await readdir(project)).includes('node_modules'));
    for (const phase of ['capture', 'approve', 'recover']) {
      const actual = JSON.parse(await readFile(join(project, `${phase}.observation.json`), 'utf8'));
      assert.equal(actual.completed, true); assert.equal(actual.exitCode, 0);
    }
  }
  assert.equal(commands.length, 9); assert.equal(new Set(commands.map(value => value.options.cwd)).size, 3);
  assert.equal(new Set(commands.map(value => value.options.name)).size, 9);
});

test('failed README command retains original exit primary and first-close failure before assertions', async t => {
  const {root, consumer} = await scratch(t);
  const primary = Object.assign(new Error('Original workflow refusal'), {commandResult: {
    pid: 10000, code: 1, signal: null, wallNs: 100,
    stdout: JSON.stringify({phase: 'capture', status: 'failed', firstFailedStep: 'wait',
      code: 'OriginalRefusal', cleanupCode: 'ClientCleanupPending'})}});
  const observed = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric: value => observed.push(value), command: async () => {throw primary;}}),
  error => error === primary);
  const actual = JSON.parse(await readFile(join(root,
    'mock-project-churn-risk-mock-readme-0/capture.observation.json'), 'utf8'));
  assert.equal(actual.completed, false); assert.equal(actual.exitCode, 1);
  assert.equal(actual.summary.code, 'OriginalRefusal'); assert.equal(actual.summary.cleanupCode, 'ClientCleanupPending');
  assert.equal(observed[0].samples[0].verified, false);
  assert.equal(observed[0].samples[0].phases.length, 1);
});

test('packed collection persists Program-removal failure after FIRST close and never removes in Saved', async () => {
  // Execute the actual fixture finalizer with explicit filesystem/close ports.
  // This verifies failure recording, not installed Host or Run behavior.
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const finalizer = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'})
    .body.find(value => value.type === 'TryStatement').finalizer;
  const runFinalizer = Function('client', 'span', 'report', 'cleanup', 'failed', 'phase', 'programs',
    'unlink', 'save', 'observeRecordApprovalDescriptors', 'setTimeout', 'stateDir', 'assert',
    `return (async () => ${source.slice(finalizer.start, finalizer.end)})();`);
  for (const phase of ['capture', 'saved']) {
    const events = [], cleanup = [], report = {firstClose: 'unobserved'}, observations = [];
    const failure = Object.assign(new Error('Original Program removal failed'), {code: 'EACCES'});
    await runFinalizer({async close() {events.push('FIRST-close');}},
      async (_name, action) => action(), report, cleanup, false, phase, ['first.sql', 'second.sql'],
      async path => {events.push(path); if (path === 'second.sql') throw failure;},
      async (path, value) => observations.push({path, value: structuredClone(value)}),
      async () => ({openPaths: []}), async () => {}, '/authored-test-state', assert);
    assert.equal(observations.length, 1); assert.equal(observations[0].path, `${phase}.observation.json`);
    assert.equal(observations[0].value.firstClose, 'returned');
    assert.deepEqual(observations[0].value.aliveScopedFD, {before: 0, after: 0});
    if (phase === 'capture') {
      assert.deepEqual(events, ['FIRST-close', 'first.sql', 'second.sql']);
      assert.equal(cleanup[0], failure); assert.equal(report.originalProgramsRemovedAfterFirstClose, 1);
      assert.equal(observations[0].value.complete, false);
      assert.deepEqual(observations[0].value.cleanup, [{name: 'Error', code: 'EACCES'}]);
    } else {
      assert.deepEqual(events, ['FIRST-close']); assert.deepEqual(cleanup, []);
      assert.equal(observations[0].value.complete, true);
    }
  }
});
