import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';

const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
for (const role of ['source', 'effect']) {
  test(`native ${role} Environment preserves its full original wire and CID on the same parent`, async t => {
    const f = await boundConstructionActualFixture(t);
    const selected = await f.salesforceProfile(role);
    const entry = installedConnectors.find(value => value.registration === 'salesforce');
    let captured;
    const method = role === 'source' ? 'prepareNativeDeclaration' : 'prepareProviderEffect';
    const connectorTable = createInstalledConnectorTable([{...entry, [role]: {...entry[role],
      async load() {
        const module = await entry[role].load();
        return {...module, load(profile, options) {
          const real = options.construction;
          const construction = Object.freeze({...real, [method](...args) {
            const result = Reflect.apply(real[method], real, args);
            captured = {result};
            return result;
          }});
          return module.load(profile, {...options, construction});
        }};
      }}}]);
    const exchanges = selected.exchanges();
    await f.load(selected, {connectorTable});
    assert(captured);
    assert.equal(selected.exchanges(), exchanges);
    const {declared, environment, mappings = []} = captured.result;
    const wires = mappings.map(value => value.body);
    assert.deepEqual(environment, rowSourceCheckEnvironment(base, declared, wires), 'complete original wire and CID');
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    assert.equal(f.pending(), false);
    assert.equal(f.retire(), true);
  });
}

test('one original parent completes both large Salesforce native roles without keeping closed Environment scratch', async t => {
  const f = await boundConstructionActualFixture(t);
  for (const role of ['source', 'effect']) {
    const selected = await f.salesforceProfile(role, {largeMetadata: true, fieldCount: 71});
    const exchanges = selected.exchanges();
    await f.load(selected);
    assert.equal(selected.exchanges(), exchanges);
  }
  assert.equal(f.sources.length, 2);
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.pending(), false);
  assert.equal(f.retire(), true);
});
