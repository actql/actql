import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {admitNativePhysicalPhases} from './native-physical-phases.mjs';

const original=JSON.parse(readFileSync(new URL('./native-cleanup-retry.fixture.json',import.meta.url),'utf8'));
const admit=body=>admitNativePhysicalPhases({...body,cleanupRetry:true});
test('actual failed Native releases are rejected as normal success and matched to confirmed retries',()=>{
  assert.throws(()=>admitNativePhysicalPhases(original),/FailedNativePhysicalPhase/);
  const result=admit(original);
  assert.equal(result.cleanupStatus,'failed-task-releases-followed-by-confirmed-retries');
  assert.equal(result.failedTaskReleaseIntervals.length,3);
  assert.equal(result.taskReleaseIntervals.length,3);
  assert(result.failedTaskReleaseIntervals.every(f=>result.taskReleaseIntervals.some(r=>r.task===f.task&&r.beganAtMicroseconds>=f.endedAtMicroseconds)));
});
test('missing retry, changed failed task and non-release failure cannot certify cleanup',()=>{
  for(const mutate of [
    value=>{value.events.splice(-2,2);},
    value=>{const event=value.events.find(e=>e.success===false);event.task=99;},
    value=>{value.events.find(e=>e.phase==='compute'&&e.boundary==='end').success=false;},
    value=>{value.events.find(e=>e.success===false).success=true;},
  ]) {
    const changed=structuredClone(original);mutate(changed);assert.throws(()=>admit(changed));
  }
});
