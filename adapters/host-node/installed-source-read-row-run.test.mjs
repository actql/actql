import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});
// Exact existing RowRun consumer with explicit Core ports, not an imported
// child issuer or actual same-Run capacity/physical-cleanup positive.
function fixture() {
  const originalRead = {}, ledger = {}, acquisition = {}, run = {}, calls = [];
  const moon = {
    clientProgramInstalledSourceReadCheckLedger(read, expected) {
      calls.push('check'); assert.equal(read, originalRead); assert.equal(expected, ledger);
      return ok(undefined);
    },
    clientProgramInstalledSourceReadStartRows(read, selected, nonce, stopped, transfer, execution) {
      calls.push('start'); assert.equal(read, originalRead); assert.equal(selected, acquisition);
      assert.equal(nonce, 'original'); assert.equal(stopped({}), false);
      assert.equal(transfer, 100n); assert.equal(execution, 200n); return ok(run);
    },
    clientProgramRowSourceCloseAccounted(value) {calls.push('close'); assert.equal(value, run); return ok(undefined);},
    clientProgramRowSourceCaptureCleanup(value) {calls.push('cleanup'); assert.equal(value, run); return ok(true);},
    clientProgramInstalledSourceReadRetire(read) {calls.push('retire'); assert.equal(read, originalRead); return ok(undefined);},
    clientProgramRowSourceStart() {assert.fail('NoUnaccountedFallback');},
    clientProgramRowSourceStartAccounted() {assert.fail('NoDifferentStart');},
  };
  const options = {moon, acquisition, nonce: 'original', ledger, originalRead,
    capacity: {transferBytes: 100n, executionBytes: 200n}};
  return {moon, calls, options, run};
}

test('original Source read checks the same Run Ledger before starting and retires only after capture cleanup', () => {
  const f = fixture();
  const session = startInstalledRowRun(f.options);
  assert.deepEqual(f.calls, ['check', 'start']);
  f.moon.clientProgramRowSourceCaptureCleanup = () => {f.calls.push('pending'); return ok(false);};
  assert.throws(() => session.close(), {code: 'InstalledSourceCleanupPending'});
  assert.deepEqual(f.calls, ['check', 'start', 'close', 'pending']);
  f.moon.clientProgramRowSourceCaptureCleanup = () => {f.calls.push('cleanup'); return ok(true);};
  session.close(); session.close();
  assert.deepEqual(f.calls, ['check', 'start', 'close', 'pending', 'close', 'cleanup', 'retire']);
});

test('foreign or stale original Source Ledger refuses before every RowRun constructor', () => {
  const f = fixture();
  f.moon.clientProgramInstalledSourceReadCheckLedger = () => {
    f.calls.push('refused'); return {$tag: 0, _0: 'ForeignOriginal'};
  };
  assert.throws(() => startInstalledRowRun(f.options), {code: 'MoonBitHostFailure'});
  assert.deepEqual(f.calls, ['refused']);
});

test('Source-only scope cannot replace a missing Run Ledger or rescue an unavailable typed consumer', () => {
  const f = fixture();
  assert.throws(() => startInstalledRowRun({...f.options, ledger: undefined}),
    {code: 'InstalledSourceRunLedgerRequired'});
  assert.throws(() => startInstalledRowRun({...f.options, keyed: true}),
    {code: 'InstalledSourceRunLedgerRequired'});
  delete f.moon.clientProgramInstalledSourceReadCheckLedger;
  assert.throws(() => startInstalledRowRun(f.options), {code: 'InstalledSourceReadUnavailable'});
  assert.deepEqual(f.calls, []);
});

test('planned provider rows start through the same original Source read and Ledger', () => {
  const f = fixture(), provider = {};
  f.moon.clientProgramInstalledSourceReadStartProviderRows = (read, acquisition, capacity,
    nonce, stopped, transfer, execution) => {
    f.calls.push('provider');
    assert.equal(read, f.options.originalRead); assert.equal(acquisition, f.options.acquisition);
    assert.equal(capacity, provider); assert.equal(nonce, 'original'); assert.equal(stopped({}), false);
    assert.equal(transfer, 100n); assert.equal(execution, 200n); return ok(f.run);
  };
  f.moon.clientProgramRowSourceBorrowResponses = () => assert.fail('no reader prepared');
  f.moon.clientProgramRowSourceBindResponseCleanup = () => assert.fail('no reader prepared');
  f.moon.clientProgramRowSourceRetireResponseWorkspace = () => assert.fail('no reader prepared');
  f.moon.clientProgramRowSourceStartProviderAccounted = () => assert.fail('no independent provider parent');
  const session = startInstalledRowRun({...f.options, capacity: {...f.options.capacity, provider}});
  assert.deepEqual(f.calls, ['check', 'provider']);
  session.close();
  assert.deepEqual(f.calls, ['check', 'provider', 'close', 'cleanup', 'retire']);
  f.moon.clientProgramInstalledSourceReadCheckLedger = () => ({$tag: 0, _0: 'same foreign Ledger'});
  assert.throws(() => startInstalledRowRun({...f.options, capacity: {...f.options.capacity, provider}}),
    {code: 'MoonBitHostFailure'});
  assert.deepEqual(f.calls, ['check', 'provider', 'close', 'cleanup', 'retire']);
});
