// End-to-end proof of the Run owner's authorization gate against a real
// Remote Site: the gated Coordinator (`createRemoteSiteCoordinator` with its
// SQLite journal and the real mTLS client) dispatches to the real HTTPS Site
// agent fixture with its SQLite dispatch journal. Counts come from the Site
// process itself (HTTP requests reaching its server and dispatch runtime
// starts) and from the Site journal, never from the client.
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createRemoteSiteCoordinator} from
  '../host-node/remote-site-coordinator.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  '../host-node/sqlite-coordinator-journal.mjs';
import {
  accountEntry,
  fixtureAuthorization,
  sqliteDeferral,
} from '../host-node/authorization-fixture.mjs';
import {
  certificates,
  startFixture,
  terminalStatus,
} from './https-agent-harness.mjs';

const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;

const root = await mkdtemp(join(tmpdir(), 'actql-remote-authorization-'));
const material = await certificates(root);
const siteA = await startFixture(root, material, {siteKey: 'site-a'});
const siteB = await startFixture(root, material, {siteKey: 'site-b'});
test.after(async () => {
  await Promise.all([siteA.close(), siteB.close()]);
  await rm(root, {recursive: true, force: true});
});

// Rows the Site's own SQLite dispatch journal holds for one dispatch id.
function siteJournalRows(site, dispatchId) {
  const database = new DatabaseSync(
    join(site.storeRoot, 'dispatch-journal.sqlite3'),
    {readOnly: true},
  );
  try {
    return database.prepare(
      'SELECT COUNT(*) AS count FROM dispatches WHERE dispatch_id = ?',
    ).get(dispatchId).count;
  } finally {
    database.close();
  }
}

// One gated Coordinator dispatch over real mTLS. Reports the Site-observed
// delta of HTTP requests per endpoint and runtime starts, whether the
// Coordinator recorded a durable intent, and the Site journal row count.
async function gatedDispatch(gate, dispatchId, {
  site = siteA,
  signal,
  resumption,
  complete = false,
} = {}) {
  const store = openSqliteCoordinatorDispatchJournal(
    join(root, `coordinator-${dispatchId}`),
    {coordinatorAuthority: 'coordinator-a'},
  );
  try {
    const coordinator = createRemoteSiteCoordinator({
      authorization: gate,
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
    });
    // One task per dispatch id: the Site rejects a second dispatch of the
    // same Run task attempt, which is not what these scenarios exercise.
    const dispatch = site.dispatch(dispatchId, 'local/1',
      {taskKey: `task-${dispatchId}`});
    const options = {
      origin: site.origin,
      ca: material.ca,
      cert: material.coordinatorCertificate,
      key: material.coordinatorKey,
      control,
      dispatch,
      inputBindingBody: '{}',
      signal,
      resumption,
    };
    const before = await site.stats();
    let error;
    let terminal;
    try {
      await coordinator.dispatch(options);
      if (complete) {
        terminal = await terminalStatus(
          {...options, signal: undefined},
          value => coordinator.query(value),
        );
      }
    } catch (reason) {
      error = reason;
    }
    const after = await site.stats();
    const delta = name => (after.requests[name] ?? 0) -
      (before.requests[name] ?? 0);
    return {
      error,
      terminal,
      dispatchRequests: delta('dispatch'),
      allRequests: Object.keys(after.requests)
        .reduce((sum, name) => sum + delta(name), 0),
      runtimeStarts: after.runtimeStarts - before.runtimeStarts,
      coordinatorIntent: store.contains(dispatch, control),
      siteRows: siteJournalRows(site, dispatchId),
    };
  } finally {
    store.close();
  }
}

const refused = (result, code, label) => {
  assert.equal(result.error?.code, code, label);
  assert.equal(result.allRequests, 0, label);
  assert.equal(result.runtimeStarts, 0, label);
  assert.equal(result.coordinatorIntent, false, label);
  assert.equal(result.siteRows, 0, label);
};

const siteEntries = (outcome, connection = 'site-a') => [
  accountEntry('remote-sites', outcome, {connection, operation: 'dispatch'}),
];
const permit = view => ({decision: 'permit', subject: view.subject,
  authority: 'reviewer'});

test('allow: exactly one dispatch reaches and executes on the real Site',
  async () => {
    const gate = await fixtureAuthorization(siteEntries('allow'));
    const result = await gatedDispatch(gate, 'e2e-allow', {complete: true});
    assert.equal(result.error, undefined);
    assert.equal(result.dispatchRequests, 1);
    assert.equal(result.runtimeStarts, 1);
    assert.equal(result.coordinatorIntent, true);
    assert.equal(result.siteRows, 1);
    // Executed to a terminal succeeded state with evidence on the Site.
    assert.deepEqual(result.terminal.state, [3, 2, 0, 1, 0]);
    assert.equal(typeof result.terminal.evidenceWire, 'string');
    assert.equal(gate.counters().protectedDispatches, 1);
    assert.equal(gate.counters().hostDecisionCalls, 0);
  });

test('explicit deny and no-match deny send no HTTP request to the Site',
  async () => {
    const explicit = await fixtureAuthorization(siteEntries('deny'));
    refused(await gatedDispatch(explicit, 'e2e-explicit-deny'),
      'ExecutionAuthorizationDenied', 'explicit deny');
    const noMatch = await fixtureAuthorization(siteEntries('allow', 'site-z'));
    refused(await gatedDispatch(noMatch, 'e2e-no-match'),
      'ExecutionAuthorizationDenied', 'no-match deny');
    assert.equal(explicit.counters().deniedBeforeDispatch, 1);
    assert.equal(noMatch.counters().deniedBeforeDispatch, 1);
  });

test('delegate: immediate permit dispatches once; reject sends nothing',
  async () => {
    const permitted = await fixtureAuthorization(siteEntries('delegate'), {
      decide: permit, answeringAuthorities: ['reviewer'],
    });
    const sent = await gatedDispatch(permitted, 'e2e-permit');
    assert.equal(sent.error, undefined);
    assert.equal(sent.dispatchRequests, 1);
    assert.equal(sent.runtimeStarts, 1);
    assert.equal(sent.coordinatorIntent, true);
    assert.equal(sent.siteRows, 1);

    const rejecting = await fixtureAuthorization(siteEntries('delegate'), {
      decide: view => ({decision: 'reject', subject: view.subject,
        authority: 'reviewer'}),
      answeringAuthorities: ['reviewer'],
    });
    refused(await gatedDispatch(rejecting, 'e2e-reject'),
      'ExecutionAuthorizationDenied', 'reject');
    assert.equal(rejecting.counters().hostRejections, 1);
  });

test('decision failure (throw, timeout) sends nothing and is not a reject',
  async () => {
    for (const [label, decide] of [
      ['throw', () => { throw new Error('DecisionServiceDown'); }],
      ['timeout', () => new Promise(() => {})],
    ]) {
      const gate = await fixtureAuthorization(siteEntries('delegate'), {
        decide, answeringAuthorities: ['reviewer'], decisionTimeoutMs: 50,
      });
      const result = await gatedDispatch(gate, `e2e-failure-${label}`);
      refused(result, 'ExecutionAuthorizationDecisionFailed', label);
      assert.equal(result.error.authorization.action, 'failure', label);
      if (label === 'timeout') {
        assert.equal(result.error.authorization.reason, 'timeout', label);
      }
      assert.equal(gate.counters().decisionFailures, 1, label);
      assert.equal(gate.counters().hostRejections, 0, label);
      assert.equal(gate.counters().deniedBeforeDispatch, 0, label);
    }
  });

test('defer persists a Checkpoint and sends nothing; the committed approval ' +
  'resumes exactly one dispatch to the approved Site only', async t => {
  const journalRoot = await mkdtemp(join(tmpdir(), 'actql-remote-deferral-'));
  t.after(() => rm(journalRoot, {recursive: true, force: true}));
  const deferral = await sqliteDeferral(journalRoot);
  t.after(() => deferral.journal.close());
  let hostCalls = 0;
  const gate = await fixtureAuthorization(
    siteEntries('delegate', ['site-a', 'site-b']),
    {
      decide: view => {
        hostCalls++;
        return {decision: 'defer', subject: view.subject};
      },
      answeringAuthorities: ['reviewer'],
      deferral,
    },
  );
  const waiting = await gatedDispatch(gate, 'e2e-defer');
  refused(waiting, 'ExecutionAuthorizationWaiting', 'defer');
  const checkpoint = waiting.error.authorization.checkpoint;
  assert.equal(deferral.journal.getRunState(checkpoint.runId).status,
    'waiting_checkpoint');
  assert.deepEqual(deferral.journal.listPending()
    .map(pending => pending.checkpointCid), [checkpoint.checkpointCid]);
  assert.equal(gate.counters().checkpointsPersisted, 1);

  // The reviewer approves through the journal; the Run owner claims resume.
  const resolution = await deferral.answer(checkpoint.checkpointCid,
    'approved');
  assert.equal(resolution.decision, 'approved');
  const claim = deferral.journal.claimResume(checkpoint.runId, {
    claimant: 'coordinator-a', leaseMs: 60_000, binding: deferral.binding,
  });
  assert.equal(claim.action, 'claimed');
  const resumption = {claim, resolution};

  // The approval for Site A does not dispatch the same Run to Site B.
  const elsewhere = await gatedDispatch(gate, 'e2e-defer', {
    site: siteB, resumption,
  });
  refused(elsewhere, 'ExecutionAuthorizationDecisionFailed', 'Site B');
  assert.equal(elsewhere.error.authorization.detail,
    'ResolutionSubjectMismatch');

  const resumed = await gatedDispatch(gate, 'e2e-defer', {resumption});
  assert.equal(resumed.error, undefined);
  assert.equal(resumed.dispatchRequests, 1);
  assert.equal(resumed.runtimeStarts, 1);
  assert.equal(resumed.coordinatorIntent, true);
  assert.equal(resumed.siteRows, 1);
  // Resumption asked the Host nothing new.
  assert.equal(hostCalls, 1);
  assert.equal(gate.counters().resumedDecisions, 1);
  assert.equal(siteJournalRows(siteB, 'e2e-defer'), 0);
});

test('a changed Site after a permit is decided again and not dispatched',
  async () => {
    const decided = [];
    const gate = await fixtureAuthorization(
      siteEntries('delegate', ['site-a', 'site-b']),
      {
        decide: view => {
          decided.push(view.tuple.connection);
          return view.tuple.connection === 'site-a' ? permit(view)
            : {decision: 'reject', subject: view.subject,
              authority: 'reviewer'};
        },
        answeringAuthorities: ['reviewer'],
      },
    );
    const first = await gatedDispatch(gate, 'e2e-site-change');
    assert.equal(first.dispatchRequests, 1);
    assert.equal(first.siteRows, 1);
    // Same Run and registration, other Site: the Site A permit is not reused.
    const moved = await gatedDispatch(gate, 'e2e-site-change', {site: siteB});
    refused(moved, 'ExecutionAuthorizationDenied', 'Site B');
    assert.deepEqual(decided, ['site-a', 'site-b']);
    assert.equal(gate.counters().reusedDecisions, 0);
    // The same Site A dispatch reuses its exact permit without a new call.
    const again = await gatedDispatch(gate, 'e2e-site-change-retry');
    assert.equal(again.dispatchRequests, 1);
    assert.deepEqual(decided, ['site-a', 'site-b']);
    assert.equal(gate.counters().reusedDecisions, 1);
  });

test('cancelling the Run while it waits sends nothing', async t => {
  // Cancelled while the Host decision is pending.
  let asked;
  const called = new Promise(resolve => { asked = resolve; });
  const pending = await fixtureAuthorization(siteEntries('delegate'), {
    decide: () => { asked(); return new Promise(() => {}); },
    answeringAuthorities: ['reviewer'],
  });
  const controller = new AbortController();
  const cancelling = gatedDispatch(pending, 'e2e-cancel-pending',
    {signal: controller.signal});
  await called;
  controller.abort(new Error('RunCancelled'));
  const cancelled = await cancelling;
  refused(cancelled, 'ExecutionAuthorizationDecisionFailed', 'pending');
  assert.equal(cancelled.error.authorization.reason, 'unavailable');

  // Cancelled while waiting on a persisted Checkpoint: the journal cancels
  // the waiting Run when its Checkpoint closes unanswered. No approval can
  // be committed afterwards and there is no resume to dispatch from.
  const journalRoot = await mkdtemp(join(tmpdir(), 'actql-remote-cancel-'));
  t.after(() => rm(journalRoot, {recursive: true, force: true}));
  const clock = {ms: Date.now()};
  const deferral = await sqliteDeferral(journalRoot, {now: () => clock.ms});
  t.after(() => deferral.journal.close());
  const gate = await fixtureAuthorization(siteEntries('delegate'), {
    decide: view => ({decision: 'defer', subject: view.subject}),
    answeringAuthorities: ['reviewer'],
    deferral,
  });
  const waiting = await gatedDispatch(gate, 'e2e-cancel-waiting');
  refused(waiting, 'ExecutionAuthorizationWaiting', 'waiting');
  const checkpoint = waiting.error.authorization.checkpoint;
  clock.ms += 2 * 86_400_000;
  assert.deepEqual(deferral.journal.expire(), [checkpoint.checkpointCid]);
  assert.equal(deferral.journal.getRunState(checkpoint.runId).status,
    'cancelled');
  // Answering after the Run was cancelled commits nothing.
  await assert.rejects(deferral.answer(checkpoint.checkpointCid, 'approved'),
    error => ['CheckpointExpired', 'InvalidResolution'].includes(error.code));
  assert.equal(deferral.journal.inspect(checkpoint.checkpointCid).closure,
    'expired');
  assert.throws(() => deferral.journal.claimResume(checkpoint.runId, {
    claimant: 'coordinator-a', leaseMs: 60_000, binding: deferral.binding,
  }), {code: 'ResumeIntentNotFound'});
  // A resume presented anyway is not a committed approval.
  const forged = await gatedDispatch(gate, 'e2e-cancel-waiting', {
    resumption: {
      claim: {action: 'claimed', checkpointCid: checkpoint.checkpointCid,
        claim: {runId: checkpoint.runId}},
      resolution: {decision: 'approved', resolutionCid: `sha256:${'f'.repeat(64)}`,
        verifiedResolutionWire: '{}'},
    },
  });
  refused(forged, 'ExecutionAuthorizationDecisionFailed', 'forged resume');
  assert.equal(forged.error.authorization.detail, 'ResolutionNotCommitted');
});
