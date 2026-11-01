import test from 'node:test';
import assert from 'node:assert/strict';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
test('Pure Local frozen submission aliases share a retiring preparation slot', async () => {
  const registry = installLocalPreparationRegistry(value => value.pure === true);
  const prepared = {pure: true};
  const handle = registry.adopt(prepared);
  assert.notEqual(handle, prepared);
  assert.equal(registry.adopt(prepared), handle);
  const candidate = Object.freeze(registry.attach({id: 1}, handle));
  const submission = registry.attach({id: 1}, handle);
  assert.equal(candidate.preparedProgram, prepared);
  assert.equal(Object.hasOwn(Object.getOwnPropertyDescriptor(candidate, 'preparedProgram'), 'value'), false);
  const dispatch = registry.begin(submission);
  await Promise.resolve();
  assert.equal(dispatch.preparedProgram, prepared);
  assert.equal(candidate.preparedProgram, prepared);
  assert.throws(() => registry.begin(submission), /AlreadyDispatched/);
  dispatch.retire(); dispatch.retire();
  assert.throws(() => candidate.preparedProgram, /BorrowReleased|Retired/);
  assert.throws(() => submission.preparedProgram, /BorrowReleased|Retired/);
  assert.throws(() => dispatch.preparedProgram, /BorrowReleased|Retired/);
});
test('generic Source Effect and Model routes are not adopted', () => {
  const registry = installLocalPreparationRegistry(() => false);
  const prepared = {};
  assert.equal(registry.adopt(prepared), prepared);
  const submission = registry.attach({}, prepared);
  assert.equal(submission.preparedProgram, prepared);
  assert.equal(registry.begin(submission), undefined);
});
test('handler and dispatch share input descriptors until both original owners finish', async () => {
  const registry = installLocalPreparationRegistry(() => true);
  const input = Object.freeze({text: 'SELECT 1', format: 'sql'}), parameters = Object.freeze({x: 1});
  const request = registry.capture(Object.freeze({kind: 'aql', input, parameters}));
  assert.throws(() => registry.copy(request, {input: {}}), /SnapshotMutation/);
  assert.throws(() => registry.copy(request, {parameters: {}}), /SnapshotMutation/);
  const derived = registry.copy(request, {requestId: 'original'});
  const handle = registry.adopt({}, derived);
  const submission = Object.freeze(registry.attach(registry.copy(derived), handle));
  const candidate = Object.freeze(registry.attach(registry.copy(derived), handle));
  for (const value of [request, derived, submission, candidate]) {
    assert.equal(value.input, input);
    assert.equal(Object.hasOwn(Object.getOwnPropertyDescriptor(value, 'input'), 'value'), false);
  }
  const dispatch = registry.begin(submission);
  dispatch.retire();
  // Result cleanup may finish before the submitting handler's final await.
  await Promise.resolve();
  assert.equal(request.input, input);
  registry.finishHandler(request);
  registry.finishHandler(request);
  for (const value of [request, derived, submission, candidate]) assert.throws(() => value.input, /Retired/);
  assert.equal(input.text, 'SELECT 1'); // Caller-owned data is never mutated.
});
test('dispatch continues after handler return and later releases all input aliases', () => {
  const registry = installLocalPreparationRegistry(() => true);
  const request = registry.capture({kind: 'program', input: {stages: []}, parameters: null});
  const handle = registry.adopt({}, request);
  const submission = registry.attach(registry.copy(request), handle);
  const dispatch = registry.begin(submission);
  registry.finishHandler(request);
  assert.deepEqual(submission.input, {stages: []});
  assert.ok(dispatch.preparedProgram);
  dispatch.retire();
  assert.throws(() => submission.input, /Retired/);
});
test('handler failure before dispatch preserves original preparation for uncertain setup cleanup', () => {
  const registry = installLocalPreparationRegistry(() => true);
  const request = registry.capture({kind:'aql',input:{text:'SELECT 1'},parameters:null});
  const prepared = {}, handle = registry.adopt(prepared, request);
  const candidate = Object.freeze(registry.attach(registry.copy(request),handle));
  registry.finishHandler(request);
  assert.equal(candidate.preparedProgram,prepared);
  assert.deepEqual(candidate.input,{text:'SELECT 1'});
});

test('retirement continuation retries after dispatch slots clear without rereading the body', () => {
  let begun=0,finished=0,handlerDone=false;
  const prepared={};
  const registry=installLocalPreparationRegistry(()=>true, original=>{
    assert.equal(original,prepared);begun++;
    return ()=>{finished++;if(!handlerDone)throw new Error('OriginalCleanupPending');};
  });
  const request=registry.capture({kind:'program',input:{stages:[]},parameters:null});
  const handle=registry.adopt(prepared,request);
  const submission=registry.attach(registry.copy(request),handle);
  const dispatch=registry.begin(submission);
  assert.throws(()=>dispatch.retire(),/OriginalCleanupPending/);
  assert.throws(()=>dispatch.preparedProgram,/BorrowReleased/);
  assert.equal(submission.preparedProgram,prepared); // Original handler still owns its slot.
  registry.finishHandler(request);handlerDone=true;
  assert.throws(()=>submission.preparedProgram,/Retired/);
  dispatch.retire();dispatch.retire();
  assert.equal(begun,1);assert.equal(finished,2);
});

test('Core handler and dispatch tokens return only after their JS payload slots are severed',()=>{
 const prepared={},tokens=new Set();let begun=false,request,submission;
 const token=()=>{const value={};tokens.add(value);return value;};
 const handler=token();
 const runtime={clientProgramPreparationBorrowRead(h){assert(tokens.has(h));return prepared;},
 clientProgramPreparationBorrowSibling(h){assert.equal(h,handler);return {$tag:1,_0:token()};},
 clientProgramPreparationBorrowReturn(h){assert(tokens.delete(h));
   if(tokens.size===0){assert.throws(()=>request.input,/Retired/);assert.throws(()=>submission.preparedProgram,/Retired/);}
   return {$tag:1,_0:tokens.size===0};}};
 const registry=installLocalPreparationRegistry(()=>true,()=>{begun=true;return()=>{
   if(tokens.size)throw new Error('OriginalCoreCleanupPending');
 };},{runtime,borrow:()=>handler});
 request=registry.capture({kind:'program',input:{stages:[]},parameters:null});
 const handle=registry.adopt(prepared,request);submission=registry.attach(registry.copy(request),handle);
 const dispatch=registry.begin(submission);assert.equal(tokens.size,2);
 assert.throws(()=>dispatch.retire(),/OriginalCoreCleanupPending/);assert(begun);assert.equal(tokens.size,1);
 assert.equal(submission.preparedProgram,prepared);
 registry.finishHandler(request);assert.equal(tokens.size,0);
 dispatch.retire();dispatch.retire();
});
test('foreign Core handler body is returned to its original owner before rejection',()=>{
 let returned=0;const holder={};
 const runtime={clientProgramPreparationBorrowRead:()=>({}),
 clientProgramPreparationBorrowSibling(){assert.fail();},
 clientProgramPreparationBorrowReturn(h){assert.equal(h,holder);returned++;return {$tag:1,_0:false};}};
 const registry=installLocalPreparationRegistry(()=>true,undefined,{runtime,borrow:()=>holder});
 assert.throws(()=>registry.adopt({}),/ForeignLocalPreparationResource/);assert.equal(returned,1);
});

test('Host close retires finished undispatched original, not uncertain handler completion', () => {
  let starts=0, finishes=0;
  const prepared={};
  const registry=installLocalPreparationRegistry(()=>true, original=>{
    assert.equal(original,prepared); starts++; return()=>{finishes++;};
  });
  const request=registry.capture({kind:'program',input:{stages:[]}});
  const handle=registry.adopt(prepared,request);
  const submission=registry.attach(registry.copy(request),handle);
  registry.finishHandler(request);
  assert.equal(submission.preparedProgram,prepared);
  registry.retireQuiescentUndispatched(); registry.retireQuiescentUndispatched();
  assert.equal(starts,1); assert.equal(finishes,1);
  assert.throws(()=>submission.preparedProgram,/Retired/);
  assert.throws(()=>registry.begin(submission),/RegistryClosing/);
  assert.throws(()=>registry.adopt({}),/RegistryClosing/);
});

test('Host close refuses active handler without cutting it, then retries original', () => {
  let starts=0;
  const registry=installLocalPreparationRegistry(()=>true,()=>{starts++;});
  const request=registry.capture({kind:'program',input:{stages:[]}});
  const prepared={},handle=registry.adopt(prepared,request);
  const submission=registry.attach(registry.copy(request),handle);
  assert.throws(()=>registry.retireQuiescentUndispatched(),/HandlerCleanupPending/);
  assert.equal(starts,0); assert.equal(submission.preparedProgram,prepared);
  registry.finishHandler(request); registry.retireQuiescentUndispatched();
  assert.equal(starts,1); assert.throws(()=>request.input,/Retired/);
});

for (const failReturn of [false,true]) test(`undispatched close retries light continuation; consumed return failure=${failReturn}`,()=>{
  const prepared={},holder={}; let returns=0,starts=0,finishes=0,request;
  const runtime={clientProgramPreparationBorrowRead:()=>prepared,
    clientProgramPreparationBorrowSibling(){assert.fail('No new dispatch holder');},
    clientProgramPreparationBorrowReturn(token){
      assert.equal(token,holder);returns++;
      assert.throws(()=>request.input,/Retired/);
      if(failReturn)throw new Error('ConsumedReturnSettlementPending');
      return {$tag:1,_0:true};
    }};
  const registry=installLocalPreparationRegistry(()=>true,()=>{
    starts++; return()=>{finishes++;if(finishes===1)throw new Error('OriginalCleanupPending');};
  },{runtime,borrow:()=>holder});
  request=registry.capture({kind:'program',input:{stages:[]}});
  registry.adopt(prepared,request); registry.finishHandler(request);
  assert.throws(()=>registry.retireQuiescentUndispatched(), failReturn ? /ConsumedReturn/ : /OriginalCleanupPending/);
  if(failReturn) assert.throws(()=>registry.retireQuiescentUndispatched(),/OriginalCleanupPending/);
  registry.retireQuiescentUndispatched(); registry.retireQuiescentUndispatched();
  assert.equal(returns,1); assert.equal(starts,1); assert.equal(finishes,2);
});

test('held original may dispatch after handler completion before Host close',()=>{
  const registry=installLocalPreparationRegistry(()=>true);
  const request=registry.capture({kind:'program',input:{stages:[]}});
  const handle=registry.adopt({},request),submission=registry.attach(registry.copy(request),handle);
  registry.finishHandler(request);
  const dispatch=registry.begin(submission);
  dispatch.retire();
  assert.throws(()=>request.input,/Retired/);
  registry.retireQuiescentUndispatched();
});

test('unselected source snapshot is not retired by Pure installation-close hook',()=>{
  const registry=installLocalPreparationRegistry(()=>false,()=>assert.fail());
  const input={stages:[]},request=registry.capture({kind:'program',input});
  registry.adopt({},request); registry.finishHandler(request);
  registry.retireQuiescentUndispatched(); assert.equal(request.input,input);
});

test('initial retirement cuts only the exact finished, retiring original without closing other entries',()=>{
 const prepared={},other={},holder={},otherHolder={};let retiring=false,returns=0,started=0;
 const values=new Map([[holder,prepared],[otherHolder,other]]);
 const runtime={clientProgramPreparationBorrowRead:h=>values.get(h),
  clientProgramPreparationBorrowSibling(){assert.fail('No dispatch');},
  clientProgramPreparationBorrowRetirementStarted:h=>h===holder&&retiring,
  clientProgramPreparationBorrowReturn(h){assert.equal(h,holder);returns++;return {$tag:1,_0:false};}};
 const registry=installLocalPreparationRegistry(()=>true,()=>{started++;},{runtime,borrow:p=>p===prepared?holder:otherHolder});
 const request=registry.capture({kind:'program',input:{x:1}}),active=registry.capture({kind:'program',input:{x:2}});
 registry.adopt(prepared,request);registry.adopt(other,active);
 assert.throws(()=>registry.retireRetiringOriginal(prepared),/HandlerCleanupPending/);
 registry.finishHandler(request);
 assert.throws(()=>registry.retireRetiringOriginal(prepared),/RetirementNotStarted/);
 retiring=true;
 registry.retireRetiringOriginal({});assert.equal(returns,0);
 registry.retireRetiringOriginal(prepared);registry.retireRetiringOriginal(prepared);
 assert.equal(returns,1);assert.equal(started,1);assert.throws(()=>request.input,/Retired/);
 assert.deepEqual(active.input,{x:2});
 assert.throws(()=>registry.retireRetiringOriginal(other),/HandlerCleanupPending/);
 assert.ok(registry.capture({kind:'program',input:{x:3}}));
});

test('initial retirement retry does not reread a consumed Core handler',()=>{
 const prepared={},holder={};let returned=false,returns=0;
 const runtime={clientProgramPreparationBorrowRead(h){assert.equal(returned,false);assert.equal(h,holder);return prepared;},
  clientProgramPreparationBorrowSibling(){assert.fail();},
  clientProgramPreparationBorrowRetirementStarted:()=>true,
  clientProgramPreparationBorrowReturn(){returned=true;returns++;throw Error('ConsumedSettlementPending');}};
 const registry=installLocalPreparationRegistry(()=>true,()=>undefined,{runtime,borrow:()=>holder});
 const request=registry.capture({kind:'program',input:{x:1}});registry.adopt(prepared,request);registry.finishHandler(request);
 assert.throws(()=>registry.retireRetiringOriginal(prepared),/ConsumedSettlementPending/);
 registry.retireRetiringOriginal(prepared);assert.equal(returns,1);
});

test('Request registry cannot select a domain body without an actual original Core borrower', () => {
  let borrows = 0, returns = 0, retirements = 0;
  const prepared = {}, runtime = {
    clientProgramPreparationBorrowRead() {assert.fail('No borrower was issued');},
    clientProgramPreparationBorrowSibling() {assert.fail('No dispatch borrower may be issued');},
    clientProgramPreparationBorrowReturn() {returns++; assert.fail('No borrower may be returned');},
  };
  const registry = installLocalPreparationRegistry(() => true, () => {retirements++;}, {
    runtime, borrow() {borrows++; return undefined;},
  });
  const input = {stages: []}, request = registry.capture({kind: 'program', input});
  const original = registry.adopt(prepared, request);
  assert.equal(original, prepared);
  const submission = registry.attach(registry.copy(request), original);
  assert.equal(submission.preparedProgram, prepared);
  assert.equal(registry.begin(submission), undefined);
  registry.finishHandler(request); registry.retireQuiescentUndispatched();
  assert.equal(request.input, input);
  assert.equal(borrows, 1); assert.equal(returns, 0); assert.equal(retirements, 0);
});
