// Values-origin Salesforce record updates through the public Client on the
// installed Remote HTTPS Host, against the stateful local org. Every expected
// value (provider bodies, stored records, write counts and Run states) is
// written by hand from the org's stored records and the Program's rows;
// nothing is derived from ActQL output. These expectations are fixed before
// the update path moves to the common author interface and must hold, unchanged,
// after it.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {effectProgram} from './installed-salesforce-effect.fixture.mjs';
import {numberText} from './salesforce-effect-site.fixture.mjs';
import {approveHeldSet, readComputeEffectInstallation, waitFor} from
  './read-compute-effect.fixture.mjs';

const terminal = ['succeeded', 'failed', 'needs_reconciliation', 'cancelled'];
const targetOf = write => decodeURIComponent(write.path.split('/').at(-1));

// Two stored records with a Number(15,2), a datetime and a text value.
const typedRecords = Object.freeze([
  {Id: 'a00000000000001', Name: 'record-1', External_Key__c: 'key-1',
    Amount__c: numberText('1.2345678E7'),
    Due_At__c: '2012-07-12T17:49:01.123+0000', Due_Date__c: null},
  {Id: 'a00000000000002', Name: 'record-2', External_Key__c: 'key-2',
    Amount__c: null, Due_At__c: null, Due_Date__c: null}]);
const typedWrite = {resource: 'Test_Record__c', kind: 'update',
  fields: ['Amount__c', 'Due_At__c', 'Name']};
const typedOrg = {numberFields: true, temporalFields: true,
  patchFields: ['Amount__c', 'Due_At__c', 'Name']};
const typedSchema = (nameNullable = false) => ({
  id: {type: 'string', nullable: false},
  amount: {type: 'decimal', precision: 15, scale: 2, nullable: true},
  at: {type: 'timestamp', nullable: true},
  name: {type: 'string', nullable: nameNullable}});

const typedProgram = (setup, rows, nameNullable) => JSON.stringify(effectProgram({save:
  {update: {target: 'connector://crm-main/Test_Record__c',
    mapping: setup.mappingRef, from: {result: 'rows'}, id: 'id',
    set: {Amount__c: {field: 'amount'}, Due_At__c: {field: 'at'},
      Name: {field: 'name'}}}}}, rows, typedSchema(nameNullable)));

// The rows of a Name-only update.
const nameProgram = (setup, ids) => JSON.stringify(effectProgram({save:
  {update: {target: 'connector://crm-main/Test_Record__c',
    mapping: setup.mappingRef, from: {result: 'rows'}, id: 'id',
    set: {Name: {field: 'id'}}}}}, ids.map(id => ({id}))));

async function submit(setup, host, program, requestId) {
  const client = await host.as('owner-token');
  const execution = await client.aql(program, {format: 'json', requestId});
  const state = await waitFor(async () => {
    const current = await execution.status();
    return current.status === 'waiting_checkpoint' ||
      terminal.includes(current.status) ? current : undefined;
  });
  return {execution, state};
}

// Approve from a separate Host that is closed before anything else happens.
async function approveStopped(setup, first, execution) {
  await first.close();
  const reviewer = await setup.openHost();
  await approveHeldSet(reviewer, execution);
  await reviewer.close();
}

async function resumed(setup, execution) {
  const host = await setup.openHost();
  const attached = await (await host.as('owner-token')).attach(execution.ref);
  const state = await waitFor(async () => {
    const current = await attached.status();
    return terminal.includes(current.status) ? current : undefined;
  });
  return {host, attached, state};
}

test('typed values and nulls are held, approved across restarts and written once as approved',
  async t => {
    const setup = await readComputeEffectInstallation(t, {
      records: typedRecords, writes: [typedWrite], org: typedOrg});
    const first = await setup.openHost();
    const {execution, state} = await submit(setup, first, typedProgram(setup, [
      {id: 'a00000000000001', amount: '12.50',
        at: '2024-06-01T09:30:00.000Z', name: 'one'},
      {id: 'a00000000000002', amount: null, at: null, name: 'two'}]),
    'update-typed');
    assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(state));
    // Held: nothing is written before approval.
    assert.equal(setup.writes().length, 0);
    await approveStopped(setup, first, execution);
    assert.equal(setup.writes().length, 0);
    const {host: third, state: done} = await resumed(setup, execution);
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    // Exactly one PATCH per row: the decimal keeps its approved digits, the
    // datetime is sent as approved, and a null is sent as JSON null.
    assert.deepEqual(setup.writes().map(write =>
      [write.method, targetOf(write), write.body]).sort(), [
      ['PATCH', 'a00000000000001',
        '{"Amount__c":12.50,"Due_At__c":"2024-06-01T09:30:00.000Z","Name":"one"}'],
      ['PATCH', 'a00000000000002',
        '{"Amount__c":null,"Due_At__c":null,"Name":"two"}'],
    ]);
    assert.deepEqual(setup.org.records().map(record =>
      [record.Id, record.Name, record.Due_At__c]), [
      ['a00000000000001', 'one', '2024-06-01T09:30:00.000Z'],
      ['a00000000000002', 'two', null]]);
    await third.close();
    // A further restart writes nothing more.
    const fourth = await setup.openHost();
    const again = await (await fourth.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'succeeded');
    assert.equal(setup.writes().length, 2);
  });

test('a nullable source for a non-nullable field is refused at submission',
  async t => {
    const setup = await readComputeEffectInstallation(t, {
      records: typedRecords, writes: [typedWrite], org: typedOrg});
    const host = await setup.openHost();
    const client = await host.as('owner-token');
    await assert.rejects(client.aql(typedProgram(setup, [
      {id: 'a00000000000001', amount: '1.00',
        at: '2024-06-01T09:30:00.000Z', name: null}], true),
    {format: 'json', requestId: 'update-null-name'}),
    {code: 'ClientProgramRejected'});
    assert.equal(setup.writes().length, 0);
  });

test('a rejected write fails the Set and halts the rows after it',
  async t => {
    const setup = await readComputeEffectInstallation(t,
      {org: {rejectWrites: [1]}});
    const first = await setup.openHost();
    const {execution} = await submit(setup, first, nameProgram(setup,
      ['a00000000000001', 'a00000000000003']), 'update-rejected');
    await approveStopped(setup, first, execution);
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    // The first row was sent and rejected; halt sends nothing after it.
    assert.equal(setup.writes().length, 1);
    assert.deepEqual(setup.org.records().map(record => record.Name),
      ['record-1', 'record-2', 'record-3']);
  });

test('a server error after the send is unknown and never resent',
  async t => {
    const setup = await readComputeEffectInstallation(t, {org: {writeReplies: {
      1: {status: 500, body: [{errorCode: 'SERVER_UNAVAILABLE',
        message: 'unavailable'}]}}}});
    const first = await setup.openHost();
    const {execution} = await submit(setup, first, nameProgram(setup,
      ['a00000000000001']), 'update-server-error');
    await approveStopped(setup, first, execution);
    const {host: second, state} = await resumed(setup, execution);
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    assert.equal(setup.writes().length, 1);
    await second.close();
    const third = await setup.openHost();
    const again = await (await third.as('owner-token')).attach(execution.ref);
    await waitFor(async () => terminal.includes((await again.status()).status));
    assert.equal(setup.writes().length, 1);
  });

test('a reply lost after the org applied the update is unknown and never resent',
  async t => {
    const setup = await readComputeEffectInstallation(t,
      {org: {loseReplyAfterApply: [1]}});
    const first = await setup.openHost();
    const {execution} = await submit(setup, first, nameProgram(setup,
      ['a00000000000001']), 'update-lost-reply');
    await approveStopped(setup, first, execution);
    const {host: second, state} = await resumed(setup, execution);
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    // Applied at the org, sent exactly once.
    assert.equal(setup.org.records()[0].Name, 'a00000000000001');
    assert.equal(setup.writes().length, 1);
    await second.close();
    const third = await setup.openHost();
    const again = await (await third.as('owner-token')).attach(execution.ref);
    assert.equal((await waitFor(async () => {
      const current = await again.status();
      return terminal.includes(current.status) ? current : undefined;
    })).status, 'needs_reconciliation');
    assert.equal(setup.writes().length, 1);
  });

// Wait until the Run's physical work and its cleanup are confirmed stopped.
const stopped = attached => waitFor(async () => {
  const current = await attached.status();
  return current.control?.physical_stop === 'confirmed' ? current : undefined;
});

// The first close of a journal of `module` fails; every close is counted.
function failFirstClose(t, module) {
  const original = DatabaseSync.prototype.close;
  const injected = new Error('InjectedJournalCloseFailure');
  const counts = {attempts: 0, failed: 0};
  DatabaseSync.prototype.close = function () {
    if (new Error().stack.includes(module)) {
      counts.attempts++;
      if (counts.failed === 0) {
        counts.failed++;
        throw injected;
      }
    }
    return original.call(this);
  };
  const restore = () => { DatabaseSync.prototype.close = original; };
  t.after(restore);
  return {injected, counts, restore};
}

// The installed Host's cleanup: a journal close that fails while the Host
// shuts down keeps the release pending, with its original error, and the
// Host's cleanup handle retries it without any provider I/O. The public Run
// state is checked separately from the internal release.
test('a failed journal close at Host shutdown is retried without provider I/O',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const first = await setup.openHost();
    const {execution} = await submit(setup, first, nameProgram(setup,
      ['a00000000000001']), 'update-cleanup');
    await approveStopped(setup, first, execution);
    const {host, attached} = await resumed(setup, execution);
    await stopped(attached);
    const seen = setup.org.seen.length;
    const fault = failFirstClose(t, 'sqlite-credential-journal.mjs');
    let pending;
    await assert.rejects(host.close(), error => {
      pending = error;
      assert.equal(error.code, 'InstalledHostCleanupPending');
      assert.ok(error.cleanupErrors.some(item =>
        item.error === fault.injected));
      assert.ok(error.cleanupHandle.status().pending.length > 0);
      return true;
    });
    // Internal release: the same handle's retry completes it.
    await pending.cleanupHandle.retry();
    assert.deepEqual(pending.cleanupHandle.status().pending, []);
    fault.restore();
    assert.equal(setup.org.seen.length, seen);
    // Public state: the Run stays succeeded with its one write.
    const after = await setup.openHost();
    const again = await (await after.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'succeeded');
    assert.equal(setup.writes().length, 1);
  });

// The recovered Effect Ledger handle is released by the Host's recovery
// custody after the Run settles. A close that fails there stays that owner's
// pending cleanup and is retried by the Host, with no provider I/O and no
// change to the Run's public state.
test('a failed close of the recovered Ledger handle is retried by the Host',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const first = await setup.openHost();
    const {execution} = await submit(setup, first, nameProgram(setup,
      ['a00000000000001']), 'update-ledger-cleanup');
    await approveStopped(setup, first, execution);
    const host = await setup.openHost();
    const fault = failFirstClose(t, 'effect-ledger.mjs');
    const attached = await (await host.as('owner-token'))
      .attach(execution.ref);
    const state = await waitFor(async () => {
      const current = await attached.status();
      return terminal.includes(current.status) ? current : undefined;
    });
    // Public state: settled, written once.
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.equal(setup.writes().length, 1);
    const seen = setup.org.seen.length;
    // Internal release: the failed first close is retried by its owner
    // before the Host completes its shutdown.
    await host.close();
    assert.equal(fault.counts.failed, 1);
    assert.ok(fault.counts.attempts >= 2);
    fault.restore();
    assert.equal(setup.org.seen.length, seen);
    const after = await setup.openHost();
    const again = await (await after.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'succeeded');
    assert.equal(setup.writes().length, 1);
  });

// --- Embedded Local: each step is its own process, so each is a restart ----
// Embedded Local has no shutdown of its own (its Host lives with its
// process), so the shutdown cleanup case above is HTTPS only; the recovered
// Ledger close below is the same Host owner on both paths.

test('Local: held across restarts, approved, written once and never again',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const steps = await setup.embedded('update-local-once',
      nameProgram(setup, ['a00000000000001']), {resultName: 'answer'});
    assert.deepEqual(await steps('submit'), {held: true});
    assert.equal(setup.writes().length, 0);
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    assert.equal(setup.writes().length, 0);
    const done = await steps('resume');
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    assert.deepEqual(setup.writes().map(write => [targetOf(write),
      write.body]), [['a00000000000001', '{"Name":"a00000000000001"}']]);
    assert.equal((await steps('resume')).status, 'succeeded');
    assert.equal(setup.writes().length, 1);
  });

test('Local: a reply lost after the org applied the update stays unknown and is never resent',
  async t => {
    const setup = await readComputeEffectInstallation(t,
      {org: {loseReplyAfterApply: [1]}});
    const steps = await setup.embedded('update-local-lost',
      nameProgram(setup, ['a00000000000001']), {resultName: 'answer'});
    assert.deepEqual(await steps('submit'), {held: true});
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    assert.equal((await steps('resume')).status, 'needs_reconciliation');
    assert.equal(setup.org.records()[0].Name, 'a00000000000001');
    assert.equal(setup.writes().length, 1);
    assert.equal((await steps('resume')).status, 'needs_reconciliation');
    assert.equal(setup.writes().length, 1);
  });

test('Local: a rejected write fails the Set and halts the rows after it',
  async t => {
    const setup = await readComputeEffectInstallation(t,
      {org: {rejectWrites: [1]}});
    const steps = await setup.embedded('update-local-rejected',
      nameProgram(setup, ['a00000000000001', 'a00000000000003']),
      {resultName: 'answer'});
    assert.deepEqual(await steps('submit'), {held: true});
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    assert.equal((await steps('resume')).status, 'failed');
    assert.equal(setup.writes().length, 1);
  });

test('Local: a failed close of the recovered Ledger handle is retried by the Host',
  async t => {
    const setup = await readComputeEffectInstallation(t);
    const steps = await setup.embedded('update-local-ledger-cleanup',
      nameProgram(setup, ['a00000000000001']),
      {resultName: 'answer', failFirstClose: 'effect-ledger.mjs'});
    assert.deepEqual(await steps('submit'), {held: true});
    assert.deepEqual(await steps('answer'), {answered: ['committed']});
    const done = await steps('resume');
    // Public state: settled, written once.
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    assert.equal(setup.writes().length, 1);
    // Internal release: the failed first close was retried by its owner.
    assert.equal(done.closes.failed, 1);
    assert.ok(done.closes.attempts >= 2, JSON.stringify(done.closes));
  });
