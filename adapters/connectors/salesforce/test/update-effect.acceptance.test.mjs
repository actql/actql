// Values-origin Salesforce record updates through the public Client on the
// installed Remote HTTPS Host, against the stateful local org. Every expected
// value (provider bodies, stored records, write counts and Run states) is
// written by hand from the org's stored records and the Program's rows;
// nothing is derived from ActQL output. These expectations are fixed before
// the update path moves to the common author interface and must hold, unchanged,
// after it.
import assert from 'node:assert/strict';
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
