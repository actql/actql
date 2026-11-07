// Actual JS assembly/parser with explicit typed Common quantity/extent ports.
// Native arithmetic and real Ledger controls are separate MoonBit tests;
// these ports do not establish numerical funding or physical acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {hubSpotEffectPlanFixture as fixture} from './hubspot-effect-plan.fixture.mjs';

test('HubSpot typed Effect recipe declares all nineteen distinct original physical occurrences and cold constructor', () => {
  const f = fixture(), recipe = f.build(f.options);
  assert.equal(recipe.memberOperations.length, 8); assert.equal(recipe.rowOperations.length, 15);
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
  assert.equal(extent.capacities[0].call.host, 15); assert.equal(extent.capacities[0].call.limits[0], 15);
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
  schema.responseExtent(128, new Uint8Array(128));
  target.responseExtent(256, new Uint8Array(256));
  const actual = f.quotes.slice(before);
  assert(actual.some(q => q.kind === 3 && q.input[0] === 16 && q.input[2] === 30000));
  assert(actual.some(q => q.kind === 4 && q.input[0] === 128 && q.input[2] === 30000));
  assert(actual.some(q => q.kind === 1 && q.input[0] === 256));
  for (const [bytes, body] of [[16, new Uint8Array(15)], [30001, new Uint8Array(30001)], [-1, new Uint8Array(0)]]) {
    assert.throws(() => target.responseExtent(bytes, body), {code: 'HubSpotEffectRecipeUnavailable'});
  }
  assert.throws(() => f.build({...f.options, mappings: []}), {code: 'HubSpotEffectRecipeUnavailable'});
});
