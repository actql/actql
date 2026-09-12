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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let count = 0;
  for (const pkg of obligationPackages) {
    const api = readFileSync(new URL(`../src/${pkg}/pkg.generated.mbti`, import.meta.url), 'utf8');
    count += validateObligationReads(api, pkg);
  }
  assert.ok(count > 0, 'empty obligation API inventory');
  console.log(`${count} obligation array APIs have typed count/index counterparts.`);
}
