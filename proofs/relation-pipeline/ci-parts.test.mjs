import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname,join} from 'node:path';
import {syncBuiltinESMExports} from 'node:module';
import {fileDigest,packArchive,unpackArchive} from './ci-artifacts.mjs';
import {hash} from './inventory.mjs';
import {partIds,planDigest,plan,partRole} from './proof-parts.mjs';
import {partSchema,partStages,capacityPartExecutions,validatePartEnvelope,validatePartInputs,requireValidation} from './ci-parts.mjs';
import * as transport from './ci-parts.mjs';
const digest='a'.repeat(64);
const identity=path=>{
 const info=fs.statSync(path,{bigint:true});
 return Object.fromEntries(['dev','ino','mode','size','mtimeNs','ctimeNs','nlink','blocks'].map(key=>[key,info[key]]));
};
// Real owned filesystem/TAR transport only; no Native execution is asserted.
function stagedMember(t) {
 const root=fs.realpathSync(fs.mkdtempSync(join(tmpdir(),'actql-part-member-')));
 t.after(()=>fs.rmSync(root,{recursive:true}));
 const producer=join(root,'producer'),bytes=Buffer.alloc(2*1024**2,0xa5);
 const sha256=hash(bytes),member='capacity/custody/binaries/'+sha256;
 fs.mkdirSync(dirname(join(producer,member)),{recursive:true});
 fs.writeFileSync(join(producer,member),bytes);
 fs.writeFileSync(join(producer,'ci-seal.json'),'{}\n');
 const archive=join(root,'evidence.tar'),archiveDigest=packArchive(producer,archive),archiveIdentity=identity(archive);
 const verified=join(root,'verified');unpackArchive(archive,verified,archiveDigest);
 const from=join(verified,member),to=join(root,'union',member);
 fs.mkdirSync(dirname(to),{recursive:true});
 return {root,from,to,bytes,sha256,archive,archiveDigest,archiveIdentity};
}
function originalArchiveUnchanged(f) {
 assert.equal(fileDigest(f.archive),f.archiveDigest);
 assert.deepEqual(identity(f.archive),f.archiveIdentity);
}
test('verified union member consumes one extracted inode without duplicating payload storage',t=>{
 const f=stagedMember(t),before=identity(f.from);
 transport.materializeVerifiedMember(f.from,f.to,f.sha256);
 assert.equal(fs.existsSync(f.from),false,'Verified staging allocation must transfer to the union');
 const after=identity(f.to);
 for(const key of ['dev','ino','size','mtimeNs','blocks'])assert.equal(after[key],before[key],key);
 assert.equal(after.nlink,1n);assert.equal(after.mode&0o777n,0o444n);
 assert.deepEqual(fs.readFileSync(f.to),f.bytes);
 originalArchiveUnchanged(f);
});
function transferFaults(t,methods) {
 for(const [name,implementation] of Object.entries(methods))t.mock.method(fs,name,implementation);
 syncBuiltinESMExports();
 t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
}
function samePayloadIdentity(path,before) {
 const after=identity(path);
 for(const key of ['dev','ino','mode','size','mtimeNs','nlink','blocks'])assert.equal(after[key],before[key],key);
}
test('verified union member refuses an existing destination without changing either original',t=>{
 const f=stagedMember(t);fs.writeFileSync(f.to,f.bytes);
 const source=identity(f.from),target=identity(f.to);
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),{code:'EEXIST'});
 samePayloadIdentity(f.from,source);samePayloadIdentity(f.to,target);
 originalArchiveUnchanged(f);
});
test('verified union member refuses changed bytes before consuming the source',t=>{
 const f=stagedMember(t);fs.chmodSync(f.from,0o644);fs.writeFileSync(f.from,'changed');fs.chmodSync(f.from,0o444);
 const before=identity(f.from);
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),/Verified member bytes changed/);
 samePayloadIdentity(f.from,before);assert.equal(fs.existsSync(f.to),false);
 originalArchiveUnchanged(f);
});
for(const kind of ['symbolic','hard-linked'])test(`verified union member refuses a ${kind} source`,t=>{
 const f=stagedMember(t),other=join(f.root,'other');
 if(kind==='symbolic') {fs.writeFileSync(other,f.bytes);fs.unlinkSync(f.from);fs.symlinkSync(other,f.from);}
 else fs.linkSync(f.from,other);
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),/unlinked regular file/);
 assert.equal(fs.existsSync(f.to),false);assert.deepEqual(fs.readFileSync(other),f.bytes);
 originalArchiveUnchanged(f);
});
test('verified union member preserves source on cross-device failure without a copy fallback',t=>{
 const f=stagedMember(t),before=identity(f.from),failure=Object.assign(new Error('fixture cross-device link'),{code:'EXDEV'});
 let copies=0;
 transferFaults(t,{linkSync(){throw failure;},copyFileSync(){copies++;throw new Error('Copy fallback is forbidden');}});
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),error=>error===failure);
 assert.equal(copies,0);samePayloadIdentity(f.from,before);assert.equal(fs.existsSync(f.to),false);
 originalArchiveUnchanged(f);
});
test('verified union member preserves source and original error when unlink fails',t=>{
 const f=stagedMember(t),before=identity(f.from),unlink=fs.unlinkSync,failure=new Error('fixture source unlink failure');
 transferFaults(t,{unlinkSync(path){if(path===f.from)throw failure;return Reflect.apply(unlink,fs,[path]);}});
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),error=>error===failure);
 samePayloadIdentity(f.from,before);assert.equal(fs.existsSync(f.to),false);
 originalArchiveUnchanged(f);
});
test('verified union member retains canonical bytes after an uncertain source removal',t=>{
 const f=stagedMember(t),before=identity(f.from),unlink=fs.unlinkSync,failure=new Error('fixture error after unlink');
 transferFaults(t,{unlinkSync(path){const value=Reflect.apply(unlink,fs,[path]);if(path===f.from)throw failure;return value;}});
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),error=>error===failure);
 assert.equal(fs.existsSync(f.from),false);samePayloadIdentity(f.to,before);
 assert.equal(fileDigest(f.to),f.sha256);originalArchiveUnchanged(f);
});
test('verified union member reports both source removal and link cleanup failures',t=>{
 const f=stagedMember(t),failure=new Error('fixture source unlink failure'),cleanup=new Error('fixture link cleanup failure');
 transferFaults(t,{unlinkSync(path){throw path===f.from?failure:cleanup;}});
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),error=>{
  assert(error instanceof AggregateError);assert.equal(error.cause,failure);assert.deepEqual(error.errors,[failure,cleanup]);return true;
 });
 assert.equal(fs.statSync(f.from,{bigint:true}).ino,fs.statSync(f.to,{bigint:true}).ino);assert.equal(fs.statSync(f.to,{bigint:true}).nlink,2n);
 assert.deepEqual(fs.readFileSync(f.from),f.bytes);originalArchiveUnchanged(f);
});
test('verified union member detects same-byte source replacement during transfer',t=>{
 const f=stagedMember(t),before=identity(f.from),link=fs.linkSync,held=fs.openSync(f.from,'r');
 let replacement;
 try {
  transferFaults(t,{linkSync(from,to){fs.unlinkSync(from);fs.writeFileSync(from,f.bytes,{mode:0o444});replacement=identity(from);return Reflect.apply(link,fs,[from,to]);}});
  assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),/Verified source identity changed/);
  assert.notEqual(replacement.ino,before.ino);assert.equal(fs.statSync(f.from,{bigint:true}).ino,replacement.ino);
  assert.deepEqual(fs.readFileSync(f.from),f.bytes);originalArchiveUnchanged(f);
 }finally{fs.closeSync(held);}
});
test('verified union member retains the final hash check after transfer',t=>{
 const f=stagedMember(t),unlink=fs.unlinkSync;
 transferFaults(t,{unlinkSync(path){
  if(path===f.from){fs.chmodSync(path,0o644);fs.writeFileSync(path,'changed after validation');}
  return Reflect.apply(unlink,fs,[path]);
 }});
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),/Materialized member bytes changed/);
 assert.equal(fs.existsSync(f.from),false);assert.equal(fs.statSync(f.to,{bigint:true}).nlink,1n);
 originalArchiveUnchanged(f);
});
// Synthetic stat identities model values the Number API rounds together. The
// real fixture still owns its original TAR, files and filesystem operations.
for(const changed of ['source','target'])test(`verified union member detects rounded ${changed} inode identity`,t=>{
 const f=stagedMember(t),stat=fs.lstatSync,descriptorStat=fs.fstatSync,link=fs.linkSync,original=2n**53n;
 const physical=fs.statSync(f.from,{bigint:true}).ino;
 let linked=false;
 assert.equal(Number(original),Number(original+1n));
 transferFaults(t,{
  lstatSync(path,options){
   const info=Reflect.apply(stat,fs,[path,options]);
   if(path===f.from||path===f.to){
    const different=linked&&path===(changed==='source'?f.from:f.to);
    const ino=original+(different?1n:0n);info.ino=options?.bigint?ino:Number(ino);
   }
   return info;
  },
  fstatSync(fd,options){
   const info=Reflect.apply(descriptorStat,fs,[fd,options]);
   if(BigInt(info.ino)===physical)info.ino=options?.bigint?original:Number(original);
   return info;
  },
  linkSync(from,to){const value=Reflect.apply(link,fs,[from,to]);linked=true;return value;}
 });
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),new RegExp(`Verified ${changed} identity changed`));
 assert.equal(fs.existsSync(f.from),true);assert.equal(fs.existsSync(f.to),true);
 assert.deepEqual(fs.readFileSync(f.from),f.bytes);assert.deepEqual(fs.readFileSync(f.to),f.bytes);
 originalArchiveUnchanged(f);
});
test('verified union member preserves a distinct rounded inode during rollback',t=>{
 const f=stagedMember(t),stat=fs.lstatSync,descriptorStat=fs.fstatSync,unlink=fs.unlinkSync,original=2n**53n;
 const physical=fs.statSync(f.from,{bigint:true}).ino;
 const failure=new Error('fixture original source removal failure');
 let failed=false,targetRemovals=0;
 transferFaults(t,{
  lstatSync(path,options){
   const info=Reflect.apply(stat,fs,[path,options]);
   if(path===f.from||path===f.to){
    const ino=original+(failed&&path===f.to?1n:0n);info.ino=options?.bigint?ino:Number(ino);
   }
   return info;
  },
  fstatSync(fd,options){
   const info=Reflect.apply(descriptorStat,fs,[fd,options]);
   if(BigInt(info.ino)===physical)info.ino=options?.bigint?original:Number(original);
   return info;
  },
  unlinkSync(path){
   if(path===f.from){failed=true;throw failure;}
   if(path===f.to)targetRemovals++;
   return Reflect.apply(unlink,fs,[path]);
  }
 });
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),error=>error===failure);
 assert.equal(targetRemovals,0,'Never unlink a different inode that rounds to the original');
 assert.equal(fs.existsSync(f.from),true);assert.equal(fs.existsSync(f.to),true);
 assert.deepEqual(fs.readFileSync(f.to),f.bytes);originalArchiveUnchanged(f);
});
test('verified union member detects submillisecond source modification',t=>{
 const f=stagedMember(t),stat=fs.lstatSync,link=fs.linkSync;
 let linked=false;
 transferFaults(t,{
  lstatSync(path,options){
   const info=Reflect.apply(stat,fs,[path,options]);
   if(linked&&(path===f.from||path===f.to)&&options?.bigint)info.mtimeNs+=1n;
   return info;
  },
  linkSync(from,to){const value=Reflect.apply(link,fs,[from,to]);linked=true;return value;}
 });
 assert.throws(()=>transport.materializeVerifiedMember(f.from,f.to,f.sha256),/Verified source identity changed/);
 assert.equal(fs.existsSync(f.from),true);assert.equal(fs.existsSync(f.to),false);
 assert.deepEqual(fs.readFileSync(f.from),f.bytes);originalArchiveUnchanged(f);
});
const expected={context:{repository:'actql/actql',runId:'1',runAttempt:'1',testedSha:'b'.repeat(40),prHeadSha:null},
 source:{digest},exploration:{required:true},toolchain:{moonbit:{moonc:'pin'}},
 workflow:{ref:'actql/actql/.github/workflows/ci.yml@refs/heads/main',sha:'b'.repeat(40)},planDigest};
function envelope(partId='L-C0a') {
 const path=`${partId}-123-45-0000-normal-js.json`,boundary={workspace:`owner-${partId}`,target:'js',role:'normal'};
 const value={schema:partSchema,partId,...structuredClone(expected),completedStages:[...partStages[partId]],
 restoration:{sourceRestored:true,fixtureClosed:true,workspacesClosed:true},
 files:[{path,kind:'file',size:1,sha256:digest}],evidence:{reports:[{path,sha256:digest}],owners:[boundary.workspace],
 receipts:[{path,sha256:digest,target:'js',boundary,buildIdentity:hash(JSON.stringify(boundary))}],
 observations:[{id:`${partId}-observation`,receipt:path,target:'js',owner:boundary.workspace,caseDigest:digest}]}};
 if(partRole(partId)==='capacity-support') Object.assign(value.evidence,{owners:[],receipts:[],observations:[]});
 return value;
}
const inputs=()=>partIds.map((partId,index)=>({partId,result:'success',artifactId:String(index+1),artifactDigest:digest,archiveDigest:digest,manifestDigest:digest}));
test('fixed plan names exactly four capacity and four mutation producers',()=>{
 assert.deepEqual(partIds,['L-C0a','L-C0b','L-C1a','L-C1b','L-M0a','L-M0b','L-M1a','L-M1b']);
 assert.equal(Object.keys(plan.parts).length,8);
 assert.equal(plan.parts['L-C0a'].obligations.finalNormal.caseCount,114);
 assert.equal(plan.parts['L-C1a'].obligations.ownerLocalRestoration.caseCount,3);
 assert.equal(plan.parts['L-C1a'].obligations.finalNormal,undefined);
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
 unknownReceipt:m=>m.evidence.observations[0].receipt='missing',foreignPart:m=>m.partId='L-C1a',unknownField:m=>m.fullSuccess=true,
 swappedCompiledOwner:m=>m.evidence.receipts[0].boundary.workspace='other',
 alteredFile:m=>m.files[0].sha256='c'.repeat(64),traversal:m=>m.files[0].path='../bad',
})) test(`part seal rejects ${label}`,()=>{
 const m=envelope();change(m);assert.throws(()=>validatePartEnvelope(m,expected,'L-C0a'));
});
test('aggregate accepts exactly eight successful distinct immutable inputs',()=>assert.doesNotThrow(()=>validatePartInputs(inputs())));
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
 assert.deepEqual(capacityPartExecutions({...report,executions:[]}),[]);
 assert.deepEqual(capacityPartExecutions({part:'L-C1a',executions:[primary,restored],postRestore:{executions:[restored]}}),[primary,restored]);
 assert.throws(()=>capacityPartExecutions({...report,executions:[primary]}));
 assert.throws(()=>capacityPartExecutions({part:'L-C0b',executions:[],parentStartup:{execution:primary}}));
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
 return {report:{part:'L-C0b',source,parentStartup:parent},files,read:path=>{
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
