import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {observeNodeRestoredModelStop} from './client-dispatch-owner.mjs';
import {issueInstalledUnpublishedRunState} from '../host-common/run-state-observation.mjs';
import {createLocalSigningOriginalReader} from './local-checkpoint-answer.mjs';
const moon=await import(process.env.ACTQL_TEST_COMMON_RUNTIME??new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const control=runtimeCore(moon).publicationControl;
const cid=digit=>'sha256:'+digit.repeat(64);
const limits={maxWireBytes:65536,maxNodes:4096,maxDepth:64};

// Actual Common-issued identity/Run, SQLite Journal and Node terminal caller.
// Store observation is explicit; this is not full Host execution or funding.
async function fixture(t){
  const path=await mkdtemp(join(tmpdir(),'actql-run-stop-frame-'));
  const journal=openClientRequestJournal(path);
  const journals=new Set([journal]);
  t.after(()=>{for(const original of journals)original.close();return rm(path,{recursive:true});});
  const identity=moon.clientRequestAdmitRecord(cid('a'),'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',cid('b'),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert(identity);
  const definition=control.seal('run_definition',JSON.stringify({version:'actql-run-definition/0.1',
    scope_id:'original-scope',run_id:'observed-run',compiled_plan_cid:cid('1'),
    invocation_template_cid:cid('2'),authorization_context_cid:cid('3'),input_artifact_set_cid:cid('4'),
    created_at:'2026-10-16T00:00:00.000Z',valid_until:'2098-01-01T00:00:00.000Z'}),limits);
  const ref=journal.acceptDefinition(identity,{namespaceId:'namespace-a',runDefinition:definition,
    lookupExpiresAt:'2099-01-01T00:00:00.000Z'},moon,control).ref;
  journal.reserveDispatch(identity,{namespaceId:ref.namespaceId,currentAuthorization:true},moon,control);
  assert.equal(journal.reservePhysicalStart(identity,{namespaceId:ref.namespaceId,ref,currentAuthorization:true},moon,control),true);
  const counts={requestIdentityAdmissions:0,runDefinitionAdmissions:0,store:0};
  const countedRequest=Object.freeze({...moon,clientRequestAdmitRecord(...args){
    counts.requestIdentityAdmissions++;return moon.clientRequestAdmitRecord(...args);
  }});
  const countedControl=Object.freeze({...control,admit(...args){
    counts.runDefinitionAdmissions++;return control.admit(...args);
  }});
  return{path,journal,journals,ref,counts,requestControl:countedRequest,publicationControl:countedControl,
    facts:{ref,journal,moon:countedRequest,control:countedControl,cleanupConfirmed:true,
      physicalStopConfirmed:true,store:{async confirmCommittedIndex(){counts.store++;return {};}}}};
}

function publishRunning(f,frame){
  const state=issueInstalledUnpublishedRunState(moon,{runId:'observed-run',observedAt:'2026-10-16T00:00:00.000Z',
    resultNames:['answer'],dispatchReserved:true,preDispatchFailureConfirmed:false,cancelledBeforeStart:false,
    observedTerminalOutcome:'none',executionUnknown:false});
  return JSON.parse(f.journal.publishRunState(frame,state,f.requestControl,f.publicationControl));
}

test('signing stop comparison accepts only the same Journal original physical-close progression', async t => {
  const f = await fixture(t);
  const before = f.journal.lookupRunDefinition(f.ref, f.requestControl, f.publicationControl);
  f.journal.markPhysicalClose(f.ref, null, before);
  const after = f.journal.lookupRunDefinition(f.ref, f.requestControl, f.publicationControl, before);
  assert.equal(after.revision, before.revision + 1);
  assert.equal(before.physicalCloseConfirmed, false); assert.equal(after.physicalCloseConfirmed, true);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, after), true);
  assert.equal(f.journal.canReinspectRunForSigning(before, after), true);
  assert.equal(f.journal.canReinspectRunForSigning(before, before), false);
  assert.equal(f.journal.canReinspectRunForSigning(after, before), false);
  assert.equal(f.journal.canReinspectRunForSigning({...before}, after), false);
  assert.equal(f.journal.canReinspectRunForSigning(before, {...after}), false);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, before), false);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose(after, before), false);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose({...before}, after), false);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, {...after}), false);
  const other = openClientRequestJournal(f.path); f.journals.add(other);
  const foreign = other.lookupRunDefinition(f.ref, f.requestControl, f.publicationControl);
  assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, foreign), false);
  assert.equal(f.journal.canReinspectRunForSigning(before, foreign), false);
  for (const [request, publication] of [[{...f.requestControl}, f.publicationControl],
    [f.requestControl, {...f.publicationControl}]]) {
    const foreignControl = f.journal.lookupRunDefinition(f.ref, request, publication);
    assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, foreignControl), false);
    assert.equal(f.journal.canReinspectRunForSigning(before, foreignControl), false);
  }
});

for (const [name, sql, parameters] of [
  ['same revision', 'UPDATE client_requests SET physical_close_confirmed=1', []],
  ['skipped revision', 'UPDATE client_requests SET physical_close_confirmed=1, revision=revision+2', []],
  ['revision without stop', 'UPDATE client_requests SET revision=revision+1', []],
  ['cancellation', 'UPDATE client_requests SET physical_close_confirmed=1, revision=revision+1, cancellation_requested=1', []],
  ['terminal outcome', "UPDATE client_requests SET physical_close_confirmed=1, revision=revision+1, observed_terminal_outcome='failed'", []],
  ['lookup lifetime', 'UPDATE client_requests SET physical_close_confirmed=1, revision=revision+1, lookup_expires_at=?', ['2099-02-01T00:00:00.000Z']],
  ['state publication', 'UPDATE client_requests SET physical_close_confirmed=1, revision=revision+1, state_revision=state_revision+1', []],
]) {
  test(`signing stop comparison refuses ${name} drift beside the original stop`, async t => {
    const f = await fixture(t);
    const before = f.journal.lookupRunDefinition(f.ref, f.requestControl, f.publicationControl);
    const writer = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {writer.prepare(sql).run(...parameters);} finally {writer.close();}
    const after = f.journal.lookupRunDefinition(f.ref, f.requestControl, f.publicationControl, before);
    assert.equal(f.journal.canReinspectRunAfterPhysicalClose(before, after), false);
    assert.equal(f.journal.canReinspectRunForSigning(before, after), false);
  });
}

for (const scenario of [
  {name: 'holds recovery while its original Journal records the physical stop', physical: true},
  {name: 'refuses cancellation during retained recovery', physical: true, cancellation: true},
  {name: 'preserves a published observation during retained signing recovery', publication: true},
  {name: 'preserves physical close plus a published observation during retained signing recovery', physical: true, publication: true},
  {name: 'refuses cancellation beside a published observation during retained signing recovery', physical: true, publication: true, cancellation: true},
  {name: 'refuses lookup lifetime drift beside a published observation during retained signing recovery', physical: true, publication: true, drift: true},
]) {
  test('actual signing reader ' + scenario.name, async t => {
  const cancellation = scenario.cancellation === true || scenario.drift === true;
  const f = await fixture(t), materials = {}, preview = {}, original = {}, managed = {};
  const recoveries = new Set(), events = [];
  let enter, release, stale;
  const entered = new Promise(resolve => {enter = resolve;});
  const stopped = new Promise(resolve => {release = resolve;});
  const publication = Object.freeze({...f.publicationControl,
    effectComputationPreviewSemanticCid(value) {assert.strictEqual(value, preview); return cid('7');}});
  const recovered = {materials, requestIdentity: {}, computation: {preview, invocation: {}},
    originalSubmittedIntent: {referenceWire: 'original-submission', assertCurrent() {events.push('original-current');}},
    assertUpdateSelectionCurrent() {events.push('selection-current');}};
  const publicationFixture = {...f, publicationControl: publication};
  if (scenario.publication && scenario.physical) publishRunning(publicationFixture,
    f.journal.lookupRunDefinition(f.ref, f.requestControl, publication));
  const read = createLocalSigningOriginalReader({namespaceId: f.ref.namespaceId,
    authorityScopeCid: f.ref.authorityScopeCid, moon: f.requestControl, control: publication, journal: f.journal,
    async restoreEffectManagedPreparation(ref) {
      assert.deepEqual(ref, f.ref); events.push('restore'); enter(); await stopped;
      return {managedEffect: managed, original};
    },
    async recoverEffectCapture(ref, signal, parent, retain, binding) {
      assert.deepEqual(ref, f.ref); assert.strictEqual(parent, managed); assert.strictEqual(binding, original);
      events.push('recover'); return recovered;
    },
    localSigningRecoveries: recoveries, assertCurrent() {events.push('host-current');},
    async releaseLocalSigningRecovery(value) {
      assert.strictEqual(value, recovered); assert(recoveries.has(value));
      events.push('release'); recoveries.delete(value);
    },
    clientOperationError: code => Object.assign(new Error(code), {code})});
  const answer = read({runDefinitionCid: f.ref.runDefinitionCid, requiredArtifact: {cid: cid('7')}}, undefined,
    async frame => {
      assert.strictEqual(frame.materials, materials); assert(recoveries.has(recovered));
      stale = frame.assertCurrent; frame.assertCurrent(); await Promise.resolve(); frame.assertCurrent();
      events.push('consume'); return 'original-consumed';
    });
  await entered;
  assert.deepEqual(events, ['restore']);
  const beforeStop = f.journal.lookupRunDefinition(f.ref, f.requestControl, publication);
  assert.equal(beforeStop.physicalCloseConfirmed, false);
  if (scenario.physical) f.journal.markPhysicalClose(f.ref, null, beforeStop);
  if (scenario.publication) publishRunning(publicationFixture,
    f.journal.lookupRunDefinition(f.ref, f.requestControl, publication));
  if (scenario.drift) {
    const writer = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
    finally {writer.close();}
  }
  if (scenario.cancellation) f.journal.requestCancellation(f.ref,
    {currentAuthorization: true, publicationCommitted: false}, f.requestControl, publication);
  release();
  if (cancellation) await assert.rejects(answer, {code: 'LocalSigningOriginalConflict'});
  else assert.equal(await answer, 'original-consumed');
  assert.equal(events.filter(value => value === 'restore').length, 1);
  assert.equal(events.filter(value => value === 'recover').length, 1);
  if (cancellation) {
    assert.equal(events.includes('consume'), false); assert.equal(stale, undefined);
    assert.equal(events.at(-1), 'release');
  } else {
    assert.deepEqual(events.slice(-2), ['consume', 'release']);
    assert.throws(stale, {code: 'LocalSigningOriginalConflict'});
  }
  assert.equal(recoveries.size, 0);
  assert.equal(events.filter(value => value === 'release').length, 1);
  });
}

test('stop state-only comparison accepts actual observation frames without promoting copies or foreign controls',async t=>{
  const f=await fixture(t),before=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  const published=publishRunning(f,before);
  assert.equal(published.revision,0,'Common keeps the first observation at its original zero counter');
  const after=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl,before);
  assert.notStrictEqual(before,after);assert.equal(before.revision,after.revision);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,after),true);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,before),false);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication({...before},after),false);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,{...after}),false);
  const other=openClientRequestJournal(f.path);f.journals.add(other);
  const foreign=other.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,foreign),false);
  const controls=f.journal.lookupRunDefinition(f.ref,{...f.requestControl},f.publicationControl);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,controls),false);
});

test('stop state-only comparison refuses an immutable same-revision change beside observation metadata',async t=>{
  const f=await fixture(t),before=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  publishRunning(f,before);
  const writer=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try{writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
  finally{writer.close();}
  const after=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl,before);
  assert.equal(after.revision,before.revision);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,after),false);
});

test('stop state-only comparison refuses a real cancellation control change',async t=>{
  const f=await fixture(t),before=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  f.journal.requestCancellation(f.ref,{currentAuthorization:true,publicationCommitted:false},f.requestControl,f.publicationControl);
  const changed=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  publishRunning(f,changed);
  const after=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  assert.equal(after.cancellationRequested,true);assert(after.revision>before.revision);
  assert.equal(f.journal.canReinspectRunStopAfterStatePublication(before,after),false);
});

test('physical stop observes one request identity and Run definition across the unchanged operation',async t=>{
  const f=await fixture(t);
  await observeNodeRestoredModelStop(f.facts);
  assert.equal(f.journal.lookupRunDefinition(f.ref,moon,control).physicalCloseConfirmed,true);
  assert.deepEqual(f.counts,{requestIdentityAdmissions:1,runDefinitionAdmissions:1,store:1},
    'Count actual heavy admissions separately, not helper entries or cache hits');
});

test('same original Run frame lookup reuses only a complete unchanged row',async t=>{
  const f=await fixture(t);
  const first=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  assert.strictEqual(f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl,first),first);
  assert.deepEqual(f.counts,{requestIdentityAdmissions:1,runDefinitionAdmissions:1,store:0});
  const writer=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try{writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
  finally{writer.close();}
  const changed=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl,first);
  assert.notStrictEqual(changed,first);assert.equal(changed.revision,first.revision);
  assert.equal(f.counts.requestIdentityAdmissions,2);assert.equal(f.counts.runDefinitionAdmissions,2);
});

test('physical stop refuses same-revision row mutation during its publication observation',async t=>{
  const f=await fixture(t);
  f.facts.store.confirmCommittedIndex=async()=>{
    const writer=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
    try{writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
    finally{writer.close();}
    return {};
  };
  await assert.rejects(observeNodeRestoredModelStop(f.facts),{message:'ClientRunStopObservationChanged'});
  assert.equal(f.journal.lookupRunDefinition(f.ref,moon,control).physicalCloseConfirmed,false);
});

test('physical close mutation consumes the exact same-Journal complete original frame',async t=>{
  const f=await fixture(t);
  const original=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  assert.throws(()=>f.journal.markPhysicalClose(f.ref,null,{...original}),{code:'ForeignRunStateObservation'});
  const writer=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
  try{writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
  finally{writer.close();}
  assert.throws(()=>f.journal.markPhysicalClose(f.ref,null,original),{code:'ClientRunStopObservationChanged'});
  assert.equal(f.journal.lookupRunDefinition(f.ref,moon,control).physicalCloseConfirmed,false);
});

test('Run lookup reuse refuses copied foreign-control Journal and selected-key frames',async t=>{
  const f=await fixture(t),original=f.journal.lookupRunDefinition(f.ref,f.requestControl,f.publicationControl);
  const other=openClientRequestJournal(f.path);f.journals.add(other);
  const lookup=(owner=f.journal,ref=f.ref,request=f.requestControl,publication=f.publicationControl,frame=original)=>
    owner.lookupRunDefinition(ref,request,publication,frame);
  for(const frame of[{...original},Object.freeze({})])assert.throws(()=>lookup(undefined,undefined,undefined,undefined,frame),
    {code:'ForeignRunStateObservation'});
  assert.throws(()=>lookup(other),{code:'ForeignRunStateObservation'});
  assert.throws(()=>lookup(undefined,undefined,{...f.requestControl}),{code:'ForeignRunStateObservation'});
  assert.throws(()=>lookup(undefined,undefined,undefined,{...f.publicationControl}),{code:'ForeignRunStateObservation'});
  for(const ref of[{...f.ref,namespaceId:'other'},{...f.ref,authorityScopeCid:cid('f')},
    {...f.ref,runDefinitionCid:cid('f')}])assert.throws(()=>lookup(undefined,ref),{code:'ForeignRunStateObservation'});
  f.journal.close();assert.throws(()=>lookup(),{code:'ClientRequestJournalClosed'});
});

test('physical stop transaction rejects mutation during the terminal decision callback',async t=>{
  const f=await fixture(t);
  const original=f.facts.control;
  f.facts.control=Object.freeze({...original,runCancellationConfirmed(facts){
    const result=original.runCancellationConfirmed(facts);
    const writer=new DatabaseSync(join(f.path,'client-requests.sqlite3'));
    try{writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
    finally{writer.close();}
    return result;
  }});
  await assert.rejects(observeNodeRestoredModelStop(f.facts),{code:'ClientRunStopObservationChanged'});
  assert.equal(f.journal.lookupRunDefinition(f.ref,moon,control).physicalCloseConfirmed,false);
});

test('physical stop keeps actual cleanup prerequisites and skips an already recorded publication inspection',async t=>{
  const f=await fixture(t);
  await observeNodeRestoredModelStop({...f.facts,cleanupConfirmed:false});
  await observeNodeRestoredModelStop({...f.facts,physicalStopConfirmed:false});
  assert.deepEqual(f.counts,{requestIdentityAdmissions:0,runDefinitionAdmissions:0,store:0});
  f.journal.markPhysicalClose(f.ref,null);
  await observeNodeRestoredModelStop(f.facts);
  assert.deepEqual(f.counts,{requestIdentityAdmissions:1,runDefinitionAdmissions:1,store:0});
});

for(const afterCommit of[false,true]){
test(`physical stop preserves ${afterCommit?'committed':'rolled-back'} COMMIT Unknown without another dispatch`,async t=>{
  const exec=DatabaseSync.prototype.exec;
  let armed=false,lost=false;
  t.mock.method(DatabaseSync.prototype,'exec',function(sql){
    if(armed&&!lost&&sql==='COMMIT'){
      lost=true;if(afterCommit)Reflect.apply(exec,this,[sql]);
      throw new Error('original physical stop COMMIT reply lost');
    }
    return Reflect.apply(exec,this,[sql]);
  });
  const f=await fixture(t);
  f.facts.store.confirmCommittedIndex=async()=>{armed=true;return {};};
  await assert.rejects(observeNodeRestoredModelStop(f.facts),error=>
    error.code==='ClientRunStopObservationUnknown'&&error.outcome==='unknown');
  assert.equal(lost,true,'the captured original COMMIT path was actually reached');
  assert.equal(f.journal.lookupRunDefinition(f.ref,moon,control).physicalCloseConfirmed,afterCommit);
  assert.deepEqual(f.counts,{requestIdentityAdmissions:1,runDefinitionAdmissions:1,store:0});
});
}
