import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import type {Server} from 'node:http';
import {readFile} from 'node:fs/promises';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {fundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {installClientRunInspect} from './client-run-inspect.mjs';
import {prepareClientHostRequest} from '../../packages/client-wire/index.mjs';
import {cid, ref, legacyState, paused as fixturePaused} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';

// This independent semantic fixture tests routing/disclosure, not actual
// compiler/runtime provenance or measured Provider execution counts.
type Installation = Parameters<typeof installClientRunInspect<object, object | undefined, object | undefined, typeof legacyState>>[0];
type InspectRequest = Parameters<Installation['authorize']>[0];
type Original = ReturnType<Installation['lookupOriginal']>;
type HostOptions = Parameters<typeof createNodeInProcessClientHost>[0];

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
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []} satisfies InspectRequest['connection'];
const request = () => ({connection, ref: structuredClone(ref), principalId: 'viewer', maxWireBytes: 65536,
  maxNodes: 10000, maxDepth: 64});
const consumeView = <Value,>(value: Value) => value;
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'inspect-test', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

test('Run Inspect request owns its original ref before asynchronous authorization', () => {
  const original = request();
  const {principalId: _principalId, ...body} = original;
  const prepared = prepareClientHostRequest('inspect-run', body);
  original.ref.runDefinitionCid = cid('0');
  assert(prepared && typeof prepared.body === 'object' && prepared.body !== null && 'ref' in prepared.body);
  assert.deepEqual(prepared.body.ref, ref);
});

test('Run Inspect projects existing original evidence and rechecks access after Owner reads', async () => {
  const definition = {}, prepared = {}, authorization = {};
  const evidence = {prepared: 'original-prepared', authorization: 'original-authorization'};
  let allowed = true, reads = 0, projections = 0;
  const observations = () => ({owners: [{owner: 'run', kind: 'observed',
    snapshot: {value: legacyState}}], revisionVector: [{owner: {kind: 'run' as const,
      scopeCid: ref.authorityScopeCid, streamCid: ref.runDefinitionCid}, snapshotCid: cid('7')}]});
  const install = (changes: Partial<Installation>) => installClientRunInspect({authorize: () => allowed,
    authorizeCurrent: () => allowed,
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
  assert.deepEqual(await install({})(request(), consumeView), view());
  assert.equal(reads, 1); assert.equal(projections, 1);
  allowed = false;
  await assert.rejects(install({})(request(), consumeView), {code: 'RunObservationAccessDenied'});
  assert.equal(reads, 1);
  allowed = true;
  await assert.rejects(install({observeOwners: async () => {allowed = false; return observations();}})(request(), consumeView),
    {code: 'RunObservationAccessDenied'});
  assert.equal(projections, 1);
});

test('Run Inspect enters its sink under the same synchronous current decision', async () => {
  let account: boolean | PromiseLike<boolean> = true;
  let issued: Parameters<Installation['authorize']>[1] | undefined;
  let staleAtProjection = false, consumed = 0, finished = false;
  const held = Promise.withResolvers<void>();
  const inspect = installClientRunInspect({
    authorize: async (selected, operation) => {
      assert.deepEqual(operation, {principalId: 'viewer', indexKey: ref, purpose: 'inspect'});
      assert.equal(operation.indexKey, selected.ref);
      assert(Object.isFrozen(operation));
      issued = operation;
      return true;
    },
    authorizeCurrent: (selected, operation) => {
      assert.equal(operation, issued);
      assert.equal(operation.indexKey, selected.ref);
      return account;
    },
    lookupOriginal: () => ({runDefinition: {}, runAdmissionEvidence: {prepared: 'p', authorization: 'a'}}),
    observeOwners: async () => ({owners: [{owner: 'run', kind: 'observed', snapshot: {value: legacyState}}],
      revisionVector: [{owner: {kind: 'run', scopeCid: ref.authorityScopeCid, streamCid: ref.runDefinitionCid},
        snapshotCid: cid('7')}]}),
    control: {admitRunEvidence() {}, readCurrentClientRunView() {
      if (staleAtProjection) account = false;
      return JSON.stringify(view());
    }},
  });
  const selected = request();
  staleAtProjection = true;
  await assert.rejects(inspect(selected, () => {consumed++;}), {code: 'RunObservationAccessDenied'});
  assert.equal(consumed, 0);
  staleAtProjection = false;
  account = Promise.reject(new Error('asynchronous current decision'));
  await assert.rejects(inspect(selected, () => {consumed++;}), {code: 'RunObservationAccessDenied'});
  assert.equal(consumed, 0);
  account = true;
  const entered = Promise.withResolvers<void>();
  const delivery = inspect(selected, async value => {
    consumed++;
    assert.deepEqual(value, view());
    entered.resolve();
    await held.promise;
    return 'consumed';
  }).then(result => {finished = true; return result;});
  await entered.promise;
  assert.equal(consumed, 1);
  assert.equal(finished, false);
  held.resolve();
  assert.equal(await delivery, 'consumed');
});

test('absent original policy evidence and unavailable observations do not trigger preparation', async () => {
  let reads = 0, projects = 0;
  const control = {admitRunEvidence() {throw new Error('unexpected evidence');},
    readCurrentClientRunView() {projects++; throw new Error('unexpected project');}};
  const install = (original: Original) => installClientRunInspect({authorize: () => true, authorizeCurrent: () => true, control,
    lookupOriginal: () => original,
    observeOwners: async () => {reads++; return {owners: [], revisionVector: []};}});
  await assert.rejects(install(undefined)(request(), consumeView), {code: 'RunObservationAccessDenied'});
  await assert.rejects(install({runDefinition: {}})(request(), consumeView), {code: 'ClientOperationUnavailable'});
  assert.equal(reads, 0);
  await assert.rejects(install({runDefinition: {}, runAdmissionEvidence: {prepared: 'p', authorization: 'a'}})(request(), consumeView),
    {code: 'ClientOperationUnavailable'});
  assert.equal(reads, 1); assert.equal(projects, 0);
});

test('Run Inspect sends funded scalars to Common and rechecks the same original park before delivery', async () => {
  let park: NonNullable<ReturnType<NonNullable<Installation['observeDebugPause']>>> = {
    revision: 17, runRef: ref, ttlPolicy: 'original_debug_entry_deadline',
    logicalMapCid: cid('8'), startRevision: 3, controlRevision: 2,
    committedGeneration: 6, completedStepId: cid('a'), nextStepId: cid('b'),
    pausedAt: Date.parse('2026-10-11T00:05:00.000Z'), expiresAt: Date.parse('2026-10-11T00:10:00.000Z')};
  const workspace: {failure?: unknown} = {};
  const closeFailure = () => workspace.failure;
  let active = false, probes = 0, consumed = 0, changePark = false;
  let resumeAllowed = true, revokeAfterProjection = false;
  const out = view(), selected = request();
  const paused = {...view(), logical_map_cid: cid('8'), run_state: {...fixturePaused, control_revision: 17}};
  const inspect = installClientRunInspect({authorize: () => true, authorizeCurrent: () => true,
    authorizeResume: () => resumeAllowed,
    lookupOriginal: () => ({runDefinition: {}, runAdmissionEvidence: {prepared: 'p', authorization: 'a'}}),
    observeOwners: async () => ({owners: [{owner: 'run', kind: 'observed', snapshot: {value: legacyState}}],
      revisionVector: [{owner: {kind: 'run', scopeCid: ref.authorityScopeCid, streamCid: ref.runDefinitionCid},
        snapshotCid: cid('7')}]}),
    control: {admitRunEvidence() {}, readCurrentClientRunView(_run, _p, _a, actual, state, snapshot, _limits, packet) {
      assert.deepEqual(actual, ref); assert.equal(state, legacyState); assert.equal(snapshot, cid('7'));
      if (packet === '') return JSON.stringify(out);
      assert(typeof packet === 'string');
      assert(active);
      assert.deepEqual(JSON.parse(packet), {kind: 'logical_step', run_ref: ref, revision: 17, logical_map_cid: cid('8'),
        paused_at: '2026-10-11T00:05:00.000Z', expires_at: '2026-10-11T00:10:00.000Z',
        ttl_policy: 'original_debug_entry_deadline', resume_available: resumeAllowed, start_revision: 3, control_revision: 2,
        committed_generation: 6, completed_step_id: cid('a'), next_step_id: cid('b')});
      const available = resumeAllowed ? ['inspect', 'resume'] : ['inspect'];
      if (revokeAfterProjection) resumeAllowed = false;
      return JSON.stringify({...paused, available_operations: available});
    }},
    observeDebugPause(request, current, canResume) {
      assert.deepEqual(request.ref, ref); assert.equal(current(), true);
      probes++;
      if (probes === 12 && changePark) return undefined;
      return Object.freeze({...park, ...(canResume === undefined ? {} : {resumeAvailable: canResume()})});
    },
    readWorkspace: {
      begin(request) {assert.equal(request, selected); assert(!active); active = true;},
      metadata(request, bytes) {
        assert.equal(request, selected); assert(active);
        assert.equal(bytes, 2 * (2112 + 6 * (ref.namespaceId.length + legacyState.run_id.length)));
      },
      close(request, error) {assert.equal(request, selected); assert(active); active = false; workspace.failure = error;},
    },
  });
  const read = () => inspect(selected, value => {assert(active); consumed++; return value;});
  assert.deepEqual(await read(), {...paused, available_operations: ['inspect', 'resume']});
  assert.equal(probes, 3);
  assert.equal(closeFailure(), undefined);
  resumeAllowed = false;
  assert.deepEqual(await read(), {...paused, available_operations: ['inspect']});
  resumeAllowed = true; revokeAfterProjection = true;
  await assert.rejects(read(), {code: 'ClientOperationUnavailable'});
  assert.equal(resumeAllowed, false);
  revokeAfterProjection = false;
  changePark = true;
  await assert.rejects(read(), {code: 'ClientOperationUnavailable'});
  const failure = closeFailure();
  assert(failure instanceof Error && 'code' in failure);
  assert.equal(failure.code, 'ClientOperationUnavailable');
  assert.equal(consumed, 2);
  assert.equal(active, false);
  park = {revision: 17, runRef: park.runRef, pausedAt: park.pausedAt, expiresAt: park.expiresAt};
  assert.deepEqual(await inspect(selected, consumeView), out);
});

for (const transport of ['local', 'http-loopback']) {
  test(`${transport}: SDK inspect remains original-Run read-only and refuses substituted observations`, async t => {
    let client: Awaited<ReturnType<typeof connect>> | undefined;
    let server: Server | undefined;
    let corrupt = false, inspecting = false;
    const calls = {attach: 0, inspect: 0, submit: 0, inspectReplies: 0};
    const operations: Pick<HostOptions, 'authorizeConnection' | 'negotiate' | 'attach' | 'inspectRun' | 'submit'> = {
      authorizeConnection: () => true, negotiate: () => profile,
      attach(value) {calls.attach++; return {ref: value.ref, durability: 'volatile', revision: 17};},
      async inspectRun(value, consume) {
        calls.inspect++; assert.deepEqual(value.ref, ref);
        const answer = view();
        if (corrupt) answer.run_ref.runDefinitionCid = cid('0');
        inspecting = true;
        try {return await consume(answer);}
        finally {inspecting = false;}
      }, submit() {calls.submit++; throw new Error('unexpected submit');}};
    t.after(async () => {
      try {await client?.close();}
      finally {
        const activeServer = server;
        if (activeServer !== undefined) {
          activeServer.closeAllConnections();
          await new Promise<void>((resolve, reject) => activeServer.close(error => error ? reject(error) : resolve()));
        }
      }
    });
    if (transport === 'local') {
      client = await connectInProcess({mode: 'local', owner: 'local'},
        createNodeInProcessClientHost({...operations, authenticate: () => 'inspect-test', maxRowBytes: 1024}));
    } else {
      const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
      const wire = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
      const body = JSON.parse(wire);
      const environment = moon.clientProgramCheckEnvironment(wire.trimEnd(),
        body.evidence_bundle_cid, false, false, true, true, false, false, false);
      assert.ok(environment);
      // The generated declarations describe fixed arities for unused Model
      // entry points. The fixture verifies the installed preparation port.
      type Runtime = Parameters<typeof fundedClientPreparation>[1]['moon'];
      const runtime = moon as unknown as Runtime;
      const {prepareRequest} = await fundedClientPreparation(t, {moon: runtime, environment, http: true});
      type FixtureBody = Parameters<typeof prepareRequest>[1];
      const activeServer = createServer(createClientHttpHandler({...operations,
        authenticate: () => 'inspect-test', loopbackHttp: true,
        prepareRequest(operation, body) {
          // These read-only operations only use the fixture's Request lifetime.
          assert(operation === 'connect' || operation === 'attach' || operation === 'inspect-run');
          const original = prepareRequest(operation, body as FixtureBody);
          return {...original, bindRequest: derived => original.bindRequest(derived as FixtureBody),
            beforeReply() {
              original.beforeReply();
              if (operation === 'inspect-run') {
                assert.equal(inspecting, true, 'the original Inspect handler remains active at HTTP egress');
                calls.inspectReplies++;
              }
            }};
        }}));
      server = activeServer;
      await new Promise<void>(resolve => activeServer.listen(0, '127.0.0.1', resolve));
      const address = activeServer.address();
      assert(address !== null && typeof address === 'object');
      client = await connect({mode: 'local', owner: 'local', token: 'fixture',
        endpoint: `http://127.0.0.1:${address.port}/`});
    }
    const run = await client.attach(ref);
    const first = await run.inspect();
    assert.deepEqual(first, view()); assert.equal(Object.isFrozen(first), true);
    assert.equal(Object.hasOwn(first.run_state, 'cleanup_pending'), false);
    await assert.rejects(run.inspect({maxWireBytes: 0}), {code: 'InvalidRunInspectRequest'});
    assert.equal(calls.inspect, 1);
    corrupt = true;
    await assert.rejects(run.inspect(), transport === 'http-loopback'
      ? {code: 'ClientHostFailure', status: 500} : {code: 'InvalidClientHostRunView'});
    assert.equal(calls.submit, 0); assert.equal(calls.attach, 1);
    assert.equal(calls.inspectReplies, transport === 'http-loopback' ? 1 : 0);
  });
}
