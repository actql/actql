import assert from 'node:assert/strict';
import test from 'node:test';

// Independent selected-meter traces, not inferred costs of a vector evaluator.
// component work, ordering work, byte traffic, temporary peak, retained peak.
const cases = [
  {name:'empty', trace:[[1,0,0,0,0]], cap:[1,0,0,0,0], used:[1,0,0,0,0], complete:true, accept:true},
  {name:'whole operation exact', trace:[[2,0,8,4,8],[2,3,8,6,16]], cap:[4,3,16,6,16], used:[4,3,16,6,16], complete:true, accept:true},
  ...[0,1,2,3,4].map(i => ({name:`short meter ${i}`,trace:[[2,0,8,4,8],[2,3,8,6,16]],cap:[4,3,16,6,16].map((n,j)=>n-(j===i?1:0)),used:[4,3,16,6,16],complete:true,accept:false})),
  {name:'empty input invalid query',trace:[[1,0,0,0,0]],cap:[1,0,0,0,0],used:[1,0,0,0,0],complete:false,accept:false},
];
test('vector component and score ordering meters have distinct whole-operation scopes', () => {
  for(const c of cases) {
    const used=[0,0,0,0,0];
    for(const event of c.trace) event.forEach((v,i)=>{used[i]=i<3?used[i]+v:Math.max(used[i],v);});
    assert.deepEqual(used,c.used,c.name);
    assert.equal(c.complete && used.every((n,i)=>n<=c.cap[i]),c.accept,c.name);
  }
});
