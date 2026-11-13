import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, access, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeDefaultNumericQueries, observeNativeDefaultNumericQueries, observeNativeFileSourceNumeric,
  nativeDefaultUnionCases, observeNativeDefaultUnionMetadata}
  from './test-native-cli-source-free-install.mjs';

// Explicit command ports exercise the acceptance oracle, not Native execution.
async function numericFixture(t, fault) {
  const project = await mkdtemp(join(tmpdir(), 'native-default-numeric-oracle-'));
  t.after(() => rm(project, {recursive: true, force: true}));
  const runs = new Map(), calls = [], saved = [], hosts = new Map();
  const cli = async (args, cwd) => {
    calls.push(args);
    const [operation, file] = args;
    if (operation === 'init') {
      assert.equal(cwd, project); assert(!hosts.has(file));
      await mkdir(file); hosts.set(file, 0); return {stdout: ''};
    }
    assert(hosts.has(cwd), 'All submissions must use the one initialized ordinary Host');
    if (operation === 'sql') {
      hosts.set(cwd, hosts.get(cwd)+1);
      return {stdout: '{"total":3}\n'};
    }
    if (file === 'numeric-invalid.sql' || file === 'numeric-invalid-syntax.sql') {
      assert.equal(operation, 'check');
      return {stdout: JSON.stringify({outcome: 'completed', report: {verdict: 'invalid', runnable: {verdict: 'no'}}})};
    }
    if (operation === 'check' || operation === 'run') {
      const entry = nativeDefaultNumericQueries.find(value => file === `numeric-${value.name}.sql`);
      assert(entry); assert.equal(cwd, join(project, 'numeric-cases', 'ordinary'));
      assert.equal(await readFile(join(cwd, file), 'utf8'), entry.sql);
      if (operation === 'check') return {stdout: JSON.stringify({outcome: 'completed', report: {
        verdict: fault === 'check' ? 'undetermined' : 'verified', runnable: {verdict: fault === 'check' ? 'no' : 'yes'},
      }})};
      assert(!runs.has(entry.name), 'The original Program must be submitted only once');
      hosts.set(cwd, hosts.get(cwd)+1);
      runs.set(entry.name, entry);
      return {stdout: JSON.stringify({version: 'actql-run-state/0.1', status: 'succeeded', run_id: entry.name})};
    }
    assert.equal(operation, 'result');
    const entry = runs.get(file); assert(entry);
    let cold = false;
    assert.equal(cwd, join(project, 'numeric-cases', 'ordinary'));
    try {await access(join(cwd, `numeric-${entry.name}.sql`));}
    catch (error) {assert.equal(error.code, 'ENOENT'); cold = true;}
    if (cold) {
      saved.push(entry.name);
      if (entry.parameters) for (const name of ['numeric-declarations.json', 'numeric-parameters.json'])
        await assert.rejects(access(join(cwd, name)), {code: 'ENOENT'});
    }
    const rows = fault === 'live' || (cold && fault === 'saved') ||
      (fault === 'old-saved' && hosts.get(cwd) === 11) ? [{total: 4}] : entry.rows;
    return {stdout: rows.map(value => JSON.stringify(value)).join('\n')+'\n'};
  };
  return {project, cli, calls, runs, saved, hosts};
}

test('default numeric oracle requires runnable checking and same Saved after original input removal', async t => {
  const fixture = await numericFixture(t);
  const observed = await observeNativeDefaultNumericQueries(fixture);
  assert.equal(observed.length, 10); assert.equal(fixture.runs.size, 10);
  assert.equal(fixture.hosts.size, 1); assert.equal([...fixture.hosts.values()][0], 11);
  const names = nativeDefaultNumericQueries.map(entry => entry.name);
  assert.deepEqual(fixture.saved, [...names, ...names]);
  assert(observed.every(entry => entry.savedAfterLaterSubmissions));
  assert.deepEqual(observed[0].rows, [{total: 3}]);
  assert.deepEqual(observed[1].rows, [{total: 1.5}]);
  assert.deepEqual(observed[2].rows, [{total: '4.00'}]);
});

test('default numeric oracle refuses a successful check command with undetermined report before execution', async t => {
  const fixture = await numericFixture(t, 'check');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), /verified check required/u);
  assert.equal(fixture.calls.length, 2); assert.equal(fixture.runs.size, 0);
});

test('default numeric oracle refuses incorrect live rows without submitting a replacement Run', async t => {
  const fixture = await numericFixture(t, 'live');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.runs.size, 1); assert.deepEqual(fixture.saved, []);
});

test('default numeric oracle refuses changed Saved rows without reprepare or reexecution', async t => {
  const fixture = await numericFixture(t, 'saved');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.runs.size, 1); assert.deepEqual(fixture.saved, ['sum']);
});

test('same-project numeric oracle refuses an old Saved changed by later submissions', async t => {
  const fixture = await numericFixture(t, 'old-saved');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.hosts.size, 1); assert.equal(fixture.runs.size, 10);
  assert.equal(fixture.calls.filter(args => args[0] === 'init').length, 1);
});

async function fileFixture(t, fault) {
  const root = await mkdtemp(join(tmpdir(), 'native-file-numeric-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const project = join(root, 'numeric-file-source');
  const program = join(project, 'numeric-source.sql'), source = join(project, 'mock/data.json');
  const original = '{"items":[{"trend":"down"},{"trend":"up"}]}\n';
  const calls = [];
  let reads = 0;
  const cli = async (args, cwd) => {
    calls.push(args);
    if (args[0] === 'init') {
      assert.deepEqual(args, ['init', '--template', 'churn-risk-mock', project]);
      assert.equal(cwd, root);
      await mkdir(join(project, 'mock'), {recursive: true});
      await writeFile(source, original, {flag: 'wx'});
      return {stdout: ''};
    }
    assert.equal(cwd, project);
    if (args[0] === 'check') return {stdout: JSON.stringify({outcome: 'completed',
      report: {verdict: 'verified', runnable: {verdict: 'yes'}}})};
    if (args[0] === 'run') {
      assert.equal(calls.filter(value => value[0] === 'run').length, 1);
      if (fault === 'source') await writeFile(source, 'changed');
      return {stdout: JSON.stringify({status: 'succeeded', run_id: 'original-file-run'})};
    }
    assert.deepEqual(args, ['result', 'original-file-run', '--format', 'jsonl']);
    if (++reads === 1) {await access(program); await access(source);}
    else for (const path of [program, source]) await assert.rejects(access(path), {code: 'ENOENT'});
    const wrong = (fault === 'live' && reads === 1) || (fault === 'saved' && reads === 2);
    return {stdout: JSON.stringify({total: wrong ? 12 : 16, average: 8}) + '\n'};
  };
  return {root, cli, calls, reads: () => reads};
}

test('File CASE oracle verifies complete 16/8 before input removal and same cold Saved', async t => {
  const fixture = await fileFixture(t);
  const observed = await observeNativeFileSourceNumeric(fixture);
  assert.equal(fixture.reads(), 2);
  assert.equal(observed.completeResultBeforeInputRemoval, true);
  assert.equal(observed.coldSavedWithoutProgramOrSource, true);
  assert.deepEqual(observed.rows, [{total: 16, average: 8}]);
});

for (const fault of ['live', 'saved', 'source']) test(`File CASE oracle refuses changed ${fault} without another Run`, async t => {
  const fixture = await fileFixture(t, fault);
  await assert.rejects(observeNativeFileSourceNumeric(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.calls.filter(args => args[0] === 'run').length, 1);
  assert.equal(fixture.calls.filter(args => args[0] === 'init').length, 1);
});

const fixtureCid = value => 'sha256:' + createHash('sha256').update(value).digest('hex');

// Independent WITH-set golden: values/derive/select per literal branch,
// N-1 appends and the final group/select. Port fields follow the common emitter;
// no padding supplies size. This is not actual Native layout/size evidence.
function unionPlanFixture(branches) {
  const compiled = fixtureCid(`compiled-${branches}`), steps = [];
  const append = (operator, producers = []) => {
    const index = steps.length, step = fixtureCid(`step-${branches}-${index}`);
    const output = fixtureCid(`output-${branches}-${index}`);
    steps.push({step_id: step, key: {version: 'actql-logical-step-key/0.1',
      compiled_plan_cid: compiled, self_cid: step, stage_ordinal: 0,
      occurrence: {kind: 'operation', operation_ordinal: index}}, operator,
      names: operator === 'derive' || operator === 'group' ? [] : [`binding-${index}`],
      can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed',
      ports: [...producers.map((producer, ordinal) => ({
        port_id: fixtureCid(`input-${branches}-${index}-${ordinal}`), role: 'input',
        port_ordinal: ordinal, carrier: 'relation', carrier_contract_cid: fixtureCid('relation'),
        can_sample: false, sample_reason: 'not_installed', source: {kind: 'logical_output', step_id: producer.step, output_port_id: producer.output},
      })), {port_id: output, role: 'output', port_ordinal: 0, carrier: 'relation',
        carrier_contract_cid: fixtureCid('relation'), can_sample: false, sample_reason: 'not_installed',
        source: {kind: 'logical_output', step_id: step, output_port_id: output}}]});
    return {step, output};
  };
  const terms = Array.from({length: branches}, () => append('select', [append('derive', [append('values')])]));
  let combined = terms[0];
  for (const term of terms.slice(1)) combined = append('append', [combined, term]);
  append('select', [append('group', [combined])]);
  return {version: 'actql-plan-view/0.1', compiled_plan_cid: compiled,
    observation: 'static', provider_io: 0, quantities: [{kind: 'unknown', unit: 'work', reason: 'not_observed'}],
    capabilities: {static_plan: true, inspect: false, durable_control: false, sample_capture: [],
      full_intermediate_retention: [], cost_guard: false, execution_batch: false, policy_revision_cid: fixtureCid('policy')},
    logical_map: {version: 'actql-logical-map/0.1', compiled_plan_cid: compiled,
      program_definition_cid: fixtureCid(`program-${branches}`), self_cid: fixtureCid(`map-${branches}`), steps}};
}

async function unionFixture(t, fault) {
  const root = await mkdtemp(join(tmpdir(), 'native-union-metadata-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const project = join(root, 'ordinary-union-metadata');
  const calls = [], runs = new Map(), explains = new Map();
  const cli = async (args, cwd, expectedCode = 0) => {
    calls.push({args, cwd, expectedCode});
    const reply = value => ({stdout: typeof value === 'string' ? value : JSON.stringify(value), elapsedMs: 17});
    const [operation, id] = args;
    if (operation === 'init') {
      assert.equal(cwd, root); assert.equal(id, project);
      await mkdir(project, {mode: 0o700});
      await writeFile(join(project, 'actql.config.json'), JSON.stringify(fault === 'profile' ? {profile: 'enlarged'} : {}));
      return reply('');
    }
    assert.equal(cwd, project, 'Reuse one ordinary installation');
    if (operation === 'run') {
      const entry = nativeDefaultUnionCases.find(value => id === `union-${value.branches}.sql`);
      assert(entry); assert(!runs.has(id), 'Never resubmit an original');
      const sql = await readFile(join(project, id), 'utf8');
      assert.equal(sql.match(/SELECT [0-9]+ AS v/gu).length, entry.branches);
      assert.equal(sql.match(/UNION ALL/gu).length, entry.branches - 1);
      runs.set(id, entry);
      return reply({version: 'actql-run-state/0.1', status: fault === 'run' ? 'failed' : 'succeeded', run_id: id});
    }
    if (operation === 'sql') {
      if (id === 'SELECT )') {assert.equal(expectedCode, 1); return reply('syntax refused');}
      assert.equal(id, 'SELECT 9821 AS n');
      return reply(fault === 'recovery' ? '{"n":0}\n' : '{"n":9821}\n');
    }
    const runId = operation === 'explain' || operation === 'status' ? args[2] : id;
    const entry = runs.get(runId); assert(entry);
    await assert.rejects(access(join(project, runId)), {code: 'ENOENT'});
    const ref = {namespaceId: 'workspace:original', authorityScopeCid: fixtureCid('original-scope'),
      runDefinitionCid: fixtureCid(runId)};
    if (operation === 'status') {
      assert.deepEqual(args, ['status', '--run-id', runId, '--json']);
      return reply({kind: 'local_saved_run_state', ref, state: {version: 'actql-run-state/0.1',
        status: 'succeeded', run_id: fault === 'status-run' ? 'foreign-run' : runId}});
    }
    if (operation === 'result') {
      const wrong = fault === 'saved' || (fault === 'old-saved' && runs.size === 3 && runId === 'union-11.sql');
      return reply(JSON.stringify({total: wrong ? -1 : entry.total}) + '\n');
    }
    assert.equal(operation, 'explain'); assert.equal(args[3], '--json');
    const count = explains.get(runId) ?? 0; explains.set(runId, count + 1);
    const plan = unionPlanFixture(entry.branches);
    if (fault === 'explain' && count > 0) plan.logical_map.steps[0].names = ['changed'];
    if (fault === 'truncated-plan') plan.logical_map.steps.pop();
    if (fault === 'missing-branch') plan.logical_map.steps.splice(0, 3);
    if (fault === 'missing-derive') {
      const [removed] = plan.logical_map.steps.splice(1, 1), seed = plan.logical_map.steps[0];
      for (const [ordinal, step] of plan.logical_map.steps.entries()) {
        step.key.occurrence.operation_ordinal = ordinal;
        for (const port of step.ports) if (port.role === 'input' && port.source.step_id === removed.step_id)
          port.source = {kind: 'logical_output', step_id: seed.step_id, output_port_id: seed.ports[0].port_id};
      }
    }
    if (fault === 'truncated-ports') plan.logical_map.steps.at(-1).ports.pop();
    if (fault === 'dangling-producer') plan.logical_map.steps.at(-1).ports[0].source = {kind: 'logical_output'};
    if (fault === 'plan-binding') plan.logical_map.compiled_plan_cid = fixtureCid('foreign-plan');
    const envelope = {version: 'actql-run-plan-view/0.1', run_ref: fault === 'foreign-run' ?
      {...ref, runDefinitionCid: fixtureCid('foreign-run')} : ref,
      plan_view: fault === 'empty-plan' ? {} : plan};
    return reply(fault === 'truncated-json' ? JSON.stringify(envelope).slice(0, -1) : envelope);
  };
  return {root, cli, calls, runs, explains};
}

test('UNION metadata oracle requires ordinary 11/17/24, cold Saved and identical repeated explain', async t => {
  const fixture = await unionFixture(t);
  const result = await observeNativeDefaultUnionMetadata(fixture);
  assert.deepEqual(result.cases.map(value => value.branches), [11, 17, 24]);
  assert.deepEqual(result.cases.map(value => value.total), [55, 136, 276]);
  assert.equal(fixture.runs.size, 3);
  assert.equal(fixture.calls.filter(value => value.args[0] === 'init').length, 1);
  assert.equal(fixture.calls.filter(value => value.args[0] === 'result').length, 6);
  assert.deepEqual([...fixture.explains.values()], [2, 2, 2]);
  assert(result.cases.every(value => value.runElapsedMs === 17 && value.recoveryAfterInvalidQuery));
  assert(result.cases.at(-1).planBytes > 65536);
  assert(result.cases.every(value => value.planBytes > 0 && value.logicalSteps === 4 * value.branches + 1));
  assert(result.cases.every(value => value.storedRunMetadataBytes === null));
  assert.equal(fixture.calls.filter(value => value.args[0] === 'status').length, 3);
});

for (const fault of ['profile', 'run', 'recovery', 'saved', 'explain', 'old-saved']) {
  test(`UNION metadata oracle retains ${fault} failure without resubmission`, async t => {
    const fixture = await unionFixture(t, fault);
    await assert.rejects(observeNativeDefaultUnionMetadata(fixture), {code: 'ERR_ASSERTION'});
    assert.equal(fixture.calls.filter(value => value.args[0] === 'init').length, 1);
    assert.equal(fixture.calls.filter(value => value.args[0] === 'run').length, fixture.runs.size);
    assert(fixture.runs.size <= 3);
  });
}

for (const fault of ['empty-plan', 'foreign-run', 'status-run', 'truncated-plan', 'missing-branch', 'missing-derive',
  'truncated-ports', 'dangling-producer', 'plan-binding', 'truncated-json']) {
  test(`UNION metadata oracle rejects ${fault} at the first original without replacement`, async t => {
    const fixture = await unionFixture(t, fault);
    await assert.rejects(observeNativeDefaultUnionMetadata(fixture), error =>
      (error.code === 'ERR_ASSERTION' &&
        (fault !== 'missing-derive' || /Retain every literal evaluation/u.test(error.message))) ||
      (fault === 'truncated-json' && error instanceof SyntaxError));
    assert.equal(fixture.runs.size, 1);
    assert.equal(fixture.calls.filter(value => value.args[0] === 'init').length, 1);
    assert.equal(fixture.calls.filter(value => value.args[0] === 'run').length, 1);
    assert.equal(fixture.calls.filter(value => value.args[0] === 'explain').length,
      fault === 'status-run' ? 0 : 1);
  });
}
