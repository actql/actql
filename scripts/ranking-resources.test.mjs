import assert from 'node:assert/strict';
import test from 'node:test';

// Independent traces of selected meters, not estimates of an evaluator's cost.
// Admission, fusion, ordering and traffic accumulate; temporary/retained state peak.
const cases = [
  {name:'empty rankings',trace:[[1,0,0,0,0,0]],used:[1,0,0,0,0,0],complete:true,rows:0},
  {name:'two query groups share limits',trace:[[2,3,1,8,4,8],[2,3,2,12,6,12]],used:[4,6,3,20,6,12],complete:true,rows:2},
  {name:'repeated occurrence with shared storage',trace:[[2,2,0,8,4,8],[2,2,1,8,4,8]],used:[4,4,1,16,4,8],complete:true,rows:1},
  {name:'zero weight does not waive admission',trace:[[2,0,0,8,4,8]],used:[2,0,0,8,4,8],complete:false,rows:0},
  {name:'invalid rank beyond window',trace:[[3,0,0,12,4,8]],used:[3,0,0,12,4,8],complete:false,rows:0},
];
test('ranking budgets cover complete inputs and all query groups atomically',()=>{
  for(const c of cases){
    const used=[0,0,0,0,0,0];
    for(const event of c.trace) event.forEach((n,i)=>{used[i]=i<4?used[i]+n:Math.max(used[i],n);});
    assert.deepEqual(used,c.used,c.name);
    const admit=(caps,rows)=>c.complete && used.every((n,i)=>n<=caps[i]) && c.rows<=rows;
    assert.equal(admit(c.used,c.rows),c.complete,c.name);
    for(let i=0;i<used.length;i++) if(used[i]>0){
      const caps=c.used.slice();caps[i]--;
      assert.equal(admit(caps,c.rows),false,c.name);
    }
    if(c.rows>0) assert.equal(admit(c.used,c.rows-1),false,c.name);
  }
});
