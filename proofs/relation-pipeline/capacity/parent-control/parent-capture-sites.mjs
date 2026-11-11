import assert from 'node:assert/strict';
import {codeSymbols} from './provider-callback-code.mjs';
import {nativeFunctions,nativeCallTarget,resultObserverBranch,referenceResultMap} from './parent-reference-sites.mjs';

const observer='actql_proof_current_chain_start';
const parentName=n=>/connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(n);
const ownerName=n=>/connectors5local[0-9]+managed__provider__execution__with__child__work__issue$/.test(n);
const callbackRoles=['advance','cancel','stopped','cleanup','childWorkIssue'];
// Reviewed source/ABI correspondence, including scalar padding. Actual object
// and linked stores must independently establish these roles, not just a set.
const layouts={
  startNext:[[0,'used',8],[8,'family',8],[16,'numeric',8],[24,'maxValueBytes',4],
    [32,'measurement',8],[40,'execution',8],[48,'state',8],[56,'sequence',8],[64,'count',4]],
  advance:[[8,'startNext',8],[16,'reclaimedPrefix',4],[24,'terminal',8],[32,'cancelled',8],
    [40,'used',8],[48,'execution',8],[56,'inputs',8],[64,'state',8],[72,'sequence',8],[80,'count',4]],
  cancel:[[8,'terminal',8],[16,'cancelled',8],[24,'state',8]], stopped:[[8,'terminal',8]],
  cleanup:[[8,'cleanupIndex',8],[16,'reclaimed',8],[24,'terminal',8],[32,'state',8]], childWorkIssue:[[8,'state',8]],
};
const payloads={startNext:72,advance:88,cancel:32,stopped:16,cleanup:40,childWorkIssue:16};
const widths={QWORD:8,DWORD:4};
const family=r=>({eax:'rax',ebx:'rbx',ecx:'rcx',edx:'rdx',edi:'rdi',esi:'rsi'}[r]??r.replace(/^(r(?:[89]|1[0-5]))d$/,'$1'));
const registerWidth=r=>{const width=/^(?:r(?:ax|bx|cx|dx|di|si|[89]|1[0-5]))$/.test(r)?8:
  /^(?:e(?:ax|bx|cx|dx|di|si)|r(?:[89]|1[0-5])d)$/.test(r)?4:undefined;
  assert(width,'Unreviewed capture register width');return width;};
const valueWidth=v=>v.kind==='allocation' || v.kind==='code'?8:v.width;
const volatile=['rax','rdi','rsi','rdx','rcx','r8','r9','r10','r11'];
function roleSlots(ins,end,call,pair) {
  let begin=end-1;while(begin>=0 && !ins[begin].op.startsWith('call '))begin--;
  const registers=new Map(),stack=new Map();
  if(pair) {
    begin=pair.start-1;
    registers.set('rbx',{slot:pair.parent,width:8});
    registers.set('r12',{slot:pair.state,width:8});
  }
  for(const i of ins.slice(begin+1,end)) {
    let m=i.op.match(/^mov (\w+),(QWORD|DWORD) PTR (\[rbp-(0x[0-9a-f]+)\])$/);
    if(m){assert.equal(registerWidth(m[1]),widths[m[2]],'Capture observer load width differs');registers.set(family(m[1]),{slot:m[3],width:widths[m[2]]});continue;}
    if(pair && (i.op==='mov rdi,rbx' || i.op==='mov rsi,r12')) {
      const [destination,source]=i.op.slice(4).split(',');registers.set(destination,registers.get(source));continue;
    }
    m=i.op.match(/^mov (QWORD|DWORD) PTR \[rsp(?:\+(0x[0-9a-f]+))?\],(\w+)$/);
    assert(m,'Unreviewed capture observer argument preparation');
    const offset=Number(BigInt(m[2]??'0')),value=registers.get(family(m[3]));
    assert(value && registerWidth(m[3])===value.width && value.width===widths[m[1]],'Capture observer argument width differs');
    assert(!stack.has(offset),'Capture observer stack argument overwritten');stack.set(offset,value);
  }
  const slots=new Map();
  const add=(role,value,width)=>{assert(value && value.width===width,'Missing typed capture observer argument '+role);
    assert(!slots.has(value.slot),'Capture observer roles share a private slot');slots.set(value.slot,{role,width});};
  ['parent','state','used','cancelled','terminal','reclaimed'].forEach((role,k)=>add(role,registers.get(['rdi','rsi','rdx','rcx','r8','r9'][k]),8));
  ['cleanupIndex','sequence','inputs','execution','measurement','numeric','family','count','maxValueBytes','reclaimedPrefix']
    .forEach((role,k)=>add(role,stack.get(k*8),k<7?8:4));
  assert.equal(stack.size,10,'Unexpected capture observer stack argument');
  assert.equal(call(ins[end]),observer);
  return slots;
}
// Recognize only the existing cleanup mapper around the original parent.
// The direct observer takes its parent/state from the checked Ok pair, while
// all six construction captures still bind to these SAME private frame slots.
function inspectCleanupResultPrelude(ins,begin,map,call,slots,fn,symbols) {
  let at=begin;
  const equal=op=>assert.equal(ins[at++]?.op,op,'Changed cleanup Result transport');
  const called=name=>assert.equal(call(ins[at++]),name,'Changed cleanup Result call');
  const slot=role=>[...slots].find(([,v])=>v.role===role)?.[0];
  const header=(base,tag)=>{
    const value=ins[at++]?.op.match(/^mov r10d,(0x[0-9a-f]+)$/);
    assert(value && BigInt(value[1])>>30n===1n && (BigInt(value[1])&255n)===BigInt(tag),'Changed cleanup Result header');
    equal(`mov DWORD PTR [${base}-0x4],r10d`);
  };
  equal('movabs rdi,0x8');called('moonbit_malloc');equal('mov rbx,rax');header('rbx',1);
  equal(`mov rax,QWORD PTR ${slot('parent')}`);equal('mov QWORD PTR [rbx],rax');
  for(const role of ['cleanupIndex','reclaimed','terminal']) {
    equal(`mov rdi,QWORD PTR ${slot(role)}`);called('moonbit_incref');
  }
  equal('movabs rdi,0x28');called('moonbit_malloc');equal('mov r12,rax');header('r12',0);
  const code=ins[at],lea=code?.op.match(/^lea r10,\[rip([+-])0x([0-9a-f]+)\]$/);
  assert(lea,'Missing cleanup Result callback');let name=code.relocation?.symbol;
  if(code.relocation)assert.equal(code.relocation.kind,'PC32','Wrong cleanup callback relocation');
  else {
    const address=ins[at+1].address+BigInt('0x'+lea[2])*(lea[1]==='-'?-1n:1n);
    const names=[...symbols].filter(([,v])=>v===address).map(([n])=>n);
    assert.equal(names.length,1,'Unknown/aliased cleanup Result callback');name=names[0];
  }
  assert(name?.startsWith(fn.name+'C'),'Foreign cleanup Result callback');at++;
  equal('mov QWORD PTR [r12],r10');
  for(const [k,role] of ['cleanupIndex','reclaimed','terminal','state'].entries()) {
    equal(`mov rax,QWORD PTR ${slot(role)}`);equal(`mov QWORD PTR [r12+0x${((k+1)*8).toString(16)}],rax`);
  }
  equal('mov rdi,rbx');equal('mov rsi,r12');
  assert.equal(at,map,'Unexpected instruction before cleanup Result map');called(referenceResultMap);
  return {code:name,parent:slot('parent'),state:slot('state')};
}
function stores(fn,symbols) {
  const ins=fn.instructions,call=i=>nativeCallTarget(i,symbols);
  const probes=ins.flatMap((i,k)=>call(i)===observer?[k]:[]);assert.equal(probes.length,1,'Missing capture observer');
  const end=probes[0];
  const owners=ins.slice(0,end).flatMap((i,k)=>ownerName(call(i)??'')?[k]:[]);
  assert.equal(owners.length,1,'Missing unique parent callback handoff');const owner=owners[0];
  const masks=ins.flatMap((i,k)=>k>owner&&k<end&&i.op==='and edi,0xff'?[k]:[]);
  assert(masks.length<=1,'Repeated capture Result discriminator');
  const tag=masks.length?masks[0]-1:undefined;
  const pair=tag===undefined?undefined:{start:tag+24,
    parent:ins[owner+1]?.op.match(/^mov QWORD PTR (\[rbp-0x[0-9a-f]+\]),rax$/)?.[1],
    state:ins[tag-10]?.op.match(/^mov rax,QWORD PTR (\[rbp-0x[0-9a-f]+\])$/)?.[1]};
  if(pair)assert(pair.parent&&pair.state,'Missing original capture Result slots');
  const slots=roleSlots(ins,end,call,pair);
  const slot=role=>{const matches=[...slots].filter(([,v])=>v.role===role);assert.equal(matches.length,1);return matches[0][0];};
  const branches=pair?resultObserverBranch(ins,owner+2,end,
    ['used','cancelled','terminal','reclaimed','cleanupIndex'].map(role=>({slot:slot(role)})),symbols):new Set();
  const allocations=ins.slice(0,owner).flatMap((i,k)=>call(i)==='moonbit_malloc'?[k]:[]).slice(-6);
  assert.equal(allocations.length,6,'Missing six actual capture allocations');
  const begin=allocations[0]-1;
  for(const [k,i] of ins.entries()) {
    const jump=i.op.match(/^j[a-z]+ ([0-9a-f]+)$/);if(!jump)continue;
    const address=BigInt('0x'+jump[1]);
    assert(address<=ins[begin].address || address>ins[end].address || branches.has(k),'Branch enters capture construction/observer region');
  }
  const registers=new Map(),writes=new Map(),headers=new Map(),code=new Map(),points=[];
  const lookup=operand=>{
    const frame=operand.match(/^(QWORD|DWORD) PTR (\[rbp-0x[0-9a-f]+\])$/);
    if(frame){const v=slots.get(frame[2]);assert(v && v.width===widths[frame[1]],'Unbound capture source slot');return {kind:'role',...v};}
    if(/^0x[0-9a-f]+$/.test(operand))return {kind:'constant',value:operand};
    const value=registers.get(family(operand));assert(value,'Unknown capture register alias');
    assert.equal(registerWidth(operand),valueWidth(value),'Partial capture register alias');return value;
  };
  let allocation=0;
  for(let k=begin;k<owner;k++) {
    const i=ins[k];if(i.op==='nop')continue;
    if(i.op.startsWith('call ')) {
      const target=call(i);
      assert(target==='moonbit_malloc' || target==='moonbit_incref','Unreviewed call during capture construction');
      if(target==='moonbit_malloc') {
        assert.equal(k,allocations[allocation],'Unexpected capture allocation');
        const role=['startNext',...callbackRoles][allocation++];
        assert.deepEqual(registers.get('rdi'),{kind:'constant',value:'0x'+payloads[role].toString(16),width:8},'Capture allocation request differs');
        volatile.forEach(r=>registers.delete(r));registers.set('rax',{kind:'allocation',role});writes.set(role,new Map());
        points.push({role,payloadBytes:payloads[role],headerBytes:8,requestedBytes:payloads[role]+8,callOffset:(i.address-fn.start).toString()});
      } else {const value=registers.get('rdi');assert(value && valueWidth(value)===8 && ['role','allocation'].includes(value.kind),'Unbound incref capture argument');volatile.forEach(r=>registers.delete(r));}
      continue;
    }
    let m=i.op.match(/^lea (\w+),\[rip([+-])0x([0-9a-f]+)\]$/);
    if(m) {
      let name=i.relocation?.symbol;
      if(i.relocation)assert.equal(i.relocation.kind,'PC32','Wrong capture code-pointer relocation');
      else {const address=ins[k+1].address+BigInt('0x'+m[3])*(m[2]==='-'?-1n:1n);
        const names=[...symbols].filter(([,v])=>v===address).map(([n])=>n);assert.equal(names.length,1,'Unknown/aliased linked capture code');name=names[0];}
      assert(name?.startsWith(fn.name+'C'),'Capture code belongs to another constructor');
      assert.equal(registerWidth(m[1]),8,'Partial capture code-pointer register');registers.set(family(m[1]),{kind:'code',name});continue;
    }
    m=i.op.match(/^(?:mov|movabs) (\w+),(.+)$/);
    if(m){let value=lookup(m[2]);const width=registerWidth(m[1]);
      if(value.kind==='constant')value={...value,width};else assert.equal(width,valueWidth(value),'Partial capture register write');
      registers.set(family(m[1]),value);continue;}
    m=i.op.match(/^mov (QWORD|DWORD) PTR \[(\w+)([+-]0x[0-9a-f]+)?\],(\w+)$/);
    assert(m,'Unreviewed capture store instruction');
    const base=registers.get(family(m[2]));assert(base?.kind==='allocation','Capture store escapes its allocation');
    const offset=m[3]?Number(BigInt(m[3].slice(1)))*(m[3][0]==='-'?-1:1):0;
    const value=lookup(m[4]),width=widths[m[1]],role=base.role;assert.equal(valueWidth(value),width,'Capture store width differs from alias');
    if(offset===-4) {
      assert.equal(width,4);assert(value.kind==='constant' && BigInt(value.value)>>30n===1n,'Missing indexed capture header');
      assert(!headers.has(role),'Repeated capture header');headers.set(role,value.value);continue;
    }
    if(callbackRoles.includes(role) && offset===0) {
      assert.equal(width,8);assert.equal(value.kind,'code');assert(!code.has(role),'Repeated capture code pointer');code.set(role,value.name);continue;
    }
    const expected=layouts[role].find(([at])=>at===offset);assert(expected && width===expected[2],'Unknown/partial capture field store');
    const wanted=expected[1]==='startNext'?{kind:'allocation',role:'startNext'}:{kind:'role',role:expected[1],width};
    assert.deepEqual(value,wanted,'Capture store source role differs');assert(!writes.get(role).has(offset),'Capture field overwritten');writes.get(role).set(offset,value);
  }
  assert.equal(allocation,6);
  for(const [k,role] of callbackRoles.entries())assert.deepEqual(registers.get(['rdi','rsi','rdx','rcx','r8'][k]),{kind:'allocation',role},'Callback handoff role differs');
  const parentSlot=[...slots].find(([,v])=>v.role==='parent')[0];
  assert.equal(ins[owner+1]?.op,`mov QWORD PTR ${parentSlot},rax`,'Parent handoff return lost before observer');
  let cursor=owner+2;
  for(const role of callbackRoles) {
    const move=ins[cursor++]?.op.match(/^mov rdi,(\w+)$/);
    assert(move && registers.get(family(move[1]))?.kind==='allocation' &&
      registers.get(family(move[1])).role===role,'Changed caller callback retirement after handoff');
    assert.equal(call(ins[cursor++]),'moonbit_decref','Unknown call after callback handoff');
  }
  const cleanupMapper=pair?inspectCleanupResultPrelude(ins,cursor,tag-6,call,slots,fn,symbols):undefined;
  if(!pair)for(const i of ins.slice(cursor,end))assert(/^(?:mov (?:\w+,(?:QWORD|DWORD) PTR \[rbp-0x[0-9a-f]+\]|(?:QWORD|DWORD) PTR \[rsp(?:\+0x[0-9a-f]+)?\],\w+)|nop)$/.test(i.op),
    'Unexpected instruction between callback retirement and observer');
  for(const point of points) {
    assert(headers.has(point.role),'Missing capture header');assert.equal(writes.get(point.role).size,layouts[point.role].length,'Missing capture field');
    point.header=headers.get(point.role);point.fields=layouts[point.role];if(point.role!=='startNext')point.code=code.get(point.role);
    assert(point.role==='startNext' || point.code,'Missing actual callback code');
  }
  return {points,cleanupMapper};
}
export function inspectParentCaptureCode(start,symbolText,objectText,linkedText) {
  const symbols=codeSymbols(symbolText),objects=nativeFunctions(objectText),linked=nativeFunctions(linkedText);
  const names=[...objects.keys()].filter(parentName);assert.equal(names.length,1,'Missing capture constructor');
  const name=names[0];assert(linked.has(name),'Missing linked capture constructor');
  const object={...objects.get(name),name},exe={...linked.get(name),name};
  const construction=stores(object),executed=stores(exe,symbols);assert.deepEqual(executed,construction,'Object/linked capture correspondence differs');
  const {points}=construction;
  const roots={...start.roots,startNext:start.environments[0].id};
  const observations=[start.environments[0],...start.callbacks];assert.equal(observations.length,points.length);
  for(const [k,p] of points.entries()) {
    assert.equal(observations[k].requestedBytes,p.requestedBytes,'Actual capture request differs');
    const captures=p.fields.filter(([,role,width])=>width===8).map(([offset,role])=>{
      assert(Object.hasOwn(roots,role),'Missing observed capture role '+role);return {offset,id:roots[role]};});
    assert.deepEqual(observations[k].captures,captures,'Actual capture offset/role identity differs');
  }
  return {scope:'six Linux x64 construction-point allocations and ordered observer capture roles',points,
    captureRolesEstablished:true,completePhysicalLifetimeUpper:false};
}
