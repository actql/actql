import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../adapters/host-common/runtime-result.mjs';
import {checked as duckChecked} from '../adapters/connectors/duckdb/node/runtime-result.mjs';
import {checkedEffectPreparation, isEffectPreparationRefusal} from
  '../adapters/host-common/effect-preparation-result.mjs';
import {checkedSalesforceCatalogPreparation} from
  '../adapters/connectors/salesforce/site/salesforce-effect-preparation-result.mjs';
import {runtimeIsOk, runtimeIsError, runtimeUnboxedReferenceOption, runtimeUnboxedUnitOptionPresent,
  runtimeField, runtimePair} from '../adapters/host-common/compiler-binding.generated.mjs';

type ProbeOriginal = object;
type BindingProbe = Readonly<{
  bindingOriginal(value: number): ProbeOriginal;
  bindingAccept(value: ProbeOriginal): unknown;
  bindingUnit(): unknown;
  bindingOption(value: ProbeOriginal, present: boolean): ProbeOriginal | undefined;
  bindingUnitOption(present: boolean): unknown;
  bindingTuple(value: ProbeOriginal): unknown;
  bindingPairInput(value: {_0: ProbeOriginal; _1: ProbeOriginal}): boolean;
}>;
type RuntimeFailure = {code?: unknown; cause?: unknown};

const compiled: BindingProbe = await import(new URL(
  '../_build/js/release/build/interface_binding_probe/interface_binding_probe.js', import.meta.url).href);

test('actual pinned MoonBit Result preserves original payload and typed refusal', () => {
  const original = compiled.bindingOriginal(7);
  const accepted = compiled.bindingAccept(original);
  assert.equal(runtimeIsOk(accepted), true);
  assert.equal(checked(accepted), original);
  assert.equal(duckChecked(accepted), original);
  const refused = compiled.bindingAccept(compiled.bindingOriginal(-1));
  assert.equal(runtimeIsError(refused), true);
  assert.throws(() => checked(refused), {code: 'MoonBitHostFailure', cause: 'BindingContractRefused'});
  assert.throws(() => duckChecked(refused), (error: RuntimeFailure) =>
    error.code === 'MoonBitHostFailure' && error.cause === 'BindingContractRefused');
  assert.equal(checked(compiled.bindingUnit()), undefined);
});

test('actual Option distinguishes None from Some Unit and preserves opaque identity', () => {
  const original = compiled.bindingOriginal(11);
  const some = compiled.bindingOption(original, true);
  const none = compiled.bindingOption(original, false);
  assert.equal(runtimeUnboxedReferenceOption(some), original);
  assert.equal(runtimeUnboxedReferenceOption(none), undefined);
  assert.equal(runtimeUnboxedUnitOptionPresent(compiled.bindingUnitOption(true)), true);
  assert.equal(runtimeUnboxedUnitOptionPresent(compiled.bindingUnitOption(false)), false);
});

test('actual tuple keeps role order, exact Int64, Unicode and callback arguments', () => {
  const first = compiled.bindingOriginal(7), second = compiled.bindingOriginal(11);
  const tuple = compiled.bindingTuple(first);
  assert.equal(runtimeField(tuple, 0), first);
  assert.equal(runtimeField(tuple, 1), 'original\nUnicode: λ');
  assert.equal(runtimeField(tuple, 2), 9007199254740993n);
  assert.equal(compiled.bindingPairInput(runtimePair(first, second)), true);
  assert.equal(compiled.bindingPairInput(runtimePair(second, first)), false);
});

test('malformed compiler returns are not success or a provider refusal', () => {
  for (const result of [undefined, null, false, 1, {}, {$tag: 2}, {$tag: '1'}]) {
    assert.throws(() => checked(result), {code: 'InvalidHostRuntimeResult'});
    assert.throws(() => duckChecked(result), (error: RuntimeFailure) => error.code === 'InvalidHostRuntimeResult');
  }
  // These are public DATA field names, not a compiler result interpretation.
  assert.deepEqual(JSON.parse('{"_0":1,"$tag":"public"}'), {_0: 1, $tag: 'public'});
});

test('actual typed refusal keeps the existing preparation marker boundary', () => {
  const refusal = compiled.bindingAccept(compiled.bindingOriginal(-1));
  assert.throws(() => checkedEffectPreparation(refusal), (error: RuntimeFailure) =>
    error.code === 'MoonBitHostFailure' && error.cause === 'BindingContractRefused' &&
      isEffectPreparationRefusal(error));
  assert.throws(() => checkedEffectPreparation({}), (error: RuntimeFailure) =>
    error.code === 'InvalidHostRuntimeResult' && !isEffectPreparationRefusal(error));
});

test('Salesforce projection does not turn unobserved Catalog failure into refusal', () => {
  const refusal = compiled.bindingAccept(compiled.bindingOriginal(-1));
  const observation = Object.freeze({});
  for (const described of [false, true]) {
    const moon = {salesforceCatalogObservationJson(original: unknown) {
      assert.equal(original, observation);
      return JSON.stringify({listed_resources: described ? [{outcome: 'described'}] : []});
    }};
    assert.throws(() => checkedSalesforceCatalogPreparation(refusal, moon, observation), (error: RuntimeFailure) =>
      error.code === 'MoonBitHostFailure' && error.cause === 'BindingContractRefused' &&
        isEffectPreparationRefusal(error) === described);
  }
});
