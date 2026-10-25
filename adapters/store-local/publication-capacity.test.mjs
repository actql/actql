import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
async function fixture(t,options) {
 const directory=await mkdtemp('/tmp/store-budget-exact-');
 const store=await openLocalPublicationStore({directory,storeAuthorityCid:'sha256:'+'0'.repeat(64),maxContractNodes:4096,maxContractDepth:64,...options},createPublicationContractControlFixture());
 t.after(async()=>{await store.close();await rm(directory,{recursive:true,force:true});});return {store};
}

test('per-kind publication quote accepts exact and rejects one-byte-short Store capacity', async t => {
  const {completedPublicationCapacity} = await import('../host-common/publication-capacity.mjs');
  const c = identity => ({identity, wire: JSON.stringify({identity})});
  const plan = {runDefinition:c('run'),invocation:c('invocation'),
    results:Array.from({length:100},()=>({retention:c('retention'),evidenceContext:{inputRelationCids:[]}})),
    outputLimits:{maxWireBytes:68,maxSchemaBytes:128},contractLimits:{maxWireBytes:4096}};
  const quote = completedPublicationCapacity(plan,
    Array.from({length:100},(_,i)=>c('definition'+i)),c('request'),c('attempt'));
  const {store} = await fixture(t,{capacityBytes:quote.requiredBytes,
    maxObjectBytes:quote.maxObjectBytes,maxObjects:quote.objectCount});
  const before=store.status();
  assert.equal(store.publicationCapacitySupports(quote),true);
  assert.equal(store.publicationCapacitySupports({...quote,requiredBytes:quote.requiredBytes+1}),false);
  assert.deepEqual(store.status(),before,'preflight does not issue or consume reservation');
  await store.putBytes(Buffer.from('x'));
  assert.equal(store.publicationCapacitySupports(quote),false,'retained existing byte must remain in the cumulative sum');
});
