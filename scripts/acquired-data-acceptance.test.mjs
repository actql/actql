import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredDataSuccesses, acquiredGraphSourceSuccesses, acquiredDataRefusals}
  from './fixtures/acquired-data-source-input.mjs';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';

// Test the acceptance app's detection of bad output, not the Frontend or Host.
// Actual execution remains the installed Local/HTTP harness's obligation.
async function exerciseReader(item, {rows, columns, sessions = 1,
  readAcquires = false, refusalIo = false} = {}) {
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
    aql: async (_text, {requestId}) => {
      if (!item.results) {
        if (refusalIo) counters.sourceIo++;
        throw Object.assign(new Error('typed input rejection'),
          {code: 'ClientProgramInvalidInput'});
      }
      if (!requests.has(requestId)) {
        requests.set(requestId, execution);
        counters.acceptedRuns++;
        counters.sourceIo++;
        counters.sourceReadSessions += sessions;
      }
      return execution;
    },
    attach: async () => execution,
    lookupRequest: async id => requests.has(id)
      ? {ref: execution.ref} : {kind: 'not_found'},
    close() {},
  };
  await exercisePublicQueryInput(async () => client, {mode: 'local'}, {
    requestPrefix: 'harness-control', observe: () => ({...counters}),
    successes: item.results ? [item] : [], refusals: item.results ? [] : [item],
  });
}

test('acquired DATA empty Result still checks nullable type and column order', async () => {
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

test('acquired DATA expectations detect lost duplicates and NULL values', async () => {
  const copied = acquiredDataSuccesses[0];
  await assert.rejects(exerciseReader(copied, {rows: [
    {amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3},
  ]}), {code: 'ERR_ASSERTION'});
  await assert.rejects(exerciseReader(copied, {rows: [
    {amount: 0, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3},
  ]}), {code: 'ERR_ASSERTION'});
});

test('acquired DATA detects repeated capture and I/O during Result reads', async () => {
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

test('a late DATA rejection must still have zero provider I/O and Run admission', async () => {
  await exerciseReader(acquiredDataRefusals[0]);
  await assert.rejects(exerciseReader(acquiredDataRefusals[0], {refusalIo: true}),
    /rejected source must not accept a Run or perform source I\/O/u);
});
