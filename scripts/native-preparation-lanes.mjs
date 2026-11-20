// One preparation owner, two independent construction lanes, one Ready index.
// Runtime Stores, claims, keys and test executions are never lane inputs.
import assert from 'node:assert/strict';
import {Worker,isMainThread,parentPort,workerData} from 'node:worker_threads';
import {appendFileSync,lstatSync,mkdirSync,readFileSync,realpathSync,writeFileSync} from 'node:fs';
import {basename,join} from 'node:path';
import {copyNativePreparationTools,exportNativeCompiledCommand,originalDescriptor} from './native-preparation-originals.mjs';
export {copyNativePreparationTools} from './native-preparation-originals.mjs';
import {prepareNativeQuerySoftware} from './native-query-preparation.mjs';
import {prepareNativeResidentHttpComponent,prepareNativeResidentSite,prepareNativeRuntimeBundle,
  prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import {prepareNativeResidentPortableRuntime} from './native-resident-portable-preparation.mjs';

// Build-action slots, not OS thread or memory quotas. Both portable Moon
// invocations share the command-side slot; Query uses the component-side two.
const darwinJobs=Object.freeze({portable:1,query:2});

export function nativePreparationConsumerJobs({target,selection,lanes,destination,queryReceipt,portableReceipt}) {
  assert(['darwin-arm64','linux-x64'].includes(target));
  assert(['bundle','resident','all'].includes(selection)&&[1,2].includes(lanes));
  if(target!=='darwin-arm64'||selection!=='all'||lanes!==2)return {};
  assert.equal(queryReceipt,join(destination,'query-software.json'));
  assert.equal(portableReceipt,join(destination,'portable-runtime.json'));
  return {ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS:String(darwinJobs.query),
    ACTQL_TEST_NATIVE_PORTABLE_PREPARATION_JOBS:String(darwinJobs.portable)};
}


function timed(destination,source,target,phase,prepare) {
  const started=performance.now(),startedEpochMs=Date.now();let succeeded=false;
  try {const result=prepare();succeeded=true;return result;}
  finally {
    const result={source,target,phase,startedEpochMs,endedEpochMs:Date.now(),milliseconds:Math.round(performance.now()-started),succeeded};
    console.error('ACTQL_NATIVE_CI_PHASE '+JSON.stringify(result));
    try {writeFileSync(join(destination,'lane-'+phase+'.timing.json'),JSON.stringify(result)+'\n',{flag:'wx',mode:0o600});}
    catch {console.error('Native lane timing diagnostic unavailable');}
    if(process.env.GITHUB_STEP_SUMMARY) {
      try {appendFileSync(process.env.GITHUB_STEP_SUMMARY,
        `- Native ${phase}: ${result.milliseconds} ms (${succeeded?'success':'failed'}).\n`);}
      catch {console.error('Native lane timing summary unavailable');}
    }
  }
}

export function prepareNativeConstructionLane(lane,configuration,ports={}) {
  assert(['commands','components'].includes(lane));
  const {repository,destination,source,target,selection,seconds,residentSeconds,httpJobs,moonHome,
    receiverMoonHome=moonHome}=configuration;
  assert(['bundle','resident','all'].includes(selection));
  const queryLane=target==='darwin-arm64'&&selection==='all';
  const prepare=(phase,operation)=>timed(destination,source,target,phase,operation);
  if(lane==='commands') {
    const builds=join(destination,'command-builds'),inputs=join(destination,'command-inputs');
    mkdirSync(builds,{mode:0o700});mkdirSync(inputs,{mode:0o700});
    const entries={};
    for(const [name,producer,selected] of [
      ['native_runtime_bundle',ports.bundle??prepareNativeRuntimeBundle,selection!=='resident'],
      ['native_remote_resident_site',ports.resident??prepareNativeResidentSite,selection!=='bundle'],
    ]) {
      if(!selected)continue;
      const directory=join(builds,name),budget=name==='native_remote_resident_site'?residentSeconds:seconds;
      prepare(name,()=>{
        const deadline=performance.now()+budget*1000;
        const remaining=()=>{const value=Math.floor((deadline-performance.now())/1000);
          assert(value>0,'Original command lane budget exhausted');return value;};
        producer(repository,directory,{moonHome,seconds:budget,preparation:null});
        const context={repository,source,target,moon_home:moonHome,clang:configuration.clang,sdk:configuration.sdk??undefined};
        remaining();
        const input=(ports.exportCommand??exportNativeCompiledCommand)(directory,join(inputs,name),name,context);
        producer(repository,join(destination,name),{moonHome:receiverMoonHome,seconds:remaining(),preparation:null,compiledInput:input});
      });
      entries[name]=originalDescriptor(join(destination,name,'received.json'));
    }
    if(!queryLane)return {entries};
    const portableReceipt=join(destination,'portable-runtime.json');
    prepare('portable_runtime',()=>(ports.portable??prepareNativeResidentPortableRuntime)(repository,portableReceipt,
      {env:{...process.env,MOON_HOME:receiverMoonHome},jobs:darwinJobs.portable}));
    return {entries,portableReceipt};
  }
  const components=join(destination,'components');
  prepare('runtime_libraries',()=>(ports.libraries??prepareNativeRuntimeBundleLibraries)(repository,components,
    {moonHome,seconds,preparation:null}));
  const sharedOpenSSL=process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE??
    (target==='darwin-arm64'&&(process.env.ACTQL_TEST_NATIVE_CRYPTO_PROFILE??'source-macos11')==='source-macos11'
      ?join(components,'openssl-original.tar.gz'):undefined);
  const httpReceipt=selection==='bundle'?undefined:prepare('http_component',()=>(ports.http??prepareNativeResidentHttpComponent)(
    repository,join(destination,'http'),{seconds,tlsArchive:sharedOpenSSL,tlsJobs:httpJobs}));
  if(queryLane) {
    const queryReceipt=prepare('query_software',()=>(ports.query??prepareNativeQuerySoftware)(
      repository,destination,{moonHome,jobs:darwinJobs.query}));
    assert.equal(queryReceipt,join(destination,'query-software.json'),'Foreign Query preparation output');
    return {components,httpReceipt,queryReceipt};
  }
  const portableReceipt=selection==='all'?join(destination,'portable-runtime.json'):undefined;
  if(portableReceipt!==undefined)prepare('portable_runtime',()=>(ports.portable??prepareNativeResidentPortableRuntime)(
    repository,portableReceipt));
  return {components,httpReceipt,portableReceipt};
}

function startWorker(lane,configuration) {
  return new Promise((resolve,reject)=>{
    const worker=new Worker(new URL(import.meta.url),{workerData:{kind:'native-preparation-lane',lane,configuration},
      resourceLimits:{maxOldGenerationSizeMb:256}});
    let result,error;
    worker.on('message',value=>{result=value;});worker.on('error',value=>{error=value;});
    worker.on('exit',code=>{
      if(error)reject(error);
      else if(code!==0||result===undefined)reject(new Error('Native '+lane+' lane failed with exit '+code));
      else resolve(result);
    });
  });
}
export async function prepareNativeParallel(configuration,{copyTools=copyNativePreparationTools,startLane=startWorker}={}) {
  const {repository,destination,moonHome,target}=configuration;
  const pin=JSON.parse(readFileSync(join(repository,'toolchain.json'),'utf8'));
  const toolBase=join(repository,'.toolchains');mkdirSync(toolBase,{recursive:true});
  const baseStat=lstatSync(toolBase);
  assert(baseStat.isDirectory()&&!baseStat.isSymbolicLink(),'A shared tool-output alias is not a preparation destination');
  assert.equal(realpathSync(toolBase),join(realpathSync(repository),'.toolchains'));
  const toolDirectory=join(realpathSync(toolBase),basename(destination)+'-commands');
  const copied=copyTools(moonHome,toolDirectory,JSON.stringify({pin,platform:target}));
  writeFileSync(join(destination,'command-tool-copy.json'),JSON.stringify(copied)+'\n',{flag:'wx',mode:0o600});
  const launch=(lane,options)=>{
    try {return Promise.resolve(startLane(lane,options));}
    catch(error) {return Promise.reject(error);}
  };
  const results=await Promise.allSettled([
    launch('commands',{...configuration,moonHome:toolDirectory,receiverMoonHome:moonHome}),
    launch('components',configuration),
  ]);
  // A failed lane cannot publish Ready; still wait for the other original owner
  // to close naturally, retaining its exact partial outputs and original error.
  // A synchronous launch failure also joins every owner that did start.
  const failed=results.find(result=>result.status==='rejected');if(failed)throw failed.reason;
  return {...results[0].value,...results[1].value};
}
if(!isMainThread&&workerData?.kind==='native-preparation-lane') {
  parentPort.postMessage(prepareNativeConstructionLane(workerData.lane,workerData.configuration));
}
