import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {createClientOwnerCursorCodec} from './client-owner-cursor.mjs';
const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId:'ns', authorityScopeCid:cid('a'), runDefinitionCid:cid('b')};
const effectOwner = {kind:'effect', scopeCid:cid('c'), streamCid:cid('d')};
const runOwner = {kind:'run', scopeCid:cid('c'), streamCid:cid('b')};
const keys = generateKeyPairSync('ed25519');
const codec = createClientOwnerCursorCodec(keys);
const original = {revision:1,entryCid:cid('1'),entryJson:'{"state":"prepared"}'};
async function fixture(options = {}) {
  const {installClientOwnerObservations} = await import('./client-owner-observations.mjs');
  let allowed = true, ownerAllowed = true, reads = 0, runRevision = 7;
  const counters = {submitted:0,cancelled:0,sent:0};
  const sources = [
    {owner:runOwner, history:'not_provided', authorize:() => true,
      readSnapshot:async () => {reads++; return {revision:runRevision,value:{status:'running'}};}},
    {owner:effectOwner, history:'formal', authorize:() => ownerAllowed,
      readSnapshot:async () => {reads++; return {revision:1,value:{state:'prepared'}};},
      readPage:async ({after}) => ({kind:'page',generation:cid('1'),head:{revision:1,entryCid:cid('1')},
        previous:after === null ? null : original,entries:after === null ? [original] : []}), ...options.effect},
  ];
  const read = installClientOwnerObservations({authorizeRun:async () => allowed,
    sourcesFor:async () => sources, codec, maxEntries:8, maxWireBytes:8192});
  return {read:request => read({ref,...request}), counters, sources,
    get reads() {return reads;}, advanceRun() {runRevision=9;},
    denyRun() {allowed=false;}, denyOwner() {ownerAllowed=false;}};
}

test('mixed formal and current-only Owners report independent non-atomic observations', async () => {
  const f = await fixture(); const value = await f.read();
  assert.equal(value.consistency,'non_atomic');
  assert.equal(value.ordering,'owner_local');
  assert.deepEqual(value.ref,ref);
  assert.equal(value.owners[0].history.kind,'not_provided');
  assert.deepEqual(value.owners[0].snapshot,{revision:7,value:{status:'running'}});
  assert.equal(value.owners[1].history.kind,'page');
  assert.deepEqual(value.owners[1].history.entries,[{revision:1,entryCid:cid('1'),state:'prepared'}]);
  assert.equal(value.revision,undefined,'no global control revision is invented');
  assert.deepEqual(f.counters,{submitted:0,cancelled:0,sent:0});
});

for (const kind of ['retention_expired','history_unrecoverable','limit_exceeded']) {
  test(`Owner-certified ${kind} remains distinct from current snapshot and unsupported history`, async () => {
    const f = await fixture({effect:{readPage:async () => ({kind})}});
    const value = await f.read();
    assert.equal(value.owners[0].history.kind,'not_provided');
    assert.equal(value.owners[1].history.kind,kind);
    assert.equal(value.owners[1].snapshot.value.state,'prepared');
    assert.equal(value.owners[1].history.cursor,undefined);
    assert.deepEqual(f.counters,{submitted:0,cancelled:0,sent:0});
  });
}

test('one acquisition failure retains other Owner snapshots without claiming replay', async () => {
  const f = await fixture({effect:{readPage:async () => {throw new Error('PRIVATE_FAILURE');}}});
  const value = await f.read();
  assert.equal(value.owners[1].history.kind,'acquisition_failed');
  assert.equal(value.owners[0].snapshot.value.status,'running');
  assert(!JSON.stringify(value).includes('PRIVATE_FAILURE'));
});

test('current authorization precedes cursor decoding and is checked again after await', async () => {
  const f = await fixture(); const initial = await f.read();
  f.denyRun(); const before = f.reads;
  await assert.rejects(f.read({cursors:[initial.owners[1].history.cursor]}), {code:'RunObservationAccessDenied'});
  assert.equal(f.reads,before);
  const changed = await fixture({effect:{readSnapshot:async () => {
    changed.denyOwner(); return {revision:1,value:{secret:true}};
  }}});
  const value = await changed.read();
  assert.deepEqual(value.owners[1],{owner:'effect',kind:'unavailable'});
  assert(!JSON.stringify(value).includes('secret'));
});

test('foreign Run cursor gives a scoped mismatch, never a new execution or replay', async () => {
  const f = await fixture(); const first = await f.read();
  const next = await f.read({ref:{...ref,runDefinitionCid:cid('e')},cursors:[first.owners[1].history.cursor]});
  assert.equal(next.owners[1].history.kind,'cursor_mismatch');
  assert.equal(next.owners[1].history.entries,undefined);
  assert.deepEqual(f.counters,{submitted:0,cancelled:0,sent:0});
});

test('snapshot updates do not reconstruct unavailable transitions or order independent histories', async () => {
  const f = await fixture();
  const first = await f.read();
  f.advanceRun();
  const next = await f.read({cursors:[first.owners[1].history.cursor]});
  assert.equal(next.owners[0].history.kind,'not_provided');
  assert.equal(next.owners[0].snapshot.revision,9);
  assert.equal(next.owners[0].history.entries,undefined);
  assert.equal(next.consistency,'non_atomic');
  assert.equal(next.revision,undefined);
});

test('the composite response budget includes every snapshot, vector and signed cursor', async () => {
  const {installClientOwnerObservations} = await import('./client-owner-observations.mjs');
  const sources = ['run','effect','publication','delivery','site'].map((kind,index) => ({
    owner:{kind,scopeCid:cid('c'),streamCid:cid(String(index+1))}, history:'not_provided',
    authorize:() => true,
    readSnapshot:async () => ({revision:1,value:{text:'x'.repeat(3000)}}),
  }));
  const read = installClientOwnerObservations({authorizeRun:() => true,sourcesFor:() => sources,
    codec,maxEntries:8,maxWireBytes:4096});
  const value = await read({ref});
  assert(Buffer.byteLength(JSON.stringify(value),'utf8') <= 4096);
  assert(value.owners.every(view => view.snapshotProblem?.kind === 'limit_exceeded'));
  assert.equal(value.consistency,'non_atomic');
});

test('Owner binding and hooks are captured before asynchronous snapshot acquisition', async () => {
  const f = await fixture();
  f.sources[1].readSnapshot = async () => {
    f.sources[1].owner = {...effectOwner,streamCid:cid('f')};
    f.sources[1].readPage = () => {throw new Error('CHANGED_HOOK');};
    return {revision:1,value:{state:'prepared'}};
  };
  const value = await f.read();
  assert.equal(value.owners[1].history.kind,'page');
  assert.deepEqual(value.owners[1].history.cursor.owner,effectOwner);
});

test('a current-only Owner cannot silently accept a purported history cursor', async () => {
  const f = await fixture();
  const value = await f.read({cursors:[{owner:runOwner,value:'not-a-cursor'}]});
  assert.equal(value.owners[0].history.kind,'cursor_mismatch');
  assert.equal(value.owners[0].snapshot.value.status,'running');
});

test('a page whose terminal entry differs from its advertised head is not replay evidence', async () => {
  const f = await fixture({effect:{readPage:async () => ({kind:'page',generation:cid('1'),
    head:{revision:1,entryCid:cid('2')},previous:null,entries:[original]})}});
  const value = await f.read();
  assert.equal(value.owners[1].history.kind,'acquisition_failed');
  assert.equal(value.owners[1].history.cursor,undefined);
});

test('snapshot identity changes independently of the Run control revision', async () => {
  const f = await fixture();
  let status = 'running';
  f.sources[0].readSnapshot = async () => ({revision:7,value:{status,control:{revision:7}}});
  const first = await f.read();
  status = 'needs_reconciliation';
  const second = await f.read();
  assert.notEqual(first.revisionVector[0].snapshotCid,second.revisionVector[0].snapshotCid);
  assert.match(second.revisionVector[0].snapshotCid,/^sha256:[a-f0-9]{64}$/u);
  assert.equal(second.revisionVector[0].snapshotRevision,undefined);
  assert.equal(second.owners[0].snapshot.value.control.revision,7);
});

test('an unmatched cursor is explicitly unavailable without certifying protected history absence', async () => {
  const f=await fixture();
  const value=await f.read({cursors:[{owner:{...effectOwner,streamCid:cid('e')},value:'foreign'}]});
  assert.deepEqual(value.unmatchedCursors,[{index:0,kind:'unavailable'}]);
  assert.equal(value.owners[0].history.kind,'not_provided');
  assert.equal(value.owners[1].history.kind,'page');
  assert.deepEqual(f.counters,{submitted:0,cancelled:0,sent:0});
});

test('undisclosable and unbound cursor positions have the same unavailable projection',async()=>{
  const f=await fixture();f.denyOwner();
  for(const owner of [effectOwner,{...effectOwner,streamCid:cid('e')}]){
    const value=await f.read({cursors:[{owner,value:'candidate'}]});
    assert.deepEqual(value.owners[1],{owner:'effect',kind:'unavailable'});
    assert.deepEqual(value.unmatchedCursors,[{index:0,kind:'unavailable'}]);
    assert.equal(value.revisionVector.length,1);
  }
});

test('generic unavailable details do not expose the number of protected streams',async()=>{
  const f=await fixture();f.denyOwner();
  f.sources.push({...f.sources[1],owner:{...effectOwner,streamCid:cid('e')}});
  const value=await f.read();
  assert.deepEqual(value.owners.filter(view=>view.owner==='effect'),[{owner:'effect',kind:'unavailable'}]);
  assert.equal(value.revisionVector.length,1);
});

test('snapshot identity preserves data keys, decomposed Unicode and each newline form', async () => {
  const f=await fixture();
  let data={'e\u0301':'e\u0301\r\n'};
  f.sources[0].readSnapshot=async()=>({value:{data}});
  const first=await f.read();
  assert.deepEqual(first.owners[0].snapshot.value.data,{'e\u0301':'e\u0301\r\n'});
  const identities=[first.revisionVector[0].snapshotCid];
  for(const next of [{'é':'e\u0301\r\n'},{'e\u0301':'é\r\n'},{'e\u0301':'e\u0301\r'},{'e\u0301':'e\u0301\n'}]){
    data=next;
    identities.push((await f.read()).revisionVector[0].snapshotCid);
  }
  assert.equal(new Set(identities).size,5);
});
