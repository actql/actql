import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';

// Actual shared Reader lifetime JS. The original Site, current decision and
// transport close/retirement are explicit ports; no physical lease is opened.
function fixture({malformed = false} = {}) {
  const originalAuthorization = {}, control=Object.freeze({kind:'installation-metadata'}),
    credential={control},events=[];
  let retireReady = false, retireGetterCalls = 0;
  const acquisition = {credential, close() {
    assert.equal(this, acquisition);events.push('socket-close');return 'closed';
  }};
  if (malformed) Object.defineProperty(acquisition, 'retire', {get() {
    retireGetterCalls++;assert.fail('The returned retirement accessor must not be invoked');
  }});
  else acquisition.retire = function retire() {
    assert.equal(this, acquisition);events.push('binding-retire');return retireReady;
  };
  Object.freeze(acquisition);
  const originalSite = Object.freeze({site: Object.freeze({}),
    callResource() {assert.fail('No physical send in this component');},
    readChildCredential() {assert.fail('No physical child in this lifetime component');},
    referenceCurrent() {return true;},
    authorizationPurpose(value) {
      assert.equal(value, originalAuthorization);return {kind:'installation-metadata',control};
    },
    bindRunAcquisition(value, callbacks) {
      assert.equal(value, originalAuthorization);callbacks.assertCurrent();
      events.push('bind');return acquisition;
    },
  });
  const factory = createInstalledCredentialSourceReader({capacity: {}, originalSite,
    assertCurrent() {}, maxResponses: 1,
    maxResponseBytes:128,prepareReadSequence() {return {
      read() {events.push('provider-read');},retire() {return true;}
    };},
  });
  const reader = factory.prepare({originalAuthorization, columns: ['id'],
    verifyRead() {},authorizeReadChild() {},chargePage() {},consumeObservation() {},authorizationFor(index) {
      assert.equal(index, 0);events.push('authorize');return {original: originalAuthorization};
    },
  });
  return {reader, factory, events, ready() {retireReady = true;},
    getterCalls() {return retireGetterCalls;}};
}

test('invalid original binding retirement cannot become acknowledged socket cleanup', async () => {
  const f = fixture({malformed: true});
  await assert.rejects(f.reader.read(), {code: 'InstalledSourceReaderMethodUnavailable'});
  assert.deepEqual(f.events, ['bind']);assert.equal(f.getterCalls(), 0);
  f.reader.requestStop(new Error('same-read-stop'));
  const observed = f.reader.observe();
  assert.equal(observed.transportClosed, true);
  assert.equal(observed.readPending, false);
  assert.equal(observed.cleanupConfirmed, false);
  assert.equal(f.factory.retire(), false);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  assert.deepEqual(f.events, ['bind', 'socket-close']);
  assert.equal(f.getterCalls(), 0);
});

test('valid original binding retirement keeps its pending duty and completes on the same retry', async () => {
  const f = fixture();
  await f.reader.read();
  f.reader.requestStop();
  assert.equal(f.reader.observe().transportClosed, true);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  assert.equal(f.factory.retire(), false);
  f.ready();f.reader.retry();
  assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.factory.retire(), true);
  assert.equal(f.events.filter(value => value === 'bind').length, 1);
  assert.equal(f.events.filter(value => value === 'socket-close').length, 1);
  assert.equal(f.events.filter(value => value === 'provider-read').length, 1);
});
