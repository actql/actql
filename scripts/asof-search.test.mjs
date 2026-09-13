import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const path = 'spec/contracts/actql-asof-search.json';
const cid = 'sha256:1d7fba7118fe71311cd8272b5c002bb5761088911c5adcad3fb4fb729ce5a096';
test('asof search has an operation-specific pin distinct from row and interval laws', () => {
  const contract = read(path);
  assert.equal(machineCid(contract), cid);
  assert.equal(contract.unit, 'pair_visits');
  assert.notEqual(cid, machineCid(read('spec/contracts/actql-interval-search.json')));
  assert.equal(read('spec/contracts/actql-bound-join-laws.json').unit, 'rows');
  const language = read('spec/spec-family.json').documents.find(d => d.spec_id === 'actql.language');
  assert.deepEqual(language.machine_contracts.filter(r => r.path === path), [{path,pointer:'',cid,version:contract.version}]);
  assert.ok(readFileSync('src/pipeline_check_context/core_contracts.mbt','utf8').replace(/\s+/g,' ').includes(`AsOfSearchRules => "${cid}"`));
});
test('asof visit ceilings count rejected pairs independently of ties and selected output', () => {
  const corpus = read('portability/corpus/asof-search.json');
  assert.equal(corpus.version, 'actql-asof-search-vectors/0.1');
  for (const v of corpus.traces) {
    const seen = new Set();
    for (const [l,r] of v.visits) {
      assert.ok(Number.isInteger(l) && l >= 0 && l < v.left);
      assert.ok(Number.isInteger(r) && r >= 0 && r < v.right);
      seen.add(`${l}/${r}`);
    }
    for (const [l,r] of v.eligible) assert.ok(seen.has(`${l}/${r}`));
    assert.equal(seen.size === v.visits.length, v.single_visit, v.name);
    assert.equal(v.visits.length <= v.limit, v.within_limit, v.name);
    // No assertion here equates a within-budget trace with successful matching,
    // absence of ties, complete input admission, or backend conformance.
  }
});
