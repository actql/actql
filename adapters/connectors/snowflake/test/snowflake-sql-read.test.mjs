
import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {gzipSync} from 'node:zlib';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {snowflakeFixture, pending, resultBody, decimal38} from './snowflake-read.fixture.mjs';

test('actual TLS POST, same-handle GET and gzip partition feed the original Host capture', async t => {
  const f = await snowflakeFixture(t);
  const bodies = [pending('slash/?雪%'), resultBody({handle: 'slash/?雪%', parts: [1, 1],
    rows: [['a1', decimal38, 'down']]}), Buffer.from('{"data":[["a2","0",null]]}')];
  const wire = [bodies[0], gzipSync(bodies[1]), gzipSync(bodies[2])];
  f.state.onRequest = () => {
    const n = f.state.requests.length - 1;
    return {status: n === 0 ? 202 : 200, body: wire[n],
      headers: n === 0 ? {} : {'content-encoding': 'gzip'}};
  };
  const result = await f.read();
  assert.deepEqual(f.state.requests.map(r => [r.method, r.path]), [
    ['POST', `/api/v2/statements?requestId=${f.frame.requestId}`],
    ['GET', '/api/v2/statements/slash%2F%3F%E9%9B%AA%25'],
    ['GET', '/api/v2/statements/slash%2F%3F%E9%9B%AA%25?partition=1']]);
  assert.ok(f.state.requests.every(r => r.headers.authorization === 'Bearer snowflake-fixture-secret'));
  assert.ok(f.state.requests.every(r => r.headers['user-agent'] === 'actql-snowflake/0.1'));
  assert.equal(f.state.requests[0].headers['x-snowflake-authorization-token-type'], 'OAUTH');
  assert.deepEqual(JSON.parse(f.state.requests[0].body), {parameters: {multi_statement_count: '1'},
    role: 'READER', statement: 'SELECT "ACCOUNT_ID","ACTIVE_USERS","TREND" FROM "PRODUCT"."USAGE"."USAGE_30D"',
    timeout: 60, warehouse: 'ANALYTICS'});
  assert.equal(result.statementHandle, 'slash/?雪%');
  assert.equal(result.pages, 2); assert.equal(result.rows, 2n); assert.equal(result.exchanges, 3);
  assert.equal(result.wireBytes, BigInt(wire.reduce((n, b) => n + b.byteLength, 0)));
  assert.equal(result.decodedBytes, BigInt(bodies.reduce((n, b) => n + b.byteLength, 0)));
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.wireBytes, 'wire is charged once, never inflated bytes');
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n,
    'transport retirement is not original Host reservation retirement');
  assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded', 'succeeded', 'succeeded']);
  const rows = f.row.captureRows();
  assert.equal(rows.length, 2);
  assert.ok(rows[0].includes(decimal38), 'Common must retain the exact 38 digit coefficient');
  assert.ok(rows[1].includes('null'));
  assert.equal(JSON.stringify(result, (_, v) => typeof v === 'bigint' ? String(v) : v)
    .includes('snowflake-fixture-secret'), false);
});

test('complete first response needs no GET and does not convert transport success into Host capture', async t => {
  const f = await snowflakeFixture(t);
  const result = await f.read();
  assert.equal(f.state.requests.length, 1);
  assert.equal(result.pages, 1); assert.equal(result.rows, 2n);
  f.row.assertNoCapture();
  assert.equal(f.row.captureRows().length, 2);
});

test('current Account denial refuses before credential resolution or provider request', async t => {
  const f = await snowflakeFixture(t, {accountOutcome: 'deny'});
  await assert.rejects(f.read(), {code: 'ExecutionAuthorizationDenied', outcome: 'not_started'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n); f.row.assertNoCapture();
});

test('Account replacement during the resolver await is fenced before physical send', async t => {
  const f = await snowflakeFixture(t);
  f.state.resolve = () => f.writeAccount('deny');
  await assert.rejects(f.read(), {code: 'AuthorizationCurrentAccountChanged'});
  assert.equal(f.state.resolutions, 1); assert.equal(f.state.requests.length, 0);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n); f.row.assertNoCapture();
});

test('Account replacement across an actual reply retains and charges bytes without Source acceptance', async t => {
  const f = await snowflakeFixture(t);
  f.state.onRequest = async () => { await f.writeAccount('deny'); return {body: resultBody()}; };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'AuthorizationCurrentAccountChanged');
    assert.equal(error.observation.body.toString(), resultBody().toString());
    assert.equal(Object.keys(error).includes('observation'), false);
    return true;
  });
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(resultBody().byteLength));
  assert.equal(f.journal.recover()[0].outcome, 'succeeded');
  f.row.assertNoCapture();
});

test('foreign original scope is rejected before secret, claim or network I/O', async t => {
  const f = await snowflakeFixture(t);
  await assert.rejects(f.read({authorizationFor: async () => ({grant: f.grant,
    scope: {...f.scope, dispatchRequestCid: `sha256:${'e'.repeat(64)}`}, useId: 'foreign'})}),
  {code: 'ForeignSnowflakeReadAuthorization'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  assert.deepEqual(f.journal.recover(), []); assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n);
});

test('revoked original credential cannot send or create a replacement use', async t => {
  const f = await snowflakeFixture(t);
  f.state.resolve = () => f.journal.revoke(f.control.identity(f.grant));
  await assert.rejects(f.read());
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n); f.row.assertNoCapture();
});

test('lost POST reply keeps original request and Unknown without resending on the same run', async t => {
  const f = await snowflakeFixture(t);
  f.state.onRequest = (_, request) => { request.socket.destroy(); };
  await assert.rejects(f.read(), error => {
    assert.ok(error instanceof AcquisitionOpenError);
    assert.equal(error.code, 'ECONNRESET');
    assert.equal(error.outcome, 'unknown');
    assert.equal(error.originalStatement.requestId, f.frame.requestId);
    assert.equal(error.originalStatement.statementHandle, undefined);
    return true;
  });
  assert.equal(f.journal.recover()[0].outcome, 'unknown');
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.resolutions, 1);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n, 'a lost complete body is not fabricated as observed bytes');
  f.row.assertNoCapture();
});

test('dot and dot-dot observed handles retain charge and identity but issue no normalized GET', async t => {
  for (const handle of ['.', '..']) {
    const f = await snowflakeFixture(t);
    f.state.onRequest = () => ({status: 202, body: pending(handle)});
    await assert.rejects(f.read(), error => {
      assert.equal(error.code, 'MoonBitHostFailure');
      assert.equal(error.originalStatement.statementHandle, handle);
      assert.equal(error.outcome, 'unknown'); return true;
    });
    assert.equal(f.state.requests.length, 1);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(pending(handle).byteLength));
    assert.equal(f.journal.recover()[0].outcome, 'succeeded');
    f.row.assertNoCapture();
  }
});

test('HTTP refusal is an original charged observation, never a row or commit ACK', async t => {
  const f = await snowflakeFixture(t);
  f.state.onRequest = () => ({status: 403, body: '{"message":"denied"}'});
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.observation.statusCode, 403);
    assert.equal(error.outcome, 'stopped'); return true;
  });
  assert.equal(f.state.requests.length, 1);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(Buffer.byteLength('{"message":"denied"}')));
  assert.equal(f.journal.recover()[0].outcome, 'failed'); f.row.assertNoCapture();
});

test('accepted statement followed by a status refusal keeps its original Unknown without resending', async t => {
  for (const status of [403, 404, 422]) {
    const f = await snowflakeFixture(t);
    const handle = `accepted-original-${status}`;
    const accepted = pending(handle);
    const refused = Buffer.from('{"message":"status unavailable"}');
    f.state.onRequest = () => f.state.requests.length === 1
      ? {status: 202, body: accepted} : {status, body: refused};
    await assert.rejects(f.read(), error => {
      assert.ok(error instanceof AcquisitionOpenError);
      assert.equal(error.code, 'MoonBitHostFailure');
      assert.equal(error.observation.statusCode, status);
      assert.equal(error.outcome, 'unknown');
      assert.deepEqual(error.originalStatement, {
        requestId: f.frame.requestId, statementHandle: handle});
      return true;
    });
    assert.deepEqual(f.state.requests.map(r => [r.method, r.path]), [
      ['POST', `/api/v2/statements?requestId=${f.frame.requestId}`],
      ['GET', `/api/v2/statements/${handle}`]]);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(accepted.byteLength + refused.byteLength));
    assert.deepEqual(f.journal.recover().map(r => r.outcome), ['succeeded', 'failed']);
    f.row.assertNoCapture();
    await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
    assert.equal(f.state.requests.length, 2, 'the original POST and GET are not resent');
    assert.equal(f.state.resolutions, 2);
  }
});

test('gzip decoder refusal retains the exact charged wire and never accepts partial rows', async t => {
  for (const body of [Buffer.from('not-gzip'), gzipSync(Buffer.alloc(8192, 97))]) {
    const f = await snowflakeFixture(t);
    f.state.onRequest = () => ({body, headers: {'content-encoding': 'gzip'}});
    await assert.rejects(f.read(), error => {
      assert.deepEqual(error.observation.body, body); return true;
    });
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.byteLength));
    assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
  }
});

test('foreign result schema is refused by the actual original Common Contract', async t => {
  const f = await snowflakeFixture(t);
  const body = resultBody({precision: 37});
  f.state.onRequest = () => ({body});
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.byteLength));
  assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
});

test('abort during a pending original exchange closes its physical binding without retry or capture', async t => {
  const f = await snowflakeFixture(t);
  const controller = new AbortController();
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.onRequest = () => { entered(); };
  const result = f.read({signal: controller.signal});
  await started;
  controller.abort();
  await assert.rejects(result, error => error.outcome === 'unknown');
  assert.equal(f.state.requests.length, 1);
  assert.equal(f.journal.recover()[0].outcome, 'unknown'); f.row.assertNoCapture();
});

test('parent close during secret resolution retains the same Root until physical stop is confirmed', async t => {
  const f = await snowflakeFixture(t);
  let resume, entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.state.resolve = () => new Promise(resolve => { resume = resolve; entered(); });
  const result = f.read();
  await started;
  assert.throws(f.row.close, {code: 'MoonBitHostFailure'});
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  resume();
  await assert.rejects(result);
  f.row.close(); f.row.close();
  assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 1);
  assert.equal(f.journal.recover()[0].outcome, 'failed');
});

test('in-flight response processing keeps the original Root after socket stop and parent close', async t => {
  const f = await snowflakeFixture(t);
  let closeFailure, heldAfterClose;
  f.state.beforeCurrent = async calls => {
    if (calls !== 4) return;
    try { f.row.close(); } catch (error) { closeFailure = error; }
    heldAfterClose = ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes;
  };
  await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
  assert.equal(closeFailure?.code, 'MoonBitHostFailure',
    'socket stop must not retire workspace still used by this driver');
  assert.ok(heldAfterClose > 0n);
  f.row.close();
  assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
});

test('in-flight decoder failure preserves its primary cause when original refusal recording is stale', async t => {
  const f = await snowflakeFixture(t);
  f.state.onRequest = () => ({body: 'not-gzip', headers: {'content-encoding': 'gzip'}});
  f.state.beforeCurrent = async calls => {
    if (calls === 4) {
      try { f.row.close(); } catch { /* The original parent cleanup is pending. */ }
    }
  };
  await assert.rejects(f.read(), error => {
    assert.equal(error.code, 'Z_DATA_ERROR');
    assert.equal(error.cause.code, 'Z_DATA_ERROR');
    assert.equal(error.recordingFailure.code, 'MoonBitHostFailure');
    assert.equal(error.observation.body.toString(), 'not-gzip');
    return true;
  });
  f.row.close();
  assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(f.state.requests.length, 1); f.row.assertNoCapture();
});

// The generic Host counters below use real Common preparations, ledgers and
// cleanup. Their Site driver deliberately performs no I/O, and its stop Bool
// is an explicit physical-law double, separate from the actual TLS cases.
async function genericHost(f, readPages, prepareAcquisition) {
  const o = f.row.originals;
  let grants = 0;
  const adapter = await createInstalledRowSource({moon: f.moon,
    declaration: o.declaration, declared: o.declared, environmentWire: o.environment.wire,
    connectorId: 'snowflake', connectorRegistration: 'snowflake',
    connectorRevision: 'snowflake/0.1', bindingCid: `sha256:${'a'.repeat(64)}`,
    site: {connection: 'snowflake:fixture', issueReadGrant() {grants++; return {};}, close() {}},
    authorization: {authorize: async () => {await f.options.verifyRead(); return {action: 'dispatch'};},
      context: {contextCid: `sha256:${'d'.repeat(64)}`}, accountConfiguration: '{}'},
    physicalTarget: (resource, fields) => ({resource, fields: [...fields], generation: 1}),
    readOperation: 'snowflake:sql:read', readPages, prepareAcquisition,
    limits: {maxPages: 2, maxPageBytes: 4096, maxPageRows: 2, maxCaptureRows: 2}});
  return {adapter, grants: () => grants,
    preparation: {preparedProgram: o.program, registry: o.registry,
      values: o.values, fragment: o.fragment, ordered: o.ordered}};
}

test('installed pure preparer cannot replace the original requirement with an equal foreign acquisition', async t => {
  const f = await snowflakeFixture(t);
  let reads = 0;
  const h = await genericHost(f, async () => {reads++;}, () => f.row.acquisition);
  await assert.rejects(h.adapter.prepare(h.preparation), {code: 'MoonBitHostFailure'});
  assert.equal(h.grants(), 0); assert.equal(reads, 0);
  assert.equal(f.state.requests.length, 0); assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, 0n);
});

for (const method of ['open', 'openCapture']) test(
  `installed ${method} retains the original outer Core recovery after an inner Unknown`, async t => {
    const f = await snowflakeFixture(t), o = f.row.originals;
    let stopped = false, stopChecks = 0, reads = 0, expectedAcquisition, inner;
    const h = await genericHost(f, async ({rowRun, verifyRead}) => {
      reads++;
      assert.equal(Object.isFrozen(rowRun), true);
      assert.equal(rowRun.acquisition, expectedAcquisition);
      assert.match(rowRun.requestId, /^[0-9a-f-]{36}$/u);
      assert.match(rowRun.runInvocationCid, /^sha256:[0-9a-f]{64}$/u);
      await verifyRead();
      const borrow = checked(f.moon.clientProgramRowSourceBorrowResponses(rowRun.run, rowRun.acquisition));
      checked(f.moon.clientProgramRowSourceBindResponseCleanup(borrow, () => {stopChecks++; return stopped;}));
      inner = new AcquisitionOpenError(new Error('original-exchange-unknown'), 'unknown');
      throw inner;
    }, ({declaration, requirement, queryContract, evidenceContract}) => {
      const prepared = checked(f.moon.clientProgramSnowflakePrepareRead(o.description,
        declaration, requirement, queryContract, evidenceContract, o.descriptionLimits, o.declarationLimits));
      expectedAcquisition = f.moon.clientProgramSnowflakeReadAcquisition(prepared);
      return expectedAcquisition;
    });
    const ledger = checked(f.moon.clientProgramAcquisitionLedger(1, 1, 8192n, 100000000n, 100000000n, 0));
    let failure;
    await assert.rejects(h.adapter[method]({...h.preparation, ledger}), error => {
      failure = error;
      assert.equal(error.cause, inner);
      assert.equal(error.code, 'original-exchange-unknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.recovery.cleanupPending(), true);
      return true;
    });
    assert.equal(reads, 1); assert.equal(h.grants(), 1);
    assert.ok(ledgerUsageSnapshot(f.moon.clientProgramMultiCapturedLedgerUsage(ledger)).reservedExecutionBytes > 0n);
    stopped = true;
    assert.equal(await failure.recovery.cleanup(), true);
    const observed = stopChecks;
    assert.equal(await failure.recovery.cleanup(), true);
    assert.equal(stopChecks, observed);
    assert.deepEqual(ledgerUsageFieldsFor(f.moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    assert.equal(reads, 1); assert.equal(h.grants(), 1); assert.equal(f.state.requests.length, 0);
  });
