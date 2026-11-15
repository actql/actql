import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
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

test('completed native declaration keeps its same opaque result through the next Environment phase', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.salesforceProfile('source');
  let projected, result, calls = 0;
  const connectorTable = sourceWith(real => Object.freeze({...real,
    prepareNativeDeclaration(input) {
      result = real.prepareNativeDeclaration(Object.freeze({
        capacity: () => input.capacity(),
        project() {
          calls++;
          projected = input.project(); return projected;
        }}));
      return result;
    }}));
  await f.load(selected, {connectorTable});
  assert.equal(calls, 1);
  assert.equal(result.declaration, projected.declaration, 'the same opaque output remains retained');
  assert.deepEqual(result.environment, rowSourceCheckEnvironment(base, result.declared));
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

for (const fault of ['project', 'export', 'parse']) {
  test(`failed native declaration ${fault} preserves its original failure and Source cleanup`, async t => {
    const f = await boundConstructionActualFixture(t);
    const selected = await f.salesforceProfile('source');
    const primary = new Error('OriginalNativeDeclaration' + fault + 'Failure');
    let entered = 0;
    const connectorTable = sourceWith(real => Object.freeze({...real,
      prepareNativeDeclaration(input) {
        let parseMock;
        if (fault === 'parse') {
          const parse = JSON.parse;
          parseMock = t.mock.method(JSON, 'parse', (wire, ...rest) => {
            if (typeof wire === 'string' && wire.includes('"evidence_schemas"')) {
              throw primary;
            }
            return Reflect.apply(parse, JSON, [wire, ...rest]);
          });
        }
        try {
          return real.prepareNativeDeclaration(Object.freeze({
            capacity: () => input.capacity(),
            project() {
              entered++;
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
    // A tiny new metadata read forces the SAME parent's reconciliation. It
    // cannot conceal the original constructor's multi-megabyte failure debt.
    const path = join(f.root, 'after-native-failure.json'); await writeFile(path, '{}');
    await installedSourceConfigurationReader(f.services).readText(path, {maxBytes: 2});
    assert.equal(f.sources.length, 0);
    await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
  });
}


test('failed original current fence retains native debt and denies the next constructor', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.salesforceProfile('source');
  let fault;
  const connectorTable = sourceWith(real => Object.freeze({...real,
    prepareNativeDeclaration(input) {
      return real.prepareNativeDeclaration(Object.freeze({
        capacity: () => input.capacity(),
        project() {
          const result = input.project();
          fault = f.failCurrentBeforeNextConstruction();
          return result;
        }}));
    }}));
  await assert.rejects(f.load(selected, {connectorTable}), error => {
    // The existing physical-current ABI converts callback failure into its
    // typed Resource refusal; it does not transport the JS exception identity.
    const pending = [error], seen = new Set();
    while (pending.length) {
      const value = pending.shift();
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      if (value.code === 'MoonBitHostFailure' && value.cause !== undefined) return true;
      pending.push(value.cause, value.primaryFailure);
    }
    return false;
  });
  assert.equal(fault.calls, 1, 'the original real current callback refused the attempted shrink');
  const path = join(f.root, 'after-current-failure.json'); await writeFile(path, '{}');
  await assert.rejects(installedSourceConfigurationReader(f.services).readText(path, {maxBytes: 2}),
    {code: 'MoonBitHostFailure'}, 'the original current failure remains unavailable, not a cached Allow');
  assert.equal(f.sources.length, 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});
