import assert from 'node:assert/strict';
import {codeSymbols} from './provider-callback-code.mjs';

export const referenceHelpers=['_M0MPC13ref3Ref3RefGlE','_M0MPC13ref3Ref3RefGbE','_M0MPC13ref3Ref3RefGiE'];
export const referenceResultMap='_M0MPC16result6Result3mapGRP45actql5actql10connectors5local24ManagedProviderExecutionRP35actql5actql14connector__sdk17FixedComputeIssueURP45actql5actql10connectors5local24ManagedProviderExecutionRP45actql5actql10connectors5local27RelationChainExecutionStateEE';
const observer='actql_proof_current_chain_start';
const roles=['used','cancelled','terminal','reclaimed','cleanupIndex'];
const helperRoles=[referenceHelpers[0],referenceHelpers[1],referenceHelpers[1],referenceHelpers[1],referenceHelpers[2]];
const initializers=['movabs rdi,0x0','mov edi,0x0','mov edi,0x0','mov edi,0x0','mov edi,0xffffffff'];
const parentName=name=>/connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(name);
// Partial register writes also change the full x64 frame address. Include
// frame aliases and frame registers used as an index in an escaped address.
const frameRegisters='(?:rbp|ebp|bp|bpl|rsp|esp|sp|spl)';
const frameDestination=new RegExp('^(?:mov|movabs|lea) '+frameRegisters+',');
const frameSource=new RegExp('^(?:mov|movabs) .+,'+frameRegisters+'$');
const frameLea=new RegExp('^lea .*\\[[^\\]]*\\b'+frameRegisters+'\\b');

function functions(text) {
  const functions=new Map(); let current;
  for(const line of text.split('\n')) {
    const fn=line.match(/^([0-9a-f]+) <([^>]+)>:$/);
    if(fn) {
      if(fn[2].startsWith('.') || fn[2].includes('$bb')) continue;
      assert(!functions.has(fn[2]),'Duplicate inspected function');
      current={start:BigInt('0x'+fn[1]),instructions:[]};functions.set(fn[2],current);continue;
    }
    const relocation=line.match(/^\s*([0-9a-f]+):\s+R_X86_64_(PLT32|PC32)\s+(\S+)-0x4$/);
    if(relocation) {
      const ins=current?.instructions.at(-1);assert(ins && !ins.relocation,'Detached or duplicate Ref relocation');
      ins.relocation={address:BigInt('0x'+relocation[1]),kind:relocation[2],symbol:relocation[3]};continue;
    }
    assert(!line.includes('R_X86_64_'),'Unsupported Ref relocation');
    const m=line.match(/^\s*([0-9a-f]+):\s+([a-z][a-z0-9.]*)\s*(.*)$/);
    if(m) {
      assert(current,'Instruction outside inspected function');
      const address=BigInt('0x'+m[1]);const last=current.instructions.at(-1);
      assert(!last || address>last.address,'Unordered Ref instructions');
      if(last?.relocation) assert(last.relocation.address>=last.address && last.relocation.address<address,'Detached Ref relocation');
      current.instructions.push({address,op:`${m[2]} ${m[3].split('#')[0].split(' <')[0].trim()}`.trim().replace(/\s+/g,' ').replace(/,\s*/g,',')});
    }
  }
  for(const f of functions.values()) assert(!f.instructions.at(-1)?.relocation,'Incomplete Ref relocation instruction');
  return functions;
}
function target(ins,symbols) {
  if(!ins.op.startsWith('call ')) return;
  if(ins.relocation) {assert.equal(ins.relocation.kind,'PLT32','Wrong Ref call relocation');return ins.relocation.symbol;}
  const m=ins.op.match(/^call ([0-9a-f]+)$/);
  if(m && symbols) {
    const names=[...symbols].filter(([,v])=>v===BigInt('0x'+m[1])).map(([name])=>name);
    assert(names.length<=1,'Ambiguous executed Ref call target');return names[0];
  }
}
function helperExtent(name,fn,symbols) {
  assert(fn,'Missing executed primitive Ref constructor');
  const wide=name===referenceHelpers[0],payload=wide?8:4;
  const expected=['push rbp','mov rbp,rsp','sub rsp,0x10','mov QWORD PTR [rbp-0x8],rbx',
    wide?'mov rbx,rdi':'mov ebx,edi',`movabs rdi,0x${payload}`,'call moonbit_malloc',
    'mov rdi,rax','mov r10d,0x0','mov DWORD PTR [rdi-0x4],r10d',
    wide?'mov QWORD PTR [rdi],rbx':'mov DWORD PTR [rdi],ebx',
    'mov rax,rdi','mov rbx,QWORD PTR [rbp-0x8]','mov rsp,rbp','pop rbp','ret'];
  const actual=fn.instructions.filter(i=>i.op!=='nop').map(i=>i.op.startsWith('call ')?`call ${target(i,symbols)}`:i.op);
  assert.deepEqual(actual,expected,'Unreviewed primitive Ref allocation/return sequence');
  return {helper:name,payloadBytes:payload,headerBytes:8,requestedBytes:payload+8};
}
// The direct observer's existing Result match introduces this one typed
// Ok/pair branch. Recognize it as a whole; no generic bit-op/jump allowance.
function resultObserverBranch(ins,begin,end,sites,symbols) {
  const masks=ins.flatMap((i,k)=>k>=begin&&k<end&&i.op==='and edi,0xff'?[k]:[]);
  if(!masks.length)return new Set();
  assert.equal(masks.length,1,'Repeated Result observer discriminator');
  const k=masks[0]-1;
  const equal=(at,op)=>assert.equal(ins[at]?.op,op,'Unreviewed Result observer branch');
  const call=(at,name)=>assert.equal(target(ins[at],symbols),name,'Unreviewed Result observer call');
  const jump=(at,name,destination)=>equal(at,`${name} ${ins[destination].address.toString(16)}`);
  assert(k>=begin+6&&k+24<end,'Detached Result observer branch');
  call(k-6,referenceResultMap);equal(k-5,'mov r13,rax');equal(k-4,'mov rdi,rbx');call(k-3,'moonbit_decref');
  equal(k-2,'mov rdi,r12');call(k-1,'moonbit_decref');
  equal(k,'mov edi,DWORD PTR [r13-0x4]');equal(k+1,'and edi,0xff');equal(k+2,'cmp edi,0x1');
  jump(k+3,'je',k+5);jump(k+4,'jmp',k+13);
  equal(k+5,'mov rdi,QWORD PTR [r13+0x0]');equal(k+6,'mov rbx,QWORD PTR [rdi]');
  equal(k+7,'mov r12,QWORD PTR [rdi+0x8]');equal(k+8,'mov rdi,r12');call(k+9,'moonbit_incref');
  equal(k+10,'mov rdi,rbx');call(k+11,'moonbit_incref');jump(k+12,'jmp',k+24);
  for(let n=0;n<5;n++) {
    equal(k+13+2*n,`mov rdi,QWORD PTR ${sites[4-n].slot}`);call(k+14+2*n,'moonbit_decref');
  }
  const exit=ins[k+23].op.match(/^jmp ([0-9a-f]+)$/);assert(exit,'Missing Result error exit');
  const returned=ins.findIndex(i=>i.address===BigInt('0x'+exit[1]));
  assert(returned>end,'Result error path enters observer');equal(returned,'nop');equal(returned+1,'mov rax,r13');
  // Only the two checked tag/pair reads may mention the original Result
  // register before its final return. Multi-output instructions can replace
  // it in a second operand too, even after the observer's argument scope.
  for(let at=k-4;at<returned;at++)if(at!==k&&at!==k+5)
    assert(!/\br13(?:d|w|b)?\b/.test(ins[at].op),
      'Original observed Result replaced before return');
  equal(end-6,'mov rdi,rbx');equal(end-5,'mov rsi,r12');
  return new Set([k+1,k+3,k+4,k+12,k+23]);
}
function callerSites(fn,symbols) {
  const ins=fn.instructions;
  const indices=ins.flatMap((i,k)=>referenceHelpers.includes(target(i,symbols))?[k]:[]);
  assert.equal(indices.length,5,'Changed primitive Ref call count');
  const sites=indices.map((k,r)=>{
    assert.equal(target(ins[k],symbols),helperRoles[r],'Changed primitive Ref type/order');
    assert.equal(ins[k-1]?.op,initializers[r],'Changed primitive Ref initialization');
    assert.equal(ins[k+1]?.op,'mov rdi,rax','Lost Ref return identity');
    assert.equal(ins[k+2]?.op,'mov rax,rdi','Lost Ref return alias');
    const slot=ins[k+3]?.op.match(/^mov QWORD PTR (\[rbp-0x[0-9a-f]+\]),rax$/)?.[1];
    assert(slot,'Missing local Ref custody slot');
    return {role:roles[r],helper:helperRoles[r],slot,callOffset:(ins[k].address-fn.start).toString(),storeIndex:k+3};
  });
  assert.equal(new Set(sites.map(s=>s.slot)).size,5,'Primitive Ref custody slots alias');
  const probes=ins.flatMap((i,k)=>target(i,symbols)===observer?[k]:[]);
  assert.equal(probes.length,1,'Missing or repeated actual Ref observer call');const end=probes[0],begin=indices[0]-1;
  assert(end>indices.at(-1),'Observer precedes primitive Ref construction');
  for(const i of ins.slice(0,begin)) assert(!frameLea.test(i.op) &&
    !((frameSource.test(i.op) || frameDestination.test(i.op)) &&
      i.op!=='mov rbp,rsp'),'Ref caller frame escaped before construction');
  const slotWrites=sites.map(s=>({...s,start:-BigInt(s.slot.slice(5,-1))}));
  const widths={BYTE:1n,WORD:2n,DWORD:4n,QWORD:8n};
  const resultBranch=resultObserverBranch(ins,begin,end,sites,symbols);
  for(let k=begin;k<end;k++) {
    const op=ins[k].op;
    // This restricted debug region preserves rbp/rsp, never escapes a frame
    // address, and never reassigns the five custody slots. ABI-conforming
    // calls cannot replace private caller-frame slots without such an escape.
    assert(/^(mov |movabs |lea |call |cmp |je |nop$)/.test(op)||resultBranch.has(k),'Unsupported Ref custody instruction');
    assert(!frameDestination.test(op) && !frameLea.test(op) &&
      !frameSource.test(op),'Ref caller frame escapes or changes');
    const write=op.match(/^mov (BYTE|WORD|DWORD|QWORD) PTR \[rbp-(0x[0-9a-f]+)\],/);
    if(/^mov [A-Z]+ PTR \[rbp/.test(op)) assert(write,'Unknown Ref frame write');
    if(write) {
      const address=-BigInt(write[2]),limit=address+widths[write[1]];
      for(const slot of slotWrites) if(address<slot.start+8n && limit>slot.start)
        assert(k===slot.storeIndex && address===slot.start && write[1]==='QWORD','Primitive Ref custody overwritten');
    }
    if(op.startsWith('je ')&&!resultBranch.has(k)) {
      const jump=op.match(/^je ([0-9a-f]+)$/);assert(jump,'Unknown Ref custody branch');
      assert(ins[k+3] && BigInt('0x'+jump[1])===ins[k+3].address &&
        /^mov rdi,QWORD PTR \[rbp-0x[0-9a-f]+\]$/.test(ins[k+1].op) &&
        target(ins[k+2],symbols)==='moonbit_incref','Unreviewed branch across Ref custody');
    }
  }
  // No other block may enter halfway through this straight-line region.
  for(const i of ins) {
    const jump=i.op.match(/^j[a-z]+ ([0-9a-f]+)$/);
    if(!jump) continue;const address=BigInt('0x'+jump[1]);
    if(address>ins[begin].address && address<=ins[end].address)
      assert(i.address>=ins[begin].address && i.address<ins[end].address,'External branch enters Ref custody');
  }
  for(const [n,register] of ['rdx','rcx','r8','r9'].entries())
    assert.equal(ins[end-4+n].op,`mov ${register},QWORD PTR ${sites[n].slot}`,'Ref observer register substitution');
  const stackStores=ins.slice(indices.at(-1)+4,end).flatMap((i,k)=>i.op==='mov QWORD PTR [rsp],rax'?[k+indices.at(-1)+4]:[]);
  assert.equal(stackStores.length,1,'Missing or overwritten Ref observer stack argument');
  assert.equal(ins[stackStores[0]-1].op,`mov rax,QWORD PTR ${sites[4].slot}`,'Ref observer stack substitution');
  for(const i of ins.slice(stackStores[0]+1,end)) {
    const write=i.op.match(/^mov (BYTE|WORD|DWORD|QWORD) PTR \[rsp(?:\+(0x[0-9a-f]+))?\],/);
    if(/^mov [A-Z]+ PTR \[rsp/.test(i.op)) assert(write,'Unknown Ref argument frame write');
    if(write) assert(BigInt(write[2]??'0')>=8n,'Ref observer stack overwritten');
  }
  return sites.map(({storeIndex,...s})=>s);
}
export function inspectParentReferenceCode(start,symbolText,objectText,linkedText) {
  const symbols=codeSymbols(symbolText),objects=functions(objectText),linked=functions(linkedText);
  const names=[...objects.keys()].filter(parentName);assert.equal(names.length,1,'Missing unique parent constructor');
  const fn=names[0];assert(linked.has(fn),'Missing executed parent constructor');
  const objectSites=callerSites(objects.get(fn)),linkedSites=callerSites(linked.get(fn),symbols);
  assert.deepEqual(linkedSites,objectSites,'Object/executed Ref argument correspondence differs');
  const extents=new Map(referenceHelpers.map(name=>[name,helperExtent(name,linked.get(name),symbols)]));
  const identities=new Set();
  const references=objectSites.map(s=>{
    const identity=start.roots[s.role];assert.match(identity,/^[1-9][0-9]*$/);
    assert(!identities.has(identity),'Live primitive Ref identities alias');identities.add(identity);
    return {identity,...s,...extents.get(s.helper)};
  });
  return {scope:'five primitive Refs passed to the actual Linux x64 parent constructor observer',constructor:fn,
    structuralReferenceCount:5,references,pointRequestedBytes:references.reduce((n,s)=>n+s.requestedBytes,0),
    payloadBytesMeasured:false,allocationRequestsEstablished:true,completePhysicalLifetimeUpper:false};
}

// Shared decoder only; these exports do not authorize a different inspection
// scope. Each consuming check must validate its own instruction/ABI premises.
export {functions as nativeFunctions,target as nativeCallTarget,resultObserverBranch};
