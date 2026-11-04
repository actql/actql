import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledPhysicalWritePlanRecipe} from './installed-effect-plan.mjs';
import {installedRowEffectConstructionLimits} from './installed-row-effect.mjs';

function fixture() {
  const calls = [], physical = Object.freeze({original: 'controlled physical constructor'});
  const quantities = Array.from({length: 6}, (_, index) => Object.freeze({original: index}));
  const fallback = Array.from({length: 6}, (_, index) => Object.freeze({fallback: index}));
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientProgramInstalledSourceConstructionCapacity(...values) {calls.push(['physical', ...values]); return ok(physical);},
    clientProgramInstalledEffectControlWireBound(bytes, maximum) {calls.push(['control', bytes, maximum]); return ok(2000);},
    clientProgramInstalledPhysicalWriteRecipeCapacities(...values) {
      calls.push(['recipe', ...values]); return ok(values.at(-1) === 0 ? fallback : quantities);
    },
    clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation, values) {
      assert.equal(values, quantities); return ok({operation, original: 'capture'});
    },
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return ok({operation, capacity, transfer, physical});
    },
  };
  const construction = Object.freeze({retained: Object.freeze({nodes: 3n, text: 7n, wire: 11n}),
    workspace: Object.freeze({nodes: 5n, text: 13n, wire: 17n})});
  const limits = Object.freeze({maxRequestBytes: 4000, maxRecoveryBytes: 5000,
    maxResponseBytes: 20, maxOutcomeBytes: 31, maxTransferBytes: 123});
  return {calls, physical, quantities, fallback,
    options: {moon, operation: 'files.write', construction, limits,
      inputLimits: installedRowEffectConstructionLimits()}};
}

test('physical writer composer keeps typed original and shared control codec without a credential occurrence', () => {
  const f = fixture(), recipe = prepareInstalledPhysicalWritePlanRecipe(f.options);
  assert.deepEqual(f.calls[0], ['physical', 3n, 7n, 11n, 5n, 13n, 17n]);
  const quotes = f.calls.filter(value => value[0] === 'recipe');
  assert.equal(quotes.length, 2);
  assert.equal(quotes[0].at(-2), f.physical);
  assert.equal(quotes[1].at(-2), f.physical);
  assert.deepEqual(quotes.map(value => value.at(-1)), [2000, 0]);
  assert.deepEqual(recipe.recoveryConstruction, {operationIndex: 1});
  assert.strictEqual(recipe.memberOperations[1].extent, recipe.memberOperations[0].extent);
  assert.equal(recipe.rowOperations[0].extent.capacity, f.quantities[2]);
  assert.equal(recipe.rowOperations[1].extent.capacity, f.quantities[3]);
  assert.equal(recipe.physicalWrite.transferBytes, 123n);
  assert.equal(recipe.rowOperations[recipe.physicalWrite.operationIndex].extent.physical, true);
  assert.equal(recipe.savedControlCodec.fallbackCapacity, f.fallback[4]);
  assert.equal(recipe.controlsPerRow, f.quantities[4]);
  assert.equal(recipe.credentialOperations, undefined);
});

test('physical writer composer refuses missing mutable extra and invalid constructor metadata before native calls', () => {
  for (const change of [
    f => f.options.construction = {...f.options.construction},
    f => f.options.construction = Object.freeze({...f.options.construction, foreign: true}),
    f => f.options.construction = Object.freeze({...f.options.construction,
      retained: Object.freeze({nodes: -1n, text: 1n, wire: 1n})}),
    f => f.options.limits = {...f.options.limits, maxTransferBytes: 0},
  ]) {
    const f = fixture(); change(f);
    assert.throws(() => prepareInstalledPhysicalWritePlanRecipe(f.options),
      {code: 'InstalledPhysicalWriteConstructionUnavailable'});
    assert.equal(f.calls.length, 0);
  }
});
