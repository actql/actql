import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
const control=runtimeCore(moon).publicationControl;
const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:100};
const fixture=JSON.parse(readFileSync(new URL('./fixtures/publication-global-golden.json',import.meta.url),'utf8'));
const all=fixture.contracts.map(c=>({...c,body:JSON.parse(c.wire),original:control.admit(c.name,c.wire,limits)}));
const one=name=>all.find(c=>c.name===name);
const chain={runDefinition:one('run_definition').original,invocation:one('run_invocation').original,
 manifest:control.admit('result_manifest',JSON.stringify(one('run_receipt').body.result_manifest),limits),
 receipt:one('run_receipt').original,capturedRun:one('captured_run').original,
 durableBindings:all.filter(c=>c.name==='durable_result_binding').map(c=>c.original),
 request:one('publication_request').original,attempt:one('publication_attempt').original};
test('shared index emitter retains original canonical wire and CID, exact/one-short',()=>{
 const golden=one('public_index_entry');
 const actual=control.issuePublicIndexEntry(chain,golden.body.committed_at,limits);
 assert.equal(actual.wire,golden.wire);assert.equal(actual.identity,golden.body.public_index_entry_cid);
 const exact=Buffer.byteLength(actual.wire);
 assert.equal(control.issuePublicIndexEntry(chain,golden.body.committed_at,{...limits,maxWireBytes:exact}).wire,golden.wire);
 assert.throws(()=>control.issuePublicIndexEntry(chain,golden.body.committed_at,{...limits,maxWireBytes:exact-1}));
});
test('shared progress emitter retains each prior canonical wire and CID, exact/one-short',()=>{
 const records=all.filter(c=>c.name==='publication_record').sort((a,b)=>a.body.sequence-b.body.sequence);
 let previous;
 for(const golden of records){
  const update={state:golden.body.state,observedAt:golden.body.observed_at,
   publicIndexEntry:golden.body.public_index_entry_cid?one('public_index_entry').original:undefined,
   cleanupOwnerCids:[],uncommittedConfirmed:false};
  const actual=control.issuePublicationRecord(chain.attempt,previous,update,limits);
  assert.equal(actual.wire,golden.wire);assert.equal(actual.identity,golden.body.publication_record_cid);
  const exact=Buffer.byteLength(actual.wire);
  assert.equal(control.issuePublicationRecord(chain.attempt,previous,update,{...limits,maxWireBytes:exact}).wire,golden.wire);
  assert.throws(()=>control.issuePublicationRecord(chain.attempt,previous,update,{...limits,maxWireBytes:exact-1}));
  previous=actual;
 }
});
test('frontier exposes independently funded possible winner terminal, covers actual serialization',()=>{
 const frontier=control.ordinaryPublicationFrontierByteBounds(chain.request,chain.durableBindings.length,limits);
 assert.equal(frontier.index,Buffer.byteLength(one('public_index_entry').wire));
 for(const c of all.filter(c=>c.name==='publication_record')){
  const key=c.body.state==='succeeded'?'terminal':c.body.state;
  assert.ok(frontier.current[key]>=Buffer.byteLength(c.wire));
 }
 assert.equal(frontier.possibleForeignWinnerTerminal,frontier.current.terminal);
 assert.ok(Object.isFrozen(frontier)&&Object.isFrozen(frontier.current));
 console.log('frontier bytes',JSON.stringify(frontier));
});

test('resolved foreign winner missing terminal adds its success and unknown loser cancellation',async()=>{
 const {parse}=await import('acorn');
 const source=readFileSync(new URL('./run-publication.mjs',import.meta.url),'utf8');
 const names=new Set(['appendState','finishCommittedAttempt','finishSupersededAttempt','finishResolvedCommit']);
 const chunks=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body
  .filter(node=>node.type==='FunctionDeclaration'&&names.has(node.id?.name))
  .map(node=>source.slice(node.start,node.end));
 assert.equal(chunks.length,4);
 const finish=new Function('member','fail',`${chunks.join('\n')}\nreturn finishResolvedCommit;`)
  ((value,key)=>value?.[key],code=>{throw Object.assign(new Error(code),{code});});
 const loser=control.issuePublicationAttempt(chain.request,chain.runDefinition,{attemptId:'frontier-loser',fenceCid:one('publication_attempt').body.fence_cid,externalIdempotencyKey:'frontier-loser',startedAt:'2026-10-24T03:49:58.644Z'},limits);
 const history=new Map(),written=[];
 const emit=(attempt,previous,state,index)=>control.issuePublicationRecord(attempt,previous,
  {state,observedAt:'2026-10-24T03:49:58.781Z',publicIndexEntry:index,
   cleanupOwnerCids:[],uncommittedConfirmed:false},limits);
 let previous;
 for(const state of ['preparing','committing','publication_unknown']){
  previous=emit(loser,previous,state);written.push(previous);
 }
 history.set(loser.identity,previous);
 const winnerCommitting=all.find(c=>c.name==='publication_record'&&c.body.state==='committing').original;
 history.set(chain.attempt.identity,winnerCommitting);
 const store={
  async latestRecordContract(cid){return history.get(cid);},
  async readPublicationContract(cid,kind){assert.equal(cid,chain.attempt.identity);assert.equal(kind,'publication_attempt');return chain.attempt;},
  async appendRecord(wire){const record=control.admit('publication_record',wire,limits);written.push(record);history.set(JSON.parse(wire).publication_attempt_cid,record);},
  async retireUncommittedPublication(cid){assert.equal(cid,'loser-candidate');return {cleanup:undefined};},
 };
 await finish(store,control,loser,{identity:'loser-candidate'},one('public_index_entry').original,
  ()=>'2026-10-24T03:49:58.781Z',limits);
 assert.equal(written.length,5);
 assert.deepEqual(written.slice(3).map(c=>JSON.parse(c.wire).state),['succeeded','cancelled']);
 assert.equal(JSON.parse(written[3].wire).publication_attempt_cid,chain.attempt.identity);
 assert.equal(JSON.parse(written[4].wire).publication_attempt_cid,loser.identity);
 const f=control.ordinaryPublicationFrontierByteBounds(chain.request,1,limits);
 const progressBudget=Object.values(f.current).reduce((a,b)=>a+b,0)+f.possibleForeignWinnerTerminal;
 assert.ok(written.reduce((sum,c)=>sum+Buffer.byteLength(c.wire),0)<=progressBudget);
});


test('shared Manifest skeleton counts full artifacts, retaining canonical issuance bytes',()=>{
 const golden=JSON.stringify(one('run_receipt').body.result_manifest);
 const actual=control.issueResultManifest(chain.runDefinition,chain.invocation,
  [one('result_definition').original],[one('result_artifact').original],limits);
 assert.equal(actual.wire,golden);
 const f=control.ordinaryPublicationFrontierByteBounds(chain.request,1,limits);
 assert.ok(f.manifest>=Buffer.byteLength(golden));
 // Only future actual_row_count uses Int width here (10 digits rather than 1).
 assert.equal(f.manifest-Buffer.byteLength(golden),9);
 assert.throws(()=>control.ordinaryPublicationFrontierByteBounds(chain.request,2,limits));
});

test('capacity projection rejects foreign originals and inventory mismatch; exhausted proof stays conservative',()=>{
 assert.throws(()=>control.ordinaryPublicationFrontierByteBounds({...chain.request},1,limits),/Foreign/);
 assert.throws(()=>control.ordinaryPublicationFrontierByteBounds(chain.request,0,limits),/projection/);
 assert.throws(()=>control.ordinaryPublicationReceiptByteBound({admission:{},receiptEvidence:{}},chain.request,limits),/Foreign Run publication admission/);
 const tiny=control.ordinaryPublicationFrontierByteBounds(chain.request,1,{...limits,maxWireBytes:1});
 assert.equal(tiny.manifest,1);assert.equal(tiny.index,1);
 assert.deepEqual(Object.values(tiny.current),[1,1,1,1]);
 assert.equal(tiny.possibleForeignWinnerTerminal,1);
});
