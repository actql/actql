import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {DatabaseSync} from 'node:sqlite';
import {mkdtemp, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {connect} from '../../packages/node/index.mjs';
import {openInstalledRemoteHttpHost} from '../../packages/local-node/http-host.mjs';
import {createHostObservationConnection} from '../../packages/local-node/adapters/host-common/observation.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {inputOnlyProgram, runSql, expectedRows} from './fixtures/interactive-read-program.mjs';

async function drain(observation) {
  // The existing finite queue pumps one record per event-loop turn. No sleep
  // or sampling is used as evidence that the actual execution entry was idle.
  for (let i = 0; i < 512; i++) {
    const status = observation.status();
    if (status.queued === 0 && status.active === 0 && status.activeSegments === 0) {
      for (const field of ['dropped', 'deliveryFailed', 'budgetUnavailable',
        'queueOverflow', 'limited']) assert.equal(status[field], 0, field);
      assert.deepEqual(status.loss, {});
      return;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('The finite observation queue did not drain');
}

function starts(records, physicalStarts) {
  return {physical: physicalStarts, source: records.filter(r =>
    r.operation === 'source' && r.event === 'attempt_started').length,
  compute: records.filter(r => r.operation === 'compute' && r.event === 'task_started').length,
  model: records.filter(r => r.operation === 'infer' && r.event === 'attempt_started').length,
  effect: records.filter(r => r.operation === 'effect' && r.event === 'application_observed').length};
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: compiler Plan and original Run Inspect are read-only`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-interactive-read-public-'));
    const principalId = userInfo().username, keys = generateKeyPairSync('ed25519');
    const records = [];
    const observation = createHostObservationConnection({deliver: record => records.push(record)});
    let physicalStarts = 0, client, host, server, completed = false;
    const authorization = {
      accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'interactive-read', entries: [{entry_id: 'execution', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}]}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      faultInjection(name) {if (name === 'physical_start_reserved') physicalStarts++;},
    };
    const installation = {directory: join(root, 'host'), authorization, observation};
    const trust = getCACertificates('default');
    t.after(async () => {
      try {
        await client?.close();
        if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
        await host?.close();
        if (completed) await rm(root, {recursive: true, force: true});
        else t.diagnostic(`Failure custody retained at ${root}`);
      } finally {setDefaultCACertificates(trust);}
    });
    if (entrance === 'local') {
      client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
    } else {
      const certificates = await fixtureCertificates(root);
      setDefaultCACertificates([...trust, certificates.ca.toString('utf8')]);
      host = await openInstalledRemoteHttpHost({...installation, authenticate: () => principalId});
      server = createServer({key: certificates.key, cert: certificates.cert},
        (request, response) => host.handler(request, response));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connect({mode: 'remote', token: 'fixture-caller', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`});
    }

    const plan = await client.plan(inputOnlyProgram);
    assert.equal(plan.observation, 'static'); assert.equal(plan.provider_io, 0);
    assert.equal(plan.capabilities.static_plan, true); assert.equal(plan.capabilities.inspect, true);
    assert.deepEqual(plan.logical_map.steps.map(s => s.operator), ['values', null]);
    const receiving = plan.logical_map.steps[1];
    assert.deepEqual(receiving.key.occurrence, {kind: 'input_output', input_port_ordinal: 0});
    assert.deepEqual(receiving.ports.map(p => p.role), ['input', 'output']);
    for (const port of receiving.ports) {
      assert.deepEqual(port.source, {kind: 'stage_input', stage_ordinal: 1, input_port_ordinal: 0});
      assert.equal(port.can_sample, false);
    }
    assert.equal(receiving.ports[0].carrier_contract_cid, receiving.ports[1].carrier_contract_cid);
    assert.deepEqual(await client.plan(inputOnlyProgram), plan);
    await assert.rejects(client.plan(inputOnlyProgram, {maxNodes: 0}), {code: 'InvalidClientPlanRequest'});
    const invalid = structuredClone(inputOnlyProgram);
    invalid.stages[1].results.rows.fields = ['not_declared'];
    await assert.rejects(client.plan(invalid), {code: 'ClientProgramInvalidInput'});
    await drain(observation);
    assert.deepEqual(starts(records, physicalStarts), {physical: 0, source: 0, compute: 0, model: 0, effect: 0});

    // A positive execution witnesses the actual selected dispatcher observer.
    // Source/Model/Effect providers are not installed in this Values profile;
    // their zero counts do not claim acceptance of those other profiles.
    const run = await client.startSource(runSql, {format: 'sql',
      submissionRef: client.newSubmission({nonce: 'interactive-original'})});
    const state = await run.wait({signal: AbortSignal.timeout(15000)});
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), expectedRows);
    await drain(observation);
    const before = starts(records, physicalStarts);
    assert.equal(before.physical, 1); assert.equal(before.compute, 1);
    assert.equal(before.source, 0); assert.equal(before.model, 0); assert.equal(before.effect, 0);

    // Automatic first admission retained the original opaque compiler map.
    // Public read/attach below must never compile a replacement for that Run.
    const originalPlan = await run.plan();
    assert.deepEqual(originalPlan.run_ref, run.ref);
    assert.equal(originalPlan.plan_view.observation, 'static');
    assert.equal(originalPlan.plan_view.provider_io, 0);
    assert.equal(originalPlan.plan_view.logical_map.compiled_plan_cid,
      originalPlan.plan_view.compiled_plan_cid);
    assert.deepEqual(await run.plan(), originalPlan);
    const attached = await client.attach(run.ref);
    assert.deepEqual(await attached.plan(), originalPlan);
    await assert.rejects(run.plan({maxNodes: 0}), {code: 'InvalidRunPlanRequest'});

    for (let i = 0; i < 2; i++) {
      const view = await run.inspect();
      assert.deepEqual(view.run_ref, run.ref);
      assert.equal(view.run_state.run_id, state.run_id);
      assert.equal(view.run_state.status, 'succeeded');
      assert.equal(view.run_state.control_revision, state.control.revision);
      assert.equal(view.run_state.legacy_state.control.revision, state.control.revision);
      for (const field of ['pause_pending', 'expiry_pending', 'cleanup_pending']) {
        assert.equal(Object.hasOwn(view.run_state, field), false);
      }
      assert.equal(view.consistency, 'non_atomic'); assert.equal(view.observation_scope, 'owner_local');
      assert.equal(view.logical_map_cid, null);
      assert.deepEqual(view.available_operations, ['inspect']);
      assert.deepEqual(view.sample, {state: 'unavailable', reason: 'not_supported'});
      assert.equal(view.capabilities.inspect, true);
      assert.equal(view.capabilities.static_plan, true);
      for (const field of ['durable_control', 'cost_guard', 'execution_batch']) {
        assert.equal(view.capabilities[field], false);
      }
      assert.deepEqual(view.capabilities.sample_capture, []);
      assert.deepEqual(view.capabilities.full_intermediate_retention, []);
      assert.equal((await run.status()).control.revision, state.control.revision);
      assert.deepEqual(await run.result('answer').all(), expectedRows);
    }
    await assert.rejects(run.inspect({maxDepth: 0}), {code: 'InvalidRunInspectRequest'});
    await drain(observation);
    assert.deepEqual(starts(records, physicalStarts), before);
    t.diagnostic(JSON.stringify({entrance, readOnlyAdditionalStarts: {
      physical: 0, source: 0, compute: 0, model: 0, effect: 0}, witnessedStarts: before,
    observationStatus: observation.status(), originalRef: run.ref,
    profile: 'source-free-values', uninstalledProviders: ['source', 'model', 'effect']}));
    completed = true;
  });
}

const debugProgram = {
  version: 'actql/0.1', id: 'fixture.original_debug',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {n: {type: 'number', nullable: false}}, rows: [{n: 1}, {n: 2}]}, as: 'rows'},
    {from: 'rows', filter: {gt: [{field: 'n'}, {literal: 1}]}, as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['n']}}}],
  results: {main: {from: {stage: 'main', result: 'rows'}}},
};

async function inspectLivePause(run, minimumRevision, deadline) {
  let last;
  while (Date.now() < deadline) {
    last = await run.inspect();
    if (last.run_state.status === 'paused' && last.run_state.control_revision >= minimumRevision) return last;
    assert.ok(['preparing', 'running', 'paused'].includes(last.run_state.status), JSON.stringify(last.run_state));
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('No original live pause before deadline: ' + JSON.stringify(last?.run_state));
}

const readColdDebugOriginal = `
  const {connect} = await import(process.argv[1]);
  const {createHostObservationConnection} = await import(process.argv[2]);
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const {installation, ref, stepId, operation} = JSON.parse(Buffer.concat(chunks));
  const records = [];
  let physical = 0;
  installation.authorization.faultInjection = name => {
    if (name === 'physical_start_reserved') physical++;
  };
  const observation = createHostObservationConnection({deliver: record => records.push(record)});
  const client = await connect({mode: 'local', owner: 'local', durability: 'durable',
    installation: {...installation, observation}});
  let answer;
  try {
    const run = await client.attach(ref);
    answer = {pid: process.pid, ref: run.ref,
      sample: await run.sample({step: {by: 'id', step_id: stepId}, role: 'output'}),
      control: await run.lookupControlOperation(operation)};
  } finally {
    await client.close();
  }
  for (let turn = 0; turn < 512; turn++) {
    const status = observation.status();
    if (status.queued === 0 && status.active === 0 && status.activeSegments === 0) {
      process.stdout.write(JSON.stringify({...answer, physical,
        starts: records.filter(record => record.event === 'task_started' ||
          record.event === 'attempt_started' || record.event === 'application_observed').length,
        loss: status.loss}));
      break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
`;

function readDebugJournalCustody(directory, debugRef, normalRef) {
  const db = new DatabaseSync(join(directory, 'requests', 'client-requests.sqlite3'), {readOnly: true});
  const keys = [debugRef.runDefinitionCid, normalRef.runDefinitionCid];
  try {
    return {physical: db.prepare(`SELECT run_definition_cid, revision, physical_start_reserved,
      physical_close_confirmed FROM client_requests WHERE run_definition_cid IN (?, ?)
      ORDER BY run_definition_cid`).all(...keys),
    retained: db.prepare(`SELECT r.run_definition_cid, s.start_revision, COUNT(a.sample_ref_cid) AS samples
      FROM client_requests r LEFT JOIN client_relation_sample_starts s USING (run_definition_cid)
      LEFT JOIN client_relation_sample_adoptions a USING (run_definition_cid)
      WHERE r.run_definition_cid IN (?, ?) GROUP BY r.run_definition_cid ORDER BY r.run_definition_cid`)
      .all(...keys)};
  } finally {db.close();}
}

test('installed Local SDK Debug steps one original and a cold process reads its Sample and receipt', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-interactive-debug-public-'));
  const principalId = userInfo().username, keys = generateKeyPairSync('ed25519');
  const records = [];
  const observation = createHostObservationConnection({deliver: record => records.push(record)});
  let physicalStarts = 0, client, completed = false;
  let boundary = 'connect';
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'interactive-debug', entries: [
        {entry_id: 'execution', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []},
        {entry_id: 'output', outcome: 'allow',
          principal: {any_of: [principalId]}, connection: {any_of: ['actql-remote-host']},
          resource: {any_of: ['result/main']}, operation: {any_of: ['read']}, exclusions: []},
        {entry_id: 'run-control', outcome: 'allow',
          principal: {any_of: [principalId]}, connection: {any_of: ['actql-remote-host']},
          resource: {any_of: ['run']}, operation: {any_of: ['pause', 'read', 'resume']}, exclusions: []},
        {entry_id: 'sample-access', outcome: 'allow',
          principal: {any_of: [principalId]}, connection: {any_of: ['actql-remote-host']},
          resource: {any_of: ['sample']}, operation: {any_of: ['capture', 'read']}, exclusions: []},
      ]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(event, detail) {
      if (event === 'dispatch_failed') t.diagnostic(JSON.stringify({
        code: detail.code, primary: detail.primaryDiagnostic,
        issue: [detail.issueTag, detail.nestedIssueTag, detail.leafIssueTag],
      }));
    },
    faultInjection(name) {if (name === 'physical_start_reserved') physicalStarts++;},
  };
  t.after(async () => {
    await client?.close();
    if (completed) await rm(root, {recursive: true, force: true});
    else t.diagnostic(JSON.stringify({failedAt: boundary, physicalStarts, original: root}));
  });
  const installation = {directory: join(root, 'host'), authorization};
  client = await connect({mode: 'local', owner: 'local', durability: 'durable',
    installation: {...installation, observation}});
  const deadline = Date.now() + 15000;
  boundary = 'submit_debug';
  const run = await client.start(debugProgram, {executionProfile: 'debug',
    submissionRef: client.newSubmission({nonce: 'interactive-debug-original'})});
  boundary = 'observe_entry_pause';
  const entry = await inspectLivePause(run, 1, deadline);
  assert.deepEqual(entry.run_ref, run.ref);
  assert.equal(entry.run_state.stop_reason, 'entry');
  assert.equal(entry.run_state.boundary.position, 'before');
  assert.equal(physicalStarts, 0);
  boundary = 'read_original_plan';
  const plan = (await run.plan()).plan_view;
  assert.equal(entry.compiled_plan_cid, plan.compiled_plan_cid);
  assert.equal(entry.logical_map_cid, plan.logical_map.self_cid);
  const revision = entry.run_state.control_revision;
  const stale = await run.prepareResume({operationId: 'stale-entry', expectedRevision: revision - 1, until: 'step'});
  await assert.rejects(run.resume(stale), {code: 'ClientRunDebugEntryRevisionConflict', status: 409});
  assert.equal(physicalStarts, 0);
  const command = await run.prepareResume({operationId: 'first-step', expectedRevision: revision, until: 'step'});
  boundary = 'resume_first_step';
  const accepted = await run.resume(command);
  assert.equal(accepted.state, 'found');
  assert.equal(accepted.receipt.observed_state.control_revision, revision + 1);
  boundary = 'observe_step_pause';
  const paused = await inspectLivePause(run, revision + 2, deadline);
  assert.equal(paused.run_state.stop_reason, 'step');
  assert.equal(paused.run_state.boundary.position, 'before');
  const [produced, next] = plan.logical_map.steps;
  assert.equal(paused.run_state.boundary.step_id, next.step_id);
  assert.equal(physicalStarts, 1);
  boundary = 'read_sample';
  const sample = await run.sample({step: {by: 'id', step_id: produced.step_id}, role: 'output'});
  assert.equal(sample.state, 'available', JSON.stringify(sample));
  assert.equal(sample.capture.sampled_items, '2');
  assert.deepEqual(sample.data.rows.map(row => row[0].value), [1, 2]);
  boundary = 'continue_original';
  const attached = await client.attach(run.ref);
  const finish = await attached.prepareResume({operationId: 'continue-original',
    expectedRevision: paused.run_state.control_revision, until: 'terminal'});
  assert.equal((await attached.resume(finish)).state, 'found');
  assert.equal((await attached.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
  assert.deepEqual(await attached.result('main').all(), [{n: 2}]);
  assert.equal(physicalStarts, 1);
  const after = await attached.lookupControlOperation(accepted.receipt.operation_ref);
  assert.deepEqual(after, accepted);
  await drain(observation);
  assert.deepEqual(starts(records, physicalStarts), {physical: 1, source: 0, compute: 2, model: 0, effect: 0});

  boundary = 'submit_normal';
  const normal = await client.start(debugProgram, {
    submissionRef: client.newSubmission({nonce: 'interactive-normal-original'})});
  assert.notDeepEqual(normal.ref, run.ref);
  assert.equal((await normal.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
  assert.deepEqual(await normal.result('main').all(), [{n: 2}]);
  const normalPlan = (await normal.plan()).plan_view;
  const normalStep = normalPlan.logical_map.steps.find(step => step.ports.some(port =>
    port.role === 'output' && port.carrier === 'relation'));
  assert.ok(normalStep);
  assert.deepEqual(await normal.sample({step: {by: 'id', step_id: normalStep.step_id}, role: 'output'}),
    {state: 'unavailable', reason: 'not_retained'});
  await client.close();
  client = undefined;
  await drain(observation);

  const before = readDebugJournalCustody(installation.directory, run.ref, normal.ref);
  assert.equal(before.physical.length, 2);
  assert.ok(before.physical.every(row => row.physical_start_reserved === 1 && row.physical_close_confirmed === 1));
  const original = before.retained.find(row => row.run_definition_cid === run.ref.runDefinitionCid);
  const unselected = before.retained.find(row => row.run_definition_cid === normal.ref.runDefinitionCid);
  assert.ok(original.start_revision > 0 && original.samples > 0);
  assert.equal(unselected.start_revision, null);
  assert.equal(unselected.samples, 0);

  boundary = 'reopen_same_original';
  const cold = spawnSync(process.execPath, ['--input-type=module', '--eval', readColdDebugOriginal,
    new URL('../../packages/node/index.mjs', import.meta.url).href,
    new URL('../../packages/local-node/adapters/host-common/observation.mjs', import.meta.url).href], {
    input: JSON.stringify({installation, ref: run.ref, stepId: produced.step_id,
      operation: accepted.receipt.operation_ref}),
    encoding: 'utf8', timeout: 15000, maxBuffer: 128 * 1024,
  });
  assert.equal(cold.status, 0, cold.error?.code ?? cold.stderr);
  const observed = JSON.parse(cold.stdout);
  assert.notEqual(observed.pid, process.pid);
  assert.deepEqual(observed.ref, run.ref);
  assert.deepEqual(observed.sample, sample);
  assert.deepEqual(observed.control, accepted);
  assert.deepEqual({physical: observed.physical, starts: observed.starts, loss: observed.loss},
    {physical: 0, starts: 0, loss: {}});
  assert.deepEqual(readDebugJournalCustody(installation.directory, run.ref, normal.ref), before);
  t.diagnostic(JSON.stringify({firstClose: 'returned', detachedProcess: true, debugSamples: original.samples,
    normalSamples: unselected.samples, coldPhysicalStarts: observed.physical, coldTaskStarts: observed.starts}));
  completed = true;
});
