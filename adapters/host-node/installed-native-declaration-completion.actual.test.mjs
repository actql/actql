import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const originalEntry = installedConnectors.find(value => value.registration === 'salesforce');
const sourceWith = install => createInstalledConnectorTable([{...originalEntry, source: {...originalEntry.source,
  async load() {
    const module = await originalEntry.source.load();
    return {...module, load(profile, options) {
      return module.load(profile, {...options, construction: install(options.construction)});
    }};
  }}}]);
const contains = (error, expected) => {
  const pending = [error], seen = new Set();
  while (pending.length) {
    const value = pending.shift();
    if (value === expected) return true;
    if (!value || typeof value !== 'object' || seen.has(value)) continue;
    seen.add(value); pending.push(value.cause, value.primaryFailure);
  }
  return false;
};

test('completed native declaration projects its original retained quantity before the next Environment phase', async t => {
  const events = [], completions = [];
  const f = await boundConstructionActualFixture(t, {capacityEvents: events, nativeCompletions: completions});
  const selected = await f.salesforceProfile('source');
  let quantity, projected, result, calls = 0, nativePeak;
  const connectorTable = sourceWith(real => Object.freeze({...real,
    prepareNativeDeclaration(input) {
      result = real.prepareNativeDeclaration(Object.freeze({
        capacity() {quantity = input.capacity(); return quantity;},
        project() {
          calls++; nativePeak = events.at(-1).peak;
          projected = input.project(); return projected;
        }}));
      return result;
    }}));
  await f.load(selected, {connectorTable});
  assert.equal(calls, 1);
  assert.equal(result.declaration, projected.declaration, 'the same opaque output remains retained');
  assert.deepEqual(result.environment, rowSourceCheckEnvironment(base, result.declared));
  const completed = completions.filter(value => value.quantity === quantity);
  assert.equal(completed.length, 1, 'the actual successful native constructor receives its own retained projection');
  const zero = checked(f.moon.clientProgramInstalledSourceConstructionCapacity(0n, 0n, 0n, 0n, 0n, 0n));
  const bytes = q => runtimeField(f.moon.clientProgramSerializationCapacityBytes(checked(
    f.moon.clientProgramComposeInstalledSourceConstructionCapacity(zero, [q]))), 1);
  const peak = bytes(quantity), retained = bytes(completed[0].retained);
  assert(retained < peak, 'this actual shared recipe has a distinct closed-output inventory');
  const cut = completed[0].eventIndex;
  const before = events[cut - 1], after = events[cut];
  assert.equal(before.operation, 'clientProgramReserveInstalledSourceConstruction');
  assert.equal(after.operation, 'clientProgramReserveInstalledSourceConstruction');
  assert(before.accepted && after.accepted, 'the SAME physical parent passes both original fences');
  const reconciled = events[cut + 1];
  assert.equal(reconciled.operation, 'clientProgramReconcileInstalledSourceConstruction');
  assert.equal(reconciled.accepted, true);
  assert.equal(after.peak, reconciled.peak);
  assert.equal(before.peak - reconciled.peak, peak - retained,
    'only this successful native phase shrinks before the next Environment');
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

for (const fault of ['project', 'export', 'parse']) {
  test(`failed native declaration ${fault} preserves its full quote and original failure`, async t => {
    const events = [], completions = [];
    const f = await boundConstructionActualFixture(t, {capacityEvents: events, nativeCompletions: completions});
    const selected = await f.salesforceProfile('source');
    const primary = new Error('OriginalNativeDeclaration' + fault + 'Failure');
    let quantity, nativePeak, entered = 0;
    const connectorTable = sourceWith(real => Object.freeze({...real,
      prepareNativeDeclaration(input) {
        let parseMock;
        if (fault === 'parse') {
          const parse = JSON.parse;
          parseMock = t.mock.method(JSON, 'parse', (wire, ...rest) => {
            if (typeof wire === 'string' && wire.includes('"evidence_schemas"')) {
              nativePeak = events.at(-1).peak;
              throw primary;
            }
            return Reflect.apply(parse, JSON, [wire, ...rest]);
          });
        }
        try {
          return real.prepareNativeDeclaration(Object.freeze({
            capacity() {quantity = input.capacity(); return quantity;},
            project() {
              entered++; nativePeak = events.at(-1).peak;
              if (fault === 'project') throw primary;
              const actual = input.project();
              if (fault !== 'export') return actual;
              return Object.freeze({...actual, declaration: new Proxy(actual.declaration,
                {get() {throw primary;}})});
            }}));
        } finally {parseMock?.mock.restore();}
      }}));
    await assert.rejects(f.load(selected, {connectorTable}), error => contains(error, primary));
    assert.equal(entered, 1);
    assert.equal(completions.filter(value => value.quantity === quantity).length, 0);
    // A tiny new metadata read forces the SAME parent's reconciliation. It
    // cannot conceal the original constructor's multi-megabyte failure debt.
    const path = join(f.root, 'after-native-failure.json'); await writeFile(path, '{}');
    await installedSourceConfigurationReader(f.services).readText(path, {maxBytes: 2});
    const final = events.at(-1);
    assert.equal(final.accepted, true); assert(final.peak >= nativePeak);
    assert.equal(f.sources.length, 0);
    await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
  });
}


test('failed original current fence retains native debt and denies the next constructor', async t => {
  const events = [], completions = [];
  const f = await boundConstructionActualFixture(t, {capacityEvents: events, nativeCompletions: completions});
  const selected = await f.salesforceProfile('source');
  let quantity, fault;
  const connectorTable = sourceWith(real => Object.freeze({...real,
    prepareNativeDeclaration(input) {
      return real.prepareNativeDeclaration(Object.freeze({
        capacity() {
          quantity = input.capacity();
          fault = f.failCurrentAfterNativeRetention(quantity);
          return quantity;
        }, project: () => input.project()}));
    }}));
  await assert.rejects(f.load(selected, {connectorTable}), error => {
    // The existing physical-current ABI converts callback failure into its
    // typed Resource refusal; it does not transport the JS exception identity.
    const pending = [error], seen = new Set();
    while (pending.length) {
      const value = pending.shift();
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      if (value.code === 'MoonBitHostFailure' &&
          /PreparationCapacityIssue.*Resource$/u.test(value.cause?.constructor?.name ?? '')) return true;
      pending.push(value.cause, value.primaryFailure);
    }
    return false;
  });
  assert.equal(fault.calls, 1, 'the original real current callback refused the attempted shrink');
  const completed = completions.filter(value => value.quantity === quantity);
  assert.equal(completed.length, 1, 'a DATA projection alone is not successful reconciliation');
  const cut = completed[0].eventIndex;
  const before = events[cut - 1], refused = events[cut];
  assert.equal(before.accepted, true);
  assert.equal(refused.operation, 'clientProgramReserveInstalledSourceConstruction');
  assert.equal(refused.accepted, false);
  const path = join(f.root, 'after-current-failure.json'); await writeFile(path, '{}');
  await assert.rejects(installedSourceConfigurationReader(f.services).readText(path, {maxBytes: 2}),
    {code: 'MoonBitHostFailure'}, 'the original current failure remains unavailable, not a cached Allow');
  assert.equal(completed[0].lastProviderQuantity, quantity,
    'the next refused constructor still sees the SAME original full native quote');
  assert.equal(events.at(-1).accepted, false);
  assert.equal(f.sources.length, 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});
