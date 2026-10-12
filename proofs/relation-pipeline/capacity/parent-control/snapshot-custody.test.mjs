import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {checkDriverRetirementSource,driverPath,blockAfter} from './driver-retirement-source.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const read=p=>readFileSync(root+p);
test('current snapshot source retains cancellation custody until cleanup or successful finalization',()=>{
  const witness=checkDriverRetirementSource(read);
  assert.deepEqual(witness.snapshotCustody,{pendingCancelRetainsCallback:true,
    retirementRequiresCallbackAbsent:true,cleanupRetryBeforeRootRetirement:true,
    successfulFinishRequiresReleasedStorage:true,pendingImporterRemainsRegistered:true});
  assert.equal(witness.wholePhysicalLifetimeUpper,false);
});

// Reach a unique reviewed closure before changing an independently specified
// condition. Duplicate text elsewhere must not turn a missed mutation into a pass.
function changedBlock(anchors, from, to) {
  const original=read(driverPath).toString();
  let body=original;
  for(const anchor of anchors) body=blockAfter(body,anchor);
  const pattern=new RegExp(from.replace(/[.*+?^${}()|[\]\\]/g,'\\$&').replace(/\s+/g,'\\s+'),'g');
  assert.equal([...body.matchAll(pattern)].length,1,'Snapshot mutation must reach a unique actual condition');
  const replacement=body.replace(pattern,to);
  assert.equal(original.split(body).length,2,'Snapshot closure must be unique');
  return p=>p===driverPath?original.replace(body,replacement):read(p);
}
const snapshotAnchor='prepare_relation_snapshot: fn(storage_released)';
for(const [name,anchors,from,to] of [
  ['scratch observation accepts pending snapshot callback',['scratch_released: fn()'],
    '&& relation_snapshot_cancel.val is None',''],
  ['root retirement ignores snapshot callback',['let release_owned_scratch = fn()'],
    'relation_snapshot_cancel.val is Some(_) ||',''],
  ['cancel discards callback on incomplete cleanup',['let cancel_finalization = fn()'],
    'if cancel() {','if !cancel() {'],
  ['cleanup retry ignores incomplete callback',['cleanup_refresh: fn()'],
    'if !cancel() {','if false {'],
  ['cleanup retry detaches callback before invoking it',['cleanup_refresh: fn()'],
    'if !cancel() {','relation_snapshot_cancel.val = None\nif !cancel() {'],
  ['snapshot cancellation loses importer',[snapshotAnchor,'relation_snapshot_cancel.val = Some(fn()'],
    'restored.val = None','importing.val = None\nrestored.val = None'],
  ['snapshot callback reports completion without references',[snapshotAnchor,'relation_snapshot_cancel.val = Some(fn()'],
    'cleanup_references(64)','true'],
  ['snapshot cleanup drops unreleased physical storage',[snapshotAnchor,'let cleanup_references = fn(quantum : Int)'],
    'if !storage_released() {','if false {'],
  ['snapshot cleanup drops pending material reclamation',[snapshotAnchor,'let cleanup_references = fn(quantum : Int)'],
    '!@execution.advance_retained_output_reference_reclamation(','@execution.advance_retained_output_reference_reclamation('],
  ['snapshot finalization releases callback before guard',[snapshotAnchor,'finish: () =>'],
    'guard live.val &&','relation_snapshot_cancel.val = None\nguard live.val &&'],
  ['snapshot finalization omits restored value readiness',[snapshotAnchor,'finish: () =>'],
    'restored.val is Some(value)','true'],
  ['snapshot finalization fails to transfer original output',[snapshotAnchor,'finish: () =>'],
    'ordinary.val = Some(value)','ignore(value)'],
  ['successful cleanup fails to detach callback',['cleanup_refresh: fn()'],
    'relation_snapshot_cancel.val = None','ignore(cancel)'],
]) test('source rejects '+name,()=>{
  const mutated=changedBlock(anchors,from,to);
  assert.throws(()=>checkDriverRetirementSource(mutated));
});
for(const [name,condition] of [
  ['live','live.val &&'],['restored phase','phase.val == Restored &&'],
  ['physical storage release','storage_released() &&'],['stored material','stored.val is None &&'],
  ['stream','stream.val is None &&'],['receipt','receipt.val is None &&'],
]) test('source rejects snapshot finalization without '+name,()=>{
  const mutated=changedBlock([snapshotAnchor,'finish: () =>'],condition,'true &&');
  assert.throws(()=>checkDriverRetirementSource(mutated));
});

