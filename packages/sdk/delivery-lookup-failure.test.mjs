import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {inspect} from 'node:util';
import * as sdk from './index.mjs';
import {connectInProcess} from './host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const found = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const hint = 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.';
const expected = observation => ({observation, summary: observation === 'lookup_unavailable'
  ? 'The DeliveryAttempt lookup could not be completed. Read opening and delivery remain unresolved.'
  : 'This SDK could not interpret the DeliveryAttempt lookup response. Read opening and delivery remain unresolved.',
  hint, next: {operation: 'deliveryAttempt', ref, resultName: 'answer', attemptId: 'read-a',
    lookupContext: {endpoint: 'actql:embedded', scopeRef: 'scope'}}});
async function fixture(t, reply) {
  const operations = [];
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation) {
      operations.push(operation);
      if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'volatile', scopeRef: 'scope', capabilities: [], limits: {
          maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
          maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
      if (operation === 'attach') return {ref, durability: 'volatile', revision: 1};
      if (operation === 'delivery-attempt') return reply();
      if (operation === 'close') return;
      assert.fail('Unexpected operation');
    },
  });
  t.after(() => client.close());
  return {result: (await client.attach(ref)).result('answer'), operations};
}
const capture = async promise => {
  let error;
  try {await promise;} catch (failure) {error = failure;}
  assert.equal(error instanceof sdk.ClientError, true);
  return error;
};
for (const [fault, reply] of [
  ['unknown variant', () => ({kind: 'private-future-success'})],
  ['unknown state', () => ({...structuredClone(found), record: {...found.record, state: 'private-future-state'}})],
  ['malformed known facts', () => ({...structuredClone(found), hostReleaseReceipt: null})],
  ['foreign attempt', () => ({...structuredClone(found), attempt: {...found.attempt, attempt_id: 'private-other-attempt'}})],
  ['unreadable field', () => ({get kind() {throw new Error('private-result-secret');}})],
]) {
  test(`delivery lookup explains ${fault} without unvalidated Owner facts`, async t => {
    const f = await fixture(t, reply);
    const error = await capture(f.result.deliveryAttempt('read-a'));
    assert.equal(error.code, 'InvalidHostAttemptLookup');
    const explanation = sdk.explainDeliveryAttempt(error);
    assert.deepEqual(explanation, expected('lookup_uninterpretable'), '[check-mutation:delivery-lookup-failure-facts]');
    assert.equal(Object.hasOwn(error, 'cause'), false, '[check-mutation:delivery-lookup-failure-disclosure]');
    assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-result-secret|private-other-attempt|private-future/);
    const before = [...f.operations];
    error.code = 'Succeeded'; error.message = 'success'; error.attemptId = 'edited';
    for (const format of ['text', 'html', 'json']) {
      const output = sdk.formatDeliveryAttempt(error, {format});
      assert.ok(output);
      assert.doesNotMatch(output, /private-|edited/);
      if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected('lookup_uninterpretable'));
    }
    assert.equal(Object.isFrozen(explanation.next.ref), true);
    assert.equal(sdk.explainDeliveryAttempt({...error}), undefined);
    assert.equal(sdk.explainDeliveryAttempt(new sdk.ClientError('InvalidHostAttemptLookup')), undefined);
    assert.deepEqual(sdk.explainDeliveryAttempt(error), explanation);
    assert.deepEqual(f.operations, before);
  });
}

test('delivery lookup exchange failures retain only original authorized lookup advice', async t => {
  const borrowed = new sdk.ClientError('ClientConnectionForbidden', {status: 403,
    cause: new Error('private-provider-secret')});
  const f = await fixture(t, () => {throw borrowed;});
  const error = await capture(f.result.deliveryAttempt('read-a'));
  assert.notEqual(error, borrowed);
  assert.equal(error.code, 'ClientConnectionForbidden');
  assert.equal(error.status, 403);
  assert.deepEqual(sdk.explainDeliveryAttempt(error), expected('lookup_unavailable'),
    '[check-mutation:delivery-lookup-exchange-facts]');
  assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-provider-secret/,
    '[check-mutation:delivery-lookup-failure-disclosure]');
  assert.equal(Object.hasOwn(error, 'cause'), false);
  assert.deepEqual(sdk.explainDeliveryAttempt(error, {locale: 'ja'}), {...expected('lookup_unavailable'),
    summary: 'DeliveryAttemptの照会を完了できませんでした。読み取り開始・配信は未確定です。',
    hint: '元の読み取り参照を保持してください。この観測はアプリケーションでの受領・保存を確認せず、再読取やComputeの再実行も許可しません。'});
  assert.deepEqual(f.operations, ['connect', 'attach', 'delivery-attempt']);
});

test('delivery lookup reused errors and subsequent success preserve earlier uncertainty', async t => {
  const borrowed = new Error('private-reused-error');
  let reply = () => {throw borrowed;};
  const f = await fixture(t, () => reply());
  const first = await capture(f.result.deliveryAttempt('read-a'));
  const original = sdk.explainDeliveryAttempt(first);
  const second = await capture(f.result.deliveryAttempt('read-b'));
  assert.notEqual(first, second);
  assert.deepEqual(original, expected('lookup_unavailable'), '[check-mutation:delivery-lookup-original-target]');
  assert.equal(sdk.explainDeliveryAttempt(second).next.attemptId, 'read-b');
  reply = () => structuredClone(found);
  const success = await f.result.deliveryAttempt('read-a');
  assert.equal(sdk.explainDeliveryAttempt(success).observation, 'host_delivery_succeeded');
  assert.deepEqual(sdk.explainDeliveryAttempt(first), original);
  assert.equal(sdk.explainDeliveryAttempt(borrowed), undefined);
  assert.deepEqual(f.operations, ['connect', 'attach', 'delivery-attempt', 'delivery-attempt', 'delivery-attempt']);
});

test('invalid local delivery lookup arguments supply no observation', async t => {
  const f = await fixture(t, () => assert.fail('No lookup expected'));
  const error = await capture(f.result.deliveryAttempt(''));
  assert.equal(error.code, 'InvalidReadAttempt');
  assert.equal(sdk.explainDeliveryAttempt(error), undefined);
  assert.deepEqual(f.operations, ['connect', 'attach']);
});
