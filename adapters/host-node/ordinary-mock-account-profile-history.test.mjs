import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,mkdir,readFile,writeFile,rename,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import {createAccountConstruction} from './account-construction.mjs';
import {canonicalJson,contentCid} from './local-account-config.mjs';

const previous=Object.freeze({id:'actql-local-mock',version:'0.1',
  cid:'sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a'});
const answerOnly=Object.freeze({...previous,
  cid:'sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f'});
const named=Object.freeze({...previous,cid:'sha256:c910a820bfc2428234bcb73701593a3aafe7f457fb586eb000d4587c1e600a5e'});
const current=Object.freeze({...previous,
  cid:'sha256:8d3a8a44d338852bdef34d4547dc8a9c22d91e9831dac20ee42f144de8793e01'});

test('plural Mock pre-signing refusal retains the original Read before keys or Account creation',async()=>{
  const f=await fixture({signingMetadata:false});
  const original=Object.freeze({kind:'explicit resource-port refusal'}),reads=[],closed=[];
  let refusing=false,release=false,inventory=0,preSigning=0;
  // Fault injection at the numeric port of the actual nominal construction
  // facet. These ports do not issue a real Ledger, policy, grant or physical ACK.
  f.moon.clientProgramAccountReadControlBytes=()=>64n;
  f.moon.clientProgramPrepareAccountReadConstruction=(read,retained,execution)=>{
    assert.ok(reads.includes(read));assert.ok(retained>=64n&&execution>=retained);
    return refusing?{$tag:0,_0:original}:{$tag:1,_0:undefined};
  };
  f.moon.clientProgramCloseAccountRead=(read,ended)=>{
    assert.equal(ended,true);assert.ok(reads.includes(read));closed.push(read);
    return {$tag:1,_0:release};
  };
  f.moon.clientProgramCompleteAccountReadConstruction=()=>assert.fail('failed constructor cannot complete');
  f.moon.clientProgramLocalMockAccountControlConnectionPrepared=(preferred,profile,original,sources,targets,prepare)=>{
    assert.equal(preferred,'local-mock');assert.equal(profile,undefined);assert.equal(original,undefined);
    assert.equal(prepare(64n,128n),true);return {$tag:1,_0:preferred};
  };
  f.moon.clientProgramLocalMockAccountInventoryPrepared=(connection,sources,tasks,request,targets,prepare)=>{
    inventory++;assert.equal(connection,'local-mock');assert.equal(sources.length,2);
    assert.equal(targets.length,2);assert.deepEqual(tasks,[]);assert.equal(request,undefined);
    assert.equal(prepare(0n,128n),true);
    return {$tag:1,_0:undefined};
  };
  f.moon.clientProgramLocalMockAccountBeforeSigningPrepared=(account,principal,connection,sources,tasks,request,targets,units,prepare)=>{
    preSigning++;assert.match(account,/^local-mock-/);assert.equal(units,71);
    assert.equal(sources.length,2);assert.equal(targets.length,2);
    refusing=true;return prepare(0n,256n);
  };
  f.moon.clientProgramLocalMockAccountConfigurationPrepared=()=>assert.fail('no configuration after refusal');
  const construction=createAccountConstruction({moon:f.moon,current(){},prepareRead(){
    const read=Object.freeze({id:reads.length});reads.push(read);return {$tag:1,_0:read};
  }});
  const sources=[['mock','first'],['mock','second']];
  await assert.rejects(initializeOrdinaryMockAccount({...f.options,accountConstruction:construction,
    sources,updateTargets:sources}),cause=>cause.code==='MoonBitHostFailure'&&cause.cause===original);
  assert.equal(inventory,1);assert.equal(preSigning,1);assert.equal(f.calls.configuration,0);
  await assert.rejects(stat(join(f.root,'mock-account')),{code:'ENOENT'});
  assert.equal(reads.length,2);assert.equal(construction.pending(),true);
  assert.equal(await construction.close(),false);
  assert.deepEqual(closed,[reads[1]],'pending frame keeps the fixed original Read held');
  assert.equal(construction.pending(),true);
  release=true;
  assert.equal(await construction.close(),true);
  assert.deepEqual(closed,[reads[1],reads[1],reads[0]],'retry closes the SAME frame before the SAME fixed Read');
  assert.equal(reads.length,2,'cleanup cannot replace the refused originals');
  assert.equal(construction.pending(),false);
});

// Real exclusive filesystem/key initialization, with explicit Common and Store
// ports. These doubles issue no actual Account, Run, Result or Store authority;
// the Common policy/evaluator is tested in its own actual Owner cases.
async function fixture({signingMetadata=true,profile=previous}={}) {
  const root=await mkdtemp(join(process.env.ACTQL_TEST_STATE_SCRATCH??tmpdir(),'actql-mock-profile-history-'));
  const calls={configuration:0,known:[],admitted:[],issues:0};let selected=profile;
  const moon={
    clientProgramLocalMockAccountProfile(){return {_0:selected.id,_1:selected.version,_2:selected.cid,_3:'fixture policy'};},
    clientProgramLocalMockAccountProfileKnown(id,version,cid){
      assert.strictEqual(this,moon);calls.known.push([id,version,cid]);
      return [previous,answerOnly,current,named].some(p=>p.id===id&&p.version===version&&p.cid===cid);
    },
    clientProgramLocalMockAccountConfiguration(accountId,principal,connection,sources,modelTasks){
      calls.configuration++;
      calls.modelTasks=modelTasks;
      return {$tag:1,_0:canonicalJson({version:'actql-execution-account-config/0.1',account_id:accountId,
        bootstrap:{profile_id:selected.id,profile_version:selected.version,profile_cid:selected.cid},
        entries:[{entry_id:'explicit-fixture-only',principal,connection,outcome:'deny'}]})};
    },
    executionAuthorizationAdmit(wire){assert.equal(typeof JSON.parse(wire).account_id,'string');calls.admitted.push(wire);},
    clientLocalSigningBootstrapOriginal(){return {_0:'explicit fixture policy',_1:'fixture-policy-cid'};},
    clientLocalSigningPublicKeyOriginal(bytes){
      assert.strictEqual(this,moon);assert.equal(bytes.length,32);
      const body={version:'actql-local-signing-public-key/0.1',algorithm:'ed25519',public_key:Buffer.from(bytes).toString('base64')};
      return {$tag:1,_0:{_0:canonicalJson(body),_1:contentCid(body)}};
    },
    clientLocalSigningBootstrapIssue(policy,cid,intent,sampledAt,validUntil){
      assert.equal(policy,'explicit fixture policy');assert.equal(cid,'fixture-policy-cid');
      calls.issues++;return {$tag:1,_0:{_0:'fixture-issuer',_1:sampledAt,_2:validUntil,_3:1}};
    },
  };
  if(!signingMetadata){delete moon.clientLocalSigningBootstrapOriginal;
    delete moon.clientLocalSigningPublicKeyOriginal;delete moon.clientLocalSigningBootstrapIssue;}
  const options={moon,root,principal:'local-test',subject:{projectDirectory:root,backend:'original-test'},
    sources:[],modelTasks:[],explicitSelection:true,assertExclusiveCurrent(){}};
  const store=Object.freeze({status(){return {closed:false};}});
  async function adopt(binding){await mkdir(join(root,'publication'));
    await writeFile(join(root,'publication','store.json'),'explicit Store original fixture',{mode:0o600,flag:'wx'});
    await binding.adoptStore(store);
  }
  const originals=['initialization.json','adopted.json','account.json','reviewer.pem','host.pem','continuation.key'];
  const snapshot=async(excluded=[])=>Promise.all(originals.filter(name=>!excluded.includes(name)).map(async name=>({name,bytes:await readFile(join(root,'mock-account',name)),mode:(await stat(join(root,'mock-account',name))).mode&0o777})));
  return {root,moon,options,calls,store,adopt,snapshot,useCurrent(){selected=current;}};
}

test('saved predecessor Mock initialization reopens without profile migration or replacement keys',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);const before=await f.snapshot();
  f.useCurrent();
  const reopened=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.deepEqual(reopened.profile,previous);
  assert.deepEqual(await f.snapshot(),before);
  assert.equal(f.calls.configuration,1,'reopen must not materialize the newer grants');
  assert.deepEqual(f.calls.known.at(-1),[previous.id,previous.version,previous.cid]);
  assert.equal(reopened.reviewer.resource,first.reviewer.resource);
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);
});

test('saved answer-only initialization is not upgraded by the new public main recipe',async()=>{
  const f=await fixture({profile:answerOnly}),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);const before=await f.snapshot();f.useCurrent();
  const reopened=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.deepEqual(reopened.profile,answerOnly);
  assert.deepEqual(await f.snapshot(),before);
  assert.equal(f.calls.configuration,1,'reopen must not add a main grant or replace its Account');
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);
});

test('missing adopted Reviewer leaves current Account available without recreating signing capability',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);f.useCurrent();
  const config=JSON.parse(await readFile(first.configurationPath,'utf8'));
  config.entries[0].outcome='deny';config.entries[0].entry_id='current-operator-restriction';
  const restricted=canonicalJson(config);await writeFile(first.configurationPath,restricted);
  const reopened=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.equal(await readFile(first.configurationPath,'utf8'),restricted);
  assert.deepEqual(reopened.profile,previous);assert.equal(f.calls.configuration,1);
  const key=join(f.root,'mock-account','reviewer.pem');await rename(key,key+'.retained');
  const before=await f.snapshot(['reviewer.pem']);
  const accountOnly=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.deepEqual(accountOnly.profile,previous);
  assert.deepEqual(accountOnly.authorization,first.authorization,'original public verification and Host identity do not require the private Reviewer');
  assert.equal(accountOnly.authorization.siteKey,'local-mock');
  assert.equal(accountOnly.reviewer,undefined);
  assert.deepEqual(accountOnly.evidenceKey.key,first.evidenceKey.key);
  assert.equal(f.calls.admitted.at(-1),restricted,'the current Deny is still admitted, not replaced');
  await accountOnly.adoptStore(f.store);
  await assert.rejects(accountOnly.assertSigningCurrent(f.store),{code:'CheckpointSignerUnavailable'});
  assert.throws(()=>accountOnly.signingOriginal(f.store,1n,100n),{code:'CheckpointSignerUnavailable'});
  assert.equal(f.calls.issues,0,'saved intent PEM must not supply a missing Reviewer');
  assert.deepEqual(await f.snapshot(['reviewer.pem']),before);
  await assert.rejects(stat(key),{code:'ENOENT'});assert.equal(f.calls.configuration,1);
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);accountOnly.evidenceKey.key.fill(0);
});

test('missing saved public verification is not invented to replace an absent Reviewer',async()=>{
  const f=await fixture({signingMetadata:false}),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);const key=join(f.root,'mock-account','reviewer.pem');await rename(key,key+'.retained');
  const before=await f.snapshot(['reviewer.pem']);
  const reopened=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.deepEqual(reopened.authorization,{accountConfig:first.configurationPath,siteKey:'local-mock'});
  assert.equal(reopened.reviewer,undefined);assert.deepEqual(await f.snapshot(['reviewer.pem']),before);
  await reopened.adoptStore(f.store);
  await assert.rejects(reopened.assertSigningCurrent(f.store),{code:'CheckpointSignerUnavailable'});
  assert.throws(()=>reopened.signingOriginal(f.store,1n,100n),{code:'CheckpointSignerUnavailable'});
  await assert.rejects(stat(key),{code:'ENOENT'});assert.equal(f.calls.configuration,1);
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);
});

test('Reviewer absence does not bypass mandatory adopted Account, Store, Host or evidence originals',async()=>{
  for(const missing of ['initialization.json','account.json','host.pem','continuation.key','../publication/store.json']) {
    const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);await f.adopt(first);
    const directory=join(f.root,'mock-account'),reviewer=join(directory,'reviewer.pem');
    await rename(reviewer,reviewer+'.retained');
    const path=join(directory,missing);await rename(path,path+'.retained');
    await assert.rejects(initializeOrdinaryMockAccount({...f.options,explicitSelection:false}),{code:'LocalMockAdoptedStateMissing'},missing);
    await assert.rejects(stat(path),{code:'ENOENT'});await assert.rejects(stat(reviewer),{code:'ENOENT'});
    assert.equal(f.calls.configuration,1);first.evidenceKey.key.fill(0);
  }
});

test('present mismatched Reviewer is not silently treated as an absent capability',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);await f.adopt(first);
  const key=join(f.root,'mock-account','reviewer.pem');await rename(key,key+'.retained');
  await writeFile(key,'not the original Reviewer',{mode:0o600,flag:'wx'});
  await assert.rejects(initializeOrdinaryMockAccount(f.options),{code:'LocalMockAdoptedStateMissing'});
  assert.equal(await readFile(key,'utf8'),'not the original Reviewer');assert.equal(f.calls.configuration,1);
  first.evidenceKey.key.fill(0);
});

test('signing currentness refuses a missing Reviewer after an originally available signer',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);await f.adopt(first);
  await first.assertSigningCurrent(f.store);
  const original=first.signingOriginal(f.store,1n,100n);
  assert.strictEqual(original.privateKey,first.reviewer.privateKey);assert.equal(f.calls.issues,1);
  const key=join(f.root,'mock-account','reviewer.pem');await rename(key,key+'.retained');
  await assert.rejects(first.assertSigningCurrent(f.store),{code:'CheckpointSignerUnavailable'});
  await assert.rejects(stat(key),{code:'ENOENT'});assert.equal(f.calls.issues,1);
  first.evidenceKey.key.fill(0);
});

test('foreign saved profile is refused without recreating its configuration',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);f.useCurrent();
  const path=join(f.root,'mock-account','initialization.json');
  const intent=JSON.parse(await readFile(path,'utf8'));intent.profile.cid='sha256:'+'f'.repeat(64);
  await writeFile(path,canonicalJson(intent));
  const before=await f.snapshot();
  await assert.rejects(initializeOrdinaryMockAccount(f.options),{code:'LocalMockInstallationChanged'});
  assert.deepEqual(await f.snapshot(),before);assert.equal(f.calls.configuration,1);
  first.evidenceKey.key.fill(0);
});

test('diagnostic-only Mock observer retains bootstrap and all 129 original Task subjects',async()=>{
  const f=await fixture(),events=[];
  const observe=(...event)=>events.push(event);
  const modelTasks=Array.from({length:129},(_,index)=>'sha256:'+index.toString(16).padStart(64,'0'));
  const first=await initializeOrdinaryMockAccount({...f.options,modelTasks,operatorAuthorization:{observe}});
  assert.notEqual(first,undefined,'An observer is not an authored Account selection');
  assert.strictEqual(f.calls.modelTasks,modelTasks,'Forward the same complete Task inventory to Common');
  assert.equal(f.calls.configuration,1);
  assert.equal(first.authorization.accountConfig,first.configurationPath);
  assert.strictEqual(first.authorization.observe,observe);
  assert.deepEqual(events,[],'The diagnostic observer neither constructs nor approves authority');
  await f.adopt(first);
  const before=await f.snapshot();
  const account=JSON.parse(await readFile(first.configurationPath,'utf8'));
  account.entries[0].outcome='deny';account.entries[0].entry_id='current-observer-restriction';
  const restricted=canonicalJson(account);await writeFile(first.configurationPath,restricted);
  const reopened=await initializeOrdinaryMockAccount({...f.options,modelTasks,explicitSelection:false,
    operatorAuthorization:{observe}});
  assert.strictEqual(reopened.authorization.observe,observe);
  assert.equal(f.calls.configuration,1,'The observer cannot reissue adopted grants');
  assert.equal(f.calls.admitted.at(-1),restricted,'Current Deny remains the admitted original');
  const after=await f.snapshot();
  for(const original of before.filter(item=>item.name!=='account.json')) {
    assert.deepEqual(after.find(item=>item.name===original.name),original);
  }
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);
});

test('diagnostic exception does not bootstrap explicit or unrecognized authorization selections',async()=>{
  const observe=()=>{},symbol=Symbol('unknown');
  for(const operatorAuthorization of [null,{}, {accountConfig:'/not-opened',observe},
    {accountConfiguration:'explicit current Deny',observe},{decide(){},observe},
    {hostKey:{},observe},{unknown:true,observe},{observe:undefined},{observe:null},
    {observe:'not-a-function'},{observe,[symbol]:true},Object.create({observe}),
    Object.assign(Object.create({accountConfig:'/not-opened'}),{observe})]) {
    const f=await fixture();
    const result=await initializeOrdinaryMockAccount({...f.options,operatorAuthorization});
    assert.equal(result,undefined);
    assert.equal(f.calls.configuration,0);
    await assert.rejects(stat(join(f.root,'mock-account')),{code:'ENOENT'});
  }
  let reads=0;
  const f=await fixture(),operatorAuthorization=Object.defineProperty({},'observe',{
    enumerable:true,get(){reads++;return observe;}});
  assert.equal(await initializeOrdinaryMockAccount({...f.options,operatorAuthorization}),undefined);
  assert.equal(reads,0,'A getter cannot select the data-only diagnostic exception');
});

function funded(f) {
  const reads=new Set();let next=0;
  f.moon.clientProgramAccountReadControlBytes=()=>64n;
  f.moon.clientProgramPrepareAccountReadConstruction=(read,r,e)=>{
    assert(reads.has(read));assert(r>=64n&&e>=r);return {$tag:1,_0:undefined};
  };
  f.moon.clientProgramCompleteAccountReadConstruction=()=>({$tag:1,_0:undefined});
  f.moon.clientProgramCloseAccountRead=read=>{reads.delete(read);return {$tag:1,_0:true};};
  f.moon.clientProgramLocalMockAccountInventoryPrepared=(...args)=>{
    assert.equal(args.at(-1)(0n,128n),true);return {$tag:1,_0:undefined};
  };
  f.moon.clientProgramLocalMockAccountBeforeSigningPrepared=(...args)=>args.at(-1)(0n,128n);
  f.moon.clientProgramLocalMockAccountConfigurationPrepared=(...args)=>{
    assert.equal(args.at(-1)(128n,256n),true);
    return f.moon.clientProgramLocalMockAccountConfiguration(...args.slice(0,6));
  };
  return createAccountConstruction({moon:f.moon,current(){},prepareRead(){
    const read={id:++next};reads.add(read);return {$tag:1,_0:read};
  }});
}

test('Common-selected control original reaches request, Account, durable intent and current reopen',async()=>{
  const f=await fixture({profile:named}),construction=funded(f),calls=[];
  const source=['local-mock','actual-source'],selected='actql-local-control-0';
  f.moon.clientProgramLocalMockAccountControlConnectionPrepared=function(preferred,profile,original,sources,targets,prepare){
    assert.strictEqual(this,f.moon);calls.push({preferred,profile,original});
    assert.deepEqual(sources,[{_0:source[0],_1:source[1]}]);assert.deepEqual(targets,[]);
    assert.equal(prepare(128n,256n),true);return {$tag:1,_0:selected};
  };
  const inventory=f.moon.clientProgramLocalMockAccountInventoryPrepared;
  f.moon.clientProgramLocalMockAccountInventoryPrepared=(connection,sources,tasks,request,...rest)=>{
    assert.equal(connection,selected);assert.deepEqual(request,{_0:selected,_1:'original-realization'});
    return inventory(connection,sources,tasks,request,...rest);
  };
  const options={...f.options,sources:[source],requestTarget:['local-mock','original-realization'],accountConstruction:construction};
  const first=await initializeOrdinaryMockAccount(options);await f.adopt(first);
  assert.equal(first.authorization.siteKey,selected);
  const saved=JSON.parse(await readFile(join(f.root,'mock-account/initialization.json'),'utf8'));
  assert.equal(saved.controlConnection,selected);const before=await f.snapshot();
  const next=await initializeOrdinaryMockAccount({...options,explicitSelection:false});
  assert.equal(next.authorization.siteKey,selected);assert.deepEqual(await f.snapshot(),before);
  assert.deepEqual(calls,[{preferred:'local-mock',profile:undefined,original:undefined},
    {preferred:selected,profile:{_0:named.id,_1:named.version,_2:named.cid},original:selected}]);
  assert.equal(f.calls.configuration,1);first.evidenceKey.key.fill(0);next.evidenceKey.key.fill(0);
  assert.equal(await construction.close(),true);
});

test('Common control refusal preserves original failure and cannot materialize an Account',async()=>{
  const f=await fixture({profile:named}),construction=funded(f),original=Object.freeze({kind:'original Common refusal'});
  f.moon.clientProgramLocalMockAccountControlConnectionPrepared=()=>({$tag:0,_0:original});
  await assert.rejects(initializeOrdinaryMockAccount({...f.options,accountConstruction:construction}),
    cause=>cause.code==='MoonBitHostFailure'&&cause.cause===original);
  assert.equal(f.calls.configuration,0);await assert.rejects(stat(join(f.root,'mock-account')),{code:'ENOENT'});
  assert.equal(await construction.close(),true);
});
