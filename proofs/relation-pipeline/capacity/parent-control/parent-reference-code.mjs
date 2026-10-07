import assert from 'node:assert/strict';
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {hash} from '../../inventory.mjs';
import {inspectParentReferenceCode,referenceHelpers} from './parent-reference-sites.mjs';

const nm='/usr/bin/nm',objdump='/usr/bin/objdump';
const parentName=name=>/connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(name);
const dir='.artifacts/relation-pipeline/current-chain-native/code';
function run(tool,args) {
  const r=spawnSync(tool,args,{encoding:'utf8',timeout:30000,maxBuffer:32*1024*1024});
  assert(!r.error && r.status===0,r.stderr||String(r.error));return r.stdout;
}
function entries(text) {
  return text.split('\n').map(l=>l.match(/^([0-9a-f]+)\s+[tT]\s+(\S+)$/))
    .filter(m=>m && !m[2].startsWith('.') && !m[2].includes('$bb'));
}
function generated(object,exe) {
  const exeEntries=entries(run(nm,['-n',exe])),objectEntries=entries(run(nm,['-n',object]));
  const parent=exeEntries.filter(m=>parentName(m[2]));assert.equal(parent.length,1,'Missing unique actual parent');
  const tools=['moonbit_malloc','moonbit_incref','actql_proof_current_chain_start'];
  const selected=[parent[0][2],...referenceHelpers,...tools];
  const symbols=selected.map(name=>{
    const matches=exeEntries.filter(m=>m[2]===name);assert.equal(matches.length,1,'Missing unique executed Ref code symbol');
    return `${matches[0][1]} T ${name}`;
  }).join('\n')+'\n';
  function dump(file,all,names,relocation) {
    return names.map(name=>{
      const found=all.filter(m=>m[2]===name);assert.equal(found.length,1,'Missing unique Ref function range');
      const start=BigInt('0x'+found[0][1]),next=all.find(m=>BigInt('0x'+m[1])>start);assert(next,'Missing Ref function range end');
      const raw=run(objdump,['-d','-Mintel','--section=.text','--no-show-raw-insn',...(relocation?['-r']:[]),
        `--start-address=0x${found[0][1]}`,`--stop-address=0x${next[1]}`,file]);
      assert(raw.includes('Disassembly of section'),'Missing Ref disassembly');return raw.slice(raw.indexOf('Disassembly of section'));
    }).join('\n');
  }
  return {symbols,object:dump(object,objectEntries,[parent[0][2]],true),
    linked:dump(exe,exeEntries,[parent[0][2],...referenceHelpers],false)};
}
export function collectParentReferenceCode(root,runtime,callbackCode) {
  if(runtime.platform!=='linux-x64') return {status:'unresolved',reason:'primitive Ref code decoder currently covers linux-x64 only'};
  assert.equal(callbackCode.status,'established','Missing independently archived Native object');
  assert.equal(callbackCode.platform,runtime.platform);
  const object=join(root,callbackCode.archive),exe=join(root,'_build/native/debug/test/connectors/local/local.whitebox_test.exe');
  assert.equal(hash(readFileSync(object)),callbackCode.objectDigest,'Native object changed before Ref collection');
  const code=generated(object,exe),logs={};
  for(const [key,text] of Object.entries(code)) {
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
    assert.notEqual(report.runtime.platform,'linux-x64','Supported primitive Ref correspondence missing');
    assert.deepEqual(proof,{status:'unresolved',reason:'primitive Ref code decoder currently covers linux-x64 only'});
    return {status:'unresolved',completePhysicalLifetimeUpper:false};
  }
  assert.equal(proof.status,'established');assert.equal(proof.platform,'linux-x64');assert.equal(proof.platform,report.runtime.platform);
  assert.equal(proof.objectDigest,report.providerCallbackCode.objectDigest);assert.equal(proof.archive,report.providerCallbackCode.archive);
  assert.equal(hash(read(proof.archive)),proof.objectDigest,'Primitive Ref object changed');
  assert.deepEqual(proof.tools,{nm:hash(readFileSync(nm)),objdump:hash(readFileSync(objdump))},'Ref inspection tool changed');
  const exe=report.archives['_build/native/debug/test/connectors/local/local.whitebox_test.exe'];assert(exe,'Missing executed Ref binary');
  const regenerated=generated(join(root,proof.archive),join(root,exe));
  for(const [key,text] of Object.entries(regenerated)) {
    const entry=proof.logs[key];assert.match(entry.digest,/^[a-f0-9]{64}$/);
    assert.equal(entry.path,`${dir}/${entry.digest}.parent-ref-${key}`);
    const original=read(entry.path);assert.equal(hash(original),entry.digest);assert.equal(original.toString(),text,'Ref code observations differ from actual archived bytes');
  }
  const result=inspectParentReferenceCode(start,regenerated.symbols,regenerated.object,regenerated.linked);
  assert(result.references.every(r=>r.requestedBytes<=16),'Primitive Ref exceeds conditional component');
  return result;
}
