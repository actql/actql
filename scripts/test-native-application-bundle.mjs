// Execute the original HTTP harness's real two-component install/activate seam.
// This focused command does not execute or replace the HTTP/query campaign.
import assert from 'node:assert/strict';
import {execFile,execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir,mkdtemp,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {promisify} from 'node:util';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {installNativeApplicationBundle} from './native-application-bundle-fixture.mjs';

const repositoryRoot=fileURLToPath(new URL('../',import.meta.url));
const parent=process.env.ACTQL_TEST_SCRATCH_ROOT;assert(typeof parent==='string' && parent.length>0);
const targetTriple=process.platform==='darwin' && process.arch==='arm64'?'aarch64-apple-darwin'
  :process.platform==='linux' && process.arch==='x64'?'x86_64-unknown-linux-gnu':undefined;
assert(targetTriple,'No actual application bundle target');
const namespace=process.env.ACTQL_TEST_NATIVE_SITE_NETNS,user=process.env.ACTQL_TEST_NATIVE_SITE_USER;
assert.equal(namespace===undefined,user===undefined);assert.notEqual(namespace,'');assert.notEqual(user,'');
const duckdb=join(repositoryRoot,'adapters/connectors/duckdb/node/node_modules/@duckdb',
  'node-bindings-'+process.platform+'-'+process.arch,process.platform==='darwin'?'libduckdb.dylib':'libduckdb.so');
assert(existsSync(duckdb),'Pinned actual DuckDB component required: '+duckdb);
await mkdir(parent,{recursive:true});
const root=await mkdtemp(join(parent,'native-application-bundle-'));
let passed=false;
try {
  const moon=join(process.env.MOON_HOME??'','bin/moon');
  execFileSync(moon,['build','--target','js','--release','src/connectors_builtin_node'],{cwd:repositoryRoot,stdio:'inherit'});
  execFileSync(moon,['build','--target','native','src/cmd/native_remote_application_site'],{cwd:repositoryRoot,stdio:'inherit'});
  const moonModule=await import(pathToFileURL(join(repositoryRoot,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')).href);
  const runtimeControl=runtimeCore(moonModule).remoteBundleControl;
  const runtimeKeys=generateKeyPairSync('ed25519');
  const applicationRuntimeRoot=join(root,'runtime'),applicationBundleInputRoot=join(root,'input');
  await mkdir(applicationRuntimeRoot);await mkdir(applicationBundleInputRoot);
  const execute=promisify(execFile);
  const runCaptured=(executable,args)=>({completed:(async()=>{
    const command=namespace===undefined?executable:'sudo';
    const arguments_=namespace===undefined?args:['ip','netns','exec',namespace,'sudo',`--user=${user}`,
      'env','PATH=/usr/bin:/bin','LANG=C',executable,...args];
    try {
      const result=await execute(command,arguments_,{cwd:repositoryRoot,
        env:namespace===undefined?{PATH:'/usr/bin:/bin',LANG:'C'}:process.env,maxBuffer:2*1024*1024});
      return {code:0,signal:null,...result};
    } catch(error) {return {code:error.code,signal:error.signal,stdout:error.stdout,stderr:error.stderr};}
  })()});
  await installNativeApplicationBundle({repositoryRoot,root,applicationRuntimeRoot,applicationBundleInputRoot,
    applicationExecutable:join(repositoryRoot,'_build/native/debug/build/cmd/native_remote_application_site/native_remote_application_site.exe'),
    runtimeControl,runtimeKeys,publicKey:runtimeKeys.publicKey.export({type:'spki',format:'pem'}),targetTriple,runCaptured});
  console.log('Original Native HTTP application bundle install and activation passed (2 commands)');
  passed=true;
} finally {
  if(passed && process.env.ACTQL_TEST_PRESERVE_SCRATCH!=='1')await rm(root,{recursive:true,force:true});
  else console.error('Original application bundle scratch retained: '+root);
}
