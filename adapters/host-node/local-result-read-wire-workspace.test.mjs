import assert from 'node:assert/strict';
import test from 'node:test';
import resources from './ordinary-node-resource-runtime.cjs';
import {createLocalResultReadWorkspace} from './local-result-read-workspace.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

// Actual JS workspace/open/cleanup adapter with explicit Core ports. This
// does not issue a Common original or certify physical reader/FD completion.
const ok = value => ({$tag: 1, _0: value});
function fixture({polls = 2, refuse, current = () => {}, payloadBytes = 8192, explanation = false,
  render = () => ok('original-closed-view')} = {}) {
  const calls = [], request = explanation ? Object.freeze({principalId: 'original-reader',
    ref: Object.freeze({namespaceId: 'original-namespace', authorityScopeCid: 'original-scope',
      runDefinitionCid: 'original-run'}), maxWireBytes: 4096, maxNodes: 128, maxDepth: 32})
    : {}, parent = {}, runtime = {};
  let ports, high = 0, count = 0;
  const method = (name, body) => runtime[name] = function(...args) {
    assert.equal(this, runtime);
    calls.push([name, ...args]);
    return body(...args);
  };
  runtime.clientLocalResourcePolicyOriginal = () => ({});
  runtime.clientLocalPreparationResourceLimits = () => [100000n, 1n, 1n, 0n, 1048576n, 1048576n];
  runtime.clientProgramPrepareLocalPreparationAdmission = (original, input) => {
    ports = resources.prepareOriginalLocalPreparationPorts(original, input);
    assert.equal(ports.status(0), 0);
    return ok({});
  };
  runtime.clientProgramBeginRequestPreparation = () => ok(parent);
  method('clientProgramBeginRequestExplanationRead', (p, r) => {
    assert.equal(p, parent); assert.equal(r, request);
    return refuse === undefined ? ok(undefined) : {$tag: 0, _0: refuse};
  });
  method('clientProgramReserveRequestExplanationRead', (p, r, bytes, maxBytes, nodes, depth) => {
    assert.equal(p, parent); assert.equal(r, request);
    assert.equal(bytes, 2048); assert.equal(maxBytes, 4096);
    assert.equal(nodes, 128); assert.equal(depth, 32);
    return ok(undefined);
  });
  method('clientProgramReadRequestExplanation', render);
  runtime.clientProgramRequestExplanationReadIssueCode = () => 'RunExplanationReadCapacity';
  runtime.clientProgramAbortRequestPreparation = value => {
    assert.equal(value, parent);
    calls.push(['abort']);
    assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
    assert.equal(ports.status(2), 0);
    return ok(undefined);
  };
  method('clientProgramReserveRequestResultRead', () => ok(64));
  method('clientProgramBeginRequestResultReadWire', (p, r, bytes, rows) => {
    assert.equal(p, parent); assert.equal(r, request);
    assert.equal(bytes, BigInt(payloadBytes)); assert.equal(rows, 1);
    return ok(undefined);
  });
  method('clientProgramGrowRequestResultReadFrame', (p, r, units) => {
    assert.equal(p, parent); assert.equal(r, request);
    high = units;
    return ok({_0: high, _1: 64});
  });
  method('clientProgramBeginRequestResultReadWireRow', (p, r, wire) => {
    assert.equal(p, parent); assert.equal(r, request); assert.equal(typeof wire, 'string');
    return ok(undefined);
  });
  method('clientProgramAdvanceRequestResultReadWireRow', (p, r, quantum) => {
    assert.equal(p, parent); assert.equal(r, request); assert.equal(quantum, 4096);
    if (refuse) return {$tag: 0, _0: refuse};
    return ok({_0: ++count >= polls, _1: high, _2: 64});
  });
  for (const name of ['ReserveRequestResultMetadata', 'RetainRequestResultMetadataData',
    'ReleaseRequestResultMetadata', 'FinishRequestResultMetadata', 'ReconcileRequestResultReadSerializer']) {
    runtime[`clientProgram${name}`] = () => ok(undefined);
  }
  const workspace = createLocalResultReadWorkspace({runtime, assertCurrent: current});
  if (explanation) {
    const operation = workspace.beginExplanation(request);
    return {workspace, request, runtime, calls, operation};
  }
  workspace.begin(request);
  workspace.prepare(request, {payloadBytes, rowCount: 1, resultSchemaWire: '{}', resultFields: []},
    {maxNodes: 8192, maxWireBytes: 8192}, {maxRowBytes: 8192, maxFrameBytes: 64});
  return {workspace, request, runtime, calls};
}

test('structural workspace admits its owned operation before metadata and captures the same read ports', async () => {
  const f = fixture({explanation: true});
  assert.deepEqual(f.calls.map(([name]) => name), ['clientProgramBeginRequestExplanationRead']);
  assert.deepEqual(f.operation, {principalId: 'original-reader', purpose: 'run-explanation',
    indexKey: f.request.ref});
  assert(Object.isFrozen(f.operation)); assert(Object.isFrozen(f.operation.indexKey));
  for (const name of ['clientProgramBeginRequestExplanationRead', 'clientProgramReserveRequestExplanationRead']) {
    f.runtime[name] = () => assert.fail('structural read port was looked up again');
  }
  assert.throws(() => f.workspace.prepareExplanation({...f.request}, 2048), {code: 'ForeignResultReadWorkspace'});
  f.workspace.prepareExplanation(f.request, 2048);
  assert.throws(() => f.workspace.prepareExplanation(f.request, 2048), {code: 'ForeignResultReadWorkspace'});
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
  assert(!f.calls.some(([name]) => name === 'clientProgramReserveRequestResultRead'));
});

test('structural workspace keeps the original admission/current failures and closes their same parent', async () => {
  const refusal = Object.freeze({original: 'entry-refusal'});
  assert.throws(() => fixture({explanation: true, refuse: refusal}),
    error => error.cause === refusal && error.code === 'RunExplanationReadCapacity');
  let revoked = false;
  const primary = new Error('original-read-current-lost');
  const f = fixture({explanation: true, current() {if (revoked) throw primary;}});
  revoked = true;
  assert.throws(() => f.workspace.prepareExplanation(f.request, 2048), error => error === primary);
  assert(!f.calls.some(([name]) => name === 'clientProgramReserveRequestExplanationRead'));
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
});

test('structural workspace supplies exact original DATA to one captured Core constructor and preserves typed refusal', async () => {
  const stored = Object.freeze({definitionWire: 'original-definition', admissionEvidenceWire: JSON.stringify({
    logicalPlanOriginal: {compiledPlanWire: 'original-plan', planViewWire: 'original-map'}}),
  factsWire: 'original-facts', programDefinitionCid: 'original-program', parameterValuesCid: 'original-parameters'});
  const primary = Object.freeze({original: 'typed-read-capacity'});
  for (const refused of [false, true]) {
    let calls = 0;
    const f = fixture({explanation: true, render(parent, request, definition, plan, map, facts,
      program, parameters, namespace, scope, run, bytes, maxBytes, nodes, depth) {
      calls++; assert.equal(request, f.request);
      assert.deepEqual([definition, plan, map, facts, program, parameters, namespace, scope, run,
        bytes, maxBytes, nodes, depth], ['original-definition', 'original-plan', 'original-map',
        'original-facts', 'original-program', 'original-parameters', 'original-namespace',
        'original-scope', 'original-run', 2048, 4096, 128, 32]);
      return refused ? {$tag: 0, _0: primary} : ok('original-closed-view');
    }});
    f.workspace.prepareExplanation(f.request, 2048);
    f.runtime.clientProgramReadRequestExplanation = () => assert.fail('replacement Core method');
    if (refused) assert.throws(() => f.workspace.renderExplanation(f.request, stored),
      error => error.code === 'RunExplanationReadCapacity' && error.cause === primary);
    else assert.equal(f.workspace.renderExplanation(f.request, stored), 'original-closed-view');
    assert.equal(calls, 1);
    assert.throws(() => f.workspace.renderExplanation(f.request, stored), {code: 'ForeignResultReadWorkspace'});
    f.workspace.close(f.request);
    assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  }
  let accessed = 0;
  const invalid = fixture({explanation: true}); invalid.workspace.prepareExplanation(invalid.request, 2048);
  assert.throws(() => invalid.workspace.renderExplanation(invalid.request, {
    ...stored, get factsWire() {accessed++; return 'foreign';},
  }), {code: 'RunExplanationEncodingRejected'});
  assert.equal(accessed, 0);
  invalid.workspace.close(invalid.request);
  assert.deepEqual(await invalid.workspace.closeAll(), {pending: false});
});

test('READ workspace captures original frame/wire methods and yields before parse readiness', async () => {
  const f = fixture();
  for (const name of ['GrowRequestResultReadFrame', 'BeginRequestResultReadWireRow', 'AdvanceRequestResultReadWireRow']) {
    f.runtime[`clientProgram${name}`] = () => assert.fail('method was looked up again');
  }
  assert.deepEqual(f.workspace.row(f.request, 8192), {units: 8192, window: 64});
  const wire = '"' + 'x'.repeat(5000) + '"';
  const pending = f.workspace.row(f.request, wire);
  assert.equal(f.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 1);
  assert.deepEqual(await pending, {units: 8192, window: 64});
  assert.equal(f.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 2);
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
});

test('READ workspace retains typed preflight refusal and current failure before serializer', async () => {
  const original = {}, f = fixture({refuse: original});
  f.workspace.row(f.request, 8192);
  await assert.rejects(f.workspace.row(f.request, '[]'), error => error.cause === original);
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  let deny = false;
  const cause = new Error('current changed'), changed = fixture({current() {if (deny) throw cause;}});
  changed.workspace.row(changed.request, 8192);
  const read = changed.workspace.row(changed.request, '[]');
  deny = true;
  await assert.rejects(read, error => error === cause);
  assert.equal(changed.calls.filter(([name]) => name === 'clientProgramAdvanceRequestResultReadWireRow').length, 1);
  changed.workspace.close(changed.request);
  assert.deepEqual(await changed.workspace.closeAll(), {pending: false});
});

test('READ close cannot retire the same parent while a yielded original row callback is live', async () => {
  const f = fixture();
  f.workspace.row(f.request, 8192);
  const row = f.workspace.row(f.request, '[]');
  f.workspace.close(f.request);
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 0);
  assert.deepEqual(await f.workspace.closeAll(), {pending: true});
  await assert.rejects(row, {code: 'ForeignResultReadWorkspace'});
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
});

test('READ aggregate work envelope stays wide while row and frame sizes remain bounded', async () => {
  const f = fixture({polls: 1, payloadBytes: 2147483648});
  f.workspace.row(f.request, 64);
  assert.deepEqual(await f.workspace.row(f.request, '[]'), {units: 64, window: 64});
  f.workspace.close(f.request);
  assert.deepEqual(await f.workspace.closeAll(), {pending: false});
});

// Both owners are real imported consumers; Core row/Resource responses remain
// explicit ports, so this does not establish a physical Result reader ACK.
test('Host shutdown keeps a yielded READ on its same parent until original row cleanup finishes', async () => {
  const f = fixture(); let finalizers = 0;
  f.workspace.row(f.request, 8192);
  const row = f.workspace.row(f.request, '[]');
  f.workspace.close(f.request);
  const shutdown = installedHostShutdown({dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {}},
    initialControl: {close() {return f.workspace.closeAll();}},
    retireModelRuntime() {finalizers++;}});
  await assert.rejects(shutdown.close(), {message: 'InstalledHostInitialControlCleanupPending'});
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 0);
  assert.equal(finalizers, 0);
  await assert.rejects(row, {code: 'ForeignResultReadWorkspace'});
  await shutdown.close();
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
  assert.equal(finalizers, 1);
  await shutdown.close();
  assert.equal(f.calls.filter(([name]) => name === 'abort').length, 1);
  assert.equal(finalizers, 1);
});

// These explicit immutable Account/evaluation ports isolate the installed
// operation memo. They do not qualify Common's Account grammar/evaluator or
// supply authority to an ordinary Host; the imported factory is exercised.
function metadataReadFixture(observation) {
  const account = {account_id: 'original-account', run: 'allow', result: 'deny'};
  const authorization = {siteKey: 'original-connection'};
  Object.defineProperty(authorization, 'accountConfiguration', {
    get: () => JSON.stringify(account),
  });
  const evaluations = [];
  const moon = {
    executionAuthorizationMissing() {throw new Error('UnexpectedMissingAccount');},
    executionAuthorizationAdmit(wire) {return Object.freeze(JSON.parse(wire));},
    executionAuthorizationAccountJson(value) {
      return JSON.stringify({state: 'admitted', account_id: value.account_id});
    },
    executionAuthorizationEvaluate(value, principal, connection, resource, operation) {
      evaluations.push({value, principal, connection, resource, operation});
      return {outcome: value[resource === 'run' ? 'run' : 'result']};
    },
    executionAuthorizationEvaluationJson: JSON.stringify,
  };
  const indexKey = Object.freeze({namespaceId: 'original-namespace',
    authorityScopeCid: `sha256:${'1'.repeat(64)}`,
    runDefinitionCid: `sha256:${'2'.repeat(64)}`});
  const facts = Object.freeze({principalId: 'original-principal', indexKey,
    resultName: 'main', purpose: 'run-explanation'});
  const reads = createLocalReadAuthorizations({moon, authorization, observation,
    principalId: facts.principalId, namespaceId: indexKey.namespaceId,
    authorityScopeCid: indexKey.authorityScopeCid});
  return {reads, facts, account, evaluations,
    operation: () => Object.freeze({...facts})};
}

test('one structural metadata read memo evaluates exact run/read once and never crosses public reads', async () => {
  const f = metadataReadFixture(), operation = f.operation();
  assert.equal(await f.reads.run(f.facts, operation), true);
  assert.equal(await f.reads.run(f.facts, operation), true);
  assert.equal(f.evaluations.length, 1);
  assert.deepEqual(f.evaluations[0], {value: Object.freeze({...f.account}),
    principal: 'original-principal', connection: 'original-connection',
    resource: 'run', operation: 'read'});
  f.account.run = 'deny';
  assert.equal(await f.reads.run(f.facts, f.operation()), false);
  assert.equal(f.evaluations.length, 2);
});

test('Run metadata and Result permissions never borrow the other resource outcome', async () => {
  const f = metadataReadFixture(), operation = f.operation();
  assert.equal(await f.reads.run(f.facts, operation), true);
  assert.equal(await f.reads.result(f.facts, operation), false);
  assert.equal(await f.reads.run(f.facts, operation), true);
  assert.deepEqual(f.evaluations.map(value => value.resource), ['run', 'result/main', 'run']);
  f.account.run = 'deny'; f.account.result = 'allow';
  const next = f.operation();
  assert.equal(await f.reads.result(f.facts, next), true);
  assert.equal(await f.reads.run(f.facts, next), false);
});

test('an actual observation callback rechecks the same Run read after Account revocation', async () => {
  let f, delivered;
  const delivery = new Promise(resolve => {delivered = resolve;});
  const observation = installHostObservation(createHostObservationConnection({
    include: ['run'], correlation: false, measurements: {include: ['duration']},
    deliver() {f.account.run = 'deny'; delivered();},
  }));
  try {
    f = metadataReadFixture(observation);
    const operation = f.operation();
    await observation.run('result', undefined, async () => {
      assert.equal(await f.reads.run(f.facts, operation), true);
      await delivery;
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(await f.reads.run(f.facts, operation), false);
    });
    assert.deepEqual(f.evaluations.map(value => value.value.run), ['allow', 'deny']);
  } finally {await observation.close();}
});

test('foreign principal and namespace cannot consume an owned metadata read memo', async () => {
  const f = metadataReadFixture(), operation = f.operation();
  assert.equal(await f.reads.run(f.facts, operation), true);
  assert.equal(await f.reads.run({...f.facts, principalId: 'foreign'}, operation), false);
  assert.equal(await f.reads.run({...f.facts,
    indexKey: {...f.facts.indexKey, namespaceId: 'foreign'}}, operation), false);
  assert.equal(f.evaluations.length, 1);
});
