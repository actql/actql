import test from 'node:test';
import assert from 'node:assert/strict';
import {projectProjectedTypeSafeDecisionAnswers} from './_internal/typesafe-decision.mjs';

// Actual private SDK consumer, explicit Common boundary ports. No runtime
// response admission, raw Store ACK or installed Decision is claimed here.
function fixture() {
  const projected={},provider={},request={},response={};
  const limits={maxBytes:4096,maxDepth:20,maxNodes:100,maxWork:1000};
  const expected={_0:'{"original":{"probability":0.25}}',_1:91};
  let calls=0;
  const moon={clientProgramNativeDecisionRequestMatches:(v,p,r)=>
    v===projected&&p===provider&&r===request,
    clientProgramProjectNativeDecisionAnswers(v,p,r,raw,bytes,nodes,depth,work) {
      calls++;assert.equal(v,projected);assert.equal(p,provider);assert.equal(r,request);
      assert.equal(raw,response);assert.deepEqual([bytes,nodes,depth,work],[4096,100,20,1000]);
      return {$tag:1,_0:expected};
    }};
  return {args:{moon,projected,admittedProvider:provider,request,admittedResponse:response,limits},
    expected,calls:()=>calls};
}
test('native answer consumer delegates original opaque bindings and returns Common wire unchanged',()=>{
  const f=fixture();assert.equal(projectProjectedTypeSafeDecisionAnswers(f.args),f.expected);
  assert.equal(f.calls(),1);
});
test('native answer consumer refuses foreign view before decoding or projecting',()=>{
  for(const change of [a=>{a.projected={};},a=>{a.request={};},a=>{a.admittedProvider={};},
    a=>{delete a.moon.clientProgramProjectNativeDecisionAnswers;}]) {
    const f=fixture();change(f.args);
    assert.throws(()=>projectProjectedTypeSafeDecisionAnswers(f.args),/TypeSafeOriginalProjectionUnavailable/);
    assert.equal(f.calls(),0);
  }
});
test('native answer consumer enforces finite limits and preserves Common refusal',()=>{
  for(const limits of [null,{}, {maxBytes:0,maxDepth:20,maxNodes:100,maxWork:1000},
    {maxBytes:4096,maxDepth:20,maxNodes:100,maxWork:-1},
    {maxBytes:4096,maxDepth:20,maxNodes:100,maxWork:1000,permission:true}]) {
    const f=fixture();f.args.limits=limits;
    assert.throws(()=>projectProjectedTypeSafeDecisionAnswers(f.args),/InvalidTypeSafeAnswerProjectionLimits/);
    assert.equal(f.calls(),0);
  }
  const f=fixture();f.args.moon.clientProgramProjectNativeDecisionAnswers=()=>({$tag:0,_0:'malformed'});
  assert.throws(()=>projectProjectedTypeSafeDecisionAnswers(f.args),/TypeSafeOriginalAnswerProjectionRefused/);
});
test('native answer consumer uses inspected DATA limits without invoking getters or rereading Proxy values',()=>{
  const f=fixture();let reads=0;
  f.args.limits=new Proxy(f.args.limits,{get(){reads++;return -1;}});
  assert.equal(projectProjectedTypeSafeDecisionAnswers(f.args),f.expected);
  assert.equal(reads,0);assert.equal(f.calls(),1);
  const g=fixture();Object.defineProperty(g.args.limits,'maxBytes',{get(){assert.fail('No getter');}});
  assert.throws(()=>projectProjectedTypeSafeDecisionAnswers(g.args),/InvalidTypeSafeAnswerProjectionLimits/);
  assert.equal(g.calls(),0);
});
