// An independent public SDK CLI client. No Host implementation, issuer or
// journal is imported; the surrounding installed fixture owns the service.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, writeFile} from 'node:fs/promises';
import {connect} from '@actql/node';

const [phase, endpoint] = process.argv.slice(2);
assert(process.argv.length === 4 && ['first', 'duplicate', 'conflict', 'lost', 'lookup'].includes(phase));
assert.equal(new URL(endpoint).protocol, 'https:');
// @actql/node connects through this installed require namespace. Getters must
// observe that SAME SDK's pending originals, never another ESM WeakMap.
const sdk = createRequire(import.meta.resolve('@actql/node'))('@actql/sdk');
const save = (name, value) => writeFile(name, JSON.stringify(value, null, 2) + '\n', {flag: 'wx', mode: 0o600});
const query = 'SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id';
const requestName = phase === 'lost' || phase === 'lookup' ? 'shared-named-lost' : 'shared-named-original';
const report = {phase, requestName, passed: false};
let client, primary, failed = false;
try {
  client = await connect({mode: 'remote', endpoint, token: (await readFile('token.txt', 'utf8')).trim(), durability: 'durable'});
  let execution;
  if (phase === 'lookup') {
    const target = JSON.parse(await readFile('named-lost-recovery-target.json', 'utf8'));
    const recovery = client.recoverRequest(target);
    const lookup = await recovery.lookup();
    await save('named-original-lookup.json', lookup);
    assert.equal(lookup.kind, 'ready');
    execution = await recovery.attach(lookup);
    assert.deepEqual(execution.ref, lookup.admission.ref);
    await save('named-recovered-run.json', execution.ref);
  } else {
    const pending = client.startSource(phase === 'conflict' ? 'SELECT 3 AS id' : query,
      {format: 'sql', requestId: requestName, attemptId: `shared-named-${phase}`});
    const input = sdk.getSubmissionInput(pending);
    assert(input); assert.equal(input.requestName, requestName);
    await save(`named-${phase}-original-input.json`, input);
    report.originalInputBeforeFirstAwait = true;
    if (phase === 'conflict' || phase === 'lost') {
      let failure;
      try {await pending;} catch (error) {failure = error;}
      assert(failure instanceof sdk.ClientError);
      report.primary = {name: failure.name, code: failure.code, message: failure.message};
      const attempt = sdk.getSubmissionAttempt(failure), outcome = sdk.getSubmissionOutcome(failure);
      report.actualAttempt = attempt; report.actualOutcome = outcome;
      assert.equal(outcome, undefined);
      if (phase === 'conflict') {
        assert.equal(failure.code, 'RequestConflict');
        assert.equal(attempt.kind, 'conflict'); assert.equal(attempt.reason, 'intent');
        assert.equal(attempt.requestName, requestName);
        assert.deepEqual(attempt.attemptRef, input.attemptRef);
      } else {
        assert.equal(failure.code, 'SubmissionUnknown');
        assert.equal(attempt, undefined);
        assert.equal(failure.requestName, requestName);
        // This is the SAME SDK error's captured public lookup target, not a
        // name-to-ID guess or a claim that its sent candidate was accepted.
        await save('named-lost-recovery-target.json', client.recoverRequest(failure).target);
      }
    } else {
      execution = await pending;
      await save(`named-${phase}-run.json`, execution.ref);
      const outcome = sdk.getSubmissionOutcome(execution); assert.equal(outcome.kind, 'ready');
      await save(`named-${phase}-outcome.json`, outcome);
      if (phase === 'duplicate') {
        assert.deepEqual(execution.ref, JSON.parse(await readFile('named-first-run.json', 'utf8')));
        const original = JSON.parse(await readFile('named-first-outcome.json', 'utf8'));
        assert.deepEqual(outcome.submissionRef, original.submissionRef);
        assert.notDeepEqual(input.submissionRef, original.submissionRef,
          'A new connection candidate cannot replace the original named binding');
      }
    }
  }
  if (execution !== undefined) {
    const state = await execution.wait();
    assert.equal(state.status, 'succeeded'); assert.equal(state.result_available, true);
    const rows = await execution.result('main').all();
    assert.deepEqual(rows, [{id: 1}, {id: 2}]);
    report.status = state.status; report.independentWholeRows = rows;
  }
  report.passed = true;
} catch (error) {
  primary = error; failed = true;
  report.failure = {name: error?.name, code: error?.code, message: error?.message};
} finally {
  if (client !== undefined) {
    try {await client.close(); report.clientCloseReturned = true;}
    catch (cleanup) {
      report.clientCloseReturned = false;
      report.cleanupFailure = {name: cleanup?.name, code: cleanup?.code, message: cleanup?.message};
      primary = failed ? new AggregateError([primary, cleanup], 'Named client operation and close failed') : cleanup;
      failed = true;
      report.passed = false;
    }
  }
  await save(`named-${phase}-report.json`, report);
}
if (failed) throw primary;
console.log(JSON.stringify({stage: 'named-client-complete', phase, clientCloseReturned: report.clientCloseReturned}));
