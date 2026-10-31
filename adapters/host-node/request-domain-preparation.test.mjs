import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';

// Execute the existing manager method with explicit Core original/phase ports.
// These cases do not supply physical Model/Content construction backing.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const start = source.indexOf('    async fundedPreparation(');
const end = source.indexOf('    publicationPreparation(prepared) {', start);
assert(start >= 0 && end > start);
const method = source.slice(start, end).trim().replace(/,$/u, '');
const fail = code => {throw Object.assign(new Error(code), {code});};

function fixture({infers = [], serializations = [], acquisitions = 0, refusal,
  returned = true, foreign = false} = {}) {
  const parent = {}, input = {}, request = {}, prepared = {}, inventory = {}, selected = {};
  const snapshot = {input: {}, parameters: {}}, calls = [];
  let selectedLive = false, returnFailure = returned === true ? undefined : returned;
  const same = (owner, receipt) => {assert.equal(owner, parent); assert.equal(receipt, input);};
  const moon = {
    clientProgramPrepareRequestNativeComputation(owner, receipt) {same(owner, receipt); calls.push('check');},
    clientProgramFinishRequestComputation(owner, receipt) {same(owner, receipt); calls.push('compile'); return 'effect_free';},
    clientProgramBorrowRequestProgramPlanInput(owner, receipt) {same(owner, receipt); calls.push('inventory'); return inventory;},
    clientProgramPreparationBorrowRead(holder) {
      assert(holder === inventory || holder === selected);
      return holder === selected && foreign ? {} : prepared;
    },
    clientProgramAcquisitionCount(actual) {assert.equal(actual, prepared); return acquisitions;},
    clientProgramComposedInferOccurrences(actual) {assert.equal(actual, prepared); calls.push('infer'); return infers;},
    clientProgramSerializationOccurrences(actual) {assert.equal(actual, prepared); calls.push('serialization'); return serializations;},
    clientProgramBorrowRequestModelPlanInput(owner, receipt) {
      same(owner, receipt); calls.push('model'); if (refusal) throw refusal;
      selectedLive = true; return selected;
    },
    clientProgramBorrowRequestContentPlanInput(owner, receipt) {
      same(owner, receipt); calls.push('content'); if (refusal) throw refusal;
      selectedLive = true; return selected;
    },
    clientProgramPreparationBorrowReturn(holder) {
      assert.equal(holder, inventory); assert(selectedLive, 'Select and retain the domain before returning inventory');
      calls.push('return-inventory');
      if (returnFailure !== undefined) throw returnFailure;
      return true;
    },
    clientProgramPrepareRequestProgramModuleBody() {calls.push('ordinary-module');},
    clientProgramRequiresQueryTime: () => false,
    clientProgramRequestParametersOriginal: () => undefined,
  };
  const state = {parent, snapshot, context: {runtime: moon}};
  const producer = {receipt: input, request, kind: 'program', body: snapshot, preparation: state};
  const originals = {installation: {sequenceContractOriginal: {moon, admission: {}}}};
  const read = Function('current', 'producerForRequest', 'fail', 'originals', 'checked',
    'checkedRequestProgramPreparation', 'requestPreparationAvailable',
    `const closing=false,closed=false;return ({${method}}).fundedPreparation;`)(() => {},
    actual => {assert.equal(actual, request); return producer;}, fail, originals, value => value,
    (_moon, value) => value, () => true);
  return {state, calls, inventory, selected, prepared, read: () => read(request),
    clearReturnFailure() {returnFailure = undefined;}};
}

test('original INFER and Content inventory select their own constructor borrow before ordinary ModuleBody', async () => {
  for (const family of ['model', 'content']) {
    const f = fixture(family === 'model' ? {infers: [{}]} : {serializations: [{}], acquisitions: 1});
    for (let index = 0; index < 2; index++) {
      const result = await f.read(); assert.equal(result.prepared, f.prepared);
    }
    assert.deepEqual(f.calls, ['check', 'compile', 'inventory', 'infer', 'serialization', family, 'return-inventory']);
    assert.equal(f.state.holder, f.selected);
    assert.equal(f.state.inventoryHolder, undefined);
    assert.equal(f.state.compilationFamily, family);
  }
});

test('domain selection refusal and failed inventory return retain their exact original borrows and failure', async () => {
  const refusal = new Error('original-domain-refusal');
  const f = fixture({infers: [{}], refusal});
  await assert.rejects(f.read(), error => error === refusal);
  await assert.rejects(f.read(), error => error === refusal);
  assert.equal(f.state.holder, f.inventory);
  assert.equal(f.calls.filter(value => value === 'model').length, 1);
  const returnFailure = new Error('original-inventory-return');
  const g = fixture({serializations: [{}], acquisitions: 1, returned: returnFailure});
  await assert.rejects(g.read(), error => error === returnFailure);
  assert.equal(g.state.holder, g.selected);
  assert.equal(g.state.inventoryHolder, g.inventory);
  g.clearReturnFailure();
  await assert.rejects(g.read(), error => error === returnFailure);
  assert.equal(g.calls.filter(value => value === 'content').length, 1);
});

test('mixed inventories and foreign domain originals refuse before ordinary or domain construction', async () => {
  const mixed = fixture({infers: [{}], serializations: [{}]});
  await assert.rejects(mixed.read(), {code: 'NodeManagedRunPlanUnavailable'});
  assert.equal(mixed.state.holder, mixed.inventory);
  assert(!mixed.calls.includes('model')); assert(!mixed.calls.includes('content'));
  assert(!mixed.calls.includes('ordinary-module'));
  const foreign = fixture({infers: [{}], foreign: true});
  await assert.rejects(foreign.read(), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(foreign.state.holder, foreign.selected);
  assert.equal(foreign.state.inventoryHolder, foreign.inventory);
  assert(!foreign.calls.includes('return-inventory'));
});

test('original Request cleanup retains both family borrows until each acknowledged return', () => {
  const parent = {}, prepared = {}, inventory = {}, selected = {}, failure = new Error('inventory-return');
  const calls = [];
  let failReturn = true, retired = 0;
  const state = {parent, holder: selected, inventoryHolder: inventory, prepared,
    compilationKind: 'effect_free', compilationFamily: 'model'};
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientProgramAbortRequestPreparation(owner) {
      assert.equal(owner, parent); calls.push('abort');
      return state.holder !== undefined || state.inventoryHolder !== undefined
        ? {$tag: 0, _0: 'retained-original-borrows'} : ok();
    },
    clientProgramPreparationBorrowRetirementStarted(holder) {
      assert(holder === inventory || holder === selected); return true;
    },
    clientProgramPreparationBorrowReturn(holder) {
      calls.push(holder === inventory ? 'inventory' : 'selected');
      if (holder === inventory && failReturn) throw failure;
      return ok(true);
    },
  };
  state.context = {runtime: moon};
  const retire = actual => {assert.equal(actual, prepared); retired++;};
  assert.throws(() => cleanupRequestInput(state, retire), error => error === failure);
  assert.equal(state.inventoryHolder, inventory); assert.equal(state.holder, selected);
  assert.equal(state.prepared, undefined); assert.equal(retired, 1);
  failReturn = false;
  cleanupRequestInput(state, retire);
  assert.equal(state.inventoryHolder, undefined); assert.equal(state.holder, undefined);
  assert.equal(state.parent, undefined); assert.equal(retired, 1);
  assert.deepEqual(calls, ['abort', 'inventory', 'abort', 'inventory', 'selected', 'abort']);
});
