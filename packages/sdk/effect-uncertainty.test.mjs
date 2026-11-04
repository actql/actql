import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connect, connectInProcess, explainEffectUncertainty, explainRunObservationFailure} from './index.mjs';
import {validRunState} from '@actql/client-wire';

const ref = {namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const profile = {version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable', scopeRef: 'scope-a',
  capabilities: ['aql-document', 'result-jsonl'], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3,
    maxBatchRetainedValueBytes: 1024}};
// Explicit published state revisions are distinct from cancellation-control
// revisions. Changing published control facts below advances the former too.
const state = (revision, control) => ({version: 'actql-run-state/0.1',
  run_id: 'run-a', revision, status: 'needs_reconciliation',
  updated_at: '2026-10-05T00:00:00.000Z',
  next_action: {kind: 'reconcile', effects: ['save', 'notify']},
  result_available: false, result_availability: {updates: {
    state: 'unavailable', observed_at: '2026-10-05T00:00:00.000Z',
    reason: 'not_published'}},
  ...(control === undefined ? {} : {control})});

const expected = (physicalStop, controlRevision) => ({
  observation: 'effect_outcome_unknown',
  summary: 'External Effect outcomes are unknown. Computation stop does not establish their outcome or resource release.',
  effects: ['save', 'notify'], physicalStop,
  ...(controlRevision === undefined ? {} : {controlRevision}),
  next: {operation: 'reconcile', ref},
});

for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: Effect uncertainty retains only validated Owner observations`, async t => {
    let reply;
    const operations = [];
    t.mock.method(globalThis, 'fetch', async (url, options) => {
      const current = url.pathname.split('/').at(-1);
      operations.push(current);
      if (current === 'connect') return Response.json(profile);
      assert.deepEqual(JSON.parse(options.body).ref, ref);
      if (current === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
      assert.equal(current, operation);
      return Response.json(reply);
    });
    const client = await connect({mode: 'remote',
      endpoint: 'https://host.example/', token: 'private-token'});
    t.after(() => client.close());
    const execution = await client.attach(ref);
    for (const [revision, control] of [[20, undefined],
      [21, {revision: 4, cancellation_requested: true, physical_stop: 'unknown'}],
      [22, {revision: 7, cancellation_requested: false, physical_stop: 'confirmed'}]]) {
      reply = state(revision, control);
      const response = await execution[operation]();
      const explanation = explainEffectUncertainty(response);
      assert.deepEqual(explanation, expected(control?.physical_stop ?? 'unknown',
        control?.revision), '[check-mutation:effect-control]');
      assert.ok(Object.isFrozen(explanation));
      assert.ok(Object.isFrozen(explanation.effects));
      assert.ok(Object.isFrozen(explanation.next.ref));
      assert.equal(explainEffectUncertainty({...response}), undefined);
      response.status = 'succeeded';
      response.next_action.effects.length = 0;
      if (response.control) response.control.revision = 999;
      assert.deepEqual(explainEffectUncertainty(response), explanation);
    }
    assert.deepEqual(operations, ['connect', 'attach', operation, operation, operation],
      '[check-mutation:effect-passive]');
    for (const invalid of [
      {...state(23), status: 'succeeded'},
      {...state(23), private_provider_error: 'private-cause'},
      {...state(23), next_action: {kind: 'reconcile', effects: []}},
      state(23, {revision: 2, cancellation_requested: true, physical_stop: 'stopped'}),
    ]) {
      reply = invalid;
      await assert.rejects(execution[operation](), {code: 'InvalidHostRunState'});
      assert.equal(explainEffectUncertainty(invalid), undefined);
    }
    reply = {...state(24), next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}};
    assert.equal(explainEffectUncertainty(await execution[operation]()), undefined);
    assert.equal(explainEffectUncertainty(null), undefined);
    assert.equal(explainEffectUncertainty(new Error('needs_reconciliation')), undefined);
  });
}

test('Local response reuse cannot rebind an earlier Effect explanation to another Run', async t => {
  const otherRef = {...ref, runDefinitionCid: `sha256:${'c'.repeat(64)}`};
  const shared = state(20, {revision: 4, cancellation_requested: false,
    physical_stop: 'unknown'});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation, body) {
      if (operation === 'connect') return {...profile, mode: 'local', owner: 'local'};
      if (operation === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
      assert.equal(operation, 'status');
      if (body.ref.runDefinitionCid === otherRef.runDefinitionCid) {
        shared.run_id = 'run-b';
        shared.next_action.effects = ['other-write'];
        shared.control.revision = 7;
      }
      return shared;
    },
  });
  t.after(() => client.close());
  const first = await (await client.attach(ref)).status();
  const second = await (await client.attach(otherRef)).status();
  assert.deepEqual(explainEffectUncertainty(first), expected('unknown', 4),
    '[check-mutation:effect-custody]');
  assert.deepEqual(explainEffectUncertainty(second), {
    ...expected('unknown', 7), effects: ['other-write'],
    next: {operation: 'reconcile', ref: otherRef}}, '[check-mutation:effect-custody]');
  assert.equal(first.run_id, 'run-a', '[check-mutation:effect-custody]');
  assert.equal(second.run_id, 'run-b');
});

test('typed Effect explanations separate physical stop, owner revision and reconciliation advice', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL(
    '../../node_modules/typescript/bin/tsc', import.meta.url)),
  '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
  '--target', 'ES2022', fileURLToPath(new URL(
    './effect-uncertainty.typecheck.mts', import.meta.url))],
  {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000});
});

for (const operation of ['status', 'wait', 'reconcile']) {
  for (const kind of ['proxy', 'date', 'control-date', 'action-date']) {
    test(`Local ${operation}: Effect custody captures ${kind} data without a verification clone`, async t => {
      const value = state(20, {revision: 4, cancellation_requested: false,
        physical_stop: 'confirmed'});
      const reply = kind === 'proxy' ? new Proxy(value, {})
        : kind === 'date' ? Object.assign(new Date(0), value)
          : {...value, [kind === 'control-date' ? 'control' : 'next_action']:
            Object.assign(new Date(0), value[kind === 'control-date' ? 'control' : 'next_action'])};
      assert.equal(validRunState(reply), true);
      const nativeClone = globalThis.structuredClone;
      let conversions = 0;
      t.mock.method(globalThis, 'structuredClone', received => {
        if (received?.run_id === value.run_id) conversions++;
        return nativeClone(received);
      });
      const operations = [];
      const client = await connectInProcess({mode: 'local', owner: 'local'}, {
        perform(current, body) {
          operations.push(current);
          if (current === 'connect') return {...profile, mode: 'local', owner: 'local'};
          if (current === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
          assert.equal(current, operation);
          return reply;
        },
      });
      t.after(() => client.close());
      const execution = await client.attach(ref);
      const answer = await execution[operation]();
      assert.deepEqual(answer, value);
      assert.deepEqual(explainEffectUncertainty(answer), expected('confirmed', 4));
      assert.equal(conversions, 0);
      assert.equal(explainEffectUncertainty(reply), undefined);
      assert.deepEqual(operations, ['connect', 'attach', operation]);
    });
  }
}

// Negative custody fixtures retain invalid DATA or an actual capture failure.
// Valid enumerable Proxy/Date fields above remain supported without a clone.
for (const operation of ['status', 'wait', 'reconcile']) {
  for (const kind of ['proxy', 'date', 'control-date', 'action-date']) {
    test(`Local ${operation}: Effect custody refuses ${kind} clone failure or shape loss`, async t => {
      const value = state(20, {revision: 4, cancellation_requested: false,
        physical_stop: 'confirmed'});
      const reply = kind === 'proxy' ? new Proxy(value, {
        get(target, key, receiver) {
          if (key === 'next_action') throw new Error('private-effect-capture');
          return Reflect.get(target, key, receiver);
        },
      }) : kind === 'date' ? Object.assign(new Date(0), value, {result_available: 'true'})
        : kind === 'control-date' ? {...value,
          control: Object.assign(new Date(0), value.control, {physical_stop: 'invalid'})}
          : {...value, next_action: Object.assign(new Date(0), {kind: 'reconcile', effects: 42})};
      const operations = [];
      const client = await connectInProcess({mode: 'local', owner: 'local'}, {
        perform(current, body) {
          operations.push(current);
          if (current === 'connect') return {...profile, mode: 'local', owner: 'local'};
          if (current === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
          assert.equal(current, operation);
          return reply;
        },
      });
      t.after(() => client.close());
      const execution = await client.attach(ref);
      let failure;
      try { await execution[operation](); } catch (cause) { failure = cause; }
      assert.equal(failure?.code, 'InvalidHostRunState', '[check-mutation:effect-copied-shape]');
      assert.equal(explainRunObservationFailure(failure)?.problem, 'malformed_response');
      assert.equal(explainEffectUncertainty(failure), undefined);
      assert.deepEqual(operations, ['connect', 'attach', operation]);
    });
  }
}
