import {installedFailureCode} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedKintoneFixture as fixture, originalForm, record} from './installed-kintone.fixture.mjs';

const assertReleased = ledger => assert.deepEqual(
  ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);

test('installed kintone prepares original typed metadata without provider or secret lookup', async t => {
  const f = await fixture(t), source = await f.load();
  assert.equal(source.connectorRegistration, 'kintone');
  assert.deepEqual(source.sourceReadAccesses.map(value => value.resource), ['inquiries']);
  await source.prepare(await f.prepare(source));
  assert.equal(f.tls.seen().length, 0);assert.equal(f.state.resolutions, 0);
});

test('installed kintone pages the same accounted RowRun with original wide ID and separate App record number', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  const opened = await source.openCapture({...await f.prepare(source), ledger});f.captures.push(opened);
  const exported = checked(common.clientProgramExportSourceCapture(opened.capture.source(),
    opened.requirement, 'kintone-record-read-test'));
  const rows = common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
  assert.deepEqual(rows, ['9007199254740992', '9007199254740993', '9007199254740994'].map((id, i) => ({
    $id: id, Subject: '東京\r\nnext', Tags: ['red', '東京', 'red'], RecordNumber: `APP-${i + 7}`})));
  assert.deepEqual(f.tls.seen().map(value => value.pathname), [
    '/k/v1/app/form/fields.json', '/k/v1/records.json', '/k/v1/app/form/fields.json',
    '/k/v1/records.json', '/k/v1/app/form/fields.json']);
  assert.equal(f.state.resolutions, 5);
  assert.equal(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes,
    BigInt(f.state.responseBodies.reduce((sum, value) => sum + value.byteLength, 0)));
  await opened.close();assertReleased(ledger);
});

test('kintone metadata and record read permissions remain independent before I/O', async t => {
  for (const options of [{formRead: 'deny'}, {recordsRead: 'deny'}]) {
    const f = await fixture(t, options), source = await f.load(), ledger = f.ledger();
    await assert.rejects(source.openCapture({...await f.prepare(source), ledger}));
    assert.equal(f.tls.seen().length, 0);assert.equal(f.state.resolutions, 0);
    assertReleased(ledger);
  }
});

test('a changed kintone resolver cannot replace the original token between Form and records', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  f.state.resolve = async () => {if (f.state.resolutions === 2) f.state.secret = 'foreign-app-token';};
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'RemoteCredentialBindingChanged'});
  assert.equal(f.tls.seen().length, 1);assert.equal(f.state.resolutions, 2);
  assertReleased(ledger);
});

test('a changed final Form refuses capture after real record bytes without a replacement lookup', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  f.state.page = () => ({records: [record('9007199254740992')], totalCount: null});
  f.state.form = count => count === 2 ? {...originalForm, revision: '8'} : originalForm;
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'MoonBitHostFailure'});
  assert.equal(f.tls.seen().length, 3);assert.equal(f.state.forms, 2);
  assert.equal(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes,
    BigInt(f.state.responseBodies.reduce((sum, value) => sum + value.byteLength, 0)));
  assertReleased(ledger);
});

test('kintone repeated cross-page IDs abort instead of treating totalCount as completion', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  f.state.page = count => ({records: count === 1
    ? [record('9007199254740992'), record('9007199254740993')]
    : [record('9007199254740993')], totalCount: '1'});
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.pages, 2);assert.equal(f.tls.seen().length, 4);
  assertReleased(ledger);
});

test('a kintone reply loss remains Unknown with one physical request and no automatic retry', async t => {
  const f = await fixture(t, {faults: [{kind: 'lose-reply', method: 'POST', pathname: '/k/v1/records.json'}]}),
    source = await f.load(), ledger = f.ledger();
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), error => {
    assert.equal(error.outcome, 'unknown');assert.equal(error.code, 'ECONNRESET');return true;
  });
  assert.equal(f.tls.seen().length, 2);assert.equal(f.state.resolutions, 2);
  assertReleased(ledger);
});

test('kintone guest route and same-Site identity are selected before any request', async t => {
  const f = await fixture(t, {guestSpaceId: '15'}), initial = await f.identity();
  const source = await f.load(), ledger = f.ledger();
  f.state.page = () => ({records: [], totalCount: null});
  const opened = await source.openCapture({...await f.prepare(source), ledger});f.captures.push(opened);
  assert(f.tls.seen().every(value => value.pathname.startsWith('/k/guest/15/v1/')));
  await opened.close();assertReleased(ledger);
  await writeFile(f.sitePath, JSON.stringify({...f.site, siteGeneration: 2}));
  assert.notEqual(await f.identity(), initial);
});

test('foreign App metadata and missing typed runtime refuse before key entry or provider lookup', async t => {
  const f = await fixture(t);
  await writeFile(f.metadataPath, JSON.stringify({...f.metadata, appId: '13'}));
  await assert.rejects(f.load(), installedFailureCode('InvalidInstalledKintoneMetadata'));
  await writeFile(f.metadataPath, JSON.stringify(f.metadata));
  await writeFile(f.sitePath, JSON.stringify({...f.site, credentialPrivateKeyPath: f.site.credentialPrivateKeyPath + '.missing'}));
  await assert.rejects(f.load({...common, clientProgramKintoneBorrowRead: undefined}), installedFailureCode('KintoneOriginalReadUnavailable'));
  assert.equal(f.tls.seen().length, 0);assert.equal(f.state.resolutions, 0);
});

test('a rejected kintone response is charged on the original RowRun without another request', async t => {
  const rejected = {code: 'CB_NO02', message: 'Permission denied.'};
  const f = await fixture(t, {faults: [{kind: 'reply', method: 'POST',
    pathname: '/k/v1/records.json', reply: {status: 403, body: rejected}}]}),
    source = await f.load(), ledger = f.ledger();
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'KintoneReadHttpRejected'});
  assert.equal(f.tls.seen().length, 2);assert.equal(f.state.resolutions, 2);
  assert.equal(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes, BigInt(
    f.state.responseBodies[0].byteLength + Buffer.byteLength(JSON.stringify(rejected))));
  assertReleased(ledger);
});

test('canceling an awaited kintone page retains its original reservation until transport retirement', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  let seen, resume;
  const observed = new Promise(resolve => {seen = resolve;});
  const response = new Promise(resolve => {resume = resolve;});
  f.state.page = async () => {seen();await response;return {records: [], totalCount: null};};
  const controller = new AbortController();
  const opening = source.openCapture({...await f.prepare(source), ledger, signal: controller.signal});
  const rejected = assert.rejects(opening, error => {
    assert.equal(error.code, 'ABORT_ERR');assert.equal(error.outcome, 'unknown');return true;
  });
  await observed;
  assert.ok(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).reservedExecutionBytes > 0n);
  controller.abort();resume();
  await rejected;
  assert.equal(f.tls.seen().length, 2);assert.equal(f.state.resolutions, 2);
  assertReleased(ledger);
});
