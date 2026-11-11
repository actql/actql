import assert from 'node:assert/strict';
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {runCodeInspection as run,readNativeSymbols} from './native-code-inspection.mjs';
import {hash} from '../../inventory.mjs';
import {inspectParentReferenceCode,referenceHelpers,referenceResultMap} from './parent-reference-sites.mjs';
import {inspectParentCaptureCode} from './parent-capture-sites.mjs';
import {inspectParentCaptureArm64} from './parent-capture-arm64.mjs';
import {inspectParentReferenceArm64,arm64ReferenceHelpers} from './parent-reference-arm64.mjs';
import {nativeFunctionEntries,disassembleNativeRanges} from './native-code-disassembly.mjs';
import {nativeArtifactPath} from './provider-callback-code.mjs';

const nm='/usr/bin/nm';
const supported=['linux-x64','darwin-arm64'];
const unresolvedReason='primitive Ref code decoder currently covers linux-x64 and darwin-arm64 only';
const toolsFor=platform=>platform==='darwin-arm64'
  ? {objdump:'/Library/Developer/CommandLineTools/usr/bin/llvm-objdump',helpers:arm64ReferenceHelpers,
    calls:['_moonbit_malloc','_moonbit_incref','_moonbit_decref','_actql_proof_current_chain_start']}
  : {objdump:'/usr/bin/objdump',helpers:referenceHelpers,calls:['moonbit_malloc','moonbit_incref','moonbit_decref',referenceResultMap,'actql_proof_current_chain_start']};
const parentName=name=>/connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(name);
const dir='.artifacts/relation-pipeline/current-chain-native/code';
function generated(object,exe,platform) {
  const {objdump,helpers,calls}=toolsFor(platform);
  const selection={names:[...helpers,...calls,platform==='darwin-arm64'?'_moonbit_decref':'moonbit_decref'],
    suffixes:['managed__provider__execution__with__child__work__issue',...(platform==='darwin-arm64'?['relation__chain__reclaimed__prefix']:[])]};
  const exeEntries=nativeFunctionEntries(readNativeSymbols(nm,['-n',exe],selection)),
    objectEntries=nativeFunctionEntries(readNativeSymbols(nm,['-n',object],selection));
  const parent=exeEntries.filter(m=>parentName(m[2]));assert.equal(parent.length,1,'Missing unique actual parent');
  const selected=[parent[0][2],...helpers,...calls,
    ...(platform==='darwin-arm64'?exeEntries.filter(m=>/(?:relation__chain__reclaimed__prefix|managed__provider__execution__with__child__work__issue)$/.test(m[2])).map(m=>m[2]):[])];
  const symbols=selected.map(name=>{
    const matches=exeEntries.filter(m=>m[2]===name);assert.equal(matches.length,1,'Missing unique executed Ref code symbol');
    return `${matches[0][1]} T ${name}`;
  }).join('\n')+'\n';
  function dump(file,all,names,relocation) {
    if(platform==='darwin-arm64') {
      const raw=run(objdump,[...(relocation?['--reloc']:[]),`--disassemble-symbols=${names.join(',')}`,'--no-show-raw-insn',file]);
      assert(raw.includes('Disassembly of section'),'Missing ARM64 Ref disassembly');
      return raw.slice(raw.indexOf('Disassembly of section'));
    }
    return disassembleNativeRanges(run,objdump,file,all,names,relocation);
  }
  const captureSymbols=exeEntries.filter(m=>(m[2]===(platform==='darwin-arm64'?'_moonbit_decref':'moonbit_decref') || m[2].startsWith(parent[0][2]+'C') || /managed__provider__execution__with__child__work__issue$/.test(m[2])) && !selected.includes(m[2]))
    .map(m=>`${m[1]} T ${m[2]}`).join('\n')+'\n';
  return {symbols,captureSymbols,object:dump(object,objectEntries,[parent[0][2]],true),
    linked:dump(exe,exeEntries,[parent[0][2],...helpers],false)};
}
export function collectParentReferenceCode(root,runtime,callbackCode) {
  if(!supported.includes(runtime.platform)) return {status:'unresolved',reason:unresolvedReason};
  const {objdump}=toolsFor(runtime.platform);
  assert.equal(callbackCode.status,'established','Missing independently archived Native object');
  assert.equal(callbackCode.platform,runtime.platform);
  const object=join(root,callbackCode.archive),exe=join(root,'_build/native/debug/test/connectors/local/local.whitebox_test.exe');
  assert.equal(hash(readFileSync(object)),callbackCode.objectDigest,'Native object changed before Ref collection');
  const code=generated(object,exe,runtime.platform),logs={};
  for(const key of ['symbols','object','linked']) {
    const text=code[key];
    const digest=hash(text),path=`${dir}/${digest}.parent-ref-${key}`;
    if(!existsSync(join(root,path)))writeFileSync(join(root,path),text,{flag:'wx'});
    assert.equal(hash(readFileSync(join(root,path))),digest);logs[key]={path,digest};
  }
  return {status:'established',platform:runtime.platform,objectDigest:callbackCode.objectDigest,archive:callbackCode.archive,logs,
    tools:{nm:hash(readFileSync(nm)),objdump:hash(readFileSync(objdump))}};
}
export function auditParentReferenceCode(report,start,root,read) {
  const proof=report.parentReferenceCode;assert(proof,'Missing primitive Ref code correspondence status');
  if(proof.status==='unresolved') {
    assert(!supported.includes(report.runtime.platform),'Supported primitive Ref correspondence missing');
    assert.deepEqual(proof,{status:'unresolved',reason:unresolvedReason});
    return {status:'unresolved',completePhysicalLifetimeUpper:false};
  }
  assert.equal(proof.status,'established');assert(supported.includes(proof.platform),'Unsupported established Ref platform');assert.equal(proof.platform,report.runtime.platform);
  const {objdump}=toolsFor(proof.platform);
  assert.equal(proof.objectDigest,report.providerCallbackCode.objectDigest);assert.equal(proof.archive,report.providerCallbackCode.archive);
  assert.equal(hash(read(proof.archive)),proof.objectDigest,'Primitive Ref object changed');
  assert.deepEqual(proof.tools,{nm:hash(readFileSync(nm)),objdump:hash(readFileSync(objdump))},'Ref inspection tool changed');
  const exe=report.archives['_build/native/debug/test/connectors/local/local.whitebox_test.exe'];assert(exe,'Missing executed Ref binary');
  const regenerated=generated(nativeArtifactPath(root,read,proof.archive),
    nativeArtifactPath(root,read,exe),proof.platform);
  for(const key of ['symbols','object','linked']) {
    const text=regenerated[key];
    const entry=proof.logs[key];assert.match(entry.digest,/^[a-f0-9]{64}$/);
    assert.equal(entry.path,`${dir}/${entry.digest}.parent-ref-${key}`);
    const original=read(entry.path);assert.equal(hash(original),entry.digest);assert.equal(original.toString(),text,'Ref code observations differ from actual archived bytes');
  }
  const inspect=proof.platform==='darwin-arm64'?inspectParentReferenceArm64:inspectParentReferenceCode;
  const result=inspect(start,regenerated.symbols,regenerated.object,regenerated.linked);
  assert(result.references.every(r=>r.requestedBytes<=16),'Primitive Ref exceeds conditional component');
  const captures=proof.platform==='darwin-arm64'?inspectParentCaptureArm64:inspectParentCaptureCode;
  return {...result,captures:captures(start,regenerated.symbols+regenerated.captureSymbols,regenerated.object,regenerated.linked)};
}
