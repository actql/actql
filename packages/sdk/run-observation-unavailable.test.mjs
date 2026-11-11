import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import * as sdk from './index.mjs';
import {connectInProcess} from './host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'original-run', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const hint = 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.';
const expected = (operation, target = ref) => ({kind: 'unavailable', problem: 'observation_unavailable', operation,
  next: {operation: 'status', ref: target},
  summary: 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.', hint});
const running = {version: 'actql-run-state/0.1', run_id: 'run-a', revision: 31, status: 'running',
  updated_at: '2026-10-07T00:00:00.000Z', next_action: {kind: 'none'},
  result_available: false, result_availability: {answer: {state: 'unavailable',
    reason: 'not_published', observed_at: '2026-10-07T00:00:00.000Z'}}};
async function fixture(t, reply) {
  const operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      operations.push(operation);
      if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'original-principal', capabilities: [], limits: {
          maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
          maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
      if (operation === 'attach') return {ref: body.ref, durability: 'durable', revision: 1};
      if (operation === 'close') return;
      return reply(operation);
    },
  });
  t.after(() => client.close());
  return {client, run: await client.attach(ref), operations};
}
const capture = async promise => {
  let failure;
  try {await promise;} catch (error) {failure = error;}
  assert.equal(failure instanceof sdk.ClientError, true);
  return failure;
};
for (const operation of ['status', 'wait', 'reconcile']) {
  test(`${operation}: unavailable Run observation retains only the original read-only target`, async t => {
    const borrowed = new sdk.ClientError('ClientConnectionDenied', {status: 403,
      cause: new Error('private-credential-secret')});
    const f = await fixture(t, () => {throw borrowed;});
    const error = await capture(f.run[operation]());
    const view = sdk.explainRunObservationFailure(error);
    assert.deepEqual(view, expected(operation), '[check-mutation:run-unavailable-facts]');
    assert.notEqual(error, borrowed);
    assert.equal(error.code, 'ClientConnectionDenied');
    assert.equal(error.status, 403);
    assert.doesNotMatch(inspect({error, view}, {showHidden: true, depth: 8}), /private-credential-secret/,
      '[check-mutation:run-unavailable-disclosure]');
    assert.equal(Object.hasOwn(error, 'cause'), false);
    assert.ok(Object.isFrozen(view.next.ref));
    assert.equal(sdk.explainEffectUncertainty(error), undefined);
    assert.equal(sdk.explainRunObservationFailure({...error}), undefined);
    assert.equal(sdk.explainRunObservationFailure(structuredClone(error)), undefined);
    assert.equal(sdk.explainRunObservationFailure(borrowed), undefined);
    const before = [...f.operations];
    error.code = 'Succeeded'; error.kind = 'verified'; error.next = {operation: 'reconcile'};
    assert.deepEqual(sdk.explainRunObservationFailure(error), expected(operation));
    assert.deepEqual(sdk.explainRunObservationFailure(error, {locale: 'ja'}), {...expected(operation),
      summary: 'Runの観測を完了できませんでした。この失敗は実行・Effect・公開・解放の結果を確定しません。',
      hint: '現在の認可で元のRun状態を確認してください。この観測は実行・Effect・公開・解放の結果を確定せず、書き込みの再試行を許可しません。'});
    assert.deepEqual(f.operations, before, '[check-mutation:run-unavailable-passive]');
  });
}

test('Run observation reused failures and later success do not rebind earlier targets', async t => {
  const borrowed = new Error('private-reused-failure');
  let reply = () => {throw borrowed;};
  const f = await fixture(t, () => reply());
  const first = await capture(f.run.status());
  const otherRef = {...ref, runDefinitionCid: cid('c')};
  const other = await f.client.attach(otherRef);
  const second = await capture(other.reconcile());
  assert.notEqual(first, second);
  assert.deepEqual(sdk.explainRunObservationFailure(first), expected('status'),
    '[check-mutation:run-unavailable-custody]');
  assert.deepEqual(sdk.explainRunObservationFailure(second), expected('reconcile', otherRef));
  assert.equal(sdk.explainRunObservationFailure(borrowed), undefined);
  assert.equal(first.code, 'ClientTransportUnknown');
  reply = () => running;
  assert.equal((await f.run.status()).status, 'running');
  assert.deepEqual(sdk.explainRunObservationFailure(first), expected('status'));
  assert.deepEqual(f.operations, ['connect', 'attach', 'status', 'attach', 'reconcile', 'status']);
});

test('a closed Client supplies unavailable observation without claiming dispatch', async t => {
  const f = await fixture(t, () => assert.fail('No observation should be sent'));
  await f.client.close();
  const before = [...f.operations];
  const error = await capture(f.run.wait());
  assert.equal(error.code, 'ClientClosed');
  assert.deepEqual(sdk.explainRunObservationFailure(error), expected('wait'));
  assert.deepEqual(f.operations, before);
});

test('typed Run observation failures separate unavailable from protocol rejection', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL('../../node_modules/typescript/bin/tsc', import.meta.url)),
    '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022',
    fileURLToPath(new URL('./run-observation-protocol.typecheck.mts', import.meta.url))],
  {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000});
});

for (const field of ['code', 'status']) {
  test(`unreadable ${field} metadata cannot replace an unavailable Run observation`, async t => {
    const borrowed = new sdk.ClientError('ClientHostFailure');
    let reads = 0;
    Object.defineProperty(borrowed, field, {get() {reads++; throw new Error('private-failure-metadata');}});
    const f = await fixture(t, () => {throw borrowed;});
    const error = await capture(f.run.status());
    assert.deepEqual(sdk.explainRunObservationFailure(error), expected('status'),
      '[check-mutation:run-unavailable-metadata]');
    assert.equal(error.code, 'ClientTransportUnknown');
    assert.equal(Object.hasOwn(error, 'cause'), false);
    assert.equal(reads, 1);
    assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-failure-metadata/);
  });
}
