import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {generateRoundPrecisionReference} from './round-precision-reference.mjs';
const corpus=()=>JSON.parse(readFileSync('portability/corpus/round-precision-reference.json','utf8'));
test('precision reference generation preserves independently fixed source payloads',()=>{
  const original=corpus(),before=structuredClone(original);
  const result=generateRoundPrecisionReference(original);
  assert.deepEqual(original,before);
  assert.deepEqual(result,generateRoundPrecisionReference(original));
  assert.equal((result.vectors.match(/test "/gu)??[]).length,5);
  assert.equal((result.powers.match(/test "/gu)??[]).length,1);
  assert.ok(result.vectors.includes('0x4885617970e7e3beUL'));
});
test('precision reference corpus keeps critical DD and subnormal counterexamples',()=>{
  const rows=corpus().rows;
  assert.ok(rows.some(r=>r[0]==='4885617970e7e3bd'&&r[2]===-26&&r[3]==='4885617970e7e3be'));
  assert.ok(rows.some(r=>r[0]==='0010000000000000'&&r[2]===311&&r[3]==='000fffdd31a00c6e'&&r[4]==='000fffdd31a00c6e'));
  assert.ok(rows.some(r=>r[0]==='3fd3333333333333'&&r[2]===1&&r[4]==='3fc999999999999a'));
});
test('precision reference generator refuses stale provenance shape and nonfinite payloads',()=>{
  for(const change of [
    c=>c.reference_commit='0'.repeat(40),c=>c.rows.pop(),c=>c.rows[1]=c.rows[0],
    c=>c.rows[0][2]=1.5,c=>c.rows[0][4]='7ff0000000000000',c=>c.power_pairs.pop(),
    c=>c.power_pairs[0][0]=-324,c=>c.round_overflow_count++,
  ]){const c=corpus();change(c);assert.throws(()=>generateRoundPrecisionReference(c));}
});
