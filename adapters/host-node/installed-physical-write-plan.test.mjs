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
    clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum) {
      return ok(Object.freeze({initial, maximum}));
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
  assert.equal(quotes.length, 3);
  assert.equal(quotes[0].at(-2), f.physical);
  assert.equal(quotes[1].at(-2), f.physical);
  assert.deepEqual(quotes.map(value => value.at(-1)), [2000, 0, 2000]);
  assert.equal(recipe.recoveryConstruction.operationIndex, 1);
  assert.equal(typeof recipe.recoveryConstruction.inputExtent, 'function');
  assert.strictEqual(recipe.memberOperations[1].extent.maximum, recipe.memberOperations[0].extent);
  assert.notStrictEqual(recipe.memberOperations[1].extent.initial, recipe.memberOperations[0].extent);
  assert.deepEqual(quotes[2].slice(4, 7), [1, 1, 1]);
  assert.equal(quotes[2][8], 1);
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


test('pure cold reconstruction selects only its authenticated member wire inside unchanged maxima', () => {
  const f = fixture(), recipe = prepareInstalledPhysicalWritePlanRecipe(f.options);
  const select = recipe.recoveryConstruction.inputExtent;
  const preview = '{"a":1}', own = {memberIndex: 0, wire: '{"requests":[]}'},
    foreign = {memberIndex: 1, wire: 'x'.repeat(6000)};
  select(preview, [own, foreign], 0);
  let quote = f.calls.filter(value => value[0] === 'recipe').at(-1);
  assert.deepEqual(quote.slice(4, 7), [7, 15, 15]);
  assert.equal(quote[8], 15);
  assert.equal(quote.at(-2), f.physical);
  assert.equal(quote.at(-1), 2000);
  // UTF-8 bytes conservatively cover the already validated tree; no JSON
  // parser/serializer or a copied provider's output is used for a count.
  select('{"a":"あ"}', [], 0);
  quote = f.calls.filter(value => value[0] === 'recipe').at(-1);
  assert.deepEqual(quote.slice(4, 7), [11, 11, 11]);
  assert.equal(quote[8], 1);
  for (const [wire, recovery, index] of [
    ['', [own], 0], ['x'.repeat(f.options.inputLimits.preview.maxWireBytes + 1), [own], 0],
    [preview, [{memberIndex: 0, wire: 'x'.repeat(5001)}], 0],
    [preview, [{memberIndex: 0, wire: '\ud800'}], 0], [preview, [own], -1],
    [preview, [own], undefined], [preview, {}, 0],
  ]) {
    const before = f.calls.length;
    assert.throws(() => select(wire, recovery, index), {code: 'InstalledPhysicalWriteConstructionUnavailable'});
    assert.equal(f.calls.length, before);
  }
});
