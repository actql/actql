import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import test from 'node:test';
const source=await readFile(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const node=ast.body.find(item=>item.type==='ExportNamedDeclaration' && item.declaration?.id?.name==='sourceFreeValuesPlan').declaration;
const digest=value=>'sha256:'+createHash('sha256').update(JSON.stringify(value)).digest('hex');
function fixture(rows){
  const prepared={},publicationOriginal={},calls=[],admissions=new WeakMap();
  const globals={
    prepareQueryInvocation:()=>undefined,instant:value=>new Date(value).toISOString(),
    randomUUID:()=> 'original-run-id',
    policyCid:name=>digest({version:'actql-installed-local-policy/0.1',name}),
    valuesExecutionContextCid:scope=>digest({version:'actql-installed-local-context/0.1',authority_scope_cid:scope}),
    // Old source calls this and demonstrably refuses the large original.
    valuesHostPolicyOriginal:maxRows=>{if(maxRows>10000)throw new TypeError('InvalidLocalValuesRowLimit');return undefined;},
    bindQueryInvocation:()=>({}),limits:{},
    checkedLocalOutputLimits:(moon,actual,original)=>{assert.equal(actual,prepared);assert.equal(original,publicationOriginal);return {maxRows:rows};},
    localPublicationPlan:options=>Object.freeze(options),valuesAdmissions:admissions,
    retainOriginalPlan:plan=>plan,
  };
  const make=Function(...Object.keys(globals),`return (${source.slice(node.start,node.end)});`)(...Object.values(globals));
  const options={preparedProgram:prepared,publicationOriginal,authorityScopeCid:'scope',namespaceId:'namespace',storeAuthorityCid:'store',now:()=> '2026-10-24T00:00:00Z',
    moon:{clientProgramValuesMaxRows:()=>rows,clientProgramDefinitionCid:()=> 'definition',clientProgramResultCount:()=>1},
    control:{
      prepareCheckedClientCompiledRun(actual,kind,policy){assert.equal(actual,prepared);calls.push(policy);return {admission:{},compiledPlan:{identity:'plan'},preparedEvidence:{wire:'prepared'},authorization:{wire:'authorization'}};},
      defineCheckedClientCompiledRun(compiled,options){return {wire:options.retainedDefinitionWire ?? JSON.stringify({created_at:options.createdAt,valid_until:options.validUntil})};},
      issueCheckedClientCompiledInvocation:()=>({observation:{},invocation:{}}),
    }};
  return {make,options,calls,admissions};
}
test('large original Values demand uses the existing policy identity across retained definition replay',()=>{
  const f=fixture(100000),first=f.make(f.options);
  const second=f.make({...f.options,retainedDefinitionWire:first.runDefinition.wire});
  const expectedPolicy=digest({version:'actql-installed-local-policy/0.1',name:'source-free-values'});
  assert.equal(f.calls.length,2);
  assert.equal(f.calls[0].hostPolicyCid,expectedPolicy);
  assert.deepEqual(f.calls[1],f.calls[0]);
  assert.equal(second.runDefinition.wire,first.runDefinition.wire);
  assert.equal(first.outputLimits.maxRows,100000);
  assert.equal(Object.hasOwn(f.admissions.get(first),'valuesHostPolicyOriginal'),false);
});
test('original publication owner remains required, independent of row count',()=>{
  const f=fixture(121);
  assert.throws(()=>f.make({...f.options,publicationOriginal:{}}),assert.AssertionError);
  const plan=f.make(f.options);
  assert.equal(plan.outputLimits.maxRows,121);
});


function timedOriginalFixture(kind='values',retained=false){
  const prepared={},request={},artifact={},time={},context={},opaque=new Proxy({}, {get(){assert.fail('opaque Core Option read');}}),calls=[];
  const compilation={kind,admission:{},compiledPlan:{identity:'plan'},preparedEvidence:{wire:'prepared'},authorization:{wire:'authorization'}};
  const header={created_at:'2026-10-31T00:00:00.000Z',valid_until:'2026-11-01T00:00:00.000Z'};
  const wire=JSON.stringify(header),definition={wire};let samples=0,nowReads=0;
  const choose=name=>ast.body.map(n=>n.type==='ExportNamedDeclaration'?n.declaration:n).find(n=>n?.type==='FunctionDeclaration'&&n.id.name===name);
  const names=['prepareTimedClientInvocation','bindQueryInvocation','checkedOriginalQueryInvocation','checkedTaskRunAdmission'];
  const declarations=names.map(name=>{const n=choose(name);assert(n,name);return source.slice(n.start,n.end);}).join('\n');
  const globals={sampleOriginalQueryTime:()=>{samples++;return header.created_at;},instant:ms=>new Date(ms).toISOString(),randomUUID:()=> 'one-original-run',cid:()=> 'context',policyCid:()=> 'policy',valuesExecutionContextCid:()=> 'context',retainOriginalPlan:plan=>plan};
  const functions=Function(...Object.keys(globals),declarations+';return {prepareTimedClientInvocation,checkedOriginalQueryInvocation,checkedTaskRunAdmission};')(...Object.values(globals));
  const control={
    prepareClientQueryTime(p,r,at){assert.equal(p,prepared);assert.equal(r,request);assert.equal(at,header.created_at);calls.push('time');return time;},
    prepareCheckedClientCompiledRun(p,k,policy,graph,original){assert.equal(p,prepared);assert.equal(k,kind);assert.equal(graph,undefined);assert.equal(original,artifact);assert.equal(policy.expiresAt,header.valid_until);calls.push('issue-compiled');return compilation;},
    defineCheckedClientCompiledRun(c,h){assert.equal(c,compilation);assert.equal(h.createdAt,header.created_at);assert.equal(h.validUntil,header.valid_until);assert.equal(h.retainedDefinitionWire,retained?wire:undefined);calls.push('define');return definition;},
    bindClientQueryTime(q,p,c,d,r){assert.equal(q,time);assert.equal(p,prepared);assert.equal(c,compilation);assert.equal(d,definition);assert.equal(r,request);calls.push('bind');return context;},
    restoreClientQueryTime(p,c,d,r){assert.equal(p,prepared);assert.equal(c,compilation);assert.equal(d,definition);assert.equal(r,request);calls.push('restore-original');return {queryTimePreparation:time,queryTime:context};},
    clientQueryTimeInvocationOriginal(q,p){assert.equal(q,time);assert.equal(p,prepared);calls.push('original-option');return opaque;},
    checkClientCompiledRunOwner(c,p){assert.equal(c,compilation);assert.equal(p,prepared);},
    checkClientCompiledRunDefinition(c,d){assert.equal(c,compilation);assert.equal(d,definition);},
  };
  const retainedInvocation={preparedProgram:prepared,requestIdentity:request,compiled:undefined,runDefinition:undefined,createdAt:undefined,validUntil:undefined,queryTimePreparation:undefined,queryTime:undefined};
  const options={control,preparedProgram:prepared,requestIdentity:request,compilationOriginal:artifact,retainedInvocation,kind,authorityScopeCid:'scope',namespaceId:'namespace',now:()=>{nowReads++;return header.created_at;},...(retained?{retainedDefinitionWire:wire}:{})};
  let carrier;const build=()=>{carrier=functions.prepareTimedClientInvocation(options);return carrier.retained;};
  return {functions,build,options,control,prepared,request,compilation,definition,time,context,opaque,calls,get samples(){return samples;},get nowReads(){return nowReads;},get carrier(){return carrier;}};
}

test('timed original construction binds one sample and first compilation before forwarding Core Option',()=>{
  for(const kind of ['values','tasks']){
    const f=timedOriginalFixture(kind),original=f.build();
    assert.equal(f.carrier.original,f.opaque);assert.equal(Object.hasOwn(original,'invocationOriginal'),false);assert.equal(original.compiled,f.compilation);assert.equal(original.runDefinition,f.definition);
    assert.equal(original.queryTimePreparation,f.time);assert.equal(original.queryTime,f.context);assert.equal(original.requestIdentity,f.request);assert(Object.isFrozen(original));
    assert.equal(f.samples,1);assert.equal(f.nowReads,1);assert.deepEqual(f.calls,['time','issue-compiled','define','bind','original-option']);
  }
});

test('timed original restoration retains original header without sampling another query time',()=>{
  const f=timedOriginalFixture('tasks',true),original=f.build();
  assert.equal(f.samples,0);assert.equal(f.nowReads,1);assert.equal(original.runDefinition,f.definition);assert.equal(f.carrier.original,f.opaque);assert.equal(Object.hasOwn(original,'invocationOriginal'),false);
  assert.deepEqual(f.calls,['issue-compiled','define','restore-original','original-option']);
});

test('timed original downstream Task admission reuses first Run and never issues or samples again',()=>{
  const f=timedOriginalFixture('tasks'),original=f.build(),before=f.calls.slice();
  const actual=f.functions.checkedTaskRunAdmission({...f.options,publicationPreparation:{},invocationOriginal:original,now:()=>assert.fail('second clock')},'tasks');
  assert.equal(actual.compiled,f.compilation);assert.equal(actual.runDefinition,f.definition);assert.equal(actual.queryTimePreparation,f.time);assert.equal(actual.queryTime,f.context);
  assert.deepEqual(f.calls,before);assert.equal(f.samples,1);
  for(const update of [{preparedProgram:{}},{requestIdentity:{}},{retainedDefinitionWire:'foreign'}])assert.throws(()=>f.functions.checkedTaskRunAdmission({...f.options,...update,invocationOriginal:original},'tasks'),/ForeignClientQueryInvocationOriginal/);
  assert.deepEqual(f.calls,before);
});

test('timed original downstream Values publication preserves first Run and full publication duties',()=>{
  const f=timedOriginalFixture(),original=f.build(),publicationOriginal={},seen=[];
  const originalPlans=new WeakMap(),metadataLimits={},runPlanOriginal={};
  const retention=ast.body.find(x=>x.type==='FunctionDeclaration'&&x.id.name==='retainOriginalPlan');
  const retainOriginalPlan=Function('originalPlans','limits',
    'return ('+source.slice(retention.start,retention.end)+');')(originalPlans,metadataLimits);
  f.control.captureOriginalClientRunPlan=(compiled,prepared,definition,limits)=>{
    assert.equal(compiled,f.compilation);assert.equal(prepared,f.prepared);
    assert.equal(definition,f.definition);assert.equal(limits,metadataLimits);
    seen.push('retain');return runPlanOriginal;
  };
  const globals={checkedOriginalQueryInvocation:f.functions.checkedOriginalQueryInvocation,prepareQueryInvocation:()=>assert.fail('second time preparation'),bindQueryInvocation:()=>assert.fail('second bind'),instant:()=>assert.fail('second header'),randomUUID:()=>assert.fail('second Run'),policyCid:()=> 'policy',valuesExecutionContextCid:()=> 'context',limits:{},checkedLocalOutputLimits:(moon,p,v)=>{assert.equal(p,f.prepared);assert.equal(v,publicationOriginal);return {maxRows:10};},localPublicationPlan:value=>{seen.push('publication');return Object.freeze(value);},valuesAdmissions:new WeakMap(),retainOriginalPlan};
  const n=ast.body.find(x=>x.type==='ExportNamedDeclaration'&&x.declaration?.id?.name==='sourceFreeValuesPlan').declaration;
  const make=Function(...Object.keys(globals),'return ('+source.slice(n.start,n.end)+');')(...Object.values(globals));
  f.control.issueCheckedClientCompiledInvocation=(c,d)=>{assert.equal(c,f.compilation);assert.equal(d,f.definition);seen.push('issue-publication');return {observation:{},invocation:{}};};
  const before=f.calls.slice(),value=make({...f.options,moon:{clientProgramDefinitionCid:()=> 'program',clientProgramResultCount:()=>1},publicationOriginal,publicationPreparation:{},invocationOriginal:original,now:()=>assert.fail('second clock')});
  assert.equal(value.runDefinition,f.definition);
  const retained=originalPlans.get(value);
  assert.equal(retained.queryTimePreparation,f.time);assert.equal(retained.queryTime,f.context);
  assert.equal(retained.original,runPlanOriginal);
  assert.equal(retained.executionOwner.program,f.prepared);assert.equal(retained.executionOwner.compiled,f.compilation);
  assert(Object.isFrozen(retained));assert(Object.isFrozen(retained.executionOwner));
  assert.equal(Object.hasOwn(value,'queryTimePreparation'),false);assert.equal(Object.hasOwn(value,'queryTime'),false);
  assert.deepEqual(f.calls,before);assert.deepEqual(seen,['issue-publication','publication','retain']);
});


test('timed invocation keeps each returned original in the same pre-retained carrier on failure',()=>{
  for(const step of ['defineCheckedClientCompiledRun','bindClientQueryTime','clientQueryTimeInvocationOriginal']){
    const f=timedOriginalFixture('tasks'),primary=Object.freeze(Error('original invocation constructor refusal'));
    f.control[step]=()=>{throw primary;};
    assert.throws(()=>f.build(),error=>error===primary);
    const held=f.options.retainedInvocation;
    assert.equal(held.queryTimePreparation,f.time);assert.equal(held.compiled,f.compilation);
    if(step!=='defineCheckedClientCompiledRun')assert.equal(held.runDefinition,f.definition);
    if(step==='clientQueryTimeInvocationOriginal')assert.equal(held.queryTime,f.context);
    assert.equal(Object.isFrozen(held),false);assert.equal(f.samples,1);
  }
});

test('timed invocation refuses missing custody and bounds the pre-admission retained wire before work',()=>{
  for(const change of [{retainedInvocation:undefined},{retainedDefinitionWire:' '.repeat(100001)}]){
    const f=timedOriginalFixture('tasks');Object.assign(f.options,change);
    assert.throws(()=>f.build(),/OriginalClientQueryInvocationRequired/);
    assert.equal(f.samples,0);assert.equal(f.nowReads,0);assert.deepEqual(f.calls,[]);
  }
});
