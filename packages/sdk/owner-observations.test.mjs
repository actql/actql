import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {contentCid} from './checkpoints.mjs';
import {explainOwnerObservations, formatOwnerObservations} from './index.mjs';
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

// Fixed SHA-256 preimage uses raw data keys/strings, independently authored
// from the public snapshot domain; no product serializer supplies this CID.
test('SDK preserves decomposed result names and CRLF in a snapshot identity',async t=>{
  const original=JSON.parse("{\"ref\":{\"namespaceId\":\"original\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"consistency\":\"non_atomic\",\"ordering\":\"owner_local\",\"owners\":[{\"owner\":\"run\",\"ownerRef\":{\"kind\":\"run\",\"scopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"streamCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"kind\":\"observed\",\"snapshot\":{\"value\":{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"status\":\"failed\",\"updated_at\":\"2026-10-09T00:00:00.000Z\",\"next_action\":{\"kind\":\"none\"},\"result_available\":false,\"result_availability\":{\"é\":{\"state\":\"unknown\",\"observed_at\":\"2026-10-09T00:00:00.000Z\",\"reason\":\"store_query_failed\"}},\"terminal_error\":{\"code\":\"ACTQL_E_FIXTURE\",\"message\":\"é\\r\\n\"},\"revision\":1}},\"history\":{\"kind\":\"not_provided\"}}],\"revisionVector\":[{\"owner\":{\"kind\":\"run\",\"scopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"streamCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"snapshotCid\":\"sha256:99b639437a53888157960a79353bfce44ab231cad69c27098f32c7adb48d3b25\"}]}");
  const f=await fixture(t,()=>original);
  const value=await f.run.observeOwners();
  assert.deepEqual(Object.keys(value.owners[0].snapshot.value.result_availability),['e\u0301']);
  assert.equal(value.owners[0].snapshot.value.terminal_error.message,'e\u0301\r\n');
  assert.deepEqual(f.requests.map(request=>request.operation),['connect','attach','owner-observations']);
});

const historyMessages = {
  not_provided: 'This Owner provides a current view without transition history.',
  retention_expired: 'The Owner reports that the requested history is outside retained history.',
  history_unrecoverable: 'The Owner could not recover the requested history.',
  cursor_mismatch: 'The cursor does not match this Owner observation scope or stream.',
  cursor_expired: 'The supplied observation cursor has expired.',
  limit_exceeded: 'The observation budget could not cover the requested history.',
  acquisition_failed: 'The requested history could not be acquired.',
  page: 'The Owner returned a page of recorded transitions in Owner-local order.',
};
for (const [kind, summary] of Object.entries(historyMessages)) {
  test(`SDK explains ${kind} from the original Owner facts without I/O`, async t => {
    const original = await answer();
    if (kind !== 'page') {
      original.owners[0].history = {kind};
      delete original.revisionVector[0].historyHead;
    }
    const f = await fixture(t, () => original);
    const result = await f.run.observeOwners();
    const explanation = explainOwnerObservations(result);
    assert.equal(explanation.consistency, 'non_atomic', '[check-mutation:owner-consistency]');
    assert.equal(explanation.ordering, 'owner_local');
    assert.deepEqual(explanation.ref, ref);
    assert.deepEqual(explanation.revisionVector, result.revisionVector);
    assert.equal(explanation.owners[0].history.kind, kind, '[check-mutation:owner-history-kind]');
    assert.equal(explanation.owners[0].history.summary, summary, '[check-mutation:owner-history-summary]');
    assert.equal(explanation.controlRevision, undefined);
    assert.equal(explanation.owners[0].snapshot.revision, 1);
    assert.deepEqual(explanation.requested.cursors, []);
    assert.equal(explanation.lookupContext.scopeRef, 'caller');
    assert(Object.isFrozen(explanation.owners[0].history));
    assert.equal(explainOwnerObservations(structuredClone(result)), undefined, '[check-mutation:owner-copy]');
    assert.equal(formatOwnerObservations({...result}), undefined);
    assert.deepEqual(explainOwnerObservations(result, {locale: 'ja'}), explanation);
    for (const format of ['text', 'html', 'json']) assert.ok(formatOwnerObservations(result, {format}));
    assert.deepEqual(JSON.parse(formatOwnerObservations(result, {format: 'json'})).explanation, explanation);
    assert.deepEqual(f.requests.map(value => value.operation), ['connect', 'attach', 'owner-observations']);
  });
}

test('SDK keeps snapshot acquisition, protected streams and unmatched cursors separate', async t => {
  const original = await answer();
  delete original.owners[0].snapshot;
  original.owners[0].snapshotProblem = {kind: 'acquisition_failed'};
  delete original.revisionVector[0].snapshotCid;
  original.owners.push({owner: 'site', kind: 'unavailable'});
  original.unmatchedCursors = [{index: 0, kind: 'unavailable'}];
  const f = await fixture(t, () => original);
  const requested = {owner: {...owner, streamCid: cid('f')}, value: 'private-request-cursor'};
  const result = await f.run.observeOwners({cursors: [requested], maxEntries: 2});
  const explained = explainOwnerObservations(result);
  assert.equal(explained.owners[0].history.kind, 'page');
  assert.equal(explained.owners[0].snapshot, undefined);
  assert.equal(explained.owners[0].snapshotProblem.kind, 'acquisition_failed');
  assert.equal(explained.owners[0].snapshotProblem.summary, 'The current Owner snapshot could not be acquired.');
  assert.deepEqual(Object.keys(explained.owners[1]).sort(), ['hint', 'kind', 'owner', 'summary'],
    '[check-mutation:owner-protected]');
  assert.deepEqual(explained.unmatchedCursors, [{index: 0, kind: 'unavailable'}]);
  requested.owner.streamCid = cid('0');
  requested.value = 'changed';
  assert.deepEqual(explained.requested.cursors, [{owner: {...owner, streamCid: cid('f')}, value: 'private-request-cursor'}]);
  assert.equal(explained.requested.maxEntries, 2);
  assert.deepEqual(f.requests.map(value => value.operation), ['connect', 'attach', 'owner-observations']);
});

test('SDK response reuse cannot change earlier Owner facts or borrow a later request', async t => {
  const original = await answer();
  const f = await fixture(t, () => original);
  const first = await f.run.observeOwners({maxEntries: 1});
  const firstExplanation = explainOwnerObservations(first);
  const cursor = first.owners[0].history.cursor;
  original.owners[0].history = {kind: 'cursor_expired'};
  delete original.revisionVector[0].historyHead;
  const second = await f.run.observeOwners({cursors: [cursor], maxEntries: 3});
  assert.notEqual(second, first);
  assert.equal(firstExplanation.owners[0].history.kind, 'page', '[check-mutation:owner-reuse]');
  assert.deepEqual(firstExplanation.requested.cursors, []);
  assert.equal(firstExplanation.requested.maxEntries, 1);
  assert.equal(explainOwnerObservations(second).requested.maxEntries, 3);
  assert.equal(explainOwnerObservations(second).owners[0].history.kind, 'cursor_expired');
  assert.deepEqual(explainOwnerObservations(first), firstExplanation);
  assert.deepEqual(f.requests.map(value => value.operation), ['connect', 'attach', 'owner-observations', 'owner-observations']);
});

test('SDK formatting escapes disclosed values and refuses incomplete output', async t => {
  const original = await answer();
  original.ref = {...ref, namespaceId: '<script>e\u0301\r\n</script>'};
  // Fixture attachment still targets the fixed Run; a foreign response has no custody.
  const foreign = await fixture(t, () => original);
  let rejected;
  try { await foreign.run.observeOwners(); } catch (error) { rejected = error; }
  assert.equal(rejected.code, 'InvalidHostOwnerObservations');
  assert.equal(explainOwnerObservations(rejected), undefined);
  assert.equal(explainOwnerObservations(original), undefined);
  const valid = await answer();
  valid.owners[0].history.cursor.value = '<script>' + 'x'.repeat(2000);
  const f = await fixture(t, () => valid);
  const result = await f.run.observeOwners();
  const html = formatOwnerObservations(result, {format: 'html'});
  assert(!html.includes('<script>'));
  assert.equal(formatOwnerObservations(result, {maxBytes: 1024}), undefined);
  const before = explainOwnerObservations(result);
  const formatted = formatOwnerObservations(result, {format: 'json', get locale() {
    valid.owners[0].history = {kind: 'not_provided'};
    return 'en';
  }});
  assert.deepEqual(JSON.parse(formatted).explanation, before);
});

for (const [kind, summary] of Object.entries({
  acquisition_failed: 'The Owner observations could not be acquired.',
  limit_exceeded: 'The observation budget could not cover this Owner.',
  history_unrecoverable: 'The Owner observations could not be recovered.',
  cursor_mismatch: 'The supplied cursor could not be matched to this Owner observation.',
})) {
  test(`SDK explains unavailable ${kind} without inventing a stream identity`, async t => {
    const original = await answer();
    original.owners = [{owner: 'effect', kind: 'unavailable', problem: {kind}}];
    original.revisionVector = [];
    const f = await fixture(t, () => original);
    const result = await f.run.observeOwners();
    const explained = explainOwnerObservations(result);
    assert.equal(explained.owners[0].summary, summary);
    assert.deepEqual(explained.owners[0].problem, {kind});
    assert.equal(explained.owners[0].ownerRef, undefined);
    assert.deepEqual(explained.revisionVector, []);
    assert.deepEqual(f.requests.map(value => value.operation), ['connect', 'attach', 'owner-observations']);
  });
}
