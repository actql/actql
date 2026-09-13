import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import './interval-search-wire.test.mjs';

const read = path => JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
const path = 'spec/contracts/actql-interval-search.json';
const cid = 'sha256:4a41fc2f6967ceecd95fcd2ae1f5accc722af3090a6db6a1405d8091a8bae3c3';
const vectors = read('portability/corpus/interval-search.json');

test('interval search has its own pinned quantity, not the join output row law', () => {
  const body = read(path);
  assert.equal(machineCid(body), cid);
  assert.equal(body.unit, 'pair_visits');
  assert.equal(read('spec/contracts/actql-bound-join-laws.json').unit, 'rows');
  const language = read('spec/spec-family.json').documents.find(d => d.spec_id === 'actql.language');
  assert.deepEqual(language.machine_contracts.filter(r => r.path === path), [
    {path, pointer: '', cid, version: body.version},
    {path, pointer: '/schemas/limit', cid: machineCid(body.schemas.limit), version: body.version},
  ]);
  const source = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(source.replace(/\s+/g, ' ').includes(`IntervalSearchRules => "${cid}"`));
});

// Independent integer model: expectations are fixed, not emitted by a lowerer.
function fallback(left, right) {
  const max = 9007199254740991n;
  for (const n of [left, right]) {
    if (n !== null && (!Number.isSafeInteger(n) || n < 0)) return {error: 'InvalidValue'};
  }
  if (left === 0 || right === 0) return {expected: 0};
  if (left === null || right === null) return {expected: null};
  const n = BigInt(left) * BigInt(right);
  return n > max ? {error: 'Overflow'} : {expected: Number(n)};
}

test('search fallback fixes unknown, empty, exact-boundary and overflow cases', () => {
  assert.equal(vectors.version, 'actql-interval-search-vectors/0.1');
  for (const {left, right, ...expected} of vectors.bounds) {
    assert.deepEqual(fallback(left, right), expected);
    assert.deepEqual(fallback(right, left), expected);
  }
});

test('visit accounting and product applicability are distinct from matching and output', () => {
  for (const v of vectors.traces) {
    const seen = new Set();
    for (const [l, r] of v.visits) {
      assert.ok(Number.isInteger(l) && l >= 0 && l < v.left);
      assert.ok(Number.isInteger(r) && r >= 0 && r < v.right);
      seen.add(`${l}/${r}`);
    }
    for (const [l, r] of v.matches) assert.ok(seen.has(`${l}/${r}`));
    // A trace can disprove the single-visit condition, not prove that an
    // implementation satisfies it for every input or attest its execution.
    assert.equal(seen.size === v.visits.length, v.single_visit_trace, v.name);
    // This is only the search counter, never admission or execution success.
    assert.equal(v.visits.length <= v.limit, v.within_ceiling, v.name);
  }
  // Enumerate small match incidence relations. Semi/anti can emit <= L even
  // when all L*R candidates must be inspected; no output law bounds visits.
  for (let l = 0; l <= 3; l++) for (let r = 0; r <= 3; r++) {
    for (let mask = 0; mask < 2 ** (l * r); mask++) {
      const matched = new Set();
      let visits = 0;
      for (let i = 0; i < l; i++) for (let j = 0; j < r; j++) {
        visits++;
        if (mask & (1 << (i * r + j))) matched.add(i);
      }
      assert.equal(visits, fallback(l, r).expected);
      assert.ok(matched.size <= l);
      assert.ok(l - matched.size <= l);
    }
  }
});
