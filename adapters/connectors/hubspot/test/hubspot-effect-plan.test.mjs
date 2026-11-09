// Actual JS assembly/parser with explicit typed Common quantity/extent ports.
// Native arithmetic and real Ledger controls are separate MoonBit tests;
// these ports do not establish numerical funding or physical acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {hubSpotEffectPlanFixture as fixture} from './hubspot-effect-plan.fixture.mjs';

test('HubSpot typed Effect recipe declares all nineteen distinct original physical occurrences and cold constructor', () => {
  const f = fixture(), recipe = f.build(f.options);
  assert.equal(recipe.memberOperations.length, 9); assert.equal(recipe.rowOperations.length, 15);
  assert.equal(recipe.credentialOperations.length, 19);
  assert.equal(new Set(recipe.credentialOperations.map(o => (o.perRow === false ? 'm' : 'r') + o.operationIndex)).size, 19);
  assert.notEqual(recipe.requestConstruction.operationIndex, recipe.requestFinalization.operationIndex);
  assert.notEqual(recipe.captureConstruction.operationIndex, recipe.recoveryConstruction.operationIndex);
  const describe = recipe.credentialOperations.filter(o => o.phase.endsWith('-describe'));
  assert.equal(describe.length, 6); assert(describe.every(o => o.perRow === false && ['account', 'properties'].includes(o.resource)));
  const targets = recipe.credentialOperations.filter(o => o.phase.endsWith('-target'));
  assert.equal(targets.length, 12);
  assert.deepEqual(targets.filter(o => o.slot === 'target').map(o => [o.resource, o.perRow]),
    [[undefined, true], [undefined, true], [undefined, true]]);
  assert.equal(recipe.credentialOperations.at(-1).phase, 'write');
  assert.equal(f.quotes.find(q => q.kind === 0).input.length, 23);
  assert(f.compositions.some(call => call.host === -1)); assert(f.compositions.some(call => call.control === 0));
  const extent = recipe.recoveryConstruction.inputExtent('{}', [{memberIndex: 0, wire: '{"requests":[]}'}], 0);
  assert.equal(extent.capacities[0].call.host, 15);
  assert.equal(extent.capacities[0].call.limits[0], 1000000);
  assert.equal(extent.capacities[0].call.limits[1], 10000);
  assert.throws(() => recipe.recoveryConstruction.inputExtent('{}', [{memberIndex: 0, wire: 'x'.repeat(65537)}], 0),
    {code: 'HubSpotEffectRecipeUnavailable'});
});

test('HubSpot typed Effect recipe retains captured quantities and checks exact received body before staged Native projection', () => {
  const f = fixture(), recipe = f.build(f.options);
  f.options.limits.read.maxResponseBytes = 1000000;
  for (const key of Object.keys(f.moon)) f.moon[key] = () => {throw new Error('Substituted export');};
  const account = recipe.credentialOperations.find(o => o.phase === 'apply-describe' && o.slot === 'account');
  const schema = recipe.credentialOperations.find(o => o.phase === 'apply-target' && o.slot === 'schema-before');
  const target = recipe.credentialOperations.find(o => o.phase === 'apply-target' && o.slot === 'target');
  const before = f.quotes.length;
  account.responseExtent(16, new Uint8Array(16));
  const geometry=Object.freeze([128,128,2,1,4,8,40,12,2,1,3,16]);
  schema.responseExtent(128, new Uint8Array(128),geometry);
  target.responseExtent(256, new Uint8Array(256));
  const actual = f.quotes.slice(before);
  assert(actual.some(q => q.kind === 3 && q.input[0] === 16 && q.input[2] === 30000));
  assert(actual.some(q => q.kind === 4 && q.input[0] === 128 && q.input[2] === 30000));
  assert.deepEqual(actual.find(q=>q.kind===4).counts,geometry);
  assert(actual.filter(q=>q.kind===3).every(q=>q.counts.length===0));
  assert(actual.some(q => q.kind === 1 && q.input[0] === 256));
  for (const [bytes, body] of [[16, new Uint8Array(15)], [30001, new Uint8Array(30001)], [-1, new Uint8Array(0)]]) {
    assert.throws(() => target.responseExtent(bytes, body), {code: 'HubSpotEffectRecipeUnavailable'});
  }
  assert.throws(() => f.build({...f.options, mappings: []}), {code: 'HubSpotEffectRecipeUnavailable'});
});


test('HubSpot fixed footprint binds a scratch-only original member distinct from all physical and capture roles',()=>{
  const f=fixture(),recipe=f.build(f.options),index=recipe.footprintConstruction.operationIndex;
  assert.notEqual(index,recipe.captureConstruction.operationIndex);assert.notEqual(index,recipe.recoveryConstruction.operationIndex);
  const original=recipe.memberOperations[index];assert.equal(original.operation,'hubspot:objects:batch-update.footprint');
  assert.equal(original.extent.physical,false);assert.equal(original.extent.transfer,0n);
  assert.deepEqual(original.extent.capacity,{opaqueBoundary:true,origin:f.options.origin,account:f.options.portalId,units:f.options.objectTypeUnits});
  assert(recipe.credentialOperations.every(entry=>entry.perRow!==false||entry.operationIndex!==index));
});


test('HubSpot every reachable read binds same empty header contract without changing full constructor quantities', () => {
  const f=fixture(),recipe=f.build(f.options),reads=recipe.credentialOperations.slice(0,-1);
  assert.equal(reads.length,18);
  for(const read of reads){
    const original=(read.perRow===false?recipe.memberOperations:recipe.rowOperations)[read.operationIndex].extent;
    assert.equal(original.initial.emptyHeaders,16384);assert.equal(original.maximum.emptyHeaders,16384);
    assert.equal(original.initial.capacity.index,read.slot==='target'?6:7);
    if(read.slot==='schema-after')assert(original.initial.discardedProjection);
    const body=new Uint8Array(16),received=read.responseExtent(16,body);
    assert.equal(received.emptyHeaders,original.initial.emptyHeaders);
    assert.equal(received.capacity.index,original.initial.capacity.index);
    assert.equal(received.capacity.call.original[3]._0.input[0],read.slot==='target'?0:16);
  }
  const write=recipe.rowOperations[recipe.credentialOperations.at(-1).operationIndex].extent;
  assert.equal(write.emptyHeaders,undefined,'Unspecified write keeps full original bound');
});
