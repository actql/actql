import test,{mock} from 'node:test';
import assert from 'node:assert/strict';
import {readWaitingCheckpoints,readCheckpointReview,checkpointPageModel,validReviewObservation,reviewText} from './checkpoint-review.mjs';
import {createReadEpoch} from './read-model.mjs';
import {checkpointFixture,reviewFixture,reviewFixtureText,reviewFixtureCid} from './checkpoint-review.fixture.mjs';
import {connect} from '../sdk/index.mjs';
import {submissionEpoch} from '../sdk/submission-fixture.mjs';
const ticket=()=>createReadEpoch().capture();
const forbidden=()=>assert.fail('read cannot start, resolve, sign, sample or cancel');
test('one authorized waiting page preserves original subjects and opaque next without another page',async()=>{
 const calls=[],item=checkpointFixture(),page={items:[item],next:'original-private-cursor'};
 const result=await readWaitingCheckpoints({checkpoints:async opts=>{calls.push(opts);return page;},resolveCheckpoints:forbidden,start:forbidden},ticket());
 assert.deepEqual(calls,[{limit:32}]);assert.deepEqual(result,page);assert(Object.isFrozen(result.items[0].subject));
 item.subject.runId='mutated';assert.equal(result.items[0].subject.runId,'original-run');assert(!Object.hasOwn(result,'runRef'));
});
test('metadata malformed, duplicate, excessive items and wire overflow refuse whole pages',()=>{
 const item=checkpointFixture();for(const page of [{items:[item,item]},{items:[{...item,permission:true}]},{items:[] ,total:0},
 {items:Array.from({length:33},(_,i)=>({...item,checkpointCid:'sha256:'+String(i).padStart(64,'0')}))},
 {items:[],next:'x'.repeat(65537)}])assert.throws(()=>checkpointPageModel(page),{code:'ExplorerInvalidCheckpointReview'});
});
test('review snapshots the original before await and calls only independently authorized SDK read',async()=>{
 const input=checkpointFixture(),expected=structuredClone(input);let selected;
 const value=await readCheckpointReview({async reviewCheckpoint(original,limits){selected=original;
  assert.deepEqual(limits,{maxBytes:65536});input.subject.runId='mutated';input.reviewProjectionCid='sha256:'+'f'.repeat(64);return reviewFixture();},
  resolveCheckpoints:forbidden,start:forbidden},input,ticket());
 assert.deepEqual(selected,expected);assert.deepEqual(value.checkpoint,expected);assert.equal(value.artifactCid,reviewFixtureCid);
 assert.deepEqual(reviewText(value),{kind:'utf8',text:reviewFixtureText});assert(validReviewObservation(value,expected));
 const reordered=Object.fromEntries(Object.entries(expected).reverse());assert(validReviewObservation(value,reordered));
});
test('foreign Checkpoint/artifact, wrong bytes type and oversize are not returned as a review',async()=>{
 for(const value of [{...reviewFixture(),checkpointCid:'sha256:'+'a'.repeat(64)},
  {...reviewFixture(),artifactCid:'sha256:'+'a'.repeat(64)}, {...reviewFixture(),bytes:[1]},
  {...reviewFixture(),bytes:new Uint8Array(65537)}, {...reviewFixture(),allowed:true}])
  await assert.rejects(readCheckpointReview({reviewCheckpoint:async()=>value},checkpointFixture(),ticket()),{code:'ExplorerInvalidCheckpointReview'});
});
test('exact review byte ceiling is retained; binary is not decoded into a fake text or Effect diff',async()=>{
 const bytes=new Uint8Array(65536);bytes.fill(255);
 const value=await readCheckpointReview({reviewCheckpoint:async()=>({...reviewFixture(),bytes})},checkpointFixture(),ticket());
 assert.equal(value.byteLength,65536);const content=reviewText(value);assert.equal(content.kind,'binary');
 assert.equal(content.base64.length,87384);assert(!validReviewObservation({...value,byteLength:65537},checkpointFixture()));
 assert(!validReviewObservation({...value,checkpoint:{...value.checkpoint,subject:{...value.checkpoint.subject,runId:'foreign'}}},checkpointFixture()));
});
test('stale success and stale denial are discarded after scope switch without another read',async()=>{
 for(const denied of [false,true]){const epoch=createReadEpoch();let release,calls=0;
  const ready=new Promise(resolve=>release=resolve);
  const result=readCheckpointReview({async reviewCheckpoint(){calls++;await ready;if(denied)throw Error('private denial');return reviewFixture();}},checkpointFixture(),epoch.capture());
  epoch.invalidate();release();await assert.rejects(result,{code:'ExplorerStaleScope'});assert.equal(calls,1);
 }
});
test('public SDK verifies exact digest and refuses a corrupted read before the model sees it',async t=>{
 const calls=[];let corrupt=false;
 mock.method(globalThis,'fetch',async(url,init)=>{const op=url.pathname.split('/').at(-1);calls.push(op);
  if(op==='connect')return Response.json({version:'actql-client-host/0.1',mode:'remote',owner:'remote',durability:'durable',
   scopeRef:'scope-a',capabilities:['result-jsonl'],submissionEpoch,limits:{maxReadWireBytes:4096,maxRowWireBytes:1024,
    maxRowRetainedValueBytes:1024,maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:3,maxBatchRetainedValueBytes:1024}});
  assert.equal(op,'checkpoint-review');const body=JSON.parse(init.body);assert.equal(body.checkpointCid,checkpointFixture().checkpointCid);
  const bytes=new TextEncoder().encode(corrupt?'corrupted':reviewFixtureText);
  return Response.json({kind:'review',checkpointCid:body.checkpointCid,artifactCid:reviewFixtureCid,
   byteLength:bytes.length,contentBase64:Buffer.from(bytes).toString('base64')});
 });t.after(()=>mock.restoreAll());
 const client=await connect({mode:'remote',endpoint:'https://host.example/',token:'fixture-only'});
 try{assert.equal((await readCheckpointReview(client,checkpointFixture(),ticket())).artifactCid,reviewFixtureCid);
  corrupt=true;await assert.rejects(readCheckpointReview(client,checkpointFixture(),ticket()),{code:'ReviewIntegrityFailed'});
  assert.deepEqual(calls,['connect','checkpoint-review','checkpoint-review']);
 }finally{await client.close();}
});
test('missing capability and invalid original never create or answer a Checkpoint',async()=>{
 await assert.rejects(readWaitingCheckpoints({},ticket()),{code:'ExplorerCapabilityUnavailable'});
 await assert.rejects(readCheckpointReview({},checkpointFixture(),ticket()),{code:'ExplorerCapabilityUnavailable'});
 let calls=0;await assert.rejects(readCheckpointReview({reviewCheckpoint(){calls++;return reviewFixture();}},
 {...checkpointFixture(),allowed:true},ticket()),{code:'ExplorerInvalidCheckpointReview'});assert.equal(calls,0);
});
