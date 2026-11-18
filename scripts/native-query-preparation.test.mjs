import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter,join} from 'node:path';
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
  put(join(home,'installed.json'),JSON.stringify({pin:{},platform:process.platform+'-'+process.arch}));
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
  return {repository,destination,home,commands,put,git,env:{...process.env,MOON_HOME:home,QUERY_FIXTURE_COMMANDS:commands},
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

test('Query parallel preparation binds its one-job command to the original consumer mode',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env,jobs:1});
  const args=f.calls()[0].args;
  assert.equal(args[args.indexOf('-j')+1],'1');assert(args.includes('--build-only'));
  const env={...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt,
    ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS:'1'};
  const original=preparedNativeQuerySoftware(f.repository,env);original.verify();
  const absent={...env};delete absent.ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS;
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,absent));
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,
    {...env,ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS:'2'}));
  const bytes=readFileSync(receipt),body=JSON.parse(bytes);
  body.identity.command.splice(body.identity.command.indexOf('-j'),2);
  writeFileSync(receipt,JSON.stringify(body));
  assert.throws(()=>original.verify());writeFileSync(receipt,bytes);original.verify();
  assert.equal(f.calls().length,1,'Mode checks cannot rebuild or execute a case');
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
    {env:{...f.env,QUERY_FIXTURE_BUILD_FAILURE:'1'}}),error=>error.status===17);
  assert.equal(existsSync(join(f.destination,'query-software.json')),false);
  assert.equal(f.calls().length,1);
  const failed=JSON.parse(readFileSync(join(f.destination,'phase-query-3.timing.json')));
  assert.equal(failed.phase,'build-only');assert.equal(failed.succeeded,false);
  assert.equal(existsSync(join(f.destination,'phase-query-4.timing.json')),false);
});

test('Query preparation times original input, tool, build and retention work without claiming executed cases',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  const body=JSON.parse(readFileSync(receipt));
  assert.deepEqual(body.timings.map(row=>row.phase),
    ['input-admission','tool-copy','build-only','input-correspondence','output-retention']);
  for(const [index,row] of body.timings.entries()) {
    assert.equal(row.scope,'native-query-preparation');assert.equal(row.source,body.identity.source);
    assert.equal(row.target,process.platform+'-'+process.arch);assert.equal(row.succeeded,true);
    assert(Number.isSafeInteger(row.milliseconds)&&row.milliseconds>=0);
    assert(Number.isSafeInteger(row.startedEpochMs)&&Number.isSafeInteger(row.endedEpochMs));
    assert.deepEqual(JSON.parse(readFileSync(join(f.destination,`phase-query-${index+1}.timing.json`))),row);
  }
  assert.equal(f.calls().length,1);assert(f.calls()[0].args.includes('--build-only'));
  const runtime=preparedNativeQuerySoftware(f.repository,{...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  runtime.verify();assert.equal(f.calls().length,1,'Timing and validation cannot execute cases');
});

test('Query timing file refusal preserves the earlier evidence and the same compiler failure',async t=>{
  const {prepareNativeQuerySoftware}=await api(),f=fixture(t);
  const file=join(f.destination,'phase-query-1.timing.json');f.put(file,'earlier diagnostic evidence');
  const original=new Error('original compiler failure');
  assert.throws(()=>prepareNativeQuerySoftware(f.repository,f.destination,
    {env:f.env,execute:()=>{throw original;}}),error=>error===original);
  assert.equal(readFileSync(file,'utf8'),'earlier diagnostic evidence');
  const failed=JSON.parse(readFileSync(join(f.destination,'phase-query-3.timing.json')));
  assert.equal(failed.phase,'build-only');assert.equal(failed.succeeded,false);
  assert.equal(existsSync(join(f.destination,'query-software.json')),false);
});

test('Query timing file refusal cannot prevent the original successful preparation',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const file=join(f.destination,'phase-query-1.timing.json');f.put(file,'earlier diagnostic evidence');
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  assert.equal(readFileSync(file,'utf8'),'earlier diagnostic evidence');
  assert(JSON.parse(readFileSync(receipt)).timings.every(row=>row.succeeded));
  const original=preparedNativeQuerySoftware(f.repository,{...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  original.verify();assert.equal(f.calls().length,1);
});

test('Query reuse allows the same pinned installation at a fresh owner path but refuses aliases and duplicate construction',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const {copyNativePreparationTools}=await import('./native-preparation-lanes.mjs');
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  const fresh=join(f.destination,'fresh-tool');
  copyNativePreparationTools(f.home,fresh,readFileSync(join(f.home,'installed.json'),'utf8'));
  const original=preparedNativeQuerySoftware(f.repository,{...f.env,MOON_HOME:fresh,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  original.verify();assert.notEqual(original.environment.MOON_HOME,fresh);
  assert.throws(()=>prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env}));
  const alias=join(f.destination,'alias.json');symlinkSync(receipt,alias);
  for(const path of [alias,'',null])assert.throws(()=>preparedNativeQuerySoftware(f.repository,
    {...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:path}));
  assert.equal(f.calls().length,1);
});

test('Query reuse retains the actual selected compiler override bytes and refuses their later replacement',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const compiler=join(f.destination,'original-cc');f.put(compiler,'#!/bin/sh\nexit 0\n');
  const env={...f.env,CC:compiler};
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env});
  const retained=preparedNativeQuerySoftware(f.repository,{...env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  f.put(compiler,'#!/bin/sh\nexit 17\n');
  assert.throws(()=>retained.verify());
  assert.throws(()=>preparedNativeQuerySoftware(f.repository,{...env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt}));
  assert.equal(f.calls().length,1);
});

test('the existing Darwin preparation publishes Query software before either original caller can borrow it',()=>{
  const source=readFileSync(new URL('./prepare-native-runtime-bundle-fixture.mjs',import.meta.url),'utf8');
  assert(source.includes("if(target==='darwin-arm64'&&selection==='all')timedPreparation('query_software',()=>{"));
  const prepare=source.indexOf('queryReceipt=prepareNativeQuerySoftware(repository,destination,');
  assert(prepare>source.indexOf('?await prepareNativeParallel('));
  assert(prepare<source.indexOf("writeFileSync(join(destination,'preparation.json')"));
  assert(source.includes("'ACTQL_TEST_NATIVE_QUERY_PREPARATION='+queryReceipt+'\\n'"));
  const caller=readFileSync(new URL('./native-query-coverage.mjs',import.meta.url),'utf8');
  assert(caller.indexOf('selectNativeQueryTests(owner, readNativeQuerySources(root), env)')<
    caller.indexOf('preparedNativeQuerySoftware(root, env)'));
  assert(caller.includes('moon = prepared.moon; env = prepared.environment; targetDirectory = prepared.targetDirectory;'));
  assert(caller.includes("await runPhase('execute', args);\n  prepared?.verify();"));
  const entry=readFileSync(new URL('./native-query-coverage.test.mjs',import.meta.url),'utf8');
  assert.equal(entry.split("import './native-query-preparation.test.mjs';").length,2);
});

test('the actual Query preparation call keeps the enclosing selected Moon home over ambient environment',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const ambient=Object.freeze({...f.env,MOON_HOME:join(f.destination,'not-an-installed-tool')});
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:ambient,moonHome:f.home});
  assert.equal(ambient.MOON_HOME,join(f.destination,'not-an-installed-tool'));
  assert.equal(f.calls().length,1);assert(f.calls()[0].args.includes('--build-only'));
  const original=preparedNativeQuerySoftware(f.repository,{...ambient,MOON_HOME:f.home,
    ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  original.verify();
  assert.equal(original.environment.PATH.split(delimiter)[0],join(original.environment.MOON_HOME,'bin'));
  assert.equal(original.environment.QUERY_FIXTURE_COMMANDS,ambient.QUERY_FIXTURE_COMMANDS);
});

test('Query preparation retains the tracked skill directory alias and every original target file',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const repository=realpathSync(f.repository),target=join(repository,'.agents/skills/actql-local-verification');
  const member=join(target,'SKILL.md'),alias=join(repository,'.claude/skills/actql-local-verification');
  const skill=readFileSync(new URL('../.agents/skills/actql-local-verification/SKILL.md',import.meta.url));
  f.put(member,skill);mkdirSync(join(alias,'..'),{recursive:true});
  symlinkSync('../../.agents/skills/actql-local-verification',alias);
  f.git('add','.');f.git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','test: original skill alias');
  const receipt=prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env});
  const body=JSON.parse(readFileSync(receipt));
  assert.deepEqual(body.identity.sourceAliases,[{path:alias,link:'../../.agents/skills/actql-local-verification',target,members:[member]}]);
  assert.equal(body.inputs.filter(x=>x.selectedPath===member).length,1);
  const original=preparedNativeQuerySoftware(f.repository,{...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt});
  original.verify();f.put(member,'changed original target');
  assert.throws(()=>original.verify());f.put(member,skill);original.verify();
  assert.equal(f.calls().length,1,'Only the original build-only command is permitted');
});

test('Query preparation refuses foreign and empty tracked directory aliases before compilation',async t=>{
  const {prepareNativeQuerySoftware}=await api();
  for(const foreign of [true,false]) {
    const f=fixture(t),target=foreign?f.destination:join(f.repository,'empty-original');
    if(!foreign)mkdirSync(target);
    symlinkSync(target,join(f.repository,'original-alias'));
    f.git('add','.');f.git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','test: unrecognized directory alias');
    assert.throws(()=>prepareNativeQuerySoftware(f.repository,f.destination,{env:f.env}));
    assert.equal(existsSync(f.commands),false);
    assert.equal(existsSync(join(f.destination,'query-software.json')),false);
  }
});

test('Query reuse refuses a changed contained alias target even while the tracked tree remains clean',async t=>{
  const {prepareNativeQuerySoftware,preparedNativeQuerySoftware}=await api(),f=fixture(t);
  const repository=realpathSync(f.repository),bridge=join(repository,'.source-bridge');
  for(const name of ['first','second'])f.put(join(repository,name,'original.txt'),'same immutable bytes');
  f.put(join(repository,'.gitignore'),'.source-bridge\n');
  symlinkSync('first',bridge);symlinkSync('.source-bridge',join(repository,'original-alias'));
  f.git('add','.');f.git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','test: original resolved alias target');
  const receipt=prepareNativeQuerySoftware(repository,f.destination,{env:f.env});
  const env={...f.env,ACTQL_TEST_NATIVE_QUERY_PREPARATION:receipt},original=preparedNativeQuerySoftware(repository,env);
  original.verify();unlinkSync(bridge);symlinkSync('second',bridge);
  assert.equal(f.git('status','--porcelain').toString(),'');
  assert.throws(()=>original.verify(),/Foreign Query source\/toolchain\/compiler settings/u);
  assert.throws(()=>preparedNativeQuerySoftware(repository,env));
  unlinkSync(bridge);symlinkSync('first',bridge);original.verify();assert.equal(f.calls().length,1);
});
