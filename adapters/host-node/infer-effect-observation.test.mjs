import test from 'node:test';
import assert from 'node:assert/strict';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';

// Actual stepping adapter with explicit Core scan/receipt and original
// publication ports. No Model/Source execution, physical funding or ABI claim.
function fixture({refuseStart=false,failAdvance=false,missingExtent=false}={}) {
  const binding={},scan={},receipt={},events=[],grows=[];
  let step=0;
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramInferModelIdentityStartCapacity(original) {
      assert.strictEqual(original,binding);events.push('quote-start');
      return missingExtent?undefined:{_0:10n,_1:20n};
    },
    clientProgramInferModelIdentityStart(original) {
      assert.strictEqual(original,binding);events.push('start');return ok(scan);
    },
    clientProgramInferModelIdentityNextCapacity(original) {
      assert.strictEqual(original,scan);events.push('quote-next');
      return {_0:step===2?30n:10n,_1:step===2?40n:20n};
    },
    clientProgramInferModelIdentityAdvance(original,quantum,r,e) {
      assert.strictEqual(original,scan);assert.equal(quantum,7);
      assert.deepEqual([r,e],step===2?[30n,40n]:[10n,20n]);
      assert.deepEqual(grows.at(-1),step===2?[30n,40n]:[10n,20n]);
      events.push('advance');step++;
      return failAdvance?{$tag:0,_0:'OriginalScanRefused'}:ok({_0:step===3,_1:1});
    },
    clientProgramInferModelIdentityFinish(original) {
      assert.strictEqual(original,scan);assert.equal(step,3);events.push('finish');return ok(receipt);
    },
    clientProgramInferModelIdentityCancel(original) {
      assert.strictEqual(original,scan);events.push('cancel-scan');return true;
    },
    clientProgramInferModelIdentityReceiptCancel(original) {
      assert.strictEqual(original,receipt);events.push('cancel-receipt');
    },
    clientProgramInferModelObservationCapacity(original,completed,bytes) {
      assert.strictEqual(original,binding);assert.strictEqual(completed,receipt);
      assert.equal(bytes,16384);events.push('quote-projection');return {_0:5n,_1:6n};
    },
  };
  const operation={growOriginalPublicationCapacity(r,e) {
    events.push('grow');if(refuseStart)throw Error('OriginalBudgetRefused');grows.push([r,e]);
  }};
  return {moon,operation,binding,scan,receipt,events,grows};
}

test('Model projection steps same scan with backing before constructors and retains original binding through consumption',async()=>{
  const f=fixture();
  const result=await withOriginalInferModelObservation({...f,quantum:7,
    async consume(original) {
      assert.strictEqual(original.binding,f.binding);assert.strictEqual(original.scan,f.scan);
      assert.strictEqual(original.receipt,f.receipt);
      assert.equal(f.events.includes('cancel-scan'),false);
      assert.deepEqual(f.grows.at(-1),[35n,46n]);return 'original-projection';
    }});
  assert.equal(result,'original-projection');
  assert.equal(f.events.filter(x=>x==='start').length,1);
  assert.equal(f.events.filter(x=>x==='advance').length,3);
  assert.deepEqual(f.events.slice(-2),['cancel-receipt','cancel-scan']);
});

test('Model projection consumer failure retains primary cause while retiring same scan and receipt once',async()=>{
  const f=fixture(),primary=Object.freeze(new Error('OriginalProjectionRefused'));
  await assert.rejects(withOriginalInferModelObservation({...f,quantum:7,
    consume(){throw primary;}}),error=>error===primary);
  assert.deepEqual(f.events.slice(-2),['cancel-receipt','cancel-scan']);
});

test('Model projection scan failure retires original cursor without a fabricated receipt',async()=>{
  const f=fixture({failAdvance:true});
  await assert.rejects(withOriginalInferModelObservation({...f,quantum:7,
    consume(){assert.fail('No completed projection');}}),error=>error.cause==='OriginalScanRefused');
  assert.equal(f.events.includes('finish'),false);
  assert.deepEqual(f.events.slice(-1),['cancel-scan']);
  assert.equal(f.events.includes('cancel-receipt'),false);
});

test('Model projection rejects absent ABI or missing/refused backing before scan construction',async()=>{
  for(const selected of ['port','extent','budget']) {
    const f=fixture({missingExtent:selected==='extent',refuseStart:selected==='budget'});
    if(selected==='port')delete f.moon.clientProgramInferModelIdentityFinish;
    await assert.rejects(withOriginalInferModelObservation({...f,quantum:7,
      consume(){assert.fail('No projection without original backing');}}),selected==='budget'
      ? /OriginalBudgetRefused/ : {name:'TypeError'});
    assert.equal(f.events.includes('start'),false);
    assert.equal(f.events.includes('cancel-scan'),false);
  }
});
