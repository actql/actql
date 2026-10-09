import assert from 'node:assert/strict';
import test from 'node:test';
import * as wire from './index.mjs';
const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId:'original',authorityScopeCid:cid('a'),runDefinitionCid:cid('b')};
const owner = {kind:'effect',scopeCid:cid('c'),streamCid:cid('d')};
const view = () => ({ref,consistency:'non_atomic',ordering:'owner_local',
  owners:[{owner:'effect',ownerRef:{...owner},kind:'observed',snapshot:{revision:2,value:{state:'unknown'}},
    history:{kind:'page',entries:[{revision:1,entryCid:cid('1'),state:'prepared'},
      {revision:2,entryCid:cid('2'),state:'unknown'}],cursor:{owner:{...owner},value:'opaque'}}}],
  revisionVector:[{owner:{...owner},snapshotCid:cid('3'),historyHead:{generation:cid('1'),revision:2,entryCid:cid('2')}}]});

test('wire accepts only scoped independent Owner views and rejects false atomic claims', () => {
  const validate = wire.validOwnerObservations;
  assert.equal(typeof validate,'function');
  assert.equal(validate(view(),ref),true);
  for (const mutate of [value => {value.ref.runDefinitionCid=cid('f');},
    value => {value.consistency='atomic';},value => {value.revision=7;},
    value => {value.owners[0].ownerRef.streamCid=cid('f');},
    value => {value.revisionVector.push(value.revisionVector[0]);},
    value => {delete value.revisionVector[0].snapshotCid;},
    value => {value.owners[0].history.entries[1].revision=3;},
    value => {value.owners[0].history.entries[1].entryCid=cid('f');},
    value => {value.owners[0].history.cursor.owner.kind='run';},
    value => {value.owners[0].history={kind:'not_provided'};},
    value => {value.owners[0]={owner:'effect',kind:'unavailable'};}]) {
    const value = structuredClone(view()); mutate(value);
    assert.equal(validate(value,ref),false);
  }
});

test('wire distinguishes unsupported, expired, mismatch and failed history without granting replay', () => {
  assert.equal(typeof wire.validOwnerObservations,'function');
  for (const kind of ['not_provided','retention_expired','history_unrecoverable','cursor_mismatch','cursor_expired','acquisition_failed','limit_exceeded']) {
    const value = structuredClone(view()); value.owners[0].history={kind};
    delete value.revisionVector[0].historyHead;
    assert.equal(wire.validOwnerObservations(value,ref),true);
  }
  assert.equal(wire.validOwnerObservations(view(),ref,{maxEntries:1,maxWireBytes:65536}),false);
});

test('a nonempty retained history cannot claim a complete empty replay without a cursor',()=>{
  const value=view();
  value.owners[0].history={kind:'page',entries:[]};
  assert.equal(wire.validOwnerObservations(value,ref),false);
});
