import assert from 'node:assert/strict';
import test from 'node:test';
import {verifyTableWriteBinding} from './table-write-binding.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const create = Object.freeze({action: 'create', expectedTable: null,
  capabilityCid: cid('a'), installationBindingCid: cid('b')});
const binding = target => ({_0: 'create_or_replace', _1: target.action,
  _2: target.expectedTable?.table_uuid, _3: target.expectedTable?.generation_cid,
  _4: target.capabilityCid, _5: target.installationBindingCid});

test('fixed Table intent validates create and exact replacement generation', () => {
  verifyTableWriteBinding(create, binding(create));
  const replace = {...create, action: 'replace', expectedTable: {
    table_uuid: '12345678-1234-1234-1234-123456789abc', generation_cid: cid('c')}};
  verifyTableWriteBinding(replace, binding(replace));
  for (const change of [{_0: 'create'}, {_1: 'create'}, {_2: 'other'},
    {_3: cid('d')}, {_4: cid('d')}, {_5: cid('d')}]) {
    assert.throws(() => verifyTableWriteBinding(replace, {...binding(replace), ...change}),
      {code: 'InstalledTableWriteBindingChanged'});
  }
});

test('OR REPLACE create cannot switch to a replace target or refresh its generation', () => {
  const replace = {...create, action: 'replace', expectedTable: {
    table_uuid: '12345678-1234-1234-1234-123456789abc', generation_cid: cid('c')}};
  assert.throws(() => verifyTableWriteBinding(replace, binding(create)),
    {code: 'InstalledTableWriteBindingChanged'});
  assert.throws(() => verifyTableWriteBinding(create, {...binding(create), _3: cid('c')}),
    {code: 'InstalledTableWriteBindingChanged'});
});
