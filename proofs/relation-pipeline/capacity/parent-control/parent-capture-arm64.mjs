// Finite Darwin ARM64 construction-point correspondence. This establishes
// ordered capture roles, not callback body semantics or physical lifetime.
import assert from 'node:assert/strict';
import {codeSymbols} from './provider-callback-code.mjs';
import {arm64Functions,arm64CallTarget} from './parent-reference-arm64.mjs';
const observer='_actql_proof_current_chain_start';
const parentName=n=>/connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(n);
const ownerName=n=>/connectors5local[0-9]+managed__provider__execution__with__child__work__issue$/.test(n);
const callbacks=['advance','cancel','stopped','cleanup','childWorkIssue'];
const roles=['startNext',...callbacks];
const layouts={
 startNext:[[0,'used',8],[8,'family',8],[16,'numeric',8],[24,'maxValueBytes',4],[32,'measurement',8],[40,'execution',8],[48,'state',8],[56,'sequence',8],[64,'count',4]],
 advance:[[8,'startNext',8],[16,'reclaimedPrefix',4],[24,'terminal',8],[32,'cancelled',8],[40,'used',8],[48,'execution',8],[56,'inputs',8],[64,'state',8],[72,'sequence',8],[80,'count',4]],
 cancel:[[8,'terminal',8],[16,'cancelled',8],[24,'state',8]],stopped:[[8,'terminal',8]],
 cleanup:[[8,'cleanupIndex',8],[16,'reclaimed',8],[24,'terminal',8],[32,'state',8]],childWorkIssue:[[8,'state',8]],
};
const payloads={startNext:72,advance:88,cancel:32,stopped:16,cleanup:40,childWorkIssue:16};
const family=r=>r.replace(/^w/,'x'), width=r=>{
 assert(/^[xw](?:[0-9]|[12][0-9]|30)$/.test(r),'Unreviewed ARM64 capture register');return r[0]==='x'?8:4;
};
const valueWidth=v=>['allocation','code','page'].includes(v.kind)?8:v.width;
const volatile=Array.from({length:19},(_,n)=>'x'+n);
function observerSources(ins,end,call) {
 let begin=end-1;while(begin>=0 && !ins[begin].op.startsWith('bl '))begin--;
 const registers=new Map(),stack=new Map();
 const lookup=r=>{
  if(registers.has(family(r))) {const v=registers.get(family(r));assert.equal(v.width,width(r),'Partial ARM64 observer alias');return v;}
  assert(/^x(?:19|2[0-8])$/.test(family(r)),'Unbound ARM64 observer register');
  return {source:family(r),width:width(r)};
 };
 for(const i of ins.slice(begin+1,end)) {
  let m=i.op.match(/^ldur ([xw]\d+), \[x29, #-(0x[0-9a-f]+)\]$/);
  if(m){registers.set(family(m[1]),{source:'frame:'+m[2],width:width(m[1])});continue;}
  m=i.op.match(/^mov ([xw]\d+), ([xw]\d+)$/);
  if(m){const v=lookup(m[2]);assert.equal(width(m[1]),v.width,'Partial ARM64 observer move');registers.set(family(m[1]),v);continue;}
  m=i.op.match(/^str ([xw]\d+), \[sp(?:, #(0x[0-9a-f]+))?\]$/);
  assert(m,'Unreviewed ARM64 observer argument preparation');const at=Number(BigInt(m[2]??'0'));
  assert(!stack.has(at),'ARM64 observer stack argument overwritten');stack.set(at,lookup(m[1]));
 }
 const sources=new Map();
 const add=(role,value,w)=>{assert(value && value.width===w,'Missing typed ARM64 observer argument '+role);
  assert(!sources.has(value.source),'ARM64 observer roles alias a source');sources.set(value.source,{kind:'role',role,width:w});};
 ['parent','state','used','cancelled','terminal','reclaimed','cleanupIndex','sequence'].forEach((r,n)=>add(r,registers.get('x'+n),8));
 [['inputs',0,8],['execution',8,8],['measurement',16,8],['numeric',24,8],['family',32,8],['count',40,4],['maxValueBytes',44,4],['reclaimedPrefix',48,4]]
  .forEach(([r,at,w])=>add(r,stack.get(at),w));
 assert.equal(stack.size,8,'Unexpected ARM64 observer stack argument');assert.equal(call(ins[end]),observer);
 return {sources,begin:begin+1};
}
function stores(fn,symbols) {
 const ins=fn.instructions,call=i=>arm64CallTarget(i,symbols);
 const probes=ins.flatMap((i,k)=>call(i)===observer?[k]:[]);assert.equal(probes.length,1,'Missing unique ARM64 capture observer');
 const end=probes[0],{sources,begin:observerBegin}=observerSources(ins,end,call);
 const owners=ins.slice(0,end).flatMap((i,k)=>ownerName(call(i)??'')?[k]:[]);
 assert.equal(owners.length,1,'Missing unique ARM64 callback handoff');const owner=owners[0];
 const allocations=ins.slice(0,owner).flatMap((i,k)=>call(i)==='_moonbit_malloc'?[k]:[]).slice(-6);
 assert.equal(allocations.length,6,'Missing six ARM64 capture allocations');const begin=allocations[0]-1;
 for(const i of ins) {
  const branch=i.op.match(/^b(?:\.[a-z]+)? (0x[0-9a-f]+)$/);
  if(branch){const at=BigInt(branch[1]);assert(at<=ins[begin].address || at>ins[end].address,'Branch enters ARM64 capture construction/observer');}
  assert(!/^(?:cbz|cbnz|tbz|tbnz|br)\b/.test(i.op),'Unreviewed indirect ARM64 capture entry');
 }
 const registers=new Map([...sources].filter(([s])=>/^x/.test(s))),writes=new Map(),headers=new Map(),codes=new Map(),points=[];
 const lookup=r=>{const v=registers.get(family(r));assert(v,'Unknown ARM64 capture alias');
  assert.equal(width(r),valueWidth(v),'Partial ARM64 capture alias');return v;};
 const frame=(r,slot)=>{const v=sources.get('frame:'+slot);assert(v && v.width===width(r),'Unbound/partial ARM64 capture source slot');return v;};
 let allocation=0;
 for(let k=begin;k<owner;k++) {
  const i=ins[k],op=i.op;if(op==='nop')continue;
  if(op.startsWith('bl ')) {
   const target=call(i);assert(['_moonbit_malloc','_moonbit_incref'].includes(target),'Unreviewed call in ARM64 capture construction');
   if(target==='_moonbit_malloc') {
    assert.equal(k,allocations[allocation],'Unexpected ARM64 capture allocation');const role=roles[allocation++];
    assert.deepEqual(registers.get('x0'),{kind:'constant',value:BigInt(payloads[role]),width:8},'ARM64 capture request differs');
    volatile.forEach(r=>registers.delete(r));registers.set('x0',{kind:'allocation',role});writes.set(role,new Map());
    points.push({role,payloadBytes:payloads[role],headerBytes:8,requestedBytes:payloads[role]+8,callOffset:(i.address-fn.start).toString()});
   } else {const v=registers.get('x0');assert(v && valueWidth(v)===8 && ['role','allocation'].includes(v.kind),'Unbound ARM64 incref capture');volatile.forEach(r=>registers.delete(r));}
   continue;
  }
  let m=op.match(/^mov ([xw]\d+), #(0x[0-9a-f]+)$/);
  if(m){const w=width(m[1]),value=BigInt(m[2]);assert(value<(1n<<BigInt(w*8)),'Overflowing ARM64 capture constant');registers.set(family(m[1]),{kind:'constant',value,width:w});continue;}
  m=op.match(/^movk ([xw]\d+), #(0x[0-9a-f]+), lsl #(16|32|48)$/);
  if(m){const prior=lookup(m[1]),shift=BigInt(m[3]),value=BigInt(m[2]);assert(prior.kind==='constant' && shift<BigInt(prior.width*8) && value<=0xffffn,'Unreviewed ARM64 capture constant patch');
   registers.set(family(m[1]),{...prior,value:(prior.value&~(0xffffn<<shift))|(value<<shift)});continue;}
  m=op.match(/^mov ([xw]\d+), ([xw]\d+)$/);
  if(m){const v=lookup(m[2]);assert.equal(width(m[1]),valueWidth(v),'Partial ARM64 capture register write');registers.set(family(m[1]),v);continue;}
  m=op.match(/^ldur ([xw]\d+), \[x29, #-(0x[0-9a-f]+)\]$/);
  if(m){registers.set(family(m[1]),frame(m[1],m[2]));continue;}
  m=op.match(/^adrp (x\d+), (0x[0-9a-f]+)$/);
  if(m){const page=BigInt(m[2]);assert(page%4096n===0n,'Unaligned ARM64 capture code page');
   if(i.relocation)assert.equal(i.relocation.kind,'PAGE21','Wrong ARM64 capture page relocation');
   registers.set(family(m[1]),{kind:'page',page,name:i.relocation?.symbol});continue;}
  m=op.match(/^add (x\d+), (x\d+), #(0x[0-9a-f]+)$/);
  if(m){const p=lookup(m[2]);assert.equal(p.kind,'page','Unreviewed ARM64 capture address');let name;
   const offset=BigInt(m[3]);assert(offset<4096n,'ARM64 capture page offset outside page');
   if(i.relocation){assert.equal(i.relocation.kind,'PAGEOFF12','Wrong ARM64 capture offset relocation');assert.equal(i.relocation.symbol,p.name,'ARM64 capture page/offset symbols differ');name=p.name;}
   else {assert.equal(p.name,undefined,'Detached ARM64 capture offset relocation');const names=[...symbols].filter(([,a])=>a===p.page+offset).map(([n])=>n);assert.equal(names.length,1,'Unknown/aliased linked ARM64 capture code');name=names[0];}
   assert(name?.startsWith(fn.name+'C'),'ARM64 capture code belongs to another constructor');registers.set(family(m[1]),{kind:'code',name});continue;}
  m=op.match(/^(?:str|stur) ([xw]\d+), \[(x\d+)(?:, #(-?0x[0-9a-f]+))?\]$/);
  assert(m,'Unreviewed ARM64 capture store instruction');const base=lookup(m[2]);assert.equal(base.kind,'allocation','ARM64 capture store escapes allocation');
  const offset=m[3]?Number(m[3].startsWith('-')?-BigInt(m[3].slice(1)):BigInt(m[3])):0,value=lookup(m[1]),w=width(m[1]),role=base.role;
  if(offset===-4){assert.equal(w,4);assert(value.kind==='constant' && value.value>>30n===1n,'Missing ARM64 indexed capture header');assert(!headers.has(role),'Repeated ARM64 capture header');headers.set(role,'0x'+value.value.toString(16));continue;}
  if(callbacks.includes(role) && offset===0){assert.equal(w,8);assert.equal(value.kind,'code');assert(!codes.has(role),'Repeated ARM64 capture code pointer');codes.set(role,value.name);continue;}
  const expected=layouts[role].find(([at])=>at===offset);assert(expected && w===expected[2],'Unknown/partial ARM64 capture field store');
  const wanted=expected[1]==='startNext'?{kind:'allocation',role:'startNext'}:{kind:'role',role:expected[1],width:w};
  assert.deepEqual(value,wanted,'ARM64 capture store source role differs');assert(!writes.get(role).has(offset),'ARM64 capture field overwritten');writes.get(role).set(offset,value);
 }
 assert.equal(allocation,6);
 callbacks.forEach((role,n)=>assert.deepEqual(registers.get('x'+n),{kind:'allocation',role},'ARM64 callback handoff role differs'));
 const parent=[...sources].find(([,v])=>v.role==='parent')?.[0];assert(/^x(?:19|2[0-8])$/.test(parent),'Unreviewed ARM64 parent return custody');
 assert.equal(ins[owner+1]?.op,`mov ${parent}, x0`,'ARM64 parent handoff return lost before observer');
 let cursor=owner+2;
 for(const role of callbacks){const m=ins[cursor++]?.op.match(/^mov x0, (x\d+)$/);assert(m && registers.get(m[1])?.kind==='allocation' && registers.get(m[1]).role===role,'ARM64 callback retirement role differs');assert.equal(call(ins[cursor++]),'_moonbit_decref','Unknown call after ARM64 handoff');}
 assert.equal(cursor,observerBegin,'Unexpected instruction between ARM64 callback retirement and observer arguments');
 for(const point of points){assert(headers.has(point.role),'Missing ARM64 capture header');assert.equal(writes.get(point.role).size,layouts[point.role].length,'Missing ARM64 capture field');point.header=headers.get(point.role);point.fields=layouts[point.role];if(point.role!=='startNext')point.code=codes.get(point.role);assert(point.role==='startNext'||point.code,'Missing ARM64 callback code');}
 return points;
}
export function inspectParentCaptureArm64(start,symbolText,objectText,linkedText) {
 const symbols=codeSymbols(symbolText),objects=arm64Functions(objectText),linked=arm64Functions(linkedText);
 const names=[...objects.keys()].filter(parentName);assert.equal(names.length,1,'Missing ARM64 capture constructor');const name=names[0];assert(linked.has(name),'Missing linked ARM64 capture constructor');
 const points=stores({...objects.get(name),name}),executed=stores({...linked.get(name),name},symbols);assert.deepEqual(executed,points,'ARM64 object/linked capture correspondence differs');
 const roots={...start.roots,startNext:start.environments[0].id},observations=[start.environments[0],...start.callbacks];assert.equal(observations.length,points.length);
 for(const [k,p] of points.entries()){assert.equal(observations[k].requestedBytes,p.requestedBytes,'Actual ARM64 capture request differs');const captures=p.fields.filter(([,r,w])=>w===8).map(([offset,role])=>{assert(Object.hasOwn(roots,role),'Missing observed ARM64 capture role '+role);return {offset,id:roots[role]};});assert.deepEqual(observations[k].captures,captures,'Actual ARM64 capture offset/role identity differs');}
 return {scope:'six Darwin ARM64 construction-point allocations and ordered observer capture roles',points,captureRolesEstablished:true,completePhysicalLifetimeUpper:false};
}
