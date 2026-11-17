import assert from 'node:assert/strict';
import test from 'node:test';
import {copyFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {parse} from 'yaml';
import {inventory} from './verification-actions.mjs';
import {nativeSourceFreeShapeDiagnostics, nativeShapeCommandEnvironment}
  from './test-native-source-free-shape-diagnostic.mjs';
import {nativeLauncherEnvelope} from './native-cli-mock-scenario.mjs';
import {observeNativeResourceOperatorShape} from './native-source-free-resource-shape.mjs';
import {nativeResourceShapeFixtures, verifyNativeResourceRows}
  from './test-native-cli-source-free-install.mjs';

const timingStream = ({ledger = 7, family = 9005, cause = 5208, change = value => value} = {}) => {
  const metadata = {pid: 123, overflow: false, initializing_drops: 0, invalid_tags: 0,
    invalid_amounts: 0, clock_failures: 0, stack_overflows: 0};
  const counters = Array.from({length: 70}, (_, tag) => ({tag,
    count: ({10: 11, 11: family, 12: cause, 13: ledger})[tag] ?? 0}));
  const phases = [3, 4].map(tag => ({tag, begins: 1, ends: 1, active: 0,
    unmatched_end: 0, inclusive_ns: tag === 3 ? 100 : 10, exclusive_ns: tag === 3 ? 90 : 10}));
  const selected = change({metadata, counters, phases});
  return 'public original failure\n' + ['ACTQL_NATIVE_TIMINGS ' + JSON.stringify(selected.metadata),
    ...selected.counters.map(value => 'ACTQL_NATIVE_COUNTER ' + JSON.stringify(value)),
    ...selected.phases.map(value => 'ACTQL_NATIVE_PHASE ' + JSON.stringify(value)),
    'ACTQL_NATIVE_LAUNCHER_TIMINGS ' + JSON.stringify({units: 'nanoseconds', preparation: 1, child: 100, total: 101})].join('\n') + '\n';
};

test('failed Native shape preserves exact typed commit/resource tags and nested monotonic phases', () => {
  for (const [ledger, resource] of [[6, 'RetentionLimit'], [7, 'ExecutionLimit']]) {
    const actual = nativeSourceFreeShapeDiagnostics(timingStream({ledger}), nativeLauncherEnvelope);
    assert.equal(actual.publication.resource, resource);
    assert.deepEqual([actual.publication.stageTag, actual.publication.familyTag,
      actual.publication.causeTag, actual.publication.ledgerTag], [11, 9005, 5208, ledger]);
    assert.equal(actual.phases[0].inclusive_ns, 100);
    assert.equal(actual.phases[1].inclusive_ns, 10);
  }
  const other = nativeSourceFreeShapeDiagnostics(timingStream({family: 9006, cause: 3}), nativeLauncherEnvelope);
  assert.equal(other.publication.resource, undefined, 'An unrelated counter13 cannot label an issuance failure');
});

test('partial or invalid Native streams remain unavailable instead of fabricating a zero cause', () => {
  for (const change of [
    value => ({...value, counters: value.counters.slice(1)}),
    value => ({...value, counters: [...value.counters.slice(1), value.counters[1]]}),
    value => ({...value, metadata: {...value.metadata, overflow: true}}),
    value => ({...value, metadata: {...value.metadata, clock_failures: 1}}),
    value => ({...value, phases: [{...value.phases[0], active: 1}, value.phases[1]]}),
  ]) assert.throws(() => nativeSourceFreeShapeDiagnostics(timingStream({change}), nativeLauncherEnvelope));
  assert.throws(() => nativeSourceFreeShapeDiagnostics('original failure\n', nativeLauncherEnvelope));
});

test('only the selected run receives timing flags and no ambient runtime or loader configuration', () => {
  const original = {ACTQL_NATIVE_TIMINGS: '0', ACTQL_NATIVE_LOCAL_RUNTIME: 'foreign',
    ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: '1', NODE_PATH: '/foreign', NODE_OPTIONS: '--inspect',
    LD_PRELOAD: '/foreign', GITHUB_TOKEN: 'not-forwarded', PATH: '/foreign', LANG: 'C', TZ: 'UTC'};
  const before = {...original};
  for (const diagnostic of [false, true]) {
    const env = nativeShapeCommandEnvironment(original, '/private/shape', diagnostic);
    assert.deepEqual(Object.keys(env).sort(), ['HOME', 'LANG', 'PATH', 'TMPDIR', 'TZ',
      ...(diagnostic ? ['ACTQL_NATIVE_TIMINGS'] : [])].sort());
    assert.equal(env.ACTQL_NATIVE_TIMINGS, diagnostic ? '1' : undefined);
    assert.equal(env.PATH, '/private/shape/empty-path');
  }
  assert.deepEqual(original, before);
});

test('shared shape caller verifies all512 original rows and cold Saved without a replacement run', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-shape-caller-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const outputDirectory = join(root, 'out'); await mkdir(outputDirectory);
  const fixture = nativeResourceShapeFixtures().find(value => value.id === 'small-input-large-output');
  const rows = Array.from({length: 512}, (_, copy) => ({text: 'expand:'.repeat(585), copy}));
  assert.deepEqual(fixture.expectedRows, rows);
  const commands = [], configuration = ['--mode', 'local'];
  const state = {version: 'actql-run-state/0.1', status: 'succeeded', run_id: 'original-shape-run'};
  const result = await observeNativeResourceOperatorShape({project: root, configuration, fixture, outputDirectory,
    verifyRows: verifyNativeResourceRows, async cli(args, cwd) {
      assert.equal(cwd, root); assert.deepEqual(args.slice(0, 2), configuration);
      const command = args[2]; commands.push(command);
      if (command === 'run') assert.deepEqual(JSON.parse(await readFile(join(root, args[3]), 'utf8')), fixture.program);
      else {
        assert.equal(args[3], state.run_id);
        if (command === 'status') await assert.rejects(readFile(join(root, fixture.id + '.json')), {code: 'ENOENT'});
        if (command === 'result') await writeFile(args.at(-1), rows.map(row => JSON.stringify(row)).join('\n') + '\n');
      }
      return {code: 0, signal: null, stdout: command === 'result' ? '' : JSON.stringify(state)};
    }});
  assert.deepEqual(commands, ['run', 'result', 'status', 'result']);
  assert.equal(result.first.rows, 512); assert.equal(result.saved.rows, 512);
  assert(result.first.wireBytes > 1048576 && result.inputWireBytes < 16384);
});

test('shared shape caller preserves the failed input and stops before any result or replay', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-shape-refusal-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const fixture = nativeResourceShapeFixtures().find(value => value.id === 'small-input-large-output');
  const original = new Error('OriginalNativeFailure'); let calls = 0;
  await assert.rejects(observeNativeResourceOperatorShape({project: root, outputDirectory: root,
    configuration: [], fixture, verifyRows: () => assert.fail('No failed result read'),
    async cli() {calls++; throw original;}}), error => error === original);
  assert.equal(calls, 1);
  assert.deepEqual(JSON.parse(await readFile(join(root, fixture.id + '.json'), 'utf8')), fixture.program);
});

test('copied collector and shared helper survive switching to the original producer source', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-copied-shape-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  for (const file of ['test-native-source-free-shape-diagnostic.mjs', 'native-source-free-resource-shape.mjs']) {
    await copyFile(new URL(file, import.meta.url), join(root, file));
  }
  const copied = await import(pathToFileURL(join(root, 'test-native-source-free-shape-diagnostic.mjs')));
  assert.equal(copied.nativeSourceFreeShapeDiagnostics(timingStream(), nativeLauncherEnvelope).complete, true);
});

test('hosted shape route reuses diagnostic provenance while formal and ordinary campaigns stay separate', async () => {
  const workflow = parse(await readFile(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const ci = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const actions = inventory({workflowText: JSON.stringify({jobs: {lint: ci.jobs.lint}}),
    packageText: await readFile(new URL('../package.json', import.meta.url), 'utf8')}).actions;
  const unit = actions.find(action => action.origin === 'workflow' && action.job === 'lint' &&
    action.invocation?.kind === 'node-test' && action.invocation.argv.includes('scripts/native-source-free-shape-diagnostic.test.mjs'));
  assert(unit); assert.equal(unit.condition.step, null); assert.equal(unit.condition.continueOnError, false);
  for (const event of ['workflow_dispatch', 'workflow_call']) {
    assert.equal(workflow.on[event].inputs['native-source-free-shape-diagnostic'].default, false);
  }
  const job = workflow.jobs['native-approval'], steps = job.steps;
  const staged = steps.findIndex(value => value.name === 'Stage the narrow source-free diagnostic before original source checkout');
  const bound = steps.findIndex(value => value.name === 'Bind the original Native build source before collection');
  assert(staged >= 0 && staged < bound);
  for (const file of ['test-native-source-free-shape-diagnostic.mjs', 'native-source-free-resource-shape.mjs']) {
    assert(steps[staged].run.includes(file));
  }
  const decode = steps.find(value => value.name === 'Reuse the digest-verified original artifact for CPU diagnosis only');
  assert(decode.if.includes("inputs['native-source-free-shape-diagnostic']"));
  assert(decode.run.includes('extract-native-approval-cpu-artifact'));
  const formal = steps.find(value => value.name === 'Measure thirty complete approvals for each original Native template');
  assert(formal.if.includes("!inputs['native-source-free-shape-diagnostic']"));
  const cpu = steps.find(value => value.name === 'Prepare the opt-in unprivileged flat CPU diagnostic');
  assert.equal(cpu.if, "${{ inputs['native-approval-cpu-diagnostic'] }}");
  const collect = steps.find(value => value.name === 'Diagnose one original source-free small-input-large-output case');
  assert.equal(collect.if, "${{ inputs['native-source-free-shape-diagnostic'] }}");
  const upload = steps.find(value => value.name === 'Retain only source-free failure tags command outcomes and original package metadata');
  assert(upload.if.includes('always()'));
  assert(!upload.with.path.includes('/private'), 'Private Store, signing keys and application state never upload');
  for (const [name, value] of Object.entries(workflow.jobs)) if (name !== 'native-approval' && name !== 'node-wait-cpu') {
    assert(value.if.includes("!inputs['native-source-free-shape-diagnostic']"), name);
  }
});
