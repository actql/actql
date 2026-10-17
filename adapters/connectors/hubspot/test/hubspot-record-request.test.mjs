import assert from 'node:assert/strict';
import test from 'node:test';
import {
  hubspotProjectProperties, hubspotPrepareWriteBody, hubspotPrepareRecordTarget,
  hubspotCreateRecordWriteInput, hubspotTargetedRecordWriteInput,
  hubspotPrepareRecordBatch, hubspotRecordBatchBody, hubspotRecordBatchEndpoint,
  hubspotRecordBatchObjectType, hubspotRecordBatchCount, hubspotRecheckRecordBatch,
} from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const bounds = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false,
    modificationMetadata: {readOnlyValue: false}},
  {name: 'external_key', type: 'string', fieldType: 'text', hasUniqueValue: true,
    calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'domain', type: 'string', fieldType: 'text', hasUniqueValue: false},
]};
const project = (value = metadata, objectType = 'companies') => checked(
  hubspotProjectProperties(Buffer.from(JSON.stringify(value)), objectType, 4096, 1000, 20, 10, 100));
const body = catalog => checked(hubspotPrepareWriteBody(catalog, ['amount'],
  Buffer.from('{"amount":"9007199254740993.0100000000"}'), ...bounds));
const target = (catalog, key, value) => checked(hubspotPrepareRecordTarget(catalog,
  key, Buffer.from(JSON.stringify(value)), ...bounds));
const batch = (catalog, kind, key, inputs) => checked(hubspotPrepareRecordBatch(
  catalog, kind, key, inputs, 100, 100, 100, 10000, 1000, 20));

test('actual provider embeds original typed documents in create/update/upsert batch envelopes', () => {
  const catalog = project(), value = body(catalog);
  const inputs = [hubspotCreateRecordWriteInput(value, 'create-0')];
  const created = batch(catalog, 0, '', inputs);
  assert.equal(hubspotRecordBatchEndpoint(created), 'create');
  assert.equal(hubspotRecordBatchObjectType(created), 'companies');
  assert.equal(hubspotRecordBatchBody(created),
    '{"inputs":[{"objectWriteTraceId":"create-0","properties":{"amount":"9007199254740993.0100000000"}}]}');
  inputs.length = 0;
  assert.equal(hubspotRecordBatchCount(created), 1);
  const updated = batch(catalog, 1, 'id', [hubspotTargetedRecordWriteInput(value,
    target(catalog, 'id', '9007199254740993'), 'update-0')]);
  assert.equal(hubspotRecordBatchEndpoint(updated), 'update');
  assert.equal(hubspotRecordBatchBody(updated),
    '{"inputs":[{"id":"9007199254740993","objectWriteTraceId":"update-0","properties":{"amount":"9007199254740993.0100000000"}}]}');
  const upsert = batch(catalog, 2, 'external_key', [hubspotTargetedRecordWriteInput(value,
    target(catalog, 'external_key', 'a/b?é'), 'upsert-0')]);
  assert.equal(hubspotRecordBatchEndpoint(upsert), 'upsert');
  assert.equal(hubspotRecordBatchBody(upsert),
    '{"inputs":[{"id":"a/b?é","idProperty":"external_key","objectWriteTraceId":"upsert-0","properties":{"amount":"9007199254740993.0100000000"}}]}');
  checked(hubspotRecheckRecordBatch(upsert, project(), 100));
});

test('actual provider refuses domain uniqueness inference, foreign bodies, operation substitution and duplicate traces', () => {
  const catalog = project(), value = body(catalog);
  const original = hubspotTargetedRecordWriteInput(value, target(catalog, 'id', '1'), 'original');
  for (const evidence of [false, undefined]) {
    const current = structuredClone(metadata);
    if (evidence === undefined) delete current.results[2].hasUniqueValue;
    assert.throws(() => target(project(current), 'domain', 'same.example'), {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => batch(catalog, 0, '', [original]), {code: 'MoonBitHostFailure'});
  assert.throws(() => batch(catalog, 2, 'external_key', [original]), {code: 'MoonBitHostFailure'});
  assert.throws(() => batch(catalog, 99, '', [original]), {code: 'MoonBitHostFailure'});
  assert.throws(() => batch(catalog, 1, 'id', [original, original]), {code: 'MoonBitHostFailure'});
  const foreign = project(metadata, 'contacts');
  assert.throws(() => batch(catalog, 0, '', [hubspotCreateRecordWriteInput(body(foreign), 'foreign')]),
    {code: 'MoonBitHostFailure'});
  const request = batch(catalog, 1, 'id', [original]);
  assert.throws(() => checked(hubspotRecheckRecordBatch(request, foreign, 100)),
    {code: 'MoonBitHostFailure'});
});
