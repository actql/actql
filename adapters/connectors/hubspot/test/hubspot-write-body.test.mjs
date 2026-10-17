import assert from 'node:assert/strict';
import test from 'node:test';
import {
  hubspotProjectProperties,
  hubspotPrepareWriteBody,
  hubspotWriteBodyPropertiesJson,
  hubspotWriteBodyValueJson,
  hubspotWriteBodyPropertyNames,
  hubspotRecheckWriteBody,
} from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false,
    modificationMetadata: {readOnlyValue: false}},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', calculated: false,
    modificationMetadata: {readOnlyValue: false}, options: [{value: 'a'}, {value: 'b'}]},
]};
const project = (value = metadata, objectType = 'companies') => checked(
  hubspotProjectProperties(Buffer.from(JSON.stringify(value)), objectType, 4096, 1000, 20, 10, 100));
const limits = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const prepare = (catalog, names, wire, bounds = limits) => checked(
  hubspotPrepareWriteBody(catalog, names, Buffer.from(wire), ...bounds));

test('actual generated provider preserves the complete exact write candidate and original catalog', () => {
  const catalog = project();
  const names = ['tags', 'amount'];
  const body = prepare(catalog, names, '{"amount":"9007199254740993.0100000000","tags":["a","b"]}');
  assert.equal(hubspotWriteBodyPropertiesJson(body),
    '{"amount":"9007199254740993.0100000000","tags":"a;b"}');
  assert.equal(hubspotWriteBodyValueJson(body),
    '{"amount":"9007199254740993.0100000000","tags":["a","b"]}');
  names[0] = 'injected';
  const copy = hubspotWriteBodyPropertyNames(body);
  copy.push('injected');
  assert.deepEqual(hubspotWriteBodyPropertyNames(body), ['tags', 'amount']);
  checked(hubspotRecheckWriteBody(body, project(), 10));
  assert.throws(() => checked(hubspotRecheckWriteBody(body, project(metadata, 'contacts'), 10)),
    {code: 'MoonBitHostFailure'});
  const changed = structuredClone(metadata);
  changed.results[0].modificationMetadata.readOnlyValue = true;
  assert.throws(() => checked(hubspotRecheckWriteBody(body, project(changed), 10)),
    {code: 'MoonBitHostFailure'});
});

test('actual provider refuses lossy decimals, unlisted or delimiter values and incomplete mappings', () => {
  const catalog = project();
  for (const wire of [
    '{"amount":9007199254740993.01,"tags":["a"]}',
    '{"amount":"1.0000000000","tags":["label"]}',
    '{"amount":"1.0000000000","tags":["a;b"]}',
    '{"amount":"1.0000000000"}',
    '{"amount":"1.0000000000","tags":[],"extra":"x"}',
  ]) assert.throws(() => prepare(catalog, ['amount', 'tags'], wire), {code: 'MoonBitHostFailure'});
  const noWriteEvidence = structuredClone(metadata);
  delete noWriteEvidence.results[0].calculated;
  assert.throws(() => prepare(project(noWriteEvidence), ['amount'], '{"amount":null}'),
    {code: 'MoonBitHostFailure'});
});

test('actual provider keeps empty-array and numeric-clear values distinct and enforces byte bounds', () => {
  const catalog = project();
  const wire = '{"amount":null,"tags":[]}';
  const body = prepare(catalog, ['amount', 'tags'], wire);
  assert.equal(hubspotWriteBodyPropertiesJson(body), '{"amount":"","tags":""}');
  assert.equal(hubspotWriteBodyValueJson(body), wire);
  assert.throws(() => prepare(catalog, ['amount', 'tags'], '{"amount":null,"tags":null}'),
    {code: 'MoonBitHostFailure'});
  const exact = [...limits];
  exact[0] = Buffer.byteLength(wire);
  prepare(catalog, ['amount', 'tags'], wire, exact);
  exact[0]--;
  assert.throws(() => prepare(catalog, ['amount', 'tags'], wire, exact), {code: 'MoonBitHostFailure'});
});
