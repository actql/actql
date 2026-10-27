import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {bigqueryHttpsFixture} from './bigquery-https.fixture.mjs';

test('a rejected undefined preflight is a real failure rather than fulfilled undefined', async t => {
  const f = await bigqueryHttpsFixture(t);
  await assert.rejects(f.read({verifyRead: async () => { throw undefined; }}), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.outcome, 'not_started');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    return true;
  });
  assert.equal(f.state.requests.length, 0);
  assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []);
});

test('undefined rejection after the original POST stops without GET and retains the original reason', async t => {
  const f = await bigqueryHttpsFixture(t);
  try {
    await assert.rejects(f.read({withOriginalJob: async (_, send) => {
      await send(); throw undefined;
    }}), error => {
      assert.equal(error.code, 'AcquisitionFailed');
      assert.equal(error.outcome, 'stopped');
      assert.ok(Object.hasOwn(error, 'cause'));
      assert.equal(error.cause, undefined);
      assert.equal(error.originalJob.jobId, f.row.requestId);
      return true;
    });
    assert.equal(f.state.requests.length, 1);
    assert.equal(f.state.requests[0].method, 'POST');
    assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded']);
    f.row.assertNoCapture();
  } finally { t.diagnostic(`Original thrown-value requests: ${f.state.requests.map(r => r.method).join(',')}`); }
});

test('undefined rejection before original send is preserved without replacing it with missing handoff', async t => {
  const f = await bigqueryHttpsFixture(t);
  await assert.rejects(f.read({withOriginalJob: async () => { throw undefined; }}), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.outcome, 'unknown');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    assert.equal(error.originalJob.jobId, f.row.requestId);
    return true;
  });
  assert.equal(f.state.requests.length, 0); assert.deepEqual(f.journal.recover(), []);
});

test('all other JavaScript rejection reasons keep their exact identity', async t => {
  for (const reason of [null, false, 0, '', Object.freeze({original: true})]) {
    const f = await bigqueryHttpsFixture(t);
    await assert.rejects(f.read({withOriginalJob: async (_, send) => {
      await send(); throw reason;
    }}), error => {
      assert.equal(error.cause, reason);
      assert.equal(error.outcome, 'stopped'); return true;
    });
    assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
  }
});

test('an original undefined rejection and a later lost-send failure stay separate', async t => {
  const f = await bigqueryHttpsFixture(t);
  let entered, release;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.onRequest = (_, request) => { release = () => request.socket.destroy(); entered(); };
  let finished = false;
  const result = f.read({withOriginalJob: (_, send) => {
    void send(); throw undefined;
  }}).finally(() => { finished = true; });
  void result.catch(() => {});
  await started;
  assert.equal(finished, false);
  release();
  await assert.rejects(result, error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.equal(error.cause, undefined);
    assert.equal(error.sendFailure.code, 'ECONNRESET');
    assert.equal(Object.keys(error).includes('sendFailure'), false);
    assert.equal(error.outcome, 'unknown'); return true;
  });
  assert.equal(f.state.requests.length, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['unknown']);
  f.row.assertNoCapture();
});

test('ordinary successful undefined callback return is distinct from a rejection', async t => {
  const f = await bigqueryHttpsFixture(t);
  const result = await f.read({withOriginalJob: async (_, send) => { await send(); }});
  assert.equal(result.rows, 2n);
  assert.equal(f.state.requests.length, 2);
  assert.equal(f.state.requests[0].method, 'POST');
  assert.equal(f.state.requests[1].method, 'GET');
  assert.equal(f.state.requests[0].body.includes('bigquery-fixture-secret'), false);
  assert.equal(f.row.captureRows().length, 2);
});

test('undefined credential resolution failure is not a successful physical acquisition', async t => {
  const f = await bigqueryHttpsFixture(t);
  f.state.resolve = async () => { throw undefined; };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AcquisitionFailed');
    assert.ok(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    assert.equal(error.outcome, 'unknown'); return true;
  });
  assert.equal(f.state.resolutions, 1); assert.equal(f.state.requests.length, 0);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['failed']);
  f.row.assertNoCapture();
});

test('an injected cleanup-port refusal cannot replace an original undefined rejection', async t => {
  for (const secondary of [undefined, Object.freeze(new Error('OriginalCleanupPending'))]) {
    const f = await bigqueryHttpsFixture(t);
    // Explicit boundary fault, not a claim of a physical Common cleanup fault.
    // The original RowRun still owns its actual registered cleanup observer.
    const moon = {...f.moon, clientProgramBigQueryRetireReadBorrow() { throw secondary; }};
    await assert.rejects(f.read({moon, withOriginalJob: async (_, send) => {
      await send(); throw undefined;
    }}), error => {
      assert.equal(error.code, 'AcquisitionFailed');
      assert.ok(Object.hasOwn(error, 'cause'));
      assert.equal(error.cause, undefined);
      assert.ok(Object.hasOwn(error, 'cleanupFailure'));
      assert.equal(error.cleanupFailure, secondary);
      assert.equal(Object.keys(error).includes('cleanupFailure'), false);
      assert.equal(error.outcome, 'unknown'); return true;
    });
    assert.equal(f.state.requests.length, 1);
    assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n, 'the original Host retains responsibility');
    f.row.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
});
