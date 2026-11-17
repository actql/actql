import assert from 'node:assert/strict';
import test from 'node:test';
import {projectDeclaredProjectWritableInventory} from './declared-project-catalog.mjs';
import {declaredProjectWritableInventoryConstructionGeometry,
  declaredProjectWritableRuntimeConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';

// Post-admission metadata DATA only. These sentinels issue no Common original,
// physical file, Run, Account, grant, claim or cleanup receipt.
function source(connection, specs) {
  const declaration = Object.freeze({});
  const physical = Object.freeze(specs.map(([resource, itemsPath]) => Object.freeze({
    resource, declaration, itemsPath: Object.freeze(itemsPath), keyPath: Object.freeze(['id']),
    primaryIdentity: 'id', schema: Object.freeze({id: Object.freeze({type: 'string'}),
      value: Object.freeze({type: 'string'})})})));
  const writes = Object.freeze(specs.map(([resource]) => Object.freeze({resource,
    aliases: Object.freeze([connection + '.' + resource]), mappingWire: resource,
    permission: 'update', observe_permission: 'read'})));
  const mappings = Object.freeze(specs.map(([resource]) => Object.freeze({resource, body: resource})));
  return Object.freeze({catalogue: Object.freeze({connection}), physical, writes,
    effectPrepared: Object.freeze({mappings, environment: Object.freeze({
      wire: '{"connector_manifest":{"connectors":[]},"mapping_contracts":[]}'})})});
}

test('Mock writable metadata retains two disjoint collections from one original source', () => {
  const original = source('crm', [['Contacts', ['crm', 'contacts']], ['Accounts', ['crm', 'accounts']]]);
  const result = projectDeclaredProjectWritableInventory([original]);
  assert.deepEqual(result.map(value => value.write.resource), ['Accounts', 'Contacts']);
  assert.equal(result.length, 2);
  for (const value of result) {
    assert.equal(value.source, original);
    assert.equal(value.physical, original.physical.find(row => row.resource === value.write.resource));
    assert.equal(value.mapping, original.effectPrepared.mappings.find(row => row.resource === value.write.resource));
    assert.deepEqual(value.beforeFields, ['id', 'value']);
    assert(Object.isFrozen(value));
    assert(Object.isFrozen(value.beforeFields));
  }
  assert(Object.isFrozen(result));
  const next = source('other', [['Leads', ['other', 'leads']]]);
  assert.deepEqual(projectDeclaredProjectWritableInventory([next, original])
    .map(value => [value.source.catalogue.connection, value.write.resource]),
  [['crm', 'Accounts'], ['crm', 'Contacts'], ['other', 'Leads']]);
});

test('Mock writable metadata refuses overlapping collections and duplicate logical targets', () => {
  for (const specs of [
    [['A', ['rows']], ['B', ['rows']]],
    [['A', ['rows']], ['B', ['rows', 'nested']]],
    [['A', []], ['B', ['rows']]],
  ]) assert.throws(() => projectDeclaredProjectWritableInventory([source('crm', specs)]),
    {code: 'OverlappingMockWritableCollections'});
  assert.throws(() => projectDeclaredProjectWritableInventory([
    source('crm', [['A', ['first']]]), source('crm', [['A', ['second']]]),
  ]), {code: 'DuplicateMockWritableTarget'});
});

test('Mock writable constructor inventory quantities retain original phase identity', () => {
  const original = source('crm', [['A', ['a']], ['B', ['b']]]), sources = [original];
  const metadata = declaredProjectWritableInventoryConstructionGeometry(sources);
  assert.equal(metadata.bounds.targets, 2n);
  assert.equal(metadata.retained.nodes, 36n); // two target records/vectors and four schema-name slots
  assert.equal(metadata.retained.text, 0n); // every original name remains borrowed
  assert(metadata.workspace.nodes > 0n);
  const writables = projectDeclaredProjectWritableInventory(sources);
  const root = declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'root');
  const driver = declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'source', original);
  const aliases = declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'aliases', original);
  assert.equal(root.bounds.connections, 1n);
  assert.equal(driver.bounds.targets, 2n);
  assert(driver.retained.text > 0n);
  assert.equal(aliases.bounds.aliases, 2n);
  assert(aliases.workspace.text > 0n);
  assert(aliases.workspace.wire > 0n);
  assert.throws(() => declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'source',
    source('crm', [['A', ['a']], ['B', ['b']]])), {message: 'InvalidDeclaredProjectCatalogConstructionGeometry'});
});
