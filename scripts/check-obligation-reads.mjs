import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

// The typed-operation owners and their public facades. Indexed reads are an
// inventory prerequisite, not classification or discharge of these obligations.
export const obligationPackages = [
  'graph_typing', 'vector_typing', 'relation_typing', 'relation_join',
  'relation_join_shape', 'relation_evidence', 'relation_append', 'relation_nest',
  'relation_set', 'relation_values', 'time_series', 'calendar_typing',
  'temporal_window', 'carrier_projection', 'event_typing',
];

export function validateObligationReads(api, owner) {
  let count = 0;
  for (const m of api.matchAll(/^pub fn (\w+)\(([^\n)]*)\) -> Array\[([^\n]+)\]$/gm)) {
    const [, name, args, item] = m;
    if (!/pending|obligations/.test(name) || !/Obligation|PendingValidation/.test(item)) continue;
    const base = /validations$|obligations$/.test(name) ? name.slice(0, -1) : name;
    for (const signature of [
      `pub fn ${base}_count(${args}) -> Int`,
      `pub fn ${base}_at(${args}${args ? ', ' : ''}Int) -> ${item}?`,
    ]) assert.ok(api.split('\n').includes(signature), `${owner}.${name}: missing indexed signature ${signature}`);
    count++;
  }
  return count;
}

// Complements exhaustive MoonBit matches: a family currently returning None
// cannot acquire a new profile obligation without entering the selector.
// This checks coverage, not the normative meaning of the chosen profile.
export function validateProfileObligationCoverage(apis, selector) {
  const expected = new Map();
  const actual = new Map();
  const add = (map, name) => map.set(name, (map.get(name) ?? 0) + 1);
  for (const api of apis) {
    for (const body of api.matchAll(/pub(?:\(all\))? enum (\w*(?:Obligation|Pending\w*|Validation\w*)) \{([\s\S]*?)\n\}/g)) {
      for (const v of body[2].matchAll(/^\s*(\w*Profile)(?:\([^\n]*\))?\s*$/gm)) add(expected, v[1]);
    }
  }
  for (const v of selector.matchAll(/\b(\w*Profile)(?:\([^\n]*\))?\s*=>\s*Some\(/g)) add(actual, v[1]);
  const sorted = map => [...map].sort(([a], [b]) => a.localeCompare(b));
  assert.deepEqual(sorted(actual), sorted(expected), 'profile obligation mapping coverage differs from declared enums');
  return [...expected.values()].reduce((a, b) => a + b, 0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let count = 0;
  const apis = [];
  for (const pkg of obligationPackages) {
    const api = readFileSync(new URL(`../src/${pkg}/pkg.generated.mbti`, import.meta.url), 'utf8');
    apis.push(api);
    count += validateObligationReads(api, pkg);
  }
  assert.ok(count > 0, 'empty obligation API inventory');
  console.log(`${count} obligation array APIs have typed count/index counterparts.`);
  const selector = readFileSync(new URL('../src/pipeline_typing/operation_profile_requirement.mbt', import.meta.url), 'utf8');
  const profiles = validateProfileObligationCoverage(apis, selector);
  assert.ok(profiles > 0, 'empty profile obligation inventory');
  console.log(`${profiles} declared profile obligation variants have explicit resolution mappings.`);
}
