import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
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
