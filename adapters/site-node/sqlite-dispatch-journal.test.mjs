import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);

const request = (dispatchId, taskAttempt = 1, connectorRevision = 'local/1') =>
  Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt,
    dispatchId,
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision,
    strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'),
    obligationsCid: cid('2'),
    budgetCid: cid('3'),
    grantCid: cid('4'),
  });

function site() {
  return runtime.siteControl.create(Object.freeze({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n,
  }));
}

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-journal-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const store = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
    ...options,
  });
  t.after(() => store.close());
  return {root, store};
}

test('accepted dispatch is durable before MoonBit permits execution', async t => {
  const {store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const journal = control.createJournal(site());
  const prepared = control.prepare(request('dispatch-a'));
  const admission = control.prepareAdmission(journal, prepared);
  const record = store.accept(admission, prepared, control);
  assert.deepEqual(control.status(record), [0, 0, 0, 0, 0]);
  assert.deepEqual(store.inspect(prepared, control), {
    dispatch_request_cid: control.identity(prepared),
    request_json: control.requestJson(prepared),
  });
  control.beginProvisioning(record);
  control.beginExecution(record);
  assert.deepEqual(control.status(record), [2, 0, 0, 0, 0]);
});

test('reopen reconciles exact resend and rejects durable collisions', async t => {
  const {root, store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const firstJournal = control.createJournal(site());
  const first = control.prepare(request('dispatch-a'));
  store.accept(control.prepareAdmission(firstJournal, first), first, control);
  store.close();

  const reopened = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
  });
  t.after(() => reopened.close());
  const recoveredJournal = control.createJournal(site());
  const resend = control.prepare(request('dispatch-a'));
  const record = reopened.accept(
    control.prepareAdmission(recoveredJournal, resend),
    resend,
    control,
  );
  assert.deepEqual(control.status(record), [0, 0, 0, 0, 0]);

  const collisionJournal = control.createJournal(site());
  const collision = control.prepare(request('dispatch-a', 1, 'local/2'));
  assert.throws(() => reopened.accept(
    control.prepareAdmission(collisionJournal, collision),
    collision,
    control,
  ), {code: 'RemoteDispatchCollision'});

  const duplicateJournal = control.createJournal(site());
  const duplicate = control.prepare(request('dispatch-b'));
  assert.throws(() => reopened.accept(
    control.prepareAdmission(duplicateJournal, duplicate),
    duplicate,
    control,
  ), {code: 'RemoteAttemptAlreadyDispatched'});
});

test('failed durable admission does not consume the MoonBit attempt', async t => {
  const {store} = await fixture(t, {maxDispatches: 1});
  const control = runtime.remoteSiteControl;
  const firstJournal = control.createJournal(site());
  const first = control.prepare(request('dispatch-a'));
  store.accept(control.prepareAdmission(firstJournal, first), first, control);

  const journal = control.createJournal(site());
  const second = control.prepare(request('dispatch-c', 2));
  const admission = control.prepareAdmission(journal, second);
  assert.throws(
    () => store.accept(admission, second, control),
    {code: 'RemoteJournalCapacityExceeded'},
  );
  assert.doesNotThrow(() => control.prepareAdmission(journal, second));
});
