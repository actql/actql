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
  t.after(()=>{journal.close();return rm(path,{recursive:true});});
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
  return{path,journal,ref,counts,requestControl:countedRequest,publicationControl:countedControl,
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
