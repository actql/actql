// Actual imported retained-read service with explicit workspace/Core DATA
// ports. These controls do not qualify a Common supplier or ordinary Host.
import assert from 'node:assert/strict';
import test from 'node:test';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
import {createServer, request as sendRequest} from 'node:http';
import {installClientRunExplanation} from './client-run-explanation.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {runExplanation, explanationFacts} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
const connection = Object.freeze({mode: 'local', owner: 'local',
  consentRefs: Object.freeze([]), runners: Object.freeze([])});
const request = () => ({connection, principalId: 'original-caller',
  ref: structuredClone(runExplanation.run_ref), maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64});
function fixture(overrides = {}) {
  const calls = [], held = new Map();
  const original = {definitionWire: 'original-definition', admissionEvidenceWire: 'original-evidence',
    programDefinitionCid: explanationFacts.program_definition_cid,
    parameterValuesCid: explanationFacts.parameter_values_cid, factsWire: JSON.stringify(explanationFacts)};
  const extent = Object.freeze({storedBytes: 16384});
  const workspace = {
    beginExplanation(input) {
      calls.push('begin'); assert.equal(held.has(input), false);
      const ref = Object.freeze({...input.ref});
      const operation = Object.freeze({principalId: input.principalId, purpose: 'run-explanation', indexKey: ref});
      held.set(input, {operation, selected: Object.freeze({...input, ref})});
      return operation;
    },
    explanationRequest(input) {return held.get(input).selected;},
    prepareExplanation(input, bytes) {calls.push('prepare'); assert(held.has(input)); assert.equal(bytes, 16384);},
    renderExplanation(input, value) {
      calls.push('read'); assert(held.has(input)); assert.deepEqual(value, original);
      return JSON.stringify(value.factsWire === undefined ? {...runExplanation,
        explanation: {state: 'not_projected', reason: 'not_retained'}} : runExplanation);
    },
    close(input, primary) {calls.push('close'); assert(held.has(input)); held.delete(input);},
    ...overrides.workspace,
  };
  const authorize = async (selected, operation) => {
    calls.push('current'); assert.equal(operation, held.values().next().value.operation); return true;
  };
  const authorizeEgress = async (selected, operation) => {
    calls.push('egress'); assert.equal(operation, held.values().next().value.operation); return true;
  };
  const handler = installClientRunExplanation({authorize, authorizeEgress,
    probeOriginal: () => {calls.push('probe'); return extent;},
    lookupOriginal: (ref, bound) => {calls.push('lookup'); assert.equal(bound, extent); return {...original};},
    ...overrides, readWorkspace: overrides.readWorkspace ?? workspace});
  return {service: (input, consume = view => structuredClone(view)) => handler(input, consume),
    handler, calls, held, original, workspace};
}

test('retained explanation reads exact originals between current and egress checks', async () => {
  const f = fixture(); assert.deepEqual(await f.service(request()), runExplanation);
  assert.deepEqual(f.calls, ['begin', 'egress', 'current', 'probe', 'prepare', 'lookup',
    'read', 'egress', 'current', 'lookup', 'close']);
  assert.equal(f.held.size, 0);
});

test('missing old/Normal facts disclose NotProjected only after both authorizations', async () => {
  const f = fixture(); f.original.factsWire = undefined;
  assert.deepEqual((await f.service(request())).explanation, {state: 'not_projected', reason: 'not_retained'});
  for (const key of ['authorize', 'authorizeEgress']) {
    const denied = fixture({[key]: async () => false});
    await assert.rejects(denied.service(request()), {code: 'RunObservationAccessDenied'});
    assert.equal(denied.calls.includes('probe'), false); assert.equal(denied.calls.includes('read'), false);
    if (key === 'authorizeEgress') assert.equal(denied.calls.includes('current'), false);
    assert.equal(denied.held.size, 0);
  }
});

test('revocation and replacement after read refuse disclosure, including missing evidence changes', async () => {
  for (const mode of ['current', 'egress', 'definition', 'program', 'parameters', 'evidence', 'facts', 'old-added']) {
    let count = 0, f;
    const second = async () => {
      if (++count !== 2) return true;
      if (mode === 'current' || mode === 'egress') return false;
      const field = {definition: 'definitionWire', program: 'programDefinitionCid',
        parameters: 'parameterValuesCid', evidence: 'admissionEvidenceWire', facts: 'factsWire', 'old-added': 'factsWire'}[mode];
      f.original[field] = 'replacement'; return true;
    };
    f = fixture({[mode === 'egress' ? 'authorizeEgress' : 'authorize']: second});
    if (mode === 'old-added') f.original.factsWire = undefined;
    await assert.rejects(f.service(request()), {code: mode === 'current' || mode === 'egress'
      ? 'RunObservationAccessDenied' : 'RunExplanationEncodingRejected'}, mode);
    assert.equal(f.held.size, 0);
  }
});

test('budget and encoding refusals stay named failures, never truncation or NotProjected', async () => {
  for (const [wire, code] of [['x'.repeat(65537), 'RunExplanationReadLimit'],
    ['{', 'RunExplanationEncodingRejected'], [JSON.stringify({...runExplanation, preview: {}}), 'RunExplanationEncodingRejected']]) {
    const f = fixture({workspace: {renderExplanation: () => wire}});
    await assert.rejects(f.service(request()), {code}); assert.equal(f.held.size, 0);
  }
  const primary = Object.assign(new Error('Actual read construction refused'), {code: 'ActualConstructionLimit'});
  const f = fixture({workspace: {prepareExplanation() {throw primary;}}});
  await assert.rejects(f.service(request()), error => error === primary);
  assert.equal(f.calls.includes('lookup'), false, 'full native row read follows actual constructor admission');
  assert.equal(f.held.size, 0);
});

test('signal cancellation and callback mutation retain one original read without cancelling Run', async () => {
  const given = request(), controller = new AbortController(); let reads = 0;
  const f = fixture({authorize: async selected => {
    given.ref.namespaceId = 'changed'; given.maxWireBytes = 1;
    assert.equal(selected.maxWireBytes, 65536); return true;
  }, workspace: {renderExplanation(input) {
    reads++; assert.deepEqual(f.workspace.explanationRequest(input).ref, runExplanation.run_ref);
    controller.abort(); return JSON.stringify(runExplanation);
  }}});
  await assert.rejects(f.service({...given, signal: controller.signal}), {name: 'AbortError'});
  assert.equal(reads, 1); assert.equal(f.held.size, 0);
  const aborted = fixture(); await assert.rejects(aborted.service({...request(), signal: AbortSignal.abort()}));
  assert.deepEqual(aborted.calls, []);
});

test('retained service captures one workspace method and immutable comparison scalars before callbacks', async () => {
  let methodReads = 0, f;
  const base = fixture();
  const workspace = {...base.workspace, get renderExplanation() {
    methodReads++;
    return function () {assert.equal(this, workspace); return JSON.stringify(runExplanation);};
  }};
  f = fixture({readWorkspace: workspace, authorize: async () => true, authorizeEgress: async () => true});
  assert.deepEqual(await f.service(request()), runExplanation);
  assert.equal(methodReads, 1);
  let calls = 0;
  const changed = fixture({authorize: async () => {
    if (++calls === 2) changed.original.definitionWire = 'mutated-same-object'; return true;
  }, lookupOriginal: () => changed.original});
  await assert.rejects(changed.service(request()), {code: 'RunExplanationEncodingRejected'});
});

test('missing bounded original lookup or read admission refuses installation instead of fabricating absence', () => {
  for (const configuration of [{probeOriginal: undefined}, {lookupOriginal: undefined}, {readWorkspace: {}}]) {
    assert.throws(() => fixture(configuration), {name: 'TypeError', message: 'InvalidClientRunExplanationInstallation'});
  }
});

test('same read backing survives asynchronous consumption and returns only after its original output frame unwinds', async () => {
  const f = fixture(); let enter, release;
  const entered = new Promise(resolve => {enter = resolve;});
  const completion = new Promise(resolve => {release = resolve;});
  const pending = f.service(request(), async view => {
    assert.deepEqual(view, runExplanation); assert.equal(f.held.size, 1);
    enter(); await completion;
    assert.equal(f.calls.includes('close'), false);
    return structuredClone(view);
  });
  await entered;
  assert.equal(f.held.size, 1); assert.equal(f.calls.includes('close'), false);
  release(); assert.deepEqual(await pending, runExplanation);
  assert.equal(f.held.size, 0); assert.equal(f.calls.filter(x => x === 'close').length, 1);
});

test('consumption failure retains its original primary and pending cleanup duty without another read', async () => {
  const primary = new Error('AuthoredPhysicalOutputPending'); let observed;
  const cleanup = Object.assign(new Error('AuthoredReadCleanupPending'), {cleanupPending: true, primaryFailure: primary});
  const f = fixture({workspace: {close(input, cause) {observed = cause; throw cleanup;}}});
  await assert.rejects(f.service(request(), () => {throw primary;}), error => error === cleanup);
  assert.equal(observed, primary); assert.equal(f.calls.filter(x => x === 'read').length, 1);
  assert.equal(f.held.size, 1, 'the pending original stays owned; no fake release/ACK');
});

// Actual ingress functions, with explicit Request/response ports. The response
// callback/close controls exercise ownership ordering, not native socket ACKs.
function responseFixture() {
  const response = new EventEmitter(); let acknowledge, entered;
  const started = new Promise(resolve => {entered = resolve;});
  Object.assign(response, {closed: false, destroyed: false, headersSent: false,
    writableEnded: false, writeHead(status) {assert.equal(status, 200); this.headersSent = true;},
    end(bytes, callback) {this.writableEnded = true; acknowledge = callback; entered(bytes);},
    destroy() {this.destroyed = true;}});
  return {response, started, acknowledge(error) {acknowledge(error);},
    close() {response.closed = true; response.emit('close');}};
}
function httpRead(f, response) {
  const {principalId, ...body} = request(), events = [];
  const input = Readable.from([Buffer.from(JSON.stringify(body))]);
  Object.assign(input, {method: 'POST', url: '/actql/client/0.1/run-explanation',
    headers: {'content-type': 'application/json'}});
  const handler = createClientHttpHandler({authenticate: () => principalId,
    authorizeConnection: () => true, runExplanation: f.handler,
    prepareRequest: (operation, original) => {
      assert.equal(operation, 'run-explanation');
      return {body: original, bindRequest() {}, beforeReply() {events.push('reply');},
        finish(terminal) {events.push(terminal); assert.equal(f.held.size, 0);}};
    }});
  return {completion: handler(input, response), events};
}

test('HTTP explanation ingress retains its original read until end consumes the bytes', async () => {
  const f = fixture(), output = responseFixture();
  const {completion, events} = httpRead(f, output.response);
  const bytes = await output.started;
  assert.deepEqual(JSON.parse(bytes.toString()), runExplanation);
  assert.equal(f.held.size, 1); assert.deepEqual(events, ['reply']);
  assert.equal(f.calls.includes('close'), false);
  output.acknowledge(); await completion;
  assert.equal(f.held.size, 0); assert.deepEqual(events, ['reply', 'returned']);
  assert.equal(output.response.listenerCount('error'), 0);
  assert.equal(output.response.listenerCount('close'), 0);
});

test('HTTP explanation ingress preserves a failed end through physical close before refund', async () => {
  let cause; const primary = new Error('OriginalEndFailure');
  const f = fixture({workspace: {close(input, error) {cause = error; f.held.delete(input);}}});
  const output = responseFixture(), {completion, events} = httpRead(f, output.response);
  await output.started; output.acknowledge(primary);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(output.response.destroyed, true);
  assert.equal(f.held.size, 1); assert.deepEqual(events, ['reply']);
  output.close(); await completion;
  assert.equal(cause, primary); assert.equal(f.held.size, 0);
  assert.deepEqual(events, ['reply', 'failed']);
});

test('InProcess explanation ingress hands off an independent caller value before returning the read', async () => {
  const f = fixture(); let hostView, callerView;
  const port = createNodeInProcessClientHost({authenticate: () => 'original-caller',
    authorizeConnection: () => true, negotiate() {assert.fail('not a connect');}, maxRowBytes: 1024,
    runExplanation(input, consume) {return f.handler(input, view => {
      hostView = view; assert.equal(f.held.size, 1);
      callerView = consume(view); assert.notEqual(callerView, view);
      assert.notEqual(callerView.explanation.facts, view.explanation.facts);
      assert.equal(f.held.size, 1); return callerView;
    });}});
  const {principalId, ...body} = request();
  const result = await port.perform('run-explanation', body);
  assert.equal(result, callerView); assert.deepEqual(result, runExplanation);
  result.run_ref.namespaceId = 'caller-owned';
  assert.equal(hostView.run_ref.namespaceId, runExplanation.run_ref.namespaceId);
  assert.equal(f.held.size, 0); assert.equal(f.calls.filter(x => x === 'close').length, 1);
});

test('HTTP explanation ingress uses actual native response completion before returning the read', async t => {
  let response, finished = false;
  const f = fixture({workspace: {close(input, cause) {
    assert.equal(cause, undefined); assert.equal(response.writableFinished, true);
    f.held.delete(input);
  }}});
  const handler = createClientHttpHandler({authenticate: () => 'original-caller',
    authorizeConnection: () => true, runExplanation: f.handler,
    prepareRequest: (_operation, original) => ({body: original, bindRequest() {}, beforeReply() {},
      finish(terminal) {assert.equal(terminal, 'returned'); assert.equal(f.held.size, 0); finished = true;}})});
  let handling;
  const server = createServer((incoming, outgoing) => {
    response = outgoing; handling = handler(incoming, outgoing);
  });
  t.after(async () => {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const {principalId, ...body} = request(), bytes = Buffer.from(JSON.stringify(body));
  const value = await new Promise((resolve, reject) => {
    const original = sendRequest({host: '127.0.0.1', port: server.address().port,
      path: '/actql/client/0.1/run-explanation', method: 'POST',
      headers: {'content-type': 'application/json', 'content-length': bytes.byteLength}}, incoming => {
      const chunks = [];
      incoming.on('data', chunk => chunks.push(chunk)); incoming.once('error', reject);
      incoming.once('end', () => {
        try {assert.equal(incoming.statusCode, 200); resolve(JSON.parse(Buffer.concat(chunks)));}
        catch (cause) {reject(cause);}
      });
    });
    original.once('error', reject); original.end(bytes);
  });
  await handling;
  assert.deepEqual(value, runExplanation); assert.equal(finished, true); assert.equal(f.held.size, 0);
});

test('current read loss after an Account callback refuses before the original Journal probe', async () => {
  const primary = new Error('OriginalReadOwnerBecameStale'); let stale = false, f;
  f = fixture({workspace: {explanationRequest(input) {
    if (stale) throw primary;
    return f.held.get(input).selected;
  }}, authorizeEgress: async () => {stale = true; return true;}});
  await assert.rejects(f.service(request()), error => error === primary);
  assert.equal(f.calls.includes('probe'), false); assert.equal(f.held.size, 0);
});

// A test-only observer exposes the actual closure before startup is acquired.
// The entire Host module and its method execute unchanged; no private function
// is reconstructed, and no runtime, resource admission or cleanup ACK is issued.
test('actual Host explanation getter refuses a loan changed by its current callback', async () => {
  const {registerHooks} = await import('node:module');
  const hostUrl = new URL('./embedded-local.mjs?explanation-current-fence', import.meta.url).href;
  const observerKey = Symbol.for('actql.test.explanation-current-fence');
  const stop = new Error('StopBeforeHostStartup');
  let observed = false;
  globalThis[observerKey] = ({preparation, record, selectRuntime}) => {
    observed = true;
    const runtime = {}, prepared = {}, original = {};
    selectRuntime(runtime);
    const changes = {
      unchanged() {},
      deleted(run) {record.computeRuns.delete(prepared);},
      replacement(run) {record.computeRuns.set(prepared, {...run});},
      runtime(run) {run.runtime = {};},
      hostRuntime() {selectRuntime({});},
      unfunded(run) {run.preparationFunded = false;},
      closed(run) {run.closed = true;},
      prepared(run) {run.prepared = {};},
      failed(run) {run.failure = undefined;},
    };
    for (const [name, change] of Object.entries(changes)) {
      selectRuntime(runtime);
      let reads = 0;
      const run = {prepared, runtime, preparationFunded: true, closed: false,
        manager: {originalExplanationPreparation(value) {
          assert.strictEqual(value, prepared);
          reads++;
          change(run);
          return original;
        }}};
      record.computeRuns = new WeakMap([[prepared, run]]);
      if (name === 'unchanged') {
        assert.strictEqual(preparation.managedComputeExplanationPreparation(runtime, prepared), original);
      } else {
        assert.throws(() => preparation.managedComputeExplanationPreparation(runtime, prepared),
          {code: 'ForeignInstalledComputeRun'}, name);
      }
      assert.equal(reads, 1, `${name}: do not re-read or reissue the original loan`);
    }
    record.computeRuns = undefined;
    selectRuntime(undefined);
    throw stop;
  };
  const hooks = registerHooks({load(url, context, next) {
    const loaded = next(url, context);
    if (url !== hostUrl) return loaded;
    const source = String(loaded.source);
    const beforeStartup = '  const sourceInitializationBorrow = preparation.borrowSourceInitializationMaterial;';
    assert.equal(source.split(beforeStartup).length, 2, 'observe the complete Host before startup');
    return {...loaded, source: source.replace(beforeStartup,
      `  globalThis[Symbol.for('actql.test.explanation-current-fence')]({preparation, record,\n` +
      '    selectRuntime(value) {moon = value;}});\n' + beforeStartup)};
  }});
  try {
    const {connectEmbeddedLocal} = await import(hostUrl);
    await assert.rejects(connectEmbeddedLocal({}), error => error === stop);
    assert.equal(observed, true);
  } finally {
    hooks.deregister();
    delete globalThis[observerKey];
  }
});
