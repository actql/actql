// Independently enumerate authored registration as data. Never import the
// installed acceptance entry, product packages, or the cohort partition helper.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {publicQueryProfiles} from './fixtures/public-query-profiles.mjs';

export async function registeredPublicQueryInventory({includeInputs = false} = {}) {
const root = new URL('../', import.meta.url);
const fixtureRoot = new URL('scripts/fixtures/', root);
const read = path => readFile(new URL(path, root), 'utf8');
const packed = await read('scripts/fixtures/packed-public-query.mjs');
const marker = 'refusals: scope.refusals} : {successes: [';
const start = packed.indexOf(marker);
assert.ok(start >= 0, 'recognize the full-corpus fallback explicitly');
const registrationEnd = packed.indexOf('scopeInputs.successes = uniquePublicQueryCases', start);
assert.ok(registrationEnd > start, 'stop before Host setup and runtime work');
const inventoryStart = packed.indexOf('const inventoryKeys =');
assert.ok(inventoryStart === -1 || inventoryStart > registrationEnd,
  'transport inventory bookkeeping must remain outside registration parsing');
const registration = packed.slice(start, registrationEnd);
const initial = registration.match(/^refusals: scope\.refusals\} : \{successes: \[([^\]]*)\],\s*refusals: \[([^\]]*)\],\s*executionFailures: \[([^\]]*)\]\};/u);
assert.ok(initial, 'only accept spread-only full-corpus registration');
const symbols = new Map();
const importedPaths = new Set();
for (const match of packed.matchAll(/^import\s+\{([^}]*)\}\s+from\s+['"](\.[^'"]+)['"];/gmu)) {
  const names = match[1].split(',').map(name => name.trim());
  const used = names.filter(name => new RegExp(`\\b${name}\\b`, 'u').test(registration));
  if (used.length === 0) continue;
  const path = new URL(match[2], fixtureRoot);
  assert.ok(fileURLToPath(path).startsWith(fileURLToPath(fixtureRoot)), 'fixture import stays in the copied source');
  const values = await import(path.href);
  importedPaths.add(match[2]);
  for (const name of used) {
    assert.ok(Object.hasOwn(values, name), `registered fixture export ${name}`);
    symbols.set(name, values[name]);
  }
}
const jsonInputs = {
  scope: 'spec/frontend/fixtures/pipe-scope/cases.json',
  joinOrder: 'spec/frontend/fixtures/join-order/cases.json',
  joinChain: 'spec/frontend/fixtures/join-chain/cases.json',
  groupScope: 'spec/frontend/fixtures/group-scope/cases.json',
};
for (const [name, path] of Object.entries(jsonInputs)) symbols.set(name, JSON.parse(await read(path)));
// This one machine control is declared directly in the packed registration.
// Its literal oracle is independent of any result produced by the product.
symbols.set('dataSetStrategyInputs', {successes: [{
  name: 'independent-ordered-data-set', format: 'json',
  text: await read('spec/frontend/fixtures/data-set-strategy/repro-program.json'),
  sourceReadCount: 0,
  results: {nodes: {rows: [{id: 1}], columns: [
    {name: 'id', contract: {type: 'number', nullable: false}},
  ]}},
}], refusals: []});
const analytic = await import(new URL('analytic-order-source-input.mjs', fixtureRoot).href);
symbols.set('analyticOrderInputs', [...analytic.analyticOrderSuccesses,
  analytic.analyticOrderObjectReproduction(await read('docs/reviews/fixtures/analytic-order-property-repro.program.json'))]);

function resolveSpreads(text) {
  return text.split(',').filter(part => part.trim() !== '').flatMap(part => {
    const match = part.trim().match(/^\.\.\.([A-Za-z_$][\w$]*)(?:\.([A-Za-z_$][\w$]*))?$/u);
    assert.ok(match, `unsupported registration expression: ${part}`);
    const owner = symbols.get(match[1]);
    assert.notEqual(owner, undefined, `registered fixture source ${match[1]}`);
    const values = match[2] === undefined ? owner : owner[match[2]];
    assert.ok(Array.isArray(values), `registered fixture array ${part}`);
    return values;
  });
}
const inputs = {successes: resolveSpreads(initial[1]),
  refusals: resolveSpreads(initial[2]), executionFailures: resolveSpreads(initial[3])};
const appended = registration.slice(initial[0].length);
const allowedStatement = /scopeInputs\.(successes|refusals|executionFailures)\.push\(([^;]+)\);/gu;
let registrations = 0;
for (const match of appended.matchAll(allowedStatement)) {
  inputs[match[1]].push(...resolveSpreads(match[2]));
  registrations++;
}
assert.ok(registrations > 0);
assert.equal(appended.replace(allowedStatement, '').replace(/if \(!scopeOnly\)\s*\{|\}|\s/gu, ''), '',
  'do not silently skip a new full-corpus registration form');
const rawCounts = Object.fromEntries(Object.entries(inputs).map(([kind, values]) => [kind, values.length]));
const unique = new Map();
const duplicateSuccesses = [];
for (const item of inputs.successes) {
  if (unique.has(item.name)) {
    assert.deepEqual(item, unique.get(item.name), `duplicate success oracle ${item.name}`);
    duplicateSuccesses.push(item.name);
  } else unique.set(item.name, item);
}
inputs.successes = [...unique.values()];

const kinds = ['successes', 'executionFailures', 'refusals'];
const counts = Object.fromEntries(kinds.map(kind => [kind, inputs[kind].length]));
const profiles = publicQueryProfiles(inputs);
const entries = profiles.flatMap(profile => kinds.flatMap(kind => profile.inputs[kind].map((item, position) =>
  [profile.name, kind, position, item.name,
    createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
const inventory = entries.map(entry => JSON.stringify(entry));
const names = ['graph-subtraction-null-is-not-zero', 'graph-subtraction-conflict-needs-policy'];
return {
  ...(includeInputs ? {inputs, inventory, profileInputs: profiles} : {}),
  totalCases: inventory.length,
  inventorySha256: createHash('sha256').update(JSON.stringify(inventory)).digest('hex'),
  counts,
  profiles: profiles.map(profile => ({name: profile.name,
    counts: Object.fromEntries(kinds.map(kind => [kind, profile.inputs[kind].length]))})),
  repeatedFailures: names.map(name => {
    const occurrences = entries.filter(entry => entry[0] === 'standard' && entry[1] === 'executionFailures' && entry[3] === name);
    assert.ok(occurrences.length > 0 && occurrences.every(entry => entry[4] === occurrences[0][4]));
    return {name, positions: occurrences.map(entry => entry[2])};
  }),
};
}
