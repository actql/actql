import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installClientStaticEffectExplanation, installClientStaticPlan} from './client-interactive-plan.mjs';
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

async function staticExplanationFixture() {
  const {effectfulStaticPlan: plan} = await import('../../scripts/fixtures/effectful-static-plan-vectors.mjs');
  const binding = {program_definition_cid: plan.program_definition_cid,
    parameter_values_cid: plan.parameter_values_cid,
    compiled_plan_cid: plan.computation.plan_view.compiled_plan_cid,
    logical_map_cid: plan.computation.plan_view.logical_map.self_cid};
  const facts = {version: 'actql-explanation-facts/0.1', disclosure: 'structural',
    ...binding, steps: [], self_cid: cid('e')};
  const context = {version: 'actql-explanation-context/0.1', disclosure: 'structural',
    binding: {...binding, check_environment_cid: plan.check_environment_cid},
    items: [{kind: 'result', name: '結果', stage_ordinal: 0,
      producer: {state: 'not_projected', reason: 'no_original_port'}}]};
  return {plan, facts, context};
}

function explanationWires(view) {
  return {plan: JSON.stringify(view.plan), facts: JSON.stringify(view.facts),
    context: JSON.stringify(view.context)};
}

function explanationGeometry(value) {
  if (value === null || typeof value !== 'object') return {nodes: 1, depth: 1};
  const children = Object.values(value).map(explanationGeometry);
  const keys = Array.isArray(value) ? 0 : children.length;
  return {nodes: 1 + keys + children.reduce((sum, child) => sum + child.nodes, 0),
    depth: 1 + Math.max(0, ...children.map(child => child.depth))};
}

test('static Explanation applies aggregate limits and retains the original during delivery', async () => {
  const view = await staticExplanationFixture();
  const wires = explanationWires(view);
  const {nodes: maxNodes, depth: maxDepth} = explanationGeometry(view);
  const limits = {maxWireBytes: Buffer.byteLength(JSON.stringify(view), 'utf8'), maxNodes, maxDepth};
  let held = false;
  let delivered = 0;
  const read = installClientStaticEffectExplanation({authorize: () => true, authorizeEgress: () => true,
    async withOriginal(actual, visit) {
      assert.strictEqual(actual.connection, request.connection);
      held = true;
      try {return await visit(wires, () => assert.equal(held, true));}
      finally {held = false;}
    }});
  const result = await read({...request, ...limits}, async actual => {
    await Promise.resolve();
    assert.equal(held, true);
    delivered++;
    assert.deepEqual(actual, view);
    return 'delivered';
  });
  assert.equal(result, 'delivered');
  assert.equal(held, false);
  assert.equal(delivered, 1);
  for (const [key, bound] of Object.entries(limits)) {
    await assert.rejects(read({...request, ...limits, [key]: bound - 1},
      () => assert.fail(`One-short ${key} must stop delivery`)), {code: 'StaticExplanationReadLimit'});
    assert.equal(held, false);
  }
});

test('static Explanation refuses denied egress before preparation or wire access', async () => {
  let egressAllowed = false;
  let prepared = 0;
  const read = installClientStaticEffectExplanation({authorize: () => true,
    authorizeEgress: async () => egressAllowed,
    withOriginal(_request, visit) {
      prepared++;
      egressAllowed = false;
      return visit({get plan() {assert.fail('Revoked egress must not inspect wires');}},
        () => assert.fail('Revoked egress must stop before inspecting the original'));
    }});
  const consume = () => assert.fail('Denied facets must not be delivered');
  await assert.rejects(read(request, consume), {code: 'StaticExplanationAccessDenied'});
  assert.equal(prepared, 0);
  egressAllowed = true;
  await assert.rejects(read(request, consume), {code: 'StaticExplanationAccessDenied'});
  assert.equal(prepared, 1);
});

test('static Explanation checks the current Account run-read decision before projection and egress', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'actql-static-account-'));
  t.after(() => rm(folder, {recursive: true, force: true}));
  const accountConfig = join(folder, 'account.json');
  const change = (outcome, resource = 'run') => writeFile(accountConfig,
    sourceReadAccountConfiguration({connection: 'site', resource, outcome}));
  await change('allow');
  const evaluated = [];
  // The actual Local observer and authorization adapter use explicit Common
  // ports here. The fixture only supplies the result of the selected tuple.
  const moon = {
    executionAuthorizationAdmit(wire) {return JSON.parse(wire);},
    executionAuthorizationAccountJson(account) {
      return JSON.stringify({state: 'admitted', account_id: account.account_id});
    },
    executionAuthorizationEvaluate(account, principal, site, resource, operation) {
      evaluated.push([principal, site, resource, operation]);
      const [entry] = account.entries;
      return {outcome: entry.resource.any_of.includes(resource) ? entry.outcome : 'deny'};
    },
    executionAuthorizationEvaluationJson: JSON.stringify,
  };
  const {staticPlanImmediate} = createLocalReadAuthorizations({moon,
    authorization: {siteKey: 'site', accountConfig},
    principalId: 'person', namespaceId: 'original', authorityScopeCid: cid('a')});
  const view = await staticExplanationFixture();
  const selected = {...request, principalId: 'person'};
  let prepared = 0;
  let revoke = false;
  const read = installClientStaticEffectExplanation({authorize: () => true, authorizeEgress: staticPlanImmediate,
    async withOriginal(actual, visit) {
      assert.strictEqual(actual, selected);
      prepared++;
      if (revoke) {
        await change('deny');
        return await visit({get plan() {assert.fail('Changed Account must block wire access');}}, () => {});
      }
      return await visit(explanationWires(view), () => {});
    }});
  assert.deepEqual(await read(selected, value => value), view);
  const blocked = () => assert.fail('Denied Account must not deliver any facet');
  for (const [outcome, resource] of [['deny', 'run'], ['delegate', 'run'], ['allow', 'result/out']]) {
    await change(outcome, resource);
    await assert.rejects(read(selected, blocked), {code: 'StaticExplanationAccessDenied'});
  }
  await change('allow');
  await assert.rejects(read({...selected, principalId: 'foreign'}, blocked), {code: 'StaticExplanationAccessDenied'});
  assert.equal(prepared, 1);
  revoke = true;
  await assert.rejects(read(selected, blocked), {code: 'StaticExplanationAccessDenied'});
  assert.equal(prepared, 2);
  assert.ok(evaluated.length > 0);
  assert.ok(evaluated.every(tuple => tuple.join('/') === 'person/site/run/read'));
});

test('static Explanation refuses foreign Context and preserves final original current loss', async () => {
  const view = await staticExplanationFixture();
  let wires = explanationWires({...view, context: {...view.context,
    binding: {...view.context.binding, check_environment_cid: cid('f')}}});
  const lost = new Error('original is no longer current');
  let currentChecks = 0;
  const read = installClientStaticEffectExplanation({authorize: () => true, authorizeEgress: () => true,
    withOriginal: (_request, visit) => visit(wires, () => {
      currentChecks++;
      if (currentChecks === 2) throw lost;
    })});
  const consume = () => assert.fail('Foreign or stale facets must not be delivered');
  await assert.rejects(read(request, consume), {code: 'StaticExplanationEncodingRejected'});
  assert.equal(currentChecks, 1);
  currentChecks = 0;
  wires = explanationWires(view);
  await assert.rejects(read(request, consume), error => error === lost);
  assert.equal(currentChecks, 2);
});

test('static Explanation refuses an owner return before the visitor completes', async () => {
  const egress = Promise.withResolvers();
  let egressChecks = 0;
  let authorizationChecks = 0;
  let dropped;
  const unreadable = {get plan() {assert.fail('Returned owner must not supply wires');}};
  const read = installClientStaticEffectExplanation({
    authorize() {authorizationChecks++; return true;},
    authorizeEgress() {return ++egressChecks === 2 ? egress.promise : true;},
    withOriginal(_request, visit) {
      dropped = visit(unreadable, () => assert.fail('Returned owner must not be used'));
      void dropped.catch(() => {});
      return 'returned early';
    },
  });
  const consume = () => assert.fail('Incomplete visit must not deliver');
  try {
    await assert.rejects(read(request, consume), {code: 'StaticExplanationOriginalUnavailable'});
  } finally {
    egress.resolve(true);
  }
  await assert.rejects(dropped, {code: 'StaticExplanationOriginalUnavailable'});
  assert.equal(authorizationChecks, 1);

  let lateVisit;
  const absent = installClientStaticEffectExplanation({authorize: () => true, authorizeEgress: () => true,
    withOriginal(_request, visit) {lateVisit = visit;}});
  await assert.rejects(absent(request, consume), {code: 'StaticExplanationOriginalUnavailable'});
  await assert.rejects(lateVisit(unreadable, () => assert.fail('Late visit must not check current')),
    {code: 'StaticExplanationOriginalUnavailable'});
});

test('static Explanation refuses asynchronous current at both disclosure boundaries', async () => {
  const view = await staticExplanationFixture();
  const consume = () => assert.fail('Asynchronous assertion must stop delivery');
  for (const pass of [1, 2]) {
    let assertions = 0;
    const wires = pass === 1 ? {get plan() {assert.fail('Asynchronous assertion must stop wire access');}}
      : explanationWires(view);
    const read = installClientStaticEffectExplanation({authorize: () => true, authorizeEgress: () => true,
      withOriginal: (_request, visit) => visit(wires, () => {
        if (++assertions === pass) return Promise.reject(new Error('asynchronous assertion'));
      })});
    await assert.rejects(read(request, consume), {code: 'StaticExplanationOriginalUnavailable'});
    assert.equal(assertions, pass);
  }
});

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
