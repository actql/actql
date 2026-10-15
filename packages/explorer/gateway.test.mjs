import assert from 'node:assert/strict';
import test from 'node:test';
import {createExplorerGateway, gatewayLimits, startExplorerGateway} from './gateway.mjs';
import {createExplorerBrowserSource} from './browser-source.mjs';
import {gatewayLaunchPlanFixture} from './gateway-launch.fixture.mjs';
import {observationRef, runObservationFixture, ownerObservationFixture}
  from '../explorer-ui/run-observation.fixture.mjs';

test('current observation endpoint reads only the same original Run and one Owner-local page', async () => {
  const calls=[], original=observationRef();
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
test('foreign and delayed Owner replies cannot escape current observation scope', async () => {
  const original=observationRef();let release;
  const pending=new Promise(resolve=>release=resolve);
  const h=harness({client:{attach:async()=>({inspect:async()=>runObservationFixture(),
    observeOwners:async()=>pending})}});
  const session=await h.connect(),answer=h.read('observation',{ref:original},session);
  await tick();h.gateway.invalidateScope();release(ownerObservationFixture());
  assert.notEqual((await answer).status,200);
  const foreign=ownerObservationFixture();foreign.ref.namespaceId='foreign';
  const f=harness({client:{attach:async()=>({inspect:async()=>runObservationFixture(),observeOwners:async()=>foreign})}});
  assert.notEqual((await f.read('observation',{ref:original},await f.connect())).status,200);
});

const origin = 'http://127.0.0.1:43210';
const ref = {namespaceId: 'original', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const tick = () => new Promise(resolve => setImmediate(resolve));
function harness(options = {}) {
  const calls = [];
  const client = {async attach(selected) {
    calls.push(['attach', structuredClone(selected)]);
    return {inspect(limits) {calls.push(['inspect', limits]); return {status: 'fixture'};},
      result(name) {calls.push(['result', name]); return {
        describe() {calls.push(['describe']); return {name, marker: '<script>not HTML</script> e\u0301\r\n'};},
        rows() {assert.fail('no payload open');},
      };},
    };
  }, close() {assert.fail('borrowed client is not owned by Gateway');},
  submit() {assert.fail('no business work');}, cancel() {assert.fail('no cancellation');}};
  const gateway = createExplorerGateway({client, origin, ...options});
  const send = (path, body, headers = {}, method = 'POST') => gateway.fetch(new Request(`${origin}${path}`, {
    method, headers: {Host: '127.0.0.1:43210', Origin: origin,
      'Content-Type': 'application/json', ...headers},
    ...(method === 'POST' ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {}),
  }));
  async function connect() {
    const issued = gateway.issueBootstrap();
    const response = await send('/api/session', {bootstrap: issued.bootstrap});
    assert.equal(response.status, 200);
    return {body: await response.json(), cookie: response.headers.get('set-cookie').split(';')[0], issued};
  }
  const read = (kind, body, session, more = {}) => send(`/api/read/${kind}`, body,
    {Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf, ...more});
  return {gateway, send, connect, read, calls, client};
}

test('expired cancellation session cannot dispatch after original attach awaits', async () => {
  let now = 1000, entered, release, cancellations = 0;
  const attached = new Promise(resolve => {entered = resolve;});
  const pendingAttach = new Promise(resolve => {release = resolve;});
  const original = {cancelRef: {...ref, cancelId: 'expired-session-cancel', expectedRevision: 7},
    attemptRef: {operation: 'cancel', attemptId: 'expired-session-attempt'}};
  const h = harness({allowCancellation: true, now: () => now, sessionMs: 20,
    client: {async attach(selected) {assert.deepEqual(selected, ref); entered(); return pendingAttach;}}});
  const session = await h.connect();
  const answer = h.send('/api/control/cancel', original,
    {Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf});
  await attached; now += 21;
  release({async cancel() {cancellations++; return {kind: 'accepted', attemptRef: original.attemptRef,
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
    assert.throws(() => harness({sessionMs}), {code: 'ExplorerInvalidGateway'});
  }
});

test('direct Program launch uses only the existing static Plan Owner after session and CSRF', async () => {
  const input = {kind: 'program', text: 'SELECT 1 AS n', format: 'sql'}, calls = [];
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
  for (const format of ['aql', 'aql-text']) {
    const calls = [], view = gatewayLaunchPlanFixture();
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
  const original = {...ref}, calls = [], view = gatewayLaunchPlanFixture();
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
    const calls = [], view = gatewayLaunchPlanFixture();
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
    let release, started;
    const began = new Promise(resolve => {started = resolve;});
    const wait = new Promise(resolve => {release = resolve;});
    const h = harness({client: {async attach() {started(); await wait;
      if (failed) throw Object.assign(new Error('secret old Host token'), {status: 401});
      return {inspect() {assert.fail('scope ended before inspect');}};
    }}});
    const old = await h.connect(), pending = h.read('run', {ref}, old);
    await began;
    h.gateway.invalidateScope();
    const current = await h.connect();
    release();
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
  let release, starts = 0;
  const wait = new Promise(resolve => {release = resolve;});
  const h = harness({client: {async attach() {starts++; await wait;
    return {inspect() {return {};}};
  }}});
  const session = await h.connect(), reads = [];
  for (let i = 0; i < gatewayLimits.inFlight; i++) reads.push(h.read('run', {ref}, session));
  while (starts !== gatewayLimits.inFlight) await tick();
  assert.equal((await h.read('run', {ref}, session)).status, 429);
  release();
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
  const gateway = await startExplorerGateway({client: {async attach() {
    attaches++; return {inspect() {return {marker: 'loopback fixture'};}};
  }, close() {assert.fail('borrowed client stays open');}}});
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
  assert.match(response.headers.get('set-cookie'), /Path=\/api; HttpOnly; SameSite=Strict/u);
  const reply = await fetch(`${gateway.origin}/api/read/run`, {method: 'POST',
    headers: {Origin: gateway.origin, 'Content-Type': 'application/json',
      Cookie: response.headers.get('set-cookie').split(';')[0], 'X-Actql-CSRF': session.csrf},
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
    let release; let calls = 0;
    const wait = new Promise(resolve => {release = resolve;});
    const source = createExplorerBrowserSource({origin, now: () => 100,
      async fetch(url, options) {
        calls++;
        assert.equal(options.redirect, 'error'); assert.equal(options.credentials, 'same-origin');
        assert(!url.includes('secret')); assert(!Object.hasOwn(options.headers, 'Authorization'));
        if (url.endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
          scopeEpoch: calls, expiresAt: 200, capabilities: {plan: false, run: true,
            resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false}});
        await wait;
        return failed ? Response.json({error: 'old'}, {status: 401}) :
          Response.json({scopeEpoch: 1, data: {secret: 'old-scope'}});
      }});
    await source.connect('bootstrap');
    const pending = source.inspect(ref);
    await source.connect('new-bootstrap');
    release();
    await assert.rejects(pending, {code: 'ExplorerStaleScope'});
    assert.equal(calls, 3);
    source.close();
    await assert.rejects(source.inspect(ref), {code: 'ExplorerSessionExpired'});
    assert.equal(calls, 3);
  }
});

test('browser launch metadata validates shape and discards a delayed old-scope response', async () => {
  let release, calls = 0;
  const wait = new Promise(resolve => {release = resolve;});
  const source = createExplorerBrowserSource({origin, now: () => 100,
    async fetch(url) {
      calls++;
      if (url.endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
        scopeEpoch: calls, expiresAt: 200, capabilities: {plan: false, run: true,
          resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false}});
      await wait; return Response.json({scopeEpoch: 1, data: {kind: 'run', ref}});
    }});
  await source.connect('bootstrap');
  const pending = source.launchView(); await source.connect('next'); release();
  await assert.rejects(pending, {code: 'ExplorerStaleScope'});
  assert.equal(calls, 3); source.close();
});

test('browser refuses a forged launch response without using it or requesting a replacement', async () => {
  let calls = 0;
  const source = createExplorerBrowserSource({origin, now: () => 100,
    async fetch(url) {
      calls++;
      if (url.endsWith('/api/session')) return Response.json({csrf: 'a'.repeat(43),
        scopeEpoch: 1, expiresAt: 200, capabilities: {plan: false, run: true,
          resultMetadata: true, resultPayload: false, control: false, sample: false, cancellation: false}});
      return Response.json({scopeEpoch: 1, data: {kind: 'run', ref, start: true}});
    }});
  await source.connect('bootstrap');
  await assert.rejects(source.launchView(), {code: 'ExplorerInvalidReply'});
  assert.equal(calls, 2); source.close();
});

test('presentation timeout retains each pending SDK slot until it actually settles', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  let release, starts = 0;
  const wait = new Promise(resolve => {release = resolve;});
  const h = harness({client: {async attach() {starts++; await wait;
    return {inspect() {assert.fail('timed-out scope must stop before inspect');}};
  }}});
  const session = await h.connect(), pending = [];
  for (let i = 0; i < gatewayLimits.inFlight; i++) pending.push(h.read('run', {ref}, session));
  while (starts !== gatewayLimits.inFlight) await tick();
  t.mock.timers.tick(gatewayLimits.requestMs);
  assert((await Promise.all(pending)).every(reply => reply.status === 504));
  assert.equal((await h.read('run', {ref}, session)).status, 429);
  release(); await tick();
  assert.equal((await h.read('payload', {ref}, session)).status, 404);
  assert.equal(starts, gatewayLimits.inFlight);
});

test('body timeout cannot promote a valid JSON prefix to a complete request', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  const h = harness(), session = await h.connect();
  const body = new ReadableStream({start(controller) {
    controller.enqueue(new TextEncoder().encode(JSON.stringify({ref})));
  }});
  const pending = h.gateway.fetch(new Request(`${origin}/api/read/run`, {method: 'POST',
    duplex: 'half', body, headers: {Host: '127.0.0.1:43210', Origin: origin,
      'Content-Type': 'application/json', Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf}}));
  await tick(); t.mock.timers.tick(gatewayLimits.requestMs);
  assert.equal((await pending).status, 504);
  assert.deepEqual(h.calls, []);
});

test('cancellation is opt-in and passes only the immutable original to the existing SDK Owner',async()=>{
  const cancelRef={...ref,cancelId:'exact-cancel',expectedRevision:4},attemptRef={operation:'cancel',attemptId:'exact-attempt'};
  let cancels=0,lookups=0;
  const client={async attach(r){assert.deepEqual(r,ref);return{
    async cancel(options){cancels++;assert.deepEqual(options,{cancelId:'exact-cancel',expectedRevision:4,attemptId:'exact-attempt'});
      return{kind:'accepted',attemptRef,cancellation:{kind:'accepted',ref,cancelRef,revision:5}};},
    async lookupCancellation(saved){lookups++;assert.deepEqual(saved,cancelRef);return{kind:'unknown',cancelRef};},
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
  const cancelRef={...ref,cancelId:'lost-ack',expectedRevision:4},attemptRef={operation:'cancel',attemptId:'lost-invocation'};
  let requested=0,lookups=0;
  const h=harness({allowCancellation:true,client:{async attach(){return{
    async cancel(){requested++;return{kind:'accepted',attemptRef,cancellation:{ref,cancelRef,kind:'accepted',revision:5}};},
    async lookupCancellation(){lookups++;return{kind:'found',cancellation:{ref,cancelRef,kind:'accepted',revision:5}};},
  };}}});
  let cookie;
  const source=createExplorerBrowserSource({origin,fetch:async(url,options)=>{
    const headers={...options.headers,Host:'127.0.0.1:43210',Origin:origin,...(cookie?{Cookie:cookie}:{})};
    const response=await h.gateway.fetch(new Request(url,{...options,headers}));
    if(response.headers.get('set-cookie'))cookie=response.headers.get('set-cookie').split(';')[0];
    if(new URL(url).pathname==='/api/control/cancel')throw new Error('lost ACK');
    return response;
  }});
  await source.connect(h.gateway.issueBootstrap().bootstrap);
  const observation=await source.cancel({cancelRef,attemptRef});
  assert.deepEqual(observation,{state:'unknown',original:{cancelRef,attemptRef}});assert.equal(requested,1);
  const history=await source.lookupCancellation(cancelRef);assert.equal(history.kind,'found');assert.equal(lookups,1);assert.equal(requested,1);
});
