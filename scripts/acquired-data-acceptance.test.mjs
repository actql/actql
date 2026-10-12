import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredDataSuccesses, acquiredGraphSourceSuccesses, acquiredDataRefusals}
  from './fixtures/acquired-data-source-input.mjs';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';

// Test the acceptance app's detection of bad output, not the Frontend or Host.
// Actual execution remains the installed Local/HTTP harness's obligation.
async function exerciseReader(item, {rows, columns, sessions = 1,
  readAcquires = false, refusalIo = false, refusalCode = 'ClientProgramInvalidInput',
  lookupKind} = {}) {
  const counters = {acceptedRuns: 0, sourceIo: 0, sourceReadSessions: 0};
  const requests = new Map();
  const result = Object.values(item.results ?? {})[0];
  const execution = {ref: {fixture: item.name},
    wait: async () => ({status: 'succeeded'}),
    result: () => ({
      all: async () => {
        if (readAcquires) counters.sourceIo++;
        return rows ?? result.rows;
      },
      describe: async () => ({columns: columns ?? result.columns}),
    }),
  };
  const client = {
    newSubmission: ({nonce}) => ({epoch: 'harness-epoch', nonce}),
    startSource: async (_text, {submissionRef, requestId}) => {
      assert.equal(requestId, undefined, 'never use an epoch-less submission');
      const key = JSON.stringify(submissionRef);
      if (!item.results) {
        if (refusalIo) counters.sourceIo++;
        const outcome = {kind: 'not_accepted', submissionRef,
          problem: {code: refusalCode, classification: 'invalid_input'}};
        requests.set(key, outcome);
        throw Object.assign(new Error('typed input rejection'),
          {code: 'SubmissionNotAccepted', outcome});
      }
      if (!requests.has(key)) {
        requests.set(key, {kind: 'ready', submissionRef, admission: {ref: execution.ref}});
        counters.acceptedRuns++;
        counters.sourceIo++;
        counters.sourceReadSessions += sessions;
      }
      return execution;
    },
    attach: async () => execution,
    lookupSubmission: async ref => {
      const outcome = requests.get(JSON.stringify(ref));
      return lookupKind === undefined ? outcome : {...outcome, kind: lookupKind};
    },
    close() {},
  };
  await exercisePublicQueryInput(async () => client, {mode: 'local'}, {
    requestPrefix: 'harness-control', observe: () => ({...counters}),
    successes: item.results ? [item] : [], refusals: item.results ? [] : [item],
  });
}

test('acquired WITH empty Result still checks nullable type and column order', async () => {
  const empty = acquiredDataSuccesses.find(item => item.sourceRows?.length === 0);
  await exerciseReader(empty);
  await assert.rejects(exerciseReader(empty, {columns: [
    {name: 'amount', contract: {type: 'number', nullable: false}},
    {name: 'id', contract: {type: 'number', nullable: false}},
  ]}), /retained column order and contracts/u);
  const wrongOrder = Object.values(empty.results)[0].columns.toReversed();
  await assert.rejects(exerciseReader(empty, {columns: wrongOrder}),
    /retained column order and contracts/u);
});

test('acquired WITH expectations detect lost duplicates and NULL values', async () => {
  const copied = acquiredDataSuccesses[0];
  await assert.rejects(exerciseReader(copied, {rows: [
    {amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3},
  ]}), {code: 'ERR_ASSERTION'});
  await assert.rejects(exerciseReader(copied, {rows: [
    {amount: 0, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3},
  ]}), {code: 'ERR_ASSERTION'});
});

test('acquired WITH detects repeated capture and I/O during Result reads', async () => {
  const shared = acquiredDataSuccesses[1];
  await assert.rejects(exerciseReader(shared, {sessions: 2}),
    /one acquisition session per authored source/u);
  await assert.rejects(exerciseReader(shared, {readAcquires: true}),
    /reading, attaching and resending must not accept or acquire again/u);
});

test('acquired Graph TRAIL expectations preserve parallel-edge multiplicity', async () => {
  const trail = acquiredGraphSourceSuccesses[2];
  await assert.rejects(exerciseReader(trail, {rows: [{depth: 2}]}),
    {code: 'ERR_ASSERTION'});
});

test('a late WITH rejection must still have zero provider I/O and Run admission', async () => {
  await exerciseReader(acquiredDataRefusals[0]);
  await assert.rejects(exerciseReader(acquiredDataRefusals[0], {refusalIo: true}),
    /rejected source must not accept a Run or perform source I\/O/u);
});

test('public source acceptance checks epoch-bound ready and typed refusal outcomes', async () => {
  await assert.rejects(exerciseReader(acquiredDataSuccesses[0], {lookupKind: 'unresolvable'}),
    {code: 'ERR_ASSERTION'});
  await assert.rejects(exerciseReader(acquiredDataRefusals[0], {refusalCode: 'UnexpectedFailure'}),
    /UnexpectedFailure/u);
  await assert.rejects(exerciseReader(acquiredDataRefusals[0], {lookupKind: 'unresolvable'}),
    {code: 'ERR_ASSERTION'});
});
