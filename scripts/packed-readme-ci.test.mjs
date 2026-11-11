import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile, copyFile, symlink, unlink, readlink, mkdir, mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {gateJobs, gateJobRequired, selectTargets, verifyGate} from './ci-targets.mjs';
import {mockWorkflowMetrics} from './health-monitor-adapters.mjs';
import {packedReadmeCases} from './test-packed-readme-workflows.mjs';
import {nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

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
    let originalInputs;
    const metric = await mockWorkflowMetrics({prepared: {consumer}, root, repository,
      counts: {coldSamples: 1}, ...selected, onMetric() {},
      async command(executable, args, options) {
        commands.push({executable, args, options});
        const phase = args[1], expected = {capture: 10, approve: 11, recover: 7}[phase];
        if (phase === 'capture') {
          originalInputs = [selected.variant === 'two-models' ? 'deal-review.program.json'
            : selected.template === 'deal-review-mock' ? 'deal-review.aql' : 'churn-risk.aql',
          ...(await readdir(join(options.cwd, 'mock'))).filter(name => name.endsWith('.answers.yaml')).map(name => `mock/${name}`)];
        }
        for (const input of originalInputs) {
          if (phase === 'recover') await assert.rejects(readFile(join(options.cwd, input)), {code: 'ENOENT'});
          else assert((await readFile(join(options.cwd, input))).length > 0);
        }
        // Recovery keeps the original configuration and physical target input.
        assert((await readFile(join(options.cwd, 'actql.config.json'))).length > 0);
        assert((await readFile(join(options.cwd, 'mock/data.json'))).length > 0);
        return {pid: 10000 + commands.length, code: 0, signal: null, wallNs: 100,
          stdout: [...Array.from({length: expected}, (_, n) => ({phase, step: `explicit-${n}`, status: 'passed'})),
            {phase, status: 'passed', firstFailedStep: null,
              firstClose: {attempted: true, returned: true}}].map(value => JSON.stringify(value)).join('\n')};
      }});
    assert.equal(metric.samples.length, 1); assert.equal(metric.samples[0].verified, true);
    assert.equal(metric.samples[0].phases.length, 3);
    const project = join(root, `mock-project-${selected.template}-${selected.variant}-0`);
    assert(!(await readdir(project)).includes('node_modules'));
    for (const phase of ['capture', 'approve', 'recover']) {
      const actual = JSON.parse(await readFile(join(project, `${phase}.observation.json`), 'utf8'));
      assert.equal(actual.completed, true); assert.equal(actual.exitCode, 0);
      if (phase === 'approve') {
        assert.equal(actual.inputRemoval.completed, true);
        assert.deepEqual([...actual.inputRemoval.paths].sort(), [...originalInputs].sort());
      }
      if (phase === 'recover') {
        assert.equal(actual.originalInputsAbsentBeforeSaved, true);
        assert.equal(actual.originalInputsAbsentAfterSaved, true);
      }
    }
  }
  assert.equal(commands.length, 9); assert.equal(new Set(commands.map(value => value.options.cwd)).size, 3);
  assert.equal(new Set(commands.map(value => value.options.name)).size, 9);
});

test('required README preserves inputs and never starts Saved after an unreturned FIRST close', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args) {
      const phase = args[1]; phases.push(phase);
      return {pid: 10000 + phases.length, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: phase === 'capture' ? 10 : 11}, (_, n) =>
          ({phase, step: `explicit-${n}`, status: 'passed'})),
        {phase, status: 'passed', firstFailedStep: null,
          firstClose: {attempted: true, returned: phase !== 'approve'}}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture', 'approve']);
  const project = join(root, 'mock-project-churn-risk-mock-readme-0');
  for (const input of ['churn-risk.aql', 'mock/churn-risk.v1.answers.yaml']) assert((await readFile(join(project, input))).length > 0);
  const record = JSON.parse(await readFile(join(project, 'approve.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.equal(record.exitCode, 0);
  assert.equal(record.inputRemoval, undefined);
});

test('required README never deletes replaced authored inputs or enters dependent Saved', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args, options) {
      const phase = args[1]; phases.push(phase);
      if (phase === 'approve') await writeFile(join(options.cwd, 'mock/churn-risk.v1.answers.yaml'), 'changed input');
      return {pid: 10000 + phases.length, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: phase === 'capture' ? 10 : 11}, (_, n) =>
          ({phase, step: `explicit-${n}`, status: 'passed'})),
        {phase, status: 'passed', firstFailedStep: null,
          firstClose: {attempted: true, returned: true}}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture', 'approve']);
  const project = join(root, 'mock-project-churn-risk-mock-readme-0');
  assert.equal(await readFile(join(project, 'mock/churn-risk.v1.answers.yaml'), 'utf8'), 'changed input');
  assert((await readFile(join(project, 'churn-risk.aql'))).length > 0);
  const record = JSON.parse(await readFile(join(project, 'approve.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.deepEqual(record.inputRemoval, {completed: false, paths: []});
});

test('required README aggregate refuses the old capture count before dependent phases', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args) {
      const phase = args[1]; phases.push(phase);
      return {pid: 10000, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: 9}, (_, n) => ({phase, step: `old-${n}`, status: 'passed'})),
          {phase, status: 'passed', firstFailedStep: null}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture']);
  const record = JSON.parse(await readFile(join(root,
    'mock-project-churn-risk-mock-readme-0/capture.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.equal(record.exitCode, 0);
  assert.equal(record.expectedAssertions, 10);
});

test('failed README command retains original exit primary and first-close failure before assertions', async t => {
  const {root, consumer} = await scratch(t);
  const primary = Object.assign(new Error('Original workflow refusal'), {commandResult: {
    pid: 10000, code: 1, signal: null, wallNs: 100,
    stdout: JSON.stringify({phase: 'capture', status: 'failed', firstFailedStep: 'wait',
      code: 'OriginalRefusal', cleanupCode: 'ClientCleanupPending',
      firstClose: {attempted: true, returned: false},
      runObservation: {available: true, status: 'failed', terminalCode: 'OriginalRunRefusal'}})}});
  const observed = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric: value => observed.push(value), command: async () => {throw primary;}}),
  error => error === primary);
  const actual = JSON.parse(await readFile(join(root,
    'mock-project-churn-risk-mock-readme-0/capture.observation.json'), 'utf8'));
  assert.equal(actual.completed, false); assert.equal(actual.exitCode, 1);
  assert.equal(actual.summary.code, 'OriginalRefusal'); assert.equal(actual.summary.cleanupCode, 'ClientCleanupPending');
  assert.deepEqual(actual.summary.firstClose, {attempted: true, returned: false});
  assert.deepEqual(actual.summary.runObservation,
    {available: true, status: 'failed', terminalCode: 'OriginalRunRefusal'});
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

async function runnerFunctions() {
  const source = await readFile(new URL('./test-packed-readme-workflows.mjs', import.meta.url), 'utf8');
  const declarations = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(value => value.type === 'ExportNamedDeclaration' ? value.declaration : value)
    .filter(value => value?.type === 'FunctionDeclaration');
  return (name, ports) => {
    const node = declarations.find(value => value.id.name === name);
    assert(node, `Missing actual runner ${name}`);
    // Retain the original module coordinate when compiling its actual function
    // with explicit test ports; Function itself has no import.meta binding.
    const body = source.slice(node.start, node.end).replaceAll('import.meta.url',
      JSON.stringify(new URL('./test-packed-readme-workflows.mjs', import.meta.url).href));
    return Function(...Object.keys(ports), `return (${body});`)(...Object.values(ports));
  };
}

test('independent normal consumers continue after collection and variant failure and retain all original errors', async t => {
  // Exercise the actual orchestration with explicit package and command ports;
  // these synthetic outcomes do not qualify product or installed execution.
  const {root, consumer} = await scratch(t), output = join(root, 'out'), calls = [];
  const load = await runnerFunctions();
  const collectionFailure = new Error('Original collection failure'), variantFailure = new Error('Original churn failure');
  const cleanupFailure = new Error('Original alias cleanup failure');
  const verifyNodeBenchmarkPackages = async () => {};
  const runReadmeCases = load('runReadmeCases', {verifyNodeBenchmarkPackages, assert, writeFile, join,
    nodeBenchmarkFailure, async mockWorkflowMetrics({template, variant, onMetric}) {
      calls.push({template, variant});
      const failed = template === 'churn-risk-mock';
      await onMetric({samples: [{completed: !failed, verified: !failed}]});
      if (failed) throw variantFailure;
    }});
  const before = {clean: true, revision: 'a'.repeat(40)};
  const run = load('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
    process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/authored-normal-input'}, version: 'explicit-test',
      platform: 'explicit-test', arch: 'explicit-test'}, fileURLToPath: () => repository,
    URL, checkoutState: () => before, execFileSync: () => 'b'.repeat(40), mkdir, join, writeFile,
    packedReadmeCases, nodeBenchmarkFailure, execute: async () => assert.fail('No product command'),
    prepareHealthPackages: async () => ({consumer, manifest: {}, manifestPath: '/authored-manifest'}),
    runCollectionConsumer: async ({report, cleanup}) => {
      report.collection[0].status = 'failed'; cleanup.push(cleanupFailure); throw collectionFailure;
    }, runReadmeCases, verifyNodeBenchmarkPackages});
  await assert.rejects(run(output), error => {
    assert(error instanceof AggregateError); assert.equal(error.cause, collectionFailure);
    assert.deepEqual(error.errors, [collectionFailure, variantFailure, cleanupFailure]); return true;
  });
  assert.deepEqual(calls, packedReadmeCases);
  const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
  assert.equal(report.complete, false);
  assert.deepEqual(report.cases.map(value => value.status), ['failed', 'passed', 'passed']);
  assert.equal(report.collection[1].status, 'unexecuted');
  assert.match(report.collection[1].unexecutedReason, /completed original 100000 Result/u);
  assert.equal(report.failures.length, 2); assert.equal(report.cleanup.length, 1);
});

test('failed shared package preparation records every dependent as unexecuted and runs no consumer', async t => {
  const {root} = await scratch(t), output = join(root, 'out'), load = await runnerFunctions();
  const failure = new Error('Original normal package mismatch'), before = {clean: true, revision: 'a'.repeat(40)};
  const run = load('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
    process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/authored-normal-input'}, version: 'explicit-test',
      platform: 'explicit-test', arch: 'explicit-test'}, fileURLToPath: () => repository, URL,
    checkoutState: () => before, execFileSync: () => 'b'.repeat(40), mkdir, join, writeFile,
    packedReadmeCases, nodeBenchmarkFailure, execute: async () => assert.fail('No product command'),
    prepareHealthPackages: async () => {throw failure;},
    runCollectionConsumer: async () => assert.fail('No collection with failed shared input'),
    runReadmeCases: async () => assert.fail('No README with failed shared input'),
    verifyNodeBenchmarkPackages: async () => assert.fail('No successful prepared input')});
  await assert.rejects(run(output), error => error === failure);
  const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
  assert.equal(report.complete, false);
  assert([...report.collection, ...report.cases].every(value =>
    value.status === 'unexecuted' && value.completed === false && value.unexecutedReason));
  assert.equal(report.failures.length, 1);
});

test('failed collection capture never runs its dependent Saved and returns its exact software alias', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions(), commands = [];
  const failure = Object.assign(new Error('Original capture failure'), {commandResult:
    {pid: 123, code: 1, signal: null, wallNs: 10, stdout: ''}});
  const report = {collection: ['capture', 'saved'].map(phase =>
    ({phase, completed: false, status: 'unexecuted'}))}, cleanup = [];
  const runCollectionPhase = load('runCollectionPhase', {join, assert, process, nodeBenchmarkFailure});
  const completedCollectionCapture = load('completedCollectionCapture', {readFile, join, assert});
  const run = load('runCollectionConsumer', {join, dirname, mkdir, copyFile, writeFile,
    symlink, unlink, readlink, assert, process, nodeBenchmarkFailure, runCollectionPhase, completedCollectionCapture});
  await assert.rejects(run({prepared: {consumer}, root, repository, report, cleanup,
    async command(_executable, _args, options) {commands.push(options.name); throw failure;}}),
  error => error === failure);
  assert.deepEqual(commands, ['collection-capture']); assert.deepEqual(cleanup, []);
  assert.equal(report.collection[0].status, 'failed'); assert.equal(report.collection[0].exitCode, 1);
  assert.equal(report.collection[1].status, 'unexecuted');
  assert(!(await readdir(join(root, 'collection'))).includes('node_modules'));
});

test('required Native counter stays case-scoped and nonzero through the original dispatcher', async () => {
  const source = await readFile(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const file = 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt';
  const matches = [];
  function visit(node, parent) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'spawnSync') {
      const environment = node.arguments[2]?.properties?.find(value => value.key?.name === 'env')?.value;
      const selected = environment?.properties?.find(value => value.type === 'SpreadElement' &&
        value.argument.type === 'ConditionalExpression' &&
        source.slice(value.argument.start, value.argument.end).includes('ACTQL_NATIVE_TIMINGS'));
      if (selected) matches.push({node, parent, selected});
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(child => visit(child, node));
      else if (value && typeof value === 'object') visit(value, node);
    }
  }
  visit(tree, null); assert.equal(matches.length, 1);
  const {node, parent, selected} = matches[0];
  assert.equal(parent.callee.name, 'checkChild');
  const expression = selected.argument;
  const environment = Function('test', `return (${source.slice(expression.start, expression.end)});`);
  assert.deepEqual(environment({source: file, index: 13}), {ACTQL_NATIVE_TIMINGS: '1'});
  for (const test of [{source: file, index: 12}, {source: file, index: 14},
    {source: 'src/platform_native/client_host/another.mbt', index: 13}]) {
    assert.deepEqual(environment(test), {});
  }
  const command = source.slice(node.start, node.end);
  assert(command.includes("runFocusedTests('moon'"));
  assert(command.includes('expectedTests: 1'));
  assert(gateJobs.includes('native')); assert(workflow.jobs.check.needs.includes('native'));
  assert.equal(workflow.jobs.native.env?.ACTQL_NATIVE_TIMINGS, undefined);
  assert(workflow.jobs.native.steps.every(step => step.env?.ACTQL_NATIVE_TIMINGS === undefined));
});


test('completed original collection Saved is independent of a later capture case failure', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions(), commands = [];
  const original = {ref: {nonce: 'authored-reference'}, resultName: 'actual-sole-result', count: 100000};
  const capture = {phase: 'capture', pid: 123, complete: false, firstClose: 'returned',
    aliveScopedFD: {before: 0, after: 0}, cleanup: [], cases: [{...original, complete: true}]};
  const failure = Object.assign(new Error('Later oversized case refused'), {commandResult:
    {pid: 123, code: 1, signal: null, wallNs: 10, stdout: ''}});
  const report = {collection: ['capture', 'saved'].map(phase =>
    ({phase, completed: false, status: 'unexecuted'}))}, cleanup = [];
  const runCollectionPhase = load('runCollectionPhase', {join, assert, process, nodeBenchmarkFailure});
  const completedCollectionCapture = load('completedCollectionCapture', {readFile, join, assert});
  const run = load('runCollectionConsumer', {join, dirname, mkdir, copyFile, writeFile,
    symlink, unlink, readlink, assert, process, nodeBenchmarkFailure, runCollectionPhase, completedCollectionCapture});
  await assert.rejects(run({prepared: {consumer}, root, repository, report, cleanup,
    async command(_executable, args, options) {
      assert.equal(options.timeout, 120000); commands.push(args[1]);
      if (args[1] === 'capture') {
        await writeFile(join(options.cwd, 'capture.observation.json'), JSON.stringify(capture));
        await writeFile(join(options.cwd, 'original.json'), JSON.stringify(original));
        throw failure;
      }
      assert.equal(args[1], 'saved');
      return {pid: 456, code: 0, signal: null, wallNs: 10, stdout: JSON.stringify({phase: 'saved',
        pid: 456, complete: true, firstClose: 'returned', aliveScopedFD: {before: 0, after: 0},
        submits: 0, sourceFreeMaxWork: 30000000,
        requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824},
        cases: [{count: 100000, complete: true}]})};
    }}), error => error === failure);
  assert.deepEqual(commands, ['capture', 'saved']);
  assert.equal(report.collection[0].status, 'failed'); assert.equal(report.collection[0].completed, false);
  assert.equal(report.collection[1].status, 'passed'); assert.equal(report.collection[1].completed, true);
  assert.deepEqual(cleanup, []);
  assert(!(await readdir(join(root, 'collection'))).includes('node_modules'));
  const collection = join(root, 'collection');
  assert(await completedCollectionCapture(collection, 123));
  for (const changed of [{...capture, firstClose: 'threw'}, {...capture, cleanup: [{code: 'pending'}]},
    {...capture, aliveScopedFD: {before: 1, after: 1}}, {...capture, cases: []}]) {
    await writeFile(join(collection, 'capture.observation.json'), JSON.stringify(changed));
    assert.equal(await completedCollectionCapture(collection, 123), false);
  }
  await writeFile(join(collection, 'capture.observation.json'), JSON.stringify(capture));
  await writeFile(join(collection, 'original.json'), JSON.stringify({...original, ref: {nonce: 'foreign'}}));
  assert.equal(await completedCollectionCapture(collection, 123), false);
});


test('small policy and oracle units run during Draft while normal required gates remain intact', () => {
  const steps = workflow.jobs.lint.steps;
  for (const name of ['Test collection budget and required packed README selection',
    'Test ordinary operation performance policy oracles', 'Test plain-init Native numeric result and refusal oracles']) {
    const step = steps.find(value => value.name === name); assert(step); assert.equal(step.if, undefined);
  }
  const collection = steps.find(value => value.name === 'Test collection budget and required packed README selection');
  for (const file of ['local-result-read-policy', 'client-result-collection-policy', 'request-memory-policy'])
    assert(collection.run.includes(`adapters/host-node/${file}.test.mjs`));
  const policy = steps.find(value => value.name === 'Test ordinary operation performance policy oracles');
  const rest = steps.find(value => value.name === 'Test ordinary operation performance assessment');
  assert(rest.if.includes('draft'));
  for (const file of ['scripts/operation-performance.test.mjs', 'scripts/benchmark-node-operations.test.mjs',
    'scripts/operation-performance-policy.test.mjs', 'scripts/operation-performance-native-control.test.mjs',
    'scripts/benchmark-node-process-operations.test.mjs', 'scripts/benchmark-node-sqlite.test.mjs',
    'scripts/benchmark-node-boundaries.test.mjs', 'scripts/node-operation-fs-trace.test.mjs',
    'scripts/operation-performance-priority-transition.test.mjs', 'scripts/operation-performance-transition-ci.test.mjs',
    'scripts/native-approval-performance.test.mjs']) {
    const occurrences = [...policy.run.split(/\s+/u), ...rest.run.split(/\s+/u)].filter(value => value === file);
    assert.equal(occurrences.length, 1, file);
  }
  assert(gateJobs.includes('client-readme-packed')); assert.deepEqual(workflow.jobs.check.needs, gateJobs);
});
