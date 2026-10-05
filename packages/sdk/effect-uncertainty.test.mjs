import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connect, explainEffectUncertainty} from './index.mjs';

const ref = {namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const profile = {version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable', scopeRef: 'scope-a',
  capabilities: ['aql-document', 'result-jsonl'], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3,
    maxBatchRetainedValueBytes: 1024}};
const state = control => ({version: 'actql-run-state/0.1',
  run_id: 'run-a', status: 'needs_reconciliation',
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
  next: {operation: 'status', ref},
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
    for (const control of [undefined,
      {revision: 4, cancellation_requested: true, physical_stop: 'unknown'},
      {revision: 7, cancellation_requested: false, physical_stop: 'confirmed'}]) {
      reply = state(control);
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
      {...state(), status: 'succeeded'},
      {...state(), private_provider_error: 'private-cause'},
      {...state(), next_action: {kind: 'reconcile', effects: []}},
      state({revision: 2, cancellation_requested: true, physical_stop: 'stopped'}),
    ]) {
      reply = invalid;
      await assert.rejects(execution[operation](), {code: 'InvalidHostRunState'});
      assert.equal(explainEffectUncertainty(invalid), undefined);
    }
    reply = {...state(), next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}};
    assert.equal(explainEffectUncertainty(await execution[operation]()), undefined);
    assert.equal(explainEffectUncertainty(null), undefined);
    assert.equal(explainEffectUncertainty(new Error('needs_reconciliation')), undefined);
  });
}

test('typed Effect explanations separate physical stop, owner revision and read-only advice', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL(
    '../../node_modules/typescript/bin/tsc', import.meta.url)),
  '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
  '--target', 'ES2022', fileURLToPath(new URL(
    './effect-uncertainty.typecheck.mts', import.meta.url))],
  {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000});
});
