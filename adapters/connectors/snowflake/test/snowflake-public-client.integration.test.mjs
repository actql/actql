// Source-qualified public callers, not an installed npm/Local Python release.
import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {publicSnowflakeFixture} from './public-snowflake.fixture.mjs';
import {decimal38, pending, resultBody} from './snowflake-read.fixture.mjs';

const source = 'SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, TREND AS trend ' +
  'FROM snowflake.usage_30d |> RESULT usage';
const expected = [{account_id: 'a1', active_users: decimal38, trend: 'down'},
  {account_id: 'a2', active_users: '0', trend: null}];
const expectedColumns = [
  {name: 'account_id', contract: {type: 'string', nullable: false}},
  {name: 'active_users', contract: {type: 'decimal', nullable: false, precision: 38, scale: 0}},
  {name: 'trend', contract: {type: 'string', nullable: true}}];

for (const entrance of ['Local', 'HTTPS']) test(
  `public ${entrance} Snowflake SQL preserves decimal38 and NULL through Named Result and attach`, async t => {
    const f = await publicSnowflakeFixture(t, entrance);
    assert.equal(f.state.resolutions, 0); assert.equal(f.state.requests.length, 0);
    const report = await f.client.check(source, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(report.report?.verdict, 'verified', inspect(report, {depth: 6}));
    assert.deepEqual(report.report.runnable, {verdict: 'yes', reasons: []});
    assert.equal(f.state.requests.length, 0, 'check cannot contact Snowflake');
    f.state.onRequest = () => f.state.requests.length === 1
      ? {status: 202, body: pending('public-source-original')}
      : {body: resultBody({handle: 'public-source-original'})};
    const submissionRef = f.client.newSubmission({nonce: `snowflake-public-${entrance.toLowerCase()}`});
    const execution = await f.client.startSource(source, {format: 'sql', submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(20000)});
    if (state.status !== 'succeeded') t.diagnostic(inspect({
      requests: f.state.requests.map(({method, path}) => ({method, path})),
      observations: f.observations}, {depth: 8, maxStringLength: 3000}));
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
    const result = execution.result('usage');
    assert.deepEqual((await result.describe()).columns, expectedColumns);
    assert.deepEqual(await result.all(), expected);
    assert.deepEqual(await result.all(), expected);
    const attached = await f.client.attach(execution.ref);
    assert.deepEqual(await attached.result('usage').all(), expected);
    const sameSubmission = await f.client.startSource(source, {format: 'sql', submissionRef});
    assert.deepEqual(sameSubmission.ref, execution.ref);
    assert.deepEqual(await sameSubmission.result('usage').all(), expected);
    assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET'],
      'read, attach and same-submission lookup never replay the Provider');
    assert.equal(f.state.requests[1].path, '/api/v2/statements/public-source-original');
    await f.client.close();
    const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
    assert.equal(cleanup.length, 1, 'same dispatch cleanup completes exactly once');
    const usage = cleanup[0][1].resourceUsage;
    // Holding issuance is cumulative; physical bytes and live reservations retire.
    assert.equal(usage.holdings, '2', 'capture and Compute issuance is never refunded');
    for (const field of ['heldBytes', 'reservedTransferBytes',
      'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
      assert.equal(usage[field], '0', `original ledger cleanup: ${field}`);
    }
    assert(BigInt(usage.transferredBytes) > 0n, 'actual Provider input was charged');
    t.diagnostic(JSON.stringify({entrance, providerRequests: f.state.requests.length,
      repeatedRead: true, attachedOriginal: true, sameSubmissionLookup: true, usage}));
  });
