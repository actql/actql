import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';

const source=readFileSync(new URL('./node-host-journal-installation.mjs',import.meta.url),'utf8');
const importLine="import {createRequire} from 'node:module';";
const requireExpression='createRequire(import.meta.url)';
assert.equal(source.split(importLine).length,2);
assert.equal(source.split(requireExpression).length,2);
assert.equal(source.split('export async function ').length,2);
// Execute the entire actual adapter with only its module loader/process entry
// substituted by explicit fixed Root ports. These are original forwarding and
// cleanup counters, not actual startup/resource/SQLite or installed admission.
const load=compileFunction(source.replace(importLine,'')
  .replace(requireExpression,'selectedRequire')
  .replace('export async function ','async function ')+
  '\nreturn prepareHostJournalInstallation;', ['selectedRequire','process']);

function fixture({open,missingOpen=false,admitRootFormat}={}){
  const original=Object.freeze({}),originals=Object.freeze({}),journal=Object.freeze({});
  const state={current:true,opens:0,closes:0,checks:0,pending:false,events:[]};
  const owner={prepareHostJournalInstallation(pair){assert.strictEqual(this,owner);
    assert.strictEqual(pair,originals);return original;},
  assertHostJournalInstallationCurrent(value,pair){assert.strictEqual(this,owner);
    assert.strictEqual(value,original);assert.strictEqual(pair,originals);
    state.events.push('current');state.checks++;
    if(!state.current)throw state.failure;},
  closeHostJournalInstallation(value,pair){assert.strictEqual(this,owner);
    assert.strictEqual(value,original);assert.strictEqual(pair,originals);state.closes++;
    return {pending:state.pending};}};
  if(!missingOpen)owner.openHostJournalRequestJournal=function(value,pair,directory,options){
    assert.strictEqual(this,owner);assert.strictEqual(value,original);assert.strictEqual(pair,originals);
    state.events.push('open');state.opens++;
    return open===undefined?journal:open({state,journal,directory,options});
  };
  if(admitRootFormat!==undefined)owner.admitHostJournalRootFormat=function(value,pair,root){
    assert.strictEqual(this,owner);assert.strictEqual(value,original);assert.strictEqual(pair,originals);
    return admitRootFormat(root);
  };
  const prepare=load(name=>{
    assert.equal(name,'./node-public-initial-control-bootstrap.cjs');return owner;
  },{execArgv:[],env:{}});
  return {prepare,owner,originals,journal,state};
}

test('Journal opening uses the captured Root operation and same opaque pair without inspecting options',async()=>{
  let reads=0;const options=new Proxy({}, {get(){reads++;throw Error('No adapter reads');},
    ownKeys(){reads++;throw Error('No adapter enumeration');}});
  const f=fixture({open:({directory,options:actual,journal})=>{
    assert.equal(directory,'/original/requests');assert.strictEqual(actual,options);return journal;
  }}),view=await f.prepare(f.originals);
  f.owner.openHostJournalRequestJournal=()=>assert.fail('Replacement must not run');
  assert.strictEqual(view.openRequestJournal('/original/requests',options),f.journal);
  assert.deepEqual(f.state.events,['current','current','open']);
  assert.equal(reads,0);assert.equal(f.state.opens,1);await view.close();
});

test('missing captured Journal operation refuses without a constructor or fallback',async()=>{
  const f=fixture({missingOpen:true}),view=await f.prepare(f.originals);
  f.owner.openHostJournalRequestJournal=()=>assert.fail('Late installation is not the original');
  assert.throws(()=>view.openRequestJournal('/original/requests',{}),
    {code:'HostJournalPreparationUnavailable'});
  assert.equal(f.state.opens,0);await view.close();
});

test('original currentness refuses before Journal allocation while its same close remains reachable',async()=>{
  const f=fixture(),view=await f.prepare(f.originals);
  const failure=new Error('OriginalGenerationRetired');f.state.failure=failure;f.state.current=false;
  assert.throws(()=>view.openRequestJournal('/original/requests',{}),error=>error===failure);
  assert.equal(f.state.opens,0);await view.close();assert.equal(f.state.closes,1);
  assert.throws(()=>view.openRequestJournal('/original/requests',{}),
    {code:'HostJournalPreparationUnavailable'});
});

test('a partial Root constructor failure preserves its exact same-child cleanup carrier',async()=>{
  const cleanup={status:()=>({pending:true}),retry:async()=>({pending:true})};
  const failure=Object.assign(new Error('OriginalNativeChildPending'),{cleanupHandle:cleanup});
  const f=fixture({open:({state})=>{state.current=false;throw failure;}});
  const view=await f.prepare(f.originals),checks=f.state.checks;
  assert.throws(()=>view.openRequestJournal('/original/requests',{}),error=>error===failure);
  assert.strictEqual(failure.cleanupHandle,cleanup);assert.equal(f.state.checks,checks+1);
  assert.equal(f.state.opens,1);assert.equal(f.state.closes,0);
  await view.close();assert.equal(f.state.closes,1);
});

test('a pending original facility close prevents another open until its own exact ACK',async()=>{
  const f=fixture(),view=await f.prepare(f.originals);f.state.pending=true;
  assert.deepEqual(await view.close(),{pending:true});
  assert.throws(()=>view.openRequestJournal('/original/requests',{}),
    {code:'HostJournalPreparationUnavailable'});
  f.state.pending=false;assert.deepEqual(await view.close(),{pending:false});
  assert.equal(f.state.opens,0);assert.equal(f.state.closes,2);
});

test('root-format admission forwards through the captured sixth Root operation and same original pair',async()=>{
  let calls=0;const marker={};
  const f=fixture({admitRootFormat(root){assert.equal(root,'/original');calls++;return marker;}});
  const view=await f.prepare(f.originals);
  f.owner.admitHostJournalRootFormat=()=>assert.fail('Replacement is not the original');
  assert.strictEqual(view.admitRootFormat('/original'),marker);
  assert.equal(calls,1);await view.close();
});

test('missing or retired root-format operation refuses before any fallback',async()=>{
  const f=fixture(),view=await f.prepare(f.originals);
  f.owner.admitHostJournalRootFormat=()=>assert.fail('Late installation is not original');
  assert.throws(()=>view.admitRootFormat('/original'),{code:'HostJournalPreparationUnavailable'});
  await view.close();
  assert.throws(()=>view.admitRootFormat('/original'),{code:'HostJournalPreparationUnavailable'});
  assert.equal(f.state.opens,0);
});

test('root-format failure preserves the same original cleanup and current refusal',async()=>{
  const failure=Object.assign(new Error('OriginalRootFormatPending'),{cleanupHandle:{}});
  const f=fixture({admitRootFormat(){throw failure;}}),view=await f.prepare(f.originals);
  assert.throws(()=>view.admitRootFormat('/original'),error=>error===failure);
  f.state.current=false;f.state.failure=new Error('OriginalGenerationRetired');
  assert.throws(()=>view.admitRootFormat('/original'),error=>error===f.state.failure);
  await view.close();assert.equal(f.state.closes,1);assert.equal(f.state.opens,0);
});
