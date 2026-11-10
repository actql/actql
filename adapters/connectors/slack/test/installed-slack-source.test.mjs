import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile,writeFile} from 'node:fs/promises';
import {createPublicKey} from 'node:crypto';
import {checkInstalledSlackSourceProfile,installedSlackSourceIdentityParts,loadInstalledSlackSource} from '../host/installed-slack-source.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {installedSlackFixture,assertRetiredSlackCapture} from './installed-slack.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {join} from 'node:path';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';

test('installed Slack refuses absent original Source constructor and credential material without legacy fallback or I/O',async t=>{
  const f=await installedSlackFixture(t);
  // The actual fixture installer deliberately supplies its original constructor
  // after options. Exercise absence at the provider boundary itself.
  await assert.rejects(loadInstalledSlackSource(f.profile,{...f.options,
    installation:f.initial.installation,installationServices:f.initial.installationServices,
    configurationReader:f.initial.configurationReader,sourceInitialization:undefined}),
  {code:'SlackSourceInitializationUnavailable'});
  await assert.rejects(f.load({resolveSecret:undefined}),{code:'SlackCredentialMaterialUnavailable'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack closed original profile rejects undeclared resources authority shortcuts and limit gaps',async t=>{
  const f=await installedSlackFixture(t);const p=checkInstalledSlackSourceProfile(f.profile);
  assert(Object.isFrozen(p)&&Object.isFrozen(p.limits));
  for(const profile of [{...f.profile,workspaceId:''},{...f.profile,resources:['messages']},
    {...f.profile,readerCapacity:{retained:1,execution:1}},
    {...f.profile,limits:{...f.profile.limits,maxRows:0}},
    {...f.profile,limits:{...f.profile.limits,maxTotalResponseBytes:65536}},{...f.profile,limits:{maxRows:2}},
    {...f.profile,siteProfilePath:'relative.json'}])assert.throws(()=>checkInstalledSlackSourceProfile(profile));
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack generation retains exact workspace bytes selected Site generation and TLS authority',async t=>{
  const f=await installedSlackFixture(t);
  const first=await installedSlackSourceIdentityParts(f.profile,{...f.profile,workspaceId:'é'});
  const second=await installedSlackSourceIdentityParts(f.profile,{...f.profile,workspaceId:'é'});
  assert.notEqual(first[2].workspaceBytesCid,second[2].workspaceBytesCid);
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,siteGeneration:2}));
  const next=await installedSlackSourceIdentityParts(f.profile,f.profile);
  assert.equal(next[1].siteGeneration,2);assert.equal(first[1].siteGeneration,1);
  assert.equal(typeof next[2].caSha256,'string');assert.equal(f.state.requests.length,0);
});

test('installed Slack actual text Source retains one original reader capture and acknowledged retirement',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedSlackFixture(t),source=await f.load();
    const preparation=await f.prepare(source,{format});
    const opened=await source.openCapture(preparation);
    await f.retain(opened,preparation.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-slack-label-test'));
    assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
      {id:'U1',name:'one'},
      {id:'U2',name:'two'}]);
    assert.equal(f.state.requests.length,3);assert.equal(f.state.resolutions,3);
    assert.deepEqual(f.state.requests.map(r=>r.method),['POST','GET','GET']);
    assert.equal(f.state.requests[0].path,'/api/auth.test');
    assert.equal(f.state.requests[1].path,'/api/users.list?limit=10');
    assert.equal(f.state.requests[2].path,'/api/users.list?limit=10&cursor=opaque%2B%2F%3D%20cursor');
    await opened.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),
      ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']),[0n,0n,0n,0n]);
    assert.equal(f.state.requests.length,3);
  }
});

test('installed Slack optional TLS authority is bounded original PEM before native transport',async t=>{
  const f=await installedSlackFixture(t);
  await assert.rejects(installedSlackSourceIdentityParts(f.profile,{...f.profile,
    limits:{...f.profile.limits,maxCaBytes:1}}),{message:'InvalidInstalledSourceProfile'});
  const path=join(f.root,'untrusted-ca.pem');
  await writeFile(path,Buffer.from([0xff,0x80,0x01]));
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,caPath:path}));
  await assert.rejects(installedSlackSourceIdentityParts(f.profile,f.profile),{code:'InvalidInstalledSlackTlsAuthority'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('ordinary installed Slack entrance discovers the real factory and refuses missing normal supply',async t=>{
  const f=await installedSlackFixture(t),path=join(f.root,'source.json');
  await writeFile(path,JSON.stringify(f.profile));
  await assert.rejects(loadInstalledSource(path,{...f.options,
    runtimeUrl:new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url)}),
  error=>error.code==='InstalledHostInitializationFailed'&&
    error.primaryFailure?.code==='SlackSourceInitializationUnavailable'&&error.cause===error.primaryFailure);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack copied preparation and missing original Ledger cannot issue a physical request',async t=>{
  const f=await installedSlackFixture(t),source=await f.load(),preparation=await f.prepare(source);
  assert.throws(()=>source.ledgerCapacity({...preparation.preparedSource}),{code:'InstalledSourcePreparationMismatch'});
  await assert.rejects(source.openCapture({...preparation,ledger:undefined}),{code:'InstalledProviderSourceLedgerRequired'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack binding retains original connector identity even for the same workspace Site and runtime',async t=>{
  const f=await installedSlackFixture(t),first=await f.load();
  f.profile.connectorId='other-workspace';const other=await f.load();
  f.profile.connectorId='workspace';const original=await f.load();
  assert.notEqual(first.connectorBindings[0].bindingCid,other.connectorBindings[0].bindingCid);
  assert.equal(first.connectorBindings[0].bindingCid,original.connectorBindings[0].bindingCid);
  assert.notEqual(first.sourceReadAccesses[0].sourceRef,other.sourceReadAccesses[0].sourceRef);
  assert.equal(first.sourceReadAccesses[0].sourceRef,original.sourceReadAccesses[0].sourceRef);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack actual Account deny refuses preparation before Credential or HTTP',async t=>{
  const f=await installedSlackFixture(t,{account:'deny'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack lost original reply keeps same recovery and journal Unknown without another send',async t=>{
  const f=await installedSlackFixture(t),source=await f.load(),preparation=await f.prepare(source);
  f.state.beforeResponse=request=>request.socket.destroy();let original;
  await assert.rejects(source.openCapture(preparation),error=>{
    original=error;let cause=error;
    for(let depth=0;cause!==undefined&&depth<8;depth++,cause=cause.cause){if(cause.code==='ECONNRESET')return true;}
    return false;
  });
  await f.retain(original,preparation.ledger);
  await assertRetiredSlackCapture(f,preparation,original);
  await source.close();
  const publicKey=createPublicKey(await readFile(join(f.root,'credential-authority.pub')));
  const journal=openSqliteCredentialJournal(f.site.journalRoot,{credentialAuthorities:new Map([
    [f.site.credentialAuthorityId,new Map([[f.site.credentialKeyId,publicKey]])]])});
  try{const recovered=journal.recover();assert.equal(recovered.length,1);assert.equal(recovered[0].outcome,'unknown');}
  finally{journal.close();}
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
});


test('installed Slack profile rejects accessor and inherited originals without invoking getters',async t=>{
  const f=await installedSlackFixture(t);let calls=0;
  const accessor={...f.profile};Object.defineProperty(accessor,'workspaceId',{enumerable:true,get(){calls++;return 'T-original';}});
  assert.throws(()=>checkInstalledSlackSourceProfile(accessor),{code:'InvalidInstalledSlackSourceProfile'});
  assert.throws(()=>checkInstalledSlackSourceProfile(Object.create(f.profile)),{code:'InvalidInstalledSlackSourceProfile'});
  const limits={...f.profile.limits};Object.defineProperty(limits,'maxPages',{enumerable:true,get(){calls++;return 4;}});
  assert.throws(()=>checkInstalledSlackSourceProfile({...f.profile,limits}),{code:'InvalidInstalledSlackSourceProfile'});
  assert.equal(calls,0);assert.equal(f.state.requests.length,0);
});

test('installed Slack original workspace observation refuses foreign workspace before users request',async t=>{
  const f=await installedSlackFixture(t),source=await f.load(),preparation=await f.prepare(source);
  f.state.identity={...f.state.identity,team_id:'T-foreign'};let original;
  await assert.rejects(source.openCapture(preparation),error=>{original=error;let cause=error;while(cause&&cause.code!=='ForeignSlackWorkspace')cause=cause.cause;return cause?.code==='ForeignSlackWorkspace';});
  await f.retain(original,preparation.ledger);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.requests[0].path,'/api/auth.test');
  await assertRetiredSlackCapture(f,preparation,original);
});


test('installed Slack stop during original resolver refuses the first physical send and preserves recovery',async t=>{
  const f=await installedSlackFixture(t),source=await f.load(),preparation=await f.prepare(source),stop=new AbortController();
  const reason=new Error('OriginalSlackStop');f.state.resolved=()=>stop.abort(reason);let original;
  await assert.rejects(source.openCapture({...preparation,signal:stop.signal}),error=>{original=error;return error.cause===reason;});
  await f.retain(original,preparation.ledger);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,1);
  await assertRetiredSlackCapture(f,preparation,original);
});


test('installed Slack shared reader snapshots original callbacks and rejects copied receivers or repeated start',async()=>{
  let originalCalls=0,replacementCalls=0,constructors=0;
  // Actual shared managed reader, explicit original Site/current ports. No
  // Resource, Account or capacity admission is claimed by this component.
  const originalSite={site:{},referenceCurrent(){return true;},authorizationPurpose(){return{kind:'read'};},
    bindRunAcquisition(){assert.fail('current refusal precedes original binding');},
    readChildCredential(){assert.fail('no credential after refused current');},callResource(){assert.fail('no send');}};
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent(){},
    maxResponses:1,maxResponseBytes:8192,maxTotalResponseBytes:8192,
    prepareReadSequence(){constructors++;return Object.freeze({
      read(){assert.fail('no provider read after refused current');},retire(){return true;}});}});
  const options={resource:'users',operation:'slack:users:list',columns:['id'],signal:undefined,
    originalAuthorization:{},
    verifyRead(){assert.equal(this,options);originalCalls++;throw Object.assign(new Error('OriginalCurrentRefusal'),{code:'OriginalCurrentRefusal'});},
    authorizationFor(){assert.fail('no authorization after refused current');},authorizeReadChild(){},
    chargePage(){},consumeObservation(){},consumePage(){}};
  const reader=factory.prepare(options);options.verifyRead=()=>{replacementCalls++;};
  await assert.rejects(reader.read.call({...reader}),{code:'ForeignInstalledCredentialSourceReader'});
  await assert.rejects(reader.read(),{code:'OriginalCurrentRefusal'});
  await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
  assert.throws(()=>factory.prepare.call({...factory},options),{code:'ForeignInstalledCredentialSourceReader'});
  assert.equal(originalCalls,1);assert.equal(replacementCalls,0);assert.equal(constructors,1);
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(factory.retire(),true);
});
