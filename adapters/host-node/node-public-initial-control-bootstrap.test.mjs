import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

// Real ordinary Node module loading, same-FD captured images and the private
// installation Owner. The small Host below is explicit, not the full product
// Host or a normal installed README success, business supplier or permission.
function fixture(t,{inventory=true,changeImage=false,publicNode=false}={}) {
  const directory=mkdtempSync(join(tmpdir(),'actql-ordinary-control-'));
  t.after(()=>rmSync(directory,{recursive:true}));
  const root=join(directory,'node_modules/@actql/local-node');
  const sources=new Map();
  sources.set('package.json',Buffer.from(JSON.stringify({name:'@actql/local-node',version:'1.0.0',
    type:'module',exports:{'.':'./index.mjs',
      './_internal/initial-control-public-dispatch':'./initial-control-public-dispatch.cjs'}})));
  sources.set('index.mjs',Buffer.from('import delivery from "./initial-control-public-dispatch.cjs";'+
    'export function connect(raw){return delivery.selectedInitialControlHostPreparation("connect",raw);}'));
  sources.set('spec/local-check-environment.json',Buffer.from('{"original":"ordinary-asset"}\n'));
  sources.set('initial-control-public-dispatch.cjs',readFileSync(new URL('../../packages/local-node/initial-control-public-dispatch.cjs',import.meta.url)));
  for(const name of ['node-public-initial-control-bootstrap.cjs','initial-control-installation-owner.cjs',
    'initial-control-phase-envelope.cjs','source-managed-phase-envelope.cjs','initial-control-package-custody.cjs','initial-control-image-source.cjs',
    'initial-control-image-loader.cjs','node-initial-control-installation.mjs','initial-control-host-input.mjs']) {
    sources.set('adapters/host-node/'+name,readFileSync(new URL('./'+name,import.meta.url)));
  }
  sources.set('adapters/host-node/embedded-local.mjs',Buffer.from(
    'import{beginInitialControlInstallation,readInitialControlInstallationInput,readInitialControlInstallationAsset}from"./node-initial-control-installation.mjs";'+
    'export{snapshotInitialControlHostInput as readInitialControlHostInput}from"./initial-control-host-input.mjs";'+
    'let originals;export function assertInitialControlHostPreparation(held){'+
    'if(!originals||["host","installation","generation","supplier","moduleLifetime"].some(name=>held[name]!==originals[name]))throw new Error("ForeignHostFixture");}'+
    'export async function connectInitialControlHostPreparation(kind,raw){'+
    'originals=Object.freeze({host:{},installation:{},generation:{},supplier:connectInitialControlHostPreparation,moduleLifetime:import.meta});'+
    'const scope=await beginInitialControlInstallation(originals,raw);'+
    'return Object.freeze({input:readInitialControlInstallationInput(scope,originals),'+
    'asset:readInitialControlInstallationAsset(scope,originals,"spec/local-check-environment.json"),scope});}'));
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
      ['index.mjs',sources.get('index.mjs')],
      ['initial-control-public-dispatch.cjs',readFileSync(new URL('../../packages/node/initial-control-public-dispatch.cjs',import.meta.url))]
    ]);
    for(const[path,bytes]of nodeSources){mkdirSync(dirname(join(node,path)),{recursive:true});writeFileSync(join(node,path),bytes);}
    selected.publicNode={name:'@actql/node',version:'1.0.0',dependencies:[{name:'@actql/local-node',local:true}],
      images:[...nodeSources].map(([path,bytes])=>({path,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}))};
    selected.publicNodeCoverage='prepared';
  }
  sources.set('adapters/host-node/initial-control-package-original.cjs',Buffer.from(
    'module.exports=Object.freeze({imageInventory:'+(inventory?JSON.stringify(selected):'undefined')+'});'));
  for(const [path,bytes]of sources){mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),bytes);}
  if(changeImage)writeFileSync(join(root,'spec/local-check-environment.json'),'changed');
  return {directory,root,run(body){
    const entry=join(directory,'entry.mjs');writeFileSync(entry,body);
    const result=spawnSync(process.execPath,[entry],{cwd:directory,env:{PATH:process.env.PATH},encoding:'utf8',timeout:30000});
    assert.equal(result.error,undefined);return result;
  }};
}

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
