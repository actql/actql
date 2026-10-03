import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeComposedInferProvider} from './infer-operation.mjs';

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
  let retained;
  const port = {};
  const ok = {$tag: 1, _0: undefined};
  const assertActive = value => assert.equal(value, active);
  const moon = {
    clientProgramComposedInferLocalProvider(owner, open, issue, retain) {
      assert.equal(owner, occurrence);
      start = open;
      project = issue;
      complete = retain;
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
  assert.equal(start(inputs), active);
  assert.deepEqual(events, ['start', 'quantity', 'suffix', 'preflight', 'egress', 'retain', 'run', 'dispatch']);
  assert.equal(opened.operation(), retained);
  await assert.rejects(retained.run(), {message: 'InferComponentDrivenByLocal'});
  assert.equal(complete(active), true);
  assert.equal(events.at(-1), 'capture');
  const cause = {componentIssue: 'InputBudget'};
  project(cause);
  assert.equal(opened.failure().cause, cause);
  assert.equal(start(inputs), undefined);
  assert.equal(events.filter(value => value === 'start').length, 1);
});
