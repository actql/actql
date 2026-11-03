import assert from 'node:assert/strict';
import test from 'node:test';
import {hash} from './inventory.mjs';
import {partIds,planDigest,plan} from './proof-parts.mjs';
import {partSchema,partStages,capacityPartExecutions,validatePartEnvelope,validatePartInputs,requireValidation} from './ci-parts.mjs';
import * as transport from './ci-parts.mjs';
const digest='a'.repeat(64);
const expected={context:{repository:'actql/actql',runId:'1',runAttempt:'1',testedSha:'b'.repeat(40),prHeadSha:null},
 source:{digest},exploration:{required:true},toolchain:{moonbit:{moonc:'pin'}},
 workflow:{ref:'actql/actql/.github/workflows/ci.yml@refs/heads/main',sha:'b'.repeat(40)},planDigest};
function envelope(partId='L-C0') {
 const path=`${partId}-123-45-0000-normal-js.json`,boundary={workspace:`owner-${partId}`,target:'js',role:'normal'};
 return {schema:partSchema,partId,...structuredClone(expected),completedStages:[...partStages[partId]],
 restoration:{sourceRestored:true,fixtureClosed:true,workspacesClosed:true},
 files:[{path,kind:'file',size:1,sha256:digest}],evidence:{reports:[{path,sha256:digest}],owners:[boundary.workspace],
 receipts:[{path,sha256:digest,target:'js',boundary,buildIdentity:hash(JSON.stringify(boundary))}],
 observations:[{id:`${partId}-observation`,receipt:path,target:'js',owner:boundary.workspace,caseDigest:digest}]}};
}
const inputs=()=>partIds.map((partId,index)=>({partId,result:'success',artifactId:String(index+1),artifactDigest:digest,archiveDigest:digest,manifestDigest:digest}));
test('fixed plan names exactly two capacity and two mutation producers',()=>{
 assert.deepEqual(partIds,['L-C0','L-C1','L-M0','L-M1']);
 assert.equal(Object.keys(plan.parts).length,4);
 assert.equal(plan.parts['L-C0'].obligations.finalNormal.caseCount,114);
 assert.equal(plan.parts['L-C1'].obligations.ownerLocalRestoration.caseCount,5);
 assert.equal(plan.parts['L-C1'].obligations.finalNormal,undefined);
});
for(const partId of partIds) test(`${partId} has distinct truthful PART envelope`,()=>{
 assert.doesNotThrow(()=>validatePartEnvelope(envelope(partId),expected,partId));
});
for(const [label,change] of Object.entries({
 missingStage:m=>m.completedStages.pop(),sealBeforeClose:m=>m.restoration.fixtureClosed=false,
 unrestored:m=>m.restoration.sourceRestored=false,liveWorkspace:m=>m.restoration.workspacesClosed=false,
 foreignRun:m=>m.context.runId='2',foreignAttempt:m=>m.context.runAttempt='2',headInsteadOfMerge:m=>m.context.testedSha='c'.repeat(40),
 wrongPlan:m=>m.planDigest='c'.repeat(64),foreignWorkflow:m=>m.workflow.sha='c'.repeat(40),
 foreignSource:m=>m.source.digest='c'.repeat(64),
 duplicateReceipt:m=>m.evidence.receipts.push(m.evidence.receipts[0]),duplicateObservation:m=>m.evidence.observations.push(m.evidence.observations[0]),
 foreignOwner:m=>m.evidence.observations[0].owner='other',foreignTarget:m=>m.evidence.observations[0].target='native',
 unknownReceipt:m=>m.evidence.observations[0].receipt='missing',foreignPart:m=>m.partId='L-C1',unknownField:m=>m.fullSuccess=true,
 swappedCompiledOwner:m=>m.evidence.receipts[0].boundary.workspace='other',
 alteredFile:m=>m.files[0].sha256='c'.repeat(64),traversal:m=>m.files[0].path='../bad',
})) test(`part seal rejects ${label}`,()=>{
 const m=envelope();change(m);assert.throws(()=>validatePartEnvelope(m,expected,'L-C0'));
});
test('aggregate accepts exactly four successful distinct immutable inputs',()=>assert.doesNotThrow(()=>validatePartInputs(inputs())));
for(const [label,change] of Object.entries({missing:x=>x.pop(),duplicate:x=>x[1]=x[0],extra:x=>x.push(x[0]),wrongOrder:x=>x.reverse(),
 failure:x=>x[2].result='failure',skipped:x=>x[3].result='skipped',cancelled:x=>x[0].result='cancelled',
 foreignPart:x=>x[0].partId='L-C2',duplicateArtifact:x=>x[1].artifactId=x[0].artifactId,
 noDigest:x=>delete x[0].archiveDigest,noManifest:x=>delete x[0].manifestDigest,noArtifact:x=>delete x[0].artifactId,
})) test(`aggregate rejects ${label}`,()=>{const x=inputs();change(x);assert.throws(()=>validatePartInputs(x));});
const validation=()=>({result:'success',outputs:{'tested-sha':expected.context.testedSha,'source-digest':expected.source.digest,'plan-digest':planDigest}});
test('synthetic validation is mandatory and bound to exact source and plan',()=>{
 assert.doesNotThrow(()=>requireValidation(validation(),expected));
 for(const result of ['failure','skipped','cancelled',undefined]) assert.throws(()=>requireValidation({...validation(),result},expected));
 for(const key of ['tested-sha','source-digest','plan-digest']){const v=validation();v.outputs[key]='foreign';assert.throws(()=>requireValidation(v,expected));}
 assert.throws(()=>requireValidation(undefined,expected));
});

test('capacity transport keeps current Native evidence distinct from generic execution receipts',()=>{
 const primary={path:'primary'},restored={path:'restored'};
 const {report}=nativeParentInputs();
 assert.deepEqual(capacityPartExecutions({...report,executions:[primary]}),[primary]);
 assert.deepEqual(capacityPartExecutions({part:'L-C1',executions:[primary,restored],postRestore:{executions:[restored]}}),[primary,restored]);
 assert.throws(()=>capacityPartExecutions({part:'L-C0',executions:[primary]}));
 assert.throws(()=>capacityPartExecutions({part:'L-C0',executions:[primary],parentStartup:{execution:primary}}));
});

// Synthetic transport bytes only. Production inspectPart first runs the real
// current Native auditor; these DATA do not establish a Native execution.
function nativeParentInputs() {
 const root='.artifacts/relation-pipeline/',directory=root+'current-chain-native/';
 const log=Buffer.from('original transport log\n'),binary=Buffer.from('original transport binary');
 const object=Buffer.from('original compiled object transport bytes'),code=directory+'code/';
 const objectDigest=hash(object),archive=code+objectDigest+'.o',codeFiles=new Map([[archive,object]]);
 const proof=keys=>({status:'established',platform:'linux-x64',objectDigest,archive,
  logs:Object.fromEntries(keys.map(([key,suffix])=>{
   const bytes=Buffer.from('original '+suffix+' transport bytes'),digest=hash(bytes),path=code+digest+'.'+suffix;
   codeFiles.set(path,bytes);return [key,{path,digest}];
  }))});
 const providerCallbackCode=proof(['symbols','disassembly','linkedDisassembly'].map(key=>[key,key]));
 const parentReferenceCode=proof(['symbols','object','linked'].map(key=>[key,'parent-ref-'+key]));
 const source={digest:'a'.repeat(64),sources:{'src/original.mbt':'b'.repeat(64)}};
 const body={version:'actql-current-chain-native-diagnostic/0.1',target:'native',revision:'c'.repeat(40),source,
  runtime:{platform:'linux-x64'},providerCallbackCode,parentReferenceCode,
  command:['moon','test','--target','native','src/connectors/local/current_chain_capacity_wbtest.mbt','--deny-warn'],exit:0,
  executedSource:source,logPath:directory+'logs/'+hash(log)+'.log',logDigest:hash(log),
  artifacts:{'_build/native/debug/test/connectors/local/local.whitebox_test.exe':hash(binary)},
  archives:{'_build/native/debug/test/connectors/local/local.whitebox_test.exe':directory+'binaries/'+hash(binary)}};
 const parent={...body,providerConstruction:{transportOnly:true}};
 const json=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
 const files=new Map([...codeFiles,[root+'capacity/parent-control-probe/all.json',json(parent)],
  [directory+'source.json',json(source)],[directory+'native.log',log],[parent.logPath,log],
  [directory+'binaries/'+hash(binary),binary],
  [directory+'originals/'+hash(JSON.stringify(body))+'.json',json(body)],
  [directory+'originals/'+hash(JSON.stringify(parent))+'.json',json(parent)]]);
 return {report:{part:'L-C0',source,parentStartup:parent},files,read:path=>{
  assert(files.has(path),'Missing native parent transport input');return files.get(path);
 }};
}
test('capacity transport binds only exact current Native report and payload paths',()=>{
 const f=nativeParentInputs();
 assert.deepEqual(transport.capacityNativeParentInputs(f.report,f.read),[...f.files.keys()].sort());
});
test('capacity transport leaves an unreferenced Native code sibling unclaimed',()=>{
 const f=nativeParentInputs(),bytes=Buffer.from('unreferenced original');
 const extra='.artifacts/relation-pipeline/current-chain-native/code/'+hash(bytes)+'.symbols';
 const expected=[...f.files.keys()].sort();f.files.set(extra,bytes);
 assert.deepEqual(transport.capacityNativeParentInputs(f.report,f.read),expected);
});
function resealNativeTransport(f) {
 const parent=f.report.parentStartup,root='.artifacts/relation-pipeline/';
 const json=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
 f.files.set(root+'capacity/parent-control-probe/all.json',json(parent));
 const {providerConstruction:ignored,...original}=parent;void ignored;
 for(const value of [original,parent]) f.files.set(root+'current-chain-native/originals/'+hash(JSON.stringify(value))+'.json',json(value));
}
for(const [label,change,message] of [
 ['missing compiled object',f=>f.files.delete(f.report.parentStartup.providerCallbackCode.archive),/Missing native parent transport input/],
 ['changed compiled object',f=>f.files.set(f.report.parentStartup.providerCallbackCode.archive,Buffer.from('changed')),/Changed native parent code object/],
 ['changed scalar code log',f=>f.files.set(f.report.parentStartup.providerCallbackCode.logs.symbols.path,Buffer.from('changed')),/Changed native parent code log/],
 ['changed parent reference log',f=>f.files.set(f.report.parentStartup.parentReferenceCode.logs.linked.path,Buffer.from('changed')),/Changed native parent code log/],
 ['foreign code path',f=>{f.report.parentStartup.providerCallbackCode.logs.symbols.path='../foreign';resealNativeTransport(f);},/Foreign native parent code log path/],
 ['different reference object',f=>{f.report.parentStartup.parentReferenceCode.objectDigest='d'.repeat(64);resealNativeTransport(f);},/Different native parent code object/],
 ['foreign code platform',f=>{f.report.parentStartup.providerCallbackCode.platform='darwin-arm64';resealNativeTransport(f);},/Foreign native parent code platform/],
]) test(`capacity transport refuses ${label}`,()=>{
 const f=nativeParentInputs();change(f);
 assert.throws(()=>transport.capacityNativeParentInputs(f.report,f.read),message);
});
for(const [label,change,message] of [
 ['missing original',(f)=>f.files.delete(f.report.parentStartup.logPath),/Missing native parent transport input/],
 ['changed log',(f)=>f.files.set(f.report.parentStartup.logPath,Buffer.from('changed')),/Changed native parent log/],
 ['foreign report',(f)=>f.files.set('.artifacts/relation-pipeline/capacity/parent-control-probe/all.json',Buffer.from('{}\n')),/Changed native parent report/],
 ['escaped archive',(f)=>{
  const parent=f.report.parentStartup,root='.artifacts/relation-pipeline/';
  for(const key of Object.keys(parent.archives)) parent.archives[key]='../foreign';
  const json=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
  f.files.set(root+'capacity/parent-control-probe/all.json',json(parent));
  const {providerConstruction:ignored,...original}=parent;void ignored;
  for(const value of [original,parent]) f.files.set(root+'current-chain-native/originals/'+hash(JSON.stringify(value))+'.json',json(value));
 },/Foreign native parent binary path/],
 ['stale source',(f)=>f.report.source={digest:'d'.repeat(64)},/Foreign native parent source/],
 ['wrong platform',(f)=>f.report.parentStartup.target='js',/Foreign native parent target/],
 ['nonzero execution',(f)=>f.report.parentStartup.exit=1,/Failed native parent execution/],
]) test(`capacity transport refuses ${label}`,()=>{
 const f=nativeParentInputs();change(f);
 assert.throws(()=>transport.capacityNativeParentInputs(f.report,f.read),message);
});
