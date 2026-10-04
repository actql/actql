import assert from 'node:assert/strict';
import test from 'node:test';
import {salesforceEffectTargetReadInventory} from
  '../host/installed-salesforce-effect.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
function fixture() {
  let calls = 0;
  const site = {connection: 'crm', context: {contextCid: cid('1')},
    namespaceId: 'namespace', principal: 'owner', environment: 'test',
    connectionRevision: 'revision-1', orgId: 'org-1',
    instanceOrigin: 'https://example.invalid', siteKey: 'site-1',
    siteGeneration: 'generation-1', apiVersion: 'v61.0',
    cliAlias: 'fixture', cliUsername: 'fixture@example.invalid',
    credentialAuthorityId: 'credential', credentialKeyId: 'key-1',
    credentialPrivateKeyPath: '/fixture/key.pem', caPath: '/fixture/ca.pem',
    issueGrant() { assert.fail('Inventory must not issue grants'); },
    describeEffectCatalog() { assert.fail('Inventory must not read the provider'); }};
  const installed = {generationCid: cid('2'), mappings: [
    {mappingCid: cid('3'), mappingRef: 'mapping:account',
      write: {resource: 'Account', kind: 'update', fields: ['Name']}},
    {mappingCid: cid('4'), mappingRef: 'mapping:contact',
      write: {resource: 'Contact', kind: 'update', fields: ['Name']}},
  ]};
  const ids = ['account', 'contact', 'account_again'];
  const prepared = {};
  const moon = {clientProgramEffectMemberDescriptor(actual, stage, id) {
    calls++;
    assert.equal(actual, prepared);
    assert.equal(stage, 1);
    const index = ids.indexOf(id);
    const mapping = installed.mappings[index === 1 ? 1 : 0];
    return {$tag: 1, _0: {_0: index, _1: id, _2: 'update',
      _4: mapping.mappingRef, _5: mapping.mappingCid, _6: {}}};
  }};
  return {options: {moon, prepared, installed, site, connectorId: 'crm',
    unit: {programId: 'program', stageId: 'write', stageIndex: 1,
      effectIds: ids}}, calls: () => calls};
}

test('target inventory preserves distinct tuples and same-tuple member bindings without I/O', () => {
  const {options, calls} = fixture();
  const inventory = salesforceEffectTargetReadInventory(options);
  assert.equal(calls(), 3);
  assert.deepEqual(inventory.map(item => item.readTuple), [
    {connection: 'crm', resource: 'Account', operation: 'read'},
    {connection: 'crm', resource: 'Contact', operation: 'read'},
    {connection: 'crm', resource: 'Account', operation: 'read'},
  ]);
  assert.deepEqual(inventory.map(item => [item.physicalBinding.effect_id,
    item.physicalBinding.member_index, item.physicalBinding.mapping_cid]), [
    ['account', 0, cid('3')], ['contact', 1, cid('4')],
    ['account_again', 2, cid('3')],
  ]);
  assert.ok(Object.isFrozen(inventory));
  assert.ok(inventory.every(item => Object.isFrozen(item) &&
    Object.isFrozen(item.readTuple) && Object.isFrozen(item.physicalBinding) &&
    Object.isFrozen(item.physicalBinding.fields)));
  options.installed.mappings[0].write.fields = ['Changed'];
  assert.deepEqual(inventory[0].physicalBinding.fields, ['Name']);
});

test('target inventory changes when the Site or installed generation changes', () => {
  const {options} = fixture();
  const original = salesforceEffectTargetReadInventory(options);
  options.site.orgId = 'another-org';
  const changed = salesforceEffectTargetReadInventory(options);
  assert.notEqual(changed[0].physicalBinding.site_binding_cid,
    original[0].physicalBinding.site_binding_cid);
  options.installed.generationCid = cid('5');
  assert.equal(salesforceEffectTargetReadInventory(options)[0]
    .physicalBinding.generation_cid, cid('5'));
});

test('target inventory rejects an unresolved Mapping before any I/O', () => {
  const {options} = fixture();
  options.moon.clientProgramEffectMemberDescriptor = () => ({$tag: 1,
    _0: {_0: 0, _1: 'account', _2: 'update', _4: 'mapping:other',
      _5: cid('f'), _6: {}}});
  assert.throws(() => salesforceEffectTargetReadInventory(options),
    {code: 'SalesforceEffectMappingNotInstalled'});
});
