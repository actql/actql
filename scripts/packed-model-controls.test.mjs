import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, writeFile, lstat, readlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {modelRegistrationProjectFiles} from './fixtures/model-registration-project.mjs';
import {assertModelRequestSnapshotRefusal} from './fixtures/model-control-observations.mjs';
import {packedModelControlPhases, runPackedModelControls, assertPackedModelOutcome} from './packed-model-controls.mjs';

const repository = new URL('../', import.meta.url).pathname;
const work = phase => ({complete: true, sourceAcquisitionStarts: phase === 'capture' ? 2 : 0,
  modelCallStarts: phase === 'capture' ? 4 : 0, effectReplacementReturns: phase === 'approve' ? 2 : 0});
function explicitRows(phase, pid) {
  const firstClose = {attempted: true, returned: true};
  if (phase === 'budget') return [{kind: 'model-registry-budget', phase, pid, registeredMetadata: 129,
    selectedModelTasks: 0, status: 'passed', firstClose, submits: 2,
    requestMemory: {retainedBytes: 268435456, executionBytes: 268435456},
    budgetInputBytes: 8 * 1024 * 1024 + Buffer.byteLength('/**/ SELECT 7 AS n'),
    budgetRefusal: {verified: true, scope: 'request_snapshot', classification: 'resource_limit'},
    sameHostSmallResult: true, smallTerminal: {status: 'succeeded'}, workObservation: work(phase),
    aliveScopedFD: {after: 0}}];
  return [{phase, status: 'passed', firstFailedStep: null, firstClose, workObservation: work(phase)},
    {kind: 'model-registry-workflow', phase, pid, registeredMetadata: 129, selectedModelTasks: 2,
      selectedCallsOnCapture: 4, claims129SelectedSlots: false, originalImportFailed: false,
      inputsAbsentBeforeRecovery: phase !== 'capture', aliveScopedFD: {after: 0}}];
}
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-model-controls-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const consumer = join(root, 'software'); await mkdir(join(consumer, 'node_modules'), {recursive: true});
  const records = packedModelControlPhases.map(phase => ({phase, completed: false, status: 'unexecuted'}));
  const failures = [], calls = [], verifies = [];
  const prepared = {consumer, manifest: {}, manifestPath: join(root, 'manifest.json')};
  const command = async (_exe, args, options) => {
    const phase = args.length === 1 ? 'budget' : args[1];
    calls.push(phase);
    assert.equal(options.timeout, 120000);
    assert.equal(await readlink(join(options.cwd, 'node_modules')), join(consumer, 'node_modules'));
    const registry = JSON.parse(await readFile(join(options.cwd, 'model-tasks.json'), 'utf8'));
    assert.equal(Object.keys(registry.tasks).length, 129);
    assert.equal(await readFile(join(options.cwd, 'workflow-original.mjs'), 'utf8'),
      await readFile(join(repository, 'adapters/host-node/fixtures/mock-project-effect-public.mjs'), 'utf8'));
    if (phase !== 'budget') {
      assert.deepEqual(args.slice(2), [join(options.cwd, 'handoff.json'), 'deal-review-mock', 'two-models']);
      for (const path of ['deal-review.program.json', 'mock/deal-review.v1.answers.yaml', 'mock/deal-review-confirm.v1.answers.yaml']) {
        if (phase === 'capture') assert((await readFile(join(options.cwd, path))).length > 0);
        else await assert.rejects(lstat(join(options.cwd, path)), {code: 'ENOENT'});
      }
    }
    return {pid: 20000 + calls.length, code: 0, signal: null,
      stdout: explicitRows(phase, 20000 + calls.length).map(value => JSON.stringify(value)).join('\n') + '\n'};
  };
  return {root, prepared, records, failures, calls, verifies, command,
    verifyPackages: async (...args) => {verifies.push(args); assert.equal(args[2], consumer);}};
}

test('Model129 project registers metadata separately from two selected Tasks and four authored calls', () => {
  const files = modelRegistrationProjectFiles(), registry = JSON.parse(files['model-tasks.json']);
  assert.equal(Object.keys(registry.tasks).length, 129);
  for (const [name, path] of Object.entries(registry.tasks)) {
    assert(files[path.replace(/^\.\//u, '')].startsWith(`task: ${name}\n`));
  }
  const selected = JSON.parse(files['deal-review.program.json']).stages.flatMap(stage => stage.steps)
    .flatMap(step => step.infer ? [step.infer.contract] : []);
  assert.deepEqual(selected, ['model-task:deal-review.v1', 'model-task:deal-review-confirm.v1']);
  assert.equal(Object.keys(JSON.parse(files['actql.config.json']).mock.answers).length, 2);
});

test('Model controls reject inflated registration-as-call counts, replay and missing first close', () => {
  for (const phase of packedModelControlPhases) assertPackedModelOutcome(explicitRows(phase, 42), phase, 42);
  for (const mutate of [rows => {rows[0].workObservation.modelCallStarts = 129;},
    rows => {rows[1].claims129SelectedSlots = true;}, rows => {rows[0].firstClose.returned = false;}]) {
    const rows = explicitRows('capture', 42); mutate(rows);
    assert.throws(() => assertPackedModelOutcome(rows, 'capture', 42), {code: 'ERR_ASSERTION'});
  }
  const replay = explicitRows('recover', 42); replay[0].workObservation.modelCallStarts = 1;
  assert.throws(() => assertPackedModelOutcome(replay, 'recover', 42), {code: 'ERR_ASSERTION'});
});

test('Model budget control requires exact original numerical refusal, not a label or returned Run', () => {
  const detail = {phase: 'request_snapshot', dimension: 'retention', requiredRetentionBytes: '20',
    requiredExecutionBytes: '30', availableRetentionBytes: '10', availableExecutionBytes: '10'};
  const memory = {retainedBytes: 10, executionBytes: 10};
  assert.equal(assertModelRequestSnapshotRefusal([detail], {}, memory).verified, true);
  for (const [observations, receipt] of [[[], {}], [[detail, detail], {}], [[detail], {outcome: {kind: 'accepted'}}],
    [[{...detail, requiredRetentionBytes: '1'}], {}], [[{...detail, phase: 'model_registry'}], {}]]) {
    assert.throws(() => assertModelRequestSnapshotRefusal(observations, receipt, memory), {code: 'ERR_ASSERTION'});
  }
});

test('Model control routing uses one verified artifact and removes Program/answers before approval and Saved', async t => {
  const f = await fixture(t);
  await runPackedModelControls({...f, repository}, {verifyPackages: f.verifyPackages});
  assert.deepEqual(f.calls, packedModelControlPhases); assert.equal(f.verifies.length, 2);
  assert.deepEqual(f.failures, []); assert(f.records.every(record => record.completed && record.status === 'passed'));
  assert.equal(f.records[0].inputRemoval.completed, true); assert.equal(f.records[0].inputRemoval.paths.length, 3);
  assert.equal(f.records[1].inputsAbsentBeforeRecovery, true);
  assert.equal(f.records[2].inputsAbsentAfterSaved, true);
  for (const name of ['model-registry-129', 'model-registry-129-budget']) {
    await assert.rejects(lstat(join(f.root, name, 'node_modules')), {code: 'ENOENT'});
  }
});

test('Model capture timeout preserves same-child primary and pending close and leaves recovery unexecuted', async t => {
  const f = await fixture(t), original = Object.assign(new Error('OriginalTimeout'), {code: 'ETIMEDOUT'});
  await runPackedModelControls({...f, repository, async command(exe, args, options) {
    if (args[1] !== 'capture') return f.command(exe, args, options);
    const pending = {phase: 'capture', pid: 81, status: 'failed', code: 'OriginalBeforeClose',
      firstClose: {attempted: true, returned: false, state: 'pending'}};
    await writeFile(join(options.cwd, 'capture.pending.json'), JSON.stringify(pending));
    original.commandResult = {pid: 81, code: null, signal: 'SIGTERM', stdout: ''}; throw original;
  }}, {verifyPackages: f.verifyPackages});
  assert.strictEqual(f.failures[0], original);
  assert.equal(f.records[0].partialObservation.code, 'OriginalBeforeClose');
  assert.equal(f.records[0].partialObservation.firstClose.returned, false);
  assert.equal(f.records[0].completed, false); assert.equal(f.records[0].status, 'failed');
  assert(f.records.slice(1, 3).every(record => !record.completed && record.status === 'unexecuted'));
  assert.equal(f.records[3].status, 'passed');
  assert((await readFile(join(f.root, 'model-registry-129/deal-review.program.json'))).length > 0);
});

test('Model capture cannot remove inputs merely because a child exited zero', async t => {
  const f = await fixture(t);
  await runPackedModelControls({...f, repository, async command(exe, args, options) {
    const result = await f.command(exe, args, options);
    if (args[1] === 'capture') {
      const rows = result.stdout.trim().split('\n').map(JSON.parse); rows[0].firstClose.returned = false;
      result.stdout = rows.map(row => JSON.stringify(row)).join('\n');
    }
    return result;
  }}, {verifyPackages: f.verifyPackages});
  assert.equal(f.records[0].status, 'failed'); assert.equal(f.records[0].summary.firstClose.returned, false);
  assert.equal(f.records[0].inputRemoval, undefined);
  assert((await readFile(join(f.root, 'model-registry-129/mock/deal-review.v1.answers.yaml'))).length > 0);
});

test('Model input-removal refuses changed authored input after a real close receipt', async t => {
  const f = await fixture(t);
  await runPackedModelControls({...f, repository, async command(exe, args, options) {
    const result = await f.command(exe, args, options);
    if (args[1] === 'capture') await writeFile(join(options.cwd, 'deal-review.program.json'), 'changed');
    return result;
  }}, {verifyPackages: f.verifyPackages});
  assert.equal(f.records[0].status, 'failed'); assert.equal(f.records[0].inputRemoval.completed, false);
  assert.deepEqual(f.records[0].inputRemoval.paths, []);
  assert.equal(await readFile(join(f.root, 'model-registry-129/deal-review.program.json'), 'utf8'), 'changed');
});

test('Model fixture closure has only ordinary public imports and preserves preclose receipt ordering', async () => {
  const budget = await readFile(new URL('./fixtures/packed-model-budget.mjs', import.meta.url), 'utf8');
  const workflow = await readFile(new URL('./fixtures/packed-model-workflow.mjs', import.meta.url), 'utf8');
  assert(budget.includes("from '@actql/node'")); assert(budget.includes("from '@actql/sdk'"));
  assert(!budget.includes('clientProgram')); assert(!workflow.includes('clientProgram'));
  assert(budget.indexOf("state: client ? 'pending'") < budget.indexOf('await client.close()'));
  assert(budget.indexOf('await save(); // Accepted original') < budget.indexOf('await run.wait()'));
  const shared = await readFile(new URL('./fixtures/model-control-observations.mjs', import.meta.url), 'utf8');
  assert(!shared.includes('deal-review-two-models'));
});
