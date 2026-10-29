import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';

// The same explicit grant/response ports as the ManagedReader components.
// This composes the actual C owner with the actual G adapter. It is not a
// normal Account, compiled Common, SDK/Host or full-backing acceptance case.
function composed(transform) {
  const events = [], body = Buffer.from('{"data":[{"id":"one"}],"next":null}');
  const response = {accepted: true, statusCode: 200, body};
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name =>
    [name, name])), operation: 'acme:customers:read', resourceOrigin: 'https://example.invalid'});
  const grant = {}, control = {identity: () => 'original-grant'};
  const journal = {claim(_cid, useId) {return {use: {}, record: {grantCid: 'original-grant', useId}, replayed: false};},
    authorize() {}, finish() {}};
  const site = {credential: {control, journal, resolveSecret: () => 'synthetic-secret'},
    referenceCurrent() {assert.strictEqual(this, site);return true;},
    async callResource() {assert.strictEqual(this, site);events.push('send');return response;}};
  const source = {resource: 'customers', fields: [{name: 'id'}],
    read: {method: 'GET', path: '/v1/customers'},
    pagination: {kind: 'cursor', items: ['data'], next: ['next'], parameter: 'after'},
    limits: {maxPageRows: 2, maxPageBytes: 1024, maxPages: 2, maxRows: 4,
      maxNodes: 64, maxDepth: 8, maxCursorBytes: 32}};
  const page = {};
  const moon = {
    clientProgramRowSourceProjectJsonPage(value) {
      assert.strictEqual(value, body);assert(events.includes('charge'));events.push('project');
      return {$tag: 1, _0: page};
    },
    clientProgramRowSourceJsonPageRowsWire(value) {assert.strictEqual(value, page);return '[{"id":"one"}]';},
    clientProgramRowSourceJsonPageRowCount(value) {assert.strictEqual(value, page);return 1;},
    clientProgramRowSourceJsonPageHasNextCursor(value) {assert.strictEqual(value, page);return false;},
    clientProgramRowSourceJsonPageNextCursor() {assert.fail('No cursor');},
  };
  const factory = createInstalledCredentialSourceReader({capacity: {}, site, operation: scope.operation,
    maxResponses: 1, maxResponseBytes: 1024, maxSecretBytes: 64,
    preparePageReader: restSourcePageReader({moon, source, decodePage: transform})});
  const callbacks = {resource: 'customers', columns: ['id'], requestWire: 'original-request',
    async verifyRead() {events.push('current');},
    async authorizationFor(index) {return {grant, scope, useId: `original-use-${index}`};},
    async chargePage(value) {assert.strictEqual(value, body);events.push('charge');return {body};},
    async consumePage() {assert.fail('Wire path only');},
    async consumePageWire() {events.push('consume');},
  };
  return {reader: factory.prepare(callbacks), events};
}

test('managed owner joins the exact nested author transform before retiring its charged response', async t => {
  let resolve, thenReads = 0, thenCalls = 0, thenReceiver, transformCalls = 0;
  const pending = new Promise(yes => {resolve = yes;});
  Object.defineProperty(pending, 'then', {get() {
    thenReads++;
    return function (...args) {thenCalls++;thenReceiver = this;return Reflect.apply(Promise.prototype.then, this, args);};
  }});
  const f = composed(() => {transformCalls++;return pending;});
  let primary;
  try {await f.reader.read();assert.fail('An asynchronous author transform must refuse');}
  catch (cause) {primary = cause;}
  assert.equal(transformCalls, 1);
  assert.equal(f.events.filter(value => value === 'send').length, 1);
  assert.equal(f.events.filter(value => value === 'charge').length, 1);
  assert.equal(f.events.filter(value => value === 'project').length, 1);
  assert.equal(f.events.includes('consume'), false);
  f.reader.requestStop();
  const stopped = f.reader.observe();
  t.diagnostic(JSON.stringify({actualPrimaryCode: primary.code, stopped,
    transformCalls, thenReads, thenCalls}, (_, value) => typeof value === 'bigint' ? String(value) : value));
  assert.equal(stopped.transportClosed, true);
  assert.equal(stopped.cleanupConfirmed, false,
    'A refused still-running nested transform must keep the original charged response borrow');
  assert.equal(stopped.pendingCallbacks, 1);
  assert.equal(thenReads, 1);assert.equal(thenCalls, 1);assert.strictEqual(thenReceiver, pending);
  assert.equal(primary.code, 'InstalledSourcePageCallbackNotSynchronous');
  resolve();
  await new Promise(yes => setImmediate(yes));
  assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.reader.observe().pendingCallbacks, 0);
  f.reader.retry();
  assert.equal(f.events.filter(value => value === 'send').length, 1);
  assert.equal(f.events.includes('consume'), false);
});
