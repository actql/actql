import assert from 'node:assert/strict';
import test from 'node:test';
import {gatewayLimits, startExplorerGateway} from './gateway.mjs';
import {gatewayClient, harness, origin, ref, tick} from './gateway-test.fixture.mjs';
import {createExplorerBrowserSource} from './browser-source.mjs';
import {gatewayLaunchPlanFixture} from './gateway-launch.fixture.mjs';
import {observationRef, runObservationFixture, ownerObservationFixture}
  from '../explorer-ui/run-observation.fixture.mjs';
import {runExplanation, unprojectedRunExplanation}
  from '../../scripts/fixtures/explanation-facts-vectors.mjs';
import type {CancellationReference, Execution, RunReference} from '../sdk/index.mjs';
import type {WireClientBodyByOperation, WireControlCommand} from '../client-wire/index.js';
import {resumeControlOperationRef} from '../client-wire/index.mjs';
import type {createExplorerBrowserSource as BrowserFactory} from './browser-source.d.ts';

type Browser = ReturnType<typeof BrowserFactory>;
type PresentationOptions = Parameters<Browser['runPresentation']>[1];
type AqlSubmission = WireClientBodyByOperation['submit-intent'] &
  Pick<Extract<WireClientBodyByOperation['submit'], {kind: 'aql'}>, 'kind' | 'input'>;
type LookupRef = WireClientBodyByOperation['lookup-submission']['submissionRef'];

function requestUrl(input: Parameters<typeof fetch>[0]): string {
  assert(typeof input === 'string', 'Expected BrowserSource to send a URL string');
  return input;
}

function localBrowserRequest(input: Parameters<typeof fetch>[0], options: RequestInit | undefined,
  cookie: string | undefined) {
  const headers = new Headers(options?.headers);
  headers.set('Host', '127.0.0.1:43210');
  headers.set('Origin', origin);
  if (cookie !== undefined) headers.set('Cookie', cookie);
  return new Request(requestUrl(input), {...options, headers});
}

test('current observation endpoint reads only the same original Run and one Owner-local page', async () => {
  const calls: unknown[] = [], original=observationRef();
  const h=harness({client:{async attach(ref){calls.push(['attach',ref]);return {
    inspect(limits){calls.push(['inspect',limits]);return runObservationFixture();},
    observeOwners(limits){calls.push(['owners',limits]);return ownerObservationFixture();},
    wait(){assert.fail('no execution wait');},cancel(){assert.fail('no control');},
    result(){assert.fail('no Result open');},
  };},start(){assert.fail('no Run start');}}});
  assert.equal((await h.send('/api/read/observation',{ref:original})).status,401);
  const session=await h.connect();
  assert.equal((await h.read('observation',{ref:original,permission:true},session)).status,400);
  assert.deepEqual(calls,[]);
  const answer=await h.read('observation',{ref:original},session);assert.equal(answer.status,200);
  const model=(await answer.json()).data;
  assert.equal(model.run.status,'running');assert.equal(model.run.controlRevision,7);
  assert.equal(model.histories.owners[0].snapshot.revision,3);
  assert.equal(model.histories.owners[0].history.entries[1].state,'unknown');
  assert.equal(model.logicalProgress.state,'unavailable');
  assert.deepEqual(calls,[['attach',original],['inspect',{maxWireBytes:65536,maxNodes:10000,maxDepth:64}],
    ['owners',{maxEntries:32,maxWireBytes:65536}]]);
});
test('the browser reads the retained Relation for its exact original Run and port', async () => {
  const cid = (digit: string) => `sha256:${digit.repeat(64)}`;
  const port = {stepId: cid('1'), portId: cid('2'), role: 'input' as const,
    compiledPlanCid: cid('3'), logicalMapCid: cid('4'), carrierContractCid: cid('5')};
  const sample = {state: 'available', source: {run_ref: ref, compiled_plan_cid: port.compiledPlanCid,
    logical_map_cid: port.logicalMapCid, step_id: port.stepId, role: port.role, port_id: port.portId,
    carrier: 'relation', carrier_contract_cid: port.carrierContractCid, source_generation_cid: cid('6'),
    original_capture_cid: cid('7'), producer: {kind: 'logical_output', step_id: cid('8'), output_port_id: cid('9')}},
  capture: {strategy: 'execution_prefix', sampled_items: '1',
    total: {kind: 'unknown', unit: 'rows', reason: 'count_not_observed'}, completeness: 'partial',
    truncation: 'unknown', sample_ref_cid: cid('a'), receipt_cid: cid('b'), emission_provenance_cid: cid('c')},
  data: {version: 'actql-sample-relation/0.1', kind: 'relation', schema_cid: cid('d'),
    ordering_evidence_cid: null, columns: [{position: 0, name: 'n', value_contract_cid: cid('e'), required: false}],
    rows: [[{presence: 'present', value_contract_cid: cid('e'), value: null}]]}};
  let answer: unknown = sample, attaches = 0, reads = 0;
  let expectedRevision: number | undefined, cookie: string | undefined, csrf: string | undefined;
  let failureStatus: number | undefined;
  const {promise: started, resolve: entered} = Promise.withResolvers<void>();
  const {promise: held, resolve: release} = Promise.withResolvers<void>();
  const h = harness({allowSamples: true, client: {async attach(original) {
    assert.deepEqual(original, ref);
    attaches++;
    return {async sample(selector, limits) {
      reads++;
      assert.deepEqual(selector, {step: {by: 'id', step_id: port.stepId}, role: 'input', input_port_id: port.portId});
      assert.deepEqual(limits, {maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64,
        ...(expectedRevision === undefined ? {} : {nextRevision: expectedRevision})});
      if (failureStatus !== undefined) throw Object.assign(new Error('private detail'), {status: failureStatus});
      if (answer === undefined) {entered(); await held; return sample;}
      return answer;
    }, result() {assert.fail('Sample opens no Result');}};
  }}});
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    if (requestUrl(url).endsWith('/api/session')) csrf = (await response.clone().json()).csrf;
    return response;
  }});
  try {
    assert.equal((await h.send('/api/read/run-sample', {ref, port})).status, 401);
    const session = await source.connect(h.gateway.issueBootstrap().bootstrap);
    assert.equal(session.sample, true);
    const malformed = await h.send('/api/read/run-sample', {ref, port: {...port, portId: null}},
      {Cookie: cookie, 'X-Actql-CSRF': csrf});
    assert.equal(malformed.status, 400);
    assert.equal(attaches, 0);
    assert.deepEqual(await source.runSample(ref, port), sample);
    await assert.rejects(source.runSample(ref, {...port, nextRevision: 0}), {code: 'ExplorerInvalidReply'});
    expectedRevision = 5;
    assert.deepEqual(await source.runSample(ref, {...port, nextRevision: 5}), sample);
    expectedRevision = undefined;
    for (const state of [{state: 'forbidden'}, {state: 'expired'}, {state: 'unavailable', reason: 'not_retained'},
      {state: 'unavailable', reason: 'capacity'}]) {
      answer = state;
      assert.deepEqual(await source.runSample(ref, port), state);
    }
    answer = {...sample, source: {...sample.source, port_id: cid('f')}};
    await assert.rejects(source.runSample(ref, port), {code: 'ExplorerReadUnavailable'});
    answer = undefined;
    const pending = source.runSample(ref, port);
    await started;
    await source.connect(h.gateway.issueBootstrap().bootstrap);
    release();
    await assert.rejects(pending, {code: 'ExplorerStaleScope'});
    assert.equal(attaches, 8);
    assert.equal(reads, 8);
    // The replacement session can read the original. A per-operation 403
    // keeps it usable, while a current 401 prevents any later sample read.
    answer = sample;
    assert.deepEqual(await source.runSample(ref, port), sample);
    failureStatus = 403;
    assert.deepEqual(await source.runSample(ref, port), {state: 'forbidden'});
    failureStatus = undefined;
    assert.deepEqual(await source.runSample(ref, port), sample);
    failureStatus = 401;
    await assert.rejects(source.runSample(ref, port), {code: 'ExplorerStaleScope'});
    await assert.rejects(source.runSample(ref, port), {code: 'ExplorerCapabilityUnavailable'});
    assert.equal(reads, 12);
  } finally {release(); source.close(); await h.gateway.close();}
});

test('Explorer Resume preserves the original lookup after lost reply and distinguishes revision conflict', async t => {
  const cid = 'sha256:' + 'a'.repeat(64);
  const commands: WireControlCommand[] = [], requests: string[] = [];
  const h = harness({allowDebugResume: true, client: {attach(original) {
    assert.deepEqual(original, ref);
    return {
      prepareResume({operationId, expectedRevision, until}) {
        return {version: 'actql-control-command/0.1', operation: 'resume', run_ref: original,
          operation_id: operationId, expected_control_revision: expectedRevision, self_cid: cid,
          interval: {until, guards: null}};
      },
      resume(command) {
        if (command.expected_control_revision !== 7) {
          throw Object.assign(new Error('private rejection'), {code: 'ClientRunDebugEntryRevisionConflict'});
        }
        commands.push(command);
        return {state: 'unknown', reason: 'control_acceptance_unknown'};
      },
      lookupControlOperation(operation) {
        assert.equal(commands.length, 1);
        assert.deepEqual(operation, resumeControlOperationRef(commands[0]));
        return {state: 'unknown', reason: 'control_acceptance_unknown'};
      },
    };
  }}});
  let cookie: string | undefined;
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const path = new URL(requestUrl(url)).pathname;
    requests.push(path);
    const answer = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = answer.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    if (path === '/api/control/resume' && answer.ok) throw new TypeError('Lost reply');
    return answer;
  }});
  t.after(async () => {source.close(); await h.gateway.close();});
  const denied = harness();
  t.after(() => denied.gateway.close());
  assert.equal((await denied.read('prepare-resume', {}, await denied.connect())).status, 404);
  assert.equal((await source.connect(h.gateway.issueBootstrap().bootstrap)).debugResume, true);
  const stale = await source.prepareResume(ref, {operationId: 'older-step', expectedRevision: 6, until: 'step'});
  await assert.rejects(source.resume(stale), {code: 'ExplorerControlRevisionConflict'});
  assert.equal(commands.length, 0);
  const winning = await source.prepareResume(ref, {operationId: 'original-step', expectedRevision: 7, until: 'step'});
  const operationRef = resumeControlOperationRef(winning);
  assert.deepEqual(await source.resume(winning), {state: 'reply_unknown', operationRef});
  assert.deepEqual(await source.lookupControlOperation(operationRef), {state: 'unknown', reason: 'control_acceptance_unknown'});
  assert.deepEqual(commands, [winning]);
  assert.deepEqual(requests, ['/api/session', '/api/read/prepare-resume', '/api/control/resume',
    '/api/read/prepare-resume', '/api/control/resume', '/api/read/lookup-control-operation']);
});

test('foreign and delayed Owner replies cannot escape current observation scope', async () => {
  const original = observationRef();
  const pending = Promise.withResolvers<ReturnType<typeof ownerObservationFixture>>();
  const h=harness({client:{attach:async()=>({inspect:async()=>runObservationFixture(),
    observeOwners:async()=>pending.promise})}});
  const session=await h.connect(),answer=h.read('observation',{ref:original},session);
  await tick();h.gateway.invalidateScope();pending.resolve(ownerObservationFixture());
  assert.notEqual((await answer).status,200);
  const foreign=ownerObservationFixture();foreign.ref.namespaceId='foreign';
  const f=harness({client:{attach:async()=>({inspect:async()=>runObservationFixture(),observeOwners:async()=>foreign})}});
  assert.notEqual((await f.read('observation',{ref:original},await f.connect())).status,200);
});

test('expired cancellation session cannot dispatch after original attach awaits', async () => {
  let now = 1000, cancellations = 0;
  const attached = Promise.withResolvers<void>();
  const pendingAttach = Promise.withResolvers<{cancel(): unknown}>();
  const original = {cancelRef: {...ref, cancelId: 'expired-session-cancel', expectedRevision: 7},
    attemptRef: {operation: 'cancel', attemptId: 'expired-session-attempt'}};
  const h = harness({allowCancellation: true, now: () => now, sessionMs: 20,
    client: {async attach(selected) {assert.deepEqual(selected, ref); attached.resolve(); return pendingAttach.promise;}}});
  const session = await h.connect();
  const answer = h.send('/api/control/cancel', original,
    {Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf});
  await attached.promise; now += 21;
  pendingAttach.resolve({async cancel() {cancellations++; return {kind: 'accepted', attemptRef: original.attemptRef,
    cancellation: {kind: 'accepted', ref, cancelRef: original.cancelRef, revision: 8}};}});
  assert.equal((await answer).status, 401);
  assert.equal(cancellations, 0, 'Expired presentation session must refuse before Owner dispatch');
});

test('only exact loopback origins and finite TTLs can create a Gateway', () => {
  for (const rejected of ['http://localhost:43210', 'http://0.0.0.0:43210',
    'http://127.0.0.1:43210/', 'https://127.0.0.1:43210', 'http://user@127.0.0.1:43210']) {
    assert.throws(() => harness({origin: rejected}), {code: 'ExplorerInvalidGateway'});
  }
  for (const sessionMs of [0, -1, '5', Infinity, gatewayLimits.sessionMs + 1]) {
    assert.throws(() => harness({sessionMs: sessionMs as number}), {code: 'ExplorerInvalidGateway'});
  }
});

test('direct Program launch uses only the existing static Plan Owner after session and CSRF', async () => {
  const input = {kind: 'program' as const, text: 'SELECT 1 AS n', format: 'sql' as const}, calls: unknown[] = [];
  const view = gatewayLaunchPlanFixture();
  const h = harness({launchInput: input, client: {
    attach() {assert.fail('Program launch does not attach or start a Run');},
    async plan(text, options) {calls.push([text, options]); return view;},
    start() {assert.fail('no new Run');}, submit() {assert.fail('no submission');},
  }}); input.text = 'changed';
  assert.equal((await h.send('/api/read/launch', {})).status, 401);
  const session = await h.connect();
  assert.equal((await h.read('launch', {}, session, {'X-Actql-CSRF': ''})).status, 403);
  assert.equal((await h.read('launch', {start: true}, session)).status, 400);
  assert.deepEqual(calls, []);
  const answer = await h.read('launch', {}, session);
  assert.equal(answer.status, 200);
  assert.equal(answer.headers.get('cache-control'), 'no-store');
  const data = (await answer.json()).data;
  assert.deepEqual(Object.keys(data), ['kind', 'plan']);
  assert.equal(data.kind, 'program');
  assert.equal(data.plan.compiledPlanCid, view.compiled_plan_cid);
  assert.equal(data.plan.logicalMapCid, view.logical_map.self_cid);
  assert.deepEqual(calls, [['SELECT 1 AS n', {format: 'sql', maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  assert(!JSON.stringify(data).includes('SELECT 1 AS n'));
  h.gateway.invalidateScope();
  assert.equal((await h.read('launch', {}, session)).status, 401);
  assert.equal(calls.length, 1);
});

test('direct AQL launch preserves canonical and legacy format through the existing Plan Owner', async () => {
  for (const format of ['aql', 'aql-text'] as const) {
    const calls: unknown[] = [], view = gatewayLaunchPlanFixture();
    const h = harness({launchInput: {kind: 'program', text: 'FROM rows', format}, client: {
      attach() {assert.fail('no Run attach');},
      async plan(text, options) {calls.push([text, options]); return view;},
      submit() {assert.fail('no submit');}, start() {assert.fail('no start');},
    }});
    const session = await h.connect();
    const reply = await h.read('launch', {}, session);
    assert.equal(reply.status, 200);
    assert.equal((await reply.json()).data.plan.compiledPlanCid, view.compiled_plan_cid);
    assert.deepEqual(calls, [['FROM rows', {format, maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  }
});

test('direct Run launch reads only the original saved map and never compiles a replacement', async () => {
  const original = {...ref}, calls: unknown[] = [], view = gatewayLaunchPlanFixture();
  const h = harness({launchInput: {kind: 'run', ref: original}, client: {
    async attach(selected) {calls.push(['attach', selected]); return {
      async plan() {calls.push(['run.plan']); return {
        version: 'actql-run-plan-view/0.1', run_ref: {...ref}, plan_view: view};},
    };}, plan() {assert.fail('no static replacement');}, start() {assert.fail('no new Run');},
  }});
  original.runDefinitionCid = `sha256:${'c'.repeat(64)}`;
  const session = await h.connect();
  const data = (await (await h.read('launch', {}, session)).json()).data;
  assert.equal(data.kind, 'run'); assert.deepEqual(data.originalPlan.runRef, ref);
  assert.equal(data.originalPlan.plan.logicalMapCid, view.logical_map.self_cid);
  assert.deepEqual(calls, [['attach', ref], ['run.plan']]);
  const empty = harness(), emptySession = await empty.connect();
  assert.equal((await (await empty.read('launch', {}, emptySession)).json()).data, null);
  assert.deepEqual(empty.calls, []);
});

test('launch refuses invalid authoring without disclosing the file text or Host diagnostic', async () => {
  const secret = 'private-file-fixture-not-a-program'; let plans = 0;
  const h = harness({launchInput: {kind: 'program', text: secret, format: 'program'}, client: {
    attach() {assert.fail('no attach');}, plan() {plans++; assert.fail('invalid JSON is not admitted');},
  }});
  const session = await h.connect(), reply = await h.read('launch', {}, session);
  assert.equal(reply.status, 502);
  assert.deepEqual(await reply.json(), {error: 'ExplorerReadUnavailable'});
  assert.equal(plans, 0);
});

test('launch keeps missing and foreign original Run maps unavailable with no compiler fallback', async () => {
  for (const foreign of [false, true]) {
    const calls: unknown[] = [], view = gatewayLaunchPlanFixture();
    const h = harness({launchInput: {kind: 'run', ref}, client: {
      async attach(selected) {calls.push(['attach', selected]); return foreign ? {
        async plan() {calls.push(['run.plan']); return {version: 'actql-run-plan-view/0.1',
          run_ref: {...ref, namespaceId: 'foreign'}, plan_view: view};},
      } : {};}, plan() {assert.fail('old maps cannot be repaired');},
    }});
    const session = await h.connect(), reply = await h.read('launch', {}, session);
    assert.equal(reply.status, 409);
    assert.deepEqual(await reply.json(), {error: foreign ? 'ExplorerInvalidRunPlan' : 'ExplorerCapabilityUnavailable'});
    assert.deepEqual(calls, foreign ? [['attach', ref], ['run.plan']] : [['attach', ref]]);
  }
});

test('one-use bootstrap becomes HttpOnly scoped cookie and current CSRF session', async () => {
  const h = harness(), session = await h.connect();
  const replay = await h.send('/api/session', {bootstrap: session.issued.bootstrap});
  assert.equal(replay.status, 403);
  assert.equal((await h.read('run', {ref}, session)).status, 200);
  assert.deepEqual(h.calls, [['attach', ref], ['inspect', {
    maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  const metadata = await h.read('result', {ref, name: 'é\r\n'}, session);
  assert.equal((await metadata.json()).data.name, 'é\r\n');
  assert.deepEqual(h.calls.slice(2), [['attach', ref], ['result', 'é\r\n'], ['describe']]);
});

test('Host, Origin, Fetch Metadata, proxy headers and CSRF reject before SDK I/O', async () => {
  const h = harness(), session = await h.connect();
  for (const headers of [{Host: 'evil.example:43210'}, {Origin: 'http://evil.example'},
    {Origin: ''}, {'Sec-Fetch-Site': 'cross-site'}, {'X-Forwarded-Host': '127.0.0.1:43210'},
    {Forwarded: 'host=127.0.0.1:43210'}, {'X-Actql-CSRF': ''},
    {Cookie: `${session.cookie}; ${session.cookie}`},
    {'X-Actql-CSRF': 'é'.repeat(43)}]) {
    assert.equal((await h.read('run', {ref}, session, headers)).status, 403);
  }
  assert.equal((await h.send('/api/read/run?token=secret', {ref})).status, 400);
  assert.deepEqual(h.calls, []);
});

test('unknown/read-control paths and foreign extra input never invoke business methods', async () => {
  const h = harness(), session = await h.connect();
  for (const kind of ['submit', 'cancel', 'resume', 'sample', 'payload']) {
    assert.equal((await h.read(kind, {ref}, session)).status, 404);
  }
  assert.equal((await h.read('run', {ref, submit: true}, session)).status, 400);
  assert.equal((await h.read('run', {ref: {...ref, namespaceId: 1}}, session)).status, 400);
  assert.equal((await h.read('plan', {input: 1}, session)).status, 400);
  assert.equal((await h.read('plan', {input: {}, options: {credential: 'secret'}}, session)).status, 400);
  assert.equal((await h.read('plan', {input: 'SELECT 1 AS n'}, session)).status, 409);
  assert.deepEqual(h.calls, []);
});

test('saved Run Plan has a closed read-only body and no static fallback for old Hosts', async () => {
  const h = harness(), session = await h.connect();
  for (const body of [{ref, program: 'SELECT 1'}, {ref, options: {}},
    {ref: {...ref, authorityScopeCid: 'foreign'}}]) {
    assert.equal((await h.read('run-plan', body, session)).status, 400);
  }
  assert.deepEqual(h.calls, []);
  assert.equal((await h.read('run-plan', {ref}, session, {'X-Actql-CSRF': ''})).status, 403);
  assert.deepEqual(h.calls, []);
  const response = await h.read('run-plan', {ref}, session);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), {error: 'ExplorerCapabilityUnavailable'});
  assert.deepEqual(h.calls, [['attach', ref]]);
});

test('Gateway explanation read keeps original session Origin CSRF and closed reference before SDK I/O', async () => {
  const calls: unknown[] = [], original = runExplanation.run_ref;
  const h = harness({client: {attach(selected) {
    calls.push(['attach', selected]); return {explain(options) {
      calls.push(['explain', options]); return structuredClone(runExplanation);
    }};
  }, plan() {assert.fail('no static repair');}, start() {assert.fail('no Run');}}});
  assert.equal((await h.send('/api/read/run-explanation', {ref: original})).status, 401);
  const session = await h.connect();
  for (const headers of [{'X-Actql-CSRF': ''}, {Origin: 'https://foreign.example'}]) {
    assert.equal((await h.read('run-explanation', {ref: original}, session, headers)).status, 403);
  }
  for (const body of [{ref: original, options: {sample: true}}, {ref: {runDefinitionCid: original.runDefinitionCid}}]) {
    assert.equal((await h.read('run-explanation', body, session)).status, 400);
  }
  assert.deepEqual(calls, []);
  const response = await h.read('run-explanation', {ref: original}, session);
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual((await response.json()).data, runExplanation);
  assert.deepEqual(calls, [['attach', original], ['explain', {maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}]]);
  await h.gateway.close();
});

test('Gateway explanation distinguishes authorized NotProjected from missing support or Owner denial', async () => {
  for (const [kind, status] of [['absent', 200], ['unsupported', 409], ['denied', 403]]) {
    let calls = 0;
    const h = harness({client: {attach() {
      return kind === 'unsupported' ? {} : {explain() {
        calls++;
        if (kind === 'denied') throw Object.assign(new Error('private Host diagnostic'), {status: 403});
        return structuredClone(unprojectedRunExplanation);
      }, plan() {assert.fail('no legacy repair');}};
    }}});
    const session = await h.connect();
    const response = await h.read('run-explanation', {ref: runExplanation.run_ref}, session);
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), status === 200
      ? {scopeEpoch: session.body.scopeEpoch, data: unprojectedRunExplanation}
      : {error: kind === 'unsupported' ? 'ExplorerCapabilityUnavailable' : 'ExplorerReadRefused'});
    assert.equal(calls, kind === 'unsupported' ? 0 : 1);
    await h.gateway.close();
  }
});

test('browser explanation traverses the actual Gateway read and drops a delayed invalidated scope', async () => {
  let pending = false;
  const started = Promise.withResolvers<void>();
  const wait = Promise.withResolvers<void>();
  const h = harness({client: {attach: () => ({async explain() {
    if (pending) {started.resolve(); await wait.promise;}
    return structuredClone(runExplanation);
  }})}});
  let cookie: string | undefined;
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    return response;
  }});
  const capabilities = await source.connect(h.gateway.issueBootstrap().bootstrap);
  assert.equal(capabilities.sample, false); assert.equal(capabilities.control, false);
  assert.deepEqual(await source.explain(runExplanation.run_ref), runExplanation);
  pending = true;
  const reply = source.explain(runExplanation.run_ref);
  await started.promise; h.gateway.invalidateScope(); wait.resolve();
  await assert.rejects(reply, {code: 'ExplorerStaleScope'});
  await assert.rejects(source.explain(runExplanation.run_ref), {code: 'ExplorerSessionExpired'});
  source.close(); await h.gateway.close();
});

test('a denied Run status read preserves separate Story access until the session expires', async t => {
  let failureStatus = 403, statusReads = 0, storyReads = 0;
  let cookie: string | undefined;
  const h = harness({client: {attach(original) {
    assert.deepEqual(original, runExplanation.run_ref);
    return {
      inspect() {
        statusReads++;
        throw Object.assign(new Error('private status reason'), {status: failureStatus});
      },
      explain() {storyReads++; return structuredClone(runExplanation);},
    };
  }}});
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    return response;
  }});
  t.after(async () => {source.close(); await h.gateway.close();});
  await source.connect(h.gateway.issueBootstrap().bootstrap);
  await assert.rejects(source.inspect(runExplanation.run_ref), {code: 'ExplorerReadUnavailable'});
  assert.deepEqual(await source.explain(runExplanation.run_ref), runExplanation);
  failureStatus = 401;
  await assert.rejects(source.inspect(runExplanation.run_ref), {code: 'ExplorerStaleScope'});
  await assert.rejects(source.explain(runExplanation.run_ref), {code: 'ExplorerSessionExpired'});
  assert.deepEqual({statusReads, storyReads}, {statusReads: 2, storyReads: 1});
});

test('Gateway explanation close retains the original pending read without closing its borrowed Client', async () => {
  let completed = false;
  const started = Promise.withResolvers<void>();
  const pending = Promise.withResolvers<typeof runExplanation>();
  const h = harness({client: {attach: () => ({async explain() {started.resolve(); return pending.promise;}}),
    close() {assert.fail('Gateway does not own the Client');}}});
  const response = h.read('run-explanation', {ref: runExplanation.run_ref}, await h.connect());
  await started.promise;
  const closing = h.gateway.close().then(() => {completed = true;});
  await tick(); assert.equal(completed, false, 'Presentation closure is not original read settlement');
  pending.resolve(structuredClone(runExplanation));
  await closing;
  assert.equal(completed, true);
  assert.equal((await response).status, 401, 'Closed scope must not disclose the delayed Facts');
});

test('Gateway original presentation rejects extra execution inputs and unsupported locale before SDK I/O', async () => {
  const h = harness({client: {attach() {assert.fail('invalid presentation must not attach');}}});
  const session = await h.connect();
  for (const body of [{ref, locale: 'fr'}, {ref, captureSamples: true},
    {ref, input: 'SELECT 1'}, {ref, plan: {}}, {ref: {runDefinitionCid: ref.runDefinitionCid}}]) {
    assert.equal((await h.read('run-presentation', body, session)).status, 400);
  }
  assert.equal((await h.read('run-presentation', {ref}, session, {'X-Actql-CSRF': ''})).status, 403);
  await h.gateway.close();
});

test('bootstrap and established session expiry never silently renew', async () => {
  let time = 1000;
  const h = harness({now: () => time, sessionMs: 100, bootstrapMs: 50});
  const expired = h.gateway.issueBootstrap(); time += 50;
  assert.equal((await h.send('/api/session', {bootstrap: expired.bootstrap})).status, 403);
  const session = await h.connect(); time += 100;
  assert.equal((await h.read('run', {ref}, session)).status, 401);
  assert.deepEqual(h.calls, []);
});

test('current scope invalidation discards delayed data and old authorization failure', async () => {
  for (const failed of [false, true]) {
    const began = Promise.withResolvers<void>();
    const wait = Promise.withResolvers<void>();
    const h = harness({client: {async attach() {began.resolve(); await wait.promise;
      if (failed) throw Object.assign(new Error('secret old Host token'), {status: 401});
      return {inspect() {assert.fail('scope ended before inspect');}};
    }}});
    const old = await h.connect(), pending = h.read('run', {ref}, old);
    await began.promise;
    h.gateway.invalidateScope();
    const current = await h.connect();
    wait.resolve();
    const reply = await pending;
    assert.equal(reply.status, 401);
    assert(!JSON.stringify(await reply.json()).includes('secret'));
    assert.equal((await h.read('payload', {ref}, current)).status, 404);
  }
});

test('a session expiring during SDK read cannot disclose its delayed result', async () => {
  let time = 1;
  const h = harness({now: () => time, sessionMs: 10, client: {async attach() {
    time += 10; return {inspect() {return {secret: 'expired'};}};
  }}});
  const session = await h.connect(), reply = await h.read('run', {ref}, session);
  assert.equal(reply.status, 401);
  assert(!JSON.stringify(await reply.json()).includes('expired'));
});

test('partial/failed SDK observations disclose only a safe unavailable classification', async () => {
  const h = harness({client: {async attach() {throw new Error('credential=super-secret');}}});
  const session = await h.connect(), reply = await h.read('run', {ref}, session);
  assert.equal(reply.status, 502);
  assert.deepEqual(await reply.json(), {error: 'ExplorerReadUnavailable'});
});

test('malformed, oversized and deeply nested bodies refuse before SDK admission', async () => {
  const h = harness(), session = await h.connect();
  for (const body of ['{', ' '.repeat(gatewayLimits.bodyBytes + 1),
    JSON.stringify({ref, extra: JSON.parse('['.repeat(65) + '0' + ']'.repeat(65))})]) {
    assert([400, 413].includes((await h.read('run', body, session)).status));
  }
  assert.equal((await h.read('run', {ref}, session, {'Content-Type': 'text/plain'})).status, 400);
  assert.deepEqual(h.calls, []);
});

test('concurrent read ceiling holds slots until SDK work actually settles', async () => {
  let starts = 0;
  const wait = Promise.withResolvers<void>();
  const h = harness({client: {async attach() {starts++; await wait.promise;
    return {inspect() {return {};}};
  }}});
  const session = await h.connect(), reads = [];
  for (let i = 0; i < gatewayLimits.inFlight; i++) reads.push(h.read('run', {ref}, session));
  while (starts !== gatewayLimits.inFlight) await tick();
  assert.equal((await h.read('run', {ref}, session)).status, 429);
  wait.resolve();
  assert((await Promise.all(reads)).every(reply => reply.status === 200));
});

test('reply overflow refuses instead of a shortened observation under original identity', async () => {
  const h = harness({client: {async attach() {return {inspect() {
    return {payload: 'x'.repeat(gatewayLimits.replyBytes)};
  }};}}});
  assert.equal((await h.read('run', {ref}, await h.connect())).status, 413);
});

test('only finite preloaded assets are served; paths cannot read the workspace', async () => {
  const bytes = Buffer.from('<html>built asset fixture</html>');
  const h = harness({assets: new Map([['/index.html', {body: bytes, contentType: 'text/html; charset=utf-8'}]])});
  bytes.fill(0);
  const home = await h.send('/', undefined, {}, 'GET');
  assert.equal(await home.text(), '<html>built asset fixture</html>');
  assert.equal(home.headers.get('cache-control'), 'no-store');
  const csp = home.headers.get('content-security-policy');
  assert(csp);
  assert(csp.includes("frame-ancestors 'none'"));
  assert(csp.includes("worker-src 'self'"));
  assert(!csp.includes('blob:') && !csp.includes('unsafe-eval'));
  for (const path of ['/package.json', '/src/code.mbt', '/assets/../../README.md', '/missing.js']) {
    assert.equal((await h.send(path, undefined, {}, 'GET')).status, 404);
  }
  assert.throws(() => harness({assets: new Map([['/README.md', {body: bytes,
    contentType: 'text/html; charset=utf-8'}]])}), {code: 'ExplorerInvalidAssets'});
  assert.throws(() => harness({assets: new Map([['/index.html', {
    body: Buffer.alloc(gatewayLimits.assetBytes + 1), contentType: 'text/html; charset=utf-8'}]])}),
  {code: 'ExplorerAssetLimit'});
});

test('real Node launcher binds loopback and closes only its own HTTP server', async t => {
  let attaches = 0;
  const originalRequest = globalThis.Request, originalResponse = globalThis.Response;
  const gateway = await startExplorerGateway({client: gatewayClient({async attach() {
    attaches++; return {inspect() {return {marker: 'loopback fixture'};}};
  }, close() {assert.fail('borrowed client stays open');}})});
  t.after(() => gateway.close());
  assert.equal(globalThis.Request, originalRequest);
  assert.equal(globalThis.Response, originalResponse);
  assert.match(gateway.origin, /^http:\/\/127\.0\.0\.1:\d+$/u);
  const issued = gateway.issueBootstrap();
  const response = await fetch(`${gateway.origin}/api/session`, {method: 'POST',
    headers: {Origin: gateway.origin, 'Content-Type': 'application/json'},
    body: JSON.stringify({bootstrap: issued.bootstrap})});
  assert.equal(response.status, 200);
  const session = await response.json();
  const sessionCookie = response.headers.get('set-cookie');
  assert(sessionCookie);
  assert.match(sessionCookie, /Path=\/api; HttpOnly; SameSite=Strict/u);
  const reply = await fetch(`${gateway.origin}/api/read/run`, {method: 'POST',
    headers: {Origin: gateway.origin, 'Content-Type': 'application/json',
      Cookie: sessionCookie.split(';')[0], 'X-Actql-CSRF': session.csrf},
    body: JSON.stringify({ref})});
  assert.equal(reply.status, 200);
  assert.equal(attaches, 1);
  await gateway.close(); await gateway.close();
  assert.equal(globalThis.Request, originalRequest);
  assert.equal(globalThis.Response, originalResponse);
  await assert.rejects(fetch(gateway.origin));
});

test('browser holds CSRF only in memory, discards old replies/401 and never retries', async () => {
  for (const failed of [false, true]) {
    let calls = 0;
    const wait = Promise.withResolvers<void>();
    const source = createExplorerBrowserSource({origin, now: () => 100,
      async fetch(url, options) {
        calls++;
        assert.equal(options?.redirect, 'error'); assert.equal(options?.credentials, 'same-origin');
        assert(!requestUrl(url).includes('secret')); assert(!new Headers(options?.headers).has('Authorization'));
        if (requestUrl(url).endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
          scopeEpoch: calls, expiresAt: 200, capabilities: {plan: false, run: true,
            resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false,checkpointList:false,checkpointReview:false}});
        await wait.promise;
        return failed ? Response.json({error: 'old'}, {status: 401}) :
          Response.json({scopeEpoch: 1, data: {secret: 'old-scope'}});
      }});
    await source.connect('bootstrap');
    const pending = source.inspect(ref);
    await source.connect('new-bootstrap');
    wait.resolve();
    await assert.rejects(pending, {code: 'ExplorerStaleScope'});
    assert.equal(calls, 3);
    source.close();
    await assert.rejects(source.inspect(ref), {code: 'ExplorerSessionExpired'});
    assert.equal(calls, 3);
  }
});

test('browser original presentation refuses option overrides before sending a read', async () => {
  let reads = 0, getters = 0;
  const source = presentationBrowser(async () => {
    reads++; return {runRef: ref, plan: null, explanation: {state: 'not_projected', reason: 'not_retained'}};
  });
  try {
    await source.connect('bootstrap');
    for (const options of [{ref: {...ref, namespaceId: 'foreign'}}, {locale: 'ja', ref},
      null, [], {locale: 'fr'}, {get locale() {getters++; return 'en';}},
      {[Symbol('ref')]: ref}]) {
      await assert.rejects(source.runPresentation(ref, options as PresentationOptions), {code: 'ExplorerInvalidReply'});
    }
    assert.equal(reads, 0); assert.equal(getters, 0);
  } finally {source.close();}
});

test('browser original presentation captures reference and locale before its pending read', async () => {
  const original = {...ref}, options: NonNullable<PresentationOptions> = {locale: 'ja'};
  let sent: unknown;
  const pending = Promise.withResolvers<void>();
  const source = presentationBrowser(async body => {
    sent = body; await pending.promise;
    return {runRef: {...ref}, plan: null, explanation: {state: 'not_projected', reason: 'not_retained'}};
  });
  try {
    await source.connect('bootstrap');
    const reading = source.runPresentation(original, options);
    original.namespaceId = 'changed'; options.locale = 'en';
    assert.deepEqual(sent, {ref, locale: 'ja'});
    pending.resolve();
    assert.deepEqual((await reading).runRef, ref);
  } finally {pending.resolve(); source.close();}
});

test('browser original presentation rejects each foreign reply anchor without retry', async () => {
  let reads = 0, returned: RunReference | undefined;
  const source = presentationBrowser(async body => {
    reads++; assert.deepEqual(body, {ref, locale: 'en'});
    return {runRef: returned, plan: null, explanation: {state: 'not_projected', reason: 'not_retained'}};
  });
  try {
    await source.connect('bootstrap');
    for (const key of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
      returned = {...ref, [key]: key === 'namespaceId' ? 'foreign' : `sha256:${'c'.repeat(64)}`};
      await assert.rejects(source.runPresentation(ref, {locale: 'en'}), {code: 'ExplorerInvalidReply'});
    }
    returned = undefined;
    await assert.rejects(source.runPresentation(ref, {locale: 'en'}), {code: 'ExplorerInvalidReply'});
    assert.equal(reads, 4);
  } finally {source.close();}
});

function presentationBrowser(reply: (body: unknown) => unknown) {
  return createExplorerBrowserSource({origin, now: () => 100, async fetch(url, options) {
    if (requestUrl(url).endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
      scopeEpoch: 1, expiresAt: 200, capabilities: {plan: false, run: true,
        resultMetadata: true, resultPayload: false, control: false, sample: false,
        cancellation: false, checkpointList: false, checkpointReview: false}});
    assert.equal(url, `${origin}/api/read/run-presentation`);
    assert(typeof options?.body === 'string');
    return Response.json({scopeEpoch: 1, data: await reply(JSON.parse(options?.body))});
  }});
}

test('browser launch metadata validates shape and discards a delayed old-scope response', async () => {
  let calls = 0;
  const wait = Promise.withResolvers<void>();
  const source = createExplorerBrowserSource({origin, now: () => 100,
    async fetch(url) {
      calls++;
      if (requestUrl(url).endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
        scopeEpoch: calls, expiresAt: 200, capabilities: {plan: false, run: true,
          resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false,checkpointList:false,checkpointReview:false}});
      await wait.promise; return Response.json({scopeEpoch: 1, data: {kind: 'run', ref}});
    }});
  await source.connect('bootstrap');
  const pending = source.launchView(); await source.connect('next'); wait.resolve();
  await assert.rejects(pending, {code: 'ExplorerStaleScope'});
  assert.equal(calls, 3); source.close();
});

test('browser refuses a forged launch response without using it or requesting a replacement', async () => {
  let calls = 0;
  const source = createExplorerBrowserSource({origin, now: () => 100,
    async fetch(url) {
      calls++;
      if (requestUrl(url).endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
        scopeEpoch: 1, expiresAt: 200, capabilities: {plan: false, run: true,
          resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false,checkpointList:false,checkpointReview:false}});
      return Response.json({scopeEpoch: 1, data: {kind: 'run', ref, start: true}});
    }});
  await source.connect('bootstrap');
  await assert.rejects(source.launchView(), {code: 'ExplorerInvalidReply'});
  assert.equal(calls, 2); source.close();
});

test('presentation timeout retains each pending SDK slot until it actually settles', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  let starts = 0;
  const wait = Promise.withResolvers<void>();
  const h = harness({client: {async attach() {starts++; await wait.promise;
    return {inspect() {assert.fail('timed-out scope must stop before inspect');}};
  }}});
  const session = await h.connect(), pending = [];
  for (let i = 0; i < gatewayLimits.inFlight; i++) pending.push(h.read('run', {ref}, session));
  while (starts !== gatewayLimits.inFlight) await tick();
  t.mock.timers.tick(gatewayLimits.requestMs);
  assert((await Promise.all(pending)).every(reply => reply.status === 504));
  assert.equal((await h.read('run', {ref}, session)).status, 429);
  wait.resolve(); await tick();
  assert.equal((await h.read('payload', {ref}, session)).status, 404);
  assert.equal(starts, gatewayLimits.inFlight);
});

test('body timeout cannot promote a valid JSON prefix to a complete request', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  const h = harness(), session = await h.connect();
  const body = new ReadableStream({start(controller) {
    controller.enqueue(new TextEncoder().encode(JSON.stringify({ref})));
  }});
  const request: RequestInit & {duplex: 'half'} = {method: 'POST', duplex: 'half', body,
    headers: {Host: '127.0.0.1:43210', Origin: origin, 'Content-Type': 'application/json',
      Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf}};
  const pending = h.gateway.fetch(new Request(`${origin}/api/read/run`, request));
  await tick(); t.mock.timers.tick(gatewayLimits.requestMs);
  assert.equal((await pending).status, 504);
  assert.deepEqual(h.calls, []);
});

test('cancellation is opt-in and passes only the immutable original to the existing SDK Owner',async()=>{
  const cancelRef={...ref,cancelId:'exact-cancel',expectedRevision:4},attemptRef={operation:'cancel' as const,attemptId:'exact-attempt'};
  let cancels=0,lookups=0;
  const client={async attach(r: RunReference){assert.deepEqual(r,ref);return{
    async cancel(options: Parameters<Execution['cancel']>[0]){cancels++;assert.deepEqual(options,{cancelId:'exact-cancel',expectedRevision:4,attemptId:'exact-attempt'});
      return{kind:'accepted',attemptRef,cancellation:{kind:'accepted',ref,cancelRef,revision:5}};},
    async lookupCancellation(saved: CancellationReference){lookups++;assert.deepEqual(saved,cancelRef);return{kind:'unknown',cancelRef};},
    status(){assert.fail('no status-based retry');},
  };}};
  const h=harness({client}),s=await h.connect();
  assert.equal(s.body.capabilities.cancellation,false);
  const headers={Cookie:s.cookie,'X-Actql-CSRF':s.body.csrf};
  assert.equal((await h.send('/api/control/cancel',{cancelRef,attemptRef},headers)).status,404);assert.equal(cancels,0);
  const enabled=harness({client,allowCancellation:true}),session=await enabled.connect();
  assert.equal(session.body.capabilities.cancellation,true);
  const auth={Cookie:session.cookie,'X-Actql-CSRF':session.body.csrf};
  assert.equal((await enabled.send('/api/control/cancel',{cancelRef,attemptRef})).status,403);
  assert.equal((await enabled.send('/api/control/cancel',{cancelRef,attemptRef,force:true},auth)).status,400);
  assert.equal(cancels,0);
  const result=await enabled.send('/api/control/cancel',{cancelRef,attemptRef},auth);assert.equal(result.status,200);
  assert.equal((await result.json()).data.outcome.kind,'accepted');assert.equal(cancels,1);
  const lookup=await enabled.send('/api/control/lookup-cancellation',{cancelRef},auth);
  assert.equal((await lookup.json()).data.kind,'unknown');assert.equal(lookups,1);assert.equal(cancels,1);
});

test('browser cancellation keeps the original through lost Gateway ACK and uses only lookup afterward',async()=>{
  const cancelRef={...ref,cancelId:'lost-ack',expectedRevision:4},attemptRef={operation:'cancel' as const,attemptId:'lost-invocation'};
  let requested=0,lookups=0;
  const h=harness({allowCancellation:true,client:{async attach(){return{
    async cancel(){requested++;return{kind:'accepted',attemptRef,cancellation:{ref,cancelRef,kind:'accepted',revision:5}};},
    async lookupCancellation(){lookups++;return{kind:'found',cancellation:{ref,cancelRef,kind:'accepted',revision:5}};},
  };}}});
  let cookie: string | undefined;
  const source=createExplorerBrowserSource({origin,fetch:async(url,options)=>{
    const response = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    if(new URL(requestUrl(url)).pathname==='/api/control/cancel')throw new Error('lost ACK');
    return response;
  }});
  await source.connect(h.gateway.issueBootstrap().bootstrap);
  const observation=await source.cancel({cancelRef,attemptRef});
  assert.deepEqual(observation,{state:'unknown',original:{cancelRef,attemptRef}});assert.equal(requested,1);
  const history=await source.lookupCancellation(cancelRef);assert.equal(history.kind,'found');assert.equal(lookups,1);assert.equal(requested,1);
});

test('Explorer sends one ordinary start and looks up the original after a lost reply', async () => {
  const {connectInProcess} = await import('@actql/sdk');
  const {readySubmission, readySubmissionAttempt, submissionEpoch} = await import('../sdk/submission-fixture.mjs');
  const submissions: AqlSubmission[] = [], lookups: LookupRef[] = [];
  const admission = {ref, durability: 'durable', revision: 1};
  const client = await connectInProcess({mode: 'local', owner: 'local', durability: 'durable'}, {
    async perform(operation, body) {
      if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'explorer-start', capabilities: ['aql-document'],
        submissionEpoch, limits: {maxReadWireBytes: 1024, maxRowWireBytes: 256, maxRowRetainedValueBytes: 512,
          maxRetainedValueBytes: 2048, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
      if (operation === 'submit-intent') {
        assert('submissionRef' in body && 'intentCid' in body && 'kind' in body && body.kind === 'aql');
        const submitted = body as AqlSubmission;
        submissions.push(submitted);
        return readySubmissionAttempt(submitted, admission);
      }
      assert.equal(operation, 'lookup-submission');
      assert('submissionRef' in body);
      lookups.push(body.submissionRef);
      return readySubmission(submissions[0], admission);
    },
  });
  const readOnly = harness({client});
  const enabled = harness({client, allowRunStart: true});
  let cookie: string | undefined, lost = false;
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await enabled.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    if (requestUrl(url).endsWith('/api/control/start-run')) {
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).data, {state: 'ready', ref});
      assert.equal(lost, false);
      lost = true;
      throw new TypeError('Lost reply after original accepted');
    }
    return response;
  }});
  try {
    const defaultSession = await readOnly.connect();
    assert.equal(defaultSession.body.capabilities.runStart, undefined);
    assert.equal((await readOnly.read('prepare-start', {}, defaultSession)).status, 404);
    const enabledSession = await enabled.connect();
    const headers = {Cookie: enabledSession.cookie, 'X-Actql-CSRF': enabledSession.body.csrf};
    const original = (await (await enabled.read('prepare-start', {}, enabledSession)).json()).data;
    const text = 'SELECT 1 AS n', format = 'sql';
    assert.equal((await enabled.send('/api/control/start-run',
      {ref: original, text, format, executionProfile: 'debug'}, headers)).status, 400);
    assert.equal((await enabled.send('/api/control/start-run', {ref: original, text, format})).status, 403);
    assert.deepEqual([...submissions], []);
    assert.equal((await source.connect(enabled.gateway.issueBootstrap().bootstrap)).runStart, true);
    const candidate = await source.prepareStart();
    assert.deepEqual(await source.startRun({ref: candidate, text, format}), {state: 'reply_unknown'});
    assert.equal(lost, true);
    await source.connect(enabled.gateway.issueBootstrap().bootstrap);
    assert.deepEqual(await source.lookupStart(candidate), {state: 'ready', ref});
    assert.deepEqual(lookups, [candidate]);
    assert.deepEqual(submissions.map(body => body.submissionRef), [candidate]);
    assert.equal(submissions[0].input.text, text);
    assert.equal(Object.hasOwn(submissions[0], 'executionProfile'), false);
  } finally {
    source.close();
    await enabled.gateway.close();
    await readOnly.gateway.close();
    await client.close();
  }
});

test('Explorer starts Debug only from the current checked Plan for the same original input', async () => {
  const {connectInProcess} = await import('@actql/sdk');
  const {readySubmissionAttempt, submissionEpoch} = await import('../sdk/submission-fixture.mjs');
  const plan = gatewayLaunchPlanFixture(), text = 'SELECT 1 AS n', format = 'sql';
  const programDefinitionCid = plan.logical_map.program_definition_cid;
  const submissions: AqlSubmission[] = [];
  let admitted = true, plans = 0, cookie: string | undefined;
  const client = await connectInProcess({mode: 'local', owner: 'local', durability: 'durable'}, {
    async perform(operation, body) {
      if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'explorer-debug-start', capabilities: ['aql-document', 'debug-operation-boundaries'],
        submissionEpoch, limits: {maxReadWireBytes: 65536, maxRowWireBytes: 256, maxRowRetainedValueBytes: 512,
          maxRetainedValueBytes: 2048, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
      if (operation === 'plan') {
        plans++;
        return {...plan, capabilities: {...plan.capabilities, ...(admitted ? {debug_entry: true} : {})}};
      }
      assert.equal(operation, 'submit-intent');
      assert('submissionRef' in body && 'intentCid' in body && 'kind' in body && body.kind === 'aql');
      const submitted = body as AqlSubmission;
      submissions.push(submitted);
      return readySubmissionAttempt(submitted, {ref, durability: 'durable', revision: 2});
    },
  });
  const enabled = harness({client, allowRunStart: true, allowDebugResume: true});
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await enabled.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    return response;
  }});
  try {
    const capabilities = await source.connect(enabled.gateway.issueBootstrap().bootstrap);
    assert.equal(capabilities.runStart, true);
    assert.equal(capabilities.debugResume, true);
    assert.equal((await source.plan(text, {format})).debugEntry, true);
    const executionProfile = 'debug' as const;
    const deniedRef = await source.prepareStart();
    admitted = false;
    assert.deepEqual(await source.startRun({ref: deniedRef, text, format, executionProfile, programDefinitionCid}),
      {state: 'not_accepted'});
    admitted = true;
    const foreignRef = await source.prepareStart();
    assert.deepEqual(await source.startRun({ref: foreignRef, text, format, executionProfile,
      programDefinitionCid: `sha256:${'0'.repeat(64)}`}), {state: 'not_accepted'});
    assert.deepEqual([...submissions], []);
    const original = await source.prepareStart();
    assert.deepEqual(await source.startRun({ref: original, text, format, executionProfile, programDefinitionCid}),
      {state: 'ready', ref});
    assert.deepEqual(submissions.map(body => body.submissionRef), [original]);
    assert.equal(submissions[0].input.text, text);
    assert.equal(submissions[0].executionProfile, 'debug');
    assert.equal(plans, 4);
  } finally {
    source.close();
    await enabled.gateway.close();
    await client.close();
  }
});

test('browser original Plan and observation reads refuse a foreign Run reply', async () => {
  const h = harness({client: {async attach(original) {
    assert.deepEqual(original, ref);
    return {plan() {return {version: 'actql-run-plan-view/0.1', run_ref: ref,
      plan_view: gatewayLaunchPlanFixture()};}, inspect() {
      return {...runObservationFixture(), run_ref: ref};
    }};
  }}});
  let cookie: string | undefined, foreign = false;
  const source = createExplorerBrowserSource({origin, async fetch(url, options) {
    const response = await h.gateway.fetch(localBrowserRequest(url, options, cookie));
    cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
    if (foreign && !requestUrl(url).endsWith('/api/session')) {
      assert.equal(response.status, 200);
      const answer = await response.json();
      answer.data.runRef = {...ref, runDefinitionCid: `sha256:${'f'.repeat(64)}`};
      return Response.json(answer);
    }
    return response;
  }});
  try {
    await source.connect(h.gateway.issueBootstrap().bootstrap);
    for (const kind of ['runPlan', 'observe'] as const) {
      foreign = false;
      assert.deepEqual((await source[kind](ref)).runRef, ref);
      foreign = true;
      await assert.rejects(source[kind](ref), {code: 'ExplorerInvalidReply'});
    }
  } finally {source.close(); await h.gateway.close();}
});
