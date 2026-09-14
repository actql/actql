import assert from 'node:assert/strict';
import test from 'node:test';

// Independent selected-meter traces: input/grouping work, ordering work, fold
// work, byte traffic, temporary peak and retained peak. Not evaluator costs.
const cases = [
  {name:'empty input',trace:[[1,0,0,0,0,0]],used:[1,0,0,0,0,0],complete:true},
  {name:'two groups share the operation budget',trace:[[2,3,4,8,4,12],[2,3,4,8,6,16]],used:[4,6,8,16,6,16],complete:true},
  {name:'member encoding traffic counts',trace:[[2,1,0,12,4,8],[1,2,4,8,6,16]],used:[3,3,4,20,6,16],complete:true},
  {name:'incomplete member validation',trace:[[1,0,0,4,4,4]],used:[1,0,0,4,4,4],complete:false},
];
test('pool resource ceilings apply across groups and member identity encoding', () => {
  for(const c of cases) {
    const used=[0,0,0,0,0,0];
    for(const event of c.trace) event.forEach((v,i)=>{used[i]=i<4?used[i]+v:Math.max(used[i],v);});
    assert.deepEqual(used,c.used,c.name);
    const admit=caps=>c.complete && used.every((n,i)=>n<=caps[i]);
    assert.equal(admit(c.used),c.complete,c.name);
    for(let i=0;i<used.length;i++) if(used[i]>0) {
      const caps=c.used.slice(); caps[i]--;
      assert.equal(admit(caps),false,c.name);
    }
  }
});
