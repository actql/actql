import assert from 'node:assert/strict';
import {fieldLayout} from '../backing/native-extent.mjs';
import {parentFields,inspectParentStartup} from '../backing/parent-layout.mjs';
import {currentSlotsCeiling} from '../backing/model.mjs';
import {chainCaptureRoles} from './chain-source.mjs';
const token = id => assert(typeof id === 'string' && /^[1-9][0-9]*$/.test(id), 'Missing actual Native identity');
// Capture order is grounded in the pinned Native constructor store sequence,
// including scalar fields between references and their alignment padding.
// Admission also binds the actual capture identities; byte equality alone
// does not establish source correspondence.
const sizes = {
  state: parentFields.state, environment: parentFields.startEnvironment,
  advance: parentFields.advance, cancel: parentFields.cancel,
  stopped: parentFields.stopped, cleanup: parentFields.cleanup,
  childWorkIssue: parentFields.childWorkIssue,
  preparation: ['ref','i32','ref','ref','ref','ref','ref',...Array(6).fill('i32'),'ref','ref','i32'],
  read: ['ref','ref','ref',...Array(9).fill('i32'),'ref','ref','i32','i32'],
};
export const currentRequestedLayouts = Object.fromEntries(Object.entries(sizes)
  .map(([name,fields]) => [name,{fields,...fieldLayout(fields),requestedBytes:8+fieldLayout(fields).payloadBytes}]));
const sortedIds = record => record.captures.map(c=>c.id).filter(Boolean).toSorted();
function checkRecord(record, name) {
  token(record.id);assert.equal(record.requestedBytes,currentRequestedLayouts[name].requestedBytes, `Current source/ABI record extent ${name}`);
  const pointers = currentRequestedLayouts[name].fields.map((kind,i)=>kind==='ref'?currentRequestedLayouts[name].offsets[i]:null).filter(x=>x!==null);
  // Closures start with a non-GC code pointer of the same width. The lifted
  // start_next environment is data, not another dynamic callback owner.
  if(['advance','cancel','stopped','cleanup','childWorkIssue'].includes(name)) pointers.shift();
  assert.deepEqual(record.captures.map(c=>c.offset),pointers,`Current source/ABI pointer fields ${name}`);
}
export function inspectCurrentChain(records) {
  const starts=records.filter(r=>r.kind==='startup');assert.equal(starts.length,1);
  const start=starts[0];token(start.parent);assert.equal(start.count,2);
  checkRecord(start.state,'state');assert.equal(start.roots.state,start.state.id);
  const envs=start.environments;assert.equal(envs.length,1,'Unclassified current closure capture');
  checkRecord(envs[0],'environment');
  const callbacks=['advance','cancel','stopped','cleanup','childWorkIssue'];
  assert.equal(start.callbacks.length,callbacks.length);
  const mapping={...start.roots, cleanup_index:start.roots.cleanupIndex, start_next:envs[0].id};
  for(const [i,name] of callbacks.entries()) {
    checkRecord(start.callbacks[i],name);
    const wanted=chainCaptureRoles[name].filter(n=>Object.hasOwn(mapping,n)).map(n=>mapping[n]).filter(Boolean).toSorted();
    assert.deepEqual(sortedIds(start.callbacks[i]),wanted,`Actual ${name} capture identities differ from source roles`);
  }
  assert.deepEqual(sortedIds(envs[0]),chainCaptureRoles.startNext.filter(n=>Object.hasOwn(mapping,n)).map(n=>mapping[n]).filter(Boolean).toSorted(),'Actual start_next environment does not bind current input/configuration');
  const phases=records.filter(r=>r.kind==='phase');assert.deepEqual(phases.map(p=>p.phase),[0,1,2,3,4,5,6]);
  const base=phases[1];assert(base.preparation && base.read,'Real retained metadata preparation not exercised');
  checkRecord(base.preparation,'preparation');checkRecord(base.read,'read');
  assert.equal(base.completed.length,start.count);assert.equal(base.completed.slots,start.count);
  token(base.completed.elements[0]);token(base.completed.completions[0]);
  assert.equal(base.completed.elements[1],null);assert.equal(base.completed.completions[1],null);
  for(const f of phases) {
    assert.equal(f.parent,start.parent);assert.equal(f.state.id,start.state.id);checkRecord(f.state,'state');
    assert.deepEqual(f.callbacks,start.callbacks,'Immutable parent captures changed across cleanup');
    const field = (record,offset) => record.captures.find(c=>c.offset===offset)?.id;
    assert.equal(field(f.state,0),f.children.id,'Actual state does not own observed child array');
    assert.equal(field(f.state,16),f.completed.id,'Actual state does not own observed output container');
    assert.equal(field(f.state,40),f.preparation?.id ?? null,'Actual state does not retain observed preparation');
    if(f.preparation) {
      assert.equal(field(f.preparation,24),f.completed.id,'Preparation loses completed output backing');
      assert.equal(field(f.preparation,88),f.read?.id ?? null,'Preparation loses its real producer-read cursor');
    }
    for(const key of ['children','completed']) {
      const a=f[key];token(a.id);token(a.backing);assert.equal(a.ownerBytes,24);
      assert(Number.isSafeInteger(a.length) && a.length>=0);
      assert(Number.isSafeInteger(a.slots) && a.slots>=a.length);
      assert(BigInt(a.slots)<=currentSlotsCeiling(start.count,1),'Array backing exceeds structural count ceiling');assert.equal(a.backingBytes,8+8*a.slots);
      assert(!a.staticBacking || a.slots===0);
      assert.equal(a.elements.length,a.length);
    }
    assert(f.children.id!==f.completed.id,'Distinct Array owners unexpectedly alias');
    assert(f.children.backing!==f.completed.backing || f.children.staticBacking && f.completed.staticBacking,'Distinct nonempty backing unexpectedly aliases');
    if(f.phase>=1 && f.phase<=4) {
      assert.deepEqual(f.preparation,base.preparation,'Cancellation/pending cleanup drops or replaces real preparation');
      assert.deepEqual(f.read,base.read,'Pending cleanup drops or replaces producer metadata');
      assert.deepEqual(f.children,base.children,'Pending cleanup drops child responsibility');
      assert.deepEqual(f.completed,base.completed,'Pending cleanup drops completed occurrence custody');
      assert.equal(f.position,1);assert.equal(f.pending,true);
      assert.equal(f.children.elements[0],field(f.state,8),'Current child does not match retained responsibility');
    } else if(f.phase>=5) {
      assert.equal(f.preparation,null);assert.equal(f.read,null);
      assert.equal(f.children.length,0);assert.equal(f.completed.length,0);
    }
  }
  // Summarize point observations only. No union across time/address reuse, no
  // allocator/RSS claim, no invented size for scalar GC layouts or referents.
  return {scope:'one Native long-name serial chain, actual callback captures and metadata custody through stop/false/error/retry',
    actualPhases:phases.length,currentRequestedLayouts,
    startup:inspectParentStartup(start,'native'),
    scalarRefCount:5,scalarRefExtentPremise:'five single-field primitive Refs; at most eight payload bytes each under the pinned ABI; not measured from scalar GC descriptors',
    logicalExtraReservationBytes:512,logicalExtraReservationIsPhysicalBound:false,
    completePhysicalUpper:false,ledgerHoldingGenerationCorrespondence:false,
    excluded:['shared configuration and payload referents','preparation selected/columns allocation overlap',
      'temporary wrappers and observer allocations','allocator overhead','whole-owner and reservation retirement union']};
}
