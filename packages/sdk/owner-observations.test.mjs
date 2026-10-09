import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {contentCid} from './checkpoints.mjs';
const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId:'original',authorityScopeCid:cid('a'),runDefinitionCid:cid('b')};
const owner = {kind:'effect',scopeCid:cid('c'),streamCid:cid('d')};
const profile={version:'actql-client-host/0.1',mode:'local',owner:'local',durability:'durable',scopeRef:'caller',capabilities:[],
  limits:{maxReadWireBytes:4096,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:3,maxBatchRetainedValueBytes:1024}};
async function answer() {
  const snapshot={revision:1,value:{state:'prepared'}};
  return {ref,consistency:'non_atomic',ordering:'owner_local',owners:[{owner:'effect',ownerRef:{...owner},kind:'observed',snapshot,
    history:{kind:'page',entries:[{revision:1,entryCid:cid('1'),state:'prepared'}],cursor:{owner:{...owner},value:'opaque-original'}}}],
    revisionVector:[{owner:{...owner},snapshotCid:await contentCid({version:'actql-owner-snapshot/0.1',ref,owner,snapshot}),
      historyHead:{generation:cid('1'),revision:1,entryCid:cid('1')}}]};
}
async function fixture(t,reply) {
  const requests=[];
  const client=await connectInProcess({mode:'local',owner:'local'},{async perform(operation,body) {
    requests.push({operation,body});
    if(operation==='connect')return profile;
    if(operation==='attach')return {ref,durability:'durable',revision:1};
    return reply(body);
  }});
  t.after(()=>client.close());
  return {run:await client.attach(ref),requests};
}

test('SDK returns immutable scoped views and replays only requested cursors without execution',async t=>{
  const original=await answer();
  const f=await fixture(t,()=>original);
  assert.equal(typeof f.run.observeOwners,'function');
  const first=await f.run.observeOwners();
  const cursor=first.owners[0].history.cursor;
  const second=await f.run.observeOwners({cursors:[cursor],maxEntries:1,maxWireBytes:8192});
  assert.deepEqual(second,first);
  assert(Object.isFrozen(second.owners[0].snapshot));
  assert.deepEqual(f.requests.map(value=>value.operation),['connect','attach','owner-observations','owner-observations']);
  assert.deepEqual(f.requests.at(-1).body.cursors,[cursor]);
});

for(const alteration of ['foreign_run','false_atomic','false_snapshot_identity','foreign_cursor','extra_vector','borrowed_control_revision']) {
  test(`SDK rejects ${alteration} without retry or changing Run control`,async t=>{
    const original=await answer(); const copy=structuredClone(original);
    if(alteration==='foreign_run')copy.ref.runDefinitionCid=cid('f');
    if(alteration==='false_atomic')copy.consistency='atomic';
    if(alteration==='false_snapshot_identity')copy.revisionVector[0].snapshotCid=cid('f');
    if(alteration==='foreign_cursor')copy.owners[0].history.cursor.owner={...owner,streamCid:cid('f')};
    if(alteration==='extra_vector')copy.revisionVector.push(copy.revisionVector[0]);
    if(alteration==='borrowed_control_revision')copy.control={revision:7};
    const f=await fixture(t,()=>copy);
    assert.equal(typeof f.run.observeOwners,'function');
    await assert.rejects(f.run.observeOwners(),{code:'InvalidHostOwnerObservations'});
    assert.deepEqual(f.requests.map(value=>value.operation),['connect','attach','owner-observations']);
  });
}

test('SDK leaves acquisition and cursor gaps distinct and never refreshes by resubmitting',async t=>{
  const original=await answer();
  original.owners[0].history={kind:'retention_expired'};
  delete original.revisionVector[0].historyHead;
  const f=await fixture(t,()=>original);
  assert.equal(typeof f.run.observeOwners,'function');
  assert.equal((await f.run.observeOwners()).owners[0].history.kind,'retention_expired');
  assert.deepEqual(f.requests.map(value=>value.operation),['connect','attach','owner-observations']);
});
