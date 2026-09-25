import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {admitDurablePayloadJson, admitPayloadRequestJson,
  commitPayloadTransition, durablePayloadRequestCid, durablePayloadRevision,
  durablePayloadState, payloadRecordDigest, payloadRecordDurableJson,
  payloadRecordOpaqueGeneration, payloadRequestCid,
  payloadTransitionDurableJson, payloadTransitionExpectedRevision,
  preparePayloadOpaqueOwned, preparePayloadOpaqueReclaiming,
  preparePayloadOpaqueSealed, preparePayloadReclaimed,
  preparePayloadRecord, preparePayloadReserved, preparePayloadWriting,
  restoreDurablePayload} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const requestBody = JSON.stringify({
  durable_codec_cid: cid('1'), logical_relation_cid: cid('2'),
  material_generation_cid: cid('3'), max_bytes: '32',
  ordering_evidence_cid: cid('4'), publication_attempt_cid: cid('5'),
  result_definition_cid: cid('6'), result_schema_cid: cid('7'),
  row_count: '2', store_authority_cid: cid('8'),
  version: 'actql-publication-payload-request/0.1',
});
const requestCid = `sha256:${createHash('sha256').update(requestBody)
  .digest('hex')}`;

test('opaque Store custody uses one durable MoonBit payload owner', () => {
  assert.throws(() => admitPayloadRequestJson(requestBody, cid('f')),
    {code: 'CoordinatorOwnerRejected'});
  const request = admitPayloadRequestJson(requestBody, requestCid);
  assert.equal(payloadRequestCid(request), requestCid);
  let record = preparePayloadRecord(request);
  let persisted = payloadRecordDurableJson(record);
  const advance = transition => {
    const current = admitDurablePayloadJson(persisted);
    assert.equal(payloadTransitionExpectedRevision(transition),
      durablePayloadRevision(current));
    const next = payloadTransitionDurableJson(transition);
    const admitted = admitDurablePayloadJson(next);
    assert.equal(durablePayloadRevision(admitted),
      durablePayloadRevision(current) + 1);
    assert.equal(durablePayloadRequestCid(admitted), requestCid);
    persisted = next;
    record = commitPayloadTransition(transition);
    assert.equal(payloadRecordDurableJson(record), persisted);
  };
  advance(preparePayloadReserved(record));
  advance(preparePayloadWriting(record));
  assert.throws(() => preparePayloadOpaqueSealed(record, cid('9'), 12,
    cid('a')), {code: 'CoordinatorOwnerRejected'});
  advance(preparePayloadOpaqueOwned(record, cid('9')));
  assert.equal(durablePayloadState(admitDurablePayloadJson(persisted)),
    'writing');
  assert.throws(() => preparePayloadOpaqueSealed(record, cid('b'), 12,
    cid('a')), {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => preparePayloadOpaqueSealed(record, cid('9'), 33,
    cid('a')), {code: 'CoordinatorOwnerRejected'});
  advance(preparePayloadOpaqueSealed(record, cid('9'), 12n, cid('a')));
  assert.equal(durablePayloadState(admitDurablePayloadJson(persisted)),
    'sealed');
  assert.equal(JSON.parse(persisted).version,
    'actql-publication-payload-record/0.3');
  const reopened = restoreDurablePayload(admitDurablePayloadJson(persisted));
  assert.equal(payloadRecordOpaqueGeneration(reopened), cid('9'));
  assert.equal(payloadRecordDigest(reopened), cid('a'));
  assert.throws(() => admitDurablePayloadJson(persisted.replace(
    `"custody_generation_cid":"${cid('9')}"`,
    `"custody_generation_cid":"${cid('b')}"`)),
  {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => preparePayloadOpaqueReclaiming(reopened, cid('b')),
    {code: 'CoordinatorOwnerRejected'});
  record = reopened;
  advance(preparePayloadOpaqueReclaiming(record, cid('9')));
  advance(preparePayloadReclaimed(record));
  assert.equal(durablePayloadState(admitDurablePayloadJson(persisted)),
    'reclaimed');
});
