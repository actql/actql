import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';

// Actual common reader and RowRun lifetime JS. Site issuer/private binding,
// provider, Account/current and Core/funding methods are explicit ports.
const ok = value => ({$tag: 1, _0: value});
const error = value => ({$tag: 0, _0: value});
const deferred = () => {let resolve; const promise = new Promise(r => {resolve = r;}); return {resolve, promise};};

// Real shared page-reader lifecycle with explicit Site/charge/schema ports.
// A returned opaque page is DATA; these ports establish no normal authority,
// numerical backing or compiled row-schema acceptance.
function projectedReaderFixture({page, chargeFailure, consumeFailure, consumePending, acceptedCount = 2} = {}) {
  const events = [], projectedPage = Object.freeze({}), charge = Object.freeze({});
  const response = Object.freeze({accepted: true, statusCode: 200, body: Buffer.from('original provider bytes')});
  const original = Object.freeze({grant: {}, useId: 'original', scope: Object.freeze({operation: 'read'})});
  let sends = 0, charges = 0, consumes = 0, closes = 0;
  const consumed = deferred();
  const acquisition = Object.freeze({credential: Object.freeze({}), close() {
    assert.equal(this, acquisition);closes++;events.push('close');return 'closed';
  }});
  const site = Object.freeze({}), originalSite = Object.freeze({site,
    referenceCurrent() {return true;}, authorizationPurpose(value) {
      assert.equal(value, original);return {kind: 'read'};
    }, bindRunAcquisition(value, callbacks) {
      assert.equal(value, original);callbacks.assertCurrent();return acquisition;
    }, async callResource(input) {
      assert.equal(this, site);sends++;await input.currentBeforeSend();
      input.responseCustody.retain(response);events.push('receive');return response;
    }});
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite,
    assertCurrent() {}, operation: 'read', maxResponses: 1, maxResponseBytes: 128, maxSecretBytes: 128,
    preparePageReader() {return Object.freeze({fetchPage() {return {method: 'GET', path: '/one'};},
      decodePage(actual) {
        assert.equal(actual, response);events.push('decode');
        return page ?? {projectedPage, rowCount: 2, done: true};
      }});}});
  const options = Object.freeze({originalAuthorization: original, columns: ['id'],
    verifyRead() {}, authorizationFor() {return original;},
    consumePage() {assert.fail('No JS row fallback');},
    consumePageWire() {assert.fail('No wire encode/decode fallback');},
    chargePage(bytes) {
      assert.equal(bytes, response.body);charges++;events.push('charge');
      if (chargeFailure !== undefined) throw chargeFailure;
      return charge;
    }, async consumeProjectedPage(actual, metadata) {
      assert.equal(actual, projectedPage);assert.equal(metadata.charge, charge);
      consumes++;events.push('consume');consumed.resolve();
      if (consumePending !== undefined) await consumePending;
      if (consumeFailure !== undefined) throw consumeFailure;
      return acceptedCount;
    }});
  const reader = factory.prepare(options);
  return {reader, factory, events, projectedPage, consumed: consumed.promise,
    counts: () => ({sends, charges, consumes, closes})};
}

test('shared reader typed page keeps the same response charge and opaque page through first close', async () => {
  const f = projectedReaderFixture();
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 2});
  assert.deepEqual(f.events, ['receive', 'charge', 'decode', 'consume']);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, charges: 1, consumes: 1, closes: 1});
});

test('shared reader typed page rejects mixed representations before schema consumption', async () => {
  const f = projectedReaderFixture({page: {projectedPage: {}, rowsWire: '[]', rowCount: 0, done: true}});
  await assert.rejects(f.reader.read(), {code: 'InvalidInstalledSourceDecodedPage'});
  assert.equal(f.counts().consumes, 0);f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
});

test('shared reader typed page cannot replace the actual admitted row count', async () => {
  const f = projectedReaderFixture({acceptedCount: 1});
  await assert.rejects(f.reader.read(), {code: 'InvalidInstalledSourceDecodedPage'});
  assert.equal(f.counts().consumes, 1);f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
});

test('shared reader typed page charge failure remains pending without decode consumption or fake close ACK', async () => {
  const cause = new Error('original unknown charge disposition'), f = projectedReaderFixture({chargeFailure: cause});
  await assert.rejects(f.reader.read(), error => error === cause);
  f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  assert.equal(f.factory.retire(), false);
  assert.deepEqual(f.events, ['receive', 'charge', 'close']);
  assert.deepEqual(f.counts(), {sends: 1, charges: 1, consumes: 0, closes: 1});
});

test('shared reader typed page preserves schema refusal and closes only its original binding', async () => {
  const cause = new Error('original row-schema refusal'), f = projectedReaderFixture({consumeFailure: cause});
  await assert.rejects(f.reader.read(), error => error === cause);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, charges: 1, consumes: 1, closes: 1});
});

test('shared reader typed page stop retains the pending original consumption until it settles', async () => {
  const gate = deferred(), f = projectedReaderFixture({consumePending: gate.promise});
  const pending = f.reader.read();
  await f.consumed;f.reader.requestStop(new Error('same original caller stop'));
  assert.equal(f.reader.observe().readPending, true);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  assert.equal(f.factory.retire(), false);
  gate.resolve();await assert.rejects(pending);
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, charges: 1, consumes: 1, closes: 1});
});

function fixture({pendingRead, pendingBinding = false, responseGrowth = false, growthFailure,
  providerRetirementFailure, providerRetirementAllowed = () => true} = {}) {
  const events = [], raw = {grant: {}, scope: {operation: 'read'}}, credential = {}, capacity = {}, charge = {}, began = deferred();
  const response = Object.freeze({body: Buffer.from('same received bytes')});
  let current = true, bindingCanClose = !pendingBinding, providerRetired = false, requestSignal;
  let retainedOptions, cleanup, coreRetired = false, preparedReader;
  let captureCleanupReady = true;
  const providerReadPending = deferred();
  const site = {}, acquisition = Object.freeze({credential, close() {
    assert.equal(this, acquisition); events.push('binding-close'); return bindingCanClose ? 'closed' : 'pending';
  }});
  const originalSite = Object.freeze({site, callResource(input) {
    assert.equal(this, site);requestSignal = input.signal;input.responseCustody.retain(response);return response;
  }, readChildCredential(original, authorization) {
    assert.equal(original, acquisition);assert.equal(authorization, raw);return credential;
  },
    referenceCurrent() {return current;}, authorizationPurpose(authorization) {
      assert.equal(authorization, raw); return {kind: 'read'};
    }, bindRunAcquisition(authorization, callbacks) {
      assert.equal(authorization, raw); callbacks.assertCurrent(); events.push('bind'); return acquisition;
    }});
  let provider;
  const factory = createInstalledCredentialSourceReader({capacity, originalSite,
    assertCurrent() {if (!current) throw new Error('original Host retired');}, maxResponses: 1,
    maxResponseBytes: 128, prepareReadSequence(input) {
      assert.equal(input.responseBorrow,responseBorrow);
      assert.equal(input.originalAuthorization,raw);
      events.push('provider-create');
      provider = Object.freeze({...(responseGrowth ? {responseCapacity(bytes) {
        assert.equal(this, provider);assert.equal(bytes,response.body.byteLength);
        events.push('quote-response');return capacity;
      }} : {}), async read(context) {
        assert.equal(this, provider);retainedOptions = context;events.push('provider-read');
        await context.readChild({operation:'read', prepare() {
          return {request:{method:'GET',path:'/one'},project(actual) {
            assert.equal(actual,response);if(responseGrowth)events.push('project-response');
          }};
        }});
        assert.equal(context.signal,requestSignal,'domain current and physical send share the SAME combined stop signal');
        if (pendingRead) {providerReadPending.resolve();await pendingRead;}
        requestSignal.throwIfAborted();
        await context.consumePage([{id:1}]);
      }, retire() {
        assert.equal(this, provider);
        if (!providerRetirementAllowed()) throw providerRetirementFailure;
        providerRetired = true;retainedOptions = undefined;return true;
      }});
      return provider;
    }});
  const options = Object.freeze({originalAuthorization: raw, columns: ['id'],
    verifyRead() {assert.equal(this,options);events.push('verify');}, authorizationFor(index) {
      assert.equal(index, 0);events.push('use');return {...raw, useId:'one'};
    }, authorizeReadChild(operation,index) {
      assert.equal(operation,'read');assert.equal(index,0);
      return {authorization:{...raw,useId:'child'},originalAuthorization:raw};
    }, consumePage(rows) {assert.deepEqual(rows,[{id:1}]);},consumeObservation() {},
    chargePage(bytes) {assert.equal(bytes,response.body);events.push('charge');began.resolve();return charge;}});
  const run = {}, source = {}, ledger = {}, responseBorrow = {};
  const moon = {
    clientProgramRowSourceStartProviderAccounted() {events.push('reserve'); return ok(run);},
    clientProgramRowSourceBorrowResponses() {events.push('borrow'); return ok(responseBorrow);},
    clientProgramRowSourceGrowResponseCapacity(borrow, actual) {
      assert.equal(borrow,responseBorrow);assert.equal(actual,capacity);events.push('grow-response');
      if(growthFailure !== undefined)throw growthFailure;return ok(undefined);
    },
    clientProgramRowSourceBindResponseCleanup(borrow, observed) {cleanup = observed; events.push('retain'); return ok(undefined);},
    clientProgramRowSourceRetireResponseWorkspace() {
      if (!cleanup()) return error('same original response duty pending');
      events.push('workspace-return');return ok(undefined);
    },
    clientProgramRowSourceCloseAccounted() {
      if (!cleanup()) return error('same original response duty pending');
      coreRetired = true; events.push('core-retire'); return ok(undefined);
    },
    clientProgramRowSourceCaptureCleanup() {return ok(true);},
  };
  const captured = {}, capturedSource = {}, identity = {}, logicalInput = {}, attempt = {};
  const evidence = {}, checkedOwner = {}, requirement = {};
  Object.assign(moon, {
    clientProgramRowSourceFinish: () => ok(undefined),
    clientProgramRowSourceAttempt: () => attempt,
    clientProgramRowSourceCaptureBegin: () => ok(undefined),
    clientProgramRowSourceCaptureAdvance: () => ok({_0:true,_1:1n}),
    clientProgramRowSourceCapture: () => ok(captured),
    clientProgramRowSourceCaptureSource(actual) {
      assert.equal(actual,captured);
      return coreRetired ? error('original Core capture retired') : ok(capturedSource);
    },
    clientProgramEffectCapturedSourceMatches: () => true,
    clientProgramIdentifyCapturedEffectSourceRelation: () => ok(identity),
    clientProgramEffectIssueCapturedSourceLogical: () => ok(logicalInput),
    clientProgramRowSourceIssueSourceEvidence() {
      assert.equal(coreRetired,false);events.push('source-evidence');return ok(evidence);
    },
    clientProgramRowSourceCaptureCleanupAdvance() {return ok(captureCleanupReady);},
  });
  const session = startInstalledRowRun({moon, acquisition: source, nonce: 'one', ledger,
    capacity: {provider: capacity, transferBytes: 100n, executionBytes: 100n}});
  return {factory, options, events, session, response, readBegan: began.promise, providerReadPending: providerReadPending.promise,
    // Observe the exact returned original; read/stop/observe are never wrapped
    // or replaced. This is fixture custody, not an installed supplier overlay.
    read() {return session.readProvider({prepare(actual,retainPreparation,reserveResponseCapacity,borrow) {
      assert.equal(this,factory);assert.equal(actual,options);assert.equal(borrow,responseBorrow);
      preparedReader=Reflect.apply(factory.prepare,factory,[actual,retainPreparation,reserveResponseCapacity,borrow]);return preparedReader;
    },receiver:factory,options});},
    reader:()=>preparedReader,
    complete() {return session.complete({owner:{checkedOwner,effectful:true,requirement,
      occurrence:{task:0}},prepared:{checkedSource:{}},registry:'registry',values:'values',
      currentRead:async()=>{}});},
    capturedSource,evidence,
    captureCleanupReady(value) {captureCleanupReady=value;},
    bindingRetires() {bindingCanClose = true;},
    inspect() {return {coreRetired, providerRetired, retainedOptions, stopped:requestSignal?.aborted === true};}};
}

test('native response constructor grows the SAME original RowRun after charge and before projection', async () => {
  const f = fixture({responseGrowth:true});
  assert.deepEqual(await f.read(), {pages:1,rowCount:1});
  const selected=f.events.filter(value=>['charge','quote-response','grow-response','project-response'].includes(value));
  assert.deepEqual(selected,['charge','quote-response','grow-response','project-response']);
  assert.equal(f.reader().observe().cleanupConfirmed,false);
  f.session.close();assert.equal(f.inspect().coreRetired,true);
});

test('native response constructor preserves original capacity refusal without decoding or returning custody early', async () => {
  const cause=new Error('original capacity refusal'),f=fixture({responseGrowth:true,growthFailure:cause});
  await assert.rejects(f.read(),value=>value===cause);
  assert.equal(f.events.includes('project-response'),false);
  assert.equal(f.inspect().coreRetired,false);
  f.session.close();assert.equal(f.inspect().coreRetired,true);
});

test('same original Source reader retains grant response and binding until actual original retirement', async () => {
  const f = fixture({pendingBinding: true});
  assert.deepEqual(await f.read(), {pages:1,rowCount:1});
  assert.equal(typeof f.inspect().retainedOptions.readChild, 'function');
  assert.equal(f.inspect().stopped, false);
  assert.ok(f.events.indexOf('retain') < f.events.indexOf('bind'));
  assert.ok(f.events.indexOf('bind') < f.events.indexOf('provider-read'));
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().coreRetired, false);
  assert.equal(f.inspect().providerRetired, false);
  f.bindingRetires(); f.session.close();
  assert.equal(f.inspect().coreRetired, true);
  assert.equal(f.inspect().retainedOptions, undefined);
  assert.equal(f.inspect().providerRetired, true);
  assert.equal(f.inspect().stopped, true);
  assert.equal(f.events.filter(x => x === 'bind').length, 1);
});

test('same pending Source read cannot retire through stop or a copied factory', async () => {
  const gate = deferred(), f = fixture({pendingRead: gate.promise});
  assert.throws(() => ({...f.factory}).prepare(f.options), {code: 'ForeignInstalledCredentialSourceReader'});
  const reading = f.read();
  await f.readBegan;
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().coreRetired, false);
  assert.equal(f.inspect().providerRetired, false);
  gate.resolve(); await assert.rejects(reading, error => error.name === 'AbortError');
  f.session.close(); assert.equal(f.inspect().coreRetired, true);
  assert.equal(f.events.filter(x => x === 'provider-read').length, 1);
});

function directFixture({gate, pendingBinding = false, failCharge = false} = {}) {
  const events = [], raw = {grant:{},scope:{operation:'read'}}, credential = {}, capacity = {}, began = deferred();
  const bodies = ['account', 'schema', 'page', 'final-schema'].map(value => Object.freeze({body: Buffer.from(value)}));
  let cleanup, bindingClosed = !pendingBinding, retired = false, sent = 0;
  const originalSite = Object.freeze({site: Object.freeze({}), callResource(input) {
    const response = bodies[sent++];input.responseCustody.retain(response);
    events.push('retain-' + response.body.toString());return response;
  }, readChildCredential(_acquisition, authorization) {assert.equal(authorization,raw);return credential;},
    referenceCurrent() {return true;}, authorizationPurpose(value) {assert.equal(value, raw); return {kind: 'read'};},
    bindRunAcquisition(value, callbacks) {
      assert.equal(value, raw); callbacks.assertCurrent(); events.push('bind');
      return Object.freeze({credential, close() {events.push('close-binding'); return bindingClosed ? 'closed' : 'pending';}});
    }});
  const factory = createInstalledCredentialSourceReader({capacity, originalSite, maxResponses: 4, maxResponseBytes:128,
    assertCurrent() {}, prepareReadSequence() {return {
      async read(context) {
        events.push('sequence');
        for (let index=0;index<bodies.length;index++) {
          await context.readChild({operation:'read',prepare() {
            return {request:{method:'GET',path:'/part-' + index},project() {}};
          }});
          began.resolve();
          if (gate) await gate;
          if(index === bodies.length-1) await context.consumePage([{id:1}]);
          else await context.consumeObservation();
        }
      },retire() {events.push('provider-retire');return true;}
    };}});
  const options = Object.freeze({originalAuthorization: raw,columns:['id'],verifyRead() {events.push('current');},
    authorizationFor(index) {assert.equal(index,0);return {...raw,useId:'original-use'};},
    authorizeReadChild(operation,index) {
      assert.equal(operation,'read');return {authorization:{...raw,useId:'part-' + index},originalAuthorization:raw};
    },consumePage() {},consumeObservation() {},
    chargePage(body) {events.push('charge-' + body.toString());if(failCharge) throw new Error('original charge refused');return {};}});
  const moon = {clientProgramRowSourceStartProviderAccounted() {events.push('reserve'); return ok({});},
    clientProgramRowSourceBorrowResponses() {return ok({});},
    clientProgramRowSourceBindResponseCleanup(_borrow, value) {cleanup = value; events.push('retain-reader'); return ok(undefined);},
    clientProgramRowSourceRetireResponseWorkspace() {assert.fail('no Source completion in this control');},
    clientProgramRowSourceCloseAccounted() {if (!cleanup()) return error('original read/binding pending'); retired = true; return ok(undefined);},
    clientProgramRowSourceCaptureCleanup() {return ok(true);}};
  const session = startInstalledRowRun({moon, acquisition: {}, nonce: 'original-read', ledger: {},
    capacity: {provider: capacity, transferBytes: 100n, executionBytes: 100n}});
  return {events, bodies, session, began: began.promise,
    read() {return session.readProvider({prepare: factory.prepare, receiver: factory, options});},
    retireBinding() {bindingClosed = true;}, inspect() {return {retired, sent};}};
}

test('managed Source retains one sequence through original read and binding retirement', async () => {
  // Actual common reader and RowRun JS; no provider lifecycle/cleanup handle,
  // real grant, Core capacity, transport or physical ACK is supplied here.
  const gate = deferred(), f = directFixture({gate: gate.promise, pendingBinding: true});
  const reading = f.read(); await f.began;
  assert(f.events.indexOf('reserve') < f.events.indexOf('retain-reader'));
  assert(f.events.indexOf('retain-reader') < f.events.indexOf('bind'));
  assert(f.events.indexOf('retain-account') < f.events.indexOf('charge-account'));
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().retired, false);
  gate.resolve(); await assert.rejects(reading, error => error.name === 'AbortError');
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  f.retireBinding(); f.session.close();
  assert.equal(f.inspect().retired, true);
  assert.equal(f.events.filter(value => value === 'sequence').length, 1);
  assert.equal(f.events.filter(value => value === 'bind').length, 1);
  assert.equal(f.events.some(value => value === 'charge-schema'), false);
});

test('managed Source completes all responses then retires the same reader', async () => {
  const f = directFixture();
  assert.deepEqual(await f.read(), {pages:4,rowCount:1}); assert.equal(f.inspect().retired, false);
  for (const kind of ['account', 'schema', 'page', 'final-schema']) {
    assert(f.events.indexOf('retain-' + kind) < f.events.indexOf('charge-' + kind));
  }
  assert.equal(f.events.filter(value => value === 'sequence').length, 1);
  f.session.close(); assert.equal(f.inspect().retired, true);
});

test('managed Source accounting refusal cannot acknowledge unresolved accounting through binding closure', async () => {
  const f = directFixture({failCharge: true, pendingBinding: true});
  await assert.rejects(f.read(), /original charge refused/);
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().retired, false);
  assert.equal(f.events.filter(value => value.startsWith('charge-')).length, 1);
  f.retireBinding();
  assert.throws(() => f.session.close(), {code:'MoonBitHostFailure'});
  assert.equal(f.inspect().retired,false);assert.equal(f.inspect().sent,1);
});


// Actual Reader + actual RowRun JS; Core/authority/transport remain explicit
// ports. These assertions do not prove physical bytes or a normal budget.
test('original Reader can retire after capture while SAME Source and evidence remain live',async()=>{
  const f=fixture();await f.read();const captured=await f.complete();
  assert.equal(captured.capture.source(),f.capturedSource);
  const reader=f.reader();reader.requestStop();
  assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(f.inspect().coreRetired,false);
  assert.equal(f.inspect().retainedOptions,undefined);
  assert.equal(captured.capture.source(),f.capturedSource);
  assert.equal(await captured.issueSourceEvidence({authorityScopeCid:'scope',effectiveDataPolicyCid:'policy'}),f.evidence);
  assert.equal(await f.session.cleanup(),true);
  assert.equal(f.inspect().coreRetired,true);
  assert.throws(()=>captured.capture.source(),{code:'MoonBitHostFailure'});
  assert.equal(f.events.filter(value=>value==='bind').length,1);
});

test('original Reader pending binding prevents Source return and keeps SAME cleanup without another read',async()=>{
  const f=fixture({pendingBinding:true});await f.read();
  await assert.rejects(f.complete(),{code:'MoonBitHostFailure'});
  assert.equal(f.reader().observe().cleanupConfirmed,false);
  assert.equal(await f.session.cleanup(),false);
  assert.equal(f.inspect().coreRetired,false);
  assert.equal(f.events.includes('workspace-return'),false);
  f.bindingRetires();
  assert.equal(await f.session.cleanup(),true);
  assert.equal(f.inspect().coreRetired,true);
  assert.equal(f.events.filter(value=>value==='provider-read').length,1);
});

test('retired original Reader observer stays usable while Core capture cleanup remains pending',async()=>{
  const f=fixture();await f.read();const captured=await f.complete();
  f.reader().requestStop();assert.equal(f.reader().observe().cleanupConfirmed,true);
  f.captureCleanupReady(false);
  assert.equal(await f.session.cleanup(),false);
  assert.equal(f.inspect().coreRetired,false);
  assert.equal(captured.capture.source(),f.capturedSource);
  f.captureCleanupReady(true);
  assert.equal(await f.session.cleanup(),true);
  assert.equal(f.inspect().coreRetired,true);
});

// The native codec supplies its Site's original signed child and exact typed
// cells. Site/Core/current/charge ports remain explicit; this is not a normal
// Credential, numerical recipe or physical cleanup qualification.
function nativeReaderFixture({foreign = false, typed = false, replacement = false,
  pendingConsume, failConsume = false, admittedCount, asyncOriginal, getter = false,
  preparationHandoff = false, invocationHandoff = false, wrappedTransportFailure = false,
  asyncPreparation, preparationGetter = false, plainSequence = false} = {}) {
  const root = Object.freeze({grant: {}, scope: Object.freeze({operation: 'query'})});
  const metadata = Object.freeze({grant: {}, scope: Object.freeze({operation: 'describe'})});
  const original = foreign ? Object.freeze({...metadata}) : metadata;
  const provided = Object.freeze({originalAuthorization: original,
    authorization: Object.freeze({...original, useId: 'original-native-use'})});
  const names = Object.freeze(['id']), cells = Object.freeze([Object.freeze([Object.freeze({checked: 'original'})])]);
  const response = Object.freeze({accepted: true, statusCode: 200, body: Buffer.from('native response')});
  const charge = Object.freeze({}), credential = Object.freeze({}), site = Object.freeze({});
  let sends = 0, closes = 0, uses = 0, consumes = 0, charges = 0, retired = 0;
  const consuming = deferred();
  const preparedRead = Object.freeze({originalAcquisition: Object.freeze({})});
  let initialAuthorization;
  const acquisition = Object.freeze({credential, close() {closes++; return 'closed';}});
  const originalSite = Object.freeze({site,
    referenceCurrent() {return true;},
    authorizationPurpose(value) {assert.equal(value, root);return {kind: 'read'};},
    bindRunAcquisition(value, callbacks) {assert.equal(value, root);callbacks.assertCurrent();return acquisition;},
    readChildCredential(value, authorization) {
      assert.equal(value, acquisition);
      if (authorization !== metadata) throw Object.assign(new Error('ForeignOriginalNativeGrant'), {code: 'ForeignOriginalNativeGrant'});
      return credential;
    },
    async callResource(input) {
      assert.equal(this, site);assert.equal(input.grant, metadata.grant);
      assert.equal(input.useId, 'original-native-use');sends++;
      if (wrappedTransportFailure) throw undefined;
      await input.currentBeforeSend();input.responseCustody.retain(response);return response;
    },
  });
  let factory;
  factory = createInstalledCredentialSourceReader({capacity: {}, originalSite, assertCurrent() {},
    maxResponses: 1, maxResponseBytes: 128,
    prepareReadSequence(input) {
      if (plainSequence) assert.deepEqual(Reflect.ownKeys(input).sort(), ['columns', 'requestWire', 'resource']);
      if (preparationHandoff) {
        assert.equal(input.preparedRead, preparedRead);
        assert.equal(input.originalAuthorization, root);
        assert.equal(sends, 0);
      }
      return Object.freeze({async read(context, invocation) {
        if (plainSequence) assert.equal(arguments.length, 1);
        if (invocationHandoff) assert.equal(invocation, initialAuthorization);
        try {await context.readChild({operation: 'describe', prepare() {
          const selected = {original: provided, ...provided,
            request: Object.freeze({method: 'GET', path: '/original'}),
            project(actual) {assert.equal(actual, response);return undefined;}};
          if (asyncOriginal !== undefined) selected.originalAuthorization = asyncOriginal;
          if (getter) Object.defineProperty(selected, 'originalAuthorization', {get() {assert.fail('No native grant getter');}});
          return Object.freeze(selected);
        }});} catch (cause) {
          if (wrappedTransportFailure) throw new Error('Provider converted its original child failure');
          throw cause;
        }
        if (typed) await context.consumeValues(names, cells);
        else await context.consumeObservation();
      }, retire() {retired++;return true;}});
    },
  });
  const options = {originalAuthorization: root, columns: names,
    ...(preparationHandoff || invocationHandoff || asyncPreparation !== undefined ? {preparedRead: asyncPreparation ?? preparedRead} : {}),
    verifyRead() {}, authorizationFor(index) {assert.equal(index,0);
      initialAuthorization=Object.freeze({...root,useId:'original-root-use'});return initialAuthorization;},
    consumePage() {assert.fail('No JSON row fallback');},
    authorizeReadChild(operation, index, occurrence, actual) {
      assert.equal(operation, 'describe');assert.equal(index, 0);assert.equal(occurrence, provided);
      assert.equal(actual?.originalAuthorization, original);
      assert.equal(actual?.authorization, provided.authorization);
      uses++;return replacement ? Object.freeze({...actual, authorization: Object.freeze({...actual.authorization})}) : actual;
    },
    chargePage(body) {assert.equal(body, response.body);charges++;return charge;},
    consumeObservation(actual) {assert.equal(actual, charge);},
    consumeValues(actualNames, actualCells, facts) {
      assert.equal(actualNames, names);assert.equal(actualCells, cells);assert.equal(facts.charge, charge);
      consumes++;consuming.resolve();if (pendingConsume !== undefined) return pendingConsume.then(() => cells.length);
      if (failConsume) throw undefined;
      return admittedCount ?? cells.length;
    },
  };
  if (preparationGetter) Object.defineProperty(options, 'preparedRead', {get() {assert.fail('No prepared-read getter');}});
  const reader = factory.prepare(Object.freeze(options));
  return {factory, reader, provided, consuming: consuming.promise, metadata, counts: () => ({sends, closes, uses, consumes, charges, retired})};
}

test('shared native sequence prepares from the same original facts without doing provider IO', async () => {
  const f = nativeReaderFixture({preparationHandoff: true});
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 0});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
});

test('shared native sequence retains the earlier original transport failure through provider conversion', async () => {
  const f = nativeReaderFixture({wrappedTransportFailure: true});let caught = false;
  try {await f.reader.read();} catch (cause) {caught = true;assert.equal(cause, undefined);}
  assert.equal(caught, true);f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
});

test('shared native sequence keeps the existing single-argument protocol without a prepared input', async () => {
  const f = nativeReaderFixture({plainSequence: true});
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 0});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
});

test('shared native sequence refuses prepared input getters without invoking them', async () => {
  const f = nativeReaderFixture({preparationGetter: true});
  await assert.rejects(f.reader.read(), {code: 'InvalidInstalledSourceReadPreparation'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.equal(f.counts().sends, 0);
});

test('shared native sequence retains an asynchronous prepared input until its same computation settles', async () => {
  const gate = deferred(), f = nativeReaderFixture({asyncPreparation: gate.promise});
  await assert.rejects(f.reader.read(), {code: 'InstalledSourcePageCallbackNotSynchronous'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, false);assert.equal(f.factory.retire(), false);
  gate.resolve(Object.freeze({}));await Promise.resolve();await Promise.resolve();
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.equal(f.counts().sends, 0);
});

test('shared native sequence reads with the same first original invocation after binding', async () => {
  const f = nativeReaderFixture({invocationHandoff: true});
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 0});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
});

test('shared native reader keeps the Site original signed child without issuing another grant', async () => {
  const f = nativeReaderFixture();
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 0});
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, closes: 1, uses: 1, consumes: 0, charges: 1, retired: 1});
});

test('shared native reader consumes the same typed cells and original response charge without JSON', async () => {
  const f = nativeReaderFixture({typed: true});
  assert.deepEqual(await f.reader.read(), {pages: 1, rowCount: 1});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, closes: 1, uses: 1, consumes: 1, charges: 1, retired: 1});
});


test('shared native reader refuses a copied Site original before physical use without refunding the occurrence', async () => {
  const f = nativeReaderFixture({foreign: true});
  await assert.rejects(f.reader.read(), {code: 'ForeignOriginalNativeGrant'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 0, closes: 1, uses: 1, consumes: 0, charges: 0, retired: 1});
});

test('shared native reader refuses a substituted authorization envelope before physical use', async () => {
  const f = nativeReaderFixture({replacement: true});
  await assert.rejects(f.reader.read(), {code: 'ForeignInstalledSourceReadChild'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 0, closes: 1, uses: 1, consumes: 0, charges: 0, retired: 1});
});

test('shared native reader refuses grant accessors without invoking them or another issuer', async () => {
  const f = nativeReaderFixture({getter: true});
  await assert.rejects(f.reader.read(), {code: 'InvalidInstalledSourceReadChild'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 0, closes: 1, uses: 0, consumes: 0, charges: 0, retired: 1});
});

test('shared native reader keeps an invalid asynchronous original until its same computation settles', async () => {
  const gate = deferred(), f = nativeReaderFixture({asyncOriginal: gate.promise});
  await assert.rejects(f.reader.read(), {code: 'InstalledSourcePageCallbackNotSynchronous'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, false);
  assert.equal(f.factory.retire(), false);
  gate.resolve(f.metadata);await Promise.resolve();await Promise.resolve();
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 0, closes: 1, uses: 0, consumes: 0, charges: 0, retired: 1});
});

test('shared native typed consumption preserves thrown undefined and the original cleanup', async () => {
  const f = nativeReaderFixture({typed: true, failConsume: true});let caught = false;
  try {await f.reader.read();} catch (cause) {caught = true;assert.equal(cause, undefined);}
  assert.equal(caught, true);f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, closes: 1, uses: 1, consumes: 1, charges: 1, retired: 1});
});

test('shared native typed consumption rejects a different count after the original Core admission', async () => {
  const f = nativeReaderFixture({typed: true, admittedCount: 0});
  await assert.rejects(f.reader.read(), {code: 'InvalidInstalledSourceDecodedPage'});
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, closes: 1, uses: 1, consumes: 1, charges: 1, retired: 1});
});

test('shared native typed consumption keeps pending original cells and charge through stop', async () => {
  const gate = deferred(), f = nativeReaderFixture({typed: true, pendingConsume: gate.promise});
  const reading = f.reader.read();await f.consuming;
  f.reader.requestStop();assert.equal(f.reader.observe().readPending, true);
  assert.equal(f.reader.observe().cleanupConfirmed, false);assert.equal(f.factory.retire(), false);
  gate.resolve();await assert.rejects(reading, cause => cause.name === 'AbortError');
  assert.equal(f.reader.observe().cleanupConfirmed, true);assert.equal(f.factory.retire(), true);
  assert.deepEqual(f.counts(), {sends: 1, closes: 1, uses: 1, consumes: 1, charges: 1, retired: 1});
});

// Same actual original shared reader/RowRun fixture, with a pending selected
// provider, thrown undefined, and an independently failing original retirement.
// No Ledger/resource/physical ACK or normal provider acceptance is fabricated.
test('shared reader original undefined rejection survives concurrent stop and original retirement failure', async () => {
  let rejectRead, retirementAllowed = false;
  const pendingRead = new Promise((_resolve, reject) => {rejectRead = reject;});
  const cleanupFailure = Object.freeze(new Error('original provider retirement failed'));
  const f = fixture({pendingRead, providerRetirementFailure:cleanupFailure,
    providerRetirementAllowed:()=>retirementAllowed});
  const work = f.read();
  await f.providerReadPending;
  const original = f.reader();
  original.requestStop();
  assert.equal(original.observe().readPending,true);
  rejectRead(undefined);
  let rejected = false, cause;
  try {await work;} catch (value) {rejected=true;cause=value;}
  assert.equal(rejected,true);assert.strictEqual(cause,undefined,'original failed phase carries presence even for undefined');
  assert.equal(original.observe().cleanupConfirmed,false);
  assert.equal(original.observe().transportFailure,true);
  assert.equal(f.inspect().providerRetired,false);assert.equal(f.inspect().coreRetired,false);
  assert.throws(()=>original.retry(),error=>error===cleanupFailure);
  assert.equal(original.observe().cleanupConfirmed,false);
  retirementAllowed=true;
  original.retry();assert.equal(original.observe().cleanupConfirmed,true);
  assert.equal(f.inspect().providerRetired,true);
  f.session.close();assert.equal(f.inspect().coreRetired,true);
  assert.equal(f.factory.retire(),true);
});

// Real generic factory with explicit provider/Site ports. The sentinel is only
// a forwarding identity, not proof of a native borrow or resource admission.
function borrowHandoffFixture({managed=true,privateBorrow,optionBorrow,optionGetter=false,adoptionFailure}={}) {
  let projected,retirements=0,sends=0;
  const originalAuthorization=Object.freeze({grant:{},scope:{operation:'read'}});
  const originalSite={site:{},referenceCurrent:()=>true,
    bindRunAcquisition(){assert.fail('handoff preparation must not bind transport');},
    authorizationPurpose(){assert.fail('handoff preparation must not request authority');},
    readChildCredential(){assert.fail('handoff preparation must not obtain credentials');},
    callResource(){sends++;assert.fail('handoff preparation must not send');},
  };
  const project=input=>{
    projected=input;
    if(adoptionFailure)throw adoptionFailure;
    return managed?Object.freeze({read(){assert.fail('protocol must not run');},retire(){retirements++;return true;}})
      :Object.freeze({fetchPage(){assert.fail('page must not fetch');},decodePage(){assert.fail('page must not decode');}});
  };
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,
    assertCurrent(){},maxResponses:1,maxResponseBytes:128,
    ...(managed?{prepareReadSequence:project}:{preparePageReader:project,operation:'read',maxSecretBytes:128}),
  });
  const options={resource:'records',columns:Object.freeze(['id']),requestWire:'{}',originalAuthorization,
    verifyRead(){},authorizationFor(){assert.fail('no grant during preparation');},
    authorizeReadChild(){assert.fail('no child grant during preparation');},
    chargePage(){assert.fail('no response during preparation');},
    consumePage(){assert.fail('no page during preparation');},
    consumeObservation(){assert.fail('no observation during preparation');},
  };
  if(optionGetter)Object.defineProperty(options,'responseBorrow',{get(){assert.fail('do not inspect options borrow getter');}});
  else if(optionBorrow!==undefined)options.responseBorrow=optionBorrow;
  Object.freeze(options);
  const reader=factory.prepare(options,undefined,undefined,privateBorrow);
  return {reader,factory,options,originalAuthorization,projected,counts:()=>({retirements,sends})};
}

test('native factory receives the same private fourth borrow without replacing original options',()=>{
  const borrow=Object.freeze({}),foreign=Object.freeze({});
  const f=borrowHandoffFixture({privateBorrow:borrow,optionBorrow:foreign});
  assert.equal(f.projected.responseBorrow,borrow);
  assert.equal(f.projected.originalAuthorization,f.originalAuthorization);
  assert.equal(f.options.responseBorrow,foreign);
  assert.equal(Object.hasOwn(f.projected,'preparedRead'),false);
  assert.equal(Object.isFrozen(f.projected),true);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);
  assert.deepEqual(f.counts(),{retirements:1,sends:0});
});

test('legacy JSON factory does not receive the private native borrow or added authorization',()=>{
  const f=borrowHandoffFixture({managed:false,privateBorrow:Object.freeze({}),optionGetter:true});
  assert.deepEqual(Object.keys(f.projected).sort(),['columns','requestWire','resource']);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);assert.equal(f.counts().sends,0);
});

test('options responseBorrow cannot substitute for the absent private handoff',()=>{
  for(const optionGetter of [false,true]){
    const f=borrowHandoffFixture({optionBorrow:Object.freeze({}),optionGetter});
    assert.equal(Object.hasOwn(f.projected,'responseBorrow'),false);
    assert.equal(Object.hasOwn(f.projected,'originalAuthorization'),false);
    f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
    assert.equal(f.factory.retire(),true);
  }
});

test('native adoption refusal stays with the original factory and does not enter Site IO',async()=>{
  const failure=new Error('original native adoption refusal');
  const f=borrowHandoffFixture({privateBorrow:Object.freeze({}),adoptionFailure:failure});
  await assert.rejects(f.reader.read(),error=>error===failure);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);assert.equal(f.counts().sends,0);
});
