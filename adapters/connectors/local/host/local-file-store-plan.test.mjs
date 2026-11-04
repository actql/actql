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
  assert.equal(recipe.memberOperations.length, 1);
  assert.deepEqual(recipe.rowOperations.map(entry => entry.operation), ['files.write.request', 'files.write']);
  assert.deepEqual(recipe.rowOperations.map(entry => entry.extent.transfer), [0n, 123456n]);
  assert.deepEqual(recipe.rowOperations.map(entry => entry.extent.physical), [false, true]);
  assert.strictEqual(recipe.controlsPerRow, quantities[4]);
  assert.deepEqual(recipe.physicalWrite, {operationIndex: 1, transferBytes: 123456n});
  assert.deepEqual(recipe.savedControlCodec, {maxEntryBytes:1510, fallbackCapacity:quantities[4]});
  assert.equal(recipe.credentialOperations, undefined, 'Local must not borrow an HTTP/secret recipe');
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
