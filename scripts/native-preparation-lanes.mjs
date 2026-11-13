// One preparation owner, two independent construction lanes, one Ready index.
// Runtime Stores, claims, keys and test executions are never lane inputs.
import assert from 'node:assert/strict';
import {Worker,isMainThread,parentPort,workerData} from 'node:worker_threads';
import {createHash} from 'node:crypto';
import {chmodSync,constants,copyFileSync,lstatSync,mkdirSync,readFileSync,readdirSync,readlinkSync,
  realpathSync,symlinkSync,writeFileSync} from 'node:fs';
import {basename,dirname,join,relative,resolve,sep} from 'node:path';
import {verifyInstallation} from './moonbit-installation.mjs';
import {exportNativeCompiledCommand,originalDescriptor} from './native-preparation-originals.mjs';
import {prepareNativeResidentHttpComponent,prepareNativeResidentSite,prepareNativeRuntimeBundle,
  prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import {prepareNativeResidentPortableRuntime} from './native-resident-portable-preparation.mjs';

const sameStat=(path,original)=>{
  const current=lstatSync(path,{bigint:true});
  for(const key of ['dev','ino','size','mode','mtimeNs','ctimeNs'])assert.equal(current[key],original[key]);
};
const checksum=bytes=>createHash('sha256').update(bytes).digest('hex');
function included(path) {
  if(!path.startsWith('lib/core/_build'))return true;
  return path==='lib/core/_build'||['js','wasm','native'].some(target=>{
    const prefix='lib/core/_build/'+target;
    return path===prefix||path===prefix+'/release'||path===prefix+'/release/bundle'||path.startsWith(prefix+'/release/bundle/');
  });
}
// Native and portable Moon processes get distinct Core/cache roots. Retain only
// installed originals and the pinned bundle outputs, never stale build caches.
export function copyNativePreparationTools(original,destination,marker) {
  original=realpathSync(original);
  destination=join(realpathSync(dirname(resolve(destination))),basename(destination));
  verifyInstallation(original,marker);
  const files=[],directories=[],links=[];
  const visit=(from,to,name)=>{
    if(!included(name))return;
    const stat=lstatSync(from,{bigint:true});
    if(stat.isSymbolicLink()) {
      const target=readlinkSync(from),resolved=realpathSync(from);
      assert(!target.startsWith('/')&&(resolved===original||resolved.startsWith(original+sep)));
      symlinkSync(target,to);links.push({from,to,target,stat});
    } else if(stat.isDirectory()) {
      mkdirSync(to,{mode:Number(stat.mode&0o777n)});directories.push({from,stat});
      for(const child of readdirSync(from).sort())visit(join(from,child),join(to,child),name?name+'/'+child:child);
    } else {
      assert(stat.isFile(),'Only closed installed tool files may be copied');
      const bytes=readFileSync(from);sameStat(from,stat);
      copyFileSync(from,to,constants.COPYFILE_FICLONE|constants.COPYFILE_EXCL);
      chmodSync(to,Number(stat.mode&0o777n));
      assert.equal(checksum(readFileSync(to)),checksum(bytes));
      files.push({from,to,bytes:bytes.length,sha256:checksum(bytes),stat});
    }
  };
  visit(original,destination,'');
  for(const {from,stat} of [...files,...directories,...links])sameStat(from,stat);
  for(const {from,to,target} of links) {
    assert.equal(readlinkSync(from),target);assert.equal(readlinkSync(to),target);
    const current=realpathSync(to);assert(current.startsWith(destination+sep));
    assert.equal(relative(destination,current),relative(original,realpathSync(from)));
  }
  verifyInstallation(destination,marker);
  return {original,destination,files:files.map(({from,to,bytes,sha256})=>({from,to,bytes,sha256}))};
}

function timed(destination,source,target,phase,prepare) {
  const started=performance.now();let succeeded=false;
  try {const result=prepare();succeeded=true;return result;}
  finally {
    const result={source,target,phase,milliseconds:Math.round(performance.now()-started),succeeded};
    console.error('ACTQL_NATIVE_CI_PHASE '+JSON.stringify(result));
    try {writeFileSync(join(destination,'lane-'+phase+'.timing.json'),JSON.stringify(result)+'\n',{flag:'wx',mode:0o600});}
    catch {console.error('Native lane timing diagnostic unavailable');}
  }
}

export function prepareNativeConstructionLane(lane,configuration,ports={}) {
  assert(['commands','components'].includes(lane));
  const {repository,destination,source,target,selection,seconds,residentSeconds,httpJobs,moonHome,
    receiverMoonHome=moonHome}=configuration;
  assert(['bundle','resident','all'].includes(selection));
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
        const context={repository,source,target,moon_home:moonHome,clang:configuration.clang,sdk:configuration.sdk};
        remaining();
        const input=(ports.exportCommand??exportNativeCompiledCommand)(directory,join(inputs,name),name,context);
        producer(repository,join(destination,name),{moonHome:receiverMoonHome,seconds:remaining(),preparation:null,compiledInput:input});
      });
      entries[name]=originalDescriptor(join(destination,name,'received.json'));
    }
    return {entries};
  }
  const components=join(destination,'components');
  prepare('runtime_libraries',()=>(ports.libraries??prepareNativeRuntimeBundleLibraries)(repository,components,
    {moonHome,seconds,preparation:null}));
  const sharedOpenSSL=process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE??
    (target==='darwin-arm64'&&(process.env.ACTQL_TEST_NATIVE_CRYPTO_PROFILE??'source-macos11')==='source-macos11'
      ?join(components,'openssl-original.tar.gz'):undefined);
  const httpReceipt=selection==='bundle'?undefined:prepare('http_component',()=>(ports.http??prepareNativeResidentHttpComponent)(
    repository,join(destination,'http'),{seconds,tlsArchive:sharedOpenSSL,tlsJobs:httpJobs}));
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
  const toolDirectory=join(repository,'.toolchains',basename(destination)+'-commands');
  mkdirSync(join(repository,'.toolchains'),{recursive:true});
  const copied=copyTools(moonHome,toolDirectory,JSON.stringify({pin,platform:target}));
  writeFileSync(join(destination,'command-tool-copy.json'),JSON.stringify(copied)+'\n',{flag:'wx',mode:0o600});
  const results=await Promise.allSettled([
    startLane('commands',{...configuration,moonHome:toolDirectory,receiverMoonHome:moonHome}),
    startLane('components',configuration),
  ]);
  // A failed lane cannot publish Ready; still wait for the other original owner
  // to close naturally, retaining its exact partial outputs and original error.
  const failed=results.find(result=>result.status==='rejected');if(failed)throw failed.reason;
  return {...results[0].value,...results[1].value};
}
if(!isMainThread&&workerData?.kind==='native-preparation-lane') {
  parentPort.postMessage(prepareNativeConstructionLane(workerData.lane,workerData.configuration));
}
