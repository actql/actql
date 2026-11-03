import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectParentCaptureArm64} from './parent-capture-arm64.mjs';
const parent='__M0FP45actql5actql10connectors5local42bounded__relation__chain__execution__state';
const owner='__M0FP45actql5actql10connectors5local54managed__provider__execution__with__child__work__issue';
const roles=['startNext','advance','cancel','stopped','cleanup','childWorkIssue'];
// Independent source/ABI fixture; never import the verifier's expected fields.
const fields=[[[0,'used',8],[8,'family',8],[16,'numeric',8],[24,'maxValueBytes',4],[32,'measurement',8],[40,'execution',8],[48,'state',8],[56,'sequence',8],[64,'count',4]],
 [[8,'startNext',8],[16,'reclaimedPrefix',4],[24,'terminal',8],[32,'cancelled',8],[40,'used',8],[48,'execution',8],[56,'inputs',8],[64,'state',8],[72,'sequence',8],[80,'count',4]],
 [[8,'terminal',8],[16,'cancelled',8],[24,'state',8]],[[8,'terminal',8]],
 [[8,'cleanupIndex',8],[16,'reclaimed',8],[24,'terminal',8],[32,'state',8]],[[8,'state',8]]];
const sizes=[72,88,32,16,40,16],bases=['x23','x24','x23','x25','x26','x27'];
const slots={state:'0x40',used:'0x48',cancelled:'0x50',terminal:'0x58',reclaimed:'0x60',cleanupIndex:'0x68',sequence:'0x18',inputs:'0x20',execution:'0x28',measurement:'0x30',maxValueBytes:'0x34'};
const sources={family:'x20',numeric:'x19',count:'w21',reclaimedPrefix:'w22'};
const symbols=new Map([['_moonbit_malloc',0x7000],['_moonbit_incref',0x7100],['_moonbit_decref',0x7200],[owner,0x8000],['_actql_proof_current_chain_start',0x8100],...roles.slice(1).map((r,k)=>[parent+'C'+(k+1),0x9000+k*0x100])]);
const nm=[...symbols].map(([n,a])=>a.toString(16)+' T '+n).join('\n');
const load=(role,w,r=w===8?'x16':'w16')=>slots[role]?`ldur ${r}, [x29, #-${slots[role]}]`:`mov ${r}, ${sources[role]}`;
const ops=[];
for(const [k,role] of roles.entries()) {
 const base=bases[k];ops.push('mov x0, #0x'+sizes[k].toString(16),{call:'_moonbit_malloc'},'mov '+base+', x0','mov w10, #0x100','movk w10, #0x4001, lsl #16',`stur w10, [${base}, #-0x4]`);
 if(k)ops.push({page:parent+'C'+k},{offset:parent+'C'+k},`str x10, [${base}]`);
 for(const [at,name,w] of fields[k]) {
  if(name==='startNext')ops.push(`str x23, [${base}, #0x${at.toString(16)}]`);
  else {ops.push(load(name,w));ops.push(`str ${w===8?'x16':'w16'}, [${base}${at?', #0x'+at.toString(16):''}]`);}
 }
}
ops.push('mov x0, x24','mov x1, x23','mov x2, x25','mov x3, x26','mov x4, x27',{call:owner},'mov x28, x0');
for(const r of ['x24','x23','x25','x26','x27'])ops.push('mov x0, '+r,{call:'_moonbit_decref'});
for(const [r,at,w] of [['inputs',0,8],['execution',8,8],['measurement',16,8],['numeric',24,8],['family',32,8],['count',40,4],['maxValueBytes',44,4],['reclaimedPrefix',48,4]]) {
 ops.push(load(r,w));ops.push(`str ${w===8?'x16':'w16'}, [sp${at?', #0x'+at.toString(16):''}]`);
}
ops.push('mov x0, x28',...['state','used','cancelled','terminal','reclaimed','cleanupIndex','sequence'].map((r,k)=>load(r,8,'x'+(k+1))),{call:'_actql_proof_current_chain_start'},'ret');
function assembly(instructions,object) {
 let text=(object?0x100:0x1000).toString(16)+' <'+parent+'>:\n';
 for(const [k,op] of instructions.entries()) {
  const at=(object?0x100:0x1000)+k*4;
  if(op.call){text+=`${at.toString(16)}: bl 0x${(object?at:symbols.get(op.call)).toString(16)}\n`;if(object)text+=`${at.toString(16)}: ARM64_RELOC_BRANCH26 ${op.call}\n`;}
  else if(op.page){text+=`${at.toString(16)}: adrp x10, 0x9000\n`;if(object)text+=`${at.toString(16)}: ARM64_RELOC_PAGE21 ${op.page}\n`;}
  else if(op.offset){text+=`${at.toString(16)}: add x10, x10, #0x${(object?0:symbols.get(op.offset)-0x9000).toString(16)}\n`;if(object)text+=`${at.toString(16)}: ARM64_RELOC_PAGEOFF12 ${op.offset}\n`;}
  else text+=`${at.toString(16)}: ${op}\n`;
 }
 return text;
}
function observation() {
 const roots=Object.fromEntries([...Object.keys(slots),...Object.keys(sources)].map((r,k)=>[r,String(100+k)]));roots.numeric=null;
 const ids={...roots,startNext:'200'};
 const blocks=fields.map((fs,k)=>({id:String(200+k),requestedBytes:sizes[k]+8,captures:fs.filter(([,r,w])=>w===8).map(([offset,r])=>({offset,id:ids[r]}))}));
 return {roots,environments:[blocks[0]],callbacks:blocks.slice(1)};
}
const check=(objectOps=ops,linkedOps=objectOps,start=observation(),table=nm)=>inspectParentCaptureArm64(start,table,assembly(objectOps,true),assembly(linkedOps,false));
test('ARM64 six requests bind each ordered pointer/scalar field and observer role',()=>{
 const r=check();assert.equal(r.captureRolesEstablished,true);assert.equal(r.completePhysicalLifetimeUpper,false);
 assert.deepEqual(r.points.map(p=>p.requestedBytes),[80,96,40,24,48,24]);
 assert.deepEqual(r.points[1].fields.filter(([,r])=>['terminal','cancelled'].includes(r)),[[24,'terminal',8],[32,'cancelled',8]]);
});
test('ARM64 unchanged identity sets cannot hide swapped callback/environment captures',()=>{
 for(const choose of [s=>s.callbacks[0].captures,s=>s.environments[0].captures]) {
  const s=observation(),a=choose(s),before=a.map(c=>c.id).toSorted();[a[1].id,a[2].id]=[a[2].id,a[1].id];
  assert.deepEqual(a.map(c=>c.id).toSorted(),before);assert.throws(()=>check(ops,ops,s),/offset\/role identity differs/);
 }
 const s=observation();delete s.roots.family;assert.throws(()=>check(ops,ops,s),/Missing observed/);
});
test('ARM64 same-width frame and callee-saved capture roles cannot substitute',()=>{
 for(const [from,to] of [['ldur x16, [x29, #-0x58]','ldur x16, [x29, #-0x50]'],['ldur w16, [x29, #-0x34]','mov w16, w21'],['mov x16, x20','mov x16, x19']]) {
  const copy=[...ops],k=copy.indexOf(from);copy[k]=to;assert.throws(()=>check(copy),/store source role differs/);
 }
});
test('ARM64 missing, duplicate, partial or escaping capture stores reject',()=>{
 for(const mutate of [a=>a[a.indexOf('str x16, [x23, #0x8]')]='str w16, [x23, #0x8]',
  a=>a.splice(a.indexOf('str x16, [x23, #0x8]'),1),
  a=>a.splice(a.indexOf('str x16, [x23, #0x8]'),0,'str x16, [x23, #0x8]'),
  a=>a[a.indexOf('str x16, [x23, #0x8]')]='str x16, [x20, #0x8]',
  a=>a[a.indexOf('mov x0, #0x48')]='mov x0, #0x40']) {
  const copy=[...ops];mutate(copy);assert.throws(()=>check(copy));
 }
});
test('ARM64 callback handoff order and object/linked code identity remain exact',()=>{
 const copy=[...ops];copy[copy.indexOf('mov x0, x24')]='mov x0, x23';assert.throws(()=>check(copy),/handoff role differs/);
 const changed=ops.map(op=>op.page===parent+'C1'?{page:parent+'C2'}:op.offset===parent+'C1'?{offset:parent+'C2'}:op);assert.throws(()=>check(ops,changed),/correspondence differs/);
});
test('ARM64 page relocations and linked code symbols must agree uniquely',()=>{
 assert.throws(()=>check(ops.map(op=>op.offset===parent+'C1'?{offset:parent+'C2'}:op)),/page\/offset symbols differ/);
 assert.throws(()=>check(ops,ops,observation(),nm+'\n9000 T alias'),/aliased linked ARM64 capture code/);
 const o=assembly(ops,true),l=assembly(ops,false);
 assert.throws(()=>inspectParentCaptureArm64(observation(),nm,o.replace('PAGEOFF12','PAGE21'),l),/offset relocation/);
 assert.throws(()=>inspectParentCaptureArm64(observation(),nm,o.replace(/\s*[0-9a-f]+: ARM64_RELOC_PAGEOFF12 [^\n]+\n/, '\n'),l),/Detached/);
});
test('ARM64 partial registers, unknown calls and entering control flow reject',()=>{
 for(const op of ['mov w23, w0','mov x10, x29','str x16, [x29, #-0x40]','b 0x120','br x10',{call:owner}]) {
  const copy=[...ops];copy.splice(8,0,op);assert.throws(()=>check(copy));
 }
});
test('ARM64 observer uses compact typed stack slots with no omission or overwrite',()=>{
 for(const mutate of [a=>a.splice(a.indexOf('str x16, [sp]'),0,'str x16, [sp]'),
  a=>a.splice(a.indexOf('str x16, [sp, #0x20]'),1),
  a=>a[a.indexOf('str w16, [sp, #0x2c]')]='str x16, [sp, #0x2c]',
  a=>a[a.indexOf('str w16, [sp, #0x2c]')]='str w16, [sp, #0x30]']) {
  const copy=[...ops];mutate(copy);assert.throws(()=>check(copy),/observer/);
 }
});
test('ARM64 header/code completeness and retirement/parent return cannot change',()=>{
 for(const mutate of [a=>a[a.indexOf('movk w10, #0x4001, lsl #16')]='movk w10, #0x0, lsl #16',
  a=>a.splice(a.indexOf('str x10, [x24]'),1),
  a=>a[a.indexOf('mov x28, x0')]='mov x28, x1',
  a=>a.splice(a.findIndex(v=>v.call==='_moonbit_decref'),1),
  a=>a.splice(a.findIndex(v=>v.call==='_moonbit_decref')+1,0,'mov x28, x19')]) {
  const copy=[...ops];mutate(copy);assert.throws(()=>check(copy));
 }
});
test('ARM64 incref is typed and volatile aliases cannot survive a call',()=>{
 const copy=[...ops];copy.splice(copy.indexOf('mov x0, #0x60'),0,'ldur x0, [x29, #-0x48]',{call:'_moonbit_incref'});assert.equal(check(copy).captureRolesEstablished,true);
 const stale=[...ops];stale.splice(9,0,'ldur x16, [x29, #-0x48]','mov x0, x16',{call:'_moonbit_incref'},'str x16, [x23]');
 assert.throws(()=>check(stale),/Unknown ARM64 capture alias/);
});
