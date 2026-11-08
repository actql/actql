import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {validateSourceInventory} from './client-request-journal.mjs';
import {ordinarySourceDescriptors, verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';
import {boundSourceInventoryFixture} from './fixtures/ordinary-source-binding.fixture.mjs';
const wire = value => canonicalJson(value, {dataKeys: true});

test('ordinary bound inventory retains two opaque installed targets and exact data strings', () => {
  const value = boundSourceInventoryFixture(), original = wire(value);
  assert.equal(validateSourceInventory(original), original);
  assert.equal(JSON.parse(original).acquisitions[0].physicalBinding.path, 'e\u0301/%2F');
  assert.notEqual(original, wire({...value, acquisitions: value.acquisitions.map(item =>
    ({...item, physicalBinding: {...item.physicalBinding, path: 'é/%2F'}}))}));
});

for (const [label, change] of [
  ['envelope extra', v => {v.extra = true;}],
  ['environment missing', v => {delete v.environmentCid;}],
  ['occurrence missing', v => {v.acquisitions.pop();}],
  ['occurrence extra', v => {v.acquisitions[0].extra = true;}],
  ['ordinary coordinate replacement', v => {v.acquisitions[1].task = 0;}],
  ['binding missing', v => {delete v.acquisitions[0].installationBinding;}],
  ['binding extra', v => {v.acquisitions[0].installationBinding.extra = true;}],
  ['registration missing', v => {delete v.acquisitions[0].installationBinding.connectorRegistration;}],
  ['revision empty', v => {v.acquisitions[0].installationBinding.connectorRevision = '';}],
  ['binding CID replaced by raw value', v => {v.acquisitions[0].installationBinding.bindingCid = 'raw';}],
  ['target missing', v => {delete v.acquisitions[0].physicalBinding;}],
  ['target empty', v => {v.acquisitions[0].physicalBinding = {};}],
  ['target replaced by array', v => {v.acquisitions[0].physicalBinding = ['records'];}],
  ['checked Source extra', v => {v.acquisitions[0].checkedSource.extra = true;}],
  ['checked Source missing', v => {delete v.acquisitions[0].checkedSource.sourceViewContractCid;}],
  ['duplicate requirement', v => {v.acquisitions[1].checkedSource.requirementCid = v.acquisitions[0].checkedSource.requirementCid;}],
  ['read tuple extra', v => {v.acquisitions[0].readTuple.extra = true;}],
  ['read action replacement', v => {v.acquisitions[0].readTuple.operation = 'effect';}],
]) {
  test(`ordinary bound inventory refuses ${label}`, () => {
    const value = boundSourceInventoryFixture(); change(value);
    assert.throws(() => validateSourceInventory(wire(value)), {code: 'InvalidClientSourceInventory'});
  });
}
test('ordinary bound inventory refuses noncanonical bytes and legacy shape substitution', () => {
  const value = boundSourceInventoryFixture();
  assert.throws(() => validateSourceInventory(JSON.stringify(value)), {code: 'InvalidClientSourceInventory'});
  value.version = 'actql-client-source-inventory/0.1';
  for (const item of value.acquisitions) delete item.installationBinding;
  assert.throws(() => validateSourceInventory(wire(value)), {code: 'InvalidClientSourceInventory'});
});
test('ordinary bound malformed data uses the journal typed refusal', () => {
  const value = boundSourceInventoryFixture();
  const original = wire(value);
  const prefix = original.replace('"fields":["id","score"]', '"fields":["id","score"],"invalid_number":1e999');
  assert.notEqual(prefix, original);
  assert.throws(() => validateSourceInventory(prefix), {code: 'InvalidClientSourceInventory'});
  value.acquisitions[0].physicalBinding.path = '\ud800';
  assert.throws(() => validateSourceInventory(JSON.stringify(value)), {code: 'InvalidClientSourceInventory'});
});

// These are descriptor/provenance controls, not execution of the row owner.
function retainedSources() {
  return boundSourceInventoryFixture().acquisitions.map(item => {
    const {stage, input, task, installationBinding, ...prepared} = item;
    const original = Object.freeze(structuredClone(installationBinding));
    return {occurrence: {stage, input, task}, prepared,
      adapter: {ordinaryRecoveryBinding(candidate) {
        assert.equal(candidate, prepared); return original;
      }}};
  });
}
test('ordinary descriptor projection keeps bindings with their original preparation and port', () => {
  const sources = retainedSources(), descriptors = ordinarySourceDescriptors(sources);
  assert.deepEqual(descriptors, boundSourceInventoryFixture().acquisitions);
  for (let index = 0; index < 2; index++) {
    verifyOrdinarySourceBinding(sources[index].adapter, sources[index].prepared,
      descriptors[index].installationBinding);
  }
  assert.throws(() => verifyOrdinarySourceBinding(sources[1].adapter, sources[1].prepared,
    descriptors[0].installationBinding), {code: 'InstalledSourcePreparationMismatch'});
});
for (const field of ['connectorId', 'connectorRegistration', 'connectorRevision', 'bindingCid']) {
  test(`ordinary dispatch refuses changed original ${field}`, () => {
    const [source] = retainedSources();
    const original = structuredClone(boundSourceInventoryFixture().acquisitions[0].installationBinding);
    original[field] = field === 'bindingCid' ? `sha256:${'d'.repeat(64)}` : 'foreign';
    assert.throws(() => verifyOrdinarySourceBinding(source.adapter, source.prepared, original),
      {code: 'InstalledSourcePreparationMismatch'});
  });
}
test('ordinary projection refuses mixed capabilities and absent owner on saved bound material', () => {
  const sources = retainedSources(); delete sources[1].adapter.ordinaryRecoveryBinding;
  assert.throws(() => ordinarySourceDescriptors(sources), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => verifyOrdinarySourceBinding(sources[1].adapter, sources[1].prepared,
    boundSourceInventoryFixture().acquisitions[1].installationBinding),
  {code: 'InstalledSourcePreparationMismatch'});
});
test('ordinary legacy descriptors are unchanged when neither adapter issues a bound preparation', () => {
  const sources = retainedSources();
  for (const source of sources) delete source.adapter.ordinaryRecoveryBinding;
  const expected = boundSourceInventoryFixture().acquisitions;
  for (const item of expected) delete item.installationBinding;
  assert.deepEqual(ordinarySourceDescriptors(sources), expected);
});

test('ordinary Whole inventory keeps original Input coordinates without Query identity fields', () => {
  const value = boundSourceInventoryFixture();
  for (const [index, item] of value.acquisitions.entries()) {
    const {requirementCid: _requirement, inputContractCid: program, outputContractCid: parameters, ...source} = item.checkedSource;
    item.checkedSource = {...source, sourceInput: [program, parameters]};
    item.stage = 3;
    item.input = index;
    item.computeTask = 7;
  }
  assert.equal(validateSourceInventory(wire(value)), wire(value));
  for (const change of [
    v => {v.acquisitions[1].input = 0;},
    v => {v.acquisitions[0].checkedSource.requirementCid = 'sha256:' + 'a'.repeat(64);},
    v => {v.acquisitions[0].checkedSource.sourceInput.pop();},
    v => {v.acquisitions[0].computeTask = -1;},
  ]) {
    const changed = structuredClone(value); change(changed);
    assert.throws(() => validateSourceInventory(wire(changed)), {code: 'InvalidClientSourceInventory'});
  }
});
