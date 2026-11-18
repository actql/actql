import assert from 'node:assert/strict';
import test from 'node:test';
import {projectDeclaredProjectWritableInventory} from './declared-project-catalog.mjs';
import {declaredProjectWritableInventoryConstructionGeometry,
  declaredProjectWritableRuntimeConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../host-node/installed-effect-plan.mjs';
import {installedRowEffectConstructionLimits} from '../host-node/installed-row-effect.mjs';

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
  assert.equal(driver.workspace.nodes, 788n);
  assert.equal(driver.workspace.text, 430n);
  assert(driver.retained.text > 0n);
  assert.equal(aliases.bounds.aliases, 2n);
  assert(aliases.workspace.text > 0n);
  assert(aliases.workspace.wire > 0n);
  assert.throws(() => declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'source',
    source('crm', [['A', ['a']], ['B', ['b']]])), {message: 'InvalidDeclaredProjectCatalogConstructionGeometry'});
});

test('Mock physical recipe construction inventories its actual selected descriptor normalization',()=>{
  // Explicit quantity-port doubles exercise only the imported JS recipe
  // constructor. They are not a Common original, Resource, Plan or authority.
  // No opaque representation is inspected or passed to an execution owner.
  const quantity=Object.freeze({}),extent=Object.freeze({});
  const ok=value=>({$tag:1,_0:value});
  const moon={
    clientProgramInstalledSourceConstructionCapacity:()=>ok(quantity),
    clientProgramComposeInstalledSourceConstructionCapacity:()=>ok(quantity),
    clientProgramInstalledEffectControlWireBound:()=>ok(1024),
    clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest:()=>ok(Array(6).fill(quantity)),
    clientProgramInstalledEffectCaptureRecipeExtentPrepare:()=>ok(extent),
    clientProgramInstalledEffectOperationStagedExtentPrepare:()=>ok(extent),
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare:()=>ok(extent),
  };
  const zero=Object.freeze({nodes:0n,text:0n,wire:0n});
  const recipe=prepareInstalledPhysicalWritePlanRecipe({moon,operation:'update',targetReadOperation:'read',
    inputLimits:installedRowEffectConstructionLimits({maxRows:100}),
    construction:Object.freeze({retained:zero,workspace:zero}),
    physicalConstruction:quantity,requestConstruction:quantity,
    limits:Object.freeze({maxRequestBytes:1048576,maxRecoveryBytes:1048576,maxResponseBytes:65536,
      maxOutcomeBytes:65536,maxTransferBytes:2097152})});
  assert.equal(recipe.memberOperations.length,2);assert.equal(recipe.rowOperations.length,5);
  assert.equal(recipe.ownedReadOperations.length,3);
  const inspected=[recipe,recipe.memberOperations,recipe.rowOperations,
    ...recipe.memberOperations,...recipe.rowOperations,recipe.savedControlCodec,
    recipe.requestConstruction,recipe.captureConstruction,recipe.recoveryConstruction,
    recipe.physicalWrite,...recipe.ownedReadOperations];
  // These numbers fund precisely the selected normalizer's descriptor
  // families, rather than an incidental test/source-marker count.
  const descriptorCalls=BigInt(inspected.length);
  const descriptorProperties=inspected.reduce((sum,value)=>sum+BigInt(Reflect.ownKeys(value).length),0n);
  assert.equal(descriptorCalls,18n);assert.equal(descriptorProperties,46n);
  const original=source('crm',[['A',['a']],['B',['b']]]);
  const writables=projectDeclaredProjectWritableInventory([original]);
  const measured=declaredProjectWritableRuntimeConstructionGeometry([original],writables,'source',original);
  assert.equal(measured.bounds.descriptorCalls,descriptorCalls);
  assert.equal(measured.bounds.descriptorProperties,descriptorProperties);
  // Descriptor records248 + key/name vectors151 + callbacks87 + Set
  // construction33 + raw recipe66 + provider input113 + args79 + keys7.
  assert.equal(measured.workspace.nodes,788n);
  assert.equal(measured.retained.nodes,772n);
});
