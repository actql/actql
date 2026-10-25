import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installClientStaticPlan} from './client-interactive-plan.mjs';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {validClientBody, prepareClientHostRequest} from '../../packages/client-wire/index.mjs';
import {mapBody, planCid, cid} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

// This fixed semantic mock proves routing, not a compiler-issued public view.
const mockView = () => ({version: 'actql-plan-view/0.1', compiled_plan_cid: planCid,
  logical_map: {...structuredClone(mapBody), self_cid: `sha256:${createHash('sha256')
    .update(canonicalText(mapBody)).digest('hex')}`},
  observation: 'static', provider_io: 0,
  quantities: [{kind: 'unknown', unit: 'work', reason: 'not_observed'}],
  capabilities: {static_plan: true, inspect: true, durable_control: false,
    sample_capture: [], full_intermediate_retention: [], cost_guard: false,
    execution_batch: false, policy_revision_cid: cid('9')}});
const profile = mode => ({version: 'actql-client-host/0.1', mode, owner: mode,
  durability: 'volatile', scopeRef: 'plan-test', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}});
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};
const request = {connection, kind: 'program', input: {stages: []}, parameters: null,
  maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64};

for (const deferred of [false, true]) {
  test(`static plan keeps its original pending request through funded preparation (${deferred ? 'deferred' : 'direct'})`, async t => {
    const registry = createEmbeddedHostRegistry(() => true);
    const host = {}, installation = {}, environment = {}, checkedProgram = {};
    const aliases = [];
    let probes = 0, compilations = 0, current = true;
    const original = value => registry.originalSourceRequest(host, installation, host, value);
    const bindOwnedRequest = (parent, derived) =>
      registry.bindSourceRequest(host, installation, host, parent, derived);
    const moon = {
      clientProgramPrepareEffectFreeWithParameters() {return {prepared: checkedProgram};},
      clientProgramPreparationReady: outcome => outcome.prepared,
      clientProgramPreparationIssue() {}, clientProgramPreparationIssueCode() {},
      clientProgramRequiresTaskCompilation: () => false,
    };
    const prepare = installNodeClientProgramPreparation({moon, environment,
      getFundedPreparation(value, selected) {
        assert.strictEqual(selected, environment);
        assert.notEqual(original(value), value, 'Ingress owns its admitted derivative');
        assert.throws(() => original({...value}), {code: 'InstalledHostPreparationChanged'});
        aliases.push(value); probes++;
        // A static read has no submitted producer, so ordinary preparation
        // continues without claiming that it obtained managed Run funding.
        return undefined;
      }});
    const plan = installClientStaticPlan({moon, prepare, authorize: () => current,
      control: {readCheckedClientStaticPlan(value) {
        assert.strictEqual(value, checkedProgram); compilations++;
        return JSON.stringify(mockView());
      }}});
    const ports = {authenticate: () => 'plan-test', authorizeConnection: () => current,
      negotiate: () => profile('local'), maxRowBytes: 65536, bindOwnedRequest};
    const ingress = createNodeInProcessClientHost({...ports, plan});
    host.port = deferred ? createNodeInProcessClientHost({...ports,
      async performInstalledRequest(operation, body, signal) {
        await Promise.resolve();
        return ingress.perform(operation, body, signal);
      }}) : ingress;
    Object.assign(host, {dispatchOwner: {async drain() {}}, retireTerminalEffects() {},
      journal: {async close() {}}, store: {async close() {}}});
    registry.registerPreparation(host, installation, host);
    const client = await registry.connect('static-lineage', {}, async () => host,
      {mode: 'local', owner: 'local'}, host);
    t.after(() => client.close());
    assert.deepEqual(await client.plan({stages: []}), mockView());
    assert.equal(probes, 1); assert.equal(compilations, 1);
    for (const alias of aliases) assert.throws(() => original(alias),
      {code: 'InstalledHostPreparationChanged'});
    current = false;
    await assert.rejects(client.plan({stages: []}), {code: 'ClientConnectionDenied'});
    assert.equal(probes, 1); assert.equal(compilations, 1);
  });
}

test('static request owns the original input without a fabricated submission identity', () => {
  const prepared = prepareClientHostRequest('plan', request);
  assert.ok(prepared);
  assert.notEqual(prepared.body.input, request.input);
  assert.equal(Object.hasOwn(prepared.body, 'requestId'), false);
  for (const change of [{requestId: 'fake'}, {maxWireBytes: 65537},
    {maxNodes: 0}, {maxDepth: 65}, {parameters: []}]) {
    assert.equal(validClientBody('plan', {...request, ...change}), false);
  }
});

test('static service uses the same prepared owner and rechecks current access', async () => {
  const prepared = {}, reads = [], owned = [];
  let allowed = true;
  const prepare = Object.assign(async () => prepared, {
    assertOwned: value => {assert.equal(value, prepared); owned.push(value);},
    kindOf: () => 'effect_free',
  });
  const service = installClientStaticPlan({prepare, authorize: () => allowed,
    moon: {clientProgramRequiresTaskCompilation: value => {
      assert.equal(value, prepared); return true;
    }},
    control: {readCheckedClientStaticPlan(value, kind, limits) {
      assert.equal(value, prepared); assert.equal(kind, 'tasks');
      assert.equal(limits.maxWireBytes, 65536); reads.push(value);
      return JSON.stringify(mockView());
    }}});
  assert.deepEqual(await service(request), mockView());
  assert.equal(owned.length, 1); assert.equal(reads.length, 1);
  allowed = false;
  await assert.rejects(service(request), {code: 'ClientConnectionDenied'});
  assert.equal(reads.length, 1);
  allowed = true;
  const revoked = installClientStaticPlan({prepare,
    authorize: () => allowed,
    moon: {clientProgramRequiresTaskCompilation: () => false},
    control: {readCheckedClientStaticPlan() {allowed = false; return JSON.stringify(mockView());}}});
  await assert.rejects(revoked(request), {code: 'ClientConnectionDenied'});
});

for (const mode of ['local', 'http-loopback']) {
  test(`${mode}: SDK routes a static read without submit and rejects map CID substitution`, async t => {
    let reads = 0, submits = 0, corrupt = false, server;
    const operations = {authorizeConnection: () => true, negotiate: () => profile('local'),
      plan(value) {
        assert.equal(Object.hasOwn(value, 'requestId'), false);
        assert.equal(value.kind, 'aql'); reads++;
        const view = mockView();
        if (corrupt) view.logical_map.self_cid = cid('0');
        return view;
      }, submit() {submits++; throw new Error('unexpected submit');}};
    let client;
    t.after(async () => {await client?.close(); if (server) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }});
    if (mode === 'local') {
      client = await connectInProcess({mode: 'local', owner: 'local'},
        createNodeInProcessClientHost({...operations, authenticate: () => 'plan-test',
          maxRowBytes: 1024}));
    } else {
      server = createServer(createClientHttpHandler({...operations,
        authenticate: () => 'plan-test', loopbackHttp: true}));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connect({mode: 'local', owner: 'local', token: 'fixture',
        endpoint: `http://127.0.0.1:${server.address().port}/`});
    }
    assert.deepEqual(await client.plan('SELECT 1 AS n', {format: 'sql'}), mockView());
    assert.equal(reads, 1); assert.equal(submits, 0);
    corrupt = true;
    await assert.rejects(client.plan('SELECT 1 AS n', {format: 'sql'}),
      {code: 'InvalidClientHostPlanView'});
    assert.equal(reads, 2); assert.equal(submits, 0);
  });
}

test('static Effect service rejects a component-only response and post-read current revocation', async () => {
  const {effectfulStaticPlan} = await import('../../scripts/fixtures/effectful-static-plan-vectors.mjs');
  const original = {}, prepare = Object.assign(() => original, {
    kindOf: () => 'effectful', assertOwned: actual => assert.equal(actual, original),
  });
  let current = true, componentOnly = true;
  const service = installClientStaticPlan({prepare, authorize: () => current,
    moon: {clientProgramRequiresTaskCompilation() {assert.fail('wrong original type');}},
    control: {readCheckedClientStaticPlan(actual, kind) {
      assert.equal(actual, original); assert.equal(kind, 'effects');
      if (componentOnly) return JSON.stringify(effectfulStaticPlan.computation.plan_view);
      current = false;
      return JSON.stringify(effectfulStaticPlan);
    }}});
  await assert.rejects(service(request), {message: 'InvalidClientHostPlanView'});
  componentOnly = false;
  await assert.rejects(service(request), {code: 'ClientConnectionDenied'});
});
