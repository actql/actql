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
