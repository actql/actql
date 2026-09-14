import assert from 'node:assert/strict';
import test from 'node:test';

// Independent selected-meter traces, not measured evaluator costs. Token bytes,
// tokens/text and normalized bytes/text peak; work/traffic accumulate; state peaks.
const peaks = new Set([0,1,2,9,10]);
const cases = [
  {name:'empty inputs still enter admission',trace:[[0,0,0,1,1,0,0,0,0,0,0]],used:[0,0,0,1,1,0,0,0,0,0,0],complete:true,rows:0},
  {name:'repeated bigrams retain token multiplicity',trace:[[2,2,3,3,1,2,2,1,4,3,4]],used:[2,2,3,3,1,2,2,1,4,3,4],complete:true,rows:1},
  {name:'two texts share work but not per-text caps',trace:[[3,1,3,3,1,1,2,1,6,3,6],[2,2,3,3,1,2,2,1,4,4,8]],used:[3,2,3,6,2,3,4,2,10,4,8],complete:true,rows:2},
  {name:'no match does not waive validation',trace:[[2,1,2,2,1,1,1,0,4,2,4]],used:[2,1,2,2,1,1,1,0,4,2,4],complete:false,rows:0},
];
test('lexical per-text ceilings remain distinct from cumulative operation work',()=>{
  for(const c of cases){
    const used=Array(11).fill(0);
    for(const event of c.trace) event.forEach((n,i)=>{used[i]=peaks.has(i)?Math.max(used[i],n):used[i]+n;});
    assert.deepEqual(used,c.used,c.name);
    const admit=(caps,rows)=>c.complete && used.every((n,i)=>n<=caps[i]) && c.rows<=rows;
    assert.equal(admit(c.used,c.rows),c.complete,c.name);
    for(let i=0;i<used.length;i++) if(used[i]>0){const caps=c.used.slice();caps[i]--;assert.equal(admit(caps,c.rows),false,c.name);}
    if(c.rows>0) assert.equal(admit(c.used,c.rows-1),false,c.name);
  }
});
