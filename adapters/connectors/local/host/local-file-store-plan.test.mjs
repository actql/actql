import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareLocalFileStorePlanRecipe} from './local-file-store-plan.mjs';
import {installedRowEffectConstructionLimits} from '../../../host-node/installed-row-effect.mjs';
import {captureInstalledEffectPlanRecipe, installedEffectSavedControlEntryLimit,
  installedEffectRecipeForControlEntryLimit} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {physicalContentReadWindowBytes} from '../../../store-local/publication-store.mjs';
import {localFileWriteMaxComponents} from '../site/root-file-writer.mjs';
import {LOCAL_STORE_LIMITS} from './installed-project-file-effects.mjs';

test('Local STORE recipe consumes actual constructor bounds in distinct original occurrences', () => {
  const inputLimits = installedRowEffectConstructionLimits({maxRows: 100, maxMembers: 16});
  const limits = {...LOCAL_STORE_LIMITS, maxFileBytes: 123456};
  const writerProfile = {nativeOriginalBytes: 4321, maxRootBytes: 4096,
    maxNameBytes: 1024, maxDepth: 130, writeQuantumBytes: 65536};
  const quantities = Array.from({length: 6}, () => Object.freeze({})), calls = [];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: (origin, account, units) => ({origin, account, units}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities(...args) {
      assert.strictEqual(this, moon); calls.push(args); return {$tag: 1, _0: quantities};
    }, clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation, original) {
      assert.strictEqual(original, quantities); return {$tag: 1, _0: {operation, original}};
    }, clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return {$tag: 1, _0: {operation, capacity, transfer, physical}};
    },
  };
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile});
  const expected = [inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    inputLimits.preview.maxWireBytes, inputLimits.preview.maxNodes, inputLimits.preview.maxDepth,
    limits.maxRequestBytes, limits.maxRequestBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    4321n, 4096, 1024, localFileWriteMaxComponents, 130, physicalContentReadWindowBytes];
  assert.deepEqual(calls, [[...expected,1510],[...expected,undefined]]);
  assert.deepEqual(recipe.memberOperations.map(entry => entry.operation),
    ['files.write.capture', 'files.write.capture', 'files.write.footprint']);
  assert.deepEqual(recipe.footprintConstruction, {operationIndex: 2});
  assert.deepEqual(recipe.memberOperations[2].extent, {operation: 'files.write.footprint',
    capacity: {origin: 'local', account: 'file_collection', units: 1024}, transfer: 0n, physical: false});
  assert.strictEqual(recipe.memberOperations[1].extent, recipe.memberOperations[0].extent);
  assert.deepEqual(recipe.recoveryConstruction, {operationIndex: 1});
  assert.deepEqual(recipe.rowOperations.map(entry => entry.operation), ['files.write.request', 'files.write']);
  assert.deepEqual(recipe.rowOperations.map(entry => entry.extent.transfer), [0n, 123456n]);
  assert.deepEqual(recipe.rowOperations.map(entry => entry.extent.physical), [false, true]);
  assert.strictEqual(recipe.controlsPerRow, quantities[4]);
  assert.deepEqual(recipe.physicalWrite, {operationIndex: 1, transferBytes: 123456n});
  assert.deepEqual(recipe.savedControlCodec, {maxEntryBytes:1510, fallbackCapacity:quantities[4]});
  assert.equal(recipe.credentialOperations, undefined, 'Local must not borrow an HTTP/secret recipe');
  const originalFootprintQuote = moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity;
  moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity = () => undefined;
  try {
    assert.throws(() => prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile}), TypeError);
  } finally {moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity = originalFootprintQuote;}
});

test('owned physical write cannot reuse a constructor slot or malformed transfer amount', () => {
  const base = {memberOperations: Object.freeze([]), rowOperations: Object.freeze([
    Object.freeze({operation: 'request', extent: {}}), Object.freeze({operation: 'files.write', extent: {}})]),
  requestConstruction: Object.freeze({operationIndex: 0})};
  for (const physicalWrite of [{operationIndex: 0, transferBytes: 1n},
    {operationIndex: 1, transferBytes: -1n}, {operationIndex: 1, transferBytes: 1},
    {operationIndex: 2, transferBytes: 1n}]) {
    assert.throws(() => captureInstalledEffectPlanRecipe(Object.freeze({...base,
      physicalWrite: Object.freeze(physicalWrite)}), 2), {code: 'InvalidInstalledEffectPlanRecipe'});
  }
});


test('closed saved codec preserves the generic composed owner control allowance', () => {
  const narrow = {}, full = {};
  const local = captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations:Object.freeze([]),rowOperations:Object.freeze([Object.freeze({operation:'write',extent:{}})]),
    controlsPerRow:narrow,savedControlCodec:Object.freeze({maxEntryBytes:1510,fallbackCapacity:full})}),1);
  assert.equal(installedEffectSavedControlEntryLimit([local]),1510);
  assert.strictEqual(installedEffectRecipeForControlEntryLimit(local,1510),local);
  const maximum = installedEffectSavedControlEntryLimit([local,undefined]);
  assert.equal(maximum,effectLedgerImplementationBounds.maxEntryBytes);
  const composed = installedEffectRecipeForControlEntryLimit(local,maximum);
  assert.strictEqual(composed.controlsPerRow,full);
  assert.strictEqual(composed.rowOperations,local.rowOperations);
  for (const bytes of [0,-1,1.5,1000001]) {
    assert.throws(()=>captureInstalledEffectPlanRecipe(Object.freeze({...local,
      savedControlCodec:Object.freeze({maxEntryBytes:bytes,fallbackCapacity:full})}),1),
      {code:'InvalidInstalledEffectPlanRecipe'});
  }
});
test('warm File recipe selects owned wire geometry while keeping cold and physical originals', () => {
  const full = Array.from({length: 6}, (_, index) => ({full: index}));
  const initial = [{initial: 'member'}, {initial: 'row'}, {initial: 'request'}];
  const actual = [{actual: 'member'}, {actual: 'row'}, {actual: 'request'}];
  const observations = [];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: (origin, account, units) => ({origin, account, units}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities: () => ({$tag: 1, _0: full}),
    clientProgramInstalledLocalFileStoreInitialConstructorCapacities: () => initial,
    clientProgramInstalledLocalFileStoreObservedConstructorCapacities(...args) {
      observations.push(args); return {$tag: 1, _0: actual};
    },
    clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation, capacities) {
      return {$tag: 1, _0: {operation, capacities}};
    },
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return {$tag: 1, _0: {operation, capacity, transfer, physical}};
    },
    clientProgramInstalledEffectOperationStagedExtentPrepare(first, maximum) {
      return {$tag: 1, _0: {first, maximum}};
    },
  };
  const inputLimits = installedRowEffectConstructionLimits();
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits,
    limits: {...LOCAL_STORE_LIMITS, maxFileBytes: 123456}, requestHeaderUnits: 173,
    writerProfile: {nativeOriginalBytes: 4321, maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130}});
  assert.strictEqual(recipe.memberOperations[0].extent.first.capacities[0], initial[0]);
  assert.strictEqual(recipe.memberOperations[1].extent.maximum.capacities, full);
  assert.strictEqual(recipe.rowOperations[0].extent.first.capacity, initial[2]);
  assert.strictEqual(recipe.rowOperations[1].extent.capacity, full[3]);
  assert.equal(recipe.rowOperations[1].extent.transfer, 123456n);
  const proposal = {changesWire: '{"value":{"path":"one.jsonl"}}', selectorWire: '{"kind":"file"}'};
  const units = proposal.changesWire.length + proposal.selectorWire.length;
  const selected = recipe.captureConstruction.inputExtent([proposal]);
  assert.strictEqual(selected.capacities[0], actual[0]);
  assert.deepEqual(observations[0], [3 * units, units, inputLimits.body.maxDepth,
    18 * (units + 173), units + 173, 3 * 175 + 18 * (units + 173) + 1]);
  assert.strictEqual(recipe.requestConstruction.inputExtent(proposal).capacity, actual[2]);
  let reads = 0;
  const foreign = Object.defineProperty({}, 'changesWire', {get() {reads++; return '{}';}});
  assert.throws(() => recipe.captureConstruction.inputExtent([foreign]), TypeError);
  assert.equal(reads, 0); assert.equal(observations.length, 2);
});

test('cold File recovery selects its same original member wire before parsing and refuses ambiguous input', () => {
  const full = Array.from({length: 6}, () => ({})), initial = [{}, {}, {}], quotes = [];
  const actual = [{saved: true}, {clone: true}];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: (origin, account, units) => ({origin, account, units}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities: () => ({$tag: 1, _0: full}),
    clientProgramInstalledLocalFileStoreInitialConstructorCapacities: () => initial,
    clientProgramInstalledLocalFileStoreObservedRecoveryCapacities(...args) {
      quotes.push(args); return {$tag: 1, _0: actual};
    },
    clientProgramInstalledEffectCaptureRecipeExtentPrepare: (operation, capacities) => ({$tag: 1, _0: {operation, capacities}}),
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectOperationStagedExtentPrepare: (first, maximum) => ({$tag: 1, _0: {first, maximum}}),
  };
  const inputLimits = installedRowEffectConstructionLimits();
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits, limits: {...LOCAL_STORE_LIMITS, maxFileBytes: 123456},
    requestHeaderUnits: 173,
    writerProfile: {nativeOriginalBytes: 4321, maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130}});
  assert.strictEqual(recipe.memberOperations[1].extent.first.capacities[0], initial[0]);
  const recovery = [{memberIndex: 0, wire: '{"binding":"original","requests":[]}'},
    {memberIndex: 1, wire: 'unrelated member'}];
  const select = recipe.recoveryConstruction.inputExtent;
  const extent = select('already-admitted Preview is borrowed', recovery, 0);
  assert.strictEqual(extent.capacities[0], actual[0]);
  assert.strictEqual(extent.capacities[1], actual[1]);
  const n = recovery[0].wire.length;
  assert.deepEqual(quotes, [[3 * n, n, inputLimits.preview.maxDepth]]);
  assert.throws(() => select('', [...recovery, recovery[0]], 0), TypeError);
  assert.throws(() => select('', recovery, 2), TypeError);
  let reads = 0;
  const foreign = Object.defineProperty({memberIndex: 0}, 'wire', {get() {reads++; return '{}';}});
  assert.throws(() => select('', [foreign], 0), TypeError);
  assert.equal(reads, 0); assert.equal(quotes.length, 1);
});

test('empty warm File capture quotes only its original recovery envelope', () => {
  const full = Array.from({length: 6}, () => ({}));
  const observations = [];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: (origin, account, units) => ({origin, account, units}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities: () => ({$tag: 1, _0: full}),
    clientProgramInstalledLocalFileStoreInitialConstructorCapacities: () => [{}, {}, {}],
    clientProgramInstalledLocalFileStoreObservedConstructorCapacities(...args) {
      observations.push(args); return {$tag: 1, _0: [{}, {}, {}]};
    },
    clientProgramInstalledEffectCaptureRecipeExtentPrepare: (operation, capacities) => ({$tag: 1, _0: {operation, capacities}}),
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectOperationStagedExtentPrepare: () => ({$tag: 1, _0: {}}),
  };
  const inputLimits = installedRowEffectConstructionLimits();
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits, limits: {...LOCAL_STORE_LIMITS, maxFileBytes: 123456},
    requestHeaderUnits: 173,
    writerProfile: {nativeOriginalBytes: 4321, maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130}});
  recipe.captureConstruction.inputExtent([]);
  assert.deepEqual(observations, [[0, 0, inputLimits.body.maxDepth, 0, 0, 525]]);
});
