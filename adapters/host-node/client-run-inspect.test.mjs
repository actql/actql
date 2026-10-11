import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installClientRunInspect} from './client-run-inspect.mjs';
import {prepareClientHostRequest} from '../../packages/client-wire/index.mjs';
import {cid, ref, legacyState} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';

// This independent semantic fixture tests routing/disclosure, not actual
// compiler/runtime provenance or measured Provider execution counts.
const view = () => ({version: 'actql-run-view/0.1', run_ref: structuredClone(ref),
  run_state: {version: 'actql-controlled-run-state/0.1',
    run_id: 'original', status: 'running', updated_at: legacyState.updated_at,
    control_revision: 17, legacy_state: structuredClone(legacyState)},
  compiled_plan_cid: cid('2'), logical_map_cid: null,
  consistency: 'non_atomic', observation_scope: 'owner_local',
  components: [{owner: 'run', revision: null, state: 'observed', provenance_cid: cid('7')}],
  quantities: [], sample: {state: 'unavailable', reason: 'not_supported'},
  available_operations: ['inspect'], capabilities: {static_plan: true, inspect: true,
    durable_control: false, sample_capture: [], full_intermediate_retention: [],
    cost_guard: false, execution_batch: false, policy_revision_cid: cid('4')}});
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};
const request = () => ({connection, ref: structuredClone(ref), maxWireBytes: 65536,
  maxNodes: 10000, maxDepth: 64});
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'inspect-test', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

test('Run Inspect request owns its original ref before asynchronous authorization', () => {
  const original = request();
  const prepared = prepareClientHostRequest('inspect-run', original);
  original.ref.runDefinitionCid = cid('0');
  assert.deepEqual(prepared.body.ref, ref);
});

test('Run Inspect projects existing original evidence and rechecks access after Owner reads', async () => {
  const definition = {}, prepared = {}, authorization = {};
  const evidence = {prepared: 'original-prepared', authorization: 'original-authorization'};
  let allowed = true, reads = 0, projections = 0;
  const observations = () => ({owners: [{owner: 'run', kind: 'observed',
    snapshot: {value: legacyState}}], revisionVector: [{owner: {kind: 'run',
      scopeCid: ref.authorityScopeCid, streamCid: ref.runDefinitionCid}, snapshotCid: cid('7')}]});
  const install = changes => installClientRunInspect({authorize: () => allowed,
    lookupOriginal: () => ({runDefinition: definition, runAdmissionEvidence: evidence}),
    observeOwners: async () => {reads++; return observations();},
    control: {admitRunEvidence(kind, wire) {
      assert.equal(wire, kind === 'prepared_invocation' ? evidence.prepared : evidence.authorization);
      return kind === 'prepared_invocation' ? prepared : authorization;
    }, readCurrentClientRunView(run, preparation, authority, observedRef, state, snapshot) {
      projections++; assert.equal(run, definition); assert.equal(preparation, prepared);
      assert.equal(authority, authorization); assert.deepEqual(observedRef, ref);
      assert.deepEqual(state, legacyState); assert.equal(snapshot, cid('7'));
      return JSON.stringify(view());
    }}, ...changes});
  assert.deepEqual(await install({})(request()), view());
  assert.equal(reads, 1); assert.equal(projections, 1);
  allowed = false;
  await assert.rejects(install({})(request()), {code: 'RunObservationAccessDenied'});
  assert.equal(reads, 1);
  allowed = true;
  await assert.rejects(install({observeOwners: async () => {allowed = false; return observations();}})(request()),
    {code: 'RunObservationAccessDenied'});
  assert.equal(projections, 1);
});

test('absent original policy evidence and unavailable observations do not trigger preparation', async () => {
  let reads = 0, projects = 0;
  const control = {admitRunEvidence() {throw new Error('unexpected evidence');},
    readCurrentClientRunView() {projects++; throw new Error('unexpected project');}};
  const install = original => installClientRunInspect({authorize: () => true, control,
    lookupOriginal: () => original,
    observeOwners: async () => {reads++; return {owners: [], revisionVector: []};}});
  await assert.rejects(install(undefined)(request()), {code: 'RunObservationAccessDenied'});
  await assert.rejects(install({runAdmissionEvidence: undefined})(request()), {code: 'ClientOperationUnavailable'});
  assert.equal(reads, 0);
  await assert.rejects(install({runAdmissionEvidence: {prepared: 'p', authorization: 'a'}})(request()),
    {code: 'ClientOperationUnavailable'});
  assert.equal(reads, 1); assert.equal(projects, 0);
});

for (const transport of ['local', 'http-loopback']) {
  test(`${transport}: SDK inspect remains original-Run read-only and refuses substituted observations`, async t => {
    let client, server, corrupt = false;
    const calls = {attach: 0, inspect: 0, submit: 0};
    const operations = {authorizeConnection: () => true, negotiate: () => profile,
      attach(value) {calls.attach++; return {ref: value.ref, durability: 'volatile', revision: 17};},
      inspectRun(value) {
        calls.inspect++; assert.deepEqual(value.ref, ref);
        const answer = view();
        if (corrupt) answer.run_ref.runDefinitionCid = cid('0');
        return answer;
      }, submit() {calls.submit++; throw new Error('unexpected submit');}};
    t.after(async () => {await client?.close(); if (server) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }});
    if (transport === 'local') {
      client = await connectInProcess({mode: 'local', owner: 'local'},
        createNodeInProcessClientHost({...operations, authenticate: () => 'inspect-test', maxRowBytes: 1024}));
    } else {
      server = createServer(createClientHttpHandler({...operations,
        authenticate: () => 'inspect-test', loopbackHttp: true}));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connect({mode: 'local', owner: 'local', token: 'fixture',
        endpoint: `http://127.0.0.1:${server.address().port}/`});
    }
    const run = await client.attach(ref);
    const first = await run.inspect();
    assert.deepEqual(first, view()); assert.equal(Object.isFrozen(first), true);
    assert.equal(Object.hasOwn(first.run_state, 'cleanup_pending'), false);
    await assert.rejects(run.inspect({maxWireBytes: 0}), {code: 'InvalidRunInspectRequest'});
    assert.equal(calls.inspect, 1);
    corrupt = true;
    await assert.rejects(run.inspect(), {code: 'InvalidClientHostRunView'});
    assert.equal(calls.submit, 0); assert.equal(calls.attach, 1);
  });
}
