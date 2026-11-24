import {installedFailureCode} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import https from 'node:https';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import type {ClientRequest} from 'node:http';

import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledKintoneSource} from '../host/installed-kintone-source.mjs';
import {installedKintoneFixture as fixture, originalForm, record} from './installed-kintone.fixture.mjs';

import type {KintoneInstalledSource} from '../host/installed-kintone-source.mjs';

type Runtime = Parameters<Awaited<ReturnType<typeof fixture>>['load']>[0] & Readonly<{
  clientProgramMultiCapturedLedgerUsage(ledger: unknown): Parameters<typeof ledgerUsageSnapshot>[0];
  clientProgramExportSourceCapture(source: unknown, requirement: unknown, input: string): unknown;
  clientProgramSourceCaptureExportRows(value: unknown): string[];
  clientProgramKintoneProjectForm(body: Uint8Array, app: string, limits: unknown): Readonly<{$tag: number; _0: unknown}>;
  clientProgramKintoneFormLimits(bytes: number, nodes: number, depth: number, fields: number, names: number): unknown;
}>;
type FixtureSource = Awaited<ReturnType<Awaited<ReturnType<typeof fixture>>['load']>>;
type Capture = Awaited<ReturnType<FixtureSource['openCapture']>>;
type AcquisitionError = Readonly<{code?: unknown; outcome?: unknown; recovery?: unknown; cause?: unknown}>;
type InstallationError = Readonly<{primaryFailure?: {cause?: unknown}; cleanupPending?: unknown; cleanupErrors?: unknown}>;
const common = await import(new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href) as Runtime;

const assertReleased = (ledger: unknown) => assert.deepEqual(
  ledgerUsageFieldsFor(common.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);

type TransportObservation = {requestClosed: boolean; socketClosed: boolean; responseObserved: boolean; failure?: Error};

function observeOriginalRecordsRequest(origin: string) {
  const originalRequest = https.request;
  const host = new URL(origin).host;
  const records: TransportObservation[] = [];
  https.request = function (this: typeof https, ...args: unknown[]): ClientRequest {
    const request: ClientRequest = Reflect.apply(originalRequest, this, args);
    if (request.getHeader('host') !== host || request.method !== 'POST' || request.path !== '/k/v1/records.json') {
      return request;
    }
    const observed: TransportObservation = {requestClosed: false, socketClosed: false, responseObserved: false};
    records.push(observed);
    request.once('error', error => {observed.failure = error;});
    request.once('close', () => {observed.requestClosed = true;});
    request.once('socket', socket => socket.once('close', () => {observed.socketClosed = true;}));
    request.once('response', () => {observed.responseObserved = true;});
    return request;
  } as typeof https.request;
  syncBuiltinESMExports();
  return {
    records,
    restore() {
      https.request = originalRequest;
      syncBuiltinESMExports();
    },
  };
}

function assertStoppedWithoutResponse(error: AcquisitionError, code: string, records: readonly TransportObservation[]) {
  assert.equal(error.code, code);
  assert.equal(error.outcome, 'stopped');
  assert.equal(error.recovery, undefined);
  assert.equal(records.length, 1);
  const [original] = records;
  assert.equal(original.requestClosed, true);
  assert.equal(original.socketClosed, true);
  assert.equal(original.responseObserved, false);
  assert.ok(original.failure instanceof Error);
  const causes: unknown[] = [];
  let cause = error.cause;
  while (cause !== undefined && !causes.includes(cause) && causes.length < 6) {
    causes.push(cause);
    cause = (cause as AcquisitionError | null)?.cause;
  }
  assert.ok(causes.includes(original.failure), 'retain the original transport error in the cause chain');
  return true;
}

function assertOriginalCredentialOutcomes(journalRoot: string) {
  const database = new DatabaseSync(join(journalRoot, 'credential-journal.sqlite3'), {readOnly: true});
  try {
    const rows = database.prepare(`
      SELECT json_extract(grant_json, '$.operation') AS operation, outcome
      FROM credential_uses JOIN credential_grants USING (grant_cid)
      ORDER BY credential_uses.rowid
    `).all();
    // Credential journal outcome 1 is Succeeded and 3 is Unknown.
    assert.deepEqual(rows.map(row => [row.operation, row.outcome]),
      [['kintone:form:read', 1], ['kintone:records:read', 3]]);
  } finally {
    database.close();
  }
}

test('installed kintone prepares original typed metadata without provider or secret lookup', async t => {
  const f = await fixture(t), source = await f.load();
  assert.equal(source.connectorRegistration, 'kintone');
  assert.deepEqual(source.sourceReadAccesses!.map(value => value.resource), ['inquiries']);
  await source.prepare(await f.prepare(source));
  assert.equal(f.tls.seen().length, 0);assert.equal(f.state.resolutions, 0);
});

test('installed kintone pages the same accounted RowRun with original wide ID and separate App record number', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  const opened = await source.openCapture({...await f.prepare(source), ledger});f.captures.push(opened);
  const exported = checked(common.clientProgramExportSourceCapture(opened.capture.source(),
    (opened as Extract<Capture, {requirement: unknown}>).requirement, 'kintone-record-read-test'));
  const rows = common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse as (wire: string) => unknown);
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
  for (const options of [{formRead: 'deny'}, {recordsRead: 'deny'}] as const) {
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
  f.state.form = (count: number) => count === 2 ? {...originalForm, revision: '8'} : originalForm;
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'MoonBitHostFailure'});
  assert.equal(f.tls.seen().length, 3);assert.equal(f.state.forms, 2);
  assert.equal(ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes,
    BigInt(f.state.responseBodies.reduce((sum, value) => sum + value.byteLength, 0)));
  assertReleased(ledger);
});

test('kintone repeated cross-page IDs abort instead of treating totalCount as completion', async t => {
  const f = await fixture(t), source = await f.load(), ledger = f.ledger();
  f.state.page = (count: number) => ({records: count === 1
    ? [record('9007199254740992'), record('9007199254740993')]
    : [record('9007199254740993')], totalCount: '1'});
  await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.pages, 2);assert.equal(f.tls.seen().length, 4);
  assertReleased(ledger);
});

test('a kintone reply loss stops the transport and retains the one original Unknown use', async t => {
  const f = await fixture(t, {faults: [{kind: 'lose-reply', method: 'POST', pathname: '/k/v1/records.json'}]}),
    source = await f.load(), ledger = f.ledger();
  const transport = observeOriginalRecordsRequest(f.tls.origin);
  try {
    await assert.rejects(source.openCapture({...await f.prepare(source), ledger}), error =>
      assertStoppedWithoutResponse(error as AcquisitionError, 'ECONNRESET', transport.records));
  } finally {
    transport.restore();
  }
  assert.deepEqual(f.tls.seen().map(({method, pathname}) => [method, pathname]),
    [['POST', '/k/v1/app/form/fields.json'], ['POST', '/k/v1/records.json']]);
  assert.equal(f.state.resolutions, 2);
  assertOriginalCredentialOutcomes(f.site.journalRoot);
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
  await assert.rejects(f.load({...common, clientProgramKintoneManagedFormRequest: undefined}), installedFailureCode('KintoneOriginalReadUnavailable'));
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
  let seen: () => void, resume: () => void;
  const observed = new Promise<void>(resolve => {seen = resolve;});
  const response = new Promise<void>(resolve => {resume = resolve;});
  f.state.page = async () => {seen();await response;return {records: [], totalCount: null};};
  const controller = new AbortController();
  const transport = observeOriginalRecordsRequest(f.tls.origin);
  try {
    const opening = source.openCapture({...await f.prepare(source), ledger, signal: controller.signal});
    const rejected = assert.rejects(opening, error =>
      assertStoppedWithoutResponse(error as AcquisitionError, 'ABORT_ERR', transport.records));
    await observed;
    const [original] = transport.records;
    const pendingAtCancel = original !== undefined && !original.requestClosed && !original.socketClosed && !original.responseObserved;
    const reservedBeforeClose = ledgerUsageSnapshot(common.clientProgramMultiCapturedLedgerUsage(ledger)).reservedExecutionBytes;
    controller.abort();resume!();
    await rejected;
    assert.equal(pendingAtCancel, true);
    assert.ok(reservedBeforeClose > 0n);
  } finally {
    transport.restore();
  }
  assert.deepEqual(f.tls.seen().map(({method, pathname}) => [method, pathname]),
    [['POST', '/k/v1/app/form/fields.json'], ['POST', '/k/v1/records.json']]);
  assert.equal(f.state.resolutions, 2);
  assertOriginalCredentialOutcomes(f.site.journalRoot);
  assertReleased(ledger);
});

test('kintone loader without its original initializer never enters raw configuration fallback',async()=>{
  await assert.rejects(loadInstalledKintoneSource({metadataPath:'/UNOPENED-original-metadata'},{} as Parameters<typeof loadInstalledKintoneSource>[1]),
    {code:'KintoneSourceConstructionUnavailable'});
});

test('registered kintone native Form refusal retains the original typed cause and initial cleanup',async t=>{
  const f=await fixture(t);
  const bytes=Buffer.from('{}');
  await writeFile(f.metadataPath,JSON.stringify({...f.metadata,formBody:bytes.toString('base64')}));
  const limits=f.profile.limits satisfies KintoneInstalledSource['limits'];
  const expected=common.clientProgramKintoneProjectForm(bytes,f.profile.appId,
    common.clientProgramKintoneFormLimits(limits.maxResponseBytes,limits.maxNodes,limits.maxDepth,limits.maxFields,limits.maxNameUnits));
  assert.equal(expected.$tag,0);
  await assert.rejects(f.load(),cause=>{
    assert.deepEqual((cause as InstallationError).primaryFailure?.cause,expected._0);assert.equal((cause as InstallationError).cleanupPending,false);
    assert.deepEqual((cause as InstallationError).cleanupErrors,[]);return true;
  });
  assert.equal(f.tls.seen().length,0);assert.equal(f.state.resolutions,0);
});
