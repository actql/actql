import assert from 'node:assert/strict';
import test from 'node:test';
import {installModelProviders} from './installed-model.mjs';

function fixture() {
  let installations = 0, sends = 0, lookups = 0;
  const reconcileResponse = () => {lookups++; return undefined;};
  return {moon: {clientProgramInstallModelProvider() {installations++; return {}; }},
    entry: {providerId: 'models/fixture', invoke() {sends++;},
      validatePrompt: () => true, reconcileResponse},
    counts: () => ({installations, sends, lookups})};
}

test('registered original-response lookup is retained without invoking or reading a call', () => {
  const {moon, entry, counts} = fixture();
  const selected = installModelProviders(moon, () => [entry]).get('models/fixture');
  assert.equal(selected.reconcileResponse, entry.reconcileResponse);
  entry.reconcileResponse = () => assert.fail('mutated provider registration');
  assert.equal(selected.reconcileResponse(), undefined);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 1});
});

test('invalid original-response hook is rejected before installing the provider', () => {
  for (const reconcileResponse of [null, false, {}, 'reconcile']) {
    const {moon, entry, counts} = fixture();
    assert.throws(() => installModelProviders(moon, () => [{...entry, reconcileResponse}]),
      {message: 'InvalidInstalledModelProviderRegistration'});
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('provider without an original-response hook acquires no reconciliation capability', () => {
  const {moon, entry, counts} = fixture();
  delete entry.reconcileResponse;
  assert.equal(installModelProviders(moon, () => [entry]).get('models/fixture').reconcileResponse, undefined);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});
