import assert from 'node:assert/strict';
import {test} from 'node:test';
import {nativeLocalDefaultAssets} from './native-cli-default-assets.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {finishSourceFreeObservations} from './test-native-cli-source-free-install.mjs';
import {observeFreshSubmissionFailureDiagnostic, preserveOrdinaryFailureWithDiagnostic,
  observeNativeNumericScale, verifyNativeNumericRows, prepareNativeNumericOperator,
  observeNativeNumericOperatorScale, nativeResourceShapeFixtures, verifyNativeResourceRows,
  observeNativeResourceOperatorShapes, requireNativeSourceFreeWorkCounts, observeNativeSourceFreeCommand}
  from './test-native-cli-source-free-install.mjs';

test('Native requirements construction stays inside the original business scope with its typed failure', async () => {
  const source = await readFile(new URL('../src/cmd/native_client/local_command_business_preparation.mbt', import.meta.url), 'utf8');
  const enclosed = `let requirements = self.with_business_request(capture, () => {
    match @local_values.prepare_source_free_runtime_requirements_result(
      prepared, runtime.installed_contracts, assets.values, Some(assets.fragment), assets.ordered,
    ) {
      Ok(original) => original
      Err(issue) => local_stop_runtime_requirements(issue)
    }
  })`.replace(/\s+/gu, ' ');
  const verify = body => {
    assert.equal(body.split('@local_values.prepare_source_free_runtime_requirements_result(').length, 2);
    // Source-enclosure regression only. The installed Native case must still
    // prove actual scope entry, original close and cold Saved independently.
    assert(body.replace(/\s+/gu, ' ').includes(enclosed),
      'The unchanged constructor and typed failure must share the original business callback');
  };
  verify(source);
  assert.throws(() => verify(source.replace('let requirements = self.with_business_request(capture, () => {', 'let requirements = (() => {')));
  assert.throws(() => verify(source.replace('Err(issue) => local_stop_runtime_requirements(issue)', 'Err(issue) => stop("LocalBusinessProgramUnavailable")')));
});

// Independent counter DATA checks, not Native execution or a second protocol
// fixture. The shared diagnostic parser owns stream/schema validation.
const sourceFreeCounterRows = (operation = 'run') => [
  {tag: 21, count: operation === 'result' ? 0 : 1}, {tag: 31, count: 1}, {tag: 58, count: 1},
  {tag: 59, count: 1}, {tag: 17, count: 7},
  {tag: 66, count: operation === 'result' ? 0 : 1},
  {tag: 67, count: operation === 'result' ? 0 : 1},
  {tag: 68, count: operation === 'result' ? 0 : 1},
  {tag: 69, count: operation === 'run' || operation === 'sql' ? 1 : 0},
];

test('source-free existing work counters distinguish actual SQL work from Saved and unrelated JSON helpers', () => {
  for (const operation of ['check', 'run', 'sql', 'result']) {
    const observed = requireNativeSourceFreeWorkCounts(operation, sourceFreeCounterRows(operation));
    assert.equal(observed.measured.checkingEnvironmentAdmissions, operation === 'result' ? 0 : 1);
    assert.equal(observed.measured.legacyJsonOrSubmittedIntentHelperCalls, 7);
    assert.equal(observed.measured.requestQueryParseCalls, operation === 'result' ? 0 : 1);
    assert.equal(observed.measured.requestProgramCompileCalls, operation === 'run' || operation === 'sql' ? 1 : 0);
    assert.deepEqual(observed.unmeasured, {otherCheckerPhaseCalls: null, immutableBodyReadmissionCalls: null});
  }
});

test('source-free existing work counters refuse doubled missing and duplicate actual admission work', () => {
  for (const tag of [21, 31, 58, 59, 66, 67, 68, 69]) {
    for (const count of [0, 2]) {
      const rows = sourceFreeCounterRows().map(row => row.tag === tag ? {...row, count} : row);
      assert.throws(() => requireNativeSourceFreeWorkCounts('run', rows), /Repeated or missing/u);
    }
    assert.throws(() => requireNativeSourceFreeWorkCounts('run', sourceFreeCounterRows().filter(row => row.tag !== tag)), /Missing or duplicate/u);
    assert.throws(() => requireNativeSourceFreeWorkCounts('run', [...sourceFreeCounterRows(), {tag, count: 1}]), /Missing or duplicate/u);
  }
  assert.throws(() => requireNativeSourceFreeWorkCounts('result', sourceFreeCounterRows()), /checking Environment/u);
  const recompiledCheck = sourceFreeCounterRows('check').map(row => row.tag === 69 ? {...row, count: 1} : row);
  assert.throws(() => requireNativeSourceFreeWorkCounts('check', recompiledCheck), /requestProgramCompileCalls/u);
});

test('source-free existing work counters restore diagnostic flags and never retry a failed command', async () => {
  for (const environment of [{}, {ACTQL_NATIVE_TIMINGS: '0', ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: 'prior'}]) {
    const before = {...environment}, failure = new Error('original command failure');
    let calls = 0;
    await assert.rejects(observeNativeSourceFreeCommand({args: ['run', 'query.sql'], cwd: '/selected', environment,
      cli: async (args, cwd) => {
        calls++; assert.deepEqual(args, ['run', 'query.sql']); assert.equal(cwd, '/selected');
        assert.equal(environment.ACTQL_NATIVE_TIMINGS, '1');
        assert.equal(environment.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS, '1');
        throw failure;
      }}), error => error === failure);
    assert.equal(calls, 1); assert.deepEqual(environment, before);
  }
});

test('source-free existing work counters refuse stdout success without complete Native observations', async () => {
  const environment = {}, calls = [];
  await assert.rejects(observeNativeSourceFreeCommand({args: ['sql', 'SELECT 1 AS id'], environment,
    cli: async args => {calls.push(args); return {code: 0, signal: null, stdout: '{"id":1}\n', stderr: ''};}}),
  /launcher timing trailer missing/u);
  assert.equal(calls.length, 1); assert.deepEqual(environment, {});
});

test('source-free existing work counters refuse failed exits and inapplicable operations without inventing counts', async () => {
  const environment = {};
  await assert.rejects(observeNativeSourceFreeCommand({args: ['result', 'original-run'], environment,
    cli: async () => ({code: 1, signal: null, stdout: '{"id":1}\n', stderr: ''})}), {code: 'ERR_ASSERTION'});
  await assert.rejects(observeNativeSourceFreeCommand({args: ['approve', 'original-run'], environment,
    cli: async () => assert.fail('Approval is not this source-free measurement')}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(environment, {});
});

test('fresh submission diagnostic uses one independent project and restores its environment', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-submission-diagnostic-test-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const root = join(parent, 'fresh'), environment = {HOME: 'original-home', TMPDIR: 'original-tmp'};
  const original = {...environment}, calls = [];
  const result = await observeFreshSubmissionFailureDiagnostic({root, environment,
    cli: async (args, cwd) => {
      calls.push(args);
      assert.equal(cwd, root); assert.equal(environment.HOME, join(root, 'home'));
      assert.equal(environment.TMPDIR, join(root, 'tmp'));
      assert.equal(environment.ACTQL_NATIVE_TIMINGS, '1');
      return {stdout: args[0] === 'sql' ? '{"id":2}\n' : ''};
    }});
  assert.deepEqual(calls, [['init', 'project'], ['sql', 'SELECT 2 AS id', '--format', 'jsonl']]);
  assert.deepEqual(environment, original);
  assert.equal(result.newRequests, 1); assert.equal(result.ordinaryAcceptance, false);
});

test('fresh submission diagnostic failures restore the original environment without retry', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-submission-diagnostic-fail-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  for (const failingStep of [1, 2]) {
    const environment = {HOME: 'original', TMPDIR: 'original-tmp', ACTQL_NATIVE_TIMINGS: 'original-flag'};
    const original = {...environment}, failure = new Error('original diagnostic failure');
    let calls = 0;
    await assert.rejects(observeFreshSubmissionFailureDiagnostic({
      root: join(parent, 'fresh-'+failingStep), environment,
      cli: async () => {if (++calls === failingStep) throw failure; return {stdout: ''};},
    }), error => error === failure);
    assert.equal(calls, failingStep); assert.deepEqual(environment, original);
  }
});

test('fresh submission diagnostic refuses an existing directory before any command', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-submission-existing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const environment = {HOME: 'unchanged'};
  await assert.rejects(observeFreshSubmissionFailureDiagnostic({root, environment,
    cli: async () => assert.fail('Existing state cannot become a diagnostic actor'),
  }), error => error.code === 'EEXIST');
  assert.deepEqual(environment, {HOME: 'unchanged'}); assert.deepEqual(await readdir(root), []);
});

test('ordinary failure remains failed after diagnostic success, failure and later cleanup failure', async () => {
  const primary = new Error('original ordinary Unknown'), diagnostic = new Error('diagnostic failed');
  const success = await preserveOrdinaryFailureWithDiagnostic(primary, async () => ({ordinaryAcceptance: false}));
  assert.equal(success.failure, primary); assert.equal(success.diagnostic.status, 'observed');
  const failed = await preserveOrdinaryFailureWithDiagnostic(primary, async () => {throw diagnostic;});
  assert.deepEqual(failed.failure.errors, [primary, diagnostic]);
  assert.equal(failed.diagnostic.status, 'failed');
  const cleanup = new Error('registry close failed');
  await assert.rejects(finishSourceFreeObservations(undefined, failed.failure, {
    close: async () => {throw cleanup;},
    saveObserved: async () => assert.fail('Diagnostics cannot publish ordinary success'),
    saveFailed: async error => assert.deepEqual(error.errors, [failed.failure, cleanup]),
  }), error => error.errors[0] === failed.failure && error.errors[1] === cleanup);
});

test('source-free provisional observations require successful registry close', async () => {
  const events = [], receipt = {scope: 'synthetic-orchestration-only'};
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const completed = finishSourceFreeObservations(receipt, undefined, {
    close: async () => { events.push('closing'); await pending; events.push('closed'); },
    saveObserved: async value => {
      assert.deepEqual(events, ['closing', 'closed']);
      assert.deepEqual(value, {...receipt, status: 'observed', registryClosed: true});
      events.push('passed');
    },
    saveFailed: async () => assert.fail('No failure expected'),
  });
  await Promise.resolve();
  assert.deepEqual(events, ['closing']);
  release(); await completed;
  assert.deepEqual(events, ['closing', 'closed', 'passed']);
});

test('primary and cleanup failures remain distinguishable and never publish success', async () => {
  for (const [primary, cleanup] of [[true, false], [false, true], [true, true]]) {
    const original = new Error('original runtime failure'), close = new Error('registry close failure');
    const events = [];
    await assert.rejects(finishSourceFreeObservations({scope: 'synthetic-only'}, primary ? original : undefined, {
      close: async () => { events.push('close'); if (cleanup) throw close; },
      saveObserved: async () => assert.fail('Failure cannot publish a passing receipt'),
      saveFailed: async error => {
        assert.deepEqual(events, ['close']);
        if (primary && cleanup) assert.deepEqual(error.errors, [original, close]);
        else assert.equal(error, primary ? original : close);
        events.push('failed');
      },
    }), error => primary && cleanup ? error instanceof AggregateError
      && error.errors[0] === original && error.errors[1] === close : error === (primary ? original : close));
    assert.deepEqual(events, ['close', 'failed']);
  }
});

test('failure evidence write errors do not erase the runtime or cleanup failure', async () => {
  const original = new Error('runtime failure'), saving = new Error('evidence write failed');
  await assert.rejects(finishSourceFreeObservations(undefined, original, {
    close: async () => {},
    saveObserved: async () => assert.fail('Failure cannot publish success'),
    saveFailed: async () => { throw saving; },
  }), error => error instanceof AggregateError && error.errors[0] === original && error.errors[1] === saving);
});

test('missing observations and passing-receipt write failures are not success', async () => {
  let closed = false, saved = false;
  await assert.rejects(finishSourceFreeObservations(undefined, undefined, {
    close: async () => { closed = true; },
    saveObserved: async () => { saved = true; },
    saveFailed: async () => assert.fail('No primary failure supplied'),
  }), /Completed source-free observations required/u);
  assert(closed); assert.equal(saved, false);
  const saving = new Error('passing evidence could not be saved');
  await assert.rejects(finishSourceFreeObservations({}, undefined, {
    close: async () => {}, saveObserved: async () => { throw saving; },
    saveFailed: async () => assert.fail('A write error must propagate'),
  }), error => error === saving);
});

// Real process-exit ownership tests, not Native execution or package evidence.
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {runCleanupConditionedConsumer} from './test-native-cli-source-free-install.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

test('Native numeric oracle checks every row including the tail and rejects incomplete or extra contents', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-numeric-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'rows.jsonl');
  await writeFile(path, '{"v0":0}\n{"v0":1}\n{"v0":2}\n');
  assert.deepEqual(await verifyNativeNumericRows(path, 3), {rows: 3, sum: '3', squares: '5'});
  for (const wire of ['{"v0":0}\n{"v0":1}\n',
    '{"v0":0}\n{"v0":1}\n{"v0":1}\n',
    '{"v0":0}\n{"v0":1}\n{"v0":2}\n{"v0":3}\n',
    '{"v0":0}\n{"v0":1}\n{"v0":2,"extra":true}\n']) {
    await writeFile(path, wire);
    await assert.rejects(verifyNativeNumericRows(path, 3));
  }
});

// These replies exercise the acceptance harness, never claim Native/runtime
// success. The normal Linux installation below executes the real entry.
async function numericHarness(t, {corruptSaved = false, failRun = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-numeric-harness-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const calls = [], original = {version: 'actql-run-state/0.1', run_id: 'same-original', status: 'succeeded'};
  const cli = async (args, cwd) => {
    assert.equal(cwd, root); calls.push(args);
    if (args[0] === 'run') {
      assert.deepEqual(args, ['run', 'numeric-scale.json', '--format', 'json', '--json']);
      const wire = await readFile(join(root, 'numeric-scale.json'), 'utf8');
      assert(Buffer.byteLength(wire) > 1048576);
      const values = JSON.parse(wire).stages[0].steps[0].values;
      assert.equal(values.rows.length, 100000); assert.deepEqual(values.rows.at(-1), {v0: 99999});
      if (failRun) throw new Error('OriginalNativeFailure');
    } else {
      assert.equal(args[1], original.run_id);
      if (args[0] === 'status') assert.equal(existsSync(join(root, 'numeric-scale.json')), false);
      else {
        assert.deepEqual(args.slice(2, -1), ['--result', 'answer0', '--format', 'jsonl', '--output']);
        const saved = args.at(-1) === join(root, 'numeric-saved.jsonl');
        assert.equal(existsSync(join(root, 'numeric-scale.json')), !saved);
        const rows = Array.from({length: 100000}, (_, index) => JSON.stringify({
          v0: corruptSaved && saved && index === 99999 ? 0 : index})).join('\n') + '\n';
        await writeFile(args.at(-1), rows, {flag: 'wx'});
      }
    }
    return {code: 0, signal: null, stdout: JSON.stringify(original), stderr: ''};
  };
  return {root, calls, observe: () => observeNativeNumericScale({project: root, cli})};
}

test('Native numeric harness submits once and reads full original Saved only after source removal', async t => {
  const actor = await numericHarness(t), report = await actor.observe();
  assert.deepEqual(actor.calls.map(args => args[0]), ['run', 'result', 'status', 'result']);
  assert.equal(report.first.rows, 100000); assert.deepEqual(report.saved, report.first);
  assert.equal(report.inputRemovedBeforeSaved, true); assert.equal(report.independentFdInspection, false);
});

test('Native numeric Saved corruption stays failed without another submission', async t => {
  const actor = await numericHarness(t, {corruptSaved: true});
  await assert.rejects(actor.observe(), /Numeric Result row 99999/u);
  assert.deepEqual(actor.calls.map(args => args[0]), ['run', 'result', 'status', 'result']);
  assert.equal(existsSync(join(actor.root, 'numeric-saved.jsonl')), true);
});

test('Native numeric original failure is not retried or reclassified as Saved success', async t => {
  const actor = await numericHarness(t, {failRun: true});
  await assert.rejects(actor.observe(), /OriginalNativeFailure/u);
  assert.deepEqual(actor.calls.map(args => args[0]), ['run']);
  assert.equal(existsSync(join(actor.root, 'numeric-scale.json')), true);
});

async function ownedConsumer(t, mode) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-source-free-cleanup-test-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const observationPath = join(directory, 'observed.json'), receiptPath = join(directory, 'passed.json'),
    failurePath = join(directory, 'failed.json');
  const expected = {scope: 'synthetic-cleanup-orchestration-only', cliSourceSha: 'a'.repeat(40)};
  const source = `
import {createOwnedScratch} from ${JSON.stringify(new URL('./owned-scratch.mjs', import.meta.url).href)};
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const mode = ${JSON.stringify(mode)};
const scratch = await createOwnedScratch({parent: ${JSON.stringify(directory)}, prefix: 'consumer-',
  label: 'real consumer cleanup probe',
  digests: () => mode === 'cleanup-failure' ? ['missing-original.tgz'] : []});
await writeFile(join(scratch.path, 'original'), 'actual retained file');
await writeFile(${JSON.stringify(observationPath)}, JSON.stringify({
  ...${JSON.stringify(expected)}, status: 'observed', registryClosed: true, consumer: scratch.path}));
if (mode === 'primary-failure') throw new Error('actual child failure');
if (mode === 'signal') process.kill(process.pid, 'SIGTERM');
if (mode !== 'unconfirmed') scratch.passed();
`;
  const run = () => runCleanupConditionedConsumer({command: process.execPath,
    args: ['--input-type=module', '-e', source], observationPath, receiptPath, failurePath, expected,
    env: {...process.env, ACTQL_TEST_PRESERVE_SCRATCH: mode === 'preserve' ? '1' : ''}, timeout: 10_000});
  return {directory, observationPath, receiptPath, failurePath, run};
}

test('only a real child exit zero with its owned scratch removed publishes final success', async t => {
  const fixture = await ownedConsumer(t, 'success');
  const receipt = await fixture.run();
  assert.equal(receipt.status, 'passed'); assert.equal(receipt.scratchRemoved, true);
  assert.equal(receipt.consumerProcess.code, 0); assert.equal(receipt.consumerProcess.signal, null);
  assert.match(receipt.consumerProcess.stdout, /removed .*consumer-/u);
  assert.equal(existsSync(receipt.consumer), false);
  assert.equal(existsSync(fixture.observationPath), false);
  assert.deepEqual(JSON.parse(await readFile(fixture.receiptPath)), receipt);
  assert.deepEqual(await readdir(fixture.directory), ['passed.json']);
});

for (const [mode, code] of [['cleanup-failure', 2], ['unconfirmed', 1], ['primary-failure', 1], ['preserve', 0], ['signal', null]]) {
  test(`real child ${mode} never publishes a passed receipt`, async t => {
    const fixture = await ownedConsumer(t, mode);
    await assert.rejects(fixture.run());
    assert.equal(existsSync(fixture.receiptPath), false);
    const failed = JSON.parse(await readFile(fixture.failurePath));
    assert.equal(failed.status, 'failed'); assert.equal(failed.child.code, code);
    assert.equal(existsSync(failed.consumer), true);
    assert.equal(existsSync(fixture.observationPath), true);
    if (mode === 'cleanup-failure') assert.match(failed.child.stderr, /test passed; cleanup failed:.*ENOENT/u);
    if (mode === 'preserve') assert.match(failed.error, /Consumer scratch remains/u);
    if (mode === 'signal') assert.equal(failed.child.signal, 'SIGTERM');
  });
}

test('real registry callback failure cannot produce even provisional observations', async () => {
  const registry = await openReleaseTestRegistry([]);
  await registry.close();
  let failure;
  await assert.rejects(finishSourceFreeObservations({scope: 'synthetic-orchestration-only'}, undefined, {
    close: () => registry.close(),
    saveObserved: async () => assert.fail('A failed close cannot produce observations'),
    saveFailed: async error => { failure = error; },
  }), {code: 'ERR_SERVER_NOT_RUNNING'});
  assert.equal(failure.code, 'ERR_SERVER_NOT_RUNNING');
});

import {chmod, mkdir, utimes, writeFile} from 'node:fs/promises';
import {observeNativeInitializationSupport, observeCatalogOnlyMockRefusal, observeTimingEnabledPlainInitialization} from './test-native-cli-source-free-install.mjs';

const supportReply = {code: 0, signal: null, stderr: '',
  stdout: '{"version":"actql-project-init-support/0.1","sourceFree":true,"mock":false}\n'};
const refusalReply = {code: 69, signal: null, stdout: '',
  stderr: 'actql: The installed Native runtime does not implement the selected project bindings; no project files were created.\n'};
const timingReply = {code: 0, signal: null,
  stdout: `Local Host adopted; no Run has been admitted.\nAccount: local-cli\nAdoption: sha256:${'a'.repeat(64)}\n`,
  stderr: 'ACTQL_NATIVE_TIMINGS {"pid":123,"origin":"first_hook","child_process_counters":false}\n' +
    'ACTQL_NATIVE_LAUNCHER_TIMINGS {"units":"nanoseconds","preparation":1,"child":2,"total":3}\n'};
async function initRoot(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-init-harness-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

test('init harness independently requires both templates, both target states and repeated no-write refusals', async t => {
  const root = await initRoot(t), calls = [];
  // Synthetic replies test harness assertions only, never Native acceptance.
  const report = await observeNativeInitializationSupport({root, cli: async (args, cwd, code = 0) => {
    calls.push({args, cwd, code}); return args.at(-1) === 'project-init-support' ? supportReply : refusalReply;
  }});
  assert.equal(report.scope, 'unsupported-mock-initialization-refusal-only');
  assert.equal(calls.length, 9); assert.equal(report.cases.length, 8);
  assert.deepEqual(calls[0], {args: ['--config', join(root, 'query-no-write/actql.config.json'),
    '--state-dir', join(root, 'query-no-write/state'), 'project-init-support'], cwd: join(root, 'query-no-write'), code: 0});
  assert.deepEqual(report.query.before, report.query.after);
  assert.deepEqual(report.query.after.entries, []);
  const expected = [];
  for (const template of ['deal-review-mock', 'churn-risk-mock']) for (const target of ['new', 'empty']) {
    for (let i = 0; i < 2; i++) expected.push({args: ['init', '--template', template, target],
      cwd: join(root, `refused-${template}`), code: 69});
  }
  assert.deepEqual(calls.slice(1), expected);
  for (const value of report.cases) {
    assert.deepEqual(value.parentBefore, value.parentAfter);
    assert.deepEqual(value.emptyBefore, value.emptyAfter);
    for (const key of ['dev', 'ino', 'mode', 'mtimeNs', 'ctimeNs']) assert.equal(typeof value.emptyAfter[key], 'string');
  }
});

for (const change of ['created-new', 'changed-mode', 'changed-mtime', 'created-entry', 'wrong-code', 'unexpected-stdout']) {
  test(`no-write harness refuses ${change} despite a purported unsupported reply`, async t => {
    const root = await initRoot(t);
    await assert.rejects(observeNativeInitializationSupport({root, cli: async (args, cwd) => {
      if (args.at(-1) === 'project-init-support') return supportReply;
      if (change === 'created-new') await mkdir(join(cwd, 'new'));
      if (change === 'changed-mode') await chmod(join(cwd, 'empty'), 0o755);
      if (change === 'changed-mtime') await utimes(join(cwd, 'empty'), 123, 456);
      if (change === 'created-entry') await writeFile(join(cwd, 'empty', 'partial'), 'unexpected project data');
      return {...refusalReply, ...(change === 'wrong-code' ? {code: 0} : {}),
        ...(change === 'unexpected-stdout' ? {stdout: 'scaffolded\n'} : {})};
    }}));
  });
}

test('malformed or unavailable Native capability cannot silently skip refusal coverage', async t => {
  for (const reply of [{...supportReply, code: 69}, {...supportReply, stderr: 'query diagnostics'},
    {...supportReply, stdout: '{"version":"actql-project-init-support/0.1","sourceFree":true,"mock":1}\n'}]) {
    const root = await initRoot(t);
    await assert.rejects(observeNativeInitializationSupport({root, cli: async () => reply}));
    assert.deepEqual(await readdir(root), ['query-no-write']);
    assert.deepEqual(await readdir(join(root, 'query-no-write')), []);
  }
});

test('available Native Mock implementation stays unmeasured in the source-free consumer', async t => {
  const root = await initRoot(t), calls = [];
  const report = await observeNativeInitializationSupport({root, cli: async (args, cwd) => {
    calls.push({args, cwd});
    return {...supportReply, stdout: '{"version":"actql-project-init-support/0.1","sourceFree":true,"mock":true}\n'};
  }});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].args.at(-1), 'project-init-support');
  assert.equal(report.scope, 'mock-implementation-available-execution-unmeasured');
  assert.equal(report.support.mock, true);
  assert.deepEqual(report.cases, []);
  assert.deepEqual(report.query.before, report.query.after);
  assert.deepEqual(await readdir(root), ['query-no-write']);
  assert.deepEqual(await readdir(join(root, 'query-no-write')), []);
});

test('plain init harness selects timings only for init and restores the caller environment', async () => {
  for (const initial of [undefined, '0', '1']) {
    const environment = initial === undefined ? {} : {ACTQL_NATIVE_TIMINGS: initial};
    const report = await observeTimingEnabledPlainInitialization({root: '/synthetic-root', environment,
      cli: async (args, cwd) => {
        assert.deepEqual(args, ['init', 'project']); assert.equal(cwd, '/synthetic-root');
        assert.equal(environment.ACTQL_NATIVE_TIMINGS, '1'); return timingReply;
      }});
    assert.deepEqual(environment, initial === undefined ? {} : {ACTQL_NATIVE_TIMINGS: initial});
    assert.equal(report.scope, 'plain-initialization-with-diagnostics');
  }
});

test('init failure and missing or duplicated timing markers never become initialization success', async () => {
  const environment = {};
  await assert.rejects(observeTimingEnabledPlainInitialization({root: '/synthetic-root', environment,
    cli: async () => { throw new Error('real call failed'); }}), /real call failed/u);
  assert.deepEqual(environment, {});
  for (const reply of [{...timingReply, code: 69}, {...timingReply, stderr: ''},
    {...timingReply, stderr: timingReply.stderr + timingReply.stderr},
    {...timingReply, stderr: timingReply.stderr + 'unrecognized diagnostics\n'},
    {...timingReply, stdout: supportReply.stdout}]) {
    await assert.rejects(observeTimingEnabledPlainInitialization({root: '/synthetic-root', environment,
      cli: async () => reply}));
    assert.deepEqual(environment, {});
  }
});

test('query no-write harness rejects config or state creation before any init attempt', async t => {
  for (const target of ['configuration', 'state']) {
    const root = await initRoot(t);
    let calls = 0;
    await assert.rejects(observeNativeInitializationSupport({root, cli: async args => {
      calls++;
      assert.equal(args.at(-1), 'project-init-support');
      if (target === 'configuration') await writeFile(args[1], '{}\n');
      else await mkdir(args[3]);
      return supportReply;
    }}), /Unexpected initialized target/u);
    assert.equal(calls, 1);
  }
});

const catalogRefusalReply = {code: 1, signal: null, stdout: '',
  stderr: 'actql-native-client: LocalProjectBindingsUnavailable\n'};

test('catalog-only control requires its original Native refusal without state or input creation', async t => {
  const root = await initRoot(t), calls = [];
  // Synthetic replies prove harness assertions only, not Native execution.
  const report = await observeCatalogOnlyMockRefusal({root, cli: async (args, cwd, code) => {
    calls.push({args, cwd, code});
    assert.deepEqual(JSON.parse(await readFile(args[1], 'utf8')), {
      version: 'actql-config/0.1', mock: {catalog: 'never-opened.json'},
      connectors: 'never-opened-connectors.json',
    });
    return catalogRefusalReply;
  }});
  const directory = join(root, 'refused-catalog-only');
  assert.deepEqual(calls, [{args: ['--config', join(directory, 'actql.config.json'),
    '--state-dir', join(directory, 'state'), 'check', 'never-read.aql'], cwd: directory, code: 1}]);
  assert.equal(report.scope, 'catalog-only-mock-binding-refusal-only');
  assert.deepEqual(report.before, report.after);
  assert.deepEqual(report.configurationBefore, report.configurationAfter);
  assert.deepEqual(report.after.entries, ['actql.config.json']);
});

for (const change of ['success', 'foreign-error', 'output', 'created-state', 'created-input', 'changed-config']) {
  test(`catalog-only control rejects ${change} rather than reporting an unsupported-binding pass`, async t => {
    const root = await initRoot(t);
    await assert.rejects(observeCatalogOnlyMockRefusal({root, cli: async (args, cwd) => {
      if (change === 'created-state') await mkdir(args[3]);
      if (change === 'created-input') await writeFile(join(cwd, 'never-opened.json'), '{}');
      if (change === 'changed-config') await writeFile(args[1], '{}');
      return {...catalogRefusalReply, ...(change === 'success' ? {code: 0} : {}),
        ...(change === 'foreign-error' ? {stderr: 'actql-native-client: missing file\n'} : {}),
        ...(change === 'output' ? {stdout: 'verified\n'} : {})};
    }}));
  });
}

function numericOperatorInputs() {
  return {assets: Object.fromEntries([...nativeLocalDefaultAssets()]
    .map(([name, bytes]) => [name, bytes.toString('utf8')])),
    libraries: {sqlite: '/original/installed/sqlite.so', crypto: '/original/installed/crypto.so'},
    runtimeWire: '{"originalManifest":true}\n'};
}

test('Native numeric operator retains low defaults and authors an explicit finite original before adoption', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-numeric-policy-test-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const project = join(parent, 'operator'), inputs = numericOperatorInputs();
  const before = structuredClone(inputs);
  const selected = await prepareNativeNumericOperator({project, ...inputs, maxRows: 100000});
  assert.deepEqual(inputs, before, 'Installed assets and libraries must not be changed');
  assert.equal(JSON.parse(inputs.assets.environment).host_policy_profile.capacity.max_relation_output_rows, 1000);
  const environment = JSON.parse(await readFile(join(project, 'environment.json'), 'utf8'));
  const {evidence_bundle_cid: identity, ...body} = environment;
  verifyIdentity(body, identity);
  const expected = JSON.parse(inputs.assets.environment); delete expected.evidence_bundle_cid;
  Object.assign(expected.host_policy_profile.capacity, {
    max_relation_output_rows: 100000, max_artifact_rows: 100000, max_artifact_bytes: 16777216});
  assert.deepEqual(body, expected, 'No unrelated policy quantity changes');
  assert.deepEqual(selected.configuration, ['--mode', 'local', '--config-root', project,
    '--config-file', 'operator.json']);
  const account = JSON.parse(await readFile(join(project, 'account.json'), 'utf8'));
  assert.deepEqual(account.entries.map(entry => entry.entry_id), ['numeric-result', 'numeric-run']);
  assert.deepEqual(account.entries.map(entry => [entry.resource.any_of, entry.operation.any_of]),
    [[['result/answer0'], ['read']], [['run'], ['cancel', 'publish', 'read', 'submit']]]);
  const configuration = JSON.parse(await readFile(join(project, 'operator.json'), 'utf8'));
  assert.deepEqual(configuration.native.check_environment,
    {file: 'environment.json', evidence_bundle_cid: identity});
  assert.equal(configuration.native.local.sqlite_library, inputs.libraries.sqlite);
  assert.equal(configuration.native.local.signature_library, inputs.libraries.crypto);
  assert.deepEqual(configuration.native.local.installation_files,
    ['run.json', 'read.json', 'retention.json', 'store.json', 'runtime.json', 'profile.json', 'file-read.json']);
  assert.equal(configuration.native.local.run_policy_profile_file, 'profile.json');
  assert.equal(await readFile(join(project, 'runtime.json'), 'utf8'), inputs.runtimeWire);
  const run = JSON.parse(await readFile(join(project, 'run.json'), 'utf8')).native.run;
  const retention = JSON.parse(run.retention_policy_wire);
  const {effective_retention_policy_cid: retentionCid, ...retentionBody} = retention;
  verifyIdentity(retentionBody, retentionCid);
  const profileWire = await readFile(join(project, 'profile.json'), 'utf8');
  const profile = JSON.parse(profileWire);
  assert.deepEqual(profile, {
    version: 'actql-local-run-policy-profile/0.1',
    available_for_ms: 86400000, delete_after_ms: 172800000,
    metadata_after_ms: 604800000, read_for_ms: 86400000,
    effective_data_policy_cid: run.source_free.result_policy_cid,
    retention_contract_cid: retention.retention_contract_cid,
    metadata_retention_policy_cid: retention.metadata_retention_policy_cid,
    clock_contract_cid: retention.clock_contract_cid,
  });
  const read = JSON.parse(await readFile(join(project, 'read.json'), 'utf8')).native.result_read;
  verifyIdentity(profile, read.run_policy_profile_cid);
  assert.equal(Object.hasOwn(read, 'expires_at'), false);
  assert.deepEqual([read.run_file, read.retention_file, read.store_file],
    ['run.json', 'retention.json', 'store.json']);
  const fileRead = JSON.parse(await readFile(join(project, 'file-read.json'), 'utf8')).native.result_read;
  assert.deepEqual(fileRead, {...read, sink: 'file', purpose: 'cli-file'});
  assert.equal(run.source_free.registry, inputs.assets.registry);
  assert.equal(run.source_free.values, inputs.assets.values);
  assert.equal(run.result_payload_bytes, 16777216);
  assert.equal(existsSync(join(project, 'host')), false, 'DATA assembly cannot initialize a Host');
  await assert.rejects(prepareNativeNumericOperator({project, ...inputs, maxRows: 100000}), {code: 'EEXIST'});
  assert.equal(JSON.parse(await readFile(join(project, 'environment.json'), 'utf8')).evidence_bundle_cid, identity);
});

test('Native numeric operator harness uses one selected install and preserves distinct low-policy refusal', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-numeric-operator-harness-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const project = join(parent, 'operator'), calls = [];
  const original = {version: 'actql-run-state/0.1', run_id: 'one-original', status: 'succeeded'};
  const report = await observeNativeNumericOperatorScale({project, ...numericOperatorInputs(),
    cli: async (all, cwd, expected = 0) => {
      assert.deepEqual(all.slice(0, 3), ['--mode', 'local', '--config-root']);
      assert.equal(all[3], cwd); assert.deepEqual(all.slice(4, 6), ['--config-file', 'operator.json']);
      const args = all.slice(6), low = cwd !== project; calls.push({operation: args[0], low});
      const environment = JSON.parse(await readFile(join(cwd, 'environment.json'), 'utf8'));
      assert.equal(environment.host_policy_profile.capacity.max_relation_output_rows, low ? 1 : 100000);
      if (args[0] === 'adopt') {
        assert.deepEqual(args, ['adopt', '--initialize-signing', '--json']);
        return {code: 0, signal: null, stdout: JSON.stringify({kind: 'local_host_adopted'})};
      }
      if (low) {
        if (args[0] === 'run') {
          assert.equal(expected, 1);
          if (args[1] === 'low.json') {
            assert.deepEqual(args, ['run', 'low.json', '--format', 'json', '--json']);
            const small = JSON.parse(await readFile(join(cwd, 'low.json'), 'utf8'));
            assert.deepEqual(small.stages[0].steps[0].values.rows, [{v0: 0}, {v0: 1}]);
          } else {
            assert.deepEqual(args, ['run', 'union-low.sql', '--format', 'sql', '--json']);
            assert.equal(await readFile(join(cwd, 'union-low.sql'), 'utf8'),
              'SELECT 0 AS n UNION ALL SELECT 1 AS n');
          }
          return {code: 1, signal: null, stdout: '', stderr: JSON.stringify({code: 'ACTQL_E_PROGRAM_INVALID'})};
        }
        assert.deepEqual(args, ['sql', 'SELECT 83 AS n', '--format', 'jsonl']);
        assert.equal(expected, 0);
        return {code: 0, signal: null, stdout: '{"n":83}\n'};
      }
      if (args[0] === 'result') {
        assert.equal(args[1], original.run_id);
        assert.equal(dirname(args.at(-1)), project + '-output');
        assert.equal(cwd, project, 'Output placement cannot change the selected Host');
        await writeFile(args.at(-1), Array.from({length: 100000}, (_, v0) => JSON.stringify({v0})).join('\n') + '\n');
      } else if (args[0] === 'status') {
        assert.equal(args[1], original.run_id);
        assert.equal(existsSync(join(project, 'numeric-scale.json')), false);
      } else assert.equal(args[0], 'run');
      return {code: 0, signal: null, stdout: JSON.stringify(original)};
    }});
  assert.deepEqual(calls, ['adopt', 'run', 'result', 'status', 'result'].map(operation => ({operation, low: false}))
    .concat([{operation: 'adopt', low: true}, {operation: 'run', low: true},
      {operation: 'run', low: true}, {operation: 'sql', low: true}]));
  assert.equal(report.first.rows, 100000); assert.equal(report.saved.rows, 100000);
  assert.equal(report.operator.lowPolicyRefused, true);
  assert.equal(report.operator.maxRows, 100000);
  assert.deepEqual(report.operator.lowUnionRowPolicy, {explicitRowPolicy: 1, originalRejectedRows: 2,
    recoveryRows: [{n: 83}], classification: 'static-row-policy-input-invalid',
    sameParentBudgetRefusal: 'not-tested', recoveryFirstCloseObserved: false,
    physicalAckIndependentlyObserved: false});
});

test('Native resource fixtures separate long scalars, Unicode escapes and small-input expansion', () => {
  const [long, unicode, expanded] = nativeResourceShapeFixtures();
  assert.deepEqual([long.id, unicode.id, expanded.id],
    ['few-long-strings', 'unicode-escapes', 'small-input-large-output']);
  assert.deepEqual(long.expectedRows, [{id: 0, text: 'a'.repeat(524288)}, {id: 1, text: 'b'.repeat(524288)}]);
  assert.equal(long.program.stages[0].steps[0].values.rows.length, 2);
  assert(Buffer.byteLength(JSON.stringify(long.program)) > 1048576,
    'Few long scalars must cross the old wire-byte frontier without many nodes');
  assert.equal(unicode.expectedRows[0].text, '日本語😀'.repeat(128));
  assert.equal(unicode.expectedRows[1].text, 'e\u0301'.repeat(128));
  assert.notEqual(unicode.expectedRows[1].text, unicode.expectedRows[1].text.normalize('NFC'));
  assert.equal(unicode.expectedRows[3].text, '"\\\b\f\n\r\t\u0000\u001f'.repeat(128));
  assert.equal(unicode.expectedRows[4].text, '\u2028\u2029'.repeat(128));
  for (const fixture of [long, unicode, expanded]) {
    if (fixture !== long) assert(Buffer.byteLength(JSON.stringify(fixture.program)) < 65536);
    assert.equal(fixture.program.stages[0].steps[0].values.rows[0].text.literal, fixture.expectedRows[0].text);
  }
  assert.equal(expanded.program.stages[0].steps[0].values.rows.length, 1);
  assert.equal(expanded.program.stages[0].steps[1].values.rows.length, 512);
  assert.deepEqual(expanded.program.stages[0].steps[2].cross_join,
    {with: 'right_rows', select: {text: 'left.text', copy: 'right.copy'}});
  assert.equal(expanded.expectedRows.length, 512);
  assert.deepEqual(expanded.expectedRows.at(-1), {text: 'expand:'.repeat(585), copy: 511});
  const inputBytes = Buffer.byteLength(JSON.stringify(expanded.program));
  const outputBytes = expanded.expectedRows.reduce((total, row) => total + Buffer.byteLength(JSON.stringify(row)) + 1, 0);
  assert(inputBytes < 16384); assert(outputBytes > 1048576); assert(outputBytes > 100 * inputBytes);
});

test('Native resource oracle reads full scalars and rejects truncation, normalization, extra rows and fields', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-resource-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'rows.jsonl');
  const expected = [{id: 0, text: 'e\u0301日本語😀"\\\n\u0000'}, {id: 1, text: 'z'.repeat(16384)}];
  const writeRows = rows => writeFile(path, rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  await writeRows(expected);
  const complete = await verifyNativeResourceRows(path, expected);
  assert.equal(complete.rows, 2); assert.match(complete.contentSha256, /^[0-9a-f]{64}$/u);
  assert.equal(complete.wireBytes, (await readFile(path)).length);
  for (const rows of [expected.slice(0, 1), [...expected, expected[1]],
    [expected[0], {...expected[1], text: expected[1].text.slice(0, -1)}],
    [{...expected[0], text: expected[0].text.normalize('NFC')}, expected[1]],
    [expected[0], {...expected[1], extra: true}],
    [expected[0], {id: 1}]]) {
    await writeRows(rows);
    await assert.rejects(verifyNativeResourceRows(path, expected));
  }
});

test('Native resource JSONL preserves Unicode separators across stream chunks and CRLF records', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-resource-unicode-lines-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'rows.jsonl');
  // Cross the read stream chunk boundary, including multi-byte UTF-8 scalars.
  const expected = [{id: 0, text: ('日本語😀\u2028\u2029').repeat(12000)},
    {id: 1, text: 'before\u2028middle\u2029after\n\r'}];
  for (const separator of ['\n', '\r\n']) {
    for (const terminated of [true, false]) {
      const wire = expected.map(row => JSON.stringify(row)).join(separator) + (terminated ? separator : '');
      await writeFile(path, wire);
      const complete = await verifyNativeResourceRows(path, expected);
      assert.equal(complete.rows, 2);
      assert.equal(complete.wireBytes, Buffer.byteLength(wire));
    }
  }
  await writeFile(path, expected.map(row => JSON.stringify(row)).join('\u2028'));
  await assert.rejects(verifyNativeResourceRows(path, expected));
});

test('Native resource keyed oracle accepts permutations and rejects duplicate or missing keys', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-resource-keyed-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'rows.jsonl');
  const expected = [{id: 0, text: 'e\u0301'}, {id: 1, text: '日本語😀'}, {id: 2, text: '"\\\n\u0000'}];
  const writeRows = rows => writeFile(path, rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  await writeRows(expected);
  const original = await verifyNativeResourceRows(path, expected, 'id');
  await writeRows([expected[2], expected[0], expected[1]]);
  assert.deepEqual(await verifyNativeResourceRows(path, expected, 'id'), original);
  for (const rows of [[expected[0], expected[0], expected[2]],
    [expected[2], expected[0]], [...expected, {id: 3, text: 'foreign'}]]) {
    await writeRows(rows);
    await assert.rejects(verifyNativeResourceRows(path, expected, 'id'));
  }
});

// Synthetic replies qualify only this consumer/oracle orchestration. The
// normal Linux job executes these same fixtures through the installed entry.
async function resourceHarness(t, failure) {
  const parent = await mkdtemp(join(tmpdir(), 'actql-native-resource-harness-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const project = join(parent, 'operator'), calls = [];
  const fixtures = nativeResourceShapeFixtures(), inputs = numericOperatorInputs();
  const originalInputs = structuredClone(inputs);
  let fixture;
  const cli = async (all, cwd) => {
    assert.equal(cwd, project);
    assert.deepEqual(all.slice(0, 6), ['--mode', 'local', '--config-root', project, '--config-file', 'operator.json']);
    const args = all.slice(6); calls.push(args);
    const capacity = JSON.parse(await readFile(join(project, 'environment.json'), 'utf8')).host_policy_profile.capacity;
    assert.equal(capacity.max_relation_output_rows, 1024);
    assert.equal(capacity.max_artifact_rows, 1024); assert.equal(capacity.max_artifact_bytes, 16777216);
    assert.deepEqual(inputs, originalInputs);
    if (args[0] === 'adopt') return {code: 0, signal: null, stdout: '{"kind":"local_host_adopted"}'};
    if (args[0] === 'run') {
      fixture = fixtures.find(value => args[1] === value.id + '.json');
      assert(fixture);
      assert.deepEqual(JSON.parse(await readFile(join(project, args[1]), 'utf8')), fixture.program);
      if (failure === 'run') throw new Error('OriginalResourceRunFailure');
    } else {
      assert.equal(args[1], fixture.id + '-original');
      const saved = args[0] === 'status' || args.at(-1).endsWith('-saved.jsonl');
      assert.equal(existsSync(join(project, fixture.id + '.json')), !saved);
      if (args[0] === 'result') {
        assert.equal(dirname(args.at(-1)), project + '-output');
        const rows = structuredClone(fixture.expectedRows);
        if (saved && failure === 'saved-content') rows.at(-1).text += '!';
        if (saved && failure === undefined) rows.reverse();
        await writeFile(args.at(-1), rows.map(row => JSON.stringify(row)).join('\n') + '\n', {flag: 'wx'});
        if (saved && failure === 'saved-cleanup') return {code: 1, signal: null, stdout: '', stderr: 'OriginalCleanupFailure'};
      }
      if (args[0] === 'status' && failure === 'foreign-run') {
        return {code: 0, signal: null, stdout: JSON.stringify({version: 'actql-run-state/0.1',
          run_id: 'foreign', status: 'succeeded'})};
      }
    }
    return {code: 0, signal: failure === 'signal' ? 'SIGTERM' : null, stdout: JSON.stringify({
      version: 'actql-run-state/0.1', run_id: fixture.id + '-original', status: 'succeeded'})};
  };
  return {calls, project, observe: () => observeNativeResourceOperatorShapes({project, cli, ...inputs})};
}

test('Native resource consumer submits each shape once then reads full SAME Saved after input removal', async t => {
  const actor = await resourceHarness(t), report = await actor.observe();
  assert.deepEqual(actor.calls.map(args => args[0]),
    ['adopt', ...Array.from({length: 3}, () => ['run', 'result', 'status', 'result']).flat()]);
  assert.equal(report.observations.length, 3);
  assert.deepEqual(report.observations.map(value => value.first.rows), [2, 5, 512]);
  assert(report.observations[0].inputWireBytes > 1048576);
  assert(report.observations[0].first.wireBytes > 1048576);
  for (const observed of report.observations) {
    assert.equal(observed.inputRemovedBeforeSaved, true);
    assert.deepEqual(observed.saved, observed.first);
    assert.equal(existsSync(join(actor.project, observed.id + '.json')), false);
  }
  assert.equal(report.independentFdInspection, false);
  assert.equal(report.operator.maxRows, 1024);
});

for (const failure of ['run', 'signal', 'saved-content', 'saved-cleanup', 'foreign-run']) {
test(`Native resource ${failure} cannot become acceptance or trigger another submission`, async t => {
  const actor = await resourceHarness(t, failure);
  await assert.rejects(actor.observe());
  assert.equal(actor.calls.filter(args => args[0] === 'run').length, 1);
  assert.equal(actor.calls.some(args => args[1] === 'unicode-escapes.json'), false);
  assert.equal(existsSync(join(actor.project, 'few-long-strings.json')), ['run', 'signal'].includes(failure));
});
}
