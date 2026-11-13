import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {installationFiles} from './moonbit-installation.mjs';

async function api() { return import('./native-query-preparation.mjs'); }
function fixture(t) {
  const root=mkdtempSync(join(tmpdir(),'actql-query-preparation-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const repository=join(root,'source'),destination=join(root,'preparation'),home=join(root,'original-tool');
  for(const path of [repository,destination,home])mkdirSync(path);
  const put=(path,bytes)=>{mkdirSync(join(path,'..'),{recursive:true});writeFileSync(path,bytes,{mode:0o700});};
  put(join(repository,'toolchain.json'),'{}');put(join(repository,'original.mbt'),'original source\n');
  const git=(...args)=>execFileSync('git',args,{cwd:repository,stdio:'pipe'});
  git('init','-q');git('add','.');git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','test: original source');
  for(const path of installationFiles)put(join(home,path),'original '+path);
  put(join(home,'installed.json'),JSON.stringify({pin:{},platform:'darwin-arm64'}));
  const commands=join(root,'commands.jsonl');
  put(join(home,'bin/moon'),'#!'+process.execPath+'\n'+String.raw`
const {appendFileSync,existsSync,mkdirSync,writeFileSync}=require('node:fs');
const {join}=require('node:path');const args=process.argv.slice(2);
appendFileSync(process.env.QUERY_FIXTURE_COMMANDS,JSON.stringify({args,runtime:process.env.QUERY_FIXTURE_RUNTIME??null})+'\n');
if(process.env.QUERY_FIXTURE_BUILD_FAILURE)process.exit(17);
const target=args[args.indexOf('--target-dir')+1],directory=join(target,'native/debug/test/query_integration');
mkdirSync(directory,{recursive:true});const image=join(directory,'query_integration.whitebox_test.exe');
if(!existsSync(image))writeFileSync(image,'same original software');
if(!args.includes('--build-only'))console.log('Total tests: 1, passed: 1, failed: 0.');
`);
  return {repository,destination,home,commands,put,env:{...process.env,MOON_HOME:home,QUERY_FIXTURE_COMMANDS:commands},
    calls:()=>readFileSync(commands,'utf8').trim().split('\n').map(JSON.parse)};
}

test('one prepared Query image serves both original selections with independent runtime inputs',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  assert.equal(f.calls().length,1);assert.equal(f.calls()[0].runtime,null);
  assert.deepEqual(f.calls()[0].args.slice(0,5),['test','src/query_integration','src/native_values_integration','--target','native']);
  const paths=['src/query_integration/first_wbtest.mbt','src/query_integration/second_wbtest.mbt'];
  for(const [index,path] of paths.entries()) {
    const runtime={...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt,QUERY_FIXTURE_RUNTIME:'original-'+index};
    const original=preparedNativeQuerySoftware(f.repository,runtime);
    execFileSync(original.moon,['test',path,'--target','native','--target-dir',original.targetDirectory],
      {cwd:f.repository,env:original.environment,stdio:'pipe'});
    original.verify();
    assert.equal(runtime.MOON_HOME,f.home);
  }
  const calls=f.calls();assert.equal(calls.length,3);
  assert.deepEqual(calls.slice(1).map(x=>x.runtime),['original-0','original-1']);
  assert.equal(calls[1].args.at(-1),calls[2].args.at(-1));
  assert.equal(calls.slice(1).filter(x=>x.args.includes('--build-only')).length,0);
});

test('Query reuse refuses changed source, compiler settings, tool and generated image without rebuilding',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  const env={...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt};
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,{...env,MOONBIT_NEW_NATIVE:'0'}));
  const source=join(f.repository,'original.mbt');f.put(source,'changed source');
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,env));f.put(source,'original source\n');
  const tool=join(f.home,'bin/moonc'),bytes=readFileSync(tool);f.put(tool,'changed compiler');
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,env));f.put(tool,bytes);
  const original=preparedNativeQuerySoftware(f.repository,env);
  f.put(join(original.targetDirectory,'native/debug/test/query_integration/query_integration.whitebox_test.exe'),'changed software');
  assert.throws(()=>original.verify());assert.throws(()=>preparedNativeQuerySoftware(f.repository,env));
  assert.equal(f.calls().length,1);
});

test('Query compiler failure never publishes a preparation and absence retains the old local path',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  assert.equal(preparedNativeQuerySoftware(f.repository,f.env),undefined);
  assert.throws(()=>prepareNativeQuerySoftware(f.repository,f.destination,
    {env:{...f.env,QUERY_FIXTURE_BUILD_FAILURE:'1'}}));
  assert.equal(existsSync(join(f.destination,'query-software.json')),false);
  assert.equal(f.calls().length,1);
});
