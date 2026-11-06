import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {sourceEnvironmentConstructionGeometry, sourceEnvironmentRetainedGeometry} from './installed-source-construction-geometry.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
for (const role of ['source', 'effect']) {
  test(`native ${role} Environment retains only its actual closed output on the same parent`, async t => {
    const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
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
            const first = events.length;
            const result = Reflect.apply(real[method], real, args);
            captured = {events: events.slice(first), result};
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
    const full = sourceEnvironmentConstructionGeometry(base, declared, wires);
    const closed = sourceEnvironmentRetainedGeometry(environment);
    const cost = g => runtimeField(f.moon.clientProgramSerializationCapacityBytes(checked(
      f.moon.clientProgramInstalledSourceConstructionCapacity(g.nodes, g.text, g.wire, 0n, 0n, 0n))), 1);
    // Provider Effect constructs its independent Mapping carriers AFTER the
    // Environment has closed; the original carrier debit is still retained.
    const mappingCarriers = role === 'effect'
      ? cost({nodes: 1n + 6n * BigInt(mappings.length), text: 0n, wire: 0n}) : 0n;
    const delta = cost(full.workspace) + cost(full.retained) - cost(closed) - mappingCarriers;
    assert(delta > 0n);
    const last = captured.events.at(-1);
    assert.equal(last.operation, 'clientProgramReconcileInstalledSourceConstruction');
    assert.equal(last.returned, true);
    assert.equal(last.accepted, true);
    assert(captured.events.some(event => event.operation === 'clientProgramReserveInstalledSourceConstruction' &&
      event.returned && event.accepted && event.peak === last.peak + delta), 'actual complete reserve followed by exact closed-output reconciliation');
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    assert.equal(f.pending(), false);
    assert.equal(f.retire(), true);
  });
}

test('one original parent completes both large Salesforce native roles without keeping closed Environment scratch', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  for (const role of ['source', 'effect']) {
    const selected = await f.salesforceProfile(role, {largeMetadata: true, fieldCount: 71});
    const exchanges = selected.exchanges();
    await f.load(selected);
    assert.equal(selected.exchanges(), exchanges);
  }
  assert.equal(f.sources.length, 2);
  assert.equal(f.secretReads(), 0);
  assert(events.length > 0);
  assert(events.every(value => value.returned && value.accepted && value.peak <= 536870912n), 'actual unchanged finite Core admission');
  await f.close();
  assert.equal(f.pending(), false);
  assert.equal(f.retire(), true);
});
