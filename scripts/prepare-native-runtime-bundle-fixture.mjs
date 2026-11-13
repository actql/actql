// One job's exact-source public command/component artifacts. Consumers verify
// the original producer inputs again; private Stores and keys stay per test.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {appendFileSync,mkdirSync,realpathSync,writeFileSync} from 'node:fs';
import {basename,dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {prepareNativeResidentHttpComponent,prepareNativeResidentSite,prepareNativeRuntimeBundle,prepareNativeRuntimeBundleLibraries}
  from './native-runtime-bundle-fixture.mjs';
import {originalDescriptor} from './native-preparation-originals.mjs';
import {prepareNativeResidentPortableRuntime} from './native-resident-portable-preparation.mjs';
import {prepareNativeParallel} from './native-preparation-lanes.mjs';
import {prepareNativeQuerySoftware} from './native-query-preparation.mjs';

const args=process.argv.slice(2),options={};
for(let i=0;i<args.length;i+=2) {
  assert(['--destination','--entries','--seconds','--resident-seconds','--http-jobs','--lanes'].includes(args[i]) && args[i+1]!==undefined);
  assert.equal(options[args[i]],undefined);options[args[i]]=args[i+1];
}
assert(options['--destination']);
const selection=options['--entries']??'bundle';assert(['bundle','resident','all'].includes(selection));
const seconds=Number(options['--seconds']??900);
assert(Number.isSafeInteger(seconds) && seconds>0 && seconds<=1800);
const residentSeconds=Number(options['--resident-seconds']??seconds);
assert(Number.isSafeInteger(residentSeconds) && residentSeconds>0 && residentSeconds<=1800);
const httpJobs=Number(options['--http-jobs']??1);
assert(Number.isSafeInteger(httpJobs) && [1,2].includes(httpJobs));
const lanes=Number(options['--lanes']??1);assert([1,2,3].includes(lanes));
const target=process.platform==='darwin' && process.arch==='arm64'?'darwin-arm64'
  :process.platform==='linux' && process.arch==='x64'?'linux-x64':undefined;
assert(target,'No selected native preparation target');
if(lanes===3)assert(target==='darwin-arm64'&&selection==='all',
  'Three lanes require the complete Darwin preparation');
const repository=realpathSync(fileURLToPath(new URL('../',import.meta.url)));
const destination=join(realpathSync(dirname(resolve(options['--destination']))),basename(options['--destination']));
assert(!/[\r\n]/u.test(destination));
const run=(command,args)=>execFileSync(command,args,{cwd:repository,encoding:'utf8',timeout:60000});
const source=run('git',['rev-parse','HEAD']).trim();assert.match(source,/^[0-9a-f]{40}$/u);
assert.equal(run('git',['status','--porcelain']),'');
const moonHome=realpathSync(process.env.MOON_HOME);
const clang=realpathSync(process.platform==='darwin'?run('xcrun',['--find','clang']).trim()
  :run('sh',['-c','command -v clang']).trim());
const sdk=process.platform==='darwin'?realpathSync(run('xcrun',['--show-sdk-path']).trim()):null;
let preparationPhase=0;
function timedPreparation(phase, prepare) {
  const started=performance.now();let succeeded=false;
  try { const value=prepare();succeeded=true;return value; }
  finally {
    const milliseconds=Math.round(performance.now()-started);
    console.error('ACTQL_NATIVE_CI_PHASE '+JSON.stringify({phase,milliseconds,succeeded}));
    // The existing receipt upload runs before the test cases. Keep a bounded
    // diagnostic per completed producer there, without changing artifact identity
    // or replacing the producer's original return/throw if diagnostics fail.
    try {
      writeFileSync(join(destination,`phase-${++preparationPhase}.timing.json`),
        JSON.stringify({source,target,phase,milliseconds,succeeded})+'\n',{flag:'wx',mode:0o600});
    } catch { console.error('Native timing diagnostic unavailable'); }
    if(process.env.GITHUB_STEP_SUMMARY) {
      try { appendFileSync(process.env.GITHUB_STEP_SUMMARY,
        `- Native ${phase}: ${milliseconds} ms (${succeeded?'success':'failed'}).\n`); }
      catch { console.error('Native timing summary unavailable'); }
    }
  }
}
mkdirSync(destination,{mode:0o700});
function serialPreparation() {
const entries={};
for(const [name,prepare,selected] of [
  ['native_runtime_bundle',prepareNativeRuntimeBundle,selection!=='resident'],
  ['native_remote_resident_site',prepareNativeResidentSite,selection!=='bundle'],
]) {
  if(!selected)continue;
  const directory=join(destination,name);
  timedPreparation(name,()=>prepare(repository,directory,{moonHome,
    seconds:name==='native_remote_resident_site'?residentSeconds:seconds,preparation:null}));
  entries[name]=originalDescriptor(join(directory,'build.json'));
}
const components=join(destination,'components');
timedPreparation('runtime_libraries',()=>
  prepareNativeRuntimeBundleLibraries(repository,components,{moonHome,seconds,preparation:null}));
// Reuse only the immutable original archive already checked by Crypto. TLS
// performs its own digest check and independent build with its own lifetime
// flags; no compiled library or provider is borrowed across these recipes.
const sharedOpenSSL=process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE??
  (target==='darwin-arm64' && (process.env.ACTQL_TEST_NATIVE_CRYPTO_PROFILE??'source-macos11')==='source-macos11'
    ?join(components,'openssl-original.tar.gz'):undefined);
const httpReceipt=selection==='bundle'?undefined:
  timedPreparation('http_component',()=>
    prepareNativeResidentHttpComponent(repository,join(destination,'http'),{seconds,tlsArchive:sharedOpenSSL,tlsJobs:httpJobs}));
const portableReceipt = selection === 'all' ? join(destination, 'portable-runtime.json') : undefined;
if (portableReceipt !== undefined) timedPreparation('portable_runtime', () =>
  prepareNativeResidentPortableRuntime(repository, portableReceipt));
  return {entries,components,httpReceipt,portableReceipt};
}
const {entries,components,httpReceipt,portableReceipt,queryReceipt:parallelQueryReceipt}=lanes>1
  ?await prepareNativeParallel({repository,destination,source,target,selection,seconds,residentSeconds,httpJobs,moonHome,clang,sdk,lanes})
  :serialPreparation();
// The same completed preparation owns one default Native Query image. Only
// software is shared; the later HTTP and Remote fixtures retain fresh roots,
// keys, ports, environment, original Moon commands and exact execution counts.
let queryReceipt=parallelQueryReceipt;
if(lanes===3)assert.equal(queryReceipt,join(destination,'query-software.json'),
  'Missing original parallel Query preparation');
if(target==='darwin-arm64'&&selection==='all'&&lanes!==3)timedPreparation('query_software',()=>{
  queryReceipt=prepareNativeQuerySoftware(repository,destination,{env:{...process.env,MOON_HOME:moonHome}});
});
assert.equal(run('git',['rev-parse','HEAD']).trim(),source);
assert.equal(run('git',['status','--porcelain']),'');
writeFileSync(join(destination,'preparation.json'),JSON.stringify({source,target,moon_home:moonHome,
  clang,sdk,entries,components:originalDescriptor(join(components,'bundle-components.json')),
  http:httpReceipt===undefined?null:originalDescriptor(join(destination,'http/preparation.json'))},null,2)+'\n',
  {flag:'wx',mode:0o600});
if(process.env.GITHUB_ENV!==undefined)appendFileSync(process.env.GITHUB_ENV,
  'ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION='+destination+'\n'+
  (queryReceipt===undefined?'':'ACTQL_TEST_NATIVE_QUERY_PREPARATION='+queryReceipt+'\n')+
  (portableReceipt===undefined?'':'ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION='+portableReceipt+'\n')+
  (httpReceipt===undefined?'':'ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT='+httpReceipt+'\n'));
console.log(JSON.stringify({source,target,preparation:destination,entries:Object.keys(entries),constructionLanes:lanes}));
