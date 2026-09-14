import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const fixture=JSON.parse(readFileSync(new URL('../portability/corpus/structural-resource-scopes.json',import.meta.url),'utf8'));

// A selected meter contract's accounting, not an implementation of graph union,
// execution evidence admission or a mandated backend instruction cost model.
test('structural folds share cumulative budgets and overlapping peak scopes', () => {
  assert.deepEqual(Object.values(fixture.meters),['cumulative','cumulative','peak','peak']);
  for (const sample of fixture.cases) {
    const usage=[0,0,0,0];
    for (const fold of sample.folds) {
      assert.equal(fold.length,4);
      for(let i=0;i<4;i++) {
        assert.ok(Number.isSafeInteger(fold[i]) && fold[i]>=0);
        usage[i]=i<2?usage[i]+fold[i]:Math.max(usage[i],fold[i]);
      }
    }
    assert.deepEqual(usage,sample.usage,sample.name);
    assert.equal(sample.complete && usage.every((v,i)=>v<=sample.limits[i]),sample.accept,sample.name);
  }
  const excess=fixture.cases.find(c=>c.name==='individually-fitting-folds-exceed-total-work');
  assert.ok(excess.folds.every(f=>f[0]<=excess.limits[0]));
  assert.equal(excess.accept,false);
});
