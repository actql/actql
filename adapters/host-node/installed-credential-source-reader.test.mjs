import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';

// Actual common reader and RowRun lifetime JS. Site issuer/private binding,
// provider, Account/current and Core/funding methods are explicit ports.
const ok = value => ({$tag: 1, _0: value});
const error = value => ({$tag: 0, _0: value});
const deferred = () => {let resolve; const promise = new Promise(r => {resolve = r;}); return {resolve, promise};};
function fixture({pendingRead, pendingBinding = false} = {}) {
  const events = [], raw = {}, credential = {}, capacity = {}, charge = {}, began = deferred();
  const response = Object.freeze({body: Buffer.from('same received bytes')});
  let current = true, bindingCanClose = !pendingBinding, providerRetired = false, stopped = false;
  let retainedOptions, cleanup, coreRetired = false;
  const site = {}, acquisition = Object.freeze({credential, close() {
    assert.equal(this, acquisition); events.push('binding-close'); return bindingCanClose ? 'closed' : 'pending';
  }});
  const originalSite = Object.freeze({site, callResource() {assert.equal(this, site);},
    referenceCurrent() {return current;}, authorizationPurpose(authorization) {
      assert.equal(authorization, raw); return {kind: 'read'};
    }, bindRunAcquisition(authorization, callbacks) {
      assert.equal(authorization, raw); callbacks.assertCurrent(); events.push('bind'); return acquisition;
    }});
  let provider;
  const factory = createInstalledCredentialSourceReader({capacity, originalSite,
    assertCurrent() {if (!current) throw new Error('original Host retired');}, maxResponses: 1,
    createReader(options) {
      assert.equal(options.credential, credential); retainedOptions = options;
      events.push('provider-create');
      provider = Object.freeze({async read() {
        assert.equal(this, provider); events.push('provider-read');
        options.responseCustody.retain(response);
        await options.chargePage(response.body);
        if (pendingRead) await pendingRead;
        if (stopped) throw new Error('original read stopped');
        return {rowCount: 1};
      }, requestStop() {assert.equal(this, provider); stopped = true; events.push('provider-stop');},
      retire() {assert.equal(this, provider); providerRetired = true; retainedOptions = undefined; return true;},
      observe() {assert.equal(this, provider); return {cleanupConfirmed: providerRetired};}});
      return provider;
    }});
  const options = Object.freeze({originalAuthorization: raw, columns: ['id'],
    verifyRead() {events.push('verify');}, authorizationFor(index) {
      assert.equal(index, 0); events.push('use'); return {original: raw, useId: 'one'};
    }, chargePage(bytes) {assert.equal(bytes, response.body); events.push('charge'); began.resolve(); return charge;}});
  const run = {}, source = {}, ledger = {};
  const moon = {
    clientProgramRowSourceStartProviderAccounted() {events.push('reserve'); return ok(run);},
    clientProgramRowSourceBorrowResponses() {events.push('borrow'); return ok({});},
    clientProgramRowSourceBindResponseCleanup(borrow, observed) {cleanup = observed; events.push('retain'); return ok(undefined);},
    clientProgramRowSourceCloseAccounted() {
      if (!cleanup()) return error('same original response duty pending');
      coreRetired = true; events.push('core-retire'); return ok(undefined);
    },
    clientProgramRowSourceCaptureCleanup() {return ok(true);},
  };
  const session = startInstalledRowRun({moon, acquisition: source, nonce: 'one', ledger,
    capacity: {provider: capacity, transferBytes: 100n, executionBytes: 100n}});
  return {factory, options, events, session, response, readBegan: began.promise,
    read() {return session.readProvider({prepare: factory.prepare, receiver: factory, options});},
    bindingRetires() {bindingCanClose = true;},
    inspect() {return {coreRetired, providerRetired, retainedOptions, stopped};}};
}

test('same original Source reader retains grant response and binding until actual original retirement', async () => {
  const f = fixture({pendingBinding: true});
  assert.equal(await f.read(), undefined);
  assert.equal(f.inspect().retainedOptions.initialAuthorization.original, f.options.originalAuthorization);
  assert.equal(f.inspect().retainedOptions.credential === undefined, false);
  assert.ok(f.events.indexOf('retain') < f.events.indexOf('bind'));
  assert.ok(f.events.indexOf('bind') < f.events.indexOf('provider-read'));
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().coreRetired, false);
  assert.equal(f.inspect().providerRetired, true);
  f.bindingRetires(); f.session.close();
  assert.equal(f.inspect().coreRetired, true);
  assert.equal(f.inspect().retainedOptions, undefined);
  assert.equal(f.events.filter(x => x === 'provider-stop').length, 1);
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
  gate.resolve(); await assert.rejects(reading, /original read stopped/);
  f.session.close(); assert.equal(f.inspect().coreRetired, true);
  assert.equal(f.events.filter(x => x === 'provider-read').length, 1);
});

function directFixture({gate, pendingBinding = false, failCharge = false} = {}) {
  const events = [], raw = {}, credential = {}, capacity = {}, began = deferred();
  const bodies = ['account', 'schema', 'page', 'final-schema'].map(value => Object.freeze({body: Buffer.from(value)}));
  let cleanup, bindingClosed = !pendingBinding, retired = false, phase;
  const originalSite = Object.freeze({site: Object.freeze({}), callResource() {assert.fail('no physical transport in this component');},
    referenceCurrent() {return true;}, authorizationPurpose(value) {assert.equal(value, raw); return {kind: 'read'};},
    bindRunAcquisition(value, callbacks) {
      assert.equal(value, raw); callbacks.assertCurrent(); events.push('bind');
      return Object.freeze({credential, close() {events.push('close-binding'); return bindingClosed ? 'closed' : 'pending';}});
    }});
  const factory = createInstalledCredentialSourceReader({capacity, originalSite, maxResponses: 4,
    assertCurrent() {}, async readPages(options) {
      assert.equal(options.credential, credential); assert.equal(options.initialAuthorization.original, raw);
      events.push('sequence'); began.resolve();
      for (const response of bodies) {
        options.responseCustody.retain(response); events.push('retain-' + response.body.toString());
        await options.chargePage(response.body);
        if (gate) await gate;
        options.signal.throwIfAborted();
      }
      return Object.freeze({pages: 1, rowCount: 1});
    }});
  const options = Object.freeze({originalAuthorization: raw, verifyRead() {events.push('current');},
    authorizationFor(index) {assert.equal(index, 0); return {original: raw, useId: 'original-use'};},
    chargePage(body) {events.push('charge-' + body.toString()); if (failCharge) throw new Error('original charge refused'); return {};}});
  const moon = {clientProgramRowSourceStartProviderAccounted() {events.push('reserve'); return ok({});},
    clientProgramRowSourceBorrowResponses() {return ok({});},
    clientProgramRowSourceBindResponseCleanup(_borrow, value) {cleanup = value; events.push('retain-reader'); return ok(undefined);},
    clientProgramRowSourceCloseAccounted() {if (!cleanup()) return error('original read/binding pending'); retired = true; return ok(undefined);},
    clientProgramRowSourceCaptureCleanup() {return ok(true);}};
  const session = startInstalledRowRun({moon, acquisition: {}, nonce: 'original-read', ledger: {},
    capacity: {provider: capacity, transferBytes: 100n, executionBytes: 100n}});
  return {events, bodies, session, began: began.promise,
    read() {return session.readProvider({prepare: factory.prepare, receiver: factory, options});},
    retireBinding() {bindingClosed = true;}, inspect() {return {retired, phase};}};
}

test('standard Source directly retains one sequence through original read and binding retirement', async () => {
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

test('direct standard Source completes all responses then retires the same reader', async () => {
  const f = directFixture();
  assert.equal(await f.read(), undefined); assert.equal(f.inspect().retired, false);
  for (const kind of ['account', 'schema', 'page', 'final-schema']) {
    assert(f.events.indexOf('retain-' + kind) < f.events.indexOf('charge-' + kind));
  }
  assert.equal(f.events.filter(value => value === 'sequence').length, 1);
  f.session.close(); assert.equal(f.inspect().retired, true);
});

test('direct standard Source accounting refusal preserves its same binding duty', async () => {
  const f = directFixture({failCharge: true, pendingBinding: true});
  await assert.rejects(f.read(), /original charge refused/);
  assert.throws(() => f.session.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspect().retired, false);
  assert.equal(f.events.filter(value => value.startsWith('charge-')).length, 1);
  f.retireBinding(); f.session.close(); assert.equal(f.inspect().retired, true);
});

test('same standard reader preserves its original cancellation reason after delivery', async () => {
  const reason=new Error('original cancellation'),raw={},scope=Object.freeze({
    grantCid:'same',site:'same',siteGeneration:'same',operation:'fixture:cancel',
    resourceOrigin:'https://example.invalid'});
  // This component supplies nominal grant/Site/transport ports. It does not
  // certify actual Account/HTTPS or a normal capacity reservation.
  const {credentialInvocationBindingKeys}=await import('../host-common/credential-scope-fields.generated.mjs');
  const originalScope=Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,'same'])),
    operation:scope.operation,resourceOrigin:scope.resourceOrigin});
  const grant={},response=Object.freeze({accepted:true,statusCode:200,body:Buffer.from('one')});
  let sends=0,closed=0,consumed=0;
  const site=Object.freeze({callResource() {sends++;return response;}});
  const originalSite=Object.freeze({site,callResource:site.callResource,referenceCurrent:()=>true,
    authorizationPurpose(value) {assert.equal(value,raw);return {kind:'read'};},
    bindRunAcquisition(value) {assert.equal(value,raw);return Object.freeze({
      credential:{control:{identity:()=> 'same'},journal:{claim(_cid,useId) {
        return {use:{},record:{grantCid:'same',useId},replayed:false};},authorize() {},finish() {}},
        resolveSecret:()=> 'secret'},close() {closed++;return 'closed';}});}});
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},
    operation:originalScope.operation,maxResponses:2,maxResponseBytes:64,maxSecretBytes:64,
    preparePageReader() {return Object.freeze({fetchPage:()=>({method:'GET',path:'/one'}),
      decodePage:()=>({rows:[{id:'one'}],done:false})});}});
  const reader=factory.prepare({resource:'one',columns:['id'],originalAuthorization:raw,
    verifyRead() {},authorizationFor(index) {return {grant,scope:originalScope,useId:String(index)};},
    chargePage:body=>body,consumePage() {consumed++;reader.requestStop(reason);}});
  await assert.rejects(reader.read(),error=>error===reason);
  assert.equal(sends,1);assert.equal(consumed,1);assert.equal(closed,1);
  assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(factory.retire(),true);
});


test('native advanced constructor retains its actual late child through original stop settlement', async t => {
  // Actual shared Host owner; Site/grant/child and stop acknowledgements are
  // explicit component ports, not physical transport or normal funding.
  const construction = deferred(), entered = deferred(), stop = deferred(), stopEntered = deferred();
  const getterFailure = new Error('same native constructor then getter');
  const cancellation = new Error('same pending constructor cancellation');
  let thenReads = 0, childReads = 0, childStops = 0, childRetires = 0;
  let childStopped = false, childStopSettled = false, bindingCloses = 0, childStopPromise;
  Object.defineProperty(construction.promise, 'then', {get() {
    thenReads++; throw getterFailure;
  }});
  const child = Object.freeze({read() {childReads++;assert.fail('invalid async constructor never starts its child');},
    requestStop(reason) {
      assert.equal(this, child);assert.equal(reason, cancellation);childStops++;
      childStopPromise = stop.promise.then(() => {childStopped = true;childStopSettled = true;});
      stopEntered.resolve();return childStopPromise;
    }, retire() {
      assert.equal(this, child);childRetires++;
      return childStopped && childStopSettled;
    }, observe() {assert.equal(this, child);return {cleanupConfirmed:childStopped && childStopSettled};}});
  t.after(() => {construction.resolve(child);stop.resolve();});
  const raw = {}, credential = {}, site = Object.freeze({});
  const originalSite = Object.freeze({site,callResource() {assert.fail('no physical call');},
    referenceCurrent:()=>true,authorizationPurpose(value) {assert.equal(value,raw);return {kind:'read'};},
    bindRunAcquisition(value) {assert.equal(value,raw);return Object.freeze({credential,
      close() {bindingCloses++;return 'closed';}});}});
  const factory = createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},
    maxResponses:1,createReader() {entered.resolve();return construction.promise;}});
  const reader = factory.prepare({originalAuthorization:raw,verifyRead() {},authorizationFor() {return {};}});
  const outcome = reader.read().then(() => assert.fail('invalid constructor cannot succeed'),cause=>cause);
  await entered.promise;
  reader.requestStop(cancellation);
  let retired;
  assert.doesNotThrow(() => {retired = factory.retire();});
  assert.equal(retired,false);assert.equal(reader.observe().cleanupConfirmed,false);
  construction.resolve(child);
  await stopEntered.promise;
  assert.equal(childStops,1);assert.equal(childReads,0);
  assert.equal(reader.observe().cleanupConfirmed,false);
  assert.equal(factory.retire(),false);
  stop.resolve();await childStopPromise;
  assert.equal(await outcome,getterFailure);
  assert.equal(thenReads,1);assert.equal(childStops,1);assert.equal(childReads,0);
  assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(factory.retire(),true);
  assert.equal(bindingCloses,1);assert.equal(childRetires,1);
});

function asynchronousConstructorFixture(construct) {
  const raw = {}, entered = deferred();let reads = 0, stops = 0, retired = false, bindingCloses = 0;
  const child = Object.freeze({read() {reads++;assert.fail('refused constructor must not start child');},
    requestStop() {assert.equal(this,child);stops++;},
    retire() {assert.equal(this,child);retired = stops === 1;return retired;},
    observe() {assert.equal(this,child);return {cleanupConfirmed:retired};}});
  const originalSite = Object.freeze({site:{},callResource() {assert.fail('no physical transport');},
    referenceCurrent:()=>true,authorizationPurpose(value) {assert.equal(value,raw);return {kind:'read'};},
    bindRunAcquisition(value) {assert.equal(value,raw);return Object.freeze({credential:{},
      close() {bindingCloses++;return 'closed';}});}});
  const factory = createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},maxResponses:1,
    createReader() {entered.resolve();return construct(child);}});
  const reader = factory.prepare({originalAuthorization:raw,verifyRead() {},authorizationFor() {return {};}});
  return {child,reader,factory,entered:entered.promise,inspect:()=>({reads,stops,retired,bindingCloses})};
}

test('refused constructors join hidden native and generic late children without another read',async()=>{
  for (const native of [true,false]) {
    const gate = deferred();
    if (native) Object.defineProperty(gate.promise,'then',{value:undefined});
    const f = asynchronousConstructorFixture(()=>native ? gate.promise : Object.freeze({then(resolve,reject) {
      return Reflect.apply(Promise.prototype.then,gate.promise,[resolve,reject]);
    }}));
    const outcome = f.reader.read().then(()=>assert.fail('async constructor cannot succeed'),cause=>cause);
    await f.entered;
    f.reader.requestStop(new Error('same original stop'));
    assert.equal(f.factory.retire(),false);assert.equal(f.reader.observe().cleanupConfirmed,false);
    gate.resolve(f.child);
    assert.equal((await outcome).code,'InstalledSourceReaderConstructorNotSynchronous');
    assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
    assert.deepEqual(f.inspect(),{reads:0,stops:1,retired:true,bindingCloses:1});
  }
});

test('rejected native constructor preserves the first original failure without inventing a child',async()=>{
  for (const throwingGetter of [false,true]) {
    const gate = Promise.withResolvers(),rejection = new Error('same constructor rejection');
    const observation = new Error('same first then observation');
    if (throwingGetter) Object.defineProperty(gate.promise,'then',{get() {throw observation;}});
    const f = asynchronousConstructorFixture(()=>gate.promise);
    const outcome = f.reader.read().then(()=>assert.fail('rejected constructor cannot succeed'),cause=>cause);
    await f.entered;
    assert.equal(f.factory.retire(),false);assert.equal(f.reader.observe().cleanupConfirmed,false);
    gate.reject(rejection);
    assert.equal(await outcome,throwingGetter ? observation : rejection);
    assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
    assert.deepEqual(f.inspect(),{reads:0,stops:0,retired:false,bindingCloses:1});
  }
});

test('rejected generic constructor releases no unresolved placeholder as a physical child',async()=>{
  const gate = Promise.withResolvers(),rejection = new Error('same generic constructor rejection');
  const f = asynchronousConstructorFixture(()=>Object.freeze({then(resolve,reject) {
    return Reflect.apply(Promise.prototype.then,gate.promise,[resolve,reject]);
  }}));
  const outcome = f.reader.read().then(()=>assert.fail('rejected constructor cannot succeed'),cause=>cause);
  await f.entered;
  assert.equal(f.factory.retire(),false);assert.equal(f.reader.observe().cleanupConfirmed,false);
  gate.reject(rejection);
  assert.equal(await outcome,rejection);
  assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);
  assert.deepEqual(f.inspect(),{reads:0,stops:0,retired:false,bindingCloses:1});
});
