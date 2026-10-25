import {readdirSync,realpathSync,readFileSync,writeFileSync,existsSync} from 'node:fs';
import {join,resolve,relative,sep} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

export function verifyWorkspacePackageLinks(root) {
 root=realpathSync(root);
 for(const name of readdirSync(join(root,'node_modules/@actql'))){
  const expected=realpathSync(join(root,'packages',name));
  const actual=realpathSync(join(root,'node_modules/@actql',name));
  if(actual!==expected)throw new Error(`ForeignActqlWorkspacePackage:${name}:${actual}`);
 }
 return root;
}

export function assertSourceRuntimeReceiptCurrent(receipt) {
 verifyWorkspacePackageLinks(receipt.root);
 for(const item of receipt.files){
  const actual=createHash('sha256').update(readFileSync(join(receipt.root,item.path))).digest('hex');
  if(actual!==item.sha256)throw new Error(`SourceRuntimeChangedDuringTest:${item.path}`);
 }
}

// A separate calculator is not evidence for a runtime merely because its
// formula has the same name. Require the complete guarded model cohort,
// including adapters and compiled artifacts, before comparing its numbers.
export function assertSameSourceRuntimeModel(runtimeReceipt, calculatorReceipt) {
 assertSourceRuntimeReceiptCurrent(runtimeReceipt);
 assertSourceRuntimeReceiptCurrent(calculatorReceipt);
 for(const key of ['nodeVersion','moonVersion','selectedRuntimes']){
  if(runtimeReceipt[key]!==calculatorReceipt[key])throw new Error(`SourceRuntimeModelMismatch:${key}`);
 }
 if(JSON.stringify(runtimeReceipt.files)!==JSON.stringify(calculatorReceipt.files)){
  throw new Error('SourceRuntimeModelMismatch:source-or-compiled-inventory');
 }
}

// Source-only diagnostic harness: rebuild every selected runtime from this
// tree, then require canonical generated assets AND adapter graphs to match.
// A matching entry-module path alone cannot establish dependency coherence.
export async function verifyLocalSourceRuntime(root, receiptPath) {
 root=verifyWorkspacePackageLinks(root);
 const {localNodePackageInputs}=await import(pathToFileURL(join(root,'scripts/local-node-package-inputs.mjs')));
 const inputs=localNodePackageInputs(root);
 const moon=process.env.ACTQL_MOON??(process.env.MOON_HOME?join(process.env.MOON_HOME,'bin/moon'):'moon');
 for(const runtime of inputs.runtimeFiles){
  const pkg=runtime.slice(0,runtime.lastIndexOf('/'));
  execFileSync(moon,['build','--target','js','--release',`src/${pkg}`],{cwd:root,stdio:['ignore','ignore','pipe']});
 }
 for(const script of ['build-local-node-assets.mjs','build-local-node-adapters.mjs']){
  execFileSync(process.execPath,[join(root,'scripts',script),'--check'],{cwd:root,stdio:['ignore','ignore','pipe']});
 }
 verifyWorkspacePackageLinks(root);
 const records=[];
 const digest=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
 function inventory(directory){
  for(const item of readdirSync(directory,{withFileTypes:true})){
   if(['node_modules','.git','_build'].includes(item.name))continue;
   const file=join(directory,item.name);
   if(item.isSymbolicLink())throw new Error(`UnexpectedSourceSymlink:${file}`);
   if(item.isDirectory())inventory(file);
   else if(item.isFile())records.push({path:relative(root,file).split(sep).join('/'),sha256:digest(file)});
  }
 }
 for(const directory of ['src','adapters','packages','scripts'])inventory(join(root,directory));
 for(const name of ['package.json','package-lock.json','moon.mod','moon.mod.json','moon.work','moon.work.json','moon.lock','.npmrc'])if(existsSync(join(root,name)))records.push({path:name,sha256:digest(join(root,name))});
 for(const file of inputs.runtimeFiles){
  for(const prefix of ['_build/js/release/build','packages/local-node/_build/js/release/build']){
   const full=join(root,prefix,file);records.push({path:relative(root,full).split(sep).join('/'),sha256:digest(full)});
  }
 }
 records.sort((a,b)=>a.path.localeCompare(b.path));
 const receipt={kind:'source-export-runtime-coherence/v1',root,nodeVersion:process.version,moonVersion:execFileSync(moon,['version'],{cwd:root,encoding:'utf8'}).trim(),selectedRuntimes:inputs.runtimeFiles.length,
  canonicalCoreAssets:true,canonicalAdapters:true,workspaceLinks:true,
  sourceTreeDigest:createHash('sha256').update(JSON.stringify(records)).digest('hex'),files:records};
 if(receiptPath)writeFileSync(receiptPath,JSON.stringify(receipt,null,2)+'\n');
 return receipt;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const receipt=await verifyLocalSourceRuntime(process.argv[2]??resolve('.'),process.argv[3]);
 console.log(JSON.stringify({root:receipt.root,runtimes:receipt.selectedRuntimes,files:receipt.files.length,digest:receipt.sourceTreeDigest}));
}
