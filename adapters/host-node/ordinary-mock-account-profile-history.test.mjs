import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,mkdir,readFile,writeFile,rename,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import {canonicalJson} from './local-account-config.mjs';

const previous=Object.freeze({id:'actql-local-mock',version:'0.1',
  cid:'sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a'});
const current=Object.freeze({...previous,
  cid:'sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f'});

// Real exclusive filesystem/key initialization, with explicit Common and Store
// ports. These doubles issue no actual Account, Run, Result or Store authority;
// the Common policy/evaluator is tested in its own actual Owner cases.
async function fixture() {
  const root=await mkdtemp(join(process.env.ACTQL_TEST_STATE_SCRATCH??tmpdir(),'actql-mock-profile-history-'));
  const calls={configuration:0,known:[]};let selected=previous;
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
    executionAuthorizationAdmit(wire){assert.equal(typeof JSON.parse(wire).account_id,'string');},
  };
  const options={moon,root,principal:'local-test',subject:{projectDirectory:root,backend:'original-test'},
    sources:[],modelTasks:[],explicitSelection:true,assertExclusiveCurrent(){}};
  const store=Object.freeze({status(){return {closed:false};}});
  async function adopt(binding){await mkdir(join(root,'publication'));
    await writeFile(join(root,'publication','store.json'),'explicit Store original fixture',{mode:0o600,flag:'wx'});
    await binding.adoptStore(store);
  }
  const originals=['initialization.json','adopted.json','account.json','reviewer.pem','host.pem','continuation.key'];
  const snapshot=async()=>Promise.all(originals.map(async name=>({name,bytes:await readFile(join(root,'mock-account',name)),mode:(await stat(join(root,'mock-account',name))).mode&0o777})));
  return {root,moon,options,calls,adopt,snapshot,useCurrent(){selected=current;}};
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

test('known predecessor does not bypass current Deny or recreate a missing adopted key',async()=>{
  const f=await fixture(),first=await initializeOrdinaryMockAccount(f.options);
  await f.adopt(first);f.useCurrent();
  const config=JSON.parse(await readFile(first.configurationPath,'utf8'));
  config.entries[0].outcome='deny';config.entries[0].entry_id='current-operator-restriction';
  const restricted=canonicalJson(config);await writeFile(first.configurationPath,restricted);
  const reopened=await initializeOrdinaryMockAccount({...f.options,explicitSelection:false});
  assert.equal(await readFile(first.configurationPath,'utf8'),restricted);
  assert.deepEqual(reopened.profile,previous);assert.equal(f.calls.configuration,1);
  const key=join(f.root,'mock-account','reviewer.pem');await rename(key,key+'.retained');
  await assert.rejects(initializeOrdinaryMockAccount(f.options),{code:'LocalMockAdoptedStateMissing'});
  await assert.rejects(stat(key),{code:'ENOENT'});assert.equal(f.calls.configuration,1);
  first.evidenceKey.key.fill(0);reopened.evidenceKey.key.fill(0);
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
