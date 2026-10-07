import test from 'node:test';
import assert from 'node:assert/strict';
import {auditParentReferenceCode} from './parent-reference-code.mjs';
import {inspectParentReferenceCode,referenceHelpers} from './parent-reference-sites.mjs';
const parent='_M0FP45actql5actql10connectors5local42bounded__relation__chain__execution__state';
const addresses=new Map([[referenceHelpers[0],0x4000],[referenceHelpers[1],0x5000],[referenceHelpers[2],0x6000],
  ['moonbit_malloc',0x7000],['actql_proof_current_chain_start',0x8000]]);
const slots=['0x60','0x68','0x70','0x78','0x80'];
const types=[referenceHelpers[0],referenceHelpers[1],referenceHelpers[1],referenceHelpers[1],referenceHelpers[2]];
const values=['movabs rdi,0x0','mov edi,0x0','mov edi,0x0','mov edi,0x0','mov edi,0xffffffff'];
const ops=types.flatMap((name,i)=>[values[i],{call:name},'mov rdi,rax','mov rax,rdi',`mov QWORD PTR [rbp-${slots[i]}],rax`]);
ops.push('mov rax,QWORD PTR [rbp-0x80]','mov QWORD PTR [rsp],rax',
  'mov rdi,QWORD PTR [rbp-0x90]','mov rsi,QWORD PTR [rbp-0x50]',
  ...['rdx','rcx','r8','r9'].map((r,i)=>`mov ${r},QWORD PTR [rbp-${slots[i]}]`),
  {call:'actql_proof_current_chain_start'},'ret');
function assembly(name,start,ops,object=false) {
  let address=start;let text=`${address.toString(16)} <${name}>:\n`;
  for(const op of ops) {
    const at=address.toString(16);
    if(op.call) {
      text+=`${at}: call ${object?at:addresses.get(op.call).toString(16)}\n`;
      if(object) text+=`${(address+1).toString(16)}: R_X86_64_PLT32 ${op.call}-0x4\n`;
      address+=5;
    } else {text+=`${at}: ${op}\n`;address+=10;}
  }
  return text;
}
function helper(name) {
  const wide=name===referenceHelpers[0];
  return assembly(name,addresses.get(name),['push rbp','mov rbp,rsp','sub rsp,0x10','mov QWORD PTR [rbp-0x8],rbx',
    wide?'mov rbx,rdi':'mov ebx,edi',wide?'movabs rdi,0x8':'movabs rdi,0x4',
    {call:'moonbit_malloc'},'mov rdi,rax','mov r10d,0x0','mov DWORD PTR [rdi-0x4],r10d',
    wide?'mov QWORD PTR [rdi],rbx':'mov DWORD PTR [rdi],ebx','nop','mov rax,rdi',
    'mov rbx,QWORD PTR [rbp-0x8]','mov rsp,rbp','pop rbp','ret','nop']);
}
const object=assembly(parent,0x100,ops,true),linked=assembly(parent,0x1000,ops)+referenceHelpers.map(helper).join('');
const symbols=[...addresses].map(([name,address])=>`${address.toString(16)} T ${name}`).join('\n');
const startup=()=>({roots:{used:'10',cancelled:'20',terminal:'30',reclaimed:'40',cleanupIndex:'50'}});
const check=(o=object,l=linked,s=startup(),nm=symbols)=>inspectParentReferenceCode(s,nm,o,l);
test('allocation requests are tied through private custody slots to actual observer arguments',()=>{
  const r=check();assert.equal(r.pointRequestedBytes,64);
  assert.deepEqual(r.references.map(s=>s.requestedBytes),[16,12,12,12,12]);
  assert.deepEqual(r.references.map(s=>s.identity),['10','20','30','40','50']);
  assert.equal(r.payloadBytesMeasured,false);assert.equal(r.completePhysicalLifetimeUpper,false);
});
test('wrong typed helper, initializer, call count or lost return alias rejects',()=>{
  for(const [a,b] of [[referenceHelpers[0],referenceHelpers[2]],['movabs rdi,0x0','movabs rdi,0x1'],
    ['mov rdi,rax','mov rdi,rbx'],['mov rax,rdi','mov rax,rsi']]) assert.throws(()=>check(object.replace(a,b)));
  const fewer=ops.filter((_,i)=>i<5||i>=10);assert.throws(()=>check(assembly(parent,0x100,fewer,true)),/call count/);
});
test('replacement and partial overlapping writes cannot preserve Ref custody',()=>{
  for(const op of ['mov QWORD PTR [rbp-0x60],rdi','mov DWORD PTR [rbp-0x5c],eax','mov BYTE PTR [rbp-0x59],al']) {
    const changed=[...ops];changed.splice(25,0,op);
    assert.throws(()=>check(assembly(parent,0x100,changed,true)),/custody overwritten/);
  }
});
test('substituting register or stack observer arguments rejects',()=>{
  for(const [a,b] of [['mov rdx,QWORD PTR [rbp-0x60]','mov rdx,QWORD PTR [rbp-0x68]'],
    ['mov rax,QWORD PTR [rbp-0x80]\n','mov rax,QWORD PTR [rbp-0x78]\n']]) assert.throws(()=>check(object.replace(a,b)),/substitution/);
  const changed=[...ops];changed.splice(27,0,'mov DWORD PTR [rsp+0x4],eax');
  assert.throws(()=>check(assembly(parent,0x100,changed,true)),/stack overwritten/);
});
test('helper header, payload width, returned identity and allocation call are required',()=>{
  for(const [a,b] of [['movabs rdi,0x4','movabs rdi,0x8'],['mov r10d,0x0','mov r10d,0x1'],
    ['mov DWORD PTR [rdi],ebx','mov QWORD PTR [rdi],rbx'],['mov rax,rdi\n','mov rax,rbx\n'],['call 7000','call 7001']])
    assert.throws(()=>check(object,assembly(parent,0x1000,ops)+(referenceHelpers.map(helper).join('').replace(a,b))),/allocation\/return sequence/);
});
test('frame escape, unknown control flow and branch entry into custody reject',()=>{
  for(const op of ['lea rax,[rbp-0x60]','mov rax,rbp','mov rsp,rax','jmp 300','je 300']) {
    const changed=[...ops];changed.splice(26,0,op);assert.throws(()=>check(assembly(parent,0x100,changed,true)),/frame|instruction|branch/);
  }
  assert.throws(()=>check(assembly(parent,0x100,['je 120',...ops],true)),/External branch/);
  assert.throws(()=>check(assembly(parent,0x100,['lea rax,[rbp-0x60]',...ops],true)),/escaped before construction/);
});
test('same-size live identity alias, absent symbol and detached relocation reject',()=>{
  const s=startup();s.roots.terminal=s.roots.cancelled;assert.throws(()=>check(object,linked,s),/identities alias/);
  assert.throws(()=>check(object,linked,startup(),symbols.replace(/7000.*\n/,'')),/allocation\/return sequence/);
  assert.throws(()=>check(object.replace('10b: R_','1ff: R_')),/Detached/);
});
test('object and executed caller cannot silently differ in Ref roles',()=>{
  assert.throws(()=>check(object,linked.replace('mov edi,0xffffffff','mov edi,0x0')),/initialization/);
  assert.throws(()=>check(object,linked.replaceAll('rbp-0x68','rbp-0x88')),/correspondence differs/);
});

test('missing or unsupported correspondence cannot become an established extent',()=>{
  const noRead=()=>{throw Error('Unresolved platform must not inspect an artifact');};
  assert.throws(()=>auditParentReferenceCode({runtime:{platform:'linux-x64'}},startup(),'/unused',noRead),/Missing primitive/);
  const proof={status:'unresolved',reason:'primitive Ref code decoder currently covers linux-x64 only'};
  assert.throws(()=>auditParentReferenceCode({runtime:{platform:'linux-x64'},parentReferenceCode:proof},startup(),'/unused',noRead),/Supported/);
  assert.deepEqual(auditParentReferenceCode({runtime:{platform:'darwin-arm64'},parentReferenceCode:proof},startup(),'/unused',noRead),
    {status:'unresolved',completePhysicalLifetimeUpper:false});
});
