import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {snowflakeFixture, pending} from './snowflake-read.fixture.mjs';

test('undefined preflight rejection remains a failure before credentials or SQL API I/O', async t => {
  const f = await snowflakeFixture(t);
  await assert.rejects(f.read({verifyRead: async () => { throw undefined; }}), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.outcome, 'not_started');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined); return true;
  });
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []);
});

test('undefined rejection after original POST202 preserves charge and Unknown without GET', async t => {
  const f = await snowflakeFixture(t);
  const body = pending('original-pending');
  f.state.onRequest = () => ({status: 202, body});
  f.state.beforeCurrent = async () => { if (f.state.requests.length) throw undefined; };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.outcome, 'unknown');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    assert.equal(error.originalStatement.requestId, f.frame.requestId);
    assert.deepEqual(error.observation.body, body); return true;
  });
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.requests[0].method, 'POST');
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length));
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded']);
  f.row.assertNoCapture();
});

test('undefined secret resolver rejection cannot fulfill the original acquisition or resend', async t => {
  const f = await snowflakeFixture(t);
  f.state.resolve = async () => { throw undefined; };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    assert.equal(error.outcome, 'unknown'); return true;
  });
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['failed']);
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  f.row.assertNoCapture();
});

test('other JavaScript rejection reasons and Error identity remain unchanged', async t => {
  for (const reason of [null, false, 0, '', Object.freeze({original: true}),
    Object.freeze(new Error('OriginalCurrentRefusal'))]) {
    const f = await snowflakeFixture(t);
    await assert.rejects(f.read({verifyRead: async () => { throw reason; }}), error => {
      assert.equal(error.cause, reason); assert.equal(error.outcome, 'not_started'); return true;
    });
    assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
    assert.deepEqual(f.journal.recover(), []);
  }
});

test('undefined refusal-recording fault remains distinct from the real gzip failure', async t => {
  const f = await snowflakeFixture(t);
  // This is an explicit Core-port fault; all RowRun values remain original.
  const moon = {...f.moon, clientProgramSnowflakeRecordDecoderRefusal() { throw undefined; }};
  f.state.onRequest = () => ({body: 'not-gzip', headers: {'content-encoding': 'gzip'}});
  await assert.rejects(f.read({moon}), error => {
    assert.equal(error.code, 'Z_DATA_ERROR');
    assert.equal(error.cause.code, 'Z_DATA_ERROR');
    assert.ok(Object.hasOwn(error, 'recordingFailure'));
    assert.equal(error.recordingFailure, undefined);
    assert.equal(Object.keys(error).includes('recordingFailure'), false); return true;
  });
  assert.equal(f.state.requests.length, 1);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(Buffer.byteLength('not-gzip')));
  f.row.assertNoCapture();
});

test('an injected cleanup refusal cannot replace an original undefined rejection', async t => {
  for (const secondary of [undefined, Object.freeze(new Error('OriginalCleanupPending'))]) {
    const f = await snowflakeFixture(t);
    const moon = {...f.moon, clientProgramSnowflakeRetireReadBorrow() { throw secondary; }};
    f.state.onRequest = () => ({status: 202, body: pending('original-pending')});
    f.state.beforeCurrent = async () => { if (f.state.requests.length) throw undefined; };
    await assert.rejects(f.read({moon}), error => {
      assert.equal(error.code, 'AcquisitionFailed');
      assert.ok(Object.hasOwn(error, 'cause'));
      assert.equal(error.cause, undefined);
      assert.ok(Object.hasOwn(error, 'cleanupFailure'));
      assert.equal(error.cleanupFailure, secondary);
      assert.equal(error.outcome, 'unknown'); return true;
    });
    assert.equal(f.state.requests.length, 1);
    assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
    // The real registered observer, not the injected port, owns this ACK.
    f.row.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
});

test('successful undefined current callbacks remain valid and finish original capture', async t => {
  const f = await snowflakeFixture(t);
  f.state.beforeCurrent = async () => {};
  const result = await f.read();
  assert.equal(result.rows, 2n); assert.equal(f.state.requests.length, 1);
  assert.equal(f.row.captureRows().length, 2);
});
