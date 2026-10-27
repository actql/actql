import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {gzipSync} from 'node:zlib';
import {snowflakeFixture, metadataBody, pending} from './snowflake-read.fixture.mjs';

function temporalMetadata() {
  const body = JSON.parse(metadataBody());
  body.data[1][6] = 'DATE'; body.data[1].splice(7, 3, null, null, null);
  body.data[2][6] = 'TIMESTAMP_LTZ'; body.data[2].splice(7, 3, null, null, null);
  return Buffer.from(JSON.stringify(body));
}
function temporalResult({parts = [2], rows = [
  ['a1', '2024-02-29', '1969-12-31T23:59:59.999999999Z'],
  ['a2', '2000-02-29', '1970-01-01T00:00:00.123400000Z']], scale = 9} = {}) {
  return Buffer.from(JSON.stringify({statementHandle: 'original-temporal', sqlState: '00000',
    resultSetMetaData: {format: 'jsonv2', numRows: parts.reduce((n, v) => n + v, 0),
      rowType: [{name: 'ACCOUNT_ID', type: 'TEXT', nullable: false},
        {name: 'ACTIVE_USERS', type: 'DATE', nullable: false},
        {name: 'TREND', type: 'TIMESTAMP_LTZ', scale, nullable: true}],
      partitionInfo: parts.map(rowCount => ({rowCount}))}, data: rows}));
}
const parameters = Object.freeze({date_output_format: 'YYYY-MM-DD',
  multi_statement_count: '1', timestamp_ltz_output_format: 'YYYY-MM-DD"T"HH24:MI:SS.FF9"Z"',
  timezone: 'UTC'});

test('actual TLS selects original DATE and UTC LTZ formats and captures exact fractions across pages', async t => {
  const f = await snowflakeFixture(t, {descriptionBody: temporalMetadata()});
  const bodies = [pending('original-temporal'), temporalResult({parts: [1, 1],
    rows: [['a1', '2024-02-29', '1969-12-31T23:59:59.999999999Z']]}),
    Buffer.from('{"data":[["a2","2000-02-29","1970-01-01T00:00:00.123400000Z"]]}')];
  const wire = [bodies[0], gzipSync(bodies[1]), gzipSync(bodies[2])];
  f.state.onRequest = () => {
    const index = f.state.requests.length - 1;
    return {status: index === 0 ? 202 : 200, body: wire[index],
      headers: index === 0 ? {} : {'content-encoding': 'gzip'}};
  };
  const result = await f.read();
  assert.deepEqual(JSON.parse(f.state.requests[0].body).parameters, parameters);
  assert.deepEqual(f.state.requests.map(value => [value.method, value.path]), [
    ['POST', `/api/v2/statements?requestId=${f.frame.requestId}`],
    ['GET', '/api/v2/statements/original-temporal'],
    ['GET', '/api/v2/statements/original-temporal?partition=1']]);
  assert.equal(result.rows, 2n); assert.equal(result.pages, 2);
  assert.equal(result.wireBytes, BigInt(wire.reduce((n, b) => n + b.length, 0)));
  assert.equal(result.decodedBytes, BigInt(bodies.reduce((n, b) => n + b.length, 0)));
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, result.wireBytes);
  assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
  assert.deepEqual(f.row.captureRows().map(JSON.parse), [
    {ACCOUNT_ID: 'a1', ACTIVE_USERS: '2024-02-29', TREND: '1969-12-31T23:59:59.999999999Z'},
    {ACCOUNT_ID: 'a2', ACTIVE_USERS: '2000-02-29', TREND: '1970-01-01T00:00:00.1234Z'}]);
  assert.deepEqual(f.journal.recover().map(value => value.outcome), ['succeeded', 'succeeded', 'succeeded']);
  f.row.close(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('selected temporal SQL NULL remains distinct from text and retains canonical milliseconds', async t => {
  const f = await snowflakeFixture(t, {descriptionBody: temporalMetadata()});
  const body = temporalResult({scale: 3, rows: [
    ['a1', '0001-01-01', null], ['a2', '9999-12-31', '1970-01-01T00:00:00.123000000Z']]});
  f.state.onRequest = () => ({body});
  await f.read();
  assert.deepEqual(JSON.parse(f.state.requests[0].body).parameters, parameters);
  assert.deepEqual(f.row.captureRows().map(JSON.parse), [
    {ACCOUNT_ID: 'a1', ACTIVE_USERS: '0001-01-01', TREND: null},
    {ACCOUNT_ID: 'a2', ACTIVE_USERS: '9999-12-31', TREND: '1970-01-01T00:00:00.123Z'}]);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(body.length));
});

test('actual temporal format and scale contradictions stay charged Unknown without capture or resend', async t => {
  for (const rows of [
    [['a1', '18262', '1970-01-01T00:00:00.123000000Z'], ['a2', '2024-02-29', null]],
    [['a1', '2024-02-29', '1611871777123456789'], ['a2', '2024-02-29', null]],
    [['a1', '2024-02-29', '1970-01-01T00:00:00.123000001Z'], ['a2', '2024-02-29', null]],
  ]) {
    const f = await snowflakeFixture(t, {descriptionBody: temporalMetadata()});
    const first = pending('original-temporal'), body = temporalResult({scale: 3, rows});
    f.state.onRequest = () => f.state.requests.length === 1 ? {status: 202, body: first} : {body};
    await assert.rejects(f.read(), error => {
      assert.equal(error.outcome, 'unknown'); assert.equal(error.code, 'MoonBitHostFailure');
      assert.equal(error.originalStatement.requestId, f.frame.requestId);
      assert.equal(error.originalStatement.statementHandle, 'original-temporal');
      assert.deepEqual(error.observation.body, body); return true;
    });
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes, BigInt(first.length + body.length));
    assert.equal(f.state.requests.length, 2); f.row.assertNoCapture();
    const resolutions = f.state.resolutions;
    await assert.rejects(f.read(), {code: 'MoonBitHostFailure'});
    assert.equal(f.state.requests.length, 2); assert.equal(f.state.resolutions, resolutions);
    assert.ok(ledgerUsageSnapshot(f.row.usage()).reservedRetentionBytes > 0n && ledgerUsageSnapshot(f.row.usage()).reservedExecutionBytes > 0n);
    f.row.close(); assert.deepEqual(ledgerUsageFieldsFor(f.row.usage(), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
});
