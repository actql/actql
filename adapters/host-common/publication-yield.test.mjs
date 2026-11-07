import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {runtimeField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import {publishEffectFreeRun} from './run-publication.mjs';
import {retainFirstAndLatestCleanupError} from './managed-failure.mjs';

// Execute the two actual private loops with explicit Common ports. These
// counters establish scheduling and cleanup, not installed Host acceptance.
const source=readFileSync(new URL('./runtime-core.mjs',import.meta.url),'utf8');
const wanted=new Set(['capturedPreparationLimits','finishCapturedPreparation','finishPublicationValidation']);
const declarations=new Map();
function visit(node){
  if(node===null||typeof node!=='object')return;
  if(node.type==='VariableDeclaration')for(const d of node.declarations){
    if(d.id.type==='Identifier'&&wanted.has(d.id.name)){
      assert(!declarations.has(d.id.name));declarations.set(d.id.name,source.slice(node.start,node.end));
    }
  }
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  }
}
visit(parse(source,{ecmaVersion:'latest',sourceType:'module'}));
assert.equal(declarations.size,3);
const compile=new Function('moon','checked','inspect','setTimeout','setImmediate','runtimeField','runtimeIsBoxedSome',
  [...declarations.values()].join('\n')+';return {finishCapturedPreparation,finishPublicationValidation};');
function fixture({pending=3,advance,finish,inspect=x=>x,onYield,immediate=true}={}){
  const preparation=Object.freeze({original:'preparation'}),result=Object.freeze({original:'captured'});
  const counts={advance:0,finish:0,cancel:0,yields:0,timers:0};
  const moon={
    strategyCapturedRunPreparationLimits(value){assert.strictEqual(value,preparation);return {$tag:1,_0:[65536,4096,64]};},
    strategyCapturedRunAdvance(value,quantum){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);assert.equal(quantum,256);counts.advance++;return advance?advance(counts.advance):counts.advance>pending;},
    strategyCapturedRunFinish(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.finish++;return finish?finish():result;},
    strategyCapturedRunCancel(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.cancel++;},
  };
  const timer=(callback,delay)=>{counts.timers++;assert.equal(delay,0);
    assert(!immediate,'A bounded serialization yield must not start a delay timer');return setTimeout(callback,delay);};
  const loops=compile(moon,x=>x,inspect,timer,immediate?callback=>{
    counts.yields++;return setImmediate(()=>{onYield?.(counts.yields);callback();});
  }:undefined,runtimeField,runtimeIsBoxedSome);
  return{preparation,result,counts,moon,...loops};
}

test('captured issuance yields by event-loop turns without delay timers',async()=>{
  let anotherTurn=false;setImmediate(()=>{anotherTurn=true;});
  const f=fixture({advance:n=>{if(n>1)assert(anotherTurn,'Other queued turns must run between bounded quanta');return n===4;}});
  assert.strictEqual(await f.finishCapturedPreparation(f.preparation),f.result);
  assert.deepEqual(f.counts,{advance:4,finish:1,cancel:0,yields:3,timers:0});
});

test('publication validation yields by event-loop turns without delay timers',async()=>{
  const f=fixture();let steps=0,finished=0,cancelled=0;
  const result=Object.freeze({original:'validation'});
  assert.strictEqual(await f.finishPublicationValidation(f.preparation,(value,quantum)=>{
    assert.strictEqual(value,f.preparation);assert.equal(quantum,256);return ++steps===4?1:0;
  },value=>{assert.strictEqual(value,f.preparation);finished++;return result;},value=>{assert.strictEqual(value,f.preparation);cancelled++;}),result);
  assert.equal(steps,4);assert.equal(finished,1);assert.equal(cancelled,1);assert.equal(f.counts.yields,3);assert.equal(f.counts.timers,0);
});

test('already complete captured issuance does not yield or cancel',async()=>{
  const f=fixture({pending:0});assert.strictEqual(await f.finishCapturedPreparation(f.preparation),f.result);
  assert.deepEqual(f.counts,{advance:1,finish:1,cancel:0,yields:0,timers:0});
});

test('captured issuance abort after a yielded turn retains original reason and cancels once',async()=>{
  const abort=new AbortController(),reason=new Error('original stop');
  const f=fixture({onYield:()=>abort.abort(reason)});
  await assert.rejects(f.finishCapturedPreparation(f.preparation,abort.signal),error=>error===reason);
  assert.deepEqual(f.counts,{advance:1,finish:0,cancel:1,yields:1,timers:0});
});

test('captured issuance advance and inspection failures cancel the same preparation',async()=>{
  const reason=new Error('original failure');
  for(const options of[{advance:()=>{throw reason;}},{pending:0,inspect:()=>{throw reason;}}]){
    const f=fixture(options);await assert.rejects(f.finishCapturedPreparation(f.preparation),error=>error===reason);assert.equal(f.counts.cancel,1);
  }
});

test('publication refusal and invalid progress cancel without a yield or finish',async()=>{
  for(const progress of[-1,2]){const f=fixture();let cancellations=0;
    const run=f.finishPublicationValidation(f.preparation,()=>progress,()=>assert.fail('No finish for non-success'),value=>{assert.strictEqual(value,f.preparation);cancellations++;});
    if(progress===-1)assert.strictEqual(await run,false);else await assert.rejects(run,/Invalid publication validation progress/);
    assert.equal(cancellations,1);assert.equal(f.counts.yields,0);assert.equal(f.counts.timers,0);
  }
});

test('publication abort after a yielded turn cancels once without another quantum',async()=>{
  const abort=new AbortController(),reason=new Error('original validation stop');
  const f=fixture({onYield:()=>abort.abort(reason)});let steps=0,cancellations=0;
  await assert.rejects(f.finishPublicationValidation(f.preparation,()=>{steps++;return 0;},()=>assert.fail('No finish after abort'),()=>{cancellations++;},abort.signal),error=>error===reason);
  assert.equal(steps,1);assert.equal(cancellations,1);assert.equal(f.counts.yields,1);assert.equal(f.counts.timers,0);
});

test('publication finish failure preserves its original error and cancellation',async()=>{
  const f=fixture(),reason=new Error('original finish failure');let cancelled=0;
  await assert.rejects(f.finishPublicationValidation(f.preparation,()=>1,()=>{throw reason;},()=>{cancelled++;}),error=>error===reason);
  assert.equal(cancelled,1);assert.equal(f.counts.yields,0);
});

test('embeddings without setImmediate retain the existing asynchronous timer fallback',async()=>{
  const f=fixture({pending:1,immediate:false});
  assert.strictEqual(await f.finishCapturedPreparation(f.preparation),f.result);
  let steps=0,cancelled=0;
  assert.strictEqual(await f.finishPublicationValidation(f.preparation,()=>++steps===2?1:0,()=>f.result,()=>{cancelled++;}),f.result);
  assert.equal(f.counts.yields,0);assert.equal(f.counts.timers,2);assert.equal(cancelled,1);
});

// Keep the Local transport's actual private loops in this existing CI selection.
// Explicit operation/Store ports below do not establish physical custody or a
// normal installed Host result.
function localDeclarations(path, names) {
  const text = readFileSync(new URL(path, import.meta.url), 'utf8');
  const selected = [];
  for (const node of parse(text, {ecmaVersion:'latest',sourceType:'module'}).body) {
    if (node.type === 'VariableDeclaration' &&
        node.declarations.some(item => names.includes(item.id.name)) ||
        node.type === 'FunctionDeclaration' && names.includes(node.id.name)) {
      selected.push(text.slice(node.start, node.end));
    }
  }
  assert.equal(selected.length, names.length);
  return selected.join('\n');
}
const managedLocalSource = localDeclarations('../local-node/strategy-bundle.mjs', [
  'yieldToHost', 'managedWorkQuantum', 'managedFinalizationQuantum',
  'validateManagedAdvance', 'stopBoundedExecution',
  'runManagedExecution', 'runManagedFinalization',
]);
const snapshotLocalSource = localDeclarations('../local-node/carrier-snapshot.mjs', [
  'yieldToHost', 'quantum', 'validateAdvance', 'prepareLocalSnapshot',
]);
function localLoops({immediate=true,onYield}={}) {
  const counts = {yields:0,timers:0};
  const timer = (callback, delay) => {
    counts.timers++; assert.equal(delay,0);
    assert(!immediate,'A cooperative Local turn must not start a delay timer');
    return setTimeout(callback,delay);
  };
  const turn = immediate ? callback => {
    counts.yields++;
    return setImmediate(() => {onYield?.();callback();});
  } : undefined;
  const managed = new Function('setTimeout','setImmediate',managedLocalSource +
    ';return {runManagedExecution,runManagedFinalization};')(timer,turn);
  const snapshot = new Function('setTimeout','setImmediate',snapshotLocalSource +
    ';return prepareLocalSnapshot;')(timer,turn);
  return {...managed,prepareSnapshot:snapshot,counts};
}

test('Local execution and finalization yield fixed quanta without delay timers',async()=>{
  const f=localLoops(); let advanced=0,finalized=0,otherTurn=false;
  setImmediate(()=>{otherTurn=true;});
  const operations={
    advance(quantum){assert.strictEqual(this,operations);assert.equal(quantum,256);
      if(advanced>0)assert(otherTurn);return{complete:++advanced===3,progress:BigInt(advanced),work:1n};},
    prepare_finalization(...args){assert.deepEqual(args,['payload',3,available]);},
    advance_finalization(quantum){assert.strictEqual(this,operations);assert.equal(quantum,32);
      return{complete:++finalized===3,progress:BigInt(finalized),work:1n};},
  };
  const available=()=>true;
  await f.runManagedExecution(operations,x=>x);
  await f.runManagedFinalization(operations,x=>x,undefined,'payload',3,available);
  assert.equal(advanced,3);assert.equal(finalized,3);
  assert.deepEqual(f.counts,{yields:4,timers:0});
});

test('Local physical waiting and settlement await the original port without cooperative polling',async()=>{
  for(const paused of[{waiting:true},{settlement:0}]){
    const f=localLoops();let advances=0,release,entered;
    const ready=new Promise(resolve=>{entered=resolve;});
    const operations={advance(){return ++advances===1
      ?{complete:false,progress:0n,work:0n,...paused}
      :{complete:true,progress:1n,work:1n};}};
    const flight=f.runManagedExecution(operations,x=>x,undefined,undefined,7,
      packet=>{assert.equal(packet.task,7);entered();return new Promise(resolve=>{release=resolve;});});
    await ready;await new Promise(resolve=>setImmediate(resolve));
    assert.equal(advances,1);assert.deepEqual(f.counts,{yields:0,timers:0});
    release({action:'resume'});await flight;assert.equal(advances,2);
  }
});

test('Local execution and finalization retain abort reason and bounded stop after a turn',async()=>{
  for(const finalization of[false,true]){
    const controller=new AbortController(),reason=new Error('original Local stop');
    const f=localLoops({onYield:()=>controller.abort(reason)});
    let advanced=0,cancelled=0,stopped=false;
    const operations={
      advance(quantum){advanced++;assert.equal(quantum,cancelled?1:256);
        if(cancelled)stopped=true;return{complete:false,progress:1n,work:1n};},
      request_cancel(){cancelled++;},execution_stopped:()=>stopped,
      prepare_finalization(){},
      advance_finalization(quantum){assert.equal(quantum,32);advanced++;return{complete:false,progress:1n,work:1n};},
    };
    const flight=finalization
      ?f.runManagedFinalization(operations,x=>x,controller.signal)
      :f.runManagedExecution(operations,x=>x,controller.signal);
    await assert.rejects(flight,error=>error===reason);
    assert.equal(cancelled,1);assert.equal(advanced,2);assert(stopped);
    assert.deepEqual(f.counts,{yields:1,timers:0});
  }
});

function localSnapshotFixture(f, {signal,cleanupFailure}={}) {
  const events=[],content={cid:'sha256:'+'a'.repeat(64),bytes:3};
  let saves=0,reloads=0,released;
  const body={...content,available:()=>true,close(){events.push('body-close');},
    async consume(consume){events.push('read');await consume(new TextEncoder().encode('abc'));events.push('read-end');}};
  const store={reserve(bytes){assert.equal(bytes,16);return{
    async start(){events.push('start');},async append(part){events.push('append:'+part);},
    async seal(actual){assert.strictEqual(actual,content);events.push('seal');return body;},
  };},close(){events.push('store-close');},
    async cleanup(){events.push('cleanup');if(cleanupFailure)throw cleanupFailure;},
    status:()=>({reservedBytes:0,cleanupPending:false}),
  };
  const operation={key:'original-task',maximum_bytes:16,maximum_frame_bytes:16,
    advance_save(quantum){assert.equal(quantum,32);return{complete:++saves===3,progress:BigInt(saves),work:1n};},
    take_output:()=>['a','b','c'][saves-1],content:()=>content,
    release_source(cid){assert.equal(cid,content.cid);events.push('release-source');},
    begin_reload(text,available){assert.equal(text,'abc');assert(available());assert(events.includes('read-end'));events.push('reload');},
    advance_reload(quantum){assert.equal(quantum,32);return{complete:++reloads===3,progress:BigInt(reloads),work:1n};},
    finish(){assert(released());assert(events.includes('cleanup'));events.push('finish');},
  };
  const owner=f.prepareSnapshot({prepare_carrier_snapshot(check){released=check;return operation;}},
    async()=>store,x=>x,signal);
  return{owner,events,get saves(){return saves;},get reloads(){return reloads;}};
}

test('Local snapshot yields during save and reload while retaining read-end and cleanup ordering',async()=>{
  const f=localLoops(),s=localSnapshotFixture(f);
  const result=await s.owner.roundtrip();
  assert.equal(result.restored,true);assert.equal(result.temporaryBodyReclaimed,true);
  assert.equal(s.saves,3);assert.equal(s.reloads,3);
  assert.deepEqual(f.counts,{yields:4,timers:0});
  assert(s.events.indexOf('seal')<s.events.indexOf('release-source'));
  assert(s.events.indexOf('read-end')<s.events.indexOf('reload'));
  assert(s.events.indexOf('cleanup')<s.events.indexOf('finish'));
  assert.deepEqual(s.owner.cleanupHandle.status(),{pending:false});
});

test('Local snapshot cancellation at a yielded turn retains its original cleanup duty',async()=>{
  const controller=new AbortController(),reason=new Error('original snapshot stop');
  const f=localLoops({onYield:()=>controller.abort(reason)}),s=localSnapshotFixture(f,{signal:controller.signal});
  await assert.rejects(s.owner.roundtrip(),error=>error===reason);
  assert.equal(s.saves,1);assert.equal(s.reloads,0);
  assert(!s.events.includes('seal'));assert(!s.events.includes('finish'));
  assert.deepEqual(s.owner.cleanupHandle.status(),{pending:true});
  assert.deepEqual(await s.owner.cleanupHandle.retry(),{pending:false});
  assert.deepEqual(f.counts,{yields:1,timers:0});
});

test('Local snapshot cleanup failure after reload is not acknowledged by scheduling',async()=>{
  const f=localLoops(),reason=new Error('original cleanup failure');
  const s=localSnapshotFixture(f,{cleanupFailure:reason});
  await assert.rejects(s.owner.roundtrip(),error=>error===reason);
  assert.equal(s.reloads,3);assert(!s.events.includes('finish'));
  assert.deepEqual(s.owner.cleanupHandle.status(),{pending:true});
});

test('Local loops retain the asynchronous timer fallback outside immediate-capable embeddings',async()=>{
  const f=localLoops({immediate:false});let steps=0;
  await f.runManagedExecution({advance:()=>({complete:++steps===2,progress:BigInt(steps),work:1n})},x=>x);
  await localSnapshotFixture(f).owner.roundtrip();
  assert.deepEqual(f.counts,{yields:0,timers:5});
});

// Execute the actual publication entry/Unknown cleanup and completed caller
// with explicit semantic and payload ports. These counters establish managed
// alias transfer, not a new Common issuer, physical ACK or normal Host result.
function publicationLifetimeLoops(publishRun) {
  const text = readFileSync(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  const names = new Set(['RunPublicationError', 'member', 'fail', 'cleanupState',
    'uncertainFailure', 'publishEffectFreeRun', 'capturedComputationLifetime', 'lookupOriginalCommit']);
  const declarations = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node && (node.id && names.has(node.id.name) ||
      node.type === 'VariableDeclaration' && node.declarations.some(item => names.has(item.id.name))))
    .map(node => text.slice(node.start, node.end)).join('\n');
  return new Function('publishRun', 'retainFirstAndLatestCleanupError', declarations +
    '\nreturn {publishEffectFreeRun, uncertainFailure, member, lookupOriginalCommit};')(
      publishRun, retainFirstAndLatestCleanupError);
}

test('publication caller forwards its original Index to the existing Store commit', async () => {
  const text = readFileSync(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  const calls = [];
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'store' && node.callee.property.name === 'commitIndex') calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(parse(text, {ecmaVersion:'latest',sourceType:'module'}));
  assert.equal(calls.length, 1);
  const original = Object.freeze({name:'public_index_entry',wire:'original immutable body'});
  const inventory = Object.freeze([]), evidence = Object.freeze({original:'evidence'});
  const result = Object.freeze({committed:true});
  const handles = Object.freeze([Object.freeze({})]);
  const store = {commitIndex(actualWire, actualInventory, actualEvidence, actualOriginal, actualHandles) {
    assert.strictEqual(this, store); assert.equal(actualWire, original.wire);
    assert.strictEqual(actualInventory, inventory); assert.strictEqual(actualEvidence, evidence);
    assert.strictEqual(actualOriginal, original); assert.strictEqual(actualHandles, handles);
    return Promise.resolve(result);
  }};
  const call = new Function('store','index','inventory','evidence','commitEvidence','originalPreparedHandles',
    'return ' + text.slice(calls[0].start,calls[0].end));
  assert.strictEqual(await call(store,original,inventory,evidence,value=>value,handles), result);
});

function publicationCommitCallerFixture({committed = true, differentIndex = false} = {}) {
  // Exercise the complete actual caller with explicit semantic/Store ports.
  // These ports do not establish a Common verdict or physical durability ACK.
  const cid = digit => 'sha256:' + digit.repeat(64);
  const contract = (name, digit, body = {}) => Object.freeze({name,
    identityField: name + '_cid', identity: cid(digit),
    wire: JSON.stringify({...body, [name + '_cid']: cid(digit)})});
  const original = contract('run_definition', '1');
  const request = contract('publication_request', '2');
  const attempt = contract('publication_attempt', '3');
  const index = contract('public_index_entry', '4', {publication_attempt_cid: attempt.identity});
  const selected = differentIndex
    ? contract('public_index_entry', '5', {publication_attempt_cid: attempt.identity}) : index;
  const record = contract('publication_record', '6');
  const setup = ['check_existing_commit', 'check_initial_active', 'persist_contracts', 'enter_attempt_progress'];
  const progress = ['issue_index', 'commit_index'];
  const reads = [], events = [];
  let acknowledge;
  const ack = new Promise(resolve => {acknowledge = resolve;});
  let entered;
  const committing = new Promise(resolve => {entered = resolve;});
  const control = {
    issuePublicationRequest: () => request, issuePublicationAttempt: () => attempt,
    issuePublicIndexEntry: () => index, issuePublicationRecord: () => assert.fail('No append needed in this fixture'),
    publicationSetupAction: () => setup.shift(), publicationAttemptAction: () => progress.shift(),
    publicationCancellationAction: () => assert.fail('No cancellation'),
    committedPublicationFinalizationAction: () => 'finished',
    supersededPublicationFinalizationAction: () => assert.fail('Same original attempt'),
    publicationCommitFailureAction: () => assert.fail('No commit failure in success fixture'),
    publicationUnknownRetryAction: () => assert.fail('No retry'),
    effectFreeChainValid: () => true, effectFreeCommitValid: () => true,
    admit: () => assert.fail('No caller-side re-admission'),
    retireCapturedComputation(value) {assert.strictEqual(value, original);events.push('retire');},
  };
  const store = {
    putPublicationContract: async () => {}, putOriginalPublicationContracts: async () => {},
    createAttempt: async () => {}, latestRecordContract: async () => record,
    appendRecord: async () => assert.fail('No append needed'),
    inspectCommittedIndex: async () => undefined, confirmCommittedIndex: async () => undefined,
    validateCommittedEvidence: async () => assert.fail('No existing commit'),
    retireUncommittedPublication: async () => assert.fail('Same original attempt'),
    async commitIndex(wire, _inventory, _evidence, originalIndex) {
      assert.equal(wire, index.wire);assert.strictEqual(originalIndex, index);
      events.push('commit');entered();await ack;events.push('ack');
      return {entry: JSON.parse(selected.wire), committed, idempotent: !committed};
    },
    async readPublicationContract(identity, name) {
      reads.push({identity, name});
      if (name === 'public_index_entry') {assert.equal(identity, selected.identity);return selected;}
      assert.equal(name, 'publication_attempt');assert.equal(identity, attempt.identity);return attempt;
    },
  };
  const evidence = {runDefinition: original, invocation: original,
    definitions: [original], artifacts: [original], derivations: [], orderings: [],
    retentions: [], durableBindings: [original], manifest: original, receipt: original, capturedRun: original};
  const options = {store, control, evidence,
    request: {namespaceId: 'namespace', authorityScopeCid: cid('7'),
      publicationPolicyCid: cid('8'), publicationTargetCid: cid('9'), requestedAt: 'original-time'},
    attempt: {attemptId: 'original-attempt', fenceCid: cid('a'),
      externalIdempotencyKey: undefined, startedAt: 'original-time'},
    limits: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64},
    now: () => 'original-time', signal: undefined};
  return {options, index, selected, attempt, reads, events, committing, acknowledge};
}

test('publication original commit lookup retains captured cleanup methods and receiver', async () => {
  const {lookupOriginalCommit} = publicationLifetimeLoops();
  let pending = true, retries = 0, release, entered;
  const ready = new Promise(resolve => {entered = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const cleanup = {
    status() {assert.strictEqual(this, cleanup); return {pending};},
    async retry() {assert.strictEqual(this, cleanup); retries++; entered(); await gate; pending = false;},
  };
  const primary = Object.assign(new Error('original'), {code: 'PublicationMetadataCommitOutcomeUnknown',
    outcome: 'unknown', cleanupPending: true, cleanupHandle: cleanup});
  const expected = {}, flight = lookupOriginalCommit(primary, async () => {
    assert.equal(pending, false); return expected;
  });
  await ready;
  cleanup.status = cleanup.retry = () => assert.fail('replacement cleanup method');
  release(); assert.strictEqual(await flight, expected); assert.equal(retries, 1);
});

test('publication original commit lookup keeps unresolved storage failure and actual lookup errors', async () => {
  const {lookupOriginalCommit} = publicationLifetimeLoops();
  for (const mode of ['throw', 'pending', 'confirmed']) {
    let pending = true, lookups = 0, retries = 0;
    const primary = Object.assign(new Error('original'), {code: 'PublicationMetadataCommitOutcomeUnknown',
      outcome: 'unknown', cleanupPending: true, cleanupHandle: {
        status: () => ({pending}), async retry() {
          retries++;
          if (mode === 'throw') throw new Error('original confirmation still unknown');
          if (mode === 'confirmed') pending = false;
        },
      }});
    const changed = new Error('actual selected commit differs');
    await assert.rejects(lookupOriginalCommit(primary, async () => {
      lookups++; throw changed;
    }), error => error === (mode === 'confirmed' ? changed : primary));
    assert.equal(retries, 1); assert.equal(lookups, mode === 'confirmed' ? 1 : 0);
  }
});

test('publication original commit lookup leaves generic and legacy failures on the full lookup path', async () => {
  const {lookupOriginalCommit} = publicationLifetimeLoops();
  for (const properties of [{code: 'EIO', outcome: 'unknown'},
    {code: 'PublicationMetadataCommitOutcomeUnknown'}, {}]) {
    const primary = Object.assign(new Error('original'), properties, {cleanupPending: true});
    Object.defineProperty(primary, 'cleanupHandle', {get() {assert.fail('unrelated cleanup inspected');}});
    const actual = {}, value = await lookupOriginalCommit(primary, async () => actual);
    assert.strictEqual(value, actual);
  }
});

test('publication original commit caller confirms once before real reconciliation and validation', async () => {
  const f = publicationCommitCallerFixture(), {store, control, evidence} = f.options;
  const request = control.issuePublicationRequest(), originalAttempt = f.attempt;
  const index = Object.freeze({...f.index, wire: JSON.stringify({...JSON.parse(f.index.wire),
    publication_request_cid: request.identity})});
  let commits = 0, retries = 0, pending = true, validations = 0;
  const cleanup = {
    status: () => ({pending}),
    async retry() {assert.strictEqual(this, cleanup); retries++; pending = false;},
  };
  const primary = Object.assign(new Error('original native Index uncertainty'), {
    code: 'PublicationMetadataCommitOutcomeUnknown', outcome: 'unknown',
    cleanupPending: true, cleanupHandle: cleanup,
  });
  control.issuePublicIndexEntry = () => index;
  control.publicationCommitFailureAction = (attempted, failed, found) => {
    if (!attempted) return 'reconcile_commit';
    assert.equal(failed, false); assert.equal(found, true); return 'adopt_committed_index';
  };
  store.commitIndex = async (_wire, _inventory, _evidence, original) => {
    assert.strictEqual(original, index); commits++; throw primary;
  };
  store.confirmCommittedIndex = async () => {
    if (!commits) return undefined;
    assert.equal(pending, false, 'lookup follows the SAME original storage confirmation');
    return {public_index_entry_cid: index.identity};
  };
  store.readPublicationContract = async (identity, name) => {
    const original = {public_index_entry: index, publication_request: request,
      publication_attempt: originalAttempt}[name];
    assert.equal(identity, original.identity); return original;
  };
  store.validateCommittedEvidence = async (actual, original) => {
    assert.strictEqual(actual, index); assert.strictEqual(original, evidence); validations++; return true;
  };
  const publication = await publishEffectFreeRun(f.options);
  assert.equal(publication.state, 'succeeded'); assert.strictEqual(publication.index, index);
  assert.equal(commits, 1); assert.equal(retries, 1); assert.equal(validations, 1);
  assert.deepEqual(f.events, ['retire']);
});

test('publication caller retains only its newly acknowledged original Index', async () => {
  const f = publicationCommitCallerFixture();
  const operation = publishEffectFreeRun(f.options);
  await f.committing;
  assert.deepEqual(f.events, ['commit']);assert.deepEqual(f.reads, []);
  f.acknowledge();
  const result = await operation;
  assert.strictEqual(result.index, f.index);
  assert.equal(result.state, 'succeeded');assert.equal(result.committed, true);
  assert.deepEqual(f.reads, [{identity: f.attempt.identity, name: 'publication_attempt'}],
    'successful own-Index ACK does not require another same-input Index reader');
  assert.deepEqual(f.events, ['commit', 'ack', 'retire']);
});

test('publication caller still reads an idempotent or different committed Index', async () => {
  for (const settings of [{committed: false}, {differentIndex: true}]) {
    const f = publicationCommitCallerFixture(settings);
    const operation = publishEffectFreeRun(f.options);await f.committing;f.acknowledge();
    const result = await operation;
    assert.strictEqual(result.index, f.selected);
    assert.deepEqual(f.reads, [{identity: f.selected.identity, name: 'public_index_entry'},
      {identity: f.attempt.identity, name: 'publication_attempt'}]);
  }
});

test('publication computation lifetime captures the original retirement and waits for terminal success', async () => {
  const captured = Object.freeze({original: 'captured'}), result = Object.freeze({state: 'succeeded'});
  let retired = 0, finish;
  const control = {retireCapturedComputation(value) {
    assert.strictEqual(this, control); assert.strictEqual(value, captured); retired++;
  }};
  const loops = publicationLifetimeLoops(() => new Promise(resolve => {finish = resolve;}));
  const pending = loops.publishEffectFreeRun({control, evidence: {capturedRun: captured}});
  assert.equal(retired, 0);
  control.retireCapturedComputation = () => assert.fail('replacement retirement used');
  finish(result);
  assert.strictEqual(await pending, result); assert.equal(retired, 1);
});

test('publication computation lifetime retires on the original terminal failure and accepts legacy absence', async () => {
  for (const primary of [new Error('original terminal failure'), null]) {
    let retired = 0;
    const captured = Object.freeze({original: 'captured'});
    const control = {retireCapturedComputation(value) {assert.strictEqual(value, captured); retired++;}};
    const loops = publicationLifetimeLoops(async () => {throw primary;});
    let caught = false;
    try {await loops.publishEffectFreeRun({control, evidence: {capturedRun: captured}});}
    catch (error) {caught = true; assert.strictEqual(error, primary);}
    assert(caught); assert.equal(retired, 1);
  }
  const result = Object.freeze({legacy: true});
  assert.strictEqual(await publicationLifetimeLoops(async () => result)
    .publishEffectFreeRun({control: {}, evidence: {}}), result);
});

test('publication computation lifetime stays with failed or pending Unknown and retires after same-owner settlement', async () => {
  const loops = publicationLifetimeLoops();
  let pending = true, failed = true, retired = 0, reconciliations = 0, finish;
  let gate = Promise.resolve();
  const primary = Object.assign(new Error('original Unknown'), {cleanupPending: true,
    cleanupHandle: {status: () => ({pending}), async retry() {}}});
  const refusal = new Error('same original reconciliation refused');
  const control = {publicationUnknownRetryAction(resolved, upstreamPending, available, attempted) {
    // Existing Common action port: a finished retry may still be pending.
    if (attempted && !resolved) return 'invalid';
    if (!resolved) return 'reconcile';
    if (upstreamPending && available && !attempted) return 'retry_upstream_cleanup';
    return 'finished';
  }};
  const error = loops.uncertainFailure(primary, undefined, undefined, control, async () => {
    reconciliations++; await gate;
    if (failed) throw refusal;
    return Object.freeze({outcome: 'uncommitted'});
  }, () => {retired++;});
  assert.equal(error.cleanupHandle.status().pending, true); assert.equal(retired, 0);
  await assert.rejects(error.cleanupHandle.retry(), reason => reason === refusal);
  assert.equal(retired, 0);
  failed = false;
  gate = new Promise(resolve => {finish = resolve;});
  const first = error.cleanupHandle.retry(), again = error.cleanupHandle.retry();
  finish();
  const observations = await Promise.all([first, again]);
  assert.strictEqual(first, again, 'same original reconciliation remains single-flight');
  assert.equal(reconciliations, 2); assert(observations.every(value => value.pending));
  assert.equal(retired, 0, 'finished retry is not proof that the upstream child settled');
  pending = false;
  assert.equal((await error.cleanupHandle.retry()).pending, false);
  assert.equal(retired, 1);
  await error.cleanupHandle.retry(); assert.equal(retired, 1);
});

test('publication computation lifetime preserves a terminal failure when managed retirement also fails', async () => {
  const primary = new Error('original publication refusal'), cleanup = new Error('original cancel refused');
  let attempts = 0;
  const control = {retireCapturedComputation() {attempts++; throw cleanup;}};
  const loops = publicationLifetimeLoops(async () => {throw primary;});
  await assert.rejects(loops.publishEffectFreeRun({control, evidence: {capturedRun: {}}}), error =>
    error.code === 'RunPublicationRetirementFailed' && error.primaryFailure === primary && error.cleanupError === cleanup);
  assert.equal(attempts, 1, 'no blind cancellation retry on the terminal path');
});

test('publication computation lifetime retries only failed managed retirement after original Unknown resolution', async () => {
  const loops = publicationLifetimeLoops(), refused = new Error('original cancel refused');
  let attempts = 0, reconciliations = 0;
  const control = {publicationUnknownRetryAction: resolved => resolved ? 'finished' : 'reconcile'};
  const error = loops.uncertainFailure(new Error('original Unknown'), undefined, undefined, control,
    async () => {reconciliations++; return {outcome: 'uncommitted'};},
    () => {if (++attempts === 1) throw refused;});
  await assert.rejects(error.cleanupHandle.retry(), reason => reason === refused);
  assert.equal(error.cleanupHandle.status().pending, true);
  assert.equal((await error.cleanupHandle.retry()).pending, false);
  assert.equal(reconciliations, 1); assert.equal(attempts, 2);
  await error.cleanupHandle.retry(); assert.equal(attempts, 2);
});

test('publication computation lifetime transfers through the actual Unknown return and commit validation', async () => {
  const text = readFileSync(new URL('./run-publication.mjs', import.meta.url), 'utf8');
  let block;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && node.test.type === 'BinaryExpression' &&
        node.test.left.name === 'action' && node.test.right.value === 'return_unknown') {
      assert.equal(block, undefined); block = node.consequent;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(block);
  const names = ['uncertainFailure', 'primary', 'reconciliationFailure', 'recordFailure', 'control',
    'lookupCommit', 'validateCommit', 'finishResolvedCommit', 'store', 'publicationAttempt',
    'index', 'now', 'limits', 'publicationRequest', 'withPublicationCleanup', 'computationLifetime',
    'lookupOriginalCommit'];
  const originalUnknownReturn = new Function(...names, text.slice(block.start, block.end));
  let loops, retired = 0, reads = 0, validations = 0, finalized = 0;
  const captured = Object.freeze({original: 'capture'}), selected = Object.freeze({original: 'Index'});
  const attempt = Object.freeze({original: 'attempt'}), store = Object.freeze({original: 'Store'});
  const primary = new Error('original commit reply unavailable');
  const control = {retireCapturedComputation(value) {assert.strictEqual(value, captured); retired++;},
    publicationUnknownRetryAction: resolved => resolved ? 'finished' : 'reconcile'};
  loops = publicationLifetimeLoops(async (_options, _effectful, lifetime) => originalUnknownReturn(
    loops.uncertainFailure, primary, undefined, undefined, control,
    async () => {reads++; return {index: selected};},
    async value => {assert.strictEqual(value, selected); assert.equal(retired, 0); validations++;},
    async (actualStore, actualControl, actualAttempt, _candidate, actualIndex) => {
      assert.strictEqual(actualStore, store); assert.strictEqual(actualControl, control);
      assert.strictEqual(actualAttempt, attempt); assert.strictEqual(actualIndex, selected);
      assert.equal(retired, 0); finalized++; return {winner: attempt};
    }, store, attempt, selected, () => 'original-time', {}, Object.freeze({original: 'request'}),
    value => Object.freeze(value), lifetime, loops.lookupOriginalCommit));
  let failure;
  await assert.rejects(loops.publishEffectFreeRun({control, evidence: {capturedRun: captured}}), error => {
    failure = error; return error.code === 'RunPublicationUnknown' && error.primaryFailure === primary;
  });
  assert.equal(retired, 0); assert.equal(reads, 0);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(failure.publicationResult.state, 'succeeded');
  assert.equal(reads, 1); assert.equal(validations, 1); assert.equal(finalized, 1); assert.equal(retired, 1);
});

test('publication computation lifetime latches retry before synchronous original reconciliation reentry', async () => {
  const loops = publicationLifetimeLoops();
  let error, nested, entered = false, reconciliations = 0, retired = 0;
  const control = {publicationUnknownRetryAction: resolved => resolved ? 'finished' : 'reconcile'};
  error = loops.uncertainFailure(new Error('original Unknown'), undefined, undefined, control, async () => {
    reconciliations++;
    if (!entered) {entered = true; nested = error.cleanupHandle.retry();}
    return Object.freeze({outcome: 'uncommitted'});
  }, () => {retired++;});
  const original = error.cleanupHandle.retry();
  assert.equal((await original).pending, false);
  assert.strictEqual(nested, original);
  assert.equal(reconciliations, 1); assert.equal(retired, 1);
});

test('publication computation lifetime retires capture cancelled before publication entry without replacing payload cleanup', async () => {
  const text = readFileSync(new URL('./completed-run-publication.mjs', import.meta.url), 'utf8');
  const declaration = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'ExportNamedDeclaration' &&
      node.declaration?.id?.name === 'publishCompletedEffectFreeRun').declaration;
  const failureClass = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'ExportNamedDeclaration' &&
      node.declaration?.id?.name === 'CompletedRunPublicationError').declaration;
  for (const retirementFailure of [undefined, new Error('original capture cancellation refused')]) {
  const controller = new AbortController(), reason = new Error('original stop after capture');
  const captured = Object.freeze({original: 'captured'}), original = Object.freeze({original: 'contract'});
  let retired = 0, released = 0;
  const control = {issueResultManifest: () => original, issueEffectFreeRunReceipt: () => original,
    async issueEffectFreeCapturedRun() {controller.abort(reason); return captured;},
    retireCapturedComputation(value) {
      assert.strictEqual(this, control); assert.strictEqual(value, captured); retired++;
      if (retirementFailure !== undefined) throw retirementFailure;
    }};
  const entry = new Function('validateOptions', 'exportCompletedRunResultSet', 'uniqueContracts',
    'publishEffectFreeRun', 'releasePreparedResults', 'member', text.slice(failureClass.start, failureClass.end) +
    '\n' + text.slice(declaration.start, declaration.end) +
    '\nreturn publishCompletedEffectFreeRun;')(() => {}, async (_options, exported) => {
      exported.push({publication: {artifact: original, derivation: original,
        ordering: original, durableBinding: original}});
    }, values => values, () => assert.fail('cancelled capture entered publication'),
    async (_exported, primary) => {released++; throw primary;}, publicationLifetimeLoops().member);
  await assert.rejects(entry({control, signal: controller.signal,
    execution: {publicationInventory: {occurrences: [{definitionContract: original}]}},
    results: [{retention: original}], captureEvidence: {}, receiptEvidence: {}}), error =>
    retirementFailure === undefined ? error === reason :
      error.code === 'CompletedRunCaptureRetirementFailed' &&
      error.primaryFailure === reason && error.cleanupError === retirementFailure);
  assert.equal(retired, 1); assert.equal(released, 1);
  }
});

test('publication snapshots the original nominal holder inventory before asynchronous commit', async()=>{
 const {publishEffectFreeRun}=await import('./run-publication.mjs');
 const f=publicationCommitCallerFixture(), original=Object.freeze({}), replacement=Object.freeze({});
 const handles=[original];f.options.preparedHandles=handles;
 const commit=f.options.store.commitIndex;
 let selected;
 f.options.store.commitIndex=function(...args){selected=args[4];return Reflect.apply(commit,this,args);};
 const operation=publishEffectFreeRun(f.options);
 handles[0]=replacement;f.options.preparedHandles=[replacement];
 await f.committing;
 assert.deepEqual(selected,[original]);assert(Object.isFrozen(selected));
 f.acknowledge();await operation;
});
