import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {connectInProcess} from './host-port.mjs';
import {explainDeliveryAttempt, formatDeliveryAttempt} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const found = JSON.parse(readFileSync(new URL('../client-wire/fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));

// Fixed wire fixtures test the SDK admission/projection boundary, not an Owner
// transition. Actual submitted Run/Delivery cases live in the Host acceptance.
for (const [state, observation] of [['streaming', 'delivery_streaming'], ['failed', 'delivery_failed'],
  ['cancelled', 'delivery_cancelled'], ['succeeded', 'host_delivery_succeeded']]) {
  test(`delivery projection retains ${state} without borrowing Run or application outcomes`, async t => {
    const reply = structuredClone(found);
    if (state !== 'succeeded') {
      reply.record.state = state;
      delete reply.record.delivered_sha256;
      delete reply.record.result_delivery_receipt_cid;
      reply.hostReleaseReceipt = null;
      if (state === 'failed') {
        reply.record.exposure = 'unknown_additional';
        reply.record.possible_unconfirmed_max_bytes = 5;
        reply.record.cleanup_owner_cids = [cid('7')];
      }
    }
    const operations = [];
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation) {
        operations.push(operation);
        if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local',
          owner: 'local', durability: 'volatile', scopeRef: 'scope', capabilities: [],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
            maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
        if (operation === 'attach') return {ref, durability: 'volatile', revision: 1};
        if (operation === 'delivery-attempt') return reply;
        assert.fail('Unexpected operation');
      },
    });
    t.after(() => client.close());
    const lookup = await (await client.attach(ref)).result('answer').deliveryAttempt('read-a');
    const explanation = explainDeliveryAttempt(lookup);
    assert.equal(explanation.observation, observation, '[check-mutation:delivery-observation-classification]');
    assert.equal(explanation.recordSequence, 0);
    assert.equal(explanation.hostConfirmedByteCount, 17);
    assert.equal(explanation.exposure, state === 'failed' ? 'unknown_additional' : 'exact');
    assert.equal(explanation.cleanup, state === 'failed' ? 'unresolved' : undefined);
    assert.equal(explanation.possibleUnconfirmedMaxBytes, state === 'failed' ? 5 : undefined);
    assert.equal(explanation.hostReleaseReceiptCid, state === 'succeeded' ? cid('1') : undefined);
    assert.equal(explanation.deliveredSha256, state === 'succeeded' ? '6'.repeat(64) : undefined);
    assert.equal(explainDeliveryAttempt({...lookup}), undefined);
    assert.equal(Object.hasOwn(explanation, 'rowsYielded'), false);
    assert.equal(Object.hasOwn(explanation, 'runStatus'), false);
    assert.equal(Object.hasOwn(explanation, 'cleanupComplete'), false);
    assert.equal(Object.hasOwn(explanation, 'applicationPersisted'), false);
    const before = [...operations];
    for (const format of ['text', 'html', 'json']) {
      assert.ok(formatDeliveryAttempt(lookup, {format}));
    }
    assert.deepEqual(operations, before);
    assert.deepEqual(operations, ['connect', 'attach', 'delivery-attempt']);
  });
}
