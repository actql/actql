import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,symlinkSync,rmSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {verifyWorkspacePackageLinks,assertSourceRuntimeReceiptCurrent,assertSameSourceRuntimeModel} from './verify-local-source-runtime.mjs';
test('source harness rejects an old workspace dependency, not just entry path',()=>{
 const root=mkdtempSync(join(tmpdir(),'actql-coherence-'));
 try{
  for(const path of ['current/packages/sdk','old/packages/sdk','current/node_modules/@actql'])mkdirSync(join(root,path),{recursive:true});
  const link=join(root,'current/node_modules/@actql/sdk');
  symlinkSync(join(root,'old/packages/sdk'),link);
  assert.throws(()=>verifyWorkspacePackageLinks(join(root,'current')),/ForeignActqlWorkspacePackage:sdk/);
  rmSync(link);symlinkSync(join(root,'current/packages/sdk'),link);
  assert.equal(verifyWorkspacePackageLinks(join(root,'current')),join(root,'current'));
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('a separately current calculator with a different cost model cannot explain a runtime debit',()=>{
 const root=mkdtempSync(join(tmpdir(),'actql-model-coherence-'));
 try{
  const receipt=(name,model)=>{
   const directory=join(root,name);
   mkdirSync(join(directory,'node_modules/@actql'),{recursive:true});
   writeFileSync(join(directory,'model.js'),model);
   return {root:directory,nodeVersion:process.version,moonVersion:'fixture',selectedRuntimes:1,
    files:[{path:'model.js',sha256:createHash('sha256').update(model).digest('hex')}]};
  };
  const runtime=receipt('runtime','v1'),calculator=receipt('calculator','v2');
  assertSourceRuntimeReceiptCurrent(runtime);
  assertSourceRuntimeReceiptCurrent(calculator);
  assert.throws(()=>assertSameSourceRuntimeModel(runtime,calculator),/SourceRuntimeModelMismatch/);
  const same=receipt('same','v1');
  assertSameSourceRuntimeModel(runtime,same);
  assert.throws(()=>assertSameSourceRuntimeModel(runtime,{...same,moonVersion:'different'}),/SourceRuntimeModelMismatch:moonVersion/);
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('source harness rejects a changed compiled/module hash during execution',()=>{
 const root=mkdtempSync(join(tmpdir(),'actql-coherence-hash-'));
 try{
  mkdirSync(join(root,'node_modules/@actql'),{recursive:true});
  writeFileSync(join(root,'runtime.js'),'original');
  const receipt={root,files:[{path:'runtime.js',sha256:createHash('sha256').update('original').digest('hex')}]};
  assertSourceRuntimeReceiptCurrent(receipt);
  writeFileSync(join(root,'runtime.js'),'changed');
  assert.throws(()=>assertSourceRuntimeReceiptCurrent(receipt),/SourceRuntimeChangedDuringTest:runtime.js/);
 }finally{rmSync(root,{recursive:true,force:true});}
});
