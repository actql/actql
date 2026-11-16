import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareLocalFileStorePlanRecipe} from './local-file-store-plan.mjs';
import {installedRowEffectConstructionLimits} from '../../../host-node/installed-row-effect.mjs';
import {captureInstalledEffectPlanRecipe, installedEffectSavedControlEntryLimit,
  installedEffectSavedControlResponseLimit,
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
  const quantities = Array.from({length: 6}, () => Object.freeze({})),
    fallback = Array.from({length: 6}, () => Object.freeze({})), calls = [];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: (origin, account, units) => ({origin, account, units}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities(...args) {
      assert.strictEqual(this, moon); calls.push(args);
      return {$tag: 1, _0: args.at(-1) === undefined ? fallback : quantities};
    }, clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation, original) {
      assert.strictEqual(original, quantities); return {$tag: 1, _0: {operation, original}};
    }, clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return {$tag: 1, _0: {operation, capacity, transfer, physical}};
    },
  };
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile});
  const expected = [inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    inputLimits.preview.maxWireBytes, inputLimits.preview.maxNodes, inputLimits.preview.maxDepth,
    limits.maxRequestBytes, inputLimits.preview.maxWireBytes + limits.maxRequestBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    4321n, 4096, 1024, localFileWriteMaxComponents, 130, physicalContentReadWindowBytes];
  assert.deepEqual(calls, [[...expected,1510,limits.maxResponseBytes],[...expected,undefined,undefined]]);
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
  assert.deepEqual(recipe.savedControlCodec, {maxEntryBytes:1510,
    maxResponseBytes:limits.maxResponseBytes, fallbackCapacity:fallback[4]});
  const captured = captureInstalledEffectPlanRecipe(recipe, 5);
  const selectedResponse = installedEffectSavedControlResponseLimit([captured]);
  assert.equal(selectedResponse, limits.maxResponseBytes);
  assert.strictEqual(installedEffectRecipeForControlEntryLimit(captured, 1510, selectedResponse), captured);
  const sharedResponse = installedEffectSavedControlResponseLimit([captured, undefined]);
  assert.equal(sharedResponse, effectLedgerImplementationBounds.maxResponseBytes);
  const shared = installedEffectRecipeForControlEntryLimit(captured, 1510, sharedResponse);
  assert.strictEqual(shared.controlsPerRow, fallback[4]);
  assert.strictEqual(shared.rowOperations, captured.rowOperations);
  assert.equal(recipe.credentialOperations, undefined, 'Local must not borrow an HTTP/secret recipe');
  const originalFootprintQuote = moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity;
  moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity = () => undefined;
  try {
    assert.throws(() => prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile}), TypeError);
  } finally {moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity = originalFootprintQuote;}
});

function localGrantRecipeFixture(quantities, fallback, grantIssuer) {
  const captures = [], quotes = [], limits = {...LOCAL_STORE_LIMITS, maxFileBytes: 123456};
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: () => ({}),
    clientProgramInstalledLocalFileStoreControlWireBound: () => 1510,
    clientProgramInstalledLocalFileStoreRecipeCapacities(...args) {
      quotes.push(args); return {$tag: 1, _0: args.at(-1) === undefined ? fallback : quantities};
    },
    clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation, capacities) {
      captures.push(capacities); return {$tag: 1, _0: {operation, capacities}};
    },
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return {$tag: 1, _0: {operation, capacity, transfer, physical}};
    },
  };
  const recipe = prepareLocalFileStorePlanRecipe({moon, limits, grantIssuer,
    inputLimits: installedRowEffectConstructionLimits({maxRows: 100, maxMembers: 16}),
    writerProfile: {nativeOriginalBytes: 4321, maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130}});
  return {recipe, captures, quotes, limits};
}

test('Local Grant recipe keeps its seventh opaque quote out of the six-capacity capture and retains exact issuer originals', () => {
  let grants = 0;
  const site = Object.freeze({issueEffectGrant() {grants++; return {proof: {}};}});
  const nativeQuote = Object.freeze({get privateExtent() {assert.fail('Host must not inspect Common quote');}});
  const quantities = [...Array.from({length: 6}, () => Object.freeze({})), nativeQuote],
    fallback = Array.from({length: 7}, () => Object.freeze({}));
  const {recipe, captures, quotes, limits} = localGrantRecipeFixture(quantities, fallback, site);
  assert.equal(quotes.length, 2);
  assert.deepEqual(quotes.map(args => args.slice(-2)), [[1510, limits.maxResponseBytes], [undefined, undefined]]);
  assert.equal(captures.length, 1);
  assert.notStrictEqual(captures[0], quantities);
  assert.equal(captures[0].length, 6);
  for (let index = 0; index < 6; index++) assert.strictEqual(captures[0][index], quantities[index]);
  assert.equal(Object.isFrozen(recipe.grantConstruction), true);
  assert.strictEqual(recipe.grantConstruction.receiver, site);
  assert.strictEqual(recipe.grantConstruction.method, site.issueEffectGrant);
  assert.strictEqual(recipe.grantConstruction.capacity, nativeQuote);
  assert.strictEqual(recipe.controlsPerRow, quantities[4]);
  assert.strictEqual(recipe.rowOperations[0].extent.capacity, quantities[2]);
  assert.strictEqual(recipe.rowOperations[1].extent.capacity, quantities[3]);
  assert.strictEqual(recipe.savedControlCodec.fallbackCapacity, fallback[4]);
  const shared = installedEffectRecipeForControlEntryLimit(recipe,
    effectLedgerImplementationBounds.maxEntryBytes, limits.maxResponseBytes);
  assert.strictEqual(shared.controlsPerRow, fallback[4]);
  assert.strictEqual(shared.grantConstruction, recipe.grantConstruction);
  assert.strictEqual(shared.rowOperations, recipe.rowOperations);
  assert.equal(grants, 0, 'building a quote never issues a grant');
});

test('Local Grant recipe preserves six-capacity legacy capture without sampling an unsupported issuer', () => {
  const quantities = Array.from({length: 6}, () => Object.freeze({})),
    fallback = Array.from({length: 6}, () => Object.freeze({}));
  let sampled = 0;
  const site = Object.freeze({get issueEffectGrant() {sampled++; assert.fail('legacy must not inspect issuer');}});
  const {recipe, captures} = localGrantRecipeFixture(quantities, fallback, site);
  assert.strictEqual(captures[0], quantities);
  assert.equal(Object.hasOwn(recipe, 'grantConstruction'), false);
  assert.strictEqual(recipe.controlsPerRow, quantities[4]);
  assert.strictEqual(recipe.savedControlCodec.fallbackCapacity, fallback[4]);
  assert.equal(sampled, 0);
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
  assert.deepEqual(observations[0], [3 * units, 11, inputLimits.body.maxDepth,
    6 * (units + 173), 21, 3 * 175 + 6 * (units + 173) + 1]);
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
  assert.deepEqual(quotes, [[n, 8, inputLimits.preview.maxDepth]]);
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

test('File quantities keep long scalar text separate from nodes and bound canonical UTF8 and a failed aggregate tail', () => {
  const full = Array.from({length: 6}, () => ({})), observations = [];
  const moon = {
    clientProgramInstalledOpaqueBoundaryFootprintCapacity: () => ({}),
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
  const inputLimits = installedRowEffectConstructionLimits(), limits = {...LOCAL_STORE_LIMITS, maxFileBytes: 123456};
  const recipe = prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, requestHeaderUnits: 683,
    writerProfile: {nativeOriginalBytes: 4321, maxRootBytes: 4096, maxNameBytes: 1024, maxDepth: 130}});
  const valueNodes = value => value === null || typeof value !== 'object' ? 1
    : 1 + Object.values(value).reduce((sum, item) => sum + valueNodes(item), 0);
  const selector = {$actql_ref: 'resource', identity_cid: 'sha256:' + 'a'.repeat(64)};
  const samples = ['x'.repeat(2048), '\\"\n\u0000日本語😀{}[],:', 1e20, -9e20, 1e-6, 5e-324];
  for (const sample of samples) {
    const changes = {value: {path: 'one.jsonl', content: {sample}}};
    const proposal = {changesWire: JSON.stringify(changes), selectorWire: JSON.stringify(selector)};
    // Quantity observation must remain before either parser/materializer.
    const parse = JSON.parse;
    JSON.parse = () => assert.fail('Quantity observation parsed an original wire');
    try { recipe.captureConstruction.inputExtent([proposal]); } finally { JSON.parse = parse; }
    const [bytes, nodes, , requestBytes, requestNodes, recoveryBytes] = observations.at(-1);
    assert(nodes >= valueNodes(changes) + valueNodes(selector));
    assert(requestNodes >= valueNodes({binding: 'b', command: 'c', target: selector, value: changes.value}));
    const record = {binding: 'sha256:' + 'b'.repeat(64), command: 'sha256:' + 'c'.repeat(64),
      target: selector, value: changes.value};
    assert(requestBytes >= Buffer.byteLength(JSON.stringify(record)));
    assert(recoveryBytes >= Buffer.byteLength(JSON.stringify({binding: record.binding, requests: [record]})));
    assert(bytes >= Buffer.byteLength(proposal.changesWire) + Buffer.byteLength(proposal.selectorWire));
    if (typeof sample === 'string' && sample.length > 1000) assert(nodes < 32);
  }
  const proposal = {changesWire: JSON.stringify({value: {path: 'long.jsonl', content: {text: 'x'.repeat(2048)}}}),
    selectorWire: JSON.stringify(selector)};
  recipe.captureConstruction.inputExtent(Array.from({length: 101}, () => proposal));
  const selected = observations.at(-1);
  assert(selected[1] < 32, 'One long scalar is not thousands of value nodes');
  assert.equal(selected[5], inputLimits.preview.maxWireBytes + limits.maxRequestBytes,
    'The same member quote keeps an accepted aggregate and the next admitted record, not just the accepted frame');
});
