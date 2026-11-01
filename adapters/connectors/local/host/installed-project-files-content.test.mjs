import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {openLocalFileRoot} from '../site/root-filesystem.mjs';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {defaultFileMediaType as mime} from '../../../host-common/file-media-type.mjs';

// Complete original Local installer statements with explicit Common/Account
// ports and an actual retained native filesystem. This is not a Common
// admission, public package, permission or end-to-end Content qualification.
const moduleUrl=new URL('./installed-project-files.mjs',import.meta.url);
const source=await readFile(moduleUrl,'utf8'),tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const selected=new Set(['fail','canonical','cid','positive','text','acknowledged',
  'physicalReadChild','installPreparedProjectLocalFiles']);
const statements=tree.body.flatMap(node=>{
  const value=node.type==='ExportNamedDeclaration'?node.declaration:node;
  const names=value?.type==='VariableDeclaration'?value.declarations.map(item=>item.id.name):[value?.id?.name];
  if(!names.some(name=>selected.has(name)))return[];
  names.forEach(name=>assert(selected.delete(name),name));
  return[source.slice(value.start,value.end)];
});
assert.equal(selected.size,0);
const body=statements.join('\n').replaceAll('import.meta.url','moduleUrl');
const factory=new Function('createHash','canonicalJson','checked','runtimeOptionalField','readFile','moduleUrl',
  'createInstalledRowSource','rowSourceCheckEnvironment','composeInstalledCheckEnvironment',
  'retainInstalledHostInitializationFailure','AcquisitionOpenError','openLocalFileRoot','mime',
  body+'\nreturn installPreparedProjectLocalFiles;');
const canonical=value=>canonicalJson(value,{dataKeys:true});
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const ok=value=>({$tag:1,_0:value});
const root=fileURLToPath(new URL('../../../../',import.meta.url));
let scratch,native,sequence=0;
test.before(async()=>{
  assert(process.env.ACTQL_TEST_LOCAL_NATIVE_MODULE,'Select a qualified existing native module');
  const bytes=await readFile(process.env.ACTQL_TEST_LOCAL_NATIVE_MODULE);
  if(process.env.ACTQL_TEST_LOCAL_NATIVE_ORIGINAL){
    // This fixture may use its own normal standalone filesystem build. Bind
    // the supplied build record to the actual binary, tool and source inputs;
    // it grants no product admission or physical-current authority.
    const original=JSON.parse(await readFile(process.env.ACTQL_TEST_LOCAL_NATIVE_ORIGINAL));
    const hash=value=>createHash('sha256').update(value).digest('hex');
    assert.equal(original.platform,process.platform);assert.equal(original.arch,process.arch);
    assert.equal(original.node,process.versions.node);assert.equal(original.moduleAbi,process.versions.modules);
    assert.equal(original.nodeSha256,hash(await readFile(process.execPath)));
    assert.equal(original.source.path,'adapters/host-node/native/directory-darwin.c');
    assert.equal(original.source.sha256,hash(await readFile(join(root,original.source.path))));
    for(const path of ['adapters/connectors/local/site/root-filesystem.inc',
      'adapters/connectors/local/site/root-file-writer.inc']){
      const input=original.headers.find(row=>row.path===path);assert(input);
      const actual=await readFile(join(root,path));assert.equal(input.bytes,actual.length);assert.equal(input.sha256,hash(actual));
    }
    assert.equal(original.binary.bytes,bytes.length);assert.equal(original.binary.sha256,hash(bytes));
  }else assert.equal(createHash('sha256').update(bytes).digest('hex'),
    'aa0293929cd7d681e14b74ef2c34043ce9ffb0bb47ac42d876ba59e3d2179856');
  native=createRequire(import.meta.url)(process.env.ACTQL_TEST_LOCAL_NATIVE_MODULE);
  scratch=await createOwnedScratch({parent:join(root,'_build'),prefix:'local-content-caller-',
    label:'Local Content actual native caller with explicit Common ports'});
});
test.after(()=>scratch?.passed());

async function fixture({changedAfterFactory=false,failBegin=false,denied=false,shortReads=false,
  pendingClose=false,empty=false}={}){
  const directory=join(scratch.path,String(++sequence));await mkdir(directory);
  const bytes=Buffer.from(empty?'':'original bounded native bytes\n');await writeFile(join(directory,'one.txt'),bytes);
  const s=await stat(join(directory,'one.txt'),{bigint:true});
  const version='sha256:'+createHash('sha256').update(JSON.stringify({size:String(s.size),
    modifiedSeconds:String(s.mtimeNs/1000000000n),modifiedNanos:String(s.mtimeNs%1000000000n)})).digest('hex');
  const declaration={},scopeCid='sha256:'+'a'.repeat(64),contextCid='sha256:'+'b'.repeat(64);
  const limits={maxEntries:16,maxDepth:4,maxPathBytes:256,maxFiles:4,maxFileBytes:1024,maxReadBytes:4096,
    maxPages:64,maxPageBytes:8,maxPageRows:4,maxAttempts:64,maxDurationMs:10000,maxListingBytes:4096};
  const wire=JSON.stringify({views:[{resource:'files',source_ref:'local:files',view_cid:'view',carrier_schema_cid:'schema'},
    {resource:'contents',source_ref:'local:contents',view_cid:'view2',carrier_schema_cid:'schema2'}]});
  const entry={connection:'local',rootPath:directory,wire,declaration,scopeCid,versionMode:'metadata',limits,
    queryAliases:[{name:'local',resource:'files'},{name:'local.contents',resource:'contents'}]};
  const bundle={sources:[entry]},prepared={},request={},keyed={},selected={},run={},original={},read={};
  const sourceInput={},parent={},requestInput={};
  const serializationGraph=Object.freeze({task:0,step:1});
  let options,current=true,physical,rawClosed=false,closeAllowed=!pendingClose,nativeReads=0,runCheck;
  const calls=[],raws=[];
  const moon={
    clientProgramLocalFileTimestamp:()=>'',clientProgramResourceReferenceIssuer:()=>({}),
    clientProgramSelectSingleKeyedAcquisition:()=>{throw new Error('Must retain the original checked keyed selection');},
    clientProgramKeyedAcquisitionMatchesProgram:(value,owner)=>value===keyed&&owner===prepared,
    clientProgramKeyedDirectAcquisitionCoordinates:()=>({_0:0,_1:0}),
    clientProgramSelectInstalledSourceInput:(owner,intent,stage,input)=>{
      assert.strictEqual(owner,prepared);assert.strictEqual(intent,request);assert.equal(stage,0);assert.equal(input,0);
      return ok(sourceInput);},
    clientProgramSelectedSourceInputKind:value=>{assert.strictEqual(value,sourceInput);return'query';},
    clientProgramSelectedSourceInputRef:value=>{assert.strictEqual(value,sourceInput);return'local:files';},
    clientProgramPrepareLocalQueryRequirement:()=>ok({}),clientProgramQueryRequirementSourceRef:()=> 'local:files',
    clientProgramKeyedAcquisitionSourceEvidenceFacts:()=>ok(['local:contents']),
    clientProgramRowSourcePrepareAcquisition:(actual)=>{assert.strictEqual(actual,declaration);return ok({});},
    clientProgramInstalledRowCaptureCapacity:()=>({}),
    clientProgramInstalledManagedKeyedContentPrepare:()=>ok(selected),
    clientProgramNodeLocalContentRunPrepare:()=>assert.fail('No independent Content admission'),
    clientProgramInstalledManagedKeyedContentRunBegin:()=>assert.fail('No standalone Content begin'),
    clientProgramInstalledManagedRunCheck:(actual,value,intent)=>{
      calls.push('core-bound-check');assert.strictEqual(actual,run);assert.strictEqual(value,prepared);
      if(intent!==request)return{$tag:0,_0:'ForeignLocalFilesRequest'};
      runCheck?.(contentPreparation.localPreparation);return ok();},
    clientProgramInstalledManagedKeyedContentCheckPreparation:(actual,value)=>{
      assert.strictEqual(actual,selected);assert.strictEqual(value,prepared);return ok();},
    clientProgramInstalledManagedRunPrepareLedger:()=>ok(original),
    clientProgramInstalledManagedKeyedSourceRead:(parent,k,q,d)=>{
      assert.strictEqual(parent,run);assert.strictEqual(k,keyed);assert.strictEqual(q,keyedRequest);assert.strictEqual(d,declaration);return ok(read);},
    clientProgramInstalledKeyedSourceReadCheckCurrent:()=>ok(),
    clientProgramInstalledKeyedSourceReadRetire:value=>{assert.strictEqual(value,read);assert(physical===undefined||physical.status().pending===false);calls.push('retire');return ok();},
    clientProgramInstalledManagedRunRetire:()=>assert.fail('Local physical child cannot retire its Host parent'),
    clientProgramNodeManagedRunCleanup:()=>assert.fail('No standalone admission cleanup'),
  };
  const sourceManaged={assertCurrent(){if(!current)throw new Error('current-changed');},
    prepareRun(){throw new Error('wrong-purpose');},prepareRead(){throw new Error('wrong-child');},
    prepareContentRun(){assert.fail('No standalone Content Root');},
    prepareKeyedRead(value,d,parent,q){
      assert.strictEqual(value,prepared);assert.strictEqual(d,declaration);assert.strictEqual(parent,original);assert.strictEqual(q,keyedRequest);
      const raw={retainChild(child){physical=child;calls.push('retain-native');},
        close(){calls.push('raw-close');rawClosed=true;return{pending:false};},status:()=>({pending:!rawClosed})};
      raws.push(raw);if(changedAfterFactory)current=false;return raw;
    }};
  const decision={action:'dispatch',boundary:'acquisition',contextCid,
    tuple:{connection:'local',resource:'contents',operation:'read'}};
  const authorization={context:{contextCid},assertAccountCurrent(value){
    assert.strictEqual(this,authorization);
    if(denied||value!==decision)throw Object.assign(new Error('LocalFilesReadGrantNotAuthorized'),
      {code:'LocalFilesReadGrantNotAuthorized'});
    calls.push('original-account-current');
  }};
  const install=factory(createHash,canonicalJson,checked,runtimeOptionalField,readFile,moduleUrl,
    async value=>{options=value;return{connectorBindings:[],admitsSource:()=>true};},
    ()=>({wire:'{}'}),()=> '{}',async cause=>cause,AcquisitionOpenError,openLocalFileRoot,mime);
  const nativeFilesystem=Object.fromEntries(Object.keys(native).map(name=>[name,native[name]]));
  nativeFilesystem.fileRootRead=(handle,offset,length)=>{
    nativeReads++;const value=Reflect.apply(native.fileRootRead,native,[handle,offset,length]);
    return shortReads?value.subarray(0,1):value;
  };
  nativeFilesystem.fileRootClose=handle=>closeAllowed?Reflect.apply(native.fileRootClose,native,[handle]):{outcome:'pending',errno:0};
  const profile=await install({moon,preparation:{originalsForRuntime:()=>bundle},sourceManaged,
    baseEnvironmentWire:'{}',authorizationFor:async()=>authorization,nativeFilesystem,
    prepareManagedContentRun(value,intent,graph,recipe,construct){
      assert.strictEqual(value,prepared);assert.strictEqual(intent,request);assert.strictEqual(graph,serializationGraph);
      calls.push('same-host-parent');assert.strictEqual(construct(parent,requestInput),selected);calls.push('selected');
      if(failBegin)throw Object.assign(new Error('partial-begin'),{code:'OriginalHostContentAdoptionFailed'});
      calls.push('adopt');return{original,value:run,selectedKeyed:selected,contentCompilation:{}};
    }});
  const recipe=Object.freeze({registry:'registry',values:'values',task:0,step:1,keyedAcquisition:keyed,
    prefixRetainedBytes:1n,prefixExecutionBytes:1n});
  const contentPreparation={prepared,inputHolder:{},contentControl:Object.freeze({
    prepareRequestKeyedPlan(actualParent,actualInput,intent,actualKeyed,direct,content){
      assert.strictEqual(actualParent,parent);assert.strictEqual(actualInput,requestInput);
      assert.strictEqual(intent,request);assert.strictEqual(actualKeyed,keyed);
      assert.strictEqual(direct,declaration);assert.strictEqual(content,declaration);return selected;
    }})};
  const keyedRequest={};
  const resource={$actql_ref:'resource',version:'actql-resource-ref/0.1',provider_namespace:'local',
    resource_kind:'file',provider_identity_cid:scopeCid,authority_scope_cid:contextCid,
    boundary_cid:scopeCid,identity_cid:cid({root_scope:scopeCid,path:'one.txt'})};
  return{profile,options,prepared,request,keyed,recipe,serializationGraph,contentPreparation,
    keyedRequest,read,resource,version,bytes,calls,raws,decision,authorization,
    acknowledgeClose(){closeAllowed=true;},get nativeReads(){return nativeReads;},
    prepare:(intent=request)=>profile.prepareManagedContentRun(prepared,intent,recipe,serializationGraph,contentPreparation),
    setRunCheck(value){runCheck=value;},invalidateCurrent(){current=false;},
    prepareRead:()=>options.prepareKeyedSourceRead({checkedOwner:prepared,keyedAcquisition:keyed,
      request:keyedRequest,declaration}),
    async readContent({path='one.txt',actualResource=resource,actualVersion=version}={}){
      let ticket,rawBytes=0,rows;
      await options.readPages({resource:'contents',rowRun:{originalKeyedRead:read},
        capturedResourcePath:async()=>path,requestWire:JSON.stringify({resource:actualResource,version:actualVersion}),
        verifyRead:async()=>{calls.push('authorize-current');},
        beginRequest:async()=>{calls.push('send');},
        chargePage(part){assert.equal(ticket,undefined);assert(part.length<=limits.maxPageBytes);rawBytes+=part.length;ticket={};calls.push('raw-charge');return ticket;},
        consumeObservation(value){assert.strictEqual(value,ticket);ticket=undefined;calls.push('raw-consume');},
        captureContent:async value=>{assert.equal(rawBytes,bytes.length);assert.equal(ticket,undefined);
          assert.deepEqual(value.bytes,bytes);calls.push('capture');return{$actql_ref:'content'};},
        consumePage:async value=>{rows=value;calls.push('row');}});
      return rows;
    }};
}

test('Local Content installer selects the existing Run-owned capture before keyed dispatch',async()=>{
  const f=await fixture();
  assert.equal(f.profile.sources.length,1);
  assert.equal(f.profile.sources[0].requiresRunContentCapture,true);
  f.prepare();
  assert.deepEqual(f.calls.slice(0,3),['same-host-parent','selected','adopt']);
  await f.profile.close();
});

test('Local Content prior reuse performs exactly one original request-bound Core check',async()=>{
  const f=await fixture();const original=f.prepare();
  const before=f.calls.filter(name=>name==='core-bound-check').length;
  assert.strictEqual(f.prepare(),original);
  assert.equal(f.calls.filter(name=>name==='core-bound-check').length-before,1);
  assert.equal(f.calls.filter(name=>name==='same-host-parent').length,1);
  await f.profile.close();
});
test('Local Content prior reuse refuses a foreign request through that same Core check',async()=>{
  const f=await fixture();f.prepare();const before=f.calls.filter(name=>name==='core-bound-check').length;
  assert.throws(()=>f.prepare({}),{code:'MoonBitHostFailure'});
  assert.equal(f.calls.filter(name=>name==='core-bound-check').length-before,1);
  await f.profile.close();
});
test('Local Content direct prior reuse refuses explicit undefined without substituting the retained Request',async()=>{
  const f=await fixture();f.prepare();const before=f.calls.filter(name=>name==='core-bound-check').length;
  // Call the actual installed entry directly: fixture.prepare has a default
  // argument and must not hide this missing-input distinction.
  assert.throws(()=>f.profile.prepareManagedContentRun(f.prepared,undefined,f.recipe,
    f.serializationGraph,f.contentPreparation),{code:'ForeignLocalFilesContentPreparation'});
  assert.equal(f.calls.filter(name=>name==='core-bound-check').length,before);
  await f.profile.close();
});
test('Local Content prior reuse rechecks original identity after Core callback reentry',async()=>{
  for(const change of [run=>{run.retired=true;},run=>{run.request={};},run=>{run.value={};},
    run=>{run.effectful=true;},run=>{run.recipe={};},run=>{run.graph={};},run=>{run.hostRun={};}]){
    const f=await fixture();f.prepare();let original,restore;
    f.setRunCheck(run=>{original=run;restore={...run};change(run);});
    assert.throws(()=>f.prepare());
    for(const key of Object.keys(original))if(!Object.hasOwn(restore,key))delete original[key];
    Object.assign(original,restore);f.setRunCheck(undefined);await f.profile.close();
  }
});
test('Local Content prior reuse retains current and failed-parent refusal without another admission',async()=>{
  const f=await fixture();f.prepare();f.invalidateCurrent();
  const before=f.calls.filter(name=>name==='core-bound-check').length;
  assert.throws(()=>f.prepare(),/current-changed/u);
  assert.equal(f.calls.filter(name=>name==='core-bound-check').length,before);
  await f.profile.close();
  const failed=await fixture();failed.prepare();const cause=new Error('original-parent-failed');let retained;
  failed.setRunCheck(run=>{retained=run;run.failed=true;run.failure=cause;});
  assert.throws(()=>failed.prepare(),error=>error===cause);
  delete retained.failed;delete retained.failure;failed.setRunCheck(undefined);await failed.profile.close();
});

test('Local Content caller retains original admission, actual native bytes and same reference/version row',async()=>{
  const f=await fixture();f.prepare();assert.deepEqual(f.calls.slice(0,3),['same-host-parent','selected','adopt']);
  assert.strictEqual(f.prepareRead(),f.read);
  const rows=await f.readContent();assert.deepEqual(rows,[{resource:f.resource,version:f.version,
    path:'one.txt',media_type:'text/plain',content:{$actql_ref:'content'}}]);
  assert(f.calls.filter(x=>x==='raw-charge').length>1);
  assert(f.calls.indexOf('retain-native')>f.calls.indexOf('send'));
  await f.options.closeKeyedSourceRead(f.read);await f.profile.close();assert.equal(f.calls.includes('parent-retire'),false);
  // The current shared Host releases the exact physical child and external
  // close before the original Core retirement, never after it.
  assert(f.calls.indexOf('raw-close')>=0);
  assert(f.calls.indexOf('retire')>f.calls.indexOf('raw-close'));
});
test('Local Content grant requires original Account decision and exact tuple',async()=>{
  const f=await fixture();const fields={operation:'read',decision:f.decision,resource:'contents',
    runInvocationCid:'sha256:'+'c'.repeat(64),dispatchRequestCid:'sha256:'+'d'.repeat(64),maxUses:1};
  assert.deepEqual(f.options.site.issueReadGrant(fields),{runInvocationCid:fields.runInvocationCid,dispatchRequestCid:fields.dispatchRequestCid});
  for(const changed of [{decision:{...f.decision}},{operation:'write'},{resource:'foreign'},{maxUses:0}])
    assert.throws(()=>f.options.site.issueReadGrant({...fields,...changed}),{code:'LocalFilesReadGrantNotAuthorized'});
  await f.profile.close();
});
test('Local Content grant captures the same Account fence and never treats a copied Allow as original',async()=>{
  const f=await fixture();let replacement=0;
  f.authorization.assertAccountCurrent=()=>{replacement++;};
  const fields={operation:'read',decision:f.decision,resource:'contents',
    runInvocationCid:'sha256:'+'c'.repeat(64),dispatchRequestCid:'sha256:'+'d'.repeat(64),maxUses:1};
  f.options.site.issueReadGrant(fields);
  assert.equal(f.calls.filter(name=>name==='original-account-current').length,1);
  assert.equal(replacement,0);
  assert.throws(()=>f.options.site.issueReadGrant({...fields,decision:{...f.decision}}),
    {code:'LocalFilesReadGrantNotAuthorized'});
  const denied=await fixture({denied:true});
  assert.throws(()=>denied.options.site.issueReadGrant({...fields,decision:denied.decision}),
    {code:'LocalFilesReadGrantNotAuthorized'});
  await f.profile.close();await denied.profile.close();
});
test('Local Content ledger borrows only the same prepared recipe and declared raw transport',async()=>{
  const f=await fixture();f.prepare();
  const capacity={...f.options.originalKeyedTransport,maxBytes:8,maxWork:1000000};
  const direct={capacity:{},transferBytes:512n,executionBytes:8n};
  assert(f.profile.managedContentLedger(f.prepared,f.request,f.recipe,direct,f.keyed,capacity));
  for(const foreign of [{recipe:{...f.recipe}},{keyed:{}},{capacity:{...capacity,executionBytes:8n}}])
    assert.throws(()=>f.profile.managedContentLedger(f.prepared,f.request,foreign.recipe??f.recipe,
      direct,foreign.keyed??f.keyed,foreign.capacity??capacity),{code:'ForeignLocalFilesContentPreparation'});
  await f.profile.close();
});
test('Local Content wrong locator/resource/version refuses before capture and closes actual native custody',async()=>{
  for(const options of [{path:'other.txt'},{actualResource:{}},{actualVersion:'foreign-version'}]){
    const f=await fixture();f.prepare();f.prepareRead();
    await assert.rejects(f.readContent(options),error=>error instanceof AcquisitionOpenError&&error.outcome!=='unknown');
    assert.equal(f.calls.includes('capture'),false);await f.options.closeKeyedSourceRead(f.read);await f.profile.close();
  }
});
test('Local Content post-factory current failure retains the original close and partial parent cleanup',async()=>{
  const f=await fixture({changedAfterFactory:true});f.prepare();
  assert.throws(f.prepareRead,/current-changed/u);
  assert.equal(f.raws.length,1);const original=f.raws[0].close;let replacement=0;
  f.raws[0].close=()=>{replacement++;return{pending:false};};
  await f.profile.close();assert.equal(replacement,0);assert.equal(f.calls.includes('raw-close'),true);
  assert.notStrictEqual(f.raws[0].close,original);
});
test('Local Content failed Host adoption never creates or cleans another admission',async()=>{
  const f=await fixture({failBegin:true});assert.throws(f.prepare,{code:'OriginalHostContentAdoptionFailed'});
  assert.throws(f.prepare);assert.equal(f.calls.filter(x=>x==='same-host-parent').length,1);
  await f.profile.close();assert.equal(f.calls.includes('parent-retire'),false);assert.equal(f.calls.includes('partial-parent-cleanup'),false);
});
test('Local Content native short reads and empty bytes preserve the same exact bounded output',async()=>{
  for(const options of [{shortReads:true},{empty:true}]){
    const f=await fixture(options);f.prepare();f.prepareRead();await f.readContent();
    assert.equal(f.nativeReads,options.empty?0:f.bytes.length);
    await f.options.closeKeyedSourceRead(f.read);await f.profile.close();
  }
});
test('Local Content version refusal retains physical-only pending cleanup before Core retirement',async()=>{
  const f=await fixture({pendingClose:true});f.prepare();f.prepareRead();let failure;
  try{await f.readContent({actualVersion:'changed'});}catch(cause){failure=cause;}
  assert(failure instanceof AcquisitionOpenError);assert.equal(failure.outcome,'unknown');
  assert.equal(failure.recovery.cleanupPending(),true);assert.equal(await failure.recovery.cleanup(),false);
  assert.equal(f.calls.includes('retire'),false);assert.equal(f.calls.includes('capture'),false);
  f.acknowledgeClose();assert.equal(await failure.recovery.cleanup(),true);
  await f.options.closeKeyedSourceRead(f.read);await f.profile.close();
  assert.equal(f.calls.filter(name=>name==='send').length,1);
});
