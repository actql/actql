import assert from 'node:assert/strict';
import test from 'node:test';
import {GMAIL_THREAD_GET_OPERATION, GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';
import {threadFactoryFixture} from './gmail-thread-factory.fixture.mjs';

test('Gmail installed reader uses actual original Account Site and RowRun with separate get uses', async t => {
  const f = await threadFactoryFixture(t);
  f.state.pages = [JSON.stringify({threads: [{id: 'one'}, {id: 'two'}]}),
    JSON.stringify({id: 'one', messages: []}), JSON.stringify({id: 'two', messages: []})];
  const reader = f.makeFactory().prepare(f.options), result = await reader.read();
  assert.equal(result.rowCount, 2); assert.equal(result.pages, 1);
  assert.deepEqual(f.state.rows, ['one', 'two'].map(id => ({id, labels: [], last_message_date: null,
    message_count: '0', subject: null})));
  assert.equal(f.grants.length, 2);
  assert.deepEqual(f.grants.map(value => value.options.operation), [GMAIL_THREAD_LIST_OPERATION, GMAIL_THREAD_GET_OPERATION]);
  assert.ok(f.grants.every(value => f.authorization.issued(value.options.decision)));
  assert.notEqual(f.grants[0].original.grant, f.grants[1].original.grant);
  const uses = result.observations.map(response => f.site.credential.journal.inspect(response.useCid));
  assert.notEqual(uses[0].grantCid, uses[1].grantCid); assert.equal(uses[1].grantCid, uses[2].grantCid);
  assert.notEqual(uses[1].useId, uses[2].useId); assert.equal(uses[1].useOrdinal, 1); assert.equal(uses[2].useOrdinal, 2);
  assert.equal(f.state.charges, 3); f.row.finish();
  // Completed typed rows are not a physical cleanup/capture ACK. The fixture
  // deliberately retains the original raw/callback graph and its reservation.
  f.row.assertNoCapture();
  assert.equal(reader.observe().transportClosed, true); assert.equal(reader.observe().cleanupConfirmed, false);
  await assert.rejects(reader.read(), {code: 'InstalledGmailThreadReaderAlreadyStarted'});
});

test('Gmail installed reader captures original methods receivers and does not repeat its acquisition', async t => {
  const f = await threadFactoryFixture(t), moon = {...f.provider};
  const prepare = moon.gmailPrepareThreadRead;
  moon.gmailPrepareThreadRead = function(...args) {assert.equal(this, moon); return prepare(...args);};
  const factory = f.makeFactory({moon}), reader = factory.prepare(f.options);
  f.state.resolved = () => {
    moon.gmailNextThreadRequest = () => {throw Error('replacement provider');};
    f.suppliedSite.issueReadGrant = () => {throw Error('replacement Site');};
    f.suppliedSite.callResource = () => {throw Error('replacement physical caller');};
    f.options.verifyRead = () => {throw Error('replacement current');};
  };
  const result = await reader.read(); assert.equal(result.rowCount, 1);
  assert.throws(() => factory.prepare(f.options), {code: 'GmailThreadReaderAlreadyPrepared'});
  assert.equal(f.state.requests.length, 2); assert.equal(reader.observe().cleanupConfirmed, false);
});

test('Gmail installed reader refuses a copied Account decision before dependent get grant and send', async t => {
  const f = await threadFactoryFixture(t), current = f.options.verifyRead;
  f.options.verifyRead = async function() {
    const original = await Reflect.apply(current, f.options, []);
    return f.state.requests.length === 0 ? original : {...original};
  };
  const reader = f.makeFactory().prepare(f.options);
  await assert.rejects(reader.read(), error => error.cause?.code === 'RowSourceGrantNotAuthorized');
  assert.equal(f.state.requests.length, 1); assert.equal(f.state.charges, 1);
  assert.equal(f.grants.length, 1); f.row.assertNoCapture();
  assert.equal(reader.observe().cleanupConfirmed, false);
});

test('Gmail installed reader rechecks original RowRun container after Account await', async t => {
  const f = await threadFactoryFixture(t);
  f.hooks.afterCurrent = () => {if (f.state.requests.length === 1) f.options.rowRun = {...f.rowRun};};
  const reader = f.makeFactory().prepare(f.options);
  await assert.rejects(reader.read(), error => error.cause?.code === 'ForeignInstalledGmailThreadRun');
  assert.equal(f.state.requests.length, 1); assert.equal(f.grants.length, 1); f.row.assertNoCapture();
});

test('Gmail installed reader retains rejected get response charge and refuses another start', async t => {
  const f = await threadFactoryFixture(t);
  f.state.beforeResponse = () => {if (f.state.requests.length === 2) f.state.status = 403;};
  const reader = f.makeFactory().prepare(f.options);
  await assert.rejects(reader.read(), error => error.cause?.code === 'GmailThreadReadRejected' &&
    error.observations.length === 2 && error.exchanges[1].charge !== undefined && error.observations[1].statusCode === 403);
  assert.equal(f.state.charges, 2); assert.deepEqual(f.state.rows, []); f.row.assertNoCapture();
  await assert.rejects(reader.read(), {code: 'InstalledGmailThreadReaderAlreadyStarted'});
  assert.equal(f.state.requests.length, 2); assert.equal(reader.observe().cleanupConfirmed, false);
});

test('Gmail installed reader fails closed for denied Account and missing capacity', async t => {
  const f = await threadFactoryFixture(t, {account: 'deny'});
  assert.throws(() => f.makeFactory({capacity: undefined}), {code: 'GmailReaderCapacityUnavailable'});
  const reader = f.makeFactory().prepare(f.options);
  await assert.rejects(reader.read(), {code: 'GmailReadDenied'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.grants.length, 0); f.row.assertNoCapture();
});
