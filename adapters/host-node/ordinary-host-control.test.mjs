import assert from 'node:assert/strict';
import test from 'node:test';
import Module from 'node:module';
import {readFile} from 'node:fs/promises';
import {beginInitialControlInstallation, assertInitialControlInstallationCurrent,
  readInitialControlInstallationInput, readInitialControlInstallationAsset}
  from './node-initial-control-installation.mjs';

const originals = () => Object.freeze({host: {}, installation: {}, generation: {},
  supplier() {}, moduleLifetime: import.meta});

test('ordinary initialization snapshots documented trusted options and callback references before await', async () => {
  const pair = originals(); let calls = 0;
  const callback = () => 'caller';
  const installation = {directory: 'before', resolveSourceSecret: callback};
  const raw = {mode: 'local', get installation() {calls++; return installation;},
    consentRefs: ['original-consent'], extraUnknown: 17};
  const pending = beginInitialControlInstallation(pair, raw);
  installation.directory = 'after'; raw.mode = 'remote';
  raw.consentRefs.push('late');
  const scope = await pending;
  const input = readInitialControlInstallationInput(scope, pair);
  assert.equal(calls, 1); assert.equal(input.mode, 'local');
  assert.equal(input.installation.directory, 'before');
  assert.strictEqual(input.installation.resolveSourceSecret, callback);
  assert.equal(input.extraUnknown, 17); // Existing semantic owner still rejects it.
  assert.deepEqual(input.consentRefs, ['original-consent']);
  assertInitialControlInstallationCurrent(scope, pair);
  assert.equal((await scope.close()).pending, false);
});

test('ordinary independent Host control instances and reopen do not consume a process-wide right', async () => {
  for (let pass = 0; pass < 2; pass++) {
    const first = originals(), second = originals();
    const a = await beginInitialControlInstallation(first, {});
    const b = await beginInitialControlInstallation(second, {});
    assert.throws(() => assertInitialControlInstallationCurrent(a, second));
    assert.throws(() => readInitialControlInstallationInput({...a}, first));
    const record = {}; const duty = a.retainPreparation(record);
    assert.equal((await a.close()).pending, true);
    assertInitialControlInstallationCurrent(b, second);
    duty.releaseReferences(record);
    assert.equal((await a.close()).pending, false);
    assert.equal((await b.close()).pending, false);
  }
});

test('ordinary snapshot preserves absent original fields across later caller prototype changes', async () => {
  const prototype = {}, installationPrototype = {}, pair = originals();
  const installation = Object.assign(Object.create(installationPrototype), {directory: 'original'});
  const raw = Object.assign(Object.create(prototype), {mode: 'local', installation});
  const opening = beginInitialControlInstallation(pair, raw);
  let reads = 0;
  Object.defineProperty(prototype, 'profile', {get() {reads++; return 'mock';}});
  Object.defineProperty(installationPrototype, 'authorization', {get() {reads++; return {};}});
  const scope = await opening, value = readInitialControlInstallationInput(scope, pair);
  assert.equal(value.profile, undefined);
  assert.equal(value.installation.authorization, undefined);
  assert.equal(Object.hasOwn(value, 'profile'), false);
  assert.equal(reads, 0);
  assert.equal((await scope.close()).pending, false);
});

test('ordinary cleanup retains a real child receiver and pending state without requiring currentness', async () => {
  const pair = originals(), scope = await beginInitialControlInstallation(pair, {});
  const record = {}; let pending = true, calls = 0;
  const handle = {status() {assert.strictEqual(this, handle); return {pending};},
    async retry() {assert.strictEqual(this, handle); calls++;}};
  const duty = scope.retainPreparation(record, handle);
  duty.releaseReferences(record);
  const originalStatus = handle.status, originalRetry = handle.retry;
  handle.status = handle.retry = () => assert.fail('replacement cleanup');
  assert.equal((await scope.close()).pending, true);
  assert.equal(calls, 1);
  assert.throws(() => assertInitialControlInstallationCurrent(scope, pair));
  pending = false;
  assert.equal((await scope.close()).pending, false);
  assert.equal(calls, 2); assert.equal(typeof originalStatus, 'function');
  assert.equal(typeof originalRetry, 'function');
});

test('ordinary fixed assets remain bounded and initialization does not freeze process loader hooks', async () => {
  const before = ['registerHooks', 'register'].map(name => Object.getOwnPropertyDescriptor(Module, name));
  const pair = originals(), scope = await beginInitialControlInstallation(pair, undefined);
  const wire = readInitialControlInstallationAsset(scope, pair, 'spec/local-check-environment.json');
  assert.equal(typeof wire, 'string'); assert(wire.length > 0);
  assert.strictEqual(readInitialControlInstallationAsset(scope, pair, 'spec/local-check-environment.json'), wire);
  for (const path of ['/etc/passwd', '../package.json', 'spec/../../package.json', 'spec/\0bad']) {
    assert.throws(() => readInitialControlInstallationAsset(scope, pair, path));
  }
  assert.deepEqual(['registerHooks', 'register'].map(name => Object.getOwnPropertyDescriptor(Module, name)), before);
  assert.equal((await scope.close()).pending, false);
  assert.throws(() => readInitialControlInstallationAsset(scope, pair, 'spec/local-check-environment.json'));
});


test('ordinary Remote Host snapshots its top-level policy fields before initialization awaits', async () => {
  const environment = JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const capacity = {...environment.host_policy_profile.capacity};
  const original = capacity.max_effect_items;
  let reads = 0;
  Object.defineProperty(capacity, 'max_effect_items', {enumerable: true, configurable: true,
    get() {reads++; return original;}});
  const pair = originals();
  const opening = beginInitialControlInstallation(pair, {directory: 'remote', hostCapacityPolicy: capacity});
  assert.equal(reads, 1);
  Object.defineProperty(capacity, 'max_effect_items', {value: original + 1});
  const scope = await opening;
  const input = readInitialControlInstallationInput(scope, pair);
  assert.equal(input.hostCapacityPolicy.max_effect_items, original);
  assert.equal(Object.isFrozen(input.hostCapacityPolicy), true);
  assert.notEqual(input.hostCapacityPolicy, capacity);
  assert.equal(reads, 1);
  assert.equal((await scope.close()).pending, false);
});
