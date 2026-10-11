import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installClientStaticPlan} from './client-interactive-plan.mjs';
import {validClientBody, prepareClientHostRequest} from '../../packages/client-wire/index.mjs';
import {mapBody, planCid, cid} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

// This fixed semantic mock proves routing, not a compiler-issued public view.
const mockView = () => ({version: 'actql-plan-view/0.1', compiled_plan_cid: planCid,
  logical_map: {...structuredClone(mapBody), self_cid: `sha256:${createHash('sha256')
    .update(canonicalText(mapBody)).digest('hex')}`},
  observation: 'static', provider_io: 0,
  quantities: [{kind: 'unknown', unit: 'work', reason: 'not_observed'}],
  capabilities: {static_plan: true, inspect: false, durable_control: false,
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
    moon: {clientProgramTaskCount: () => 2, clientProgramUsesGraphCarrier: () => false},
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
    moon: {clientProgramTaskCount: () => 1, clientProgramUsesGraphCarrier: () => false},
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
