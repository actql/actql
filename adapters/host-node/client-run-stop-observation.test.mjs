import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {observeNodeRestoredModelStop} from './client-dispatch-owner.mjs';
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
