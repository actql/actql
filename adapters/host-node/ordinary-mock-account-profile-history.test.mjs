import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,mkdir,readFile,writeFile,rename,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import {canonicalJson,contentCid} from './local-account-config.mjs';

const previous=Object.freeze({id:'actql-local-mock',version:'0.1',
  cid:'sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a'});
const current=Object.freeze({...previous,
  cid:'sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f'});

// Real exclusive filesystem/key initialization, with explicit Common and Store
// ports. These doubles issue no actual Account, Run, Result or Store authority;
// the Common policy/evaluator is tested in its own actual Owner cases.
async function fixture({signingMetadata=true}={}) {
  const root=await mkdtemp(join(process.env.ACTQL_TEST_STATE_SCRATCH??tmpdir(),'actql-mock-profile-history-'));
  const calls={configuration:0,known:[],admitted:[],issues:0};let selected=previous;
  const moon={
    clientProgramLocalMockAccountProfile(){return {_0:selected.id,_1:selected.version,_2:selected.cid,_3:'fixture policy'};},
    clientProgramLocalMockAccountProfileKnown(id,version,cid){
      assert.strictEqual(this,moon);calls.known.push([id,version,cid]);
      return [previous,current].some(p=>p.id===id&&p.version===version&&p.cid===cid);
    },
    clientProgramLocalMockAccountConfiguration(accountId,principal,connection){
      calls.configuration++;
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
