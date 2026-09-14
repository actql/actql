import assert from 'node:assert/strict';
import test from 'node:test';

// Selected meter observations, not a requirement to implement a brute-force
// search or predictions of a particular backend's instruction costs.
const cases = [
  {name:'top one',c:3,q:2,k:1,rows:2,trace:[[3,3,2,8,4,12],[2,3,2,8,6,16]],used:[5,6,4,16,6,16],complete:true},
  {name:'top two same observed scoring work',c:3,q:2,k:2,rows:4,trace:[[3,3,3,8,4,12],[2,3,3,8,6,16]],used:[5,6,6,16,6,16],complete:true},
  {name:'empty queries still admit candidates',c:3,q:0,k:2,rows:0,trace:[[3,0,0,8,4,8]],used:[3,0,0,8,4,8],complete:true},
  {name:'empty candidates still admit queries',c:0,q:2,k:2,rows:0,trace:[[2,0,0,8,4,8]],used:[2,0,0,8,4,8],complete:true},
  {name:'empty queries invalid candidate',c:3,q:0,k:2,rows:0,trace:[[1,0,0,4,4,4]],used:[1,0,0,4,4,4],complete:false},
];
test('nearest output selection and whole-operation resource meters are independent', () => {
  for(const c of cases) {
    assert.equal(c.q*Math.min(c.c,c.k),c.rows,c.name);
    const used=[0,0,0,0,0,0];
    for(const event of c.trace) event.forEach((v,i)=>{used[i]=i<4?used[i]+v:Math.max(used[i],v);});
    assert.deepEqual(used,c.used,c.name);
    const admit=(caps,outputCap)=>c.complete && c.rows<=outputCap && used.every((n,i)=>n<=caps[i]);
    assert.equal(admit(c.used,c.rows),c.complete,c.name);
    for(let i=0;i<used.length;i++) if(used[i]>0) {
      const caps=c.used.slice(); caps[i]--;
      assert.equal(admit(caps,c.rows),false,c.name);
    }
    if(c.rows>0) assert.equal(admit(c.used,c.rows-1),false,c.name);
  }
});
