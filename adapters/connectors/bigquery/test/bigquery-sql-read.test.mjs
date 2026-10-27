import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {gzipSync} from 'node:zlib';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {bigqueryHttpsFixture, jobBody, rowsBody, exactRows} from './bigquery-https.fixture.mjs';
import {statement} from './bigquery-read.fixture.mjs';

test('original TLS POST, status and gzip pages feed the exact Common Signed64 capture', async t => {
  const f = await bigqueryHttpsFixture(t);
  const bodies = [jobBody(f.row.requestId, {state: 'RUNNING'}), jobBody(f.row.requestId),
    rowsBody(f.row.requestId, {rows: exactRows.slice(0, 1), token: 'slash/?雪%'}),
    rowsBody(f.row.requestId, {rows: exactRows.slice(1)})];
  const wire = bodies.map((body, i) => i < 2 ? body : gzipSync(body));
  f.state.onRequest = () => {
    const i = f.state.requests.length - 1;
    return {body: wire[i], headers: i < 2 ? {} : {'content-encoding': 'gzip'}};
  };
  const result = await f.read();
  const prefix = `/bigquery/v2/projects/acme-project`;
  assert.deepEqual(f.state.requests.map(r => [r.method, r.path]), [
    ['POST', `${prefix}/jobs`], ['GET', `${prefix}/jobs/${f.row.requestId}?location=EU`],
    ['GET', `${prefix}/queries/${f.row.requestId}?location=EU&maxResults=2&timeoutMs=0`],
    ['GET', `${prefix}/queries/${f.row.requestId}?location=EU&maxResults=2&timeoutMs=0&pageToken=slash%2F%3F%E9%9B%AA%25`]]);
  assert.deepEqual(JSON.parse(f.state.requests[0].body), {
    configuration: {query: {maximumBytesBilled: '1000000', query: statement, useLegacySql: false}},
    jobReference: {jobId: f.row.requestId, location: 'EU', projectId: 'acme-project'}});
  assert.ok(f.state.requests.every(r => r.headers.authorization === 'Bearer bigquery-fixture-secret'));
  assert.equal(f.state.originals.length, 1);
  assert.equal(JSON.parse(f.state.originals[0].wire).body, f.state.requests[0].body);
  assert.equal(result.rows, 2n); assert.equal(result.pages, 2); assert.equal(result.exchanges, 4);
  assert.equal(result.wireBytes, BigInt(wire.reduce((n, b) => n + b.length, 0)));
  assert.equal(result.decodedBytes, BigInt(bodies.reduce((n, b) => n + b.length, 0)));
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.wireBytes);
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n,
    'transport retirement does not retire the original Host holding');
  assert.deepEqual(f.journal.recover().map(r => r.outcome), Array(4).fill('succeeded'));
  f.row.assertNoCapture();
  const captured = f.row.captureRows();
  assert.equal(captured.length, 2);
  assert.ok(captured[0].includes('-9223372036854775808'));
  assert.ok(captured[1].includes('9223372036854775807'));
  assert.equal(JSON.stringify(result, (_, v) => typeof v === 'bigint' ? String(v) : v)
    .includes('bigquery-fixture-secret'), false);
});

test('a missing original-operation supplier refuses before credential or physical I/O', async t => {
  const f = await bigqueryHttpsFixture(t);
  await assert.rejects(f.read({withOriginalJob: undefined}), {code: 'BigQueryOriginalOperationUnavailable'});
  assert.equal(f.state.resolutions, 0); assert.equal(f.state.requests.length, 0);
  assert.deepEqual(f.journal.recover(), []); assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n);
});

test('unresolved original-operation handoff cannot dispatch later or mint a replacement Job', async t => {
  const f = await bigqueryHttpsFixture(t);
  let later;
  await assert.rejects(f.read({withOriginalJob: async (_, send) => { later = send; }}), error => {
    assert.equal(error.code, 'BigQueryOriginalJobUnresolved');
    assert.equal(error.outcome, 'unknown');
    assert.equal(error.originalJob.jobId, f.row.requestId); return true;
  });
  assert.throws(later, {code: 'BigQueryOriginalJobAlreadyAttempted'});
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []); f.row.assertNoCapture();
});

test('the original callback cannot invoke the same POST twice', async t => {
  const f = await bigqueryHttpsFixture(t);
  const result = await f.read({withOriginalJob: async (_, send) => {
    const first = send();
    assert.throws(send, {code: 'BigQueryOriginalJobAlreadyAttempted'});
    return first;
  }});
  assert.equal(result.rows, 2n);
  assert.equal(f.state.requests.filter(r => r.method === 'POST').length, 1);
  assert.equal(f.state.requests.length, 2);
});

test('an unawaited original send remains owned until its actual response completes', async t => {
  const f = await bigqueryHttpsFixture(t);
  let release, entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.onRequest = entry => entry.method === 'POST'
    ? new Promise(resolve => { release = () => resolve({body: jobBody(f.row.requestId)}); entered(); })
    : {body: rowsBody(f.row.requestId)};
  let finished = false;
  const result = f.read({withOriginalJob: (_, send) => { void send(); }})
    .finally(() => { finished = true; });
  await started;
  assert.equal(finished, false);
  assert.throws(f.row.close, {code: 'MoonBitHostFailure'});
  release();
  await assert.rejects(result);
  assert.equal(f.state.requests.length, 1, 'parent closing never authorizes a second request');
  f.row.close();
  assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('callback failure after starting a send waits for its original response without GET or resend', async t => {
  const f = await bigqueryHttpsFixture(t);
  let release, entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.onRequest = () => new Promise(resolve => {
    release = () => resolve({body: jobBody(f.row.requestId)}); entered();
  });
  let finished = false;
  const result = f.read({withOriginalJob: (_, send) => {
    void send(); throw Object.assign(new Error('OriginalCommitReplyLost'), {code: 'OriginalCommitReplyLost'});
  }}).finally(() => { finished = true; });
  await started;
  assert.equal(finished, false);
  release();
  await assert.rejects(result, {code: 'OriginalCommitReplyLost', outcome: 'stopped'});
  assert.equal(f.state.requests.length, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded']);
  f.row.assertNoCapture();
});

test('current Account denial precedes original-operation handoff, secret and request', async t => {
  const f = await bigqueryHttpsFixture(t, {accountOutcome: 'deny'});
  await assert.rejects(f.read(), {code: 'ExecutionAuthorizationDenied', outcome: 'not_started'});
  assert.equal(f.state.originals.length, 0); assert.equal(f.state.resolutions, 0);
  assert.equal(f.state.requests.length, 0); assert.deepEqual(f.journal.recover(), []);
});

test('Account replacement during secret resolution prevents the physical POST', async t => {
  const f = await bigqueryHttpsFixture(t);
  f.state.resolve = () => f.writeAccount('deny');
  await assert.rejects(f.read(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['failed']);
  f.row.assertNoCapture();
});

test('a foreign dispatch scope refuses before secret or request', async t => {
  const f = await bigqueryHttpsFixture(t);
  await assert.rejects(f.read({authorizationFor: async () => ({grant: f.grant,
    scope: {...f.scope, dispatchRequestCid: `sha256:${'e'.repeat(64)}`}, useId: 'foreign'})}),
  {code: 'ForeignBigQueryReadAuthorization'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []);
});

test('Account replacement across a real reply charges original bytes without accepting a Source', async t => {
  const f = await bigqueryHttpsFixture(t);
  const body = jobBody(f.row.requestId);
  f.state.onRequest = async () => { await f.writeAccount('deny'); return {body}; };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.deepEqual(error.observation.body, body); return true;
  });
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length));
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded']);
  assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
});

test('lost original POST reply retains the same Job and Unknown without resend', async t => {
  const f = await bigqueryHttpsFixture(t);
  f.state.onRequest = (_, request) => { request.socket.destroy(); };
  await assert.rejects(f.read(), error => {
    assert.ok(error instanceof AcquisitionOpenError);
    assert.equal(error.code, 'ECONNRESET'); assert.equal(error.outcome, 'unknown');
    assert.deepEqual(error.originalJob, {project: 'acme-project', jobId: f.row.requestId, location: 'EU'});
    return true;
  });
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.resolutions, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['unknown']);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n); f.row.assertNoCapture();
});

test('accepted RUNNING Job followed by refused GET remains Unknown and cannot resend POST', async t => {
  for (const status of [403, 404]) {
    const f = await bigqueryHttpsFixture(t);
    const body = jobBody(f.row.requestId, {state: 'RUNNING'});
    const refusal = Buffer.from('{"error":{"message":"unavailable"}}');
    f.state.onRequest = () => f.state.requests.length === 1 ? {body} : {status, body: refusal};
    await assert.rejects(f.read(), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.outcome, 'unknown');
      assert.equal(error.originalJob.jobId, f.row.requestId);
      assert.equal(error.observation.statusCode, status); return true;
    });
    await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
    assert.equal(f.state.requests.length, 2);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length + refusal.length));
    assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded', 'failed']);
    f.row.assertNoCapture();
  }
});

test('gzip failure charges the wire before decoder allocation and never accepts partial rows', async t => {
  for (const body of [Buffer.from('not-gzip'), gzipSync(Buffer.alloc(8192, 97))]) {
    const f = await bigqueryHttpsFixture(t);
    f.state.onRequest = () => ({body, headers: {'content-encoding': 'gzip'}});
    await assert.rejects(f.read(), error => {
      assert.deepEqual(error.observation.body, body); return true;
    });
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length));
    assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
  }
});

test('foreign Job identity is charged and refused by the actual original Common owner', async t => {
  const f = await bigqueryHttpsFixture(t);
  const body = jobBody(f.row.requestId, {foreign: true});
  f.state.onRequest = () => ({body});
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure', outcome: 'unknown'});
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length));
  assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
});

test('aborting the actual original exchange retains Unknown and closes its local binding', async t => {
  const f = await bigqueryHttpsFixture(t);
  const controller = new AbortController();
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.onRequest = () => { entered(); };
  const result = f.read({signal: controller.signal});
  await started;
  controller.abort();
  await assert.rejects(result, error => error.outcome === 'unknown');
  assert.equal(f.state.requests.length, 1);
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['unknown']);
  f.row.assertNoCapture();
});
