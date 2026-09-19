import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';
import {createRemoteSiteCoordinator} from './remote-site-coordinator.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteSiteControl;
const request = dispatchId => control.prepare({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt: 1,
  dispatchId,
  siteKey: 'site-a',
  siteGeneration: 1,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'local',
  connectorRevision: 'local/1',
  strategyRevision: 'strategy/1',
  inputBindingCid: cid('1'),
  obligationsCid: cid('2'),
  budgetCid: cid('3'),
  evidenceIssuerCapabilityCid: cid('b'),
  grantCid: cid('4'),
});

test('Coordinator makes exact intent durable before transport starts',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-client-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    const dispatch = request('dispatch-a');
    const calls = [];
    const coordinator = createRemoteSiteCoordinator({
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async options => {
        assert.equal(store.contains(options.dispatch, control), true);
        calls.push('send');
        throw Object.assign(new Error('ResponseLost'), {code: 'ResponseLost'});
      },
      query: async () => {
        calls.push('query');
        return Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]});
      },
      cancel: async () => {
        calls.push('cancel');
        return Object.freeze({revision: 0, state: [0, 0, 0, 0, 0]});
      },
    });
    await assert.rejects(
      coordinator.dispatch({dispatch}),
      {code: 'ResponseLost'},
    );
    assert.equal(store.contains(dispatch, control), true);
    assert.deepEqual(store.inspectState(dispatch, control), [
      1, 1, -1, -1, -1, -1, false, false, '', '', '',
    ]);
    await assert.rejects(
      coordinator.dispatch({dispatch: request('dispatch-b')}),
      {code: 'MoonBitHostFailure'},
    );
    assert.deepEqual(calls, ['send']);
    await coordinator.query({dispatch});
    await coordinator.cancel({dispatch});
    assert.deepEqual(calls, ['send', 'query', 'cancel']);
    assert.deepEqual(store.inspectState(dispatch, control), [
      3, 2, 0, 0, 0, 0, false, false, '', '', '',
    ]);
    assert.equal(
      coordinator.completionEvidenceAvailable({dispatch}),
      false,
    );
    store.close();
    const reopenedStore = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => reopenedStore.close());
    const reopened = createRemoteSiteCoordinator({
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store: reopenedStore,
      send: async () => {},
      query: async () => {},
      cancel: async () => {},
    });
    assert.equal(reopened.recovered.length, 1);
    assert.deepEqual(reopenedStore.inspectState(dispatch, control), [
      3, 2, 0, 0, 0, 0, false, false, '', '', '',
    ]);
    assert.equal(
      reopened.completionEvidenceAvailable({dispatch}),
      false,
    );
  });

test('Coordinator never queries an intent absent from its durable journal',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-missing-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    let called = false;
    const coordinator = createRemoteSiteCoordinator({
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => {},
      query: async () => { called = true; },
      cancel: async () => { called = true; },
    });
    await assert.rejects(
      async () => coordinator.query({dispatch: request('dispatch-a')}),
      {code: 'RemoteDispatchIntentMissing'},
    );
    assert.equal(called, false);
  });

test('Site status cannot replace evidence or rewrite one Site revision',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-status-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => store.close());
    const dispatch = request('dispatch-status');
    const coordinator = createRemoteSiteCoordinator({
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store,
      send: async () => Object.freeze({
        revision: 7,
        state: [3, 2, 0, 1, 0],
      }),
      query: async () => Object.freeze({
        revision: 7,
        state: [5, 0, 2, 0, 0],
      }),
      cancel: async () => {},
    });
    await coordinator.dispatch({dispatch});
    assert.equal(
      coordinator.completionEvidenceAvailable({dispatch}),
      false,
    );
    assert.deepEqual(store.inspectState(dispatch, control), [
      1, 2, 7, 3, 2, 0, true, false, '', '', '',
    ]);
    await assert.rejects(
      coordinator.query({dispatch}),
      {code: 'MoonBitHostFailure'},
    );
    assert.deepEqual(store.inspectState(dispatch, control), [
      2, 1, 7, 3, 2, 0, true, false, '', '', '',
    ]);
  });
