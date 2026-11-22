import assert from 'node:assert/strict';
import test from 'node:test';
import {openInstalledEffectLedger} from './installed-effect-ledger-open.mjs';

type LedgerConstruction = NonNullable<Parameters<typeof openInstalledEffectLedger>[5]>;

test('installed Ledger open retains the original request, receiver bounds and control frame', () => {
  const root = '/original/ledger', identity = {}, ledger = {}, authority = 'sha256:' + 'a'.repeat(64);
  let opened = 0, selected = 0, active = false;
  const moon = {
    clientRequestAuthorityScopeCid(value: typeof identity) {assert.strictEqual(value, identity); return authority;},
    clientRequestCallerId(value: typeof identity) {assert.strictEqual(value, identity); return 'original';},
  };
  const work: LedgerConstruction = () => assert.fail('full generic used for supported Ledger-open frame');
  work.ledgerOpen = (actual, receiver, method, args) => {
    assert.equal(actual, root); assert.equal(receiver, undefined);
    selected++; active = true;
    try {return Reflect.apply(method, receiver, args);} finally {active = false;}
  };
  const result = openInstalledEffectLedger(moon, root, identity, 4096, 8192, work, options => {
    assert.equal(active, true);
    assert.equal(options.root, root);
    assert.equal(options.authorityScopeCid, authority);
    assert.equal(options.callerRequestId, 'original');
    assert.equal(options.maxEntryBytes, 4096);
    assert.equal(options.maxReadResponseBytes, 8192);
    assert.equal(Object.hasOwn(options, 'maxResponseBytes'), false);
    assert.strictEqual(options.controlConstruction, work);
    opened++; return ledger;
  });
  assert.strictEqual(result, ledger);
  assert.equal(opened, 1); assert.equal(selected, 1);
});

test('installed Ledger open keeps legacy construction and its primary failure', () => {
  const primary = Object.assign(new Error('original'), {cleanupPending: true});
  const moon = {clientRequestAuthorityScopeCid: () => '', clientRequestCallerId: () => ''};
  const root = '/original/ledger', identity = {};
  let calls = 0;
  const open = () => {calls++; throw primary;};
  assert.throws(() => openInstalledEffectLedger(moon, root, identity, 4096, 8192, undefined, open),
    cause => cause === primary);
  const work: LedgerConstruction = (receiver, method, args) => Reflect.apply(method, receiver, args);
  assert.throws(() => openInstalledEffectLedger(moon, root, identity, 4096, 8192, work, open),
    cause => cause === primary);
  assert.equal(calls, 2);
});
