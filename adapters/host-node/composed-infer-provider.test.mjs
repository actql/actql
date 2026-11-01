import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeComposedInferProvider} from './infer-operation.mjs';

test('a prepared Effect Plan retains one Model provider and binds its original execution context once', () => {
  const occurrence = {}, graph = {}, prefix = {}, provider = {}, sources = {},
    selected = Object.freeze({occurrence, graph, computePrefix: prefix, provider: {}});
  let start, constructors = 0, attempts = 0;
  const original = new Error('actual original Model start');
  const moon = {
    clientProgramComposedInferLocalProvider(actual, open, _issue, _retain, _cleanup, sequence) {
      assert.strictEqual(actual, occurrence); assert.strictEqual(sequence, prefix);
      constructors++; start = open; return provider;
    },
    clientProgramStartComposedInferExecution(actual, plan, sequence, inputs, physical, admitted) {
      assert.strictEqual(actual, occurrence); assert.strictEqual(plan, graph);
      assert.strictEqual(sequence, prefix); assert.strictEqual(physical, selected.provider);
      assert.strictEqual(admitted, sources); assert.strictEqual(inputs, input);
      attempts++; throw original;
    },
  };
  const input = [], component = openNodeComposedInferProvider({moon, selected, deferred: true});
  assert.strictEqual(component.provider, provider); assert.equal(constructors, 1); assert.equal(attempts, 0);
  const context = {selected, sources, retainOperation() {assert.fail('start did not issue a child');}};
  assert.strictEqual(component.bindOriginal(context), component);
  assert.throws(() => component.bindOriginal(context), {message: 'ComposedInferAlreadyBound'});
  assert.equal(start(input), undefined); assert.strictEqual(component.failure(), original);
  assert.equal(constructors, 1); assert.equal(attempts, 1);
});

test('a Model provider cannot start before its original Effect context or replace it after failure', () => {
  const selected = Object.freeze({occurrence: {}, graph: {}});
  let start;
  const moon = {clientProgramComposedInferLocalProvider(_owner, open) {start = open; return {};}};
  const component = openNodeComposedInferProvider({moon, selected, deferred: true});
  assert.equal(start([]), undefined);
  assert.equal(component.failure().message, 'ComposedInferOriginalContextUnavailable');
  assert.throws(() => component.bindOriginal({selected, retainOperation() {}}),
    {message: 'ComposedInferAlreadyBound'});
});

test('the original undefined Model start failure remains failed without reopening or secondary replacement', () => {
  const selected = Object.freeze({occurrence: {}, graph: {}, provider: {}});
  let start, issue, attempts = 0;
  const moon = {clientProgramComposedInferLocalProvider(_original, open, observe) {
    start = open; issue = observe; return {};
  }, clientProgramStartComposedInferExecution() {attempts++; throw undefined;}};
  const component = openNodeComposedInferProvider({moon, selected, deferred: true});
  component.bindOriginal({selected, retainOperation() {assert.fail('no child returned');}});
  assert.equal(start([]), undefined); assert.strictEqual(component.failure(), undefined);
  issue({secondary: true}); assert.equal(start([]), undefined);
  assert.strictEqual(component.failure(), undefined); assert.equal(attempts, 1);
  assert.throws(() => component.bindOriginal({selected, retainOperation() {}}), {message: 'ComposedInferAlreadyBound'});
});

test('composed Local start retains the original Model before Run and dispatch binding', async () => {
  const active = {};
  const occurrence = {};
  const graph = {};
  const prefix = {};
  const sources = {};
  const inputs = [{producer: 'left'}, {producer: 'right'}];
  const physical = {};
  const suffix = {};
  const preflight = () => {};
  const egress = {};
  const compiled = {};
  const runDefinition = {};
  const account = {};
  const observeAccount = () => account;
  const now = () => '2026-10-03T00:00:00.000Z';
  const events = [];
  const selected = {occurrence, graph, computePrefix: prefix, computeSuffix: suffix,
    provider: physical, physicalPreflight: preflight, egressAdmission: egress,
    account, observeAccount, quantityCapacity: {
      limits: {tokens: 128n, costUnits: 0n, durationMs: 1000n},
      perAttempt: {tokens: 32n, costUnits: 0n, durationMs: 500n},
    }};
  let start;
  let project;
  let complete;
  let allowCleanup;
  let retained;
  const port = {};
  const ok = {$tag: 1, _0: undefined};
  const assertActive = value => assert.equal(value, active);
  const moon = {
    clientProgramComposedInferLocalProvider(owner, open, issue, retain, cleanup, inputPrefix) {
      assert.equal(owner, occurrence);
      assert.equal(inputPrefix, prefix);
      start = open;
      project = issue;
      complete = retain;
      allowCleanup = cleanup;
      return port;
    },
    clientProgramStartComposedInferExecution(...actual) {
      assert.deepEqual(actual, [occurrence, graph, prefix, inputs, physical, sources]);
      for (const [index, expected] of [occurrence, graph, prefix, inputs, physical, sources].entries()) {
        assert.equal(actual[index], expected);
      }
      events.push('start');
      return {$tag: 1, _0: active};
    },
    clientProgramBindInferQuantityCapacity(value, ...bounds) {
      assertActive(value);
      assert.deepEqual(bounds, [128n, 0n, 1000n, 32n, 0n, 500n]);
      events.push('quantity');
      return ok;
    },
    clientProgramBindInferComputeSuffix(value, actual) {
      assertActive(value); assert.equal(actual, suffix); events.push('suffix'); return ok;
    },
    clientProgramBindInferPhysicalPreflight(value, actual) {
      assertActive(value); assert.equal(actual, preflight); events.push('preflight'); return ok;
    },
    clientProgramBindInferEgress(value, actual) {
      assertActive(value); assert.equal(actual, egress); events.push('egress'); return ok;
    },
    clientProgramAdvanceInferExecution() { assert.fail('Local alone must advance the Model component'); },
    clientProgramInferExecutionStopped(value) { assertActive(value); return true; },
    clientProgramCleanupInferExecution(value) { assertActive(value); return {$tag: 1, _0: true}; },
  };
  const control = {
    bindCheckedClientInferRun(actual, value, definition) {
      assert.equal(actual, compiled); assertActive(value); assert.equal(definition, runDefinition);
      assert.ok(retained); events.push('run');
    },
    bindCheckedClientInferDispatch(actual, value, definition, observation) {
      assert.equal(actual, compiled); assertActive(value); assert.equal(definition, runDefinition);
      assert.equal(observation.account, account);
      assert.equal(observation.observeAccount, observeAccount);
      assert.equal(observation.observeAt, now);
      assert.equal(observation.principalId, 'composition-principal');
      events.push('dispatch');
    },
  };
  const opened = openNodeComposedInferProvider({moon, selected, sources, control,
    plan: {compiled, runDefinition}, principalId: 'composition-principal', now,
    retainOperation(operation) { retained = operation; events.push('retain'); },
    retainCompleted(operation) { assert.equal(operation, retained); events.push('capture'); }});
  assert.equal(opened.provider, port);
  assert.deepEqual(events, []);
  selected.computePrefix = {};
  assert.equal(start(inputs), active);
  assert.deepEqual(events, ['start', 'retain', 'quantity', 'suffix', 'preflight', 'egress', 'run', 'dispatch']);
  assert.equal(opened.operation(), retained);
  assert.equal(allowCleanup(active), false, 'Local cannot discard pending Host evidence');
  assert.equal(allowCleanup({}), false, 'another component cannot grant cleanup');
  await assert.rejects(retained.run(), {message: 'InferComponentDrivenByLocal'});
  assert.equal(complete(active), true);
  assert.equal(events.at(-1), 'capture');
  const cause = {componentIssue: 'InputBudget'};
  project(cause);
  assert.equal(opened.failure().cause, cause);
  assert.equal(allowCleanup(active), false, 'a failed component still owns stopped evidence');
  assert.equal(retained.cleanup(), true);
  assert.equal(allowCleanup(active), true, 'only the original reclaimed owner releases Local custody');
  assert.equal(start(inputs), undefined);
  assert.equal(events.filter(value => value === 'start').length, 1);
});

test('failed composed binding leaves cleanup to the already retained evidence owner', () => {
  const active = {}, cause = {refusal: 'ComposedInputBindingRefused'};
  let start, retained, cleanups = 0, stopped = false;
  const moon = {
    clientProgramComposedInferLocalProvider(_occurrence, open) { start = open; return {}; },
    clientProgramStartComposedInferExecution: () => ({$tag: 1, _0: active}),
    clientProgramBindInferQuantityCapacity: () => ({$tag: 0, _0: cause}),
    clientProgramCancelInferExecution() { stopped = true; },
    clientProgramAdvanceInferExecution: () => ({$tag: 1, _0: 'stopped'}),
    clientProgramInferExecutionPollKind: value => value,
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution() { cleanups++; return {$tag: 1, _0: true}; },
  };
  const component = openNodeComposedInferProvider({moon,
    selected: {occurrence: {}, graph: {}, provider: {}, quantityCapacity: {
      limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}}},
    retainOperation(owner) { retained = owner; },
  });
  assert.equal(start([]), undefined);
  assert.equal(component.operation(), retained);
  assert.equal(component.failure().cause, cause);
  assert.equal(component.failure().cleanupOwner, retained);
  assert.equal(cleanups, 0, 'constructor cannot bypass the parent evidence custody');
  assert.equal(retained.cleanup(), true);
  assert.equal(cleanups, 1);
});


test('Request component constructor forwards its already backed original prefix without changing the selected Graph', () => {
  const occurrence = {}, graph = {}, prefix = new Proxy({}, {
    get() {assert.fail('the opaque original prefix must not be inspected');},
  }), provider = {}, selected = Object.freeze({occurrence, graph, provider: {}});
  let open, constructors = 0;
  const moon = {clientProgramComposedInferLocalProvider(actual, start, _issue, _retain, _cleanup, sequence) {
    constructors++;
    assert.strictEqual(actual, occurrence);
    assert.strictEqual(sequence, prefix);
    open = start;
    return provider;
  }};
  const component = openNodeComposedInferProvider({moon, selected, inputPrefix: prefix, deferred: true});
  assert.strictEqual(component.provider, provider);
  assert.equal(constructors, 1);
  assert.equal(Object.hasOwn(selected, 'computePrefix'), false);
  assert.equal(open([]), undefined);
  assert.equal(component.failure().message, 'ComposedInferOriginalContextUnavailable');
  assert.throws(() => component.bindOriginal({selected, retainOperation() {}}),
    {message: 'ComposedInferAlreadyBound'});
});
