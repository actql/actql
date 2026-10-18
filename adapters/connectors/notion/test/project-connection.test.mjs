import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,writeFile,rm,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledProjectConfiguration} from '../../../host-node/installed-project-configuration.mjs';
import {loadInstalledNotionProjectConnection as load} from '../host/project-connection.mjs';

const limits=Object.freeze({maxConnections:8,maxSelectionWork:10000,maxDatabases:8,maxCredentialReferenceBytes:512,
  maxBytes:16384,maxNodes:2048,maxDepth:24,maxDataSources:8,maxProperties:8,maxIdentityBytes:128,maxNameBytes:128,
  maxContractNodes:256,maxContractDepth:16,maxContractTextBytes:4096,maxColumns:16,maxWork:100000});
const sha=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');
const credentials='"credentials":{"integration_token":{"path":"./must-not-be-read"}}';
const entry=' {"connector":"notion","databases":{"tasks":{ "id":"db", "marker":"actql_request" }},'+credentials+'}';
async function fixture(t,wire,{selected=true,moon=common}={}){
  const directory=await mkdtemp(join(tmpdir(),'actql-notion-project-connection-'));
  t.after(()=>rm(directory,{recursive:true}));
  await writeFile(join(directory,'actql.config.json'),selected?
    '{"version":"actql-config/0.1","connectors":"./connections.json"}':'{"version":"actql-config/0.1"}');
  const path=join(directory,'connections.json');
  if(wire!==undefined)await writeFile(path,wire);
  const project=await loadInstalledProjectConfiguration(moon,{directory});
  return{project,path};
}
const envelope=connections=>' \r\n{"version":"actql-connectors/0.1","connections":'+connections+'}\r\n';

test('actual Project file feeds the exact selected Notion entry and separate original declarations without secret I/O',async t=>{
  const name='café😀',wire=envelope('{"other":{"connector":"slack"},"'+name+'":'+entry+'}');
  const f=await fixture(t,wire);let opens=0,closes=0;
  const options={limits,assertCurrent(){assert.equal(this,options);},async openFile(path,flags){
    assert.equal(this,options);assert.equal(path,f.path);opens++;
    const handle=await open(path,flags);
    return{read:(...args)=>handle.read(...args),async close(){closes++;await handle.close();}};
  }};
  const view=await load(common,provider,f.project,name,options),original=view.originalsForRuntime(common,provider);
  assert.equal(opens,1);assert.equal(closes,1);
  assert.strictEqual(original.project,f.project);
  assert.strictEqual(original.projectConnections.project,f.project.originalsForRuntime(common));
  assert.equal(original.projectConnections.wire,wire);assert.equal(original.wire,entry.trimStart());
  assert.equal(original.name,name);assert.equal(original.index,1);
  const connection=original.connection;
  assert.equal(checked(provider.notionPublicConnectionCredentialKind(connection)),'path');
  assert.equal(checked(provider.notionPublicConnectionCredentialReference(connection)),'./must-not-be-read');
  assert.equal(checked(provider.notionPublicConnectionOriginalJson(connection,16384)),original.wire);
  assert.equal(checked(provider.notionPublicConnectionSourceCid(connection)),sha(original.wire));
  const map=checked(provider.notionPublicConnectionDatabases(connection));
  assert.equal(checked(provider.notionDatabaseReadDeclarationsAliasAt(map,0)),'tasks');
  const declaration=checked(provider.notionDatabaseReadDeclarationsAt(map,0));
  assert.equal(checked(provider.notionDatabaseReadDeclarationOriginalJson(declaration,16384)),'{ "id":"db", "marker":"actql_request" }');
  assert.equal(provider.notionDatabaseReadDeclarationsMatches(map,0,declaration),true);
  assert.ok(Object.isFrozen(view)&&Object.isFrozen(original));
});

test('Project selection uses exact Unicode names and a finite fail-closed inventory budget',async t=>{
  const f=await fixture(t,envelope('{"é":'+entry+',"é":'+entry+'}'));
  const work=1+'é'.length+(1+'é'.length)+(1+'é'.length);
  const view=await load(common,provider,f.project,'é',{limits:{...limits,maxSelectionWork:work,maxConnections:2},assertCurrent(){}});
  assert.equal(view.originalsForRuntime(common,provider).index,1);
  await assert.rejects(load(common,provider,f.project,'é',{limits:{...limits,maxSelectionWork:work-1},assertCurrent(){}}),
    {code:'NotionProjectConnectionSelectionLimit'});
  await assert.rejects(load(common,provider,f.project,'é',{limits:{...limits,maxConnections:1},assertCurrent(){}}),
    {code:'NotionProjectConnectionSelectionLimit'});
  await assert.rejects(load(common,provider,f.project,'missing',{limits,assertCurrent(){}}),{code:'NotionProjectConnectionUnavailable'});
});

test('absent empty foreign-Connector and invalid selected entries never fall back to another connection',async t=>{
  const absent=await fixture(t,undefined,{selected:false});
  await assert.rejects(load(common,provider,absent.project,'n',{limits,assertCurrent(){},openFile(){assert.fail('No unselected read');}}),
    {code:'NotionProjectConnectionUnavailable'});
  for(const connections of['{}','{"n":{"connector":"slack"}}','{"n":{"connector":"notion",'+credentials+',"unknown":true}}',
    '{"n":{"connector":"notion","databases":{"tasks":"db","unused":{"id":"db2","marker":null}},'+credentials+'}}']){
    const f=await fixture(t,envelope(connections));
    await assert.rejects(load(common,provider,f.project,'n',{limits,assertCurrent(){}}));
  }
});

test('currentness loss after original file close prevents Connector admission and a second read',async t=>{
  const f=await fixture(t,envelope('{"n":'+entry+'}'));let current=true,opens=0,admissions=0;
  const failure=new Error('Original installation replaced');
  const actualProvider={...provider,notionReadPublicConnection(...args){admissions++;return provider.notionReadPublicConnection(...args);}};
  await assert.rejects(load(common,actualProvider,f.project,'n',{limits,assertCurrent(){if(!current)throw failure;},
    async openFile(path,flags){opens++;const handle=await open(path,flags);return{read:(...args)=>handle.read(...args),
      async close(){await handle.close();current=false;}};}}),error=>error===failure);
  assert.equal(opens,1);assert.equal(admissions,0);
});

test('original callbacks and receivers survive awaits while copied views runtimes and projects refuse',async t=>{
  const runtime={...common},actualProvider={...provider};let reads=0;
  actualProvider.notionReadPublicConnection=function(...args){assert.equal(this,actualProvider);reads++;return provider.notionReadPublicConnection(...args);};
  const f=await fixture(t,envelope('{"n":'+entry+'}'),{moon:runtime});
  const options={limits,assertCurrent(){assert.equal(this,options);},async openFile(path,flags){
    assert.equal(this,options);
    runtime.clientProjectConnectionsEntryOriginalJson=()=>assert.fail('Replacement Common callback');
    actualProvider.notionReadPublicConnection=()=>assert.fail('Replacement Connector callback');
    options.assertCurrent=()=>assert.fail('Replacement current callback');
    return open(path,flags);
  }};
  const view=await load(runtime,actualProvider,f.project,'n',options);
  const original=view.originalsForRuntime(runtime,actualProvider);assert.equal(reads,1);
  assert.throws(()=>view.originalsForRuntime({...runtime},actualProvider),{code:'ForeignNotionProjectConnectionRuntime'});
  assert.throws(()=>view.originalsForRuntime(runtime,{...actualProvider}),{code:'ForeignNotionProjectConnectionRuntime'});
  for(const copy of[{...view},Object.create(view)])assert.throws(()=>copy.originalsForRuntime(runtime,actualProvider),{code:'ForeignNotionProjectConnection'});
  await assert.rejects(load(runtime,provider,{...f.project},'n',{limits,assertCurrent(){}}),{code:'ForeignInstalledProjectOriginal'});
  assert.equal(checked(provider.notionPublicConnectionCredentialKind(original.connection)),'path');
});

test('view current failures remain terminal and DATA retirement does not invalidate escaped DATA or attest physical cleanup',async t=>{
  const f=await fixture(t,envelope('{"n":'+entry+'}'));let active=true;
  const failure=new Error('Original current fence failed');
  const view=await load(common,provider,f.project,'n',{limits,assertCurrent(){if(!active)throw failure;}});
  const original=view.originalsForRuntime(common,provider);active=false;
  assert.throws(()=>view.originalsForRuntime(common,provider),error=>error===failure);
  active=true;assert.throws(()=>view.originalsForRuntime(common,provider),error=>error===failure);
  assert.throws(()=>({...view}).retire(),{code:'ForeignNotionProjectConnection'});
  view.retire();assert.throws(()=>view.originalsForRuntime(common,provider),{code:'NotionProjectConnectionRetired'});
  assert.equal(checked(provider.notionPublicConnectionCredentialReference(original.connection)),'./must-not-be-read');
});

test('pending original FD custody propagates unchanged and only its close is retried',async t=>{
  const f=await fixture(t,envelope('{"n":'+entry+'}'));let opens=0,closes=0,pending,handle,admissions=0;
  t.after(async()=>{if(pending?.status().pending)await pending.retry();else if(handle&&handle.fd!==-1)await handle.close();});
  const actualProvider={...provider,notionReadPublicConnection(...args){admissions++;return provider.notionReadPublicConnection(...args);}};
  await assert.rejects(load(common,actualProvider,f.project,'n',{limits,assertCurrent(){},async openFile(path,flags){
    opens++;handle=await open(path,flags);return{read:(...args)=>handle.read(...args),async close(){closes++;if(closes===1)return false;await handle.close();}};
  }}),error=>{assert.equal(error.cleanupPending,true);pending=error.cleanupHandle;return true;});
  assert.equal(opens,1);assert.equal(closes,1);assert.equal(admissions,0);
  assert.equal((await pending.retry()).pending,false);
  assert.equal(opens,1);assert.equal(closes,2);assert.equal(admissions,0);
  await assert.rejects(handle.stat(),{code:'EBADF'});
});

test('known connection-name selection-work exhaustion refuses before opening the original connections file',async t=>{
  const f=await fixture(t,envelope('{"n":'+entry+'}'));let opens=0;
  await assert.rejects(load(common,provider,f.project,'unavailable-name',{
    limits:{...limits,maxSelectionWork:2},assertCurrent(){},
    async openFile(...args){opens++;return open(...args);},
  }),{code:'NotionProjectConnectionSelectionLimit'});
  assert.equal(opens,0);
});
