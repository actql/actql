import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the two actual private loops with explicit Common ports. These
// counters establish scheduling and cleanup, not installed Host acceptance.
const source=readFileSync(new URL('./runtime-core.mjs',import.meta.url),'utf8');
const wanted=new Set(['finishCapturedPreparation','finishPublicationValidation']);
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
assert.equal(declarations.size,2);
const compile=new Function('moon','checked','inspect','setTimeout','setImmediate',
  [...declarations.values()].join('\n')+';return {finishCapturedPreparation,finishPublicationValidation};');
function fixture({pending=3,advance,finish,inspect=x=>x,onYield,immediate=true}={}){
  const preparation=Object.freeze({original:'preparation'}),result=Object.freeze({original:'captured'});
  const counts={advance:0,finish:0,cancel:0,yields:0,timers:0};
  const moon={
    strategyCapturedRunAdvance(value,quantum){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);assert.equal(quantum,256);counts.advance++;return advance?advance(counts.advance):counts.advance>pending;},
    strategyCapturedRunFinish(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.finish++;return finish?finish():result;},
    strategyCapturedRunCancel(value){assert.strictEqual(this,moon);assert.strictEqual(value,preparation);counts.cancel++;},
  };
  const timer=(callback,delay)=>{counts.timers++;assert.equal(delay,0);
    assert(!immediate,'A bounded serialization yield must not start a delay timer');return setTimeout(callback,delay);};
  const loops=compile(moon,x=>x,inspect,timer,immediate?callback=>{
    counts.yields++;return setImmediate(()=>{onYield?.(counts.yields);callback();});
  }:undefined);
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
    'uncertainFailure', 'publishEffectFreeRun', 'capturedComputationLifetime']);
  const declarations = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node && (node.id && names.has(node.id.name) ||
      node.type === 'VariableDeclaration' && node.declarations.some(item => names.has(item.id.name))))
    .map(node => text.slice(node.start, node.end)).join('\n');
  return new Function('publishRun', declarations +
    '\nreturn {publishEffectFreeRun, uncertainFailure, member};')(publishRun);
}

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
    'index', 'now', 'limits', 'publicationRequest', 'withPublicationCleanup', 'computationLifetime'];
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
    value => Object.freeze(value), lifetime));
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
  const controller = new AbortController(), reason = new Error('original stop after capture');
  const captured = Object.freeze({original: 'captured'}), original = Object.freeze({original: 'contract'});
  let retired = 0, released = 0;
  const control = {issueResultManifest: () => original, issueEffectFreeRunReceipt: () => original,
    async issueEffectFreeCapturedRun() {controller.abort(reason); return captured;},
    retireCapturedComputation(value) {
      assert.strictEqual(this, control); assert.strictEqual(value, captured); retired++;
    }};
  const entry = new Function('validateOptions', 'exportCompletedRunResultSet', 'uniqueContracts',
    'publishEffectFreeRun', 'releasePreparedResults', 'member', text.slice(declaration.start, declaration.end) +
    '\nreturn publishCompletedEffectFreeRun;')(() => {}, async (_options, exported) => {
      exported.push({publication: {artifact: original, derivation: original,
        ordering: original, durableBinding: original}});
    }, values => values, () => assert.fail('cancelled capture entered publication'),
    async (_exported, primary) => {released++; throw primary;}, publicationLifetimeLoops().member);
  await assert.rejects(entry({control, signal: controller.signal,
    execution: {publicationInventory: {occurrences: [{definitionContract: original}]}},
    results: [{retention: original}], captureEvidence: {}, receiptEvidence: {}}), error => error === reason);
  assert.equal(retired, 1); assert.equal(released, 1);
});
