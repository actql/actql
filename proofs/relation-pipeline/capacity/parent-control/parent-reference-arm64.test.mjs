import test from 'node:test';
import assert from 'node:assert/strict';
import {arm64ReferenceHelpers,inspectParentReferenceArm64} from './parent-reference-arm64.mjs';
const parent='__M0FP45actql5actql10connectors5local42bounded__relation__chain__execution__state';
const malloc='_moonbit_malloc',incref='_moonbit_incref',observer='_actql_proof_current_chain_start';
const owner='__M0FP45actql5actql10connectors5local54managed__provider__execution__with__child__work__issue',decref='_moonbit_decref';
const addresses=new Map([[arm64ReferenceHelpers[0],0x4000],[arm64ReferenceHelpers[1],0x5000],
  [arm64ReferenceHelpers[2],0x6000],[malloc,0x7000],[incref,0x7100],[observer,0x8000],[owner,0x9a00],[decref,0x9b00]]);
const slots=['0x48','0x50','0x58','0x60','0x68'];
const types=[arm64ReferenceHelpers[0],...Array(3).fill(arm64ReferenceHelpers[1]),arm64ReferenceHelpers[2]];
const prologue=['sub sp, sp, #0x100','stp x29, x30, [sp, #0xf0]','add x29, sp, #0x100'];
const ops=[...prologue,...types.flatMap((name,i)=>[
  ...(i===4?['mov w0, #0xffff','movk w0, #0xffff, lsl #16']:[i===0?'mov x0, #0x0':'mov w0, #0x0']),
  {call:name},'mov x16, x0',`stur x16, [x29, #-${slots[i]}]`,
]),'str w10, [sp, #0x20]','mov x0, x20','mov x1, x21',
...slots.map((slot,i)=>`ldur x${i+2}, [x29, #-${slot}]`),'ldur x7, [x29, #-0x18]',{call:observer},'ret'];
function assembly(name,start,ops,object=false) {
  let text=`${start.toString(16)} <${name}>:\n`;
  for(const [i,op] of ops.entries()) {
    const at=start+i*4,hex=at.toString(16);
    if(op.call) {
      text+=`${hex}: bl 0x${(object?at:addresses.get(op.call)).toString(16)}\n`;
      if(object)text+=`${hex}: ARM64_RELOC_BRANCH26 ${op.call}\n`;
    } else if(op.branch)text+=`${hex}: ${op.branch} 0x${(start+op.target*4).toString(16)}\n`;
    else text+=`${hex}: ${op}\n`;
  }
  return text;
}
function helper(name) {
  const wide=name===arm64ReferenceHelpers[0];
  return assembly(name,addresses.get(name),['sub sp, sp, #0x20','stp x29, x30, [sp, #0x10]',
    'add x29, sp, #0x20','stur x19, [x29, #-0x18]',wide?'mov x19, x0':'mov w19, w0',
    wide?'mov x0, #0x8':'mov x0, #0x4',{call:malloc},'mov w10, #0x0','stur w10, [x0, #-0x4]',
    wide?'str x19, [x0]':'str w19, [x0]','nop','ldur x19, [x29, #-0x18]',
    'ldp x29, x30, [sp, #0x10]','add sp, sp, #0x20','ret']);
}
const symbols=[...addresses].map(([name,address])=>`${address.toString(16)} T ${name}`).join('\n');
const start=()=>({roots:{used:'10',cancelled:'20',terminal:'30',reclaimed:'40',cleanupIndex:'50'}});
function check(changed=ops,linkedOps=changed,roots=start(),linkedHelpers=arm64ReferenceHelpers.map(helper).join('')) {
  return inspectParentReferenceArm64(roots,symbols,assembly(parent,0x100,changed,true),assembly(parent,0x1000,linkedOps)+linkedHelpers);
}
test('ARM64 five generated helper requests reach distinct actual observer roles',()=>{
  const r=check();assert.equal(r.pointRequestedBytes,64);
  assert.deepEqual(r.references.map(v=>v.requestedBytes),[16,12,12,12,12]);
  assert.deepEqual(r.references.map(v=>v.identity),['10','20','30','40','50']);
  assert.equal(r.payloadBytesMeasured,false);assert.equal(r.completePhysicalLifetimeUpper,false);
});
test('ARM64 initializer, helper order, count and returned alias remain required',()=>{
  for(const [from,to] of [['mov x0, #0x0','mov x0, #0x1'],['movk w0, #0xffff, lsl #16','movk w0, #0xfffe, lsl #16'],
    ['mov x16, x0','mov x16, x1']])assert.throws(()=>check(ops.map(v=>v===from?to:v)),/initializer|alias/);
  assert.throws(()=>check(ops.map(v=>v.call===types[0]?{call:types[4]}:v)),/type\/order/);
  assert.throws(()=>check(ops.filter(v=>v.call!==types[0])),/call count/);
});
test('ARM64 same-size identities and observer register substitution reject',()=>{
  const roots=start();roots.roots.terminal=roots.roots.cancelled;assert.throws(()=>check(ops,ops,roots),/identities alias/);
  assert.throws(()=>check(ops.map(v=>v==='ldur x2, [x29, #-0x48]'?'ldur x2, [x29, #-0x50]':v)),/role substitution/);
});
test('ARM64 private slots reject full, partial and SP-alias overwrites',()=>{
  for(const store of ['stur x16, [x29, #-0x48]','stur w16, [x29, #-0x44]',
    'sturb w16, [x29, #-0x41]','sturh w16, [x29, #-0x42]',
    'str x16, [sp, #0xb8]','str w16, [sp, #0xbc]','strb w16, [sp, #0xbf]']) {
    const changed=[...ops];changed.splice(24,0,store);assert.throws(()=>check(changed),/custody overwritten/);
  }
});
test('ARM64 frame escape or partial frame register replacement rejects',()=>{
  for(const op of ['mov x10, x29','mov w10, w29','mov w29, w10','add x10, sp, #0x8',
    'mov sp, x10','str x29, [x10]','ldr x10, [x11, x29]','ldur w29, [sp, #0x10]']) {
    for(const position of [3,24]) {
      const changed=[...ops];changed.splice(position,0,op);assert.throws(()=>check(changed),/frame/);
    }
  }
});
test('ARM64 helpers require exact request, scalar header, payload width and returned allocation',()=>{
  const text=arm64ReferenceHelpers.map(helper).join('');
  for(const [from,to] of [['mov x0, #0x4','mov x0, #0x8'],['mov w10, #0x0','mov w10, #0x1'],
    ['str w19, [x0]','str x19, [x0]'],['str x19, [x0]','str x19, [x1]'],['bl 0x7000','bl 0x7004'],['ret','mov x0, x19\n7020: ret']])
    assert.throws(()=>check(ops,ops,start(),text.replace(from,to)));
});
test('ARM64 only reviewed conditional incref branch crosses private custody',()=>{
  const changed=[...ops];const at=24;
  changed.splice(at,0,'cmp x19, #0x0',{branch:'b.ne',target:at+3},{branch:'b',target:at+5},'mov x0, x19',{call:incref});
  assert.equal(check(changed).pointRequestedBytes,64);
  const wrong=changed.map(v=>v.branch==='b.ne'?{...v,target:v.target+1}:v);assert.throws(()=>check(wrong),/conditional/);
  const entry=[...ops];entry.splice(3,0,{branch:'b',target:7});assert.throws(()=>check(entry),/External/);
  const indirect=[...ops];indirect.splice(24,0,'br x10');assert.throws(()=>check(indirect),/instruction|entry/);
});
test('ARM64 object/linked roles, relocations and instruction membership cannot differ',()=>{
  assert.throws(()=>check(ops,ops.map(v=>typeof v==='string'?v.replace('#-0x48','#-0x88'):v)),/correspondence/);
  const o=assembly(parent,0x100,ops,true),l=assembly(parent,0x1000,ops)+arm64ReferenceHelpers.map(helper).join('');
  assert.throws(()=>inspectParentReferenceArm64(start(),symbols,o.replace('110: ARM64_RELOC','114: ARM64_RELOC'),l),/Detached/);
  assert.throws(()=>inspectParentReferenceArm64(start(),symbols,o.replace('ARM64_RELOC_BRANCH26','ARM64_RELOC_UNSIGNED'),l),/Unsupported/);
  assert.throws(()=>inspectParentReferenceArm64(start(),symbols,o.replace('100: sub','101: sub'),l),/Noncontiguous/);
});

test('ARM64 unknown custody calls and repeated observer cannot be hidden',()=>{
  addresses.set('_unreviewed_custody_call',0x9900);
  const changed=[...ops];changed.splice(24,0,{call:'_unreviewed_custody_call'});
  assert.throws(()=>check(changed),/Unreviewed ARM64 custody call/);
  assert.throws(()=>check([...ops,{call:observer}]),/repeated ARM64 observer/);
});

test('ARM64 callback retirement cannot free a primitive Ref or precede retaining handoff',()=>{
  const regs=['x24','x23','x25','x26','x27'];
  const extra=regs.flatMap(r=>['mov x0, #0x10',{call:malloc},`mov ${r}, x0`]);
  extra.push(...regs.map((r,n)=>`mov x${n}, ${r}`),{call:owner},'mov x28, x0',
    ...regs.flatMap(r=>[`mov x0, ${r}`,{call:decref}]));
  const changed=[...ops];changed.splice(24,0,...extra);
  assert.equal(check(changed).pointRequestedBytes,64);
  const release=changed.findIndex(v=>v.call===decref);
  const ref=[...changed];ref[release-1]='ldur x0, [x29, #-0x48]';
  assert.throws(()=>check(ref),/retirement targets a Ref/);
  const alias=[...changed];alias.splice(release-1,0,'mov w24, w16');
  assert.throws(()=>check(alias),/callback allocation alias/);
  const duplicate=[...changed];duplicate.splice(release+1,0,'mov x0, x24',{call:decref});
  assert.throws(()=>check(duplicate),/retirement count/);
  const early=[...changed];early.splice(24,0,'mov x0, x24',{call:decref});
  assert.throws(()=>check(early),/retirement count|precedes/);
});

// The constructor now captures the original reclamation prefix Int, rather
// than the former all-or-nothing scratch flag. Its pure query does not move
// any private Ref slot or replace a callback/Owner handoff.
test('ARM64 current original reclaimed-prefix query preserves private Ref custody',()=>{
  const prefix='__M0FP45actql5actql10connectors5local34relation__chain__reclaimed__prefix';
  addresses.set(prefix,0x9c00);
  const current=[...ops];current.splice(24,0,'mov x0, x19',{call:prefix});
  assert.equal(check(current).pointRequestedBytes,64);
  const prior='__M0FP45actql5actql10connectors5local42relation__chain__reclaims__completed__scratch';
  addresses.set(prior,0x9d00);
  assert.throws(()=>check(current.map(op=>op.call===prefix?{call:prior}:op)),/Unreviewed ARM64 custody call/);
});
