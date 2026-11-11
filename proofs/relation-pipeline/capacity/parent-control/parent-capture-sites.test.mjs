import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectParentCaptureCode} from './parent-capture-sites.mjs';
const parent='_M0FP45actql5actql10connectors5local42bounded__relation__chain__execution__state';
const owner='_M0FP45actql5actql10connectors5local54managed__provider__execution__with__child__work__issue';
const roles=['startNext','advance','cancel','stopped','cleanup','childWorkIssue'];
// Independent reviewed fixture: do not import the checker's expected layouts.
const fields=[[[0,'used',8],[8,'family',8],[16,'numeric',8],[24,'maxValueBytes',4],[32,'measurement',8],[40,'execution',8],[48,'state',8],[56,'sequence',8],[64,'count',4]],
 [[8,'startNext',8],[16,'reclaimedPrefix',4],[24,'terminal',8],[32,'cancelled',8],[40,'used',8],[48,'execution',8],[56,'inputs',8],[64,'state',8],[72,'sequence',8],[80,'count',4]],
 [[8,'terminal',8],[16,'cancelled',8],[24,'state',8]],[[8,'terminal',8]],
 [[8,'cleanupIndex',8],[16,'reclaimed',8],[24,'terminal',8],[32,'state',8]],[[8,'state',8]]];
const sizes=[72,88,32,16,40,16],registers=['rbx','r12','rbx','r13','r14','r15'];
const slots={parent:'0x90',state:'0x50',used:'0x60',cancelled:'0x68',terminal:'0x70',reclaimed:'0x78',cleanupIndex:'0x80',sequence:'0x8',inputs:'0x10',execution:'0x18',measurement:'0x20',numeric:'0x30',family:'0x38',count:'0x3c',maxValueBytes:'0x24',reclaimedPrefix:'0x84'};
const symbols=new Map([['moonbit_malloc',0x7000],['moonbit_incref',0x7100],['moonbit_decref',0x7200],[owner,0x8000],['actql_proof_current_chain_start',0x8100],...roles.slice(1).map((r,k)=>[parent+'C'+(k+1),0x9000+k*0x100])]);
const nm=[...symbols].map(([n,a])=>a.toString(16)+' T '+n).join('\n');
const ops=[];
for(const [k,role] of roles.entries()) {
 const base=registers[k];ops.push('movabs rdi,0x'+sizes[k].toString(16),{call:'moonbit_malloc'},'mov '+base+',rax','mov r10d,0x40000100','mov DWORD PTR ['+base+'-0x4],r10d');
 if(k)ops.push({code:parent+'C'+k},'mov QWORD PTR ['+base+'],r10');
 for(const [at,name,width] of fields[k]) {
  if(name==='startNext')ops.push('mov QWORD PTR ['+base+'+0x'+at.toString(16)+'],rbx');
  else ops.push('mov '+(width===8?'rax,QWORD':'eax,DWORD')+' PTR [rbp-'+slots[name]+']','mov '+(width===8?'QWORD':'DWORD')+' PTR ['+base+(at?'+0x'+at.toString(16):'')+'],'+(width===8?'rax':'eax'));
 }
}
ops.push('mov rdi,r12','mov rsi,rbx','mov rdx,r13','mov rcx,r14','mov r8,r15',{call:owner},'mov QWORD PTR [rbp-0x90],rax');
for(const register of ['r12','rbx','r13','r14','r15'])ops.push('mov rdi,'+register,{call:'moonbit_decref'});
for(const [k,role] of ['cleanupIndex','sequence','inputs','execution','measurement','numeric','family','count','maxValueBytes','reclaimedPrefix'].entries()) {
 const wide=k<7;ops.push('mov '+(wide?'rax,QWORD':'eax,DWORD')+' PTR [rbp-'+slots[role]+']','mov '+(wide?'QWORD':'DWORD')+' PTR [rsp'+(k?'+0x'+(k*8).toString(16):'')+'],'+(wide?'rax':'eax'));
}
for(const [k,role] of ['parent','state','used','cancelled','terminal','reclaimed'].entries())ops.push('mov '+['rdi','rsi','rdx','rcx','r8','r9'][k]+',QWORD PTR [rbp-'+slots[role]+']');
ops.push({call:'actql_proof_current_chain_start'},'ret');
function assembly(instructions,object) {
 let at=object?0x100:0x1000,text=at.toString(16)+' <'+parent+'>:\n';
 for(const op of instructions) {
  if(op.call){text+=at.toString(16)+': call '+(object?at:symbols.get(op.call)).toString(16)+'\n';if(object)text+=(at+1).toString(16)+': R_X86_64_PLT32 '+op.call+'-0x4\n';at+=5;}
  else if(op.code){text+=at.toString(16)+': lea r10,[rip'+(object?'+0x0':'+0x'+(symbols.get(op.code)-at-7).toString(16))+']\n';if(object)text+=(at+3).toString(16)+': R_X86_64_PC32 '+op.code+'-0x4\n';at+=7;}
  else {text+=at.toString(16)+': '+op+'\n';at+=10;}
 }
 return text;
}
function observation() {
 const roots=Object.fromEntries(Object.keys(slots).map((r,k)=>[r,String(100+k)]));roots.numeric=null;
 const ids={...roots,startNext:'200'};
 const blocks=fields.map((fs,k)=>({id:String(200+k),requestedBytes:sizes[k]+8,captures:fs.filter(([,r,w])=>w===8).map(([offset,r])=>({offset,id:ids[r]}))}));
 return {roots,environments:[blocks[0]],callbacks:blocks.slice(1)};
}
const check=(objectOps=ops,linkedOps=objectOps,start=observation(),table=nm)=>inspectParentCaptureCode(start,table,assembly(objectOps,true),assembly(linkedOps,false));
test('six object and linked construction allocations bind each capture to its observer role',()=>{
 const r=check();assert.equal(r.captureRolesEstablished,true);assert.equal(r.completePhysicalLifetimeUpper,false);
 assert.deepEqual(r.points.map(p=>p.requestedBytes),[80,96,40,24,48,24]);
 assert.deepEqual(r.points[1].fields.filter(([,r])=>['terminal','cancelled'].includes(r)),[[24,'terminal',8],[32,'cancelled',8]]);
});
test('same identity set cannot hide reordered callback or environment captures',()=>{
 for(const choose of [s=>s.callbacks[0].captures,s=>s.environments[0].captures]) {
  const s=observation(),a=choose(s),before=a.map(c=>c.id).toSorted();[a[1].id,a[2].id]=[a[2].id,a[1].id];
  assert.deepEqual(a.map(c=>c.id).toSorted(),before);assert.throws(()=>check(ops,ops,s),/offset\/role identity differs/);
 }
 const s=observation();delete s.roots.family;assert.throws(()=>check(ops,ops,s),/Missing observed/);
});
test('same-width pointer and scalar field source substitutions reject in actual instructions',()=>{
 for(const [from,to] of [['mov rax,QWORD PTR [rbp-0x70]','mov rax,QWORD PTR [rbp-0x68]'],['mov eax,DWORD PTR [rbp-0x24]','mov eax,DWORD PTR [rbp-0x3c]']]) {
  const copy=[...ops],k=copy.indexOf(from);copy[k]=to;assert.throws(()=>check(copy),/store source role differs/);
 }
});
test('partial, missing, repeated and redirected allocation stores reject',()=>{
 for(const mutate of [a=>a[a.indexOf('mov QWORD PTR [rbx+0x8],rax')]='mov DWORD PTR [rbx+0x8],eax',
  a=>a.splice(a.indexOf('mov QWORD PTR [rbx+0x8],rax'),1),
  a=>a.splice(a.indexOf('mov QWORD PTR [rbx+0x8],rax'),0,'mov QWORD PTR [rbx+0x8],rax'),
  a=>a[a.indexOf('mov QWORD PTR [rbx+0x8],rax')]='mov QWORD PTR [rdi+0x8],rax',
  a=>a[a.indexOf('movabs rdi,0x48')]='movabs rdi,0x40']) {
  const copy=[...ops];mutate(copy);assert.throws(()=>check(copy));
 }
});
test('callback handoff order and object/linked code identity must agree',()=>{
 const copy=[...ops];copy[copy.indexOf('mov rdi,r12')]='mov rdi,rbx';assert.throws(()=>check(copy),/handoff role differs/);
 const changed=ops.map(op=>op.code===parent+'C1'?{code:parent+'C2'}:op);assert.throws(()=>check(ops,changed),/correspondence differs/);
});
test('unknown calls, frame writes and entering branches cannot disappear from the scope',()=>{
 for(const op of ['mov QWORD PTR [rbp-0x50],rax','jmp 140',{call:owner}]) {
  const copy=[...ops];copy.splice(8,0,op);assert.throws(()=>check(copy));
 }
});
test('observer stack overwrites, missing arguments and width changes reject',()=>{
 for(const mutate of [a=>a.splice(a.indexOf('mov QWORD PTR [rsp],rax'),0,'mov QWORD PTR [rsp],rax'),
  a=>a.splice(a.indexOf('mov QWORD PTR [rsp+0x30],rax'),1),
  a=>a[a.indexOf('mov DWORD PTR [rsp+0x38],eax')]='mov QWORD PTR [rsp+0x38],rax']) {
  const copy=[...ops];mutate(copy);assert.throws(()=>check(copy),/observer/);
 }
});
test('indexed headers and uniquely resolved linked code addresses remain mandatory',()=>{
 const changed=[...ops];changed[changed.indexOf('mov r10d,0x40000100')]='mov r10d,0x0';assert.throws(()=>check(changed),/header/);
 assert.throws(()=>check(ops,ops,observation(),nm+'\n9000 T alias'),/aliased linked capture code/);
});

test('partial register copies cannot preserve full pointer or allocation aliases',()=>{
 for(const op of ['mov eax,edi','mov r12d,eax','mov ebx,eax','mov ax,di']) {
  const copy=[...ops];copy.splice(7,0,op);assert.throws(()=>check(copy),/Partial|register|alias/);
 }
});

test('parent return and caller retirement cannot be replaced before observation',()=>{
 const changed=[...ops];changed[changed.indexOf('mov QWORD PTR [rbp-0x90],rax')]='mov QWORD PTR [rbp-0x90],rbx';
 assert.throws(()=>check(changed),/handoff return/);
 const bad=ops.map(op=>op.call==='moonbit_decref'?{call:'moonbit_incref'}:op);assert.throws(()=>check(bad),/Unknown call after/);
});
