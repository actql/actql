import test from 'node:test';
import assert from 'node:assert/strict';
import {scalarSitesX64} from './provider-callback-x64.mjs';
import {inspectScalarCode,providerConstructors} from './provider-callback-code.mjs';
// Independent object/executable pair with a basic-block label and relocation
// fields inside variable-length instructions. These are not product outputs.
const object=`0000000000000100 <factory>:
 100: push rbp
0000000000000101 <.factory$bb0>:
 101: movabs rdi,0x8
 10b: call 110 <.factory$bb0>
 10c: R_X86_64_PLT32 moonbit_malloc-0x4
 110: mov r13,rax
 113: mov r10d,0x0
 119: mov DWORD PTR [r13-0x4],r10d
 11d: lea r10,[rip+0x0]
 120: R_X86_64_PC32 callback-0x4
 124: mov QWORD PTR [r13+0x0],r10
 128: ret
`;
const linked=object.replaceAll('R_X86_64_PLT32 moonbit_malloc-0x4','').replaceAll('R_X86_64_PC32 callback-0x4','')
  .replace(/^\s*10c:.*\n/gm,'').replace(/^\s*120:.*\n/gm,'')
  .replace('call 110 <.factory$bb0>','call 4000 <moonbit_malloc>').replace('rip+0x0','rip+0x1efc');
const symbols='100 T factory\n2020 T callback\n4000 T moonbit_malloc\n5000 T actql_proof_provider_construction\n';
const facts=()=>[{indexedBytes:100,scalarDynamicCallbacks:1,scalarCodes:[{identity:'abcd',codeDelta:'-12256'}]}];
const check=(o=object,l=linked,f=facts(),s=symbols)=>inspectScalarCode(f,s,o,l,'linux-x64');
test('GNU object and linked instructions establish only the observed requested extent',()=>{
  const result=check(); assert.equal(result.maxPointRequestedBytes,116);
  const site=result.observations[0].callbacks[0];
  assert.equal(site.constructor,'factory');assert.equal(site.allocationOffset,'11');
  assert.equal(site.payloadBytes,8);assert.equal(site.headerBytes,8);
  assert.equal(result.scalarPayloadBytesMeasured,false);assert.equal(result.completeConstructorLifetimeUpper,false);
  assert.equal(result.completeParentUpper,false);assert.equal(result.completePipelineUpper,false);
});
test('32-bit zero, descriptor position and code store are all required',()=>{
  for(const [a,b] of [['mov r10d,0x0','mov r10d,0x1'],['r13-0x4','r13-0x8'],
    ['QWORD PTR [r13+0x0]','QWORD PTR [r13+0x8]'],['r10d,0x0','r10,0x0']])
    assert.throws(()=>check(object.replace(a,b)),/site sets|allocation site/);
});
test('unknown requests and non-code-pointer-only requests do not get guessed sizes',()=>{
  assert.throws(()=>check(object.replace('movabs rdi,0x8','mov rdi,rbx')),/site sets|allocation site/);
  assert.throws(()=>scalarSitesX64(object.replace('movabs rdi,0x8','movabs rdi,0x10')),/request/);
});
test('relocation must be inside its instruction and of the expected kind',()=>{
  for(const [a,b] of [['10c: R_','110: R_'],['10c: R_','10a: R_'],
    ['PLT32 moonbit_malloc','PC32 moonbit_malloc'],['PC32 callback-0x4','PC32 callback+0x4']])
    assert.throws(()=>scalarSitesX64(object.replace(a,b)),/relocation/);
});
test('inserting another instruction breaks the contiguous allocation evidence',()=>{
  assert.throws(()=>check(object.replace('113: mov','112: call 6000\n 113: mov')),/site sets|allocation site/);
});
test('linked callback target, header and malloc must correspond to object sites',()=>{
  for(const [a,b] of [['rip+0x1efc','rip+0x1efd'],['call 4000','call 4001'],['r10d,0x0','r10d,0x1']])
    assert.throws(()=>check(object,linked.replace(a,b)),/site sets|executed binary/);
});
test('signed RIP displacement is resolved from the next instruction',()=>{
  const s=symbols.replace('2020 T callback','20 T callback');const f=facts(); f[0].scalarCodes[0].codeDelta='-20448';
  assert.equal(check(object,linked.replace('rip+0x1efc','rip-0x104'),f,s).maxPointRequestedBytes,116);
});
test('allocation identities and observer anchor remain independent mandatory evidence',()=>{
  const f=facts();f[0].scalarDynamicCallbacks=2;f[0].scalarCodes.push({...f[0].scalarCodes[0]});
  assert.throws(()=>check(object,linked,f),/Repeated scalar/);
  assert.throws(()=>check(object,linked,facts(),symbols.replace(/5000.*\n/,'')),/anchor/);
  assert.throws(()=>inspectScalarCode(facts(),symbols,object,linked,'linux-arm64'),/Unsupported/);
});
test('constructor scope excludes lifecycle functions with matching name suffixes',()=>{
  const prefix='_M0FP45actql5actql10connectors5local';
  const wanted=['values__provider','managed__provider','managed__provider__with__inputs',
    'managed__provider__with__numeric','selected__relation__provider_2einner'];
  const names=wanted.map(n=>`${prefix}${n.length}${n}`);
  assert.deepEqual(providerConstructors([...names,`${prefix}25cleanup__managed__provider`],['values_provider']),names);
  assert.throws(()=>providerConstructors(names.slice(1),['values_provider']),/Missing/);
});
