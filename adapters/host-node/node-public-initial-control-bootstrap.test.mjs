import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,cpSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

// Real ordinary Node module loading, same-FD captured images and the private
// installation Owner. The small Host below is explicit, not the full product
// Host or a normal installed README success, business supplier or permission.
function fixture(t,{inventory=true,changeImage=false,publicNode=false,actualFacade=false,source=false,managedRun=false,oversizeRun=false}={}) {
  const directory=mkdtempSync(join(tmpdir(),'actql-ordinary-control-'));
  t.after(()=>rmSync(directory,{recursive:true}));
  const root=join(directory,'node_modules/@actql/local-node');
  const sourcePath=join(directory,'mock-original.json');
  if(source)writeFileSync(sourcePath,'{"original":"same-file"}\n');
  const sources=new Map();
  sources.set('package.json',Buffer.from(JSON.stringify({name:'@actql/local-node',version:'1.0.0',
    type:'module',exports:{'.':'./index.mjs',
      './_internal/initial-control-public-dispatch':'./initial-control-public-dispatch.cjs'}})));
  sources.set('index.mjs',Buffer.from('import delivery from "./initial-control-public-dispatch.cjs";'+
    'export function connect(raw){return delivery.selectedInitialControlHostPreparation("connect",raw);}'));
  sources.set('spec/local-check-environment.json',Buffer.from('{"original":"ordinary-asset"}\n'));
  sources.set('initial-control-public-dispatch.cjs',readFileSync(new URL('../../packages/local-node/initial-control-public-dispatch.cjs',import.meta.url)));
  for(const name of ['node-public-initial-control-bootstrap.cjs','host-journal-native-image.cjs','host-journal-directory.mjs','initial-control-installation-owner.cjs',
    'initial-control-phase-envelope.cjs','source-managed-phase-envelope.cjs','initial-control-package-custody.cjs','initial-control-image-source.cjs',
    'initial-control-image-loader.cjs','node-initial-control-installation.mjs','initial-control-host-input.mjs',
    'source-managed-original-input.mjs','host-journal-facility-fields.cjs',
    'host-journal-service-recipe.cjs','host-journal-schema-support.cjs',
    'host-result-service-recipe.cjs','host-local-mock-model-service-recipe.cjs',
    'ordinary-host-control.mjs','installed-host-policy.mjs','local-account-config.mjs','authorization.mjs']) {
    sources.set('adapters/host-node/'+name,readFileSync(new URL('./'+name,import.meta.url)));
  }
  for (const path of ['adapters/host-common/authorization-gate.mjs',
    'spec/contracts/actql-capacity-host-policy.json','spec/contracts/actql-check-environment.json']) {
    sources.set(path,readFileSync(new URL('../../'+path,import.meta.url)));
  }
  sources.set('adapters/host-node/embedded-local.mjs',Buffer.from(
    'import{beginInitialControlInstallation,readInitialControlInstallationInput,readInitialControlInstallationAsset}from"./node-initial-control-installation.mjs";'+
    'export{snapshotInitialControlHostInput as readInitialControlHostInput}from"./initial-control-host-input.mjs";'+
    (source?'export{readSourceManagedOriginalInput}from"./source-managed-original-input.mjs";'+
    'const declarations=Object.freeze([Object.freeze({}),Object.freeze({})]);let request,derived;'+
    'export function assertSourceManagedHostPreparation(held){assertInitialControlHostPreparation(held);}'+
    'export async function prepareInstalledMockSourcePreparation(held,original){assertInitialControlHostPreparation(held);}'+
    'export function readInstalledMockPreparation(held){assertInitialControlHostPreparation(held);return Object.freeze({dataPath:'+JSON.stringify(sourcePath)+',sources:Object.freeze(declarations.map(declaration=>Object.freeze({declaration})))});}'+
    'export function originalSourceManagedHostRequest(held,value){assertInitialControlHostPreparation(held);if(value!==derived)throw new Error("ForeignRequestFixture");return request;}'+
    'export function sourceManagedSubmittedIntentCid(held,original,body){assertInitialControlHostPreparation(held);return "sha256:"+"a".repeat(64);}'+
    (managedRun?'export function readSourceManagedRunRequirements(held,value){assertInitialControlHostPreparation(held);if(value!==derived)throw new Error("ForeignPreparedFixture");return Object.freeze({planningWork:100000,attempts:3,holdings:3,transferBytes:10000000n,retainedBytes:252808192n,executionBytes:'+(oversizeRun?'536870913n':'536870912n')+'});}':''):'')+
    'let originals;export function assertInitialControlHostPreparation(held){'+
    'if(!originals||["host","installation","generation","supplier","moduleLifetime"].some(name=>held[name]!==originals[name]))throw new Error("ForeignHostFixture");}'+
    'export async function connectInitialControlHostPreparation(kind,raw){'+
    'originals=Object.freeze({host:{},installation:{},generation:{},supplier:connectInitialControlHostPreparation,moduleLifetime:import.meta});'+
    'const scope=await beginInitialControlInstallation(originals,raw);'+
    'return Object.freeze({input:readInitialControlInstallationInput(scope,originals),'+
    'asset:readInitialControlInstallationAsset(scope,originals,"spec/local-check-environment.json"),scope'+
    (source?',originals,declarations,bindFixtureRequest(value,alias){request=value;derived=alias;}':'')+'});}'));
  const engine={node:process.versions.node,v8:process.versions.v8,openssl:process.versions.openssl,
    platform:process.platform,arch:process.arch,libraries:{...process.versions}};
  const facts=[...sources].map(([path,bytes])=>({path,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}));
  const selected={engine:{...engine,eager:true},ordinaryEngine:{...engine,eager:false},images:facts,
    packages:[],dependencies:[],localVersion:'1.0.0',optionalSdk:null,optionalSdkCoverage:'absent',
    publicNode:null,publicNodeCoverage:'absent',localPublicModule:'index.mjs',
    hostModule:'adapters/host-node/embedded-local.mjs',hostValidator:'assertInitialControlHostPreparation'};
  if(publicNode){
    const node=join(directory,'node_modules/@actql/node');
    const nodeSources=new Map([
      ['package.json',Buffer.from(JSON.stringify({name:'@actql/node',version:'1.0.0',type:'module',exports:'./index.mjs'}))],
      ['index.mjs',actualFacade?readFileSync(new URL('../../packages/node/index.mjs',import.meta.url)):sources.get('index.mjs')],
      ['initial-control-public-dispatch.cjs',readFileSync(new URL('../../packages/node/initial-control-public-dispatch.cjs',import.meta.url))]
    ]);
    for(const[path,bytes]of nodeSources){mkdirSync(dirname(join(node,path)),{recursive:true});writeFileSync(join(node,path),bytes);}
    selected.publicNode={name:'@actql/node',version:'1.0.0',dependencies:[{name:'@actql/local-node',local:true}],
      images:[...nodeSources].map(([path,bytes])=>({path,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}))};
    selected.publicNodeCoverage='prepared';
    if(actualFacade){
      // Exact source-checkout facade/SDK/Wire product copies; no prepack,
      // Common runtime, physical Host or operational supplier is issued.
      for(const name of ['sdk','client-wire']){
        const source=new URL('../../packages/'+name+'/',import.meta.url);
        const target=join(directory,'node_modules/@actql',name);
        mkdirSync(target,{recursive:true});
        const manifest=JSON.parse(readFileSync(new URL('package.json',source),'utf8'));
        for(const path of ['package.json',...manifest.files]){
          const original=new URL(path,source);
          if(existsSync(original))cpSync(original,join(target,path),{recursive:true});
        }
      }
    }
  }
  sources.set('adapters/host-node/initial-control-package-original.cjs',Buffer.from(
    'module.exports=Object.freeze({imageInventory:'+(inventory?JSON.stringify(selected):'undefined')+'});'));
  for(const [path,bytes]of sources){mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),bytes);}
  if(changeImage)writeFileSync(join(root,'spec/local-check-environment.json'),'changed');
  return {directory,root,sourcePath,run(body){
    const entry=join(directory,'entry.mjs');writeFileSync(entry,body);
    const result=spawnSync(process.execPath,[entry],{cwd:directory,env:{PATH:process.env.PATH},encoding:'utf8',timeout:30000});
    assert.equal(result.error,undefined);return result;
  }};
}

test('ordinary unselected public imports preserve original process loader registration',t=>{
  for(const publicNode of [false,true]){
    const f=fixture(t,{publicNode});const result=f.run(
      'import assert from"node:assert/strict";import Module from"node:module";'+
      'const names=["registerHooks","register"],before=names.map(name=>Object.getOwnPropertyDescriptor(Module,name));'+
      'await import('+JSON.stringify(publicNode?'@actql/node':'@actql/local-node')+');'+
      'for(let i=0;i<names.length;i++)assert.deepEqual(Object.getOwnPropertyDescriptor(Module,names[i]),before[i]);'+
      'assert.equal(Module.createRequire(import.meta.url).cache['+
      JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+'],undefined);');
    assert.equal(result.status,0,result.stderr);
  }
});

test('ordinary Remote and connected Local leave the Local bootstrap unselected',t=>{
  const f=fixture(t,{publicNode:true});const result=f.run(
    'import assert from"node:assert/strict";import Module from"node:module";'+
    'const names=["registerHooks","register"],before=names.map(name=>Object.getOwnPropertyDescriptor(Module,name));'+
    'const{connect}=await import("@actql/node");let observed=0;'+
    'for(const raw of [{mode:"remote",get installation(){observed++;throw Error("Unselected");}},'+
    '{mode:"local",endpoint:"https://host.example/",get profile(){observed++;throw Error("Unselected");}}])assert.equal(connect(raw),undefined);'+
    'assert.equal(observed,0);'+
    'for(let i=0;i<names.length;i++)assert.deepEqual(Object.getOwnPropertyDescriptor(Module,names[i]),before[i]);'+
    'assert.equal(Module.createRequire(import.meta.url).cache['+
    JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+'],undefined);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary selected Local still captures loader custody before original input',t=>{
  const f=fixture(t,{publicNode:true});const result=f.run(
    'import assert from"node:assert/strict";import Module from"node:module";'+
    'const before=Object.getOwnPropertyDescriptor(Module,"registerHooks");'+
    'const{connect}=await import("@actql/node");'+
    'assert.deepEqual(Object.getOwnPropertyDescriptor(Module,"registerHooks"),before);'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const after=Object.getOwnPropertyDescriptor(Module,"registerHooks");'+
    'assert.notStrictEqual(after.value,before.value);assert.equal(after.writable,false);assert.equal(after.configurable,false);'+
    'assert.equal(client.input.profile,"mock");assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('actual public facade and SDK Remote dispatch do not acquire the Local loader',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true,inventory:false});const result=f.run(
    'import assert from"node:assert/strict";import Module from"node:module";'+
    'const names=["registerHooks","register"],before=names.map(name=>Object.getOwnPropertyDescriptor(Module,name));'+
    'const facade=await import("@actql/node"),require=Module.createRequire(import.meta.url);'+
    'assert.equal(require.cache[require.resolve("@actql/sdk")],undefined);'+
    'let calls=0;const originalFetch=globalThis.fetch;'+
    'globalThis.fetch=async()=>{calls++;throw Error("ControlledTransportStop");};'+
    'try{for(const mode of ["remote","local"])await assert.rejects(facade.connect({mode,...(mode==="local"?{owner:"local"}:{}),endpoint:"https://host.example/",token:()=>"fixture-only"}),{code:"ClientTransportUnknown"});}'+
    'finally{globalThis.fetch=originalFetch;}'+
    'assert.equal(calls,2);'+
    'const sdk=await import("@actql/sdk");'+
    'assert.strictEqual(facade.ClientError,sdk.ClientError);assert.strictEqual(facade.RequestHeld,sdk.RequestHeld);'+
    'for(let i=0;i<names.length;i++)assert.deepEqual(Object.getOwnPropertyDescriptor(Module,names[i]),before[i]);'+
    'assert.equal(Module.createRequire(import.meta.url).cache['+
    JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+'],undefined);');
  assert.equal(result.status,0,result.stderr);
});

test('actual public facade retains tiny SDK class originals before selected Local refusal',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true,inventory:false});const result=f.run(
    'import assert from"node:assert/strict";import Module from"node:module";'+
    'const facade=await import("@actql/node"),errors=await import("@actql/sdk/_internal/client-errors");'+
    'assert.strictEqual(facade.ClientError,errors.ClientError);assert.strictEqual(facade.RequestHeld,errors.RequestHeld);'+
    'const held=Object.freeze({requestId:"original"}),lookup=Object.freeze({original:true});'+
    'const error=new facade.RequestHeld(held,lookup);assert.ok(error instanceof facade.ClientError);'+
    'assert.strictEqual(error.held,held);assert.strictEqual(error.lookupContext,lookup);assert.equal(error.requestId,"original");'+
    'const require=Module.createRequire(import.meta.url),sdkPath=require.resolve("@actql/sdk");'+
    'assert.equal(require.cache[sdkPath],undefined);let read=0;'+
    'await assert.rejects(facade.connect({mode:"local",get profile(){read++;throw Error("TooEarly");}}),'+
    '{code:"NodeInitialControlAdmissionUnavailable"});'+
    'assert.equal(read,0);assert.equal(require.cache[sdkPath],undefined);');
  assert.equal(result.status,0,result.stderr);
});

test('SDK class delivery exports only the original two classes without the execution graph',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true,inventory:false});const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";'+
    'const require=createRequire(import.meta.url),entry=await import("@actql/sdk/_internal/client-errors");'+
    'assert.deepEqual(Object.keys(entry).sort(),["ClientError","RequestHeld"]);'+
    'assert.equal(require.cache[require.resolve("@actql/sdk")],undefined);'+
    'const sdk=await import("@actql/sdk"),facade=await import("@actql/node");'+
    'for(const name of ["ClientError","RequestHeld"]){assert.strictEqual(entry[name],sdk[name]);assert.strictEqual(entry[name],facade[name]);}');
  assert.equal(result.status,0,result.stderr);
});

test('SDK class delivery cannot brand a borrowed options exception as SDK-owned',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true,inventory:false});const result=f.run(
    'import assert from"node:assert/strict";import*as entry from"@actql/sdk/_internal/client-errors";'+
    'import{connect}from"@actql/sdk";const borrowed=new Error("SourceOnlyBorrowedError");'+
    'if(typeof entry.markOwnedFailure==="function")entry.markOwnedFailure(borrowed,"BorrowedClaim");'+
    'let reads=0;const options={get mode(){reads++;throw borrowed;}};'+
    'await assert.rejects(connect(options),error=>{assert.notStrictEqual(error,borrowed);'+
    'assert.equal(error.code,"InvalidConnectionOptions");assert.ok(error instanceof entry.ClientError);return true;});'+
    'assert.equal(reads,1);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary selected bootstrap failure cannot reexecute a discarded partial module',t=>{
  for(const publicNode of [false,true]){
    const f=fixture(t,{publicNode});
    // Explicit throwing module fixture models Node dropping a failed require
    // from its cache. It is not an operational admission or cleanup ACK.
    writeFileSync(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'),
      'globalThis.bootstrapAttempts++;throw globalThis.bootstrapFailure;');
    const result=f.run('import assert from"node:assert/strict";'+
      'globalThis.bootstrapAttempts=0;globalThis.bootstrapFailure=Object.freeze({original:"failed-module"});'+
      'const{connect}=await import('+JSON.stringify(publicNode?'@actql/node':'@actql/local-node')+');'+
      'for(let i=0;i<2;i++)assert.throws(()=>connect({mode:"local"}),error=>error===globalThis.bootstrapFailure);'+
      'assert.equal(globalThis.bootstrapAttempts,1);assert.equal(connect({mode:"remote"}),undefined);');
    assert.equal(result.status,0,result.stderr);
  }
});

test('ordinary import acquires its installed prefix before original bounded input and never refills a generation',t=>{
  const f=fixture(t);const result=f.run(
    'import assert from"node:assert/strict";import{connect}from"@actql/local-node";'+
    'const raw={mode:"local",installation:{directory:".actql"},profile:"mock"};'+
    'const pending=connect(raw);raw.profile="changed";raw.installation.directory="changed";'+
    'const client=await pending;assert.equal(client.input.profile,"mock");assert.equal(client.input.installation.directory,".actql");'+
    'assert.equal(client.asset,\'{"original":"ordinary-asset"}\\n\');'+
    'assert.equal((await client.scope.close()).pending,false);'+
    'assert.equal(connect({mode:"remote"}),undefined);'+
    'assert.equal(connect({mode:"local",owner:"local",endpoint:"https://host.example/"}),undefined);'+
    'assert.throws(()=>connect({mode:"local",installation:{directory:".actql"},profile:"mock"}),{code:"NodeInitialControlInputUnavailable"});');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary source-only absence refuses before dependent packet traversal',t=>{
  const f=fixture(t,{inventory:false});const result=f.run(
    'import assert from"node:assert/strict";import{connect}from"@actql/local-node";'+
    'let seen=0;const raw={mode:"local",installation:new Proxy({},{get(){seen++;},ownKeys(){seen++;}}),get profile(){seen++;}};'+
    'assert.throws(()=>connect(raw),{code:"NodeInitialControlAdmissionUnavailable"});assert.equal(seen,0);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary public Node delivery binds its own captured facade and the same Local installation',t=>{
  const f=fixture(t,{publicNode:true});const result=f.run(
    'import assert from"node:assert/strict";import{connect}from"@actql/node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'assert.equal(client.input.profile,"mock");assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('actual public open forwards Explorer stateDir through the original bounded snapshot',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true});const result=f.run(
    'import assert from"node:assert/strict";import{open}from"@actql/node";'+
    'const raw={stateDir:".explorer"};const pending=open(raw);raw.stateDir="replacement";'+
    'const client=await pending;assert.equal(client.input.stateDir,".explorer");'+
    'assert.equal(Object.hasOwn(client.input,"profile"),false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('actual public open refuses unsupported inherited stateDir without calling its getter',t=>{
  const f=fixture(t,{publicNode:true,actualFacade:true});const result=f.run(
    'import assert from"node:assert/strict";import{open}from"@actql/node";let reads=0;'+
    'Object.defineProperty(Object.prototype,"stateDir",{configurable:true,get(){reads++;throw Error("UnownedGetter");}});'+
    'try{await assert.rejects(open({}),{code:"NodeInitialControlInputUnavailable"});assert.equal(reads,0);}'+
    'finally{delete Object.prototype.stateDir;}');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary connected Local HTTP selection stays unselected without traversing Host fields',t=>{
  const f=fixture(t,{publicNode:true});const result=f.run(
    'import assert from"node:assert/strict";import{connect}from"@actql/node";'+
    'let seen=0;const raw={mode:"local",owner:"local",endpoint:"https://host.example/",'+
    'get installation(){seen++;throw new Error("NoEmbeddedHost");},get profile(){seen++;throw new Error("NoEmbeddedProfile");}};'+
    'assert.equal(connect(raw),undefined);assert.equal(seen,0);'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'assert.equal(client.input.profile,"mock");assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary changed installed image retains its original refusal before Host or caller work',t=>{
  const f=fixture(t,{changeImage:true});const result=f.run(
    'import assert from"node:assert/strict";import{connect}from"@actql/local-node";'+
    'const errors=[];for(let i=0;i<2;i++){try{connect({mode:"local",installation:{directory:".actql"},profile:"mock"});}catch(e){errors.push(e);}}'+
    'assert.equal(errors.length,2);assert.equal(errors[0],errors[1]);assert.equal(errors[0].code,"InitialControlImageChanged");');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary modified intrinsic refuses before acquiring a caller snapshot',t=>{
  const f=fixture(t);const result=f.run(
    'import assert from"node:assert/strict";const original=Object.create;Object.create=function(...args){return original(...args);};'+
    'const{connect}=await import("@actql/local-node");let seen=0;'+
    'assert.throws(()=>connect({mode:"local",installation:{directory:".actql"},get profile(){seen++;}}),{code:"NodeInitialControlAdmissionUnavailable"});'+
    'assert.equal(seen,0);');
  assert.equal(result.status,0,result.stderr);
});

// The real installed prefix/FS handles and separate backing are exercised.
// Host declarations, pending-request association, intent CID and usage reports
// below are explicit diagnostic fixtures, not Common/Account/Run acceptance.
test('ordinary Source failed original snapshot never starts a replacement attempt',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals);let seen=0;'+
    'assert.throws(()=>root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{get unsupported(){seen++;}}),{code:"NodeSourceManagedInputUnavailable"});'+
    'assert.equal(seen,0);'+
    'assert.throws(()=>root.beforeSourceSnapshot(source,client.originals,"aql","SELECT replacement",{}),{code:"SourceManagedPreparationUnavailable"});'+
    'const closed=await root.closeSourceManagedInstallation(source,client.originals);'+
    'assert.equal(closed.pending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source managed Run keeps one joint original for both file children without Source child conversion',t=>{
  const f=fixture(t,{source:true,managedRun:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{});'+
    'const body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),prepared=Object.freeze({});client.bindFixtureRequest(request,prepared);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'const originalRun=root.prepareSourceManagedRun(source,client.originals,prepared);'+
    'assert.equal(root.prepareOriginalSourceChildPorts(originalRun),null);assert.equal(root.prepareOriginalManagedRunPorts({}),null);'+
    'assert.throws(()=>root.prepareSourceManagedRun(source,client.originals,prepared),{code:"SourceManagedPreparationUnavailable"});'+
    'assert.throws(()=>root.prepareSourceManagedRead(source,client.originals,prepared,client.declarations[0],originalRun),{code:"SourceManagedPreparationUnavailable"});'+
    'assert.equal(root.prepareOriginalManagedRunPorts(originalRun,{}),null);'+
    'const ports=root.prepareOriginalManagedRunPorts(originalRun,prepared);assert.ok(ports);assert.equal(root.prepareOriginalManagedRunPorts(originalRun,prepared),null);'+
    'assert.equal(ports.status(0),0);assert.equal(ports.status(0),-42);assert.equal(ports.limit(5),536870912n);'+
    'const reads=client.declarations.map(decl=>root.prepareSourceManagedRead(source,client.originals,prepared,decl,originalRun));'+
    'for(const read of reads)assert.equal(root.prepareOriginalSourceChildPorts(read.originalSource),null);'+
    'const left=await reads[0].readOriginalBytes(),right=await reads[1].readOriginalBytes();assert.equal(left.equals(right),true);assert.notEqual(left.buffer,right.buffer);'+
    'root.finishSourceProducer(source,client.originals,receipt,"returned");client.bindFixtureRequest(undefined,undefined);'+
    'assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).managedRunPending,true);'+
    'assert.equal(ports.report(0,0,0,0n,0n,0n,1n,0n,0n,1n,0,0,0),0);assert.equal(ports.status(2),-42);'+
    'reads[0].close();assert.equal(reads[1].status().pending,true);reads[1].close();'+
    'assert.equal(ports.report(0,0,0,0n,0n,0n,0n,0n,0n,1n,0,0,0),0);assert.equal(ports.status(2),0);'+
    'const closed=await root.closeSourceManagedInstallation(source,client.originals);assert.equal(closed.pending,false);assert.equal(closed.fdPending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source managed Run foreign reference refuses without consuming the original claim',t=>{
  const f=fixture(t,{source:true,managedRun:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{});'+
    'const body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),prepared=Object.freeze({});client.bindFixtureRequest(request,prepared);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'assert.throws(()=>root.prepareSourceManagedRun(source,client.originals,{}),/ForeignRequestFixture/);'+
    'const original=root.prepareSourceManagedRun(source,client.originals,prepared);assert.ok(original);'+
    'assert.throws(()=>root.prepareSourceManagedRead(source,client.originals,prepared,client.declarations[0]),{code:"SourceManagedPreparationUnavailable"});'+
    'root.finishSourceProducer(source,client.originals,receipt,"failed");assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).pending,false);'+
    'assert.equal(root.prepareOriginalManagedRunPorts(original),null);assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source managed Run exhaustion retains its failed claim without issuing another original',t=>{
  const f=fixture(t,{source:true,managedRun:true,oversizeRun:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{});'+
    'const body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),prepared=Object.freeze({});client.bindFixtureRequest(request,prepared);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'assert.throws(()=>root.prepareSourceManagedRun(source,client.originals,prepared),{code:"SourceManagedPreparationUnavailable"});'+
    'assert.throws(()=>root.prepareSourceManagedRun(source,client.originals,prepared),{code:"SourceManagedPreparationUnavailable"});'+
    'root.finishSourceProducer(source,client.originals,receipt,"failed");assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).pending,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source managed Run unpublished initialization closes distinctly without a fabricated usage report',t=>{
  const f=fixture(t,{source:true,managedRun:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{});'+
    'const body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),prepared=Object.freeze({});client.bindFixtureRequest(request,prepared);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'const original=root.prepareSourceManagedRun(source,client.originals,prepared),ports=root.prepareOriginalManagedRunPorts(original,prepared);assert.equal(ports.status(0),0);'+
    'assert.equal(ports.status(2),-42);root.finishSourceProducer(source,client.originals,receipt,"failed");'+
    'assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).pending,true);'+
    'assert.equal(ports.cancelUnpublished(),0);assert.equal(ports.cancelUnpublished(),0);'+
    'assert.equal(ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0),-42);'+
    'const closed=await root.closeSourceManagedInstallation(source,client.originals);assert.equal(closed.pending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal(root.prepareOriginalManagedRunPorts(original,prepared),null);assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source original retains two file children and separates logical stop from FD close',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals);'+
    'assert.throws(()=>root.assertSourceManagedInstallationCurrent({},client.originals),{code:"SourceManagedPreparationUnavailable"});'+
    'const receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{});'+
    'const body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});'+
    'root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),derived=Object.freeze({});client.bindFixtureRequest(request,derived);'+
    'root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'assert.equal(root.sourceIntentCid(source,client.originals,receipt,body),"sha256:"+"a".repeat(64));'+
    'const reads=client.declarations.map(decl=>root.prepareSourceManagedRead(source,client.originals,derived,decl));'+
    'assert.throws(()=>root.prepareSourceManagedRead(source,client.originals,derived,{}),{code:"SourceManagedPreparationUnavailable"});'+
    'const ports=reads.map(read=>root.prepareOriginalSourceChildPorts(read.originalSource));'+
    'assert.equal(root.prepareOriginalSourceChildPorts(reads[0].originalSource),null);'+
    'for(const port of ports){assert.equal(port.status(0),0);assert.equal(port.status(0),-42);}'+
    'const bodies=await Promise.all(reads.map(read=>read.readOriginalBytes()));'+
    'assert.equal(bodies[0].toString(),\'{"original":"same-file"}\\n\');'+
    'assert.equal(bodies[0].equals(bodies[1]),true);assert.notEqual(bodies[0].buffer,bodies[1].buffer);'+
    'assert.equal(ports[0].report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(ports[0].status(2),0);reads[0].close();'+
    'assert.equal(reads[1].status().pending,true);assert.equal(reads[0].status().fdPending,true);'+
    'assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).pending,true);'+
    'assert.equal(ports[1].status(1),1);'+
    'assert.equal(ports[1].report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(ports[1].status(2),0);reads[1].close();'+
    'root.finishSourceProducer(source,client.originals,receipt,"returned");'+
    'const closed=await root.closeSourceManagedInstallation(source,client.originals);'+
    'assert.equal(closed.pending,false);assert.equal(closed.fdPending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source changed same FD version refuses without issuing a replacement child',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{writeFile}from"node:fs/promises";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals);'+
    'const receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{}),body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});'+
    'root.bindSourceSnapshot(source,client.originals,receipt,body);'+
    'const request=Object.freeze({body}),derived=Object.freeze({});client.bindFixtureRequest(request,derived);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'const read=root.prepareSourceManagedRead(source,client.originals,derived,client.declarations[0]),port=root.prepareOriginalSourceChildPorts(read.originalSource);assert.equal(port.status(0),0);'+
    'await read.readOriginalBytes();await writeFile('+JSON.stringify(f.sourcePath)+',"changed original");'+
    'const other=root.prepareSourceManagedRead(source,client.originals,derived,client.declarations[1]),otherPort=root.prepareOriginalSourceChildPorts(other.originalSource);assert.equal(otherPort.status(0),0);'+
    'await assert.rejects(other.readOriginalBytes(),{code:"SourceManagedPreparationUnavailable"});'+
    'assert.throws(()=>root.prepareSourceManagedRead(source,client.originals,derived,client.declarations[1]),{code:"SourceManagedPreparationUnavailable"});'+
    'for(const [r,p]of [[read,port],[other,otherPort]]){assert.equal(p.report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(p.status(2),0);r.close();}'+
    'root.finishSourceProducer(source,client.originals,receipt,"failed");assert.equal((await root.closeSourceManagedInstallation(source,client.originals)).pending,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source keeps issued children after SDK producer aliases retire without issuing new claims',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{}),body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});'+
    'root.bindSourceSnapshot(source,client.originals,receipt,body);const request=Object.freeze({body}),derived=Object.freeze({});client.bindFixtureRequest(request,derived);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
    'const reads=client.declarations.map(decl=>root.prepareSourceManagedRead(source,client.originals,derived,decl));'+
    'root.finishSourceProducer(source,client.originals,receipt,"returned");client.bindFixtureRequest(undefined,undefined);'+
    'assert.throws(()=>root.prepareSourceManagedRead(source,client.originals,derived,client.declarations[0]),{code:"SourceManagedPreparationUnavailable"});'+
    'const ports=reads.map(read=>root.prepareOriginalSourceChildPorts(read.originalSource));for(const port of ports){assert.equal(port.status(0),0);assert.equal(port.status(1),0);}'+
    'const bytes=await Promise.all(reads.map(read=>read.readOriginalBytes()));assert.equal(bytes[0].equals(bytes[1]),true);assert.notEqual(bytes[0].buffer,bytes[1].buffer);'+
    'for(let index=0;index<2;index++){assert.equal(ports[index].report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(ports[index].status(2),0);reads[index].close();}'+
    'const closed=await root.closeSourceManagedInstallation(source,client.originals);assert.equal(closed.pending,false);assert.equal(closed.fdPending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source refuses a replaced allocator before calling it',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{Buffer}from"node:buffer";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'const original=Buffer.alloc;let calls=0;Buffer.alloc=function(){calls++;throw new Error("ReplacedAllocatorMustNotRun");};'+
    'let failure;try{await root.prepareSourceManagedInstallation(client.originals);}catch(error){failure=error;}finally{Buffer.alloc=original;}'+
    'assert.equal(calls,0);assert.equal(failure.code,"SourceManagedInstallationCleanupPending");assert.equal(failure.cause.code,"SourceManagedPreparationUnavailable");'+
    'assert.equal((await failure.cleanupHandle.retry()).pending,false);'+
    'await assert.rejects(root.prepareSourceManagedInstallation(client.originals),{code:"SourceManagedPreparationUnavailable"});'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

test('ordinary Source refuses distinct same-sized Buffer wrappers over one physical backing',t=>{
  const f=fixture(t,{source:true});
  const result=f.run(
    'import assert from"node:assert/strict";import{Buffer}from"node:buffer";import{createRequire}from"node:module";'+
    'const original=Buffer.alloc,shared=original(1048576),returned=[];'+
    'Buffer.alloc=function(size){if(size!==1048576)return Reflect.apply(original,Buffer,[size]);const value=Buffer.from(shared.buffer,shared.byteOffset,size);returned.push(value);return value;};'+
    'const{connect}=await import("@actql/local-node");'+
    'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
    'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
    'let failure;try{await root.prepareSourceManagedInstallation(client.originals);}catch(error){failure=error;}finally{Buffer.alloc=original;}'+
    'assert.equal(returned.length,2);assert.notEqual(returned[0],returned[1]);assert.equal(returned[0].length,1048576);assert.equal(returned[1].length,1048576);assert.equal(returned[0].buffer,returned[1].buffer);'+
    'assert.equal(failure.code,"SourceManagedInstallationCleanupPending");assert.equal(failure.cause.code,"SourceManagedPreparationUnavailable");'+
    'const closed=await failure.cleanupHandle.retry();assert.equal(closed.pending,false);assert.equal(closed.physicalBackingReleased,false);'+
    'assert.equal((await client.scope.close()).pending,false);');
  assert.equal(result.status,0,result.stderr);
});

for (const operation of ['subarray','equals']) {
  test('ordinary Source refuses replaced '+operation+' without dispatch and never revives after restoration',t=>{
    const f=fixture(t,{source:true});
    const result=f.run(
      'import assert from"node:assert/strict";import{Buffer}from"node:buffer";import{createRequire}from"node:module";import{connect}from"@actql/local-node";'+
      'const client=await connect({mode:"local",installation:{directory:".actql"},profile:"mock"});'+
      'const root=createRequire(import.meta.url)('+JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))+');'+
      'const source=await root.prepareSourceManagedInstallation(client.originals),receipt=root.beforeSourceSnapshot(source,client.originals,"aql","SELECT original",{}),body=Object.freeze({kind:"aql",input:"SELECT original",parameters:null});'+
      'root.bindSourceSnapshot(source,client.originals,receipt,body);const request=Object.freeze({body}),derived=Object.freeze({});client.bindFixtureRequest(request,derived);root.bindSourceRequest(source,client.originals,receipt,body,request);'+
      'const reads=client.declarations.map(decl=>root.prepareSourceManagedRead(source,client.originals,derived,decl)),ports=reads.map(read=>root.prepareOriginalSourceChildPorts(read.originalSource));for(const port of ports)assert.equal(port.status(0),0);'+
      'await reads[0].readOriginalBytes();const name='+JSON.stringify(operation)+',original=Buffer.prototype[name];let calls=0;Buffer.prototype[name]=function(){calls++;throw new Error("ReplacedBackingMethodMustNotRun");};'+
      'try{await assert.rejects(reads[1].readOriginalBytes(),{code:"SourceManagedPreparationUnavailable"});}finally{Buffer.prototype[name]=original;}'+
      'assert.equal(calls,0);assert.throws(()=>root.assertSourceManagedInstallationCurrent(source,client.originals),{code:"SourceManagedPreparationUnavailable"});'+
      'for(let index=0;index<2;index++){assert.equal(ports[index].report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(ports[index].status(2),0);reads[index].close();}'+
      'root.finishSourceProducer(source,client.originals,receipt,"failed");const closed=await root.closeSourceManagedInstallation(source,client.originals);assert.equal(closed.pending,false);assert.equal(closed.fdPending,false);assert.equal(closed.physicalBackingReleased,false);'+
      'assert.equal((await client.scope.close()).pending,false);');
    assert.equal(result.status,0,result.stderr);
  });
}
