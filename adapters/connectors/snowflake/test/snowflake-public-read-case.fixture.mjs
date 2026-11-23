// Original public read oracle shared unchanged by Source and normal-package callers.
import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {decimal38, pending, resultBody} from './snowflake-response.fixture.mjs';

const source = 'SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, TREND AS trend ' +
  'FROM snowflake.usage_30d |> RESULT usage';
const expected = [{account_id: 'a1', active_users: decimal38, trend: 'down'},
  {account_id: 'a2', active_users: '0', trend: null}];
const expectedColumns = [
  {name: 'account_id', contract: {type: 'string', nullable: false}},
  {name: 'active_users', contract: {type: 'decimal', nullable: false, precision: 38, scale: 0}},
  {name: 'trend', contract: {type: 'string', nullable: true}}];

export async function assertSnowflakePublicRead(t, f, entrance, {filtered = false} = {}) {
  const sql = filtered ? source.replace(' |> RESULT', " WHERE ACCOUNT_ID = 'a1' |> RESULT") : source;
  const rows = filtered ? expected.slice(0, 1) : expected;
  assert.equal(f.state.resolutions, 0); assert.equal(f.state.requests.length, 0);
  const report = await f.client.check(sql, {kind: 'text', scope: 'bound_input', format: 'sql'});
  assert.equal(report.report?.verdict, 'verified', inspect(report, {depth: 6}));
  assert.deepEqual(report.report.runnable, {verdict: 'yes', reasons: []});
  assert.equal(f.state.requests.length, 0, 'check cannot contact Snowflake');
  f.state.onRequest = entry => {
    f.assertOriginalCredential?.(entry);
    return f.state.requests.length === 1
      ? {status: 202, body: pending('public-source-original')}
      : {body: resultBody({handle: 'public-source-original'})};
  };
  const submissionRef = f.client.newSubmission({nonce: `snowflake-public-${entrance.toLowerCase()}`});
  const execution = await f.client.startSource(sql, {format: 'sql', submissionRef});
  const state = await execution.wait({signal: AbortSignal.timeout(20000)});
  if (state.status !== 'succeeded') t.diagnostic(inspect({
    requests: f.state.requests.map(({method, path}) => ({method, path})),
    observations: f.observations}, {depth: 8, maxStringLength: 3000}));
  assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
  const result = execution.result('usage');
  assert.deepEqual((await result.describe()).columns, expectedColumns);
  assert.deepEqual(await result.all(), rows);
  assert.deepEqual(await result.all(), rows);
  const attached = await f.client.attach(execution.ref);
  assert.deepEqual(await attached.result('usage').all(), rows);
  const sameSubmission = await f.client.startSource(sql, {format: 'sql', submissionRef});
  assert.deepEqual(sameSubmission.ref, execution.ref);
  assert.deepEqual(await sameSubmission.result('usage').all(), rows);
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET'],
    'read, attach and same-submission lookup never replay the Provider');
  assert.equal(f.state.requests[1].path, '/api/v2/statements/public-source-original');
  assert.equal(f.state.resolutions, 2);
  await f.client.close();
  const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
  assert.equal(cleanup.length, 1, 'same dispatch cleanup completes exactly once');
  const usage = cleanup[0][1].resourceUsage;
  // Holding issuance is cumulative; physical bytes and live reservations retire.
  assert(BigInt(usage.attempts) > 0n, 'the original dispatch and Source attempted work');
  for (const field of ['heldBytes', 'reservedTransferBytes',
    'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
    assert.equal(usage[field], '0', `original ledger cleanup: ${field}`);
  }
  assert(BigInt(usage.transferredBytes) > 0n, 'actual Provider input was charged');
  t.diagnostic(JSON.stringify({entrance, filtered, firstClose: true, providerRequests: f.state.requests.length,
    repeatedRead: true, attachedOriginal: true, sameSubmissionLookup: true, usage}));
}
