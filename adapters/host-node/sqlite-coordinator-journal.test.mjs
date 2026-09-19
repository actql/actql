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

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteSiteControl;
const request = (dispatchId, taskAttempt = 1) => control.prepare({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt,
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
  grantCid: cid('4'),
});

test('Coordinator intent persists before send and restores after restart',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-journal-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const firstStore = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    const firstJournal = control.createCoordinatorJournal('coordinator-a');
    const dispatch = request('dispatch-a');
    const admission = control.prepareCoordinatorIntent(firstJournal, dispatch);
    const record = firstStore.accept(admission, dispatch, control);
    assert.equal(control.coordinatorIntentMatches(record, dispatch), true);
    assert.equal(firstStore.contains(dispatch, control), true);
    firstStore.close();

    const reopened = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => reopened.close());
    const restoredJournal = control.createCoordinatorJournal('coordinator-a');
    const recovered = reopened.recoverJournal(restoredJournal, control);
    assert.equal(recovered.length, 1);
    assert.equal(
      control.coordinatorIntentMatches(recovered[0].record, dispatch),
      true,
    );
    const retry = control.prepareCoordinatorIntent(restoredJournal, dispatch);
    assert.equal(control.coordinatorIntentIsNew(retry), false);
    reopened.accept(retry, dispatch, control);
  });

test('Coordinator journal transaction rejects a second dispatch occurrence',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-race-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const left = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    const right = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => left.close());
    t.after(() => right.close());
    const leftJournal = control.createCoordinatorJournal('coordinator-a');
    const rightJournal = control.createCoordinatorJournal('coordinator-a');
    const first = request('dispatch-a');
    const second = request('dispatch-b');
    left.accept(
      control.prepareCoordinatorIntent(leftJournal, first),
      first,
      control,
    );
    assert.throws(
      () => right.accept(
        control.prepareCoordinatorIntent(rightJournal, second),
        second,
        control,
      ),
      {code: 'RemoteAttemptAlreadyDispatched'},
    );
  });
