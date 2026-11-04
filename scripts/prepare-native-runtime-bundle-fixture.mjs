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

const args=process.argv.slice(2),options={};
for(let i=0;i<args.length;i+=2) {
  assert(['--destination','--entries','--seconds'].includes(args[i]) && args[i+1]!==undefined);
  assert.equal(options[args[i]],undefined);options[args[i]]=args[i+1];
}
assert(options['--destination']);
const selection=options['--entries']??'bundle';assert(['bundle','resident','all'].includes(selection));
const seconds=Number(options['--seconds']??900);
assert(Number.isSafeInteger(seconds) && seconds>0 && seconds<=1800);
const target=process.platform==='darwin' && process.arch==='arm64'?'darwin-arm64'
  :process.platform==='linux' && process.arch==='x64'?'linux-x64':undefined;
assert(target,'No selected native preparation target');
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
mkdirSync(destination,{mode:0o700});
const entries={};
for(const [name,prepare,selected] of [
  ['native_runtime_bundle',prepareNativeRuntimeBundle,selection!=='resident'],
  ['native_remote_resident_site',prepareNativeResidentSite,selection!=='bundle'],
]) {
  if(!selected)continue;
  const directory=join(destination,name);
  prepare(repository,directory,{moonHome,seconds,preparation:null});
  entries[name]=originalDescriptor(join(directory,'build.json'));
}
const components=join(destination,'components');
prepareNativeRuntimeBundleLibraries(repository,components,{moonHome,seconds,preparation:null});
const httpReceipt=selection==='bundle'?undefined:
  prepareNativeResidentHttpComponent(repository,join(destination,'http'),{seconds});
assert.equal(run('git',['rev-parse','HEAD']).trim(),source);
assert.equal(run('git',['status','--porcelain']),'');
writeFileSync(join(destination,'preparation.json'),JSON.stringify({source,target,moon_home:moonHome,
  clang,sdk,entries,components:originalDescriptor(join(components,'bundle-components.json')),
  http:httpReceipt===undefined?null:originalDescriptor(join(destination,'http/preparation.json'))},null,2)+'\n',
  {flag:'wx',mode:0o600});
if(process.env.GITHUB_ENV!==undefined)appendFileSync(process.env.GITHUB_ENV,
  'ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION='+destination+'\n'+
  (httpReceipt===undefined?'':'ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT='+httpReceipt+'\n'));
console.log(JSON.stringify({source,target,preparation:destination,entries:Object.keys(entries)}));
