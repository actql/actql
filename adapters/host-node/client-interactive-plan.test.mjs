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
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';

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

test('public static plan admits its original snapshot before options and returns the same read producer', async t => {
  const events = [], receipt = {}, admitted = new WeakSet();
  let captured, bound, finished = 0;
  const preparation = {
    beforeSourceSnapshot(kind, input, options, originalConnection) {
      events.push('admit');
      assert.equal(kind, 'aql'); assert.equal(input, 'SELECT 1 AS n');
      assert.equal(originalConnection.owner, 'local');
      return receipt;
    },
    assertSourceSnapshotCurrent(value) {assert.strictEqual(value, receipt);},
    captureSourceSnapshot(value, original, snapshot) {
      assert.strictEqual(value, receipt); events.push('snapshot');
      captured = snapshot(original); return captured;
    },
    bindSourceSnapshot(value, body) {
      assert.strictEqual(value, receipt); assert.strictEqual(body, captured);
      assert.equal(Object.isFrozen(body), true); bound = body;
    },
    bindSourceRequest(value, body, actual) {
      assert.strictEqual(value, receipt); assert.strictEqual(body, bound);
      admitted.add(actual);
    },
    finishSourceProducer(value, terminal) {
      assert.strictEqual(value, receipt); assert.equal(terminal, 'returned');
      finished++; events.push('return');
    },
    publishSourceSnapshot() {assert.fail('Static reads have no submission publication');},
    intentCid() {assert.fail('Static reads issue no intent');},
  };
  const ingress = createNodeInProcessClientHost({authenticate: () => 'plan-test',
    authorizeConnection: () => true, negotiate: () => profile('local'),
    maxRowBytes: 1024,
    bindOwnedRequest(parent, derived) {
      assert.equal(admitted.has(parent), true);
      admitted.add(derived);
    },
    plan(actual) {
      assert.equal(admitted.has(actual), true, 'The original must precede funded preparation');
      events.push('plan'); return mockView();
    }, submit() {assert.fail('Static reads create no Run');}});
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    Object.freeze({...ingress, [sourcePreparationPort]: Object.freeze(preparation)}));
  t.after(() => client.close());
  const options = {get format() {events.push('option'); return 'sql';}};
  assert.deepEqual(await client.plan('SELECT 1 AS n', options), mockView());
  assert.equal(events[0], 'admit'); assert.equal(finished, 1);
  assert.equal(events.indexOf('snapshot') < events.indexOf('plan'), true);
  assert.equal(events.at(-1), 'return');
});

test('static plan admission and pending return preserve original failure and cleanup responsibility', async () => {
  const primary = new Error('original static reader failure');
  const cleanup = new Error('original static return failure');
  for (const mode of ['admission', 'read', 'return']) {
    const receipt = {}, events = [];
    let optionsRead = 0, returns = 0;
    const preparation = {
      beforeSourceSnapshot() {
        events.push('admit'); if (mode === 'admission') throw primary;
        return receipt;
      },
      assertSourceSnapshotCurrent(value) {assert.strictEqual(value, receipt);},
      captureSourceSnapshot(value, original, snapshot) {
        assert.strictEqual(value, receipt); return snapshot(original);
      },
      bindSourceSnapshot() {}, bindSourceRequest() {},
      finishSourceProducer(value, terminal) {
        assert.strictEqual(value, receipt); returns++; events.push('return');
        assert.equal(terminal, mode === 'read' ? 'failed' : 'returned');
        if (returns === 1) throw cleanup;
      },
      intentCid() {assert.fail('No intent for a read');},
      publishSourceSnapshot() {assert.fail('No submission publication');},
    };
    const port = {[sourcePreparationPort]: preparation,
      async perform(operation) {
        if (operation === 'connect') return profile('local');
        assert.equal(operation, 'plan'); events.push('read');
        if (mode === 'read') throw primary;
        return mockView();
      },
      close() {events.push('close');},
    };
    const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
    try {
      await assert.rejects(client.plan('SELECT 1 AS n', {
        get format() {optionsRead++; return 'sql';},
      }), error => {
        if (mode === 'admission') return error === primary;
        if (mode === 'read') return error.code === 'ClientTransportUnknown' && error.cause === primary;
        return error.code === 'ClientCleanupPending' && error.cause === cleanup &&
          error.cleanupPending === true && !Object.hasOwn(error, 'execution');
      });
      assert.equal(optionsRead, mode === 'admission' ? 0 : 1);
      assert.equal(returns, mode === 'admission' ? 0 : 1);
      assert.equal(events.includes('read'), mode !== 'admission');
    } finally {await client.close();}
    assert.equal(returns, mode === 'admission' ? 0 : 2);
    assert.equal(events.at(-1), 'close');
  }
});

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
        // Explicit original preparation port; this fixture issues no Resource
        // admission or public Run and cannot claim normal static-plan funding.
        return {kind:'effect_free',prepared:checkedProgram,
          originalInputs:{environment:selected,parameters:undefined}};
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
        authenticate: () => 'plan-test', loopbackHttp: true,
        // Explicit request-lifetime ports for this fixed wire mock only.
        // The ordinary installed Request owns real Resource admission.
        prepareRequest: (_operation, body) => ({body,
          bindRequest() {}, beforeReply() {}, finish() {}})}));
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

test('installed static service reads its held original and never re-enters raw preparation or compilation', async () => {
  let current = true, reads = 0;
  const unreachable = () => assert.fail('No second preparation/compiler for an original read');
  const prepare = Object.assign(unreachable, {assertOwned: unreachable, kindOf: unreachable});
  const service = installClientStaticPlan({moon: {clientProgramRequiresTaskCompilation: unreachable},
    control: {readCheckedClientStaticPlan: unreachable}, prepare,
    authorize: () => current,
    async readOriginal(actual) {assert.strictEqual(actual, request); reads++; return JSON.stringify(mockView());}});
  assert.deepEqual(await service(request), mockView()); assert.equal(reads, 1);
  current = false;
  await assert.rejects(service(request), {code: 'ClientConnectionDenied'});
  assert.equal(reads, 1);
  current = true;
  const revoked = installClientStaticPlan({moon: {clientProgramRequiresTaskCompilation: unreachable},
    control: {readCheckedClientStaticPlan: unreachable}, prepare, authorize: () => current,
    async readOriginal() {current = false; return JSON.stringify(mockView());}});
  await assert.rejects(revoked(request), {code: 'ClientConnectionDenied'});
});
