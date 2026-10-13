// Independent retained/current Values preimages, never product issuer output.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {currentValuesPreimages} from './temporal-join-current-preimages-oracle.mjs';
const directory = 'reviews/2026-10-13-frontend-calendar-source/preimages/';
const canonical = v => Array.isArray(v) ? v.map(canonical) : v && typeof v === 'object'
  ? Object.fromEntries(Object.keys(v).sort().map(k => [k, canonical(v[k])])) : v;
const sha = v => createHash('sha256').update(v).digest('hex');
const cid = v => 'sha256:' + sha(JSON.stringify(canonical(v)));
export function calendarSourceIdentityOracle({current = true} = {}) {
  const {grammar_manifest_cid: pin, ...body} = JSON.parse(readFileSync(directory + 'parent-grammar-manifest.json', 'utf8'));
  assert.equal(cid(body), pin);
  assert.equal(sha(readFileSync(directory + 'parent-query-grammar.ebnf')), body.query_text_grammar_sha256);
  assert.equal(sha(readFileSync(directory + 'parent-query-rules.md')), body.query_text_rules_sha256);
  const next = current ? {...body,
    query_text_grammar_sha256: sha(readFileSync('spec/grammar/actql-query-0.1.ebnf')),
    query_text_rules_sha256: sha(readFileSync('docs/spec/query-text.md'))} : body;
  return currentValuesPreimages({...next, grammar_manifest_cid: cid(next)},
    current ? 'authored-calendar-source' : 'd991b314216fdea38474876d6f10fce1a13f407c');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2), ['--write']);
  for (const [name, current] of [['pre', false], ['current', true]])
    writeFileSync(directory + name + '-values.json', JSON.stringify(calendarSourceIdentityOracle({current}), null, 2) + '\n');
}
