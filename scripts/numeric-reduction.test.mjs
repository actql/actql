import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {profile} from './numeric-reduction-contract.mjs';
import {machineCid as cid} from './actql-spec-family.mjs';

// Independent finite model of the prescribed operations, not a product lowerer.
function reduce(input, algorithm) {
  assert(input.every(x => typeof x === 'number' && Number.isFinite(x) && !Object.is(x, -0)));
  if (!input.length) return {sum:null, avg:null};
  const add = (a,b) => { const n = a+b; if (!Number.isFinite(n)) throw Error('nonfinite'); return n; };
  try {
    let sum;
    if (algorithm === 'left_fold') sum = input.reduce(add, 0);
    else {
      let level = input.slice();
      while (level.length > 1) {
        const next = [];
        for (let i=0;i<level.length;i+=2) next.push(i+1<level.length ? add(level[i],level[i+1]) : level[i]);
        level = next;
      }
      sum = level[0];
    }
    const avg = sum / input.length;
    assert(Number.isFinite(avg));
    return {sum:sum===0?0:sum, avg:avg===0?0:avg};
  } catch(e) {
    if (e.message !== 'nonfinite') throw e;
    return {failure:'nonfinite'};
  }
}
test('fixed reduction vectors distinguish algorithm, sequence and failure', () => {
  const corpus = JSON.parse(readFileSync('portability/corpus/numeric-reduction.json','utf8'));
  for (const row of corpus.cases) for (const algorithm of Object.keys(profile.contracts)) {
    assert.deepEqual(reduce(row.contributors,algorithm),row[algorithm],row.name+':'+algorithm);
  }
});
test('contract identities bind the actual rounding and reduction laws', () => {
  assert.notEqual(profile.contract_cids.left_fold,profile.contract_cids.adjacent_pairs);
  for (const [name,body] of Object.entries(profile.contracts)) {
    assert.equal(cid(body),profile.contract_cids[name]);
    assert.notEqual(cid({...body,nonfinite:'ignore'}),profile.contract_cids[name]);
  }
});
test('contributor formation distinguishes filter demand, nulls and distinct', () => {
  const rows = [{keep:false,value:'invalid'},{keep:true,value:null},{keep:true,value:2},{keep:true,value:2},{keep:true,value:4}];
  const contributors = rows.filter(r=>r.keep).map(r=>r.value).filter(v=>v!==null);
  assert.deepEqual(reduce(contributors,'left_fold'),{sum:8,avg:8/3});
  assert.deepEqual(reduce([...new Set(contributors)],'left_fold'),{sum:6,avg:3});
  assert.throws(()=>reduce([NaN],'left_fold'));
  assert.throws(()=>reduce([-0],'left_fold'));
});
