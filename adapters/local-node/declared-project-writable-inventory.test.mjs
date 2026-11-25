import assert from 'node:assert/strict';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {projectDeclaredProjectWritableInventory} from './declared-project-catalog.mjs';
import {declaredProjectWritableInventoryConstructionGeometry,
  declaredProjectWritableRuntimeConstructionGeometry}
  from '../host-node/declared-project-catalog-construction.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../host-node/installed-effect-plan.mjs';
import {createInstalledRowEffect, installedRowEffectConstructionLimits,
  prepareInstalledTargetPlanRecipes} from '../host-node/installed-row-effect.mjs';
import {installedEffectFor} from '../host-node/installed-effect-inventory.mjs';
import {runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

// Post-admission metadata DATA only. These sentinels issue no Common original,
// physical file, Run, Account, grant, claim or cleanup receipt.
function source(connection, specs) {
  const declaration = Object.freeze({});
  const physical = Object.freeze(specs.map(([resource, itemsPath]) => Object.freeze({
    resource, declaration, itemsPath: Object.freeze(itemsPath), keyPath: Object.freeze(['id']),
    primaryIdentity: 'id', schema: Object.freeze({id: Object.freeze({type: 'string'}),
      value: Object.freeze({type: 'string'})})})));
  const writes = Object.freeze(specs.map(([resource, , permission = 'update', observe_permission = 'read']) => Object.freeze({resource,
    aliases: Object.freeze([connection + '.' + resource]), mappingWire: resource,
    permission, observe_permission})));
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
  // The two-target inventory includes the footprint extent, role and index.
  assert.equal(driver.workspace.nodes, 788n + 117n);
  assert.equal(driver.workspace.text, 430n + 4n * (6n + 10n) + 2n);
  assert(driver.retained.text > 0n);
  assert.equal(aliases.bounds.aliases, 2n);
  assert(aliases.workspace.text > 0n);
  assert(aliases.workspace.wire > 0n);
  assert.throws(() => declaredProjectWritableRuntimeConstructionGeometry(sources, writables, 'source',
    source('crm', [['A', ['a']], ['B', ['b']]])), {message: 'InvalidDeclaredProjectCatalogConstructionGeometry'});
});

function physicalRecipe(operation, targetReadOperation, entryLimit = 1024) {
  // Explicit quantity-port doubles exercise only the imported JS recipe
  // constructor. They are not a Common original, Resource, Plan or authority.
  // No opaque representation is inspected or passed to an execution owner.
  const quantity=Object.freeze({controls: 'exact'}), fallback=Object.freeze({controls: 'fallback'});
  const ok=value=>({$tag:1,_0:value});
  const extent = operation => ok(Object.freeze({operation}));
  const moon={
    clientProgramInstalledSourceConstructionCapacity:()=>ok(quantity),
    clientProgramComposeInstalledSourceConstructionCapacity:()=>ok(quantity),
    clientProgramInstalledEffectControlWireBound:()=>ok(entryLimit),
    clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest:(...args)=>
      ok(Array(6).fill(args.at(-2) === 0 ? fallback : quantity)),
    clientProgramInstalledEffectCaptureRecipeExtentPrepare:extent,
    clientProgramInstalledEffectOperationStagedExtentPrepare:ok,
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare:extent,
  };
  const zero=Object.freeze({nodes:0n,text:0n,wire:0n});
  return prepareInstalledPhysicalWritePlanRecipe({moon,operation,targetReadOperation,
    inputLimits:installedRowEffectConstructionLimits({maxRows:100}),
    construction:Object.freeze({retained:zero,workspace:zero}),
    physicalConstruction:quantity,requestConstruction:quantity,
    limits:Object.freeze({maxRequestBytes:1048576,maxRecoveryBytes:1048576,maxResponseBytes:65536,
      maxOutcomeBytes:65536,maxTransferBytes:2097152})});
}

test('Mock physical recipe construction inventories its actual selected descriptor normalization',()=>{
  const recipe = physicalRecipe('update', 'read');
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
  // The actual recipe above has no plural footprint extent. Compare it to
  // the corresponding single-target inventory, not the plural quote.
  const original=source('crm',[['A',['a']]]);
  const writables=projectDeclaredProjectWritableInventory([original]);
  const measured=declaredProjectWritableRuntimeConstructionGeometry([original],writables,'source',original);
  assert.equal(measured.bounds.descriptorCalls,descriptorCalls);
  assert.equal(measured.bounds.descriptorProperties,descriptorProperties);
  // Descriptor records248 + key/name vectors151 + callbacks87 + Set
  // construction33 + raw recipe66 + provider input113 + args79 + keys7.
  assert.equal(measured.workspace.nodes,786n);
  assert.equal(measured.retained.nodes,768n + 2n + 16n);
});

test('Mock constructor funds an additional operation recipe only for distinct target permissions', () => {
  const uniform = source('crm', [['A', ['a']], ['B', ['b']]]);
  const routed = source('crm', [['A', ['a']], ['B', ['b'], 'update-contact', 'observe-contact']]);
  const quote = original => declaredProjectWritableRuntimeConstructionGeometry([original],
    projectDeclaredProjectWritableInventory([original]), 'source', original);
  const before = quote(uniform), after = quote(routed);
  assert.equal(before.bounds.targets, 2n);
  assert.deepEqual(after.bounds, before.bounds);
  // One extra recipe, its footprint controls, table/maxima/association,
  // and two entries including the preconstructed fallback wrappers.
  assert.equal(after.retained.nodes - before.retained.nodes, 768n + 32n + 12n + 48n);
  assert.equal(after.workspace.nodes - before.workspace.nodes, 16n + 24n);
  // Second recipe adds two write suffixes, three read suffixes, and footprint.
  const addedUnits = 3n * 14n + 3n * 15n + 90n;
  assert.equal(after.retained.text - before.retained.text, 2n * addedUnits);
  assert.equal(after.workspace.text - before.workspace.text, 4n * addedUnits);
  assert.equal(after.retained.wire, before.retained.wire);
});

test('installed target recipes retain two exact Mappings and reject inconsistent operation originals', async t => {
  const unused = () => assert.fail('invalid operation recipe reached an authority or effect port');
  const root = await mkdtemp(join(tmpdir(), 'actql-mock-target-recipes-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const cid = letter => 'sha256:' + letter.repeat(64);
  const [account, contact, lead, newLead] = [
    ['Account', 'a'], ['Contact', 'b'], ['Lead', 'e'], ['NewLead', 'f', 'create'],
  ].map(([resource, letter, kind = 'update']) => {
    const mappingCid = cid(letter), operation = 'write-' + letter;
    return Object.freeze({resource, mappingCid, mappingRef: 'mapping:crm/' + resource,
      body: JSON.stringify({mapping_contract_cid: mappingCid, minimum_approval: 'required',
        target_ref: 'connector://crm/' + resource, permission_rules: [{effect_kind: kind, permissions: [operation]}]})});
  });
  // Explicit compiler/plan ports observe selected recipes. The real Host
  // entrance runs, but no native Plan, grant, managed Run or I/O is issued.
  const prepared = Object.freeze({}), identity = Object.freeze({});
  const compilation = Object.freeze({}), composedCompilation = Object.freeze({}), createCompilation = Object.freeze({});
  const demand = [];
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture-unused',
    clientProgramEffectCompilationPlanWire(actual) {
      assert(actual === compilation || actual === composedCompilation || actual === createCompilation);
      return JSON.stringify({execution_material: {program: {id: 'p',
        stages: [{id: 's', steps: [{values: {}}], effects: actual === compilation
          ? {contact: {}, account: {}} : actual === createCompilation
            ? {contact: {}, newLead: {}} : {contact: {}, lead: {}}}]}}});
    },
    clientProgramEffectMemberDescriptor(actual, stage, effectId) {
      assert.equal(actual, prepared);
      assert.equal(stage, 0);
      const [index, mapping] = effectId === 'contact' ? [0, contact] :
        [1, {account, lead, newLead}[effectId]];
      return ok(runtimeTupleFromFields([index, effectId, mapping === newLead ? 'create' : 'update',
        'connector://crm/' + mapping.resource,
        mapping.mappingRef, mapping.mappingCid, Object.freeze({})]));
    },
    clientProgramEffectAcquisitionCount: actual => {assert.equal(actual, prepared); return 0;},
    clientProgramInstalledEffectOperationDemandWithControlsPrepare(actual, stage, id, members, rows, controls) {
      assert.equal(actual, prepared);
      assert.equal(stage, 0);
      demand.push({id, members: members.map(value => value.operation), rows: rows.map(value => value.operation),
        controls: controls.controls});
      return ok(id);
    },
    clientProgramInstalledEffectManagedPlanPrepare(actual, original, ...selected) {
      assert.equal(actual, prepared);
      assert.equal(original, identity);
      assert.deepEqual(selected.at(-1), demand.map(value => value.id));
      return ok(demand);
    },
  };
  const mappings = Object.freeze([account, contact]);
  const options = {moon, mappings, environmentWire: '{}',
    connectorId: 'crm', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1', connection: 'crm',
    site: {issueEffectGrant: unused, issueReadGrant: unused, close: () => true}, authorization: {authorize: unused},
    runtimeBundleCid: cid('c'), bindingCid: cid('d'), ledgerRoot: join(root, 'ledger'),
    driver: {kinds: ['update'], targetRead: {operation: 'legacy-read'},
      prepareRequest: unused, requestFacts: unused, writeOperation: unused, send: unused,
      project: unused, footprint: unused, observeTargets: unused, recoveryEntry: unused,
      recoverRequests: unused, recoverMemberRequests: unused, requestCid: unused}};
  const route = (letter, read = 'read-' + letter) =>
    Object.freeze({recipe: physicalRecipe('write-' + letter, 'read-' + letter), targetReadOperation: read});
  for (const recipes of [
    {[account.mappingCid]: route('a')},
    {[account.mappingCid]: route('a'), [cid('f')]: route('b')},
    {[account.mappingCid]: route('a'), [contact.mappingCid]: route('b', 'legacy-read')},
  ]) {
    assert.throws(() => prepareInstalledTargetPlanRecipes(mappings, Object.freeze(recipes)),
      {code: 'InvalidInstalledEffectPlanRecipe'});
  }
  const swapped = prepareInstalledTargetPlanRecipes(mappings,
    Object.freeze({[account.mappingCid]: route('a'), [contact.mappingCid]: route('a')}));
  await assert.rejects(createInstalledRowEffect({...options, managedTargetPlanRecipes: swapped}),
    {code: 'InvalidInstalledEffectPlanRecipe'});
  const exact = Object.freeze({[account.mappingCid]: route('a'), [contact.mappingCid]: route('b')});
  const funded = prepareInstalledTargetPlanRecipes(mappings, exact);
  for (const changed of [
    {...options, managedTargetPlanRecipes: exact},
    {...options, mappings: Object.freeze([...mappings]), managedTargetPlanRecipes: funded},
  ]) {
    await assert.rejects(createInstalledRowEffect(changed), {code: 'InvalidInstalledEffectPlanRecipe'});
  }
  const createRoute = letter => Object.freeze({recipe: physicalRecipe('write-' + letter),
    targetReadOperation: undefined});
  const mixedMappings = Object.freeze([contact, newLead]);
  const mixedOptions = {...options, mappings: mixedMappings,
    driver: {...options.driver, kinds: ['update', 'create']}};
  for (const entries of [
    {[contact.mappingCid]: createRoute('b'), [newLead.mappingCid]: createRoute('f')},
    {[contact.mappingCid]: route('b'), [newLead.mappingCid]: route('f')},
  ]) {
    const mixed = prepareInstalledTargetPlanRecipes(mixedMappings, Object.freeze(entries));
    await assert.rejects(createInstalledRowEffect({...mixedOptions, managedTargetPlanRecipes: mixed}),
      {code: 'InvalidInstalledEffectPlanRecipe'});
  }
  assert.deepEqual(await readdir(root), [], 'refused recipes cannot initialize the ledger');
  const effect = await createInstalledRowEffect({...options, managedTargetPlanRecipes: funded});
  assert.deepEqual(effect.effectSelectors.map(value => value.mappingCid), [account.mappingCid, contact.mappingCid]);
  const inputs = {values: '[]', installedContracts: {}};
  assert.deepEqual(effect.prepareManagedPlan({prepared, identity, compilation}, inputs), [
    {id: 'contact', members: ['write-b.capture', 'write-b.capture'],
      rows: ['write-b.request', 'write-b', 'read-b.capture-target', 'read-b.apply-target', 'read-b.resume-target'],
      controls: 'exact'},
    {id: 'account', members: ['write-a.capture', 'write-a.capture'],
      rows: ['write-a.request', 'write-a', 'read-a.capture-target', 'read-a.apply-target', 'read-a.resume-target'],
      controls: 'exact'},
  ]);
  const legacy = await createInstalledRowEffect({...options, mappings: [lead], bindingCid: cid('e'),
    managedPlanRecipe: physicalRecipe('write-e', 'read-e', 4096)});
  const composed = installedEffectFor({effects: [effect, legacy], environmentWire: '{}'}, [
    {...effect.effectSelectors[1], effectId: 'contact'}, {...legacy.effectSelectors[0], effectId: 'lead'},
  ]);
  demand.length = 0;
  assert.deepEqual(composed.prepareManagedPlan({prepared, identity, compilation: composedCompilation}, inputs), [
    {id: 'contact', members: ['write-b.capture', 'write-b.capture'],
      rows: ['write-b.request', 'write-b', 'read-b.capture-target', 'read-b.apply-target', 'read-b.resume-target'],
      controls: 'fallback'},
    {id: 'lead', members: ['write-e.capture', 'write-e.capture'],
      rows: ['write-e.request', 'write-e', 'read-e.capture-target', 'read-e.apply-target', 'read-e.resume-target'],
      controls: 'exact'},
  ]);
  const mixed = await createInstalledRowEffect({...mixedOptions,
    managedTargetPlanRecipes: prepareInstalledTargetPlanRecipes(mixedMappings, Object.freeze({
      [contact.mappingCid]: route('b'), [newLead.mappingCid]: createRoute('f'),
    }))});
  demand.length = 0;
  assert.deepEqual(mixed.prepareManagedPlan({prepared, identity, compilation: createCompilation}, inputs), [
    {id: 'contact', members: ['write-b.capture', 'write-b.capture'],
      rows: ['write-b.request', 'write-b', 'read-b.capture-target', 'read-b.apply-target', 'read-b.resume-target'],
      controls: 'exact'},
    {id: 'newLead', members: ['write-f.capture', 'write-f.capture'],
      rows: ['write-f.request', 'write-f'], controls: 'exact'},
  ]);
  assert.equal(await effect.close(), true);
  assert.equal(await legacy.close(), true);
  assert.equal(await mixed.close(), true);
});
