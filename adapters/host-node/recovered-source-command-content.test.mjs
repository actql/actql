// Actual Source child and Store composition with explicit nominal Core ports.
// These cases prove custody/current ordering, not a real Core Source admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {prepareRecoveredSourceCommandContent} from './recovered-source-command-content.mjs';

function fixture({cutFailure} = {}) {
  const candidate = {}, issued = {}, sourceOriginal = {}, prepared = {}, request = {};
  const captured = {}, preview = {}, invocation = {}, source = {}, definition = {};
  const binding = {effective_data_policy_cid: 'policy', expires_at: '2099-01-01T00:00:00.000Z'};
  const bindingWire = canonicalJson(binding), events = [];
  const holding = {holding_cid: 'holding', namespace: 'content', manifest_cid: 'reference',
    objects: [{cid: 'bytes', byte_count: 3}]};
  let live = true, released = false, native = 0, reading = 0, currentRole, inspect, consume;
  const roles = [];
  const nominal = Object.freeze({binding: {}, current: () => live && !released,
    matchesIssued: value => value === issued && live && !released,
    release() {events.push('release view'); released = true;}});
  const description = {storeCid: 'Store', workspaceScopeCid: 'scope',
    effectiveDataPolicyCid: 'policy', identity: 'reference', contentCid: 'bytes',
    sizeBytes: 3, wire: 'original reference', mediaType: 'application/octet-stream'};
  const control = {
    recoveryCandidateForEffectOriginal(original, owner, originalRequest, wire, actualBinding) {
      assert.strictEqual(original, sourceOriginal); assert.strictEqual(owner, prepared);
      assert.strictEqual(originalRequest, request); assert.equal(wire, 'original reference');
      assert.equal(actualBinding, bindingWire); assert(native > 0 && reading > 0);
      assert.equal(currentRole, 'candidate');
      events.push('candidate'); return candidate;
    },
    holdingCid(value) {assert.strictEqual(value, candidate); assert(native > 0); assert.equal(currentRole, 'holding'); return 'holding';},
    inspect(value) {assert.strictEqual(value, candidate); assert(native > 0); assert.equal(currentRole, 'inspect'); return description;},
    issuer(available, authorize) {assert(native > 0); assert.equal(currentRole, 'issuer'); return {available, authorize};},
    issue(value, issuer) {
      assert.strictEqual(value, candidate); assert(native > 0);
      assert.equal(currentRole, 'issue');
      assert.equal(issuer.available(undefined, description.wire), true);
      assert.equal(issuer.authorize(description.wire), true);
      events.push('issue'); return issued;
    },
  };
  const store = {storeAuthorityCid: 'Store', status: () => ({closed: false}),
    async inspectPhysicalHolding(value) {
      assert.equal(value, 'holding'); events.push('holding'); await inspect?.(); return holding;
    },
    async commitPhysicalHolding(value, objects) {
      assert.strictEqual(value, holding); assert.deepEqual(objects, []); events.push('commit');
    },
    async consumePhysicalHolding(value, index, accept) {
      assert.equal(value, 'holding'); assert.equal(index, 0); events.push('consume');
      await accept(Buffer.from('abc')); await consume?.();
    },
  };
  const publications = {recoverSourceEffectCommandContent(value) {
    assert(native > 0 && reading > 0);
    assert.equal(currentRole, 'view');
    for (const [key, expected] of Object.entries({sourceOriginal, prepared, request,
      definition, captured, preview, invocation, source, candidate, issued}))
      assert.strictEqual(value[key], expected);
    assert.equal(value.memberIndex, 0); assert.equal(value.row, 0); assert.equal(value.inputName, 'content');
    events.push('bind Source'); return nominal;
  }};
  const recoveryResources = {constructCaptured() {assert.fail('Source validation does not restart physical capture');},
    constructCapturedValidation(value, receiver, method, argument) {
    assert.strictEqual(value, captured); assert.strictEqual(receiver, undefined);
    reading++;
    try {
      const result = Reflect.apply(method, receiver, [argument]);
      if (cutFailure !== undefined && events.includes('bind Source')) throw cutFailure;
      return result;
    } finally {reading--;}
  }};
  const child = prepareRecoveredSourceCommandContent({publications, control, sourceOriginal,
    prepared, request, definition, captured, preview, invocation, source, store,
    principalId: 'actor', ownerPrincipal: 'actor', storeAuthorityCid: 'Store',
    authorityScopeCid: 'scope', now: () => '2026-11-16T00:00:00.000Z', authorize: () => live,
    binding, sourcePolicyCid: 'policy', referenceLimits: {}, memberIndex: 0, row: 0,
    inputName: 'content', referenceWire: 'original reference',
    assertCurrent() {if (!live) throw new Error('OriginalRunRetired');}, limits: {}, recoveryResources,
    sourceConstruction(receiver, method, args, actualBinding, role) {
      assert.equal(actualBinding, bindingWire); native++;
      assert(['candidate', 'holding', 'inspect', 'issuer', 'issue', 'view'].includes(role));
      roles.push(role);
      const previous = currentRole; currentRole = role;
      try {return Reflect.apply(method, receiver, args);} finally {native--; currentRole = previous;}
    }});
  return {child, events, roles, nominal, retire() {live = false;},
    inspect(value) {inspect = value;}, consume(value) {consume = value;}};
}

test('Source child reuses the exact Store original and native/Read frames without generation', async () => {
  const f = fixture(); assert.deepEqual(f.events, []);
  const restored = await f.child.prepare(); assert.strictEqual(restored.borrow, f.nominal);
  assert.deepEqual(f.events, ['candidate', 'holding', 'commit', 'issue', 'bind Source']);
  assert.throws(() => restored.contentOwner.storageForContent({...f.nominal.binding}),
    /OriginalEffectContentUnavailable/u);
  let received;
  await restored.contentOwner.consumeContent(f.nominal.binding, value => {received = value;});
  assert.deepEqual(received, Buffer.from('abc'));
  assert.equal(await f.child.release(), true); assert.equal(f.child.status().pending, false);
  assert.throws(() => f.child.prepare(), /RecoveredContentAlreadyAttempted/u);
  assert.equal(f.events.filter(value => value === 'issue').length, 1);
  assert(f.roles.includes('candidate') && f.roles.includes('view') && f.roles.includes('issue'));
});

test('Source child retains the returned view after its same Read current cut refuses', async () => {
  const primary = new Error('Read current refusal'), f = fixture({cutFailure: primary});
  await assert.rejects(f.child.prepare(), error => error === primary);
  assert.equal(f.events.includes('bind Source'), true);
  assert.equal(f.events.includes('release view'), false);
  assert.equal(await f.child.release(), true);
  assert.equal(f.events.filter(value => value === 'release view').length, 1);
});

test('Source child close during Store await prevents issuance and waits for original cleanup', async () => {
  const f = fixture(); let entered, unblock;
  const arrival = new Promise(resolve => {entered = resolve;});
  const barrier = new Promise(resolve => {unblock = resolve;});
  f.inspect(() => {entered(); return barrier;});
  const outcome = f.child.prepare().then(() => ({ok: true}), error => ({error}));
  await arrival;
  assert.equal(await f.child.release(), false); assert.equal(f.child.status().pending, true);
  unblock(); assert.equal((await outcome).error.code, 'CapturedContentHoldingUnavailable');
  assert.equal(await f.child.release(), true); assert.equal(f.child.status().pending, false);
  assert.equal(f.events.includes('issue'), false); assert.equal(f.events.includes('bind Source'), false);
});

test('Source child retains failed reader close and never substitutes or reissues the reference', async () => {
  const f = fixture(), restored = await f.child.prepare(); let pending = true, retries = 0;
  const primary = Object.assign(new Error('reader close refused'), {cleanupHandle: {
    status: () => ({pending}), async retry() {retries++; return {pending};},
  }});
  f.consume(() => {throw primary;});
  await assert.rejects(restored.contentOwner.consumeContent(f.nominal.binding, () => {}), error => error === primary);
  assert.equal(await f.child.release(), false); assert.equal(f.events.includes('release view'), false);
  pending = false; assert.equal(await f.child.release(), true); assert.equal(retries, 1);
  assert.equal(f.events.filter(value => value === 'issue').length, 1);
});

test('Source binding uses one owned canonical spelling without inherited toJSON', async t => {
  const previous = Object.getOwnPropertyDescriptor(Object.prototype, 'toJSON');
  Object.defineProperty(Object.prototype, 'toJSON', {configurable: true,
    value() {throw new Error('Inherited serializer must not run');}});
  t.after(() => {
    if (previous === undefined) delete Object.prototype.toJSON;
    else Object.defineProperty(Object.prototype, 'toJSON', previous);
  });
  const f = fixture(); await f.child.prepare(); assert.equal(await f.child.release(), true);
});
