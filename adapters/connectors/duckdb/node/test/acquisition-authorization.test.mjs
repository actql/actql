import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runBroadAcquisition } from '../broad-acquisition.mjs';
import { runNativeAcquisition } from '../native-acquisition.mjs';
import {
  FIXTURE_CONTEXT,
  accountEntry,
  fixtureAuthorization,
  sqliteDeferral,
} from '../../../../host-node/authorization-fixture.mjs';

const limits = Object.freeze({ maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 });
const subjectCid = `sha256:${'5'.repeat(64)}`;
const source = Object.freeze({ connection: 'warehouse', resource: 'main.records' });

// Provider spies: `sessions` counts real DuckDB sessions opened (the session
// accounting hook fires before the instance is created); `commands` counts
// SQL statements handed to the provider, including metadata/catalog SQL.
function spies() {
  const counts = { sessions: 0, commands: 0, settled: 0 };
  const accounting = {
    started() { counts.sessions++; },
    chargeTransfer() {},
    settled() { counts.settled++; },
  };
  const port = {
    metadataSql: () => { counts.commands++; return "SELECT table_type FROM information_schema.tables WHERE table_name = 'records'"; },
    metadataParameters: () => [],
    acceptMetadata() {},
    finishMetadata() {},
    scanSql: () => { counts.commands++; return 'SELECT id FROM records ORDER BY id'; },
    beginReceipt() {},
    acceptChunk() {},
    finishReceipt: () => Object.freeze({ role: 'scan' }),
    abort() {},
  };
  return { counts, accounting, port };
}

async function database(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-acquisition-authorization-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'source.duckdb');
  const instance = await DuckDBInstance.create(path);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records (id DOUBLE)');
    await connection.run('INSERT INTO records VALUES (1), (2)');
  } finally { connection.closeSync(); instance.closeSync(); }
  return { directory, path };
}

async function acquire(path, authorization) {
  const spy = spies();
  const grant = await authorizeLocalDatabase(path, { authorization, ...source, subjectCid });
  let error;
  try { await runBroadAcquisition(grant, spy.port, limits, undefined, spy.accounting); }
  catch (reason) { error = reason; }
  return { ...spy.counts, error };
}

const readEntries = outcome => [accountEntry('warehouse-read', outcome, {
  connection: 'warehouse', operation: 'read',
})];

test('acquisition allow opens the provider session with no Host call or Checkpoint', async t => {
  const { path } = await database(t);
  let hostCalls = 0;
  const gate = await fixtureAuthorization(readEntries('allow'),
    { decide: () => { hostCalls++; }, answeringAuthorities: ['reviewer'] });
  const result = await acquire(path, gate);
  assert.equal(result.error, undefined);
  assert.equal(result.sessions, 1);
  assert.equal(result.commands, 2);
  assert.equal(hostCalls, 0);
  assert.equal(gate.counters().hostDecisionCalls, 0);
  assert.equal(gate.counters().checkpointsPersisted, 0);
  assert.equal(gate.counters().protectedDispatches, 1);
});

test('acquisition deny and missing configuration open no provider session', async t => {
  const { path } = await database(t);
  let hostCalls = 0;
  const decide = () => { hostCalls++; return { decision: 'permit' }; };
  const explicit = await fixtureAuthorization(readEntries('deny'),
    { decide, answeringAuthorities: ['reviewer'] });
  const unmatched = await fixtureAuthorization([accountEntry('crm-read', 'allow', {
    connection: 'crm',
  })], { decide, answeringAuthorities: ['reviewer'] });
  for (const [gate, reason] of [[explicit, 'explicit'], [unmatched, 'no_match'],
    [undefined, 'configuration_missing']]) {
    const result = await acquire(path, gate);
    assert.equal(result.error?.code, 'ExecutionAuthorizationDenied');
    assert.equal(result.error.authorization.reason, reason);
    assert.equal(result.sessions, 0);
    assert.equal(result.commands, 0);
  }
  assert.equal(hostCalls, 0);
  // The native acquisition path shares the same boundary.
  const spy = spies();
  const grant = await authorizeLocalDatabase(path, { authorization: explicit, ...source });
  await assert.rejects(runNativeAcquisition(grant, {
    ...spy.port,
    validationSql: () => { spy.counts.commands++; return 'SELECT 1'; },
    nativeSql: () => { spy.counts.commands++; return 'SELECT 1'; },
    nativeParameters: () => [],
  }, limits, undefined, spy.accounting), { code: 'ExecutionAuthorizationDenied' });
  assert.equal(spy.counts.sessions, 0);
  assert.equal(spy.counts.commands, 0);
});

test('acquisition delegate: permit reads, reject and failures do not', async t => {
  const { path } = await database(t);
  const permit = view => ({ decision: 'permit', subject: view.subject, authority: 'reviewer' });
  const reject = view => ({ decision: 'reject', subject: view.subject, authority: 'reviewer' });
  const cases = [
    ['permit', permit, 1, undefined],
    ['reject', reject, 0, 'ExecutionAuthorizationDenied'],
    ['throw', () => { throw new Error('DecisionServiceDown'); }, 0, 'ExecutionAuthorizationDecisionFailed'],
    ['timeout', () => new Promise(() => {}), 0, 'ExecutionAuthorizationDecisionFailed'],
    ['malformed', () => ({ decision: 'yes' }), 0, 'ExecutionAuthorizationDecisionFailed'],
  ];
  for (const [label, decide, sessions, code] of cases) {
    const gate = await fixtureAuthorization(readEntries('delegate'),
      { decide, answeringAuthorities: ['reviewer'], decisionTimeoutMs: 20 });
    const result = await acquire(path, gate);
    assert.equal(result.sessions, sessions, label);
    assert.equal(result.commands, sessions * 2, label);
    assert.equal(result.error?.code, code, label);
    assert.equal(gate.counters().hostDecisionCalls, 1, label);
    assert.equal(gate.counters().hostRejections, label === 'reject' ? 1 : 0, label);
    assert.equal(gate.counters().decisionFailures,
      ['throw', 'timeout', 'malformed'].includes(label) ? 1 : 0, label);
  }
});

test('acquisition defer persists a Checkpoint first, or stops as unsupported', async t => {
  const { directory, path } = await database(t);
  const deferral = await sqliteDeferral(join(directory, 'journal'));
  t.after(() => deferral.journal.close());
  const defer = view => ({ decision: 'defer', subject: view.subject });
  const durable = await fixtureAuthorization(readEntries('delegate'),
    { decide: defer, answeringAuthorities: ['reviewer'], deferral });
  const waiting = await acquire(path, durable);
  assert.equal(waiting.error?.code, 'ExecutionAuthorizationWaiting');
  assert.equal(waiting.sessions, 0);
  assert.equal(waiting.commands, 0);
  const checkpoint = waiting.error.authorization.checkpoint;
  assert.equal(deferral.journal.listPending()[0].checkpointCid, checkpoint.checkpointCid);
  assert.equal(deferral.journal.getRunState(checkpoint.runId).status, 'waiting_checkpoint');
  assert.equal(durable.counters().checkpointsPersisted, 1);

  const unsupported = await fixtureAuthorization(readEntries('delegate'),
    { decide: defer, answeringAuthorities: ['reviewer'] });
  const stopped = await acquire(path, unsupported);
  assert.equal(stopped.error?.code, 'ExecutionAuthorizationDeferralUnsupported');
  assert.equal(stopped.sessions, 0);
  assert.equal(unsupported.counters().unsupportedDefers, 1);
  assert.equal(deferral.journal.listPending().length, 1);
});

test('a retry under a changed context re-evaluates and cannot widen authority', async t => {
  const { path } = await database(t);
  const answers = ['permit', 'reject'];
  let calls = 0;
  const gate = await fixtureAuthorization(readEntries('delegate'), {
    decide: view => ({ decision: answers[calls++], subject: view.subject, authority: 'reviewer' }),
    answeringAuthorities: ['reviewer'],
  });
  const first = await acquire(path, gate);
  assert.equal(first.sessions, 1);
  // The same exact scope reuses the permit without another Host call.
  const again = await acquire(path, gate);
  assert.equal(again.sessions, 1);
  assert.equal(calls, 1);
  // Changed authorization context: evaluated again and rejected.
  const changed = gate.withContext({ principal: FIXTURE_CONTEXT.principal,
    contextCid: `sha256:${'8'.repeat(64)}` });
  const retried = await acquire(path, changed);
  assert.equal(calls, 2);
  assert.equal(retried.error?.code, 'ExecutionAuthorizationDenied');
  assert.equal(retried.sessions, 0);
});
