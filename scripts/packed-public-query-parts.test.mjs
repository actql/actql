import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {registeredPublicQueryInventory} from './public-query-inventory.mjs';
import {publicQueryCohorts, partitionPublicQueryProfiles} from './fixtures/public-query-cases.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';

const source = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
const start = source.indexOf('const inventoryKeys =');
const end = source.indexOf('// Host profiles are immutable', start);
assert(start >= 0 && end > start);
const inventoryKeys = runInNewContext(source.slice(start, end) + '\ninventoryKeys;',
  {createHash, encodeRetainedFixture}, {timeout: 1000});
const registered = await registeredPublicQueryInventory({includeInputs: true});
const fullPin = JSON.parse(readFileSync(new URL('./fixtures/public-query-inventory.json', import.meta.url)));
const profiles = registered.profileInputs.map(profile => ({...profile, cohorts: publicQueryCohorts(profile.inputs)}));
const parts = [1, 2, 3].map(part => partitionPublicQueryProfiles(profiles, part, inventoryKeys));
const inventories = parts.map(profiles => profiles.flatMap(profile => profile.cohortInventories.flat()));
const digest = values => createHash('sha256').update(JSON.stringify(values)).digest('hex');

export const proposedPortablePins = Object.fromEntries(parts.map((profiles, index) => {
  const names = profiles.flatMap(profile => profile.inputs.successes.map(item => item.name));
  const prefixes = ['time-series-primary', 'carrier-continuation', 'temporal', 'ranking-fusion',
    'quoted-identifier', 'window-group', 'sequence', 'lag', 'cte-value-table',
    'from-unpivot', 'unpivot-row-label', 'unpivot-multicolumn'];
  const receipts = prefixes.filter(prefix => names.some(name => name.startsWith(prefix + '-') ||
    prefix === 'quoted-identifier' && name.startsWith('identifier-role-')))
    .map(prefix => ({temporal: 'temporal-join', sequence: 'sequence-source'})[prefix] ?? prefix);
  return [`portable-${index + 1}`, {totalCases: inventories[index].length,
    inventorySha256: digest(inventories[index]), receiptPrefixes: receipts}];
}));

test('three portable parts preserve the independent complete original inventory exactly once', () => {
  assert.equal(registered.totalCases, fullPin.totalCases);
  assert.equal(registered.inventorySha256, fullPin.inventorySha256);
  const selected = inventories.flat();
  assert.equal(selected.length, fullPin.totalCases);
  assert.equal(new Set(selected).size, selected.length);
  assert.deepEqual(new Set(selected), new Set(registered.inventory));
  const order = new Map(registered.inventory.map((value, index) => [value, index]));
  assert.equal(digest(selected.toSorted((a, b) => order.get(a) - order.get(b))), fullPin.inventorySha256);
  assert.deepEqual(JSON.parse(JSON.stringify(proposedPortablePins)), JSON.parse(readFileSync(
    new URL('./fixtures/public-query-portable-parts.json', import.meta.url))).parts);
});

test('portable assignment preserves whole original cohorts and every original Saved boundary sample', () => {
  const originals = profiles.flatMap(profile => profile.cohorts);
  const selected = parts.flatMap(profiles => profiles.flatMap(profile => profile.cohorts));
  assert.equal(selected.length, originals.length);
  assert.equal(new Set(selected).size, originals.length);
  for (const cohort of originals) assert.equal(selected.filter(value => value === cohort).length, 1);
  assert(inventories.every(values => values.length > 0));
  assert(parts.every(profiles => profiles.some(profile => profile.inputs.successes.length > 0)));
  const largest = Math.max(...profiles.flatMap(profile => profile.cohorts.map(cohort =>
    Object.values(cohort).reduce((count, values) => count + values.length, 0))));
  assert(Math.max(...inventories.map(values => values.length)) - Math.min(...inventories.map(values => values.length)) <= largest);
  assert(parts[0].some(profile => profile.inputs.successes.some(item => item.name === 'exact-string-values')));
});

test('unselected local portable command keeps all original cohorts in their original order', () => {
  const actual = partitionPublicQueryProfiles(profiles, undefined, inventoryKeys);
  assert.deepEqual(actual.map(profile => profile.cohorts), profiles.map(profile => profile.cohorts));
  assert.equal(digest(actual.flatMap(profile => profile.cohortInventories.flat())), fullPin.inventorySha256);
  assert.throws(() => partitionPublicQueryProfiles(profiles, 0, inventoryKeys));
  assert.throws(() => partitionPublicQueryProfiles(profiles, 4, inventoryKeys));
});
